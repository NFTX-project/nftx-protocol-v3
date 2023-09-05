contract NonfungiblePositionManager is INonfungiblePositionManager, Ownable, Multicall, ERC721Permit, PeripheryImmutableState, PoolInitializer, LiquidityManagement, PeripheryValidation, SelfPermit {
    struct Position {
        uint96 nonce;
        address operator;
        uint80 poolId;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }
    mapping(address => uint80) private _poolIds;
    mapping(uint80 => PoolAddress.PoolKey) private _poolIdToPoolKey;
    mapping(uint256 => Position) private _positions;
    uint176 private _nextId = 1;
    uint80 private _nextPoolId = 1;
    address private immutable _tokenDescriptor;
    mapping(uint256 => uint256) public override lockedUntil;
    mapping(uint256 => uint256) public override timelock;
    mapping(address => bool) public override timelockExcluded;
    constructor(address _factory, address _WETH9, address _tokenDescriptor_) ERC721Permit("NFTX V3 Positions", "NFTX-V3-POS", "1") PeripheryImmutableState(_factory, _WETH9) {
        _tokenDescriptor = _tokenDescriptor_;
    }
    function positions(uint256 tokenId) external view override returns (uint96 nonce, address operator, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, uint128 tokensOwed0, uint128 tokensOwed1) {
        Position memory position = _positions[tokenId];
        require(position.poolId != 0, "Invalid token ID");
        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        return (position.nonce, position.operator, poolKey.token0, poolKey.token1, poolKey.fee, position.tickLower, position.tickUpper, position.liquidity, position.feeGrowthInside0LastX128, position.feeGrowthInside1LastX128, position.tokensOwed0, position.tokensOwed1);
    }
    function cachePoolKey(address pool, PoolAddress.PoolKey memory poolKey) private returns (uint80 poolId) {
        poolId = _poolIds[pool];
        if (poolId == 0) {
            _poolIds[pool] = (poolId = _nextPoolId++);
            _poolIdToPoolKey[poolId] = poolKey;
        }
    }
    function mint(MintParams calldata params) external payable override checkDeadline(params.deadline) returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        IUniswapV3Pool pool;
        (liquidity, amount0, amount1, pool) = addLiquidity(AddLiquidityParams({token0: params.token0, token1: params.token1, fee: params.fee, recipient: address(this), tickLower: params.tickLower, tickUpper: params.tickUpper, amount0Desired: params.amount0Desired, amount1Desired: params.amount1Desired, amount0Min: params.amount0Min, amount1Min: params.amount1Min}));
        _mint(params.recipient, (tokenId = _nextId++));
        bytes32 positionKey = PositionKey.compute(address(this), params.tickLower, params.tickUpper);
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey);
        uint80 poolId = cachePoolKey(address(pool), PoolAddress.PoolKey({token0: params.token0, token1: params.token1, fee: params.fee}));
        _positions[tokenId] = Position({nonce: 0, operator: address(0), poolId: poolId, tickLower: params.tickLower, tickUpper: params.tickUpper, liquidity: liquidity, feeGrowthInside0LastX128: feeGrowthInside0LastX128, feeGrowthInside1LastX128: feeGrowthInside1LastX128, tokensOwed0: 0, tokensOwed1: 0});
        emit IncreaseLiquidity(tokenId, liquidity, amount0, amount1);
    }
    modifier isAuthorizedForToken(uint256 tokenId) {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not approved");
        _;
    }
    function tokenURI(uint256 tokenId) public view override(ERC721, IERC721Metadata) returns (string memory) {
        require(_exists(tokenId));
        return INonfungibleTokenPositionDescriptor(_tokenDescriptor).tokenURI(this, tokenId);
    }
    function baseURI() public pure returns (string memory) {}
    function increaseLiquidity(IncreaseLiquidityParams calldata params) external payable override checkDeadline(params.deadline) returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        Position storage position = _positions[params.tokenId];
        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        IUniswapV3Pool pool;
        (liquidity, amount0, amount1, pool) = addLiquidity(AddLiquidityParams({token0: poolKey.token0, token1: poolKey.token1, fee: poolKey.fee, tickLower: position.tickLower, tickUpper: position.tickUpper, amount0Desired: params.amount0Desired, amount1Desired: params.amount1Desired, amount0Min: params.amount0Min, amount1Min: params.amount1Min, recipient: address(this)}));
        bytes32 positionKey = PositionKey.compute(address(this), position.tickLower, position.tickUpper);
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey);
        position.tokensOwed0 += uint128(FullMath.mulDiv(feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128, position.liquidity, FixedPoint128.Q128));
        position.tokensOwed1 += uint128(FullMath.mulDiv(feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128, position.liquidity, FixedPoint128.Q128));
        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        position.liquidity += liquidity;
        emit IncreaseLiquidity(params.tokenId, liquidity, amount0, amount1);
    }
    function decreaseLiquidity(DecreaseLiquidityParams calldata params) external payable override isAuthorizedForToken(params.tokenId) checkDeadline(params.deadline) returns (uint256 amount0, uint256 amount1) {
        require(params.liquidity > 0);
        require(timelockExcluded[msg.sender] || block.timestamp > lockedUntil[params.tokenId]);
        Position storage position = _positions[params.tokenId];
        uint128 positionLiquidity = position.liquidity;
        require(positionLiquidity >= params.liquidity);
        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));
        (amount0, amount1) = pool.burn(position.tickLower, position.tickUpper, params.liquidity);
        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, "Price slippage check");
        bytes32 positionKey = PositionKey.compute(address(this), position.tickLower, position.tickUpper);
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey);
        position.tokensOwed0 += uint128(amount0) + uint128(FullMath.mulDiv(feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128, positionLiquidity, FixedPoint128.Q128));
        position.tokensOwed1 += uint128(amount1) + uint128(FullMath.mulDiv(feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128, positionLiquidity, FixedPoint128.Q128));
        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        position.liquidity = positionLiquidity - params.liquidity;
        emit DecreaseLiquidity(params.tokenId, params.liquidity, amount0, amount1);
    }
    function collect(CollectParams calldata params) external payable override isAuthorizedForToken(params.tokenId) returns (uint256 amount0, uint256 amount1) {
        require(params.amount0Max > 0 || params.amount1Max > 0);
        address recipient = params.recipient == address(0) ? address(this) : params.recipient;
        Position storage position = _positions[params.tokenId];
        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));
        (uint128 tokensOwed0, uint128 tokensOwed1) = (position.tokensOwed0, position.tokensOwed1);
        if (position.liquidity > 0) {
            pool.burn(position.tickLower, position.tickUpper, 0);
            (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(PositionKey.compute(address(this), position.tickLower, position.tickUpper));
            tokensOwed0 += uint128(FullMath.mulDiv(feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128, position.liquidity, FixedPoint128.Q128));
            tokensOwed1 += uint128(FullMath.mulDiv(feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128, position.liquidity, FixedPoint128.Q128));
            position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
            position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        }
        (uint128 amount0Collect, uint128 amount1Collect) = (params.amount0Max > tokensOwed0 ? tokensOwed0 : params.amount0Max, params.amount1Max > tokensOwed1 ? tokensOwed1 : params.amount1Max);
        (amount0, amount1) = pool.collect(recipient, position.tickLower, position.tickUpper, amount0Collect, amount1Collect);
        (position.tokensOwed0, position.tokensOwed1) = (tokensOwed0 - amount0Collect, tokensOwed1 - amount1Collect);
        emit Collect(params.tokenId, recipient, amount0Collect, amount1Collect);
    }
    function burn(uint256 tokenId) external payable override isAuthorizedForToken(tokenId) {
        Position storage position = _positions[tokenId];
        require(position.liquidity == 0 && position.tokensOwed0 == 0 && position.tokensOwed1 == 0, "Not cleared");
        delete _positions[tokenId];
        _burn(tokenId);
    }
    function setLockedUntil(uint256 tokenId, uint256 lockedUntil_, uint256 timelock_) external override {
        require(msg.sender == address(INFTXFeeDistributorV3(IUniswapV3Factory(factory).feeDistributor()).nftxRouter()));
        lockedUntil[tokenId] = lockedUntil_;
        timelock[tokenId] = timelock_;
    }
    function setTimelockExcluded(address addr, bool isExcluded) external onlyOwner {
        timelockExcluded[addr] = isExcluded;
    }
    function _getAndIncrementNonce(uint256 tokenId) internal override returns (uint256) {
        return uint256(_positions[tokenId].nonce++);
    }
    function getApproved(uint256 tokenId) public view override(ERC721, IERC721) returns (address) {
        require(_exists(tokenId), "ERC721: approved query for nonexistent token");
        return _positions[tokenId].operator;
    }
    function _approve(address to, uint256 tokenId) internal override(ERC721) {
        _positions[tokenId].operator = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }
}
