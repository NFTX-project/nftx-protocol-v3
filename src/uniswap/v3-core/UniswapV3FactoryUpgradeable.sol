contract UniswapV3FactoryUpgradeable is IUniswapV3Factory, UniswapV3PoolDeployerUpgradeable {
    address public override feeDistributor;
    mapping(uint24 => int24) public override feeAmountTickSpacing;
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;
    uint16 public override rewardTierCardinality;
    function __UniswapV3FactoryUpgradeable_init(address beaconImplementation_, uint16 rewardTierCardinality_) external initializer {
        __UniswapV3PoolDeployerUpgradeable_init(beaconImplementation_);
        if (rewardTierCardinality_ <= 1) revert InvalidRewardTierCardinality();
        rewardTierCardinality = rewardTierCardinality_;
        feeAmountTickSpacing[10000] = 200;
        emit FeeAmountEnabled(10000, 200);
    }
    function createPool(address tokenA, address tokenB, uint24 fee) external override returns (address pool) {
        require(tokenA != tokenB);
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0));
        int24 tickSpacing = feeAmountTickSpacing[fee];
        require(tickSpacing != 0);
        require(getPool[token0][token1][fee] == address(0));
        pool = deploy(address(this), token0, token1, fee, tickSpacing, rewardTierCardinality);
        getPool[token0][token1][fee] = pool;
        getPool[token1][token0][fee] = pool;
        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }
    function setFeeDistributor(address feeDistributor_) external override onlyOwner {
        feeDistributor = feeDistributor_;
    }
    function setRewardTierCardinality(uint16 rewardTierCardinality_) external override onlyOwner {
        if (rewardTierCardinality_ <= 1) revert InvalidRewardTierCardinality();
        rewardTierCardinality = rewardTierCardinality_;
    }
    function enableFeeAmount(uint24 fee, int24 tickSpacing) public override onlyOwner {
        require(fee < 1000000);
        require(tickSpacing > 0 && tickSpacing < 16384);
        require(feeAmountTickSpacing[fee] == 0);
        feeAmountTickSpacing[fee] = tickSpacing;
        emit FeeAmountEnabled(fee, tickSpacing);
    }
    function owner() public view override(IUniswapV3Factory, OwnableUpgradeable) returns (address) {
        return super.owner();
    }
}
