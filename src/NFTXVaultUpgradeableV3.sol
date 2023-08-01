// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// inheriting
import {OwnableUpgradeable} from "@src/custom/OwnableUpgradeable.sol";
import {ERC721HolderUpgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import {ERC1155HolderUpgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {ERC20FlashMintUpgradeable, IERC3156FlashBorrowerUpgradeable} from "@src/custom/tokens/ERC20/ERC20FlashMintUpgradeable.sol";

// libs
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {TransferLib} from "@src/lib/TransferLib.sol";
import {FixedPoint96} from "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import {ExponentialPremium} from "@src/lib/ExponentialPremium.sol";
import {SafeERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {EnumerableSetUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/structs/EnumerableSetUpgradeable.sol";

// interfaces
import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";
import {INFTXRouter} from "@src/interfaces/INFTXRouter.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INFTXEligibility} from "@src/interfaces/INFTXEligibility.sol";
import {IERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC721/IERC721Upgradeable.sol";
import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";
import {IERC1155Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC1155/IERC1155Upgradeable.sol";
import {INFTXFeeDistributorV3} from "@src/interfaces/INFTXFeeDistributorV3.sol";
import {INFTXEligibilityManager} from "@src/interfaces/INFTXEligibilityManager.sol";

import {INFTXVaultV3} from "@src/interfaces/INFTXVaultV3.sol";

// Authors: @apoorvlathey, @0xKiwi_ and @alexgausman

contract NFTXVaultUpgradeableV3 is
    INFTXVaultV3,
    OwnableUpgradeable,
    ERC20FlashMintUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable,
    ERC1155HolderUpgradeable
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // =============================================================
    //                           CONSTANTS
    // =============================================================

    uint256 constant BASE = 10 ** 18;
    IWETH9 public immutable override WETH;
    address constant CRYPTO_PUNKS = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;
    address constant CRYPTO_KITTIES =
        0x06012c8cf97BEaD5deAe237070F9587f8E7A266d;

    // "constants": only set during initialization

    address public override assetAddress;
    INFTXVaultFactoryV3 public override vaultFactory;
    uint256 public override vaultId;
    bool public override is1155;

    // =============================================================
    //                            VARIABLES
    // =============================================================

    address public override manager;

    INFTXEligibility public override eligibilityStorage;

    bool public override allowAllItems;
    bool public override enableMint;
    bool public override enableRedeem;
    bool public override enableSwap;

    EnumerableSetUpgradeable.UintSet internal _holdings;
    // tokenId => qty
    mapping(uint256 => uint256) internal _quantity1155;

    // tokenId => info
    mapping(uint256 => TokenDepositInfo) public override tokenDepositInfo;

    /**
     * For ERC1155 deposits, per TokenId:
     *
     *                          pointerIndex1155
     *                                |
     *                                V
     * [{qty: 0, depositor: A}, {qty: 5, depositor: B}, {qty: 10, depositor: C}, ...]
     *
     * New deposits are pushed to the end of array, and the oldest remaining deposit is used while withdrawing, hence following FIFO.
     */

    // tokenId => info[]
    mapping(uint256 => DepositInfo1155[]) public override depositInfo1155;
    // tokenId => pointerIndex
    mapping(uint256 => uint256) public override pointerIndex1155;

    // =============================================================
    //                           INIT
    // =============================================================

    constructor(IWETH9 WETH_) {
        WETH = WETH_;
    }

    function __NFTXVault_init(
        string calldata name_,
        string calldata symbol_,
        address assetAddress_,
        bool is1155_,
        bool allowAllItems_
    ) public override initializer {
        __Ownable_init();
        __ERC20_init(name_, symbol_);

        if (assetAddress_ == address(0)) revert ZeroAddress();
        assetAddress = assetAddress_;
        vaultFactory = INFTXVaultFactoryV3(msg.sender);
        vaultId = vaultFactory.numVaults();
        is1155 = is1155_;
        allowAllItems = allowAllItems_;

        emit VaultInit(vaultId, assetAddress_, is1155_, allowAllItems_);

        setVaultFeatures(
            true /*enableMint*/,
            true /*enableRedeem*/,
            true /*enableSwap*/
        );
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL WRITE
    // =============================================================

    /**
     * @inheritdoc INFTXVaultV3
     */
    function mint(
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        address depositor,
        address to
    ) public payable override nonReentrant returns (uint256 vTokensMinted) {
        _onlyOwnerIfPaused(1);
        if (!enableMint) revert MintingDisabled();

        // Take the NFTs.
        uint256 nftCount = _receiveNFTs(depositor, tokenIds, amounts);
        vTokensMinted = BASE * nftCount;

        // Mint to the user.
        _mint(to, vTokensMinted);

        (uint256 mintFee, , ) = vaultFees();
        uint256 totalVTokenFee = mintFee * nftCount;
        uint256 ethFees = _chargeAndDistributeFees(totalVTokenFee, msg.value);

        _refundETH(msg.value, ethFees);

        emit Minted(tokenIds, amounts, to);
    }

    /**
     * @inheritdoc INFTXVaultV3
     */
    function redeem(
        uint256[] calldata idsOut,
        address to,
        uint256 wethAmount,
        bool forceFees
    ) public payable override nonReentrant returns (uint256 ethFees) {
        _onlyOwnerIfPaused(2);
        if (!enableRedeem) revert RedeemDisabled();

        uint256 ethOrWethAmt;
        if (wethAmount > 0) {
            require(msg.value == 0);

            ethOrWethAmt = wethAmount;
        } else {
            ethOrWethAmt = msg.value;
        }

        uint256 count = idsOut.length;

        // burn from the sender.
        _burn(msg.sender, BASE * count);

        (, uint256 redeemFee, ) = vaultFees();
        uint256 totalVaultFee = (redeemFee * count);

        // Withdraw from vault.
        INFTXVaultFactoryV3 _vaultFactory = vaultFactory;
        bool deductFees = forceFees ||
            !_vaultFactory.excludedFromFees(msg.sender);
        (
            uint256 netVTokenPremium,
            uint256[] memory vTokenPremiums,
            address[] memory depositors
        ) = _withdrawNFTsTo(idsOut, to, deductFees, _vaultFactory);

        if (deductFees) {
            ethFees = _chargeAndDistributeFeesForRedeem(
                ethOrWethAmt,
                msg.value > 0,
                totalVaultFee,
                netVTokenPremium,
                vTokenPremiums,
                depositors
            );
        }

        if (msg.value > 0) {
            _refundETH(msg.value, ethFees);
        }

        emit Redeemed(idsOut, to);
    }

    /**
     * @inheritdoc INFTXVaultV3
     */
    function swap(
        uint256[] calldata idsIn,
        uint256[] calldata amounts,
        uint256[] calldata idsOut,
        address depositor,
        address to,
        bool forceFees
    ) public payable override nonReentrant returns (uint256 ethFees) {
        _onlyOwnerIfPaused(3);
        if (!enableSwap) revert SwapDisabled();

        {
            uint256 count;
            if (is1155) {
                for (uint256 i; i < idsIn.length; ++i) {
                    if (amounts[i] == 0) revert TransferAmountIsZero();
                    count += amounts[i];
                }
            } else {
                count = idsIn.length;
            }

            if (count != idsOut.length) revert TokenLengthMismatch();
        }

        {
            (, , uint256 swapFee) = vaultFees();
            uint256 totalVaultFee = (swapFee * idsOut.length);

            // Give the NFTs first, so the user wont get the same thing back.
            INFTXVaultFactoryV3 _vaultFactory = vaultFactory;
            bool deductFees = forceFees ||
                !_vaultFactory.excludedFromFees(msg.sender);
            (
                uint256 netVTokenPremium,
                uint256[] memory vTokenPremiums,
                address[] memory depositors
            ) = _withdrawNFTsTo(idsOut, to, deductFees, _vaultFactory);

            if (deductFees) {
                ethFees = _chargeAndDistributeFeesForRedeem(
                    msg.value,
                    true,
                    totalVaultFee,
                    netVTokenPremium,
                    vTokenPremiums,
                    depositors
                );
            }
        }

        _receiveNFTs(depositor, idsIn, amounts);

        _refundETH(msg.value, ethFees);

        emit Swapped(idsIn, amounts, idsOut, to);
    }

    /**
     * @inheritdoc INFTXVaultV3
     */
    function flashLoan(
        IERC3156FlashBorrowerUpgradeable receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) public override(ERC20FlashMintUpgradeable, INFTXVaultV3) returns (bool) {
        _onlyOwnerIfPaused(4);
        return super.flashLoan(receiver, token, amount, data);
    }

    // =============================================================
    //                     ONLY PRIVILEGED WRITE
    // =============================================================

    /**
     * @inheritdoc INFTXVaultV3
     */
    function finalizeVault() external override {
        _onlyPrivileged();
        setManager(address(0));
    }

    /**
     * @inheritdoc INFTXVaultV3
     */
    function setVaultMetadata(
        string calldata name_,
        string calldata symbol_
    ) external override {
        _onlyPrivileged();
        _setMetadata(name_, symbol_);
    }

    /**
     * @inheritdoc INFTXVaultV3
     */
    function setVaultFeatures(
        bool enableMint_,
        bool enableRedeem_,
        bool enableSwap_
    ) public override {
        _onlyPrivileged();
        enableMint = enableMint_;
        enableRedeem = enableRedeem_;
        enableSwap = enableSwap_;

        emit EnableMintUpdated(enableMint_);
        emit EnableRedeemUpdated(enableRedeem_);
        emit EnableSwapUpdated(enableSwap_);
    }

    /**
     * @inheritdoc INFTXVaultV3
     */
    function setFees(
        uint256 mintFee_,
        uint256 redeemFee_,
        uint256 swapFee_
    ) public override {
        _onlyPrivileged();
        vaultFactory.setVaultFees(vaultId, mintFee_, redeemFee_, swapFee_);
    }

    /**
     * @inheritdoc INFTXVaultV3
     */
    function disableVaultFees() public override {
        _onlyPrivileged();
        vaultFactory.disableVaultFees(vaultId);
    }

    /**
     * @inheritdoc INFTXVaultV3
     */
    function deployEligibilityStorage(
        uint256 moduleIndex,
        bytes calldata initData
    ) external override returns (address) {
        _onlyPrivileged();
        if (address(eligibilityStorage) != address(0))
            revert EligibilityAlreadySet();

        INFTXEligibilityManager eligManager = INFTXEligibilityManager(
            vaultFactory.eligibilityManager()
        );
        address _eligibility = eligManager.deployEligibility(
            moduleIndex,
            initData
        );
        eligibilityStorage = INFTXEligibility(_eligibility);
        // Toggle this to let the contract know to check eligibility now.
        allowAllItems = false;
        emit EligibilityDeployed(moduleIndex, _eligibility);
        return _eligibility;
    }

    // // This function allows for the manager to set their own arbitrary eligibility contract.
    // // Once eligiblity is set, it cannot be unset or changed.
    // Disabled for launch.
    // function setEligibilityStorage(address _newEligibility) public {
    //     onlyPrivileged();
    //     require(
    //         address(eligibilityStorage) == address(0),
    //         "NFTXVault: eligibility already set"
    //     );
    //     eligibilityStorage = INFTXEligibility(_newEligibility);
    //     // Toggle this to let the contract know to check eligibility now.
    //     allowAllItems = false;
    //     emit CustomEligibilityDeployed(address(_newEligibility));
    // }

    /**
     * @inheritdoc INFTXVaultV3
     */
    function setManager(address manager_) public override {
        _onlyPrivileged();
        manager = manager_;
        emit ManagerSet(manager_);
    }

    // =============================================================
    //                     ONLY OWNER WRITE
    // =============================================================

    /**
     * @inheritdoc INFTXVaultV3
     */
    function rescueTokens(
        TokenType tt,
        address token,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external onlyOwner {
        require(address(token) != assetAddress);

        if (tt == TokenType.ERC20) {
            uint256 balance = IERC20Upgradeable(token).balanceOf(address(this));
            IERC20Upgradeable(token).safeTransfer(msg.sender, balance);
        } else if (tt == TokenType.ERC721) {
            for (uint256 i; i < ids.length; ++i) {
                IERC721Upgradeable(token).safeTransferFrom(
                    address(this),
                    msg.sender,
                    ids[i]
                );
            }
        } else {
            IERC1155Upgradeable(token).safeBatchTransferFrom(
                address(this),
                msg.sender,
                ids,
                amounts,
                ""
            );
        }
    }

    function shutdown(
        address recipient,
        uint256[] calldata tokenIds
    ) external override onlyOwner {
        uint256 numItems = totalSupply() / BASE;
        if (numItems > 4) revert TooManyItems();

        _withdrawNFTsTo(tokenIds, recipient, false, vaultFactory);

        emit VaultShutdown(assetAddress, numItems, recipient);
        assetAddress = address(0);
    }

    // =============================================================
    //                     PUBLIC / EXTERNAL VIEW
    // =============================================================

    /**
     * @inheritdoc INFTXVaultV3
     */
    function vaultFees()
        public
        view
        override
        returns (uint256 mintFee, uint256 redeemFee, uint256 swapFee)
    {
        return vaultFactory.vaultFees(vaultId);
    }

    /**
     * @inheritdoc INFTXVaultV3
     */
    function allValidNFTs(
        uint256[] memory tokenIds
    ) public view override returns (bool) {
        if (allowAllItems) {
            return true;
        }

        INFTXEligibility _eligibilityStorage = eligibilityStorage;
        if (address(_eligibilityStorage) == address(0)) {
            return false;
        }
        return _eligibilityStorage.checkAllEligible(tokenIds);
    }

    /**
     * @inheritdoc INFTXVaultV3
     */
    function nftIdAt(
        uint256 holdingsIndex
    ) external view override returns (uint256) {
        return _holdings.at(holdingsIndex);
    }

    /**
     * @inheritdoc INFTXVaultV3
     */
    function allHoldings() external view override returns (uint256[] memory) {
        uint256 len = _holdings.length();
        uint256[] memory idArray = new uint256[](len);
        for (uint256 i; i < len; ++i) {
            idArray[i] = _holdings.at(i);
        }
        return idArray;
    }

    /**
     * @inheritdoc INFTXVaultV3
     */
    function totalHoldings() external view override returns (uint256) {
        return _holdings.length();
    }

    /**
     * @inheritdoc INFTXVaultV3
     */
    function version() external pure override returns (string memory) {
        return "v3.0.0";
    }

    /**
     * @inheritdoc INFTXVaultV3
     */
    function getVTokenPremium721(
        uint256 tokenId
    ) external view override returns (uint256 premium, address depositor) {
        TokenDepositInfo memory depositInfo = tokenDepositInfo[tokenId];
        depositor = depositInfo.depositor;

        uint256 premiumMax = vaultFactory.premiumMax();
        uint256 premiumDuration = vaultFactory.premiumDuration();

        premium = _getVTokenPremium(
            depositInfo.timestamp,
            premiumMax,
            premiumDuration
        );
    }

    /**
     * @inheritdoc INFTXVaultV3
     */
    function getVTokenPremium1155(
        uint256 tokenId,
        uint256 amount
    )
        external
        view
        override
        returns (
            uint256 netPremium,
            uint256[] memory premiums,
            address[] memory depositors
        )
    {
        require(amount > 0);

        // max possible array lengths
        premiums = new uint256[](amount);
        depositors = new address[](amount);

        uint256 _pointerIndex1155 = pointerIndex1155[tokenId];

        uint256 i = _pointerIndex1155;
        // cache
        uint256 premiumMax = vaultFactory.premiumMax();
        uint256 premiumDuration = vaultFactory.premiumDuration();
        while (true) {
            DepositInfo1155 memory depositInfo = depositInfo1155[tokenId][i];

            if (depositInfo.qty > amount) {
                uint256 vTokenPremium = _getVTokenPremium(
                    depositInfo.timestamp,
                    premiumMax,
                    premiumDuration
                ) * amount;
                netPremium += vTokenPremium;

                premiums[i] = vTokenPremium;
                depositors[i] = depositInfo.depositor;

                // end loop
                break;
            } else {
                amount -= depositInfo.qty;

                uint256 vTokenPremium = _getVTokenPremium(
                    depositInfo.timestamp,
                    premiumMax,
                    premiumDuration
                ) * depositInfo.qty;
                netPremium += vTokenPremium;

                premiums[i] = vTokenPremium;
                depositors[i] = depositInfo.depositor;

                unchecked {
                    ++i;
                }
            }
        }

        uint256 finalArrayLength = i - _pointerIndex1155 + 1;

        if (finalArrayLength < premiums.length) {
            // change array length
            assembly {
                mstore(premiums, finalArrayLength)
                mstore(depositors, finalArrayLength)
            }
        }
    }

    /**
     * @inheritdoc INFTXVaultV3
     */
    function vTokenToETH(
        uint256 vTokenAmount
    ) external view override returns (uint256 ethAmount) {
        (ethAmount, ) = _vTokenToETH(vaultFactory, vTokenAmount);
    }

    /**
     * @inheritdoc INFTXVaultV3
     */
    function depositInfo1155Length(
        uint256 tokenId
    ) external view override returns (uint256) {
        return depositInfo1155[tokenId].length;
    }

    // =============================================================
    //                        INTERNAL HELPERS
    // =============================================================

    // We set a hook to the eligibility module (if it exists) after redeems in case anything needs to be modified.
    function _afterRedeemHook(uint256[] memory tokenIds) internal {
        INFTXEligibility _eligibilityStorage = eligibilityStorage;
        if (address(_eligibilityStorage) == address(0)) {
            return;
        }
        _eligibilityStorage.afterRedeemHook(tokenIds);
    }

    function _receiveNFTs(
        address depositor,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) internal returns (uint256) {
        if (!allValidNFTs(tokenIds)) revert NotEligible();

        if (!is1155) {
            address _assetAddress = assetAddress;
            for (uint256 i; i < tokenIds.length; ++i) {
                uint256 tokenId = tokenIds[i];
                // We may already own the NFT here so we check in order:
                // Does the vault own it?
                //   - If so, check if its in holdings list
                //      - If so, we reject. This means the NFT has already been claimed for.
                //      - If not, it means we have not yet accounted for this NFT, so we continue.
                //   -If not, we "pull" it from the msg.sender and add to holdings.
                _transferFromERC721(_assetAddress, tokenId);
                _holdings.add(tokenId);
                tokenDepositInfo[tokenId] = TokenDepositInfo({
                    timestamp: uint48(block.timestamp),
                    depositor: depositor
                });
            }
            return tokenIds.length;
        } else {
            // This is technically a check, so placing it before the effect.
            IERC1155Upgradeable(assetAddress).safeBatchTransferFrom(
                msg.sender,
                address(this),
                tokenIds,
                amounts,
                ""
            );

            uint256 count;
            for (uint256 i; i < tokenIds.length; ++i) {
                uint256 tokenId = tokenIds[i];
                uint256 amount = amounts[i];

                if (amount == 0) revert TransferAmountIsZero();

                if (_quantity1155[tokenId] == 0) {
                    _holdings.add(tokenId);
                }
                _quantity1155[tokenId] += amount;
                count += amount;

                depositInfo1155[tokenId].push(
                    DepositInfo1155({
                        qty: amount,
                        depositor: depositor,
                        timestamp: uint48(block.timestamp)
                    })
                );
            }
            return count;
        }
    }

    function _withdrawNFTsTo(
        uint256[] memory specificIds,
        address to,
        bool deductFees,
        INFTXVaultFactoryV3 _vaultFactory
    )
        internal
        returns (
            uint256 netVTokenPremium,
            uint256[] memory vTokenPremiums,
            address[] memory depositors
        )
    {
        // cache
        bool _is1155 = is1155;
        address _assetAddress = assetAddress;

        uint256 premiumMax;
        uint256 premiumDuration;

        if (deductFees) {
            premiumMax = _vaultFactory.premiumMax();
            premiumDuration = _vaultFactory.premiumDuration();

            vTokenPremiums = new uint256[](specificIds.length);
            depositors = new address[](specificIds.length);
        }

        for (uint256 i; i < specificIds.length; ++i) {
            uint256 tokenId = specificIds[i];

            if (_is1155) {
                uint256 _qty1155 = _quantity1155[tokenId];
                _quantity1155[tokenId] = _qty1155 - 1;
                // updated _quantity1155 is 0 now, so remove from holdings
                if (_qty1155 == 1) {
                    _holdings.remove(tokenId);
                }

                IERC1155Upgradeable(_assetAddress).safeTransferFrom(
                    address(this),
                    to,
                    tokenId,
                    1,
                    ""
                );

                uint256 _pointerIndex1155 = pointerIndex1155[tokenId];
                DepositInfo1155 storage depositInfo = depositInfo1155[tokenId][
                    _pointerIndex1155
                ];
                uint256 _qty = depositInfo.qty;

                depositInfo.qty = _qty - 1;

                // if it was the last nft from this deposit
                if (_qty == 1) {
                    pointerIndex1155[tokenId] = _pointerIndex1155 + 1;
                }

                if (deductFees) {
                    uint256 vTokenPremium = _getVTokenPremium(
                        depositInfo.timestamp,
                        premiumMax,
                        premiumDuration
                    );
                    netVTokenPremium += vTokenPremium;

                    vTokenPremiums[i] = vTokenPremium;
                    depositors[i] = depositInfo.depositor;
                }
            } else {
                if (deductFees) {
                    TokenDepositInfo memory depositInfo = tokenDepositInfo[
                        tokenId
                    ];

                    uint256 vTokenPremium = _getVTokenPremium(
                        depositInfo.timestamp,
                        premiumMax,
                        premiumDuration
                    );
                    netVTokenPremium += vTokenPremium;

                    vTokenPremiums[i] = vTokenPremium;
                    depositors[i] = depositInfo.depositor;
                }

                _holdings.remove(tokenId);
                _transferERC721(_assetAddress, to, tokenId);
            }
        }
        _afterRedeemHook(specificIds);
    }

    /// @dev Uses TWAP to calculate fees `ethAmount` corresponding to the given `vTokenAmount`
    /// Returns 0 if pool doesn't exist or sender is excluded from fees.
    function _chargeAndDistributeFees(
        uint256 vTokenFeeAmount,
        uint256 ethReceived
    ) internal returns (uint256 ethAmount) {
        // cache
        INFTXVaultFactoryV3 _vaultFactory = vaultFactory;

        if (_vaultFactory.excludedFromFees(msg.sender)) {
            return 0;
        }

        INFTXFeeDistributorV3 feeDistributor;
        (ethAmount, feeDistributor) = _vTokenToETH(
            _vaultFactory,
            vTokenFeeAmount
        );

        if (ethAmount > 0) {
            if (ethReceived < ethAmount) revert InsufficientETHSent();

            WETH.deposit{value: ethAmount}();
            WETH.transfer(address(feeDistributor), ethAmount);
            feeDistributor.distribute(vaultId);
        }
    }

    function _chargeAndDistributeFeesForRedeem(
        uint256 ethOrWethReceived,
        bool isETH,
        uint256 totalVaultFees,
        uint256 netVTokenPremium,
        uint256[] memory vTokenPremiums,
        address[] memory depositors
    ) internal returns (uint256 ethAmount) {
        uint256 vaultETHFees;
        INFTXFeeDistributorV3 feeDistributor;
        (vaultETHFees, feeDistributor) = _vTokenToETH(
            vaultFactory,
            totalVaultFees
        );

        if (vaultETHFees > 0) {
            uint256 netETHPremium;
            uint256 netETHPremiumForDepositors;
            if (netVTokenPremium > 0) {
                netETHPremium =
                    (vaultETHFees * netVTokenPremium) /
                    totalVaultFees;
                netETHPremiumForDepositors =
                    (netETHPremium * vaultFactory.depositorPremiumShare()) /
                    1 ether;
            }
            ethAmount = vaultETHFees + netETHPremium;

            if (ethOrWethReceived < ethAmount) revert InsufficientETHSent();

            if (isETH) {
                WETH.deposit{value: ethAmount}();
            } else {
                // pull only required weth from sender
                WETH.transferFrom(msg.sender, address(this), ethAmount);
            }

            WETH.transfer(
                address(feeDistributor),
                ethAmount - netETHPremiumForDepositors
            );
            feeDistributor.distribute(vaultId);

            for (uint256 i; i < vTokenPremiums.length; ) {
                if (vTokenPremiums[i] > 0) {
                    uint256 wethPremium = (netETHPremiumForDepositors *
                        vTokenPremiums[i]) / netVTokenPremium;

                    WETH.transfer(depositors[i], wethPremium);

                    emit PremiumShared(depositors[i], wethPremium);
                }

                unchecked {
                    ++i;
                }
            }
        }
    }

    function _vTokenToETH(
        INFTXVaultFactoryV3 _vaultFactory,
        uint256 vTokenAmount
    )
        internal
        view
        returns (uint256 ethAmount, INFTXFeeDistributorV3 feeDistributor)
    {
        feeDistributor = INFTXFeeDistributorV3(_vaultFactory.feeDistributor());
        INFTXRouter nftxRouter = INFTXRouter(feeDistributor.nftxRouter());

        (address pool, bool exists) = nftxRouter.getPoolExists(
            address(this),
            feeDistributor.rewardFeeTier()
        );
        if (!exists) {
            return (0, feeDistributor);
        }

        // price = amount1 / amount0
        // priceX96 = price * 2^96
        uint256 priceX96 = vaultFactory.getTwapX96(pool);
        if (priceX96 == 0) return (0, feeDistributor);

        if (
            address(this) < address(WETH) // checking if isVToken0
        ) {
            ethAmount = FullMath.mulDiv(
                vTokenAmount,
                priceX96,
                FixedPoint96.Q96
            );
        } else {
            ethAmount = FullMath.mulDiv(
                vTokenAmount,
                FixedPoint96.Q96,
                priceX96
            );
        }
    }

    function _getVTokenPremium(
        uint48 timestamp,
        uint256 premiumMax,
        uint256 premiumDuration
    ) internal view returns (uint256) {
        return
            ExponentialPremium.getPremium(
                timestamp,
                premiumMax,
                premiumDuration
            );
    }

    /// @dev Must satisfy ethReceived >= ethFees
    function _refundETH(uint256 ethReceived, uint256 ethFees) internal {
        uint256 ethRefund = ethReceived - ethFees;
        if (ethRefund > 0) {
            TransferLib.transferETH(msg.sender, ethRefund);
        }
    }

    function _transferERC721(
        address assetAddr,
        address to,
        uint256 tokenId
    ) internal {
        bytes memory data;

        if (assetAddr != CRYPTO_PUNKS && assetAddr != CRYPTO_KITTIES) {
            // Default
            data = abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256)",
                address(this),
                to,
                tokenId
            );
        } else if (assetAddr == CRYPTO_PUNKS) {
            data = abi.encodeWithSignature(
                "transferPunk(address,uint256)",
                to,
                tokenId
            );
        } else {
            data = abi.encodeWithSignature(
                "transfer(address,uint256)",
                to,
                tokenId
            );
        }

        (bool success, bytes memory returnData) = address(assetAddr).call(data);
        require(success, string(returnData));
    }

    function _transferFromERC721(address assetAddr, uint256 tokenId) internal {
        bytes memory data;

        if (assetAddr != CRYPTO_PUNKS && assetAddr != CRYPTO_KITTIES) {
            // Default
            // Allow other contracts to "push" into the vault, safely.
            // If we already have the token requested, make sure we don't have it in the list to prevent duplicate minting.
            if (
                IERC721Upgradeable(assetAddress).ownerOf(tokenId) ==
                address(this)
            ) {
                if (_holdings.contains(tokenId)) revert NFTAlreadyOwned();

                return;
            } else {
                data = abi.encodeWithSignature(
                    "safeTransferFrom(address,address,uint256)",
                    msg.sender,
                    address(this),
                    tokenId
                );
            }
        } else if (assetAddr == CRYPTO_PUNKS) {
            // To prevent frontrun attack
            bytes memory punkIndexToAddress = abi.encodeWithSignature(
                "punkIndexToAddress(uint256)",
                tokenId
            );
            (bool checkSuccess, bytes memory result) = address(assetAddr)
                .staticcall(punkIndexToAddress);
            address nftOwner = abi.decode(result, (address));

            if (!checkSuccess || nftOwner != msg.sender) revert NotNFTOwner();

            data = abi.encodeWithSignature("buyPunk(uint256)", tokenId);
        } else {
            // CRYPTO_KITTIES
            data = abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                msg.sender,
                address(this),
                tokenId
            );
        }

        (bool success, bytes memory resultData) = address(assetAddr).call(data);
        require(success, string(resultData));
    }

    function _onlyPrivileged() internal view {
        if (manager == address(0)) {
            if (msg.sender != owner()) revert NotOwner();
        } else {
            if (msg.sender != manager) revert NotManager();
        }
    }

    function _onlyOwnerIfPaused(uint256 lockId) internal view {
        if (vaultFactory.isLocked(lockId) && msg.sender != owner())
            revert Paused();
    }
}
