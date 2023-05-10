// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {Create2Upgradeable} from "@openzeppelin-upgradeable/contracts/utils/Create2Upgradeable.sol";

/// @title Provides functions for deriving a pool address from the factory, tokens, and the fee
library PoolAddress {
    // NOTE: Ensure this value is latest & corresponds to current Create2BeaconProxy code
    // keccak256(type(Create2BeaconProxy).creationCode);
    bytes32 internal constant BEACON_CODE_HASH =
        0x25e3ec08b5481ab6736bacbc1babb737902563de379be5263db365452e048cc1;

    /// @notice The identifying key of the pool
    struct PoolKey {
        address token0;
        address token1;
        uint24 fee;
    }

    /// @notice Returns PoolKey: the ordered tokens with the matched fee levels
    /// @param tokenA The first token of a pool, unsorted
    /// @param tokenB The second token of a pool, unsorted
    /// @param fee The fee level of the pool
    /// @return Poolkey The pool details with ordered token0 and token1 assignments
    function getPoolKey(
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal pure returns (PoolKey memory) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey({token0: tokenA, token1: tokenB, fee: fee});
    }

    /// @notice Deterministically computes the pool address given the factory and PoolKey
    /// @param factory The Uniswap V3 factory contract address
    /// @param key The PoolKey
    /// @return pool The contract address of the V3 pool
    function computeAddress(
        address factory,
        PoolKey memory key
    ) internal pure returns (address pool) {
        require(key.token0 < key.token1);
        pool = Create2Upgradeable.computeAddress(
            keccak256(abi.encode(key.token0, key.token1, key.fee)),
            BEACON_CODE_HASH,
            factory
        );
    }
}
