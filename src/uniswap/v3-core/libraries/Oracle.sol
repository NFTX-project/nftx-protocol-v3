library Oracle {
    error I();
    error OLD();
    struct Observation {
        uint32 blockTimestamp;
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulativeX128;
        bool initialized;
    }
    function transform(Observation memory last, uint32 blockTimestamp, int24 tick, uint128 liquidity) private pure returns (Observation memory) {
        unchecked {
            uint32 delta = blockTimestamp - last.blockTimestamp;
            return Observation({blockTimestamp: blockTimestamp, tickCumulative: last.tickCumulative + int56(tick) * int56(uint56(delta)), secondsPerLiquidityCumulativeX128: last.secondsPerLiquidityCumulativeX128 + ((uint160(delta) << 128) / (liquidity > 0 ? liquidity : 1)), initialized: true});
        }
    }
    function initialize(Observation[65535] storage self, uint32 time) internal returns (uint16 cardinality) {
        self[0] = Observation({blockTimestamp: time, tickCumulative: 0, secondsPerLiquidityCumulativeX128: 0, initialized: true});
        return 1;
    }
    function write(Observation[65535] storage self, uint16 index, uint32 blockTimestamp, int24 tick, uint128 liquidity, uint16 cardinality, uint16 cardinalityNext) internal returns (uint16 indexUpdated, uint16 cardinalityUpdated) {
        unchecked {
            Observation memory last = self[index];
            if (last.blockTimestamp == blockTimestamp) return (index, cardinality);
            if (cardinalityNext > cardinality && index == (cardinality - 1)) {
                cardinalityUpdated = cardinalityNext;
            } else {
                cardinalityUpdated = cardinality;
            }
            indexUpdated = (index + 1) % cardinalityUpdated;
            self[indexUpdated] = transform(last, blockTimestamp, tick, liquidity);
        }
    }
    function grow(Observation[65535] storage self, uint16 current, uint16 next, bool shouldSSTORE) internal returns (uint16) {
        unchecked {
            if (current <= 0) revert I();
            if (next <= current) return current;
            if (shouldSSTORE) {
                for (uint16 i = current; i < next; i++) self[i].blockTimestamp = 1;
            }
            return next;
        }
    }
    function lte(uint32 time, uint32 a, uint32 b) private pure returns (bool) {
        unchecked {
            if (a <= time && b <= time) return a <= b;
            uint256 aAdjusted = a > time ? a : a + 2 ** 32;
            uint256 bAdjusted = b > time ? b : b + 2 ** 32;
            return aAdjusted <= bAdjusted;
        }
    }
    function binarySearch(Observation[65535] storage self, uint32 time, uint32 target, uint16 index, uint16 cardinality) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        unchecked {
            uint256 l = (index + 1) % cardinality; 
            uint256 r = l + cardinality - 1; 
            uint256 i;
            while (true) {
                i = (l + r) / 2;
                beforeOrAt = self[i % cardinality];
                if (!beforeOrAt.initialized) {
                    l = i + 1;
                    continue;
                }
                atOrAfter = self[(i + 1) % cardinality];
                bool targetAtOrAfter = lte(time, beforeOrAt.blockTimestamp, target);
                if (targetAtOrAfter && lte(time, target, atOrAfter.blockTimestamp)) break;
                if (!targetAtOrAfter) r = i - 1;
                else l = i + 1;
            }
        }
    }
    function getSurroundingObservations(Observation[65535] storage self, uint32 time, uint32 target, int24 tick, uint16 index, uint128 liquidity, uint16 cardinality) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        unchecked {
            beforeOrAt = self[index];
            if (lte(time, beforeOrAt.blockTimestamp, target)) {
                if (beforeOrAt.blockTimestamp == target) {
                    return (beforeOrAt, atOrAfter);
                } else {
                    return (beforeOrAt, transform(beforeOrAt, target, tick, liquidity));
                }
            }
            beforeOrAt = self[(index + 1) % cardinality];
            if (!beforeOrAt.initialized) beforeOrAt = self[0];
            if (!lte(time, beforeOrAt.blockTimestamp, target)) revert OLD();
            return binarySearch(self, time, target, index, cardinality);
        }
    }
    function observeSingle(Observation[65535] storage self, uint32 time, uint32 secondsAgo, int24 tick, uint16 index, uint128 liquidity, uint16 cardinality) internal view returns (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) {
        unchecked {
            if (secondsAgo == 0) {
                Observation memory last = self[index];
                if (last.blockTimestamp != time) last = transform(last, time, tick, liquidity);
                return (last.tickCumulative, last.secondsPerLiquidityCumulativeX128);
            }
            uint32 target = time - secondsAgo;
            (Observation memory beforeOrAt, Observation memory atOrAfter) = getSurroundingObservations(self, time, target, tick, index, liquidity, cardinality);
            if (target == beforeOrAt.blockTimestamp) {
                return (beforeOrAt.tickCumulative, beforeOrAt.secondsPerLiquidityCumulativeX128);
            } else if (target == atOrAfter.blockTimestamp) {
                return (atOrAfter.tickCumulative, atOrAfter.secondsPerLiquidityCumulativeX128);
            } else {
                uint32 observationTimeDelta = atOrAfter.blockTimestamp - beforeOrAt.blockTimestamp;
                uint32 targetDelta = target - beforeOrAt.blockTimestamp;
                return (beforeOrAt.tickCumulative + ((atOrAfter.tickCumulative - beforeOrAt.tickCumulative) / int56(uint56(observationTimeDelta))) * int56(uint56(targetDelta)), beforeOrAt.secondsPerLiquidityCumulativeX128 + uint160((uint256(atOrAfter.secondsPerLiquidityCumulativeX128 - beforeOrAt.secondsPerLiquidityCumulativeX128) * targetDelta) / observationTimeDelta));
            }
        }
    }
    function observe(Observation[65535] storage self, uint32 time, uint32[] memory secondsAgos, int24 tick, uint16 index, uint128 liquidity, uint16 cardinality) internal view returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) {
        unchecked {
            if (cardinality <= 0) revert I();
            tickCumulatives = new int56[](secondsAgos.length);
            secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
            for (uint256 i = 0; i < secondsAgos.length; i++) {
                (tickCumulatives[i], secondsPerLiquidityCumulativeX128s[i]) = observeSingle(self, time, secondsAgos[i], tick, index, liquidity, cardinality);
            }
        }
    }
}
