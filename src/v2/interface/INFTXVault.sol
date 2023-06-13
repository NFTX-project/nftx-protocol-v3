// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../token/IERC20Upgradeable.sol";
import "./INFTXVaultFactory.sol";
import "./INFTXEligibility.sol";
import "../token/IERC721Upgradeable.sol";
import "../token/IERC1155Upgradeable.sol";

// TODO: organize using comment blocks
interface INFTXVault is IERC20Upgradeable {
    function manager() external view returns (address);

    function assetAddress() external view returns (address);

    function vaultFactory() external view returns (INFTXVaultFactory);

    function eligibilityStorage() external view returns (INFTXEligibility);

    function is1155() external view returns (bool);

    function allowAllItems() external view returns (bool);

    function enableMint() external view returns (bool);

    function vaultId() external view returns (uint256);

    function nftIdAt(uint256 holdingsIndex) external view returns (uint256);

    function allHoldings() external view returns (uint256[] memory);

    function totalHoldings() external view returns (uint256);

    function mintFee() external view returns (uint256);

    function targetRedeemFee() external view returns (uint256);

    function targetSwapFee() external view returns (uint256);

    function vaultFees() external view returns (uint256, uint256, uint256);

    function tokenDepositInfo(
        uint256 tokenId
    ) external view returns (uint48 timestamp, address depositor);

    struct TokenDepositInfo {
        uint48 timestamp;
        address depositor;
    }

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

    error InsufficientETHSent();
    error UnableToRefundETH();

    function __NFTXVault_init(
        string calldata _name,
        string calldata _symbol,
        address _assetAddress,
        bool _is1155,
        bool _allowAllItems
    ) external;

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

    function mint(
        uint256[] calldata tokenIds,
        uint256[] calldata amounts /* ignored for ERC721 vaults */
    ) external payable returns (uint256 nftCount);

    function mintTo(
        uint256[] calldata tokenIds,
        uint256[] calldata amounts /* ignored for ERC721 vaults */,
        address to
    ) external payable returns (uint256 nftCount);

    function redeem(
        uint256[] calldata specificIds
    ) external payable returns (uint256 ethFees);

    function redeemTo(
        uint256[] calldata specificIds,
        address to
    ) external payable returns (uint256 ethFees);

    function swap(
        uint256[] calldata tokenIds,
        uint256[] calldata amounts /* ignored for ERC721 vaults */,
        uint256[] calldata specificIds
    ) external payable returns (uint256 ethFees);

    function swapTo(
        uint256[] calldata tokenIds,
        uint256[] calldata amounts /* ignored for ERC721 vaults */,
        uint256[] calldata specificIds,
        address to
    ) external payable returns (uint256 ethFees);

    function allValidNFTs(
        uint256[] calldata tokenIds
    ) external view returns (bool);

    function getVTokenPremium(
        uint256 tokenId
    ) external view returns (uint256 premium, address depositor);

    // Calculate ETH amount corresponding to the vToken amount, calculated via TWAP from the AMM
    function vTokenToETH(uint256 vTokenAmount) external view returns (uint256);

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
}
