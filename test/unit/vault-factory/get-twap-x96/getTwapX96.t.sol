// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {NFTXVaultUpgradeableV3} from "@src/NFTXVaultUpgradeableV3.sol";
import {FullMath} from "@uni-core/libraries/FullMath.sol";
import {FixedPoint96} from "@uni-core/libraries/FixedPoint96.sol";
import {MockNFT} from "@mocks/MockNFT.sol";
import {INFTXRouter} from "@src/NFTXRouter.sol";

import {NFTXVaultFactory_Unit_Test} from "../NFTXVaultFactory.t.sol";

contract getTwapX96_Unit_Test is NFTXVaultFactory_Unit_Test {
    NFTXVaultUpgradeableV3 vault;
    address pool;

    function setUp() public virtual override {
        super.setUp();

        (, vault) = deployVToken721(vaultFactory);
    }

    function test_GivenThePoolWasJustDeployed() external {
        pool = mintLiquidityPosition({
            currentNFTPrice: 5 ether,
            lowerNFTPrice: 3 ether,
            upperNFTPrice: 7 ether
        });

        // for same block, twapX96A will be zero
        uint256 twapX96 = vaultFactory.getTwapX96(pool);
        assertEq(twapX96, 0);
    }

    // twap should get set instantly from the next second
    modifier givenThePoolWasDeployedLessThanTwapIntervalAgo(
        uint256 currentNFTPrice,
        uint256 warpBy
    ) {
        pool = mintLiquidityPosition(currentNFTPrice);
        vm.assume(warpBy > 0 && warpBy < vaultFactory.twapInterval());
        vm.warp(block.timestamp + warpBy);
        _;
    }

    function test_GivenThePoolHadNoTransactionsA(
        uint256 currentNFTPrice,
        uint256 warpBy
    )
        external
        givenThePoolWasDeployedLessThanTwapIntervalAgo(currentNFTPrice, warpBy)
    {
        // it should return the twap of initial price for time period since the pool was deployed
        assertTwapX96(currentNFTPrice);
    }

    function test_GivenThePoolHadAddLiquidityTransactionA(
        uint256 currentNFTPrice,
        uint256 warpBy
    )
        external
        givenThePoolWasDeployedLessThanTwapIntervalAgo(currentNFTPrice, warpBy)
    {
        // have new add liquidity transaction after pool was deployed (this should not change the pool price)
        mintLiquidityPosition({
            currentNFTPrice: 5 ether,
            lowerNFTPrice: 3 ether,
            upperNFTPrice: 7 ether
        });

        // it should return the twap of initial price for time period since the pool was deployed
        assertTwapX96(currentNFTPrice);
    }

    modifier givenThePoolWasDeployedMoreThanTwapIntervalAgo(
        uint256 currentNFTPrice,
        uint256 warpBy
    ) {
        pool = mintLiquidityPosition(currentNFTPrice);

        // vm.warp doesn't work as expected for very large values
        vm.assume(warpBy >= vaultFactory.twapInterval() && warpBy <= 365 days);
        vm.warp(block.timestamp + warpBy);
        _;
    }

    function test_GivenThePoolHadNoTransactionsB(
        uint256 currentNFTPrice,
        uint256 warpBy
    )
        external
        givenThePoolWasDeployedMoreThanTwapIntervalAgo(currentNFTPrice, warpBy)
    {
        // it should return the twap of initial price for twap interval
        assertTwapX96(currentNFTPrice);
    }

    function test_GivenThePoolHadAddLiquidityTransactionB(
        uint256 currentNFTPrice,
        uint256 warpBy
    )
        external
        givenThePoolWasDeployedMoreThanTwapIntervalAgo(currentNFTPrice, warpBy)
    {
        // it should return the twap of initial price for twap interval
        assertTwapX96(currentNFTPrice);
    }

    // helpers

    function mintLiquidityPosition(
        uint256 currentNFTPrice
    ) internal returns (address _pool) {
        // currentNFTPrice has to be min 10 wei to avoid lowerNFTPrice from being zero
        vm.assume(
            currentNFTPrice >= 10 wei && currentNFTPrice <= type(uint64).max
        );

        uint256 lowerNFTPrice = (currentNFTPrice * 95) / 100;
        uint256 upperNFTPrice = (currentNFTPrice * 105) / 100;

        return
            mintLiquidityPosition(
                currentNFTPrice,
                lowerNFTPrice,
                upperNFTPrice
            );
    }

    function mintLiquidityPosition(
        uint256 currentNFTPrice,
        uint256 lowerNFTPrice,
        uint256 upperNFTPrice
    ) internal returns (address _pool) {
        mintLiquidityPosition({
            qty: 5,
            currentNFTPrice: currentNFTPrice,
            lowerNFTPrice: lowerNFTPrice,
            upperNFTPrice: upperNFTPrice,
            feeTier: DEFAULT_FEE_TIER
        });
        _pool = nftxRouter.getPool(address(vault), DEFAULT_FEE_TIER);
    }

    function mintLiquidityPosition(
        uint256 qty,
        uint256 currentNFTPrice,
        uint256 lowerNFTPrice,
        uint256 upperNFTPrice,
        uint24 feeTier
    )
        internal
        returns (
            uint256[] memory nftIdsDeposited,
            uint256 positionId,
            int24 tickLower,
            int24 tickUpper,
            uint256 ethUsed
        )
    {
        MockNFT nft = MockNFT(vault.assetAddress());
        nftIdsDeposited = nft.mint(qty);
        nft.setApprovalForAll(address(nftxRouter), true);

        uint256 tickDistance = getTickDistance(nftxRouter, feeTier);
        uint160 currentSqrtPriceX96;
        (currentSqrtPriceX96, tickLower, tickUpper) = getTicks(
            nftxRouter.isVToken0(address(vault)),
            tickDistance,
            currentNFTPrice,
            lowerNFTPrice,
            upperNFTPrice
        );

        uint256 preETHBalance = address(this).balance;

        positionId = nftxRouter.addLiquidity{value: qty * 100 ether}(
            INFTXRouter.AddLiquidityParams({
                vaultId: vault.vaultId(),
                vTokensAmount: 0,
                nftIds: nftIdsDeposited,
                nftAmounts: emptyAmounts,
                tickLower: tickLower,
                tickUpper: tickUpper,
                fee: feeTier,
                sqrtPriceX96: currentSqrtPriceX96,
                vTokenMin: 0,
                wethMin: 0,
                deadline: block.timestamp,
                forceTimelock: false,
                recipient: address(this)
            })
        );

        ethUsed = preETHBalance - address(this).balance;
    }

    function getPrice(uint256 twapX96) internal view returns (uint256 price) {
        if (nftxRouter.isVToken0(address(vault))) {
            price = FullMath.mulDiv(1 ether, twapX96, FixedPoint96.Q96);
        } else {
            price = FullMath.mulDiv(1 ether, FixedPoint96.Q96, twapX96);
        }
    }

    function assertTwapX96(uint256 currentNFTPrice) internal {
        uint256 twapX96 = vaultFactory.getTwapX96(pool);
        assertGt(twapX96, 0, "twapX96A == 0");

        uint256 price = getPrice(twapX96);
        assertGt(price, 0);
        assertGe(
            price,
            valueWithError({value: currentNFTPrice, errorBps: 10}),
            "!price"
        );
    }
}
