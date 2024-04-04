// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

// inheriting
import {OwnableUpgradeable} from "@src/custom/OwnableUpgradeable.sol";
import {IRescueAirdrop} from "@src/interfaces/IRescueAirdrop.sol";

// libs
import {SafeERC20Upgradeable, IERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

/**
 * @title Rescue Airdrop
 * @author @apoorvlathey
 *
 * @notice Beacon Proxy implementation that allows to transfer ERC20 tokens stuck in a address, where this contract would eventually be deployed.
 */
contract RescueAirdropUpgradeable is OwnableUpgradeable, IRescueAirdrop {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function __RescueAirdrop_init() external override initializer {
        // owner is the factory that'll deploy this contract
        __Ownable_init();
    }

    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) external override onlyOwner {
        IERC20Upgradeable(token).safeTransfer(to, amount);
    }
}
