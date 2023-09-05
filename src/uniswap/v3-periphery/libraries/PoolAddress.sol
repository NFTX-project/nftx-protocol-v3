library PoolAddress {
    bytes32 internal constant BEACON_CODE_HASH = 0x7700ec83d0dc69c0a1e228138168ca93778a8d2f0fe9a0afb44901e1d5142d48;
    struct PoolKey {
        address token0;
        address token1;
        uint24 fee;
    }
    function getPoolKey(address tokenA, address tokenB, uint24 fee) internal pure returns (PoolKey memory) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey({token0: tokenA, token1: tokenB, fee: fee});
    }
    function computeAddress(address factory, PoolKey memory key) internal pure returns (address pool) {
        require(key.token0 < key.token1);
        pool = Create2Upgradeable.computeAddress(keccak256(abi.encode(key.token0, key.token1, key.fee)), BEACON_CODE_HASH, factory);
    }
}
