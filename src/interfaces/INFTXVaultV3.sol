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
    event EnableTargetRedeemUpdated(bool enabled);
    event EnableTargetSwapUpdated(bool enabled);

    event Minted(uint256[] nftIds, uint256[] amounts, address to);
    event Redeemed(uint256[] specificIds, address to);
    event Swapped(
        uint256[] nftIds,
        uint256[] amounts,
        uint256[] specificIds,
        address to
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

    // =============================================================
    //                           INIT
    // =============================================================

    function __NFTXVault_init(
        string calldata _name,
        string calldata _symbol,
        address _assetAddress,
        bool _is1155,
        bool _allowAllItems
    ) external;

    // =============================================================
    //                     ONLY PRIVILEGED WRITE
    // =============================================================

    function finalizeVault() external;

    function setVaultMetadata(
        string memory name_,
        string memory symbol_
    ) external;

    function setVaultFeatures(
        bool _enableMint,
        bool _enableTargetRedeem,
        bool _enableTargetSwap
    ) external;

    function setFees(
        uint256 _mintFee,
        uint256 _targetRedeemFee,
        uint256 _targetSwapFee
    ) external;

    function disableVaultFees() external;

    // This function allows for an easy setup of any eligibility module contract from the EligibilityManager.
    // It takes in ABI encoded parameters for the desired module. This is to make sure they can all follow
    // a similar interface.
    function deployEligibilityStorage(
        uint256 moduleIndex,
        bytes calldata initData
    ) external returns (address);

    // The manager has control over options like fees and features
    function setManager(address _manager) external;

    function rescueTokens(IERC20Upgradeable token) external;

    function rescueERC721(
        IERC721Upgradeable nft,
        uint256[] calldata ids
    ) external;

    function rescueERC1155(
        IERC1155Upgradeable nft,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external;

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    function mint(
        uint256[] calldata tokenIds,
        uint256[] calldata amounts /* ignored for ERC721 vaults */
    ) external payable returns (uint256 vTokensMinted);

    function mintTo(
        uint256[] calldata tokenIds,
        uint256[] calldata amounts /* ignored for ERC721 vaults */,
        address to
    ) external payable returns (uint256 vTokensMinted);

    // TODO: add wethAmount option to other functions as well?
    function redeem(
        uint256[] calldata specificIds,
        uint256 wethAmount, // if vault fees should be deducted in WETH instead of ETH (msg.value should be 0 here)
        bool forceFees // deduct fees even if on the exclude list
    ) external payable returns (uint256 ethFees);

    function redeemTo(
        uint256[] calldata specificIds,
        address to,
        uint256 wethAmount, // if vault fees should be deducted in WETH instead of ETH (msg.value should be 0 here)
        bool forceFees // deduct fees even if on the exclude list
    ) external payable returns (uint256 ethFees);

    function swap(
        uint256[] calldata tokenIds,
        uint256[] calldata amounts /* ignored for ERC721 vaults */,
        uint256[] calldata specificIds,
        bool forceFees // deduct fees even if on the exclude list
    ) external payable returns (uint256 ethFees);

    function swapTo(
        uint256[] calldata tokenIds,
        uint256[] calldata amounts /* ignored for ERC721 vaults */,
        uint256[] calldata specificIds,
        address to,
        bool forceFees // deduct fees even if on the exclude list
    ) external payable returns (uint256 ethFees);

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

    function vaultFees()
        external
        view
        returns (uint256 mintFee, uint256 redeemFee, uint256 swapFee);

    function allValidNFTs(
        uint256[] calldata tokenIds
    ) external view returns (bool);

    function getVTokenPremium721(
        uint256 tokenId
    ) external view returns (uint256 premium, address depositor);

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

    // Calculate ETH amount corresponding to the vToken amount, calculated via TWAP from the AMM
    function vTokenToETH(uint256 vTokenAmount) external view returns (uint256);

    function depositInfo1155Length(
        uint256 tokenId
    ) external view returns (uint256);
}
