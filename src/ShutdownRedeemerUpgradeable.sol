// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

// inheriting
import {PausableUpgradeable} from "@src/custom/PausableUpgradeable.sol";

// libs
import {TransferLib} from "@src/lib/TransferLib.sol";

// interfaces
import {INFTXVaultFactoryV2} from "@src/v2/interfaces/INFTXVaultFactoryV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Shutdown Redeemer
 * @author @apoorvlathey
 *
 * @notice Allows users to exchange their vault tokens for ETH, after the vault shutdown.
 */
contract ShutdownRedeemerUpgradeable is PausableUpgradeable {
    // =============================================================
    //                           CONSTANTS
    // =============================================================

    uint256 constant PAUSE_REDEEM_LOCKID = 0;
    uint256 constant PRECISION = 1 ether;

    INFTXVaultFactoryV2 public immutable V2VaultFactory;

    // =============================================================
    //                          VARIABLES
    // =============================================================

    // vaultId -> ethPerVToken
    /// @notice Stores value multiplied by 10^18 (PRECISION)
    mapping(uint256 => uint256) public ethPerVToken;

    // =============================================================
    //                           EVENTS
    // =============================================================

    event Redeemed(
        uint256 indexed vaultId,
        uint256 vTokenAmount,
        uint256 ethAmount
    );
    event EthPerVTokenSet(uint256 indexed vaultId, uint256 value);

    // =============================================================
    //                           ERRORS
    // =============================================================

    error RedeemNotEnabled();
    error NoETHSent();

    // =============================================================
    //                         INIT
    // =============================================================

    constructor(INFTXVaultFactoryV2 V2VaultFactory_) {
        V2VaultFactory = V2VaultFactory_;
    }

    function __ShutdownRedeemer_init() external initializer {
        __Pausable_init();
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    /**
     * @notice Burn sender's vTokens by locking in this contract and redeem ETH in exchange
     *
     * @param vaultId The id of the vault
     * @param vTokenAmount Vault tokens amount to burn and redeem
     */
    function redeem(uint256 vaultId, uint256 vTokenAmount) external {
        onlyOwnerIfPaused(PAUSE_REDEEM_LOCKID);

        uint256 _ethPerVToken = ethPerVToken[vaultId];
        if (_ethPerVToken == 0) revert RedeemNotEnabled();

        // burn sender's vToken by locking in this contract
        address vToken = V2VaultFactory.vault(vaultId);
        IERC20(vToken).transferFrom(msg.sender, address(this), vTokenAmount);

        // transfer ETH to the sender in exchange
        uint256 ethToSend = (vTokenAmount * _ethPerVToken) / PRECISION;
        TransferLib.transferETH(msg.sender, ethToSend);

        emit Redeemed(vaultId, vTokenAmount, ethToSend);
    }

    // =============================================================
    //                        ONLY OWNER WRITE
    // =============================================================

    /**
     * @notice Add new vault for redemption. Send total ETH corresponding to the sale of all NFTs after the vault shutdown.
     *
     * @param vaultId The id of the vault
     */
    function addVaultForRedeem(uint256 vaultId) external payable onlyOwner {
        if (msg.value == 0) revert NoETHSent();

        address vToken = V2VaultFactory.vault(vaultId);
        uint256 vTokenTotalSupply = IERC20(vToken).totalSupply();

        uint256 _ethPerVToken = (msg.value * PRECISION) / vTokenTotalSupply;
        ethPerVToken[vaultId] = _ethPerVToken;

        emit EthPerVTokenSet(vaultId, _ethPerVToken);
    }

    /**
     * @notice Modify ethPerVToken
     *
     * @param vaultId The id of the vault
     * @param ethPerVToken_ New ethPerVToken value for the vault
     */
    function setEthPerVToken(
        uint256 vaultId,
        uint256 ethPerVToken_
    ) external payable onlyOwner {
        ethPerVToken[vaultId] = ethPerVToken_;

        emit EthPerVTokenSet(vaultId, ethPerVToken_);
    }

    /**
     * @notice Allows owner to withdraw ETH from the contract
     *
     * @param ethAmount Amount of ETH to withdraw
     */
    function recoverETH(uint256 ethAmount) external onlyOwner {
        TransferLib.transferETH(msg.sender, ethAmount);
    }

    // allow receiving more ETH externally
    receive() external payable {}
}
