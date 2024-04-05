// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// inheriting
import {Pausable} from "@src/custom/Pausable.sol";

// interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title V3 Migrate Swap
 * @author @apoorvlathey
 *
 * @notice Swap v2 -> v3 NFTX vault tokens 1:1
 */
contract V3MigrateSwap is Pausable {
    // constants
    uint256 constant SWAP_LOCK_ID = 0;

    // storage
    // v2 vault token => v3 address
    mapping(address => address) public v2ToV3VToken;

    // events
    event Swapped(address v2VToken, uint256 amount);
    event V2ToV3MappingSet(address v2VToken, address v3VToken);

    // errors
    error SwapNotEnabledForVault();

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    function swap(address v2VToken, uint256 amount) external {
        onlyOwnerIfPaused(SWAP_LOCK_ID);

        address v3VToken = v2ToV3VToken[v2VToken];
        if (v3VToken == address(0)) revert SwapNotEnabledForVault();

        // pull v2 tokens to this contract
        IERC20(v2VToken).transferFrom(msg.sender, address(this), amount);

        // transfer equal v3 tokens to the caller
        IERC20(v3VToken).transfer(msg.sender, amount);

        emit Swapped(v2VToken, amount);
    }

    // =============================================================
    //                        ONLY OWNER WRITE
    // =============================================================

    function setV2ToV3Mapping(
        address v2VToken,
        address v3VToken
    ) external onlyOwner {
        v2ToV3VToken[v2VToken] = v3VToken;
        emit V2ToV3MappingSet(v2VToken, v3VToken);
    }

    function rescueTokens(IERC20 token) external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        token.transfer(msg.sender, balance);
    }
}
