// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";
import {Helpers} from "./lib/Helpers.sol";
import {TestExtend} from "./lib/TestExtend.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import {UniswapV3Factory} from "@uni-core/UniswapV3Factory.sol";
import {UniswapV3Pool} from "@uni-core/UniswapV3Pool.sol";
import {NonfungibleTokenPositionDescriptor} from "@uni-periphery/NonfungibleTokenPositionDescriptor.sol";
import {NonfungiblePositionManager, INonfungiblePositionManager} from "@uni-periphery/NonfungiblePositionManager.sol";
import {SwapRouter} from "@uni-periphery/SwapRouter.sol";
import {QuoterV2} from "@uni-periphery/lens/QuoterV2.sol";
import {TickMath} from "@uni-core/libraries/TickMath.sol";
import {FullMath} from "@uni-core/libraries/FullMath.sol";
import {FixedPoint128} from "@uni-core/libraries/FixedPoint128.sol";

import {MockWETH} from "@mocks/MockWETH.sol";
import {MockNFT} from "@mocks/MockNFT.sol";
import {vToken} from "@mocks/vToken.sol";
import {MockFeeDistributor} from "@mocks/MockFeeDistributor.sol";
import {MockVaultFactory} from "@mocks/MockVaultFactory.sol";

import {INFTXVaultFactory} from "@src/v2/interface/INFTXVaultFactory.sol";
import {NFTXRouter, INFTXRouter} from "@src/NFTXRouter.sol";

