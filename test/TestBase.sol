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

contract TestBase is TestExtend, ERC721Holder {
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
        // TODO: add tests for different fee tiers
        uint24 fee = DEFAULT_FEE_TIER;

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

    function _sellNFTs(
        uint256 qty
    ) internal returns (uint256[] memory tokenIds) {
        tokenIds = nft.mint(qty);
        nft.setApprovalForAll(address(vtoken), true);

        uint256 preNFTBalance = nft.balanceOf(address(this));

        nftxRouter.sellNFTs(
            INFTXRouter.SellNFTsParams({
                vtoken: address(vtoken),
                nftIds: tokenIds,
                deadline: block.timestamp,
                fee: DEFAULT_FEE_TIER,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 postNFTBalance = nft.balanceOf(address(this));
        assertEq(
            preNFTBalance - postNFTBalance,
            qty,
            "NFT balance didn't decrease"
        );
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
