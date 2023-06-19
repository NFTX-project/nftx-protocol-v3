// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.15;

import {UpgradeableBeacon} from "@src/custom/proxy/UpgradeableBeacon.sol";
import {Create2Upgradeable} from "@openzeppelin-upgradeable/contracts/utils/Create2Upgradeable.sol";
import {Create2BeaconProxy} from "@src/custom/proxy/Create2BeaconProxy.sol";

import {UniswapV3PoolUpgradeable, IUniswapV3Pool} from "./UniswapV3PoolUpgradeable.sol";

contract UniswapV3PoolDeployerUpgradeable is UpgradeableBeacon {
    bytes internal constant BEACON_CODE = type(Create2BeaconProxy).creationCode;

    function __UniswapV3PoolDeployerUpgradeable_init(
        address beaconImplementation_
    ) public onlyInitializing {
        __UpgradeableBeacon__init(beaconImplementation_);
    }

    /// @dev Deploys a pool with the given parameters by transiently setting the parameters storage slot and then
    /// clearing it after deploying the pool.
    /// @param factory The contract address of the Uniswap V3 factory
    /// @param token0 The first token of the pool by address sort order
    /// @param token1 The second token of the pool by address sort order
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param tickSpacing The spacing between usable ticks
    function deploy(
        address factory,
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing,
        uint16 observationCardinalityNext
    ) internal returns (address pool) {
        pool = Create2Upgradeable.deploy(
            0,
            keccak256(abi.encode(token0, token1, fee)),
            BEACON_CODE
        );
        IUniswapV3Pool(pool).__UniswapV3PoolUpgradeable_init(
            factory,
            token0,
            token1,
            fee,
            tickSpacing,
            observationCardinalityNext
        );
    }
}
