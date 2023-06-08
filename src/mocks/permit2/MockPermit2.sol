// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPermitAllowanceTransfer} from "@src/interfaces/IPermitAllowanceTransfer.sol";
import {EIP712} from "./EIP712.sol";
import {SignatureVerification} from "./SignatureVerification.sol";
import {PermitHash} from "./PermitHash.sol";
import {Allowance} from "./Allowance.sol";

contract MockPermit2 is EIP712 {
    using SignatureVerification for bytes;
    using PermitHash for IPermitAllowanceTransfer.PermitSingle;
    using Allowance for IPermitAllowanceTransfer.PackedAllowance;
    using SafeERC20 for IERC20;

    /// @notice Maps users to tokens to spender addresses and information about the approval on the token
    /// @dev Indexed in the order of token owner address, token address, spender address
    /// @dev The stored word saves the allowed amount, expiration on the allowance, and nonce
    mapping(address => mapping(address => mapping(address => IPermitAllowanceTransfer.PackedAllowance)))
        public allowance;

    /// @notice Thrown when validating an inputted signature that is stale
    /// @param signatureDeadline The timestamp at which a signature is no longer valid
    error SignatureExpired(uint256 signatureDeadline);

    /// @notice Thrown when validating that the inputted nonce has not been used
    error InvalidNonce();

    function approve(
        address token,
        address spender,
        uint160 amount,
        uint48 expiration
    ) external {
        IPermitAllowanceTransfer.PackedAllowance storage allowed = allowance[
            msg.sender
        ][token][spender];

        allowed.updateAmountAndExpiration(amount, expiration);
    }

    function permit(
        address owner,
        IPermitAllowanceTransfer.PermitSingle memory permitSingle,
        bytes calldata signature
    ) external {
        if (block.timestamp > permitSingle.sigDeadline)
            revert SignatureExpired(permitSingle.sigDeadline);

        // Verify the signer address from the signature.
        signature.verify(_hashTypedData(permitSingle.hash()), owner);

        _updateApproval(permitSingle.details, owner, permitSingle.spender);
    }

    function transferFrom(
        address from,
        address to,
        uint160 amount,
        address token
    ) external {
        IPermitAllowanceTransfer.PackedAllowance storage allowed = allowance[
            from
        ][token][msg.sender];

        if (block.timestamp > allowed.expiration)
            revert IPermitAllowanceTransfer.AllowanceExpired(
                allowed.expiration
            );

        uint256 maxAmount = allowed.amount;
        if (maxAmount != type(uint160).max) {
            if (amount > maxAmount) {
                revert IPermitAllowanceTransfer.InsufficientAllowance(
                    maxAmount
                );
            } else {
                unchecked {
                    allowed.amount = uint160(maxAmount) - amount;
                }
            }
        }

        // Transfer the tokens from the from address to the recipient.
        IERC20(token).safeTransferFrom(from, to, amount);
    }

    /// @notice Sets the new values for amount, expiration, and nonce.
    /// @dev Will check that the signed nonce is equal to the current nonce and then incrememnt the nonce value by 1.
    /// @dev Emits a Permit event.
    function _updateApproval(
        IPermitAllowanceTransfer.PermitDetails memory details,
        address owner,
        address spender
    ) private {
        uint48 nonce = details.nonce;
        address token = details.token;
        uint160 amount = details.amount;
        uint48 expiration = details.expiration;
        IPermitAllowanceTransfer.PackedAllowance storage allowed = allowance[
            owner
        ][token][spender];

        if (allowed.nonce != nonce) revert InvalidNonce();

        allowed.updateAll(amount, expiration, nonce);
    }
}
