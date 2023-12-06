// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";
import {TickHelpers} from "@src/lib/TickHelpers.sol";

import {INFTXRouter} from "@src/NFTXRouter.sol";
import {ISwapRouter, SwapRouter} from "@uni-periphery/SwapRouter.sol";
import {INonfungiblePositionManager} from "@uni-periphery/interfaces/INonfungiblePositionManager.sol";

import {MockERC20} from "@src/mocks/MockERC20.sol";

import {TestBase} from "@test/TestBase.sol";

// add same $ liquidity in various % around current price: 25%, 50%, 75%
// swap same $ amount across these positions
// return gas consumed in each
// do this for 0.3, 1 and 3% pools

contract SpreadVsGas is TestBase {
    uint256 vTokenAddLiqAmount = 10 ether;
    uint256 ethAddLiqAmount = 100 ether;

    uint256 vTokenAmtToBuy = 5 ether;
    uint256 maxEthAmtToSell = 100 ether;

    uint256 currentPrice = 1 ether;

    MockERC20 token;

    bool isVToken0;
    address token0;
    address token1;

    uint24[] feeTiers = [3_000, 10_000, 30_000];
    uint256[] percentRanges = [75, 50, 25];

    // internal, so that it doesn't run the first time
    function _reset() internal {
        super.setUp();

        token = new MockERC20(1_000_000 ether);
        token.approve(address(positionManager), type(uint256).max);

        isVToken0 = address(token) < address(weth);
        token0 = isVToken0 ? address(token) : address(weth);
        token1 = isVToken0 ? address(weth) : address(token);
    }

    function test_SpreadVsGas() external {
        for (uint256 i = 0; i < feeTiers.length; i++) {
            uint24 feeTier = feeTiers[i];

            console.log("For feeTier %s:", uint256(feeTier));
            for (uint256 j = 0; j < percentRanges.length; j++) {
                uint256 percentRange = percentRanges[j];

                // reset state
                _reset();

                _addLiq(percentRange, feeTier);
                uint256 gasUsed = _buyVToken(feeTier);

                console.log("");
                console.log("percentRange", percentRange);
                console.log("gasUsed", gasUsed);
            }
            console.log("==========================");
        }
    }

    function _addLiq(uint256 percentRange, uint24 feeTier) internal {
        (
            int24 tickLower,
            int24 tickUpper,
            uint160 currentSqrtPriceX96
        ) = _getTicks(
                currentPrice,
                (currentPrice * (100 - percentRange)) / 100,
                (currentPrice * (100 + percentRange)) / 100,
                feeTier
            );

        (uint256 amount0Desired, uint256 amount1Desired) = isVToken0
            ? (vTokenAddLiqAmount, ethAddLiqAmount)
            : (ethAddLiqAmount, vTokenAddLiqAmount);

        positionManager.createAndInitializePoolIfNecessary(
            token0,
            token1,
            feeTier,
            currentSqrtPriceX96
        );
        positionManager.mint{value: ethAddLiqAmount}(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: feeTier,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 1
            })
        );
    }

    function _buyVToken(uint24 feeTier) internal returns (uint256 gasUsed) {
        uint256 gasStart = gasleft();

        weth.deposit{value: maxEthAmtToSell}();
        weth.approve(address(router), type(uint256).max);
        router.exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(token),
                fee: feeTier,
                recipient: address(this),
                deadline: block.timestamp + 1,
                amountOut: vTokenAmtToBuy,
                amountInMaximum: maxEthAmtToSell,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 gasEnd = gasleft();
        gasUsed = gasStart - gasEnd;
    }

    function _getTicks(
        uint256 currentNFTPriceInETH,
        uint256 lowerNFTPriceInETH,
        uint256 upperNFTPriceInETH,
        uint24 fee
    )
        internal
        view
        returns (int24 tickLower, int24 tickUpper, uint160 currentSqrtPriceX96)
    {
        uint256 tickDistance = uint24(factory.feeAmountTickSpacing(fee));
        if (isVToken0) {
            currentSqrtPriceX96 = TickHelpers.encodeSqrtRatioX96(
                currentNFTPriceInETH,
                1 ether
            );
            // price = amount1 / amount0 = 1.0001^tick => tick ∝ price
            tickLower = TickHelpers.getTickForAmounts(
                lowerNFTPriceInETH,
                1 ether,
                tickDistance
            );
            tickUpper = TickHelpers.getTickForAmounts(
                upperNFTPriceInETH,
                1 ether,
                tickDistance
            );
        } else {
            currentSqrtPriceX96 = TickHelpers.encodeSqrtRatioX96(
                1 ether,
                currentNFTPriceInETH
            );
            tickLower = TickHelpers.getTickForAmounts(
                1 ether,
                upperNFTPriceInETH,
                tickDistance
            );
            tickUpper = TickHelpers.getTickForAmounts(
                1 ether,
                lowerNFTPriceInETH,
                tickDistance
            );
        }
    }
}
