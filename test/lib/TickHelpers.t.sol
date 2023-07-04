// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {Babylonian} from "@uniswap/lib/contracts/libraries/Babylonian.sol";
import {SafeCast} from "@uni-core/libraries/SafeCast.sol";
import {TickMath} from "@uni-core/libraries/TickMath.sol";
import {FullMath} from "@uni-core/libraries/FullMath.sol";

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/Test.sol";

contract TickHelpersTest is Test {
    function testIntermediateValues() external view {
        uint256 amount1 = 500000000000000;
        uint256 amount0 = 1000000000000000000;
        uint256 tickDistance = 200;

        // getTickForAmounts
        uint160 sqrtP = encodeSqrtRatioX96(amount1, amount0);
        int24 tempTick = TickMath.getTickAtSqrtRatio(sqrtP); // this might not be in the tickDistance

        uint256 unsignedTempTick = tempTick < 0
            ? uint256(uint24(-tempTick))
            : uint256(uint24(tempTick));
        // calculating the closest next tick: ceil(tempTick / tickDistance) * tickDistance;
        uint256 unsignedTick = FullMath.mulDivRoundingUp(
            unsignedTempTick,
            1,
            tickDistance
        ) * tickDistance;

        // cast to int24 & add back the sign
        int24 tick = int24(uint24(unsignedTick));
        if (tempTick < 0) {
            tick = -tick;
        }

        console.log("sqrtP", uint256(sqrtP));
        console.logInt(int256(tempTick));
        console.log("unsignedTempTick", unsignedTempTick);
        console.log("unsignedTick", unsignedTick);
        console.logInt(int256(tick));
    }

    // internal

    function encodeSqrtRatioX96(
        uint256 amount1,
        uint256 amount0
    ) internal pure returns (uint160 sqrtP) {
        // sqrtP = sqrt(price) * 2^96
        // = sqrt(amount1 / amount0) * 2^96
        // = sqrt(amount1 * 2^192 / amount0)

        sqrtP = SafeCast.toUint160(Babylonian.sqrt((amount1 << 192) / amount0));
    }
}
