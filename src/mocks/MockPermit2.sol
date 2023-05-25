// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPermitAllowanceTransfer} from "@src/interfaces/IPermitAllowanceTransfer.sol";

contract MockPermit2 is IPermitAllowanceTransfer {
    using SafeERC20 for IERC20;

    /// @notice Maps users to tokens to spender addresses and information about the approval on the token
    /// @dev Indexed in the order of token owner address, token address, spender address
    /// @dev The stored word saves the allowed amount, expiration on the allowance, and nonce
    mapping(address => mapping(address => mapping(address => PackedAllowance)))
        public
        override allowance;

    function approve(
        address token,
        address spender,
        uint160 amount,
        uint48 expiration
    ) external override {
        PackedAllowance storage allowed = allowance[msg.sender][token][spender];

        // If the inputted expiration is 0, the allowance only lasts the duration of the block.
        allowed.expiration = expiration == 0
            ? uint48(block.timestamp)
            : expiration;
        allowed.amount = amount;
    }

    function transferFrom(
        address from,
        address to,
        uint160 amount,
        address token
    ) external {
        PackedAllowance storage allowed = allowance[from][token][msg.sender];

        if (block.timestamp > allowed.expiration) revert("AllowanceExpired");

        uint256 maxAmount = allowed.amount;
        if (maxAmount != type(uint160).max) {
            if (amount > maxAmount) {
                revert("InsufficientAllowance");
            } else {
                unchecked {
                    allowed.amount = uint160(maxAmount) - amount;
                }
            }
        }

        // Transfer the tokens from the from address to the recipient.
        IERC20(token).safeTransferFrom(from, to, amount);
    }
}
