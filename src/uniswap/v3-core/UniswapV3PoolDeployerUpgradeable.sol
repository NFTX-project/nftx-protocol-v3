contract UniswapV3PoolDeployerUpgradeable is UpgradeableBeacon {
    bytes internal constant BEACON_CODE = type(Create2BeaconProxy).creationCode;
    function __UniswapV3PoolDeployerUpgradeable_init(address beaconImplementation_) public onlyInitializing {
        __UpgradeableBeacon__init(beaconImplementation_);
    }
    function deploy(address factory, address token0, address token1, uint24 fee, int24 tickSpacing, uint16 observationCardinalityNext) internal returns (address pool) {
        pool = Create2Upgradeable.deploy(0, keccak256(abi.encode(token0, token1, fee)), BEACON_CODE);
        IUniswapV3Pool(pool).__UniswapV3PoolUpgradeable_init(factory, token0, token1, fee, tickSpacing, observationCardinalityNext);
    }
}
