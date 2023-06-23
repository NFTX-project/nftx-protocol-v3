// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {Babylonian} from "@uniswap/lib/contracts/libraries/Babylonian.sol";
import {SafeCast} from "@uni-core/libraries/SafeCast.sol";
import {TickMath} from "@uni-core/libraries/TickMath.sol";
import {FullMath} from "@uni-core/libraries/FullMath.sol";

library TickHelpers {
    function encodeSqrtRatioX96(
        uint256 amount1,
        uint256 amount0
    ) internal pure returns (uint160 sqrtP) {
        // sqrtP = sqrt(price) * 2^96
        // = sqrt(amount1 / amount0) * 2^96
        // = sqrt(amount1 * 2^192 / amount0)

        sqrtP = SafeCast.toUint160(Babylonian.sqrt((amount1 << 192) / amount0));
    }

    function getTickForAmounts(
        uint256 amount1,
        uint256 amount0,
        uint256 tickDistance
    ) internal pure returns (int24 tick) {
        uint160 sqrtP = encodeSqrtRatioX96(amount1, amount0);
        int24 tempTick = TickMath.getTickAtSqrtRatio(sqrtP); // this might not be in the tickDistance

        uint256 unsignedTempTick = uint256(uint24(tempTick));
        // calculating the closest next tick: ceil(tempTick / tickDistance) * tickDistance;
        uint256 unsignedTick = FullMath.mulDivRoundingUp(
            unsignedTempTick,
            1,
            tickDistance
        ) * tickDistance;

        // cast to int24 & add back the sign
        tick = int24(uint24(unsignedTick));
        if (tempTick < 0) {
            tick = -tick;
        }
    }
}