contract NFTXFeeDistributorV3Tests is TestExtend, ERC721Holder {
    UniswapV3Factory factory;
    NonfungibleTokenPositionDescriptor descriptor;
    MockWETH weth;
    NonfungiblePositionManager positionManager;
    SwapRouter router;
    QuoterV2 quoter;

    MockNFT nft;
    vToken vtoken;
    // TODO: replace with NFTXFeeDistributorV3
    MockFeeDistributor feeDistributor;
    // TODO: replace with NFTXVaultFactory
    MockVaultFactory vaultFactory;
    NFTXRouter nftxRouter;

    // TODO: remove this and add tests for different fee tiers
    uint24 constant DEFAULT_FEE_TIER = 10000;

    function setUp() external {
        weth = new MockWETH();

        factory = new UniswapV3Factory();
        descriptor = new NonfungibleTokenPositionDescriptor(
            address(weth),
            bytes32(0)
        );

        positionManager = new NonfungiblePositionManager(
            address(factory),
            address(weth),
            address(descriptor)
        );
        router = new SwapRouter(address(factory), address(weth));
        quoter = new QuoterV2(address(factory), address(weth));

        nft = new MockNFT();
        vtoken = new vToken(nft);
        vaultFactory = new MockVaultFactory();
        vaultFactory.addVault(address(vtoken));
        nftxRouter = new NFTXRouter(
            positionManager,
            router,
            quoter,
            INFTXVaultFactory(address(vaultFactory))
        );

        feeDistributor = new MockFeeDistributor(nftxRouter, vtoken);
        factory.setFeeDistributor(address(feeDistributor));
    }

    // UniswapV3Factory#setFeeDistributor

    function test_setFeeDistributor_RevertsForNonOwner() external {
        hoax(makeAddr("nonOwner"));
        vm.expectRevert();
        factory.setFeeDistributor(address(feeDistributor));
    }

    function test_setFeeDistributor_Success() external {
        address newFeeDistributor = makeAddr("newFeeDistributor");
        factory.setFeeDistributor(newFeeDistributor);
        assertEq(factory.feeDistributor(), newFeeDistributor);
    }

    // UniswapV3Pool#distributeRewards
    function test_distributeRewards_RevertsForNonFeeDistributor() external {
        // minting so that Pool is deployed
        _mintPosition(1);
        UniswapV3Pool pool = UniswapV3Pool(
            nftxRouter.getPool(address(vtoken), DEFAULT_FEE_TIER)
        );

        hoax(makeAddr("nonFeeDistributor"));
        vm.expectRevert();
        pool.distributeRewards(1 ether, true);
    }

    // FeeDistributor#distribute

    function test_feeDistribution_Success() external {
        uint256 mintQty = 5;

        // mint position
        (
            uint256[] memory mintTokenIds,
            uint256 positionId, // uint256 ethDeposited
            ,
            ,

        ) = _mintPosition(mintQty);
        // have another position, so that the pool doesn't have 0 liquidity to facilitate swapping fractional vTokens during removeLiquidity
        _mintPosition(mintQty);
        // TODO: add console logs for initial values as well, in all test cases

        uint256 wethFees = 2 ether;

        // distribute fees
        weth.deposit{value: wethFees}();
        weth.transfer(address(feeDistributor), wethFees);
        feeDistributor.distribute(0);

        // NOTE: We have 2 LP positions with the exact same liquidity. So the fees is distributed equally between them both
        // So for wethFees = 2, each position should get 1 weth as fees, but due to rounding gets 0.999..999 of weth as fees

        // Findings: On liquidity withdrawal 1 wei gets left in the pool as well.
        // So 1 wei of distributed weth and 1 wei from initial provided liquidity gets stuck in the pool (for a total of 2 wei)

        (, uint256 _wethFees) = _getAccumulatedFees(positionId);
        console.log("_wethFees", _wethFees);
        assertGe(_wethFees, wethFees / 2 - 1);

        // remove liquidity
        uint256[] memory nftIds = new uint256[](mintQty - 1); // accounting for that 1 wei difference allows us to redeem 1 less NFT
        nftIds[0] = mintTokenIds[0];
        nftIds[1] = mintTokenIds[1];
        nftIds[2] = mintTokenIds[2];
        nftIds[3] = mintTokenIds[3];
        // nftIds[4] = mintTokenIds[4];

        uint128 liquidity = _getLiquidity(positionId);

        uint256 preNFTBalance = nft.balanceOf(address(this));
        uint256 preETHBalance = address(this).balance;

        positionManager.setApprovalForAll(address(nftxRouter), true);
        nftxRouter.removeLiquidity(
            INFTXRouter.RemoveLiquidityParams({
                positionId: positionId,
                vtoken: address(vtoken),
                nftIds: nftIds,
                receiveVTokens: false,
                liquidity: liquidity,
                swapPoolFee: 10000,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        uint256 nftReceived = nft.balanceOf(address(this)) - preNFTBalance;
        uint256 ethReceived = address(this).balance - preETHBalance;

        console.log("NFT received", nftReceived);
        // ethReceived = ethDeposited + _wethFees + swapped 0.9999..99 vToken into ETH
        console.log("ETH received", ethReceived);
    }

    function _mintPosition(
        uint256 qty
    )
        internal
        returns (
            uint256[] memory tokenIds,
            uint256 positionId,
            int24 tickLower,
            int24 tickUpper,
            uint256 ethUsed
        )
    {
        // Current Eg: 1 NFT = 5 ETH, and liquidity provided in the range: 3-6 ETH per NFT
        uint256 currentNFTPrice = 5 ether; // 5 * 10^18 wei for 1*10^18 vTokens
        uint256 lowerNFTPrice = 3 ether;
        uint256 upperNFTPrice = 6 ether;
        uint24 fee = 10000;

        return
            _mintPosition(
                qty,
                currentNFTPrice,
                lowerNFTPrice,
                upperNFTPrice,
                fee
            );
    }

    function _mintPosition(
        uint256 qty,
        uint256 currentNFTPrice,
        uint256 lowerNFTPrice,
        uint256 upperNFTPrice,
        uint24 fee
    )
        internal
        returns (
            uint256[] memory tokenIds,
            uint256 positionId,
            int24 tickLower,
            int24 tickUpper,
            uint256 ethUsed
        )
    {
        tokenIds = nft.mint(qty);
        nft.setApprovalForAll(address(vtoken), true);

        uint160 currentSqrtP;
        uint256 tickDistance = _getTickDistance(fee);
        if (nftxRouter.isVToken0(address(vtoken))) {
            currentSqrtP = Helpers.encodeSqrtRatioX96(currentNFTPrice, 1 ether);
            // price = amount1 / amount0 = 1.0001^tick => tick ∝ price
            tickLower = Helpers.getTickForAmounts(
                lowerNFTPrice,
                1 ether,
                tickDistance
            );
            tickUpper = Helpers.getTickForAmounts(
                upperNFTPrice,
                1 ether,
                tickDistance
            );
        } else {
            currentSqrtP = Helpers.encodeSqrtRatioX96(1 ether, currentNFTPrice);
            tickLower = Helpers.getTickForAmounts(
                1 ether,
                upperNFTPrice,
                tickDistance
            );
            tickUpper = Helpers.getTickForAmounts(
                1 ether,
                lowerNFTPrice,
                tickDistance
            );
        }

        uint256 preETHBalance = address(this).balance;

        positionId = nftxRouter.addLiquidity{value: qty * 100 ether}(
            INFTXRouter.AddLiquidityParams({
                vtoken: address(vtoken),
                vTokensAmount: 0,
                nftIds: tokenIds,
                tickLower: tickLower,
                tickUpper: tickUpper,
                fee: fee,
                sqrtPriceX96: currentSqrtP,
                deadline: block.timestamp
            })
        );

        ethUsed = preETHBalance - address(this).balance;
    }

    function _getTickDistance(
        uint24 fee
    ) internal view returns (uint256 tickDistance) {
        tickDistance = uint256(uint24(factory.feeAmountTickSpacing(fee)));
    }

    function _getLiquidity(
        uint256 positionId
    ) internal view returns (uint128 liquidity) {
        (, , , , , , , liquidity, , , , ) = positionManager.positions(
            positionId
        );
    }

    function _getAccumulatedFees(
        uint256 positionId
    ) internal returns (uint256 vTokenFees, uint256 wethFees) {
        // "simulating" call here. Similar to "callStatic" in ethers.js for executing non-view function to just get return values.
        uint256 snapshot = vm.snapshot();
        (uint256 amount0, uint256 amount1) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: positionId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        vm.revertTo(snapshot);

        (vTokenFees, wethFees) = nftxRouter.isVToken0(address(vtoken))
            ? (amount0, amount1)
            : (amount1, amount0);
    }

    // to receive the refunded ETH
    receive() external payable {}
}
