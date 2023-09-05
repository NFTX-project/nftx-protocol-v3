// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {ISwapRouter, SwapRouter} from "@uni-periphery/SwapRouter.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPermitAllowanceTransfer} from "@src/interfaces/external/IPermitAllowanceTransfer.sol";

/// @notice A Router contract that uses Permit2 for allowance, and swaps between 2 tokens via UniV3 Pool
contract MockUniversalRouter {
    using SafeERC20 for IERC20;

    uint24 constant DEFAULT_FEE_TIER = 10000;

    IPermitAllowanceTransfer immutable permit2;
    SwapRouter public immutable router;

    constructor(IPermitAllowanceTransfer permit2_, SwapRouter router_) {
        permit2 = permit2_;
        router = router_;
    }

    function execute(
        address fromToken,
        uint256 amountIn,
        address toToken
    ) external {
        // get tokens from sender via permit2
        permit2.transferFrom(
            msg.sender,
            address(this),
            uint160(amountIn),
            fromToken
        );

        // swap to toToken and send back to sender
        IERC20(fromToken).safeApprove(address(router), type(uint256).max);
        router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: fromToken,
                tokenOut: toToken,
                fee: DEFAULT_FEE_TIER,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }
}
