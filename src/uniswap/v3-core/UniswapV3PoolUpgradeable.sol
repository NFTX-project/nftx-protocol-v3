contract UniswapV3PoolUpgradeable is IUniswapV3Pool, Initializable {
    using SafeCast for uint256;
    using SafeCast for int256;
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    using Oracle for Oracle.Observation[65535];
    address public override factory;
    address public override token0;
    address public override token1;
    uint24 public override fee;
    int24 public override tickSpacing;
    uint128 public override maxLiquidityPerTick;
    struct Slot0 {
        uint160 sqrtPriceX96;
        int24 tick;
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observationCardinalityNext;
        uint8 feeProtocol;
        bool unlocked;
    }
    Slot0 public override slot0;
    uint256 public override feeGrowthGlobal0X128;
    uint256 public override feeGrowthGlobal1X128;
    struct ProtocolFees {
        uint128 token0;
        uint128 token1;
    }
    ProtocolFees public override protocolFees;
    uint128 public override liquidity;
    mapping(int24 => Tick.Info) public override ticks;
    mapping(int16 => uint256) public override tickBitmap;
    mapping(bytes32 => Position.Info) public override positions;
    Oracle.Observation[65535] public override observations;
    modifier lock() {
        if (!slot0.unlocked) revert LOK();
        slot0.unlocked = false;
        _;
        slot0.unlocked = true;
    }
    modifier onlyFactoryOwner() {
        require(msg.sender == IUniswapV3Factory(factory).owner());
        _;
    }
    function __UniswapV3PoolUpgradeable_init(address factory_, address token0_, address token1_, uint24 fee_, int24 tickSpacing_, uint16 observationCardinalityNext_) external override initializer {
        factory = factory_;
        token0 = token0_;
        token1 = token1_;
        fee = fee_;
        tickSpacing = tickSpacing_;
        maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(tickSpacing_);
        if (observationCardinalityNext_ > 0) {
            slot0.observationCardinalityNext = observations.grow(1, observationCardinalityNext_, false);
        } else {
            slot0.observationCardinalityNext = 1;
        }
    }
    function checkTicks(int24 tickLower, int24 tickUpper) private pure {
        if (tickLower >= tickUpper) revert TLU();
        if (tickLower < TickMath.MIN_TICK) revert TLM();
        if (tickUpper > TickMath.MAX_TICK) revert TUM();
    }
    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp);
    }
    function balance0() private view returns (uint256) {
        (bool success, bytes memory data) = token0.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this)));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }
    function balance1() private view returns (uint256) {
        (bool success, bytes memory data) = token1.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this)));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }
    function snapshotCumulativesInside(int24 tickLower, int24 tickUpper) external view override returns (int56 tickCumulativeInside, uint160 secondsPerLiquidityInsideX128, uint32 secondsInside) {
        checkTicks(tickLower, tickUpper);
        int56 tickCumulativeLower;
        int56 tickCumulativeUpper;
        uint160 secondsPerLiquidityOutsideLowerX128;
        uint160 secondsPerLiquidityOutsideUpperX128;
        uint32 secondsOutsideLower;
        uint32 secondsOutsideUpper;
        {
            Tick.Info storage lower = ticks[tickLower];
            Tick.Info storage upper = ticks[tickUpper];
            bool initializedLower;
            (tickCumulativeLower, secondsPerLiquidityOutsideLowerX128, secondsOutsideLower, initializedLower) = (lower.tickCumulativeOutside, lower.secondsPerLiquidityOutsideX128, lower.secondsOutside, lower.initialized);
            require(initializedLower);
            bool initializedUpper;
            (tickCumulativeUpper, secondsPerLiquidityOutsideUpperX128, secondsOutsideUpper, initializedUpper) = (upper.tickCumulativeOutside, upper.secondsPerLiquidityOutsideX128, upper.secondsOutside, upper.initialized);
            require(initializedUpper);
        }
        Slot0 memory _slot0 = slot0;
        unchecked {
            if (_slot0.tick < tickLower) {
                return (tickCumulativeLower - tickCumulativeUpper, secondsPerLiquidityOutsideLowerX128 - secondsPerLiquidityOutsideUpperX128, secondsOutsideLower - secondsOutsideUpper);
            } else if (_slot0.tick < tickUpper) {
                uint32 time = _blockTimestamp();
                (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observations.observeSingle(time, 0, _slot0.tick, _slot0.observationIndex, liquidity, _slot0.observationCardinality);
                return (tickCumulative - tickCumulativeLower - tickCumulativeUpper, secondsPerLiquidityCumulativeX128 - secondsPerLiquidityOutsideLowerX128 - secondsPerLiquidityOutsideUpperX128, time - secondsOutsideLower - secondsOutsideUpper);
            } else {
                return (tickCumulativeUpper - tickCumulativeLower, secondsPerLiquidityOutsideUpperX128 - secondsPerLiquidityOutsideLowerX128, secondsOutsideUpper - secondsOutsideLower);
            }
        }
    }
    function observe(uint32[] calldata secondsAgos) external view override returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) {
        return observations.observe(_blockTimestamp(), secondsAgos, slot0.tick, slot0.observationIndex, liquidity, slot0.observationCardinality);
    }
    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external override lock {
        uint16 observationCardinalityNextOld = slot0.observationCardinalityNext;
        uint16 observationCardinalityNextNew = observations.grow(observationCardinalityNextOld, observationCardinalityNext, true);
        slot0.observationCardinalityNext = observationCardinalityNextNew;
        if (observationCardinalityNextOld != observationCardinalityNextNew) emit IncreaseObservationCardinalityNext(observationCardinalityNextOld, observationCardinalityNextNew);
    }
    function initialize(uint160 sqrtPriceX96) external override {
        if (slot0.sqrtPriceX96 != 0) revert AI();
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        uint16 cardinality = observations.initialize(_blockTimestamp());
        slot0 = Slot0({sqrtPriceX96: sqrtPriceX96, tick: tick, observationIndex: 0, observationCardinality: cardinality, observationCardinalityNext: slot0.observationCardinalityNext, feeProtocol: 0, unlocked: true});
        emit Initialize(sqrtPriceX96, tick);
    }
    struct ModifyPositionParams {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        int128 liquidityDelta;
    }
    function _modifyPosition(ModifyPositionParams memory params) private returns (Position.Info storage position, int256 amount0, int256 amount1) {
        checkTicks(params.tickLower, params.tickUpper);
        Slot0 memory _slot0 = slot0;
        position = _updatePosition(params.owner, params.tickLower, params.tickUpper, params.liquidityDelta, _slot0.tick);
        if (params.liquidityDelta != 0) {
            if (_slot0.tick < params.tickLower) {
                amount0 = SqrtPriceMath.getAmount0Delta(TickMath.getSqrtRatioAtTick(params.tickLower), TickMath.getSqrtRatioAtTick(params.tickUpper), params.liquidityDelta);
            } else if (_slot0.tick < params.tickUpper) {
                uint128 liquidityBefore = liquidity;
                (slot0.observationIndex, slot0.observationCardinality) = observations.write(_slot0.observationIndex, _blockTimestamp(), _slot0.tick, liquidityBefore, _slot0.observationCardinality, _slot0.observationCardinalityNext);
                amount0 = SqrtPriceMath.getAmount0Delta(_slot0.sqrtPriceX96, TickMath.getSqrtRatioAtTick(params.tickUpper), params.liquidityDelta);
                amount1 = SqrtPriceMath.getAmount1Delta(TickMath.getSqrtRatioAtTick(params.tickLower), _slot0.sqrtPriceX96, params.liquidityDelta);
                liquidity = params.liquidityDelta < 0 ? liquidityBefore - uint128(-params.liquidityDelta) : liquidityBefore + uint128(params.liquidityDelta);
            } else {
                amount1 = SqrtPriceMath.getAmount1Delta(TickMath.getSqrtRatioAtTick(params.tickLower), TickMath.getSqrtRatioAtTick(params.tickUpper), params.liquidityDelta);
            }
        }
    }
    function _updatePosition(address owner, int24 tickLower, int24 tickUpper, int128 liquidityDelta, int24 tick) private returns (Position.Info storage position) {
        position = positions.get(owner, tickLower, tickUpper);
        uint256 _feeGrowthGlobal0X128 = feeGrowthGlobal0X128;
        uint256 _feeGrowthGlobal1X128 = feeGrowthGlobal1X128;
        bool flippedLower;
        bool flippedUpper;
        if (liquidityDelta != 0) {
            uint32 time = _blockTimestamp();
            (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observations.observeSingle(time, 0, slot0.tick, slot0.observationIndex, liquidity, slot0.observationCardinality);
            flippedLower = ticks.update(tickLower, tick, liquidityDelta, _feeGrowthGlobal0X128, _feeGrowthGlobal1X128, secondsPerLiquidityCumulativeX128, tickCumulative, time, false, maxLiquidityPerTick);
            flippedUpper = ticks.update(tickUpper, tick, liquidityDelta, _feeGrowthGlobal0X128, _feeGrowthGlobal1X128, secondsPerLiquidityCumulativeX128, tickCumulative, time, true, maxLiquidityPerTick);
            if (flippedLower) {
                tickBitmap.flipTick(tickLower, tickSpacing);
            }
            if (flippedUpper) {
                tickBitmap.flipTick(tickUpper, tickSpacing);
            }
        }
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = ticks.getFeeGrowthInside(tickLower, tickUpper, tick, _feeGrowthGlobal0X128, _feeGrowthGlobal1X128);
        position.update(liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128);
        if (liquidityDelta < 0) {
            if (flippedLower) {
                ticks.clear(tickLower);
            }
            if (flippedUpper) {
                ticks.clear(tickUpper);
            }
        }
    }
    function mint(address recipient, int24 tickLower, int24 tickUpper, uint128 amount, bytes calldata data) external override lock returns (uint256 amount0, uint256 amount1) {
        require(amount > 0);
        (, int256 amount0Int, int256 amount1Int) = _modifyPosition(ModifyPositionParams({owner: recipient, tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: int256(uint256(amount)).toInt128()}));
        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);
        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();
        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0, amount1, data);
        if (amount0 > 0 && balance0Before + amount0 > balance0()) revert M0();
        if (amount1 > 0 && balance1Before + amount1 > balance1()) revert M1();
        emit Mint(msg.sender, recipient, tickLower, tickUpper, amount, amount0, amount1);
    }
    function collect(address recipient, int24 tickLower, int24 tickUpper, uint128 amount0Requested, uint128 amount1Requested) external override lock returns (uint128 amount0, uint128 amount1) {
        Position.Info storage position = positions.get(msg.sender, tickLower, tickUpper);
        amount0 = amount0Requested > position.tokensOwed0 ? position.tokensOwed0 : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1 ? position.tokensOwed1 : amount1Requested;
        unchecked {
            if (amount0 > 0) {
                position.tokensOwed0 -= amount0;
                TransferHelper.safeTransfer(token0, recipient, amount0);
            }
            if (amount1 > 0) {
                position.tokensOwed1 -= amount1;
                TransferHelper.safeTransfer(token1, recipient, amount1);
            }
        }
        emit Collect(msg.sender, recipient, tickLower, tickUpper, amount0, amount1);
    }
    function burn(int24 tickLower, int24 tickUpper, uint128 amount) external override lock returns (uint256 amount0, uint256 amount1) {
        unchecked {
            (Position.Info storage position, int256 amount0Int, int256 amount1Int) = _modifyPosition(ModifyPositionParams({owner: msg.sender, tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: -int256(uint256(amount)).toInt128()}));
            amount0 = uint256(-amount0Int);
            amount1 = uint256(-amount1Int);
            if (amount0 > 0 || amount1 > 0) {
                (position.tokensOwed0, position.tokensOwed1) = (position.tokensOwed0 + uint128(amount0), position.tokensOwed1 + uint128(amount1));
            }
            emit Burn(msg.sender, tickLower, tickUpper, amount, amount0, amount1);
        }
    }
    struct SwapCache {
        uint8 feeProtocol;
        uint128 liquidityStart;
        uint32 blockTimestamp;
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulativeX128;
        bool computedLatestObservation;
    }
    struct SwapState {
        int256 amountSpecifiedRemaining;
        int256 amountCalculated;
        uint160 sqrtPriceX96;
        int24 tick;
        uint256 feeGrowthGlobalX128;
        uint128 protocolFee;
        uint128 liquidity;
    }
    struct StepComputations {
        uint160 sqrtPriceStartX96;
        int24 tickNext;
        bool initialized;
        uint160 sqrtPriceNextX96;
        uint256 amountIn;
        uint256 amountOut;
        uint256 feeAmount;
    }
    function swap(address recipient, bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96, bytes calldata data) external override returns (int256 amount0, int256 amount1) {
        if (amountSpecified == 0) revert AS();
        Slot0 memory slot0Start = slot0;
        if (!slot0Start.unlocked) revert LOK();
        require(zeroForOne ? sqrtPriceLimitX96 < slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO : sqrtPriceLimitX96 > slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO, "SPL");
        slot0.unlocked = false;
        SwapCache memory cache = SwapCache({liquidityStart: liquidity, blockTimestamp: _blockTimestamp(), feeProtocol: zeroForOne ? (slot0Start.feeProtocol % 16) : (slot0Start.feeProtocol >> 4), secondsPerLiquidityCumulativeX128: 0, tickCumulative: 0, computedLatestObservation: false});
        bool exactInput = amountSpecified > 0;
        SwapState memory state = SwapState({amountSpecifiedRemaining: amountSpecified, amountCalculated: 0, sqrtPriceX96: slot0Start.sqrtPriceX96, tick: slot0Start.tick, feeGrowthGlobalX128: zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128, protocolFee: 0, liquidity: cache.liquidityStart});
        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != sqrtPriceLimitX96) {
            StepComputations memory step;
            step.sqrtPriceStartX96 = state.sqrtPriceX96;
            (step.tickNext, step.initialized) = tickBitmap.nextInitializedTickWithinOneWord(state.tick, tickSpacing, zeroForOne);
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);
            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(state.sqrtPriceX96, (zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : step.sqrtPriceNextX96 > sqrtPriceLimitX96) ? sqrtPriceLimitX96 : step.sqrtPriceNextX96, state.liquidity, state.amountSpecifiedRemaining, fee);
            if (exactInput) {
                unchecked {
                    state.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount).toInt256();
                }
                state.amountCalculated -= step.amountOut.toInt256();
            } else {
                unchecked {
                    state.amountSpecifiedRemaining += step.amountOut.toInt256();
                }
                state.amountCalculated += (step.amountIn + step.feeAmount).toInt256();
            }
            if (cache.feeProtocol > 0) {
                unchecked {
                    uint256 delta = step.feeAmount / cache.feeProtocol;
                    step.feeAmount -= delta;
                    state.protocolFee += uint128(delta);
                }
            }
            if (state.liquidity > 0) {
                unchecked {
                    state.feeGrowthGlobalX128 += FullMath.mulDiv(step.feeAmount, FixedPoint128.Q128, state.liquidity);
                }
            }
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    if (!cache.computedLatestObservation) {
                        (cache.tickCumulative, cache.secondsPerLiquidityCumulativeX128) = observations.observeSingle(cache.blockTimestamp, 0, slot0Start.tick, slot0Start.observationIndex, cache.liquidityStart, slot0Start.observationCardinality);
                        cache.computedLatestObservation = true;
                    }
                    int128 liquidityNet = ticks.cross(step.tickNext, (zeroForOne ? state.feeGrowthGlobalX128 : feeGrowthGlobal0X128), (zeroForOne ? feeGrowthGlobal1X128 : state.feeGrowthGlobalX128), cache.secondsPerLiquidityCumulativeX128, cache.tickCumulative, cache.blockTimestamp);
                    unchecked {
                        if (zeroForOne) liquidityNet = -liquidityNet;
                    }
                    state.liquidity = liquidityNet < 0 ? state.liquidity - uint128(-liquidityNet) : state.liquidity + uint128(liquidityNet);
                }
                unchecked {
                    state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
                }
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }
        if (state.tick != slot0Start.tick) {
            (uint16 observationIndex, uint16 observationCardinality) = observations.write(slot0Start.observationIndex, cache.blockTimestamp, slot0Start.tick, cache.liquidityStart, slot0Start.observationCardinality, slot0Start.observationCardinalityNext);
            (slot0.sqrtPriceX96, slot0.tick, slot0.observationIndex, slot0.observationCardinality) = (state.sqrtPriceX96, state.tick, observationIndex, observationCardinality);
        } else {
            slot0.sqrtPriceX96 = state.sqrtPriceX96;
        }
        if (cache.liquidityStart != state.liquidity) liquidity = state.liquidity;
        if (zeroForOne) {
            feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
            unchecked {
                if (state.protocolFee > 0) protocolFees.token0 += state.protocolFee;
            }
        } else {
            feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
            unchecked {
                if (state.protocolFee > 0) protocolFees.token1 += state.protocolFee;
            }
        }
        unchecked {
            (amount0, amount1) = zeroForOne == exactInput ? (amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated) : (state.amountCalculated, amountSpecified - state.amountSpecifiedRemaining);
        }
        if (zeroForOne) {
            unchecked {
                if (amount1 < 0) TransferHelper.safeTransfer(token1, recipient, uint256(-amount1));
            }
            uint256 balance0Before = balance0();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
            if (balance0Before + uint256(amount0) > balance0()) revert IIA();
        } else {
            unchecked {
                if (amount0 < 0) TransferHelper.safeTransfer(token0, recipient, uint256(-amount0));
            }
            uint256 balance1Before = balance1();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
            if (balance1Before + uint256(amount1) > balance1()) revert IIA();
        }
        emit Swap(msg.sender, recipient, amount0, amount1, state.sqrtPriceX96, state.liquidity, state.tick);
        slot0.unlocked = true;
    }
    function distributeRewards(uint256 rewardsAmount, bool isToken0) external override {
        require(msg.sender == IUniswapV3Factory(factory).feeDistributor());
        uint256 feeGrowthGlobalX128 = isToken0 ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128;
        unchecked {
            feeGrowthGlobalX128 += FullMath.mulDiv(rewardsAmount, FixedPoint128.Q128, liquidity);
        }
        if (isToken0) {
            feeGrowthGlobal0X128 = feeGrowthGlobalX128;
        } else {
            feeGrowthGlobal1X128 = feeGrowthGlobalX128;
        }
    }
    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external override lock {
        uint128 _liquidity = liquidity;
        if (_liquidity <= 0) revert L();
        uint256 fee0 = FullMath.mulDivRoundingUp(amount0, fee, 1e6);
        uint256 fee1 = FullMath.mulDivRoundingUp(amount1, fee, 1e6);
        uint256 balance0Before = balance0();
        uint256 balance1Before = balance1();
        if (amount0 > 0) TransferHelper.safeTransfer(token0, recipient, amount0);
        if (amount1 > 0) TransferHelper.safeTransfer(token1, recipient, amount1);
        IUniswapV3FlashCallback(msg.sender).uniswapV3FlashCallback(fee0, fee1, data);
        uint256 balance0After = balance0();
        uint256 balance1After = balance1();
        if (balance0Before + fee0 > balance0After) revert F0();
        if (balance1Before + fee1 > balance1After) revert F1();
        unchecked {
            uint256 paid0 = balance0After - balance0Before;
            uint256 paid1 = balance1After - balance1Before;
            if (paid0 > 0) {
                uint8 feeProtocol0 = slot0.feeProtocol % 16;
                uint256 pFees0 = feeProtocol0 == 0 ? 0 : paid0 / feeProtocol0;
                if (uint128(pFees0) > 0) protocolFees.token0 += uint128(pFees0);
                feeGrowthGlobal0X128 += FullMath.mulDiv(paid0 - pFees0, FixedPoint128.Q128, _liquidity);
            }
            if (paid1 > 0) {
                uint8 feeProtocol1 = slot0.feeProtocol >> 4;
                uint256 pFees1 = feeProtocol1 == 0 ? 0 : paid1 / feeProtocol1;
                if (uint128(pFees1) > 0) protocolFees.token1 += uint128(pFees1);
                feeGrowthGlobal1X128 += FullMath.mulDiv(paid1 - pFees1, FixedPoint128.Q128, _liquidity);
            }
            emit Flash(msg.sender, recipient, amount0, amount1, paid0, paid1);
        }
    }
    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external override lock onlyFactoryOwner {
        unchecked {
            require((feeProtocol0 == 0 || (feeProtocol0 >= 4 && feeProtocol0 <= 10)) && (feeProtocol1 == 0 || (feeProtocol1 >= 4 && feeProtocol1 <= 10)));
            uint8 feeProtocolOld = slot0.feeProtocol;
            slot0.feeProtocol = feeProtocol0 + (feeProtocol1 << 4);
            emit SetFeeProtocol(feeProtocolOld % 16, feeProtocolOld >> 4, feeProtocol0, feeProtocol1);
        }
    }
    function collectProtocol(address recipient, uint128 amount0Requested, uint128 amount1Requested) external override lock onlyFactoryOwner returns (uint128 amount0, uint128 amount1) {
        amount0 = amount0Requested > protocolFees.token0 ? protocolFees.token0 : amount0Requested;
        amount1 = amount1Requested > protocolFees.token1 ? protocolFees.token1 : amount1Requested;
        unchecked {
            if (amount0 > 0) {
                if (amount0 == protocolFees.token0) amount0--;
                protocolFees.token0 -= amount0;
                TransferHelper.safeTransfer(token0, recipient, amount0);
            }
            if (amount1 > 0) {
                if (amount1 == protocolFees.token1) amount1--;
                protocolFees.token1 -= amount1;
                TransferHelper.safeTransfer(token1, recipient, amount1);
            }
        }
        emit CollectProtocol(msg.sender, recipient, amount0, amount1);
    }
}
