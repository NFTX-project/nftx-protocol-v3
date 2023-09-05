library TickHelpers {
    function encodeSqrtRatioX96(uint256 amount1, uint256 amount0) internal pure returns (uint160 sqrtP) {
        sqrtP = SafeCast.toUint160(Babylonian.sqrt((amount1 << 192) / amount0));
    }
    function getTickForAmounts(uint256 amount1, uint256 amount0, uint256 tickDistance) internal pure returns (int24 tick) {
        uint160 sqrtP = encodeSqrtRatioX96(amount1, amount0);
        int24 tempTick = TickMath.getTickAtSqrtRatio(sqrtP); // this might not be in the tickDistance
        uint256 unsignedTempTick = tempTick < 0
            ? uint256(uint24(-tempTick))
            : uint256(uint24(tempTick));
        uint256 unsignedTick = FullMath.mulDivRoundingUp(
            unsignedTempTick,
            1,
            tickDistance
        ) * tickDistance;

        tick = int24(uint24(unsignedTick));
        if (tempTick < 0) {
            tick = -tick;
        }
    }
}
