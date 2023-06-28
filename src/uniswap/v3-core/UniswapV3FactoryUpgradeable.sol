// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.15;

import {IUniswapV3Factory} from "./interfaces/IUniswapV3Factory.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {INFTXFeeDistributorV3} from "@src/interfaces/INFTXFeeDistributorV3.sol";

import {UniswapV3PoolDeployerUpgradeable, UpgradeableBeacon} from "./UniswapV3PoolDeployerUpgradeable.sol";

/// @title Canonical Uniswap V3 factory
/// @notice Deploys Uniswap V3 pools and manages ownership and control over pool protocol fees
contract UniswapV3FactoryUpgradeable is
    IUniswapV3Factory,
    UniswapV3PoolDeployerUpgradeable
{
    /// @inheritdoc IUniswapV3Factory
    address public override feeDistributor;

    /// @inheritdoc IUniswapV3Factory
    mapping(uint24 => int24) public override feeAmountTickSpacing;
    /// @inheritdoc IUniswapV3Factory
    mapping(address => mapping(address => mapping(uint24 => address)))
        public
        override getPool;

    uint16 public override rewardTierCardinality;

    function __UniswapV3FactoryUpgradeable_init(
        address beaconImplementation_,
        uint16 rewardTierCardinality_
    ) external initializer {
        __UniswapV3PoolDeployerUpgradeable_init(beaconImplementation_);

        rewardTierCardinality = rewardTierCardinality_;

        // feeAmountTickSpacing[500] = 10;
        // emit FeeAmountEnabled(500, 10);
        // feeAmountTickSpacing[3000] = 60;
        // emit FeeAmountEnabled(3000, 60);
        feeAmountTickSpacing[10000] = 200;
        emit FeeAmountEnabled(10000, 200);
    }

    /// @inheritdoc IUniswapV3Factory
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override returns (address pool) {
        require(tokenA != tokenB);
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0));
        int24 tickSpacing = feeAmountTickSpacing[fee];
        require(tickSpacing != 0);
        require(getPool[token0][token1][fee] == address(0));
        pool = deploy(
            address(this),
            token0,
            token1,
            fee,
            tickSpacing,
            INFTXFeeDistributorV3(feeDistributor).rewardFeeTier() == fee
                ? rewardTierCardinality
                : 1
        );
        getPool[token0][token1][fee] = pool;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        getPool[token1][token0][fee] = pool;
        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }

    /// @inheritdoc IUniswapV3Factory
    function setFeeDistributor(
        address feeDistributor_
    ) external override onlyOwner {
        feeDistributor = feeDistributor_;
    }

    function setRewardTierCardinality(
        uint16 rewardTierCardinality_
    ) external override onlyOwner {
        rewardTierCardinality = rewardTierCardinality_;
    }

    /// @inheritdoc IUniswapV3Factory
    function enableFeeAmount(
        uint24 fee,
        int24 tickSpacing
    ) public override onlyOwner {
        require(fee < 1000000);
        // tick spacing is capped at 16384 to prevent the situation where tickSpacing is so large that
        // TickBitmap#nextInitializedTickWithinOneWord overflows int24 container from a valid tick
        // 16384 ticks represents a >5x price change with ticks of 1 bips
        require(tickSpacing > 0 && tickSpacing < 16384);
        require(feeAmountTickSpacing[fee] == 0);

        feeAmountTickSpacing[fee] = tickSpacing;
        emit FeeAmountEnabled(fee, tickSpacing);
    }

    function owner()
        public
        view
        override(IUniswapV3Factory, OwnableUpgradeable)
        returns (address)
    {
        return super.owner();
    }
}
