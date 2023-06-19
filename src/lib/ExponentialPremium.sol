// SPDX-License-Identifier: MIT
// Modified from ENS: https://github.com/ensdomains/ens-contracts/blob/master/contracts/ethregistrar/ExponentialPremiumPriceOracle.sol

pragma solidity ^0.8.0;

library ExponentialPremium {
    uint256 constant PRECISION = 1e18;
    uint256 constant bit1 = 999989423469314432; // 0.5 ^ 1/65536 * (10 ** 18)
    uint256 constant bit2 = 999978847050491904; // 0.5 ^ 2/65536 * (10 ** 18)
    uint256 constant bit3 = 999957694548431104;
    uint256 constant bit4 = 999915390886613504;
    uint256 constant bit5 = 999830788931929088;
    uint256 constant bit6 = 999661606496243712;
    uint256 constant bit7 = 999323327502650752;
    uint256 constant bit8 = 998647112890970240;
    uint256 constant bit9 = 997296056085470080;
    uint256 constant bit10 = 994599423483633152;
    uint256 constant bit11 = 989228013193975424;
    uint256 constant bit12 = 978572062087700096;
    uint256 constant bit13 = 957603280698573696;
    uint256 constant bit14 = 917004043204671232;
    uint256 constant bit15 = 840896415253714560;
    uint256 constant bit16 = 707106781186547584;

    // converting true exponential into individual steps
    uint256 constant timeStep = 1 hours;

    /**
     * @dev Returns the premium in internal base units.
     */
    function getPremium(
        uint256 depositedAt,
        uint256 startPremium,
        uint256 premiumDuration
    ) internal view returns (uint256) {
        uint256 elapsed = block.timestamp - depositedAt;
        uint256 premium = _decayedPremium(startPremium, elapsed);

        uint256 endValue = startPremium >> (premiumDuration / timeStep); // endValue = startPremium >> totalSteps
        if (premium >= endValue) {
            return premium - endValue;
        }
        return 0;
    }

    /**
     * @dev Returns the premium value at current time elapsed
     * @param startPremium starting value
     * @param elapsed time past since nft deposit
     */
    function _decayedPremium(
        uint256 startPremium,
        uint256 elapsed
    ) internal pure returns (uint256) {
        uint256 stepsPast = (elapsed * PRECISION) / timeStep;
        uint256 intSteps = stepsPast / PRECISION;
        uint256 premium = startPremium >> intSteps;
        uint256 partStep = (stepsPast - intSteps * PRECISION);
        uint256 fraction = (partStep * (2 ** 16)) / PRECISION;
        uint256 totalPremium = _addFractionalPremium(fraction, premium);
        return totalPremium;
    }

    function _addFractionalPremium(
        uint256 fraction,
        uint256 premium
    ) internal pure returns (uint256) {
        if (fraction & (1 << 0) != 0) {
            premium = (premium * bit1) / PRECISION;
        }
        if (fraction & (1 << 1) != 0) {
            premium = (premium * bit2) / PRECISION;
        }
        if (fraction & (1 << 2) != 0) {
            premium = (premium * bit3) / PRECISION;
        }
        if (fraction & (1 << 3) != 0) {
            premium = (premium * bit4) / PRECISION;
        }
        if (fraction & (1 << 4) != 0) {
            premium = (premium * bit5) / PRECISION;
        }
        if (fraction & (1 << 5) != 0) {
            premium = (premium * bit6) / PRECISION;
        }
        if (fraction & (1 << 6) != 0) {
            premium = (premium * bit7) / PRECISION;
        }
        if (fraction & (1 << 7) != 0) {
            premium = (premium * bit8) / PRECISION;
        }
        if (fraction & (1 << 8) != 0) {
            premium = (premium * bit9) / PRECISION;
        }
        if (fraction & (1 << 9) != 0) {
            premium = (premium * bit10) / PRECISION;
        }
        if (fraction & (1 << 10) != 0) {
            premium = (premium * bit11) / PRECISION;
        }
        if (fraction & (1 << 11) != 0) {
            premium = (premium * bit12) / PRECISION;
        }
        if (fraction & (1 << 12) != 0) {
            premium = (premium * bit13) / PRECISION;
        }
        if (fraction & (1 << 13) != 0) {
            premium = (premium * bit14) / PRECISION;
        }
        if (fraction & (1 << 14) != 0) {
            premium = (premium * bit15) / PRECISION;
        }
        if (fraction & (1 << 15) != 0) {
            premium = (premium * bit16) / PRECISION;
        }
        return premium;
    }
}
