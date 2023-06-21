// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";
import {INFTXVaultV3} from "@src/interfaces/INFTXVaultV3.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {INFTXInventoryStakingV2} from "@src/v2/interfaces/INFTXInventoryStakingV2.sol";
import {INFTXInventoryStakingV3} from "@src/interfaces/INFTXInventoryStakingV3.sol";
import {INonfungiblePositionManager} from "@uni-periphery/interfaces/INonfungiblePositionManager.sol";

contract MigratorZap {
    INonfungiblePositionManager public immutable positionManager;
    IWETH9 public immutable WETH;
    INFTXInventoryStakingV2 public immutable v2Inventory;
    INFTXInventoryStakingV3 public immutable v3Inventory;

    constructor(
        INonfungiblePositionManager positionManager_,
        INFTXInventoryStakingV2 v2Inventory_,
        INFTXInventoryStakingV3 v3Inventory_
    ) {
        positionManager = positionManager_;
        WETH = IWETH9(positionManager_.WETH9());
        v2Inventory = v2Inventory_;
        v3Inventory = v3Inventory_;

        WETH.approve(address(positionManager_), type(uint256).max);
    }

    struct SushiToNFTXAMMParams {
        address sushiPair;
        address vToken;
        uint256 lpAmount;
        uint256 vaultId;
        int24 tickLower;
        int24 tickUpper;
        uint24 fee;
        uint160 sqrtPriceX96;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /**
     * @notice Migrates liquidity from Sushiswap to NFTX AMM
     */
    function sushiToNFTXAMM(
        SushiToNFTXAMMParams calldata params
    ) external returns (uint256 positionId) {
        // TODO: use UNI-V2's native permit for gasless approval
        // get lp tokens from the user
        IUniswapV2Pair(params.sushiPair).transferFrom(
            msg.sender,
            address(this),
            params.lpAmount
        );
        // burn sushi liquidity to this contract
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(params.sushiPair)
            .burn(address(this));

        bool _isVToken0 = params.vToken < address(WETH);
        (address token0, address token1) = _isVToken0
            ? (params.vToken, address(WETH))
            : (address(WETH), params.vToken);

        // deploy new pool if doesn't yet exist
        positionManager.createAndInitializePoolIfNecessary(
            token0,
            token1,
            params.fee,
            params.sqrtPriceX96
        );

        // give vToken approval to positionManager
        _maxApproveToken(
            params.vToken,
            address(positionManager),
            _isVToken0 ? amount0 : amount1
        );

        // provide liquidity to NFTX AMM
        uint256 newAmount0;
        uint256 newAmount1;
        (positionId, , newAmount0, newAmount1) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: params.fee,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                recipient: msg.sender,
                deadline: params.deadline
            })
        );

        // refund any dust left
        if (newAmount0 < amount0) {
            IERC20(token0).transfer(msg.sender, amount0 - newAmount0);
        }
        if (newAmount1 < amount1) {
            IERC20(token1).transfer(msg.sender, amount1 - newAmount1);
        }
    }

    /**
     * @notice Move vTokens from v2 Inventory to v3 Inventory (minting xNFT)
     */
    function v2InventoryToXNFT(
        uint256 vaultId,
        address vToken,
        uint256 shares
    ) external returns (uint256 xNFTId) {
        address xToken = v2Inventory.vaultXToken(vaultId);
        IERC20(xToken).transferFrom(msg.sender, address(this), shares);

        v2Inventory.withdraw(vaultId, shares);

        uint256 vTokenBalance = IERC20(vToken).balanceOf(address(this));
        _maxApproveToken(vToken, address(v3Inventory), vTokenBalance);

        xNFTId = v3Inventory.deposit(vaultId, vTokenBalance, msg.sender);
    }

    function _maxApproveToken(
        address token,
        address spender,
        uint256 amount
    ) internal {
        uint256 allowance = IERC20(token).allowance(address(this), spender);

        if (amount > allowance) {
            // SafeERC20 not required here as both vToken and WETH follow the ERC20 standard correctly
            IERC20(token).approve(spender, type(uint256).max);
        }
    }
}
