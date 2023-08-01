// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";
import {INFTXEligibility} from "@src/interfaces/INFTXEligibility.sol";
import {IERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC721/IERC721Upgradeable.sol";
import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";
import {IERC1155Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC1155/IERC1155Upgradeable.sol";
import {IERC3156FlashBorrowerUpgradeable} from "@src/custom/tokens/ERC20/ERC20FlashMintUpgradeable.sol";

interface INFTXVaultV3 is IERC20Upgradeable {
    // =============================================================
    //                            STRUCTS
    // =============================================================

    struct TokenDepositInfo {
        uint48 timestamp;
        address depositor;
    }

    struct DepositInfo1155 {
        uint256 qty;
        address depositor;
        uint48 timestamp;
    }

    enum TokenType {
        ERC20,
        ERC721,
        ERC1155
    }

    // =============================================================
    //                           CONSTANTS
    // =============================================================

    function WETH() external view returns (IWETH9);

    // only set during initialization

    function assetAddress() external view returns (address);

    function vaultFactory() external view returns (INFTXVaultFactoryV3);

    function vaultId() external view returns (uint256);

    function is1155() external view returns (bool);

    // =============================================================
    //                          VARIABLES
    // =============================================================

    function manager() external view returns (address);

    function eligibilityStorage() external view returns (INFTXEligibility);

    function allowAllItems() external view returns (bool);

    function enableMint() external view returns (bool);

    function tokenDepositInfo(
        uint256 tokenId
    ) external view returns (uint48 timestamp, address depositor);

    function depositInfo1155(
        uint256 tokenId,
        uint256 index
    ) external view returns (uint256 qty, address depositor, uint48 timestamp);

    function pointerIndex1155(uint256 tokenId) external view returns (uint256);

    // =============================================================
    //                            EVENTS
    // =============================================================

    event VaultInit(
        uint256 indexed vaultId,
        address assetAddress,
        bool is1155,
        bool allowAllItems
    );

    event ManagerSet(address manager);
    event EligibilityDeployed(uint256 moduleIndex, address eligibilityAddr);
    // event CustomEligibilityDeployed(address eligibilityAddr);

    event EnableMintUpdated(bool enabled);
    event EnableRedeemUpdated(bool enabled);
    event EnableSwapUpdated(bool enabled);

    event Minted(uint256[] nftIds, uint256[] amounts, address to);
    event Redeemed(uint256[] specificIds, address to);
    event Swapped(
        uint256[] nftIds,
        uint256[] amounts,
        uint256[] specificIds,
        address to
    );
    event PremiumShared(address depositor, uint256 wethPremium);
    event VaultShutdown(
        address assetAddress,
        uint256 numItems,
        address recipient
    );

    // =============================================================
    //                            ERRORS
    // =============================================================

    error ZeroAddress();
    error MintingDisabled();
    error InsufficientETHSent();
    error TransferAmountIsZero();
    error TokenLengthMismatch();
    error EligibilityAlreadySet();
    error NotEligible();
    error NotNFTOwner();
    error NFTAlreadyOwned();
    error NotOwner();
    error NotManager();
    error Paused();
    error TooManyItems();
    error InvalidToken();
    error PremiumLimitExceeded();

    // =============================================================
    //                           INIT
    // =============================================================

    function __NFTXVault_init(
        string calldata name_,
        string calldata symbol_,
        address assetAddress_,
        bool is1155_,
        bool allowAllItems_
    ) external;

    // =============================================================
    //                     ONLY PRIVILEGED WRITE
    // =============================================================

    /**
     * @notice Sets manager to zero address
     */
    function finalizeVault() external;

    function setVaultMetadata(
        string memory name_,
        string memory symbol_
    ) external;

    function setVaultFeatures(
        bool enableMint_,
        bool enableRedeem_,
        bool enableSwap_
    ) external;

    function setFees(
        uint256 mintFee_,
        uint256 redeemFee_,
        uint256 swapFee_
    ) external;

    /**
     * @notice Disables custom vault fees. Vault fees reverts back to the global vault fees.
     */
    function disableVaultFees() external;

    /**
     * @notice Allows for an easy setup of any eligibility module contract from the EligibilityManager.
     *
     * @param moduleIndex Index of the module to deploy
     * @param initData ABI encoded parameters for the desired module
     */
    function deployEligibilityStorage(
        uint256 moduleIndex,
        bytes calldata initData
    ) external returns (address);

    /**
     * @notice Set new manager. The manager has control over options like fees and features
     */
    function setManager(address _manager) external;

    // =============================================================
    //                     ONLY OWNER WRITE
    // =============================================================

    function rescueTokens(
        TokenType tt,
        address token,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external;

    function shutdown(address recipient, uint256[] calldata tokenIds) external;

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    /**
     * @notice Mints vault tokens in exchange for depositing NFTs. Mint fees is paid in ETH (via msg.value)
     *
     * @param tokenIds The token ids to deposit
     * @param amounts For ERC1155: quantity corresponding to each tokenId to deposit
     * @param depositor Depositor address that should receive premiums for the `tokenIds` deposited here
     * @param to Recipient address for the vTokens
     */
    function mint(
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        address depositor,
        address to
    ) external payable returns (uint256 vTokensMinted);

    /**
     * @notice Redeem vault tokens for the underlying NFTs. Redeem fees is paid in ETH (via msg.value) or WETH
     *
     * @param idsOut NFT ids to withdraw
     * @param to Recipient address for the NFTs
     * @param wethAmount if vault fees should be deducted in WETH instead of ETH (msg.value should be 0 here)
     * @param vTokenPremiumLimit The max net premium in vTokens the user is willing to pay, else tx reverts
     * @param forceFees forcefully deduct fees even if sender is on the exclude list
     *
     * @return ethFees The ETH fees charged
     */
    function redeem(
        uint256[] calldata idsOut,
        address to,
        uint256 wethAmount,
        uint256 vTokenPremiumLimit,
        bool forceFees
    ) external payable returns (uint256 ethFees);

    /**
     * @notice Swap `idsIn` of NFTs into `idsOut` from the vault. Swap fees is paid in ETH (via msg.value)
     *
     * @param idsIn NFT ids to sell
     * @param amounts For ERC1155: quantity corresponding to each tokenId to sell
     * @param idsOut NFT ids to buy
     * @param depositor Depositor address that should receive premiums for the `idsIn` deposited here
     * @param to Recipient address for the NFTs
     * @param vTokenPremiumLimit The max net premium in vTokens the user is willing to pay, else tx reverts
     * @param forceFees forcefully deduct fees even if sender is on the exclude list
     *
     * @return ethFees The ETH fees charged
     */
    function swap(
        uint256[] calldata idsIn,
        uint256[] calldata amounts,
        uint256[] calldata idsOut,
        address depositor,
        address to,
        uint256 vTokenPremiumLimit,
        bool forceFees
    ) external payable returns (uint256 ethFees);

    /**
     * @notice Performs a flash loan. New tokens are minted and sent to the
     * `receiver`, who is required to implement the {IERC3156FlashBorrower}
     * interface. By the end of the flash loan, the receiver is expected to own
     * amount + fee tokens and have them approved back to the token contract itself so
     * they can be burned.
     *
     * @param receiver The receiver of the flash loan. Should implement the
     * {IERC3156FlashBorrower-onFlashLoan} interface.
     * @param token The token to be flash loaned. Only `address(this)` is
     * supported.
     * @param amount The amount of tokens to be loaned.
     * @param data An arbitrary datafield that is passed to the receiver.
     *
     * @return `true` if the flash loan was successful.
     */
    function flashLoan(
        IERC3156FlashBorrowerUpgradeable receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bool);

    // =============================================================
    //                     PUBLIC / EXTERNAL VIEW
    // =============================================================

    function nftIdAt(uint256 holdingsIndex) external view returns (uint256);

    function allHoldings() external view returns (uint256[] memory);

    function totalHoldings() external view returns (uint256);

    /**
     * @notice Vault Fees in terms of vault tokens
     */
    function vaultFees()
        external
        view
        returns (uint256 mintFee, uint256 redeemFee, uint256 swapFee);

    function allValidNFTs(
        uint256[] calldata tokenIds
    ) external view returns (bool);

    /**
     * @notice Get vToken premium corresponding for a tokenId in the vault
     *
     * @param tokenId token id to calculate the premium for
     * @return premium Premium in vTokens
     * @return depositor Depositor that receives a share of this premium
     */
    function getVTokenPremium721(
        uint256 tokenId
    ) external view returns (uint256 premium, address depositor);

    /**
     * @notice Get vToken premium corresponding for a tokenId in the vault
     *
     * @param tokenId token id to calculate the premium for
     * @param amount ERC1155 amount of tokenId to redeem
     *
     * @return netPremium Net premium in vTokens
     * @return premiums Premiums corresponding to each depositor
     * @return depositors Depositors that receive a share from the `premiums`
     */
    function getVTokenPremium1155(
        uint256 tokenId,
        uint256 amount
    )
        external
        view
        returns (
            uint256 netPremium,
            uint256[] memory premiums,
            address[] memory depositors
        );

    /**
     * @notice Calculate ETH amount corresponding to a given vToken amount, calculated via TWAP from the NFTX AMM
     */
    function vTokenToETH(uint256 vTokenAmount) external view returns (uint256);

    /**
     * @notice Length of depositInfo1155 array for a given `tokenId`
     */
    function depositInfo1155Length(
        uint256 tokenId
    ) external view returns (uint256);

    function version() external pure returns (string memory);
}
