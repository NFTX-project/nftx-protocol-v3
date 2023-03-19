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
    MockFeeDistributor feeDistributor;
    NFTXRouter nftxRouter;

    uint256 tickDistance;

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
        nftxRouter = new NFTXRouter(positionManager, router, quoter);
        tickDistance = uint256(
            uint24(factory.feeAmountTickSpacing(nftxRouter.FEE()))
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
        UniswapV3Pool pool = UniswapV3Pool(nftxRouter.getPool(address(vtoken)));

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
            uint256 positionId,
            ,
            ,

        ) = _mintPosition(mintQty);
        // have another position, so that the pool doesn't have 0 liquidity to facilitate swapping fractional vTokens during removeLiquidity
        _mintPosition(mintQty);
        // TODO: add console logs for initial values as well, in all test cases

        uint256 nftFees = 4;
        uint256[] memory feeTokenIds = _mintDistributeFees(nftFees);

        // NOTE: We have 2 LP positions with the exact same liquidity. So the fees is distributed equally between them both
        // So for nftFees = 2, each position should get 1 NFT as fees, but due to rounding gets 0.999..999 of vTokens as fees
        // Hence can't redeem that portion to NFT. The fractional part would get swapped for ETH during removeLiquidity

        // Findings: On liquidity withdrawal 1 wei gets left in the pool.
        // So 1 wei of distributed vToken and 1 wei from initial provided liquidity gets stuck in the pool (for a total of 2 wei)
        // TODO: ^ this shouldn't affect vault rewards as they'll be now distributed in WETH

        (uint256 _vTokenFees, ) = _getAccumulatedFees(positionId);

        uint256 positionNFTFeesShare = nftFees / 2 - 1;

        // remove liquidity
        uint256[] memory nftIds = new uint256[](mintQty + positionNFTFeesShare);
        nftIds[0] = mintTokenIds[0];
        nftIds[1] = mintTokenIds[1];
        nftIds[2] = mintTokenIds[2];
        nftIds[3] = mintTokenIds[3];
        nftIds[4] = mintTokenIds[4];
        nftIds[5] = feeTokenIds[0];

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
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        uint256 nftReceived = nft.balanceOf(address(this)) - preNFTBalance;
        uint256 ethReceived = address(this).balance - preETHBalance;

        console.log("NFT received", nftReceived);
        console.log("ETH received", ethReceived);

        assertEq(nftReceived, mintQty + positionNFTFeesShare);
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

        return
            _mintPosition(qty, currentNFTPrice, lowerNFTPrice, upperNFTPrice);
    }

    function _mintPosition(
        uint256 qty,
        uint256 currentNFTPrice,
        uint256 lowerNFTPrice,
        uint256 upperNFTPrice
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
                nftIds: tokenIds,
                tickLower: tickLower,
                tickUpper: tickUpper,
                sqrtPriceX96: currentSqrtP,
                deadline: block.timestamp
            })
        );

        ethUsed = preETHBalance - address(this).balance;
    }

    function _getLiquidity(
        uint256 positionId
    ) internal returns (uint128 liquidity) {
        (, , , , , , , liquidity, , , , ) = positionManager.positions(
            positionId
        );
    }

    function _mintDistributeFees(
        uint256 nftFees
    ) internal returns (uint256[] memory feeTokenIds) {
        // mint vTokens for fees
        uint256 vTokenFees = nftFees * 1 ether;
        feeTokenIds = nft.mint(nftFees);

        nft.setApprovalForAll(address(vtoken), true);
        vtoken.mint(feeTokenIds, address(this), address(this));

        // distribute fees
        vtoken.transfer(address(feeDistributor), vTokenFees);
        feeDistributor.distribute(0);
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
