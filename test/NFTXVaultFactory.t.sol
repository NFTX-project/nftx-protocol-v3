// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";

import {NFTXVaultFactoryUpgradeableV3} from "@src/NFTXVaultFactoryUpgradeableV3.sol";
import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";
import {NFTXVaultUpgradeableV3} from "@src/NFTXVaultUpgradeableV3.sol";
import {PausableUpgradeable} from "@src/custom/PausableUpgradeable.sol";
import {Create2Upgradeable} from "@openzeppelin-upgradeable/contracts/utils/Create2Upgradeable.sol";
import {MockNFT} from "@mocks/MockNFT.sol";
import {ExponentialPremium} from "@src/lib/ExponentialPremium.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Create2BeaconProxy} from "@src/custom/proxy/Create2BeaconProxy.sol";
import {FullMath} from "@uni-core/libraries/FullMath.sol";
import {FixedPoint96} from "@uni-core/libraries/FixedPoint96.sol";
import {NFTXRouter, INFTXRouter} from "@src/NFTXRouter.sol";
import {UpgradeableBeacon} from "@src/custom/proxy/UpgradeableBeacon.sol";

import {TestBase} from "@test/TestBase.sol";

contract NFTXVaultFactoryTests is TestBase {
    uint256 constant CREATEVAULT_PAUSE_CODE = 0;
    uint256 constant FEE_LIMIT = 0.5 ether;
    uint64 constant DEFAULT_VAULT_FACTORY_FEES = 0.1 ether;

    event NewVault(
        uint256 indexed vaultId,
        address vaultAddress,
        address assetAddress,
        string name,
        string symbol
    );
    event UpdateFactoryFees(
        uint256 mintFee,
        uint256 redeemFee,
        uint256 swapFee
    );
    event UpdateVaultFees(
        uint256 vaultId,
        uint256 mintFee,
        uint256 redeemFee,
        uint256 swapFee
    );
    event DisableVaultFees(uint256 vaultId);
    event NewFeeDistributor(address oldDistributor, address newDistributor);
    event FeeExclusion(address feeExcluded, bool excluded);
    event NewEligibilityManager(address oldEligManager, address newEligManager);
    event NewTwapInterval(uint32 twapInterval);
    event NewPremiumDuration(uint256 premiumDuration);
    event NewPremiumMax(uint256 premiumMax);
    event NewDepositorPremiumShare(uint256 depositorPremiumShare);

    event Upgraded(address indexed beaconImplementation);

    // NFTXVaultFactory#init
    function test_init_RevertsForZeroTwapInterval() external {
        NFTXVaultFactoryUpgradeableV3 newVaultFactory = new NFTXVaultFactoryUpgradeableV3();

        vm.expectRevert(INFTXVaultFactoryV3.ZeroTwapInterval.selector);
        newVaultFactory.__NFTXVaultFactory_init({
            vaultImpl: address(vaultImpl),
            twapInterval_: 0,
            premiumDuration_: 10 hours,
            premiumMax_: 5 ether,
            depositorPremiumShare_: 0.30 ether
        });
    }

    function test_init_RevertsIfDepositorPremiumShareExceedsLimit() external {
        NFTXVaultFactoryUpgradeableV3 newVaultFactory = new NFTXVaultFactoryUpgradeableV3();

        vm.expectRevert(
            INFTXVaultFactoryV3.DepositorPremiumShareExceedsLimit.selector
        );
        newVaultFactory.__NFTXVaultFactory_init({
            vaultImpl: address(vaultImpl),
            twapInterval_: 60 minutes,
            premiumDuration_: 10 hours,
            premiumMax_: 5 ether,
            depositorPremiumShare_: 1 ether + 1
        });
    }

    function test_init_Success() external {
        NFTXVaultFactoryUpgradeableV3 newVaultFactory = new NFTXVaultFactoryUpgradeableV3();

        uint32 twapInterval = 60 minutes;
        uint256 premiumDuration = 10 hours;
        uint256 premiumMax = 5 ether;
        uint256 depositorPremiumShare = 0.30 ether;

        newVaultFactory.__NFTXVaultFactory_init({
            vaultImpl: address(vaultImpl),
            twapInterval_: twapInterval,
            premiumDuration_: premiumDuration,
            premiumMax_: premiumMax,
            depositorPremiumShare_: depositorPremiumShare
        });

        assertEq(newVaultFactory.owner(), address(this));
        assertEq(newVaultFactory.implementation(), address(vaultImpl));
        assertEq(newVaultFactory.factoryMintFee(), DEFAULT_VAULT_FACTORY_FEES);
        assertEq(
            newVaultFactory.factoryRedeemFee(),
            DEFAULT_VAULT_FACTORY_FEES
        );
        assertEq(newVaultFactory.factorySwapFee(), DEFAULT_VAULT_FACTORY_FEES);
        assertEq(newVaultFactory.twapInterval(), twapInterval);
        assertEq(newVaultFactory.premiumDuration(), premiumDuration);
        assertEq(newVaultFactory.premiumMax(), premiumMax);
        assertEq(
            newVaultFactory.depositorPremiumShare(),
            depositorPremiumShare
        );
    }

    // NFTXVaultFactory#createVault
    function test_createVault_RevertsForNonOwnerIfPaused() external {
        vaultFactory.setIsGuardian(address(this), true);
        vaultFactory.pause(CREATEVAULT_PAUSE_CODE);

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(PausableUpgradeable.Paused.selector);
        vaultFactory.createVault({
            name: "Test",
            symbol: "TST",
            assetAddress: address(nft),
            is1155: false,
            allowAllItems: true
        });
    }

    function test_createVault_RevertsIfFeeDistributorNotSet() external {
        NFTXVaultFactoryUpgradeableV3 newVaultFactory = new NFTXVaultFactoryUpgradeableV3();
        newVaultFactory.__NFTXVaultFactory_init({
            vaultImpl: address(vaultImpl),
            twapInterval_: 60 minutes,
            premiumDuration_: 10 hours,
            premiumMax_: 5 ether,
            depositorPremiumShare_: 0.30 ether
        });

        vm.expectRevert(INFTXVaultFactoryV3.FeeDistributorNotSet.selector);
        newVaultFactory.createVault({
            name: "Test",
            symbol: "TST",
            assetAddress: address(nft),
            is1155: false,
            allowAllItems: true
        });
    }

    // NOTE: this error (VaultImplementationNotSet) won't ever be thrown because:
    // if feeDistributor is not set it'll revert there first.
    // if we try to set feeDistributor, then owner has to be set which means that init has to be called first
    // if init is called, then vaultImpl has to be set (UpgradeableBeacon doesn't allow non contract address to be passed)

    // function test_createVault_RevertsIfVaultImplementationNotSet() external {
    //     NFTXVaultFactoryUpgradeableV3 newVaultFactory = new NFTXVaultFactoryUpgradeableV3();

    //     vm.expectRevert(INFTXVaultFactoryV3.VaultImplementationNotSet.selector);
    //     newVaultFactory.createVault({
    //         name: "Test",
    //         symbol: "TST",
    //         assetAddress: address(nft),
    //         is1155: false,
    //         allowAllItems: true
    //     });
    // }

    function test_createVault_RevertsForSameNameSymbolForAsset() external {
        MockNFT newNFT = new MockNFT();

        string memory name = "CryptoPunk";
        string memory symbol = "PUNK";

        address assetAddress = address(newNFT);
        vaultFactory.createVault({
            name: name,
            symbol: symbol,
            assetAddress: assetAddress,
            is1155: false,
            allowAllItems: true
        });

        vm.expectRevert("Create2: Failed on deploy");
        vaultFactory.createVault({
            name: name,
            symbol: symbol,
            assetAddress: assetAddress,
            is1155: false,
            allowAllItems: true
        });
    }

    function test_createVault_Success() external {
        MockNFT newNFT = new MockNFT();

        string memory name = "CryptoPunk";
        string memory symbol = "PUNK";
        address assetAddress = address(newNFT);
        bool is1155 = false;
        bool allowAllItems = true;

        uint256 vaultId = vaultFactory.numVaults();
        address vaultAddress = vaultFactory.computeVaultAddress(
            assetAddress,
            name,
            symbol
        );

        vm.expectEmit(true, false, false, true);
        emit NewVault(vaultId, vaultAddress, assetAddress, name, symbol);
        vaultFactory.createVault({
            name: name,
            symbol: symbol,
            assetAddress: assetAddress,
            is1155: is1155,
            allowAllItems: allowAllItems
        });

        assertEq(vaultFactory.numVaults(), vaultId + 1);
        assertEq(vaultFactory.vault(vaultId), vaultAddress);

        address[] memory vaultsForAsset = vaultFactory.vaultsForAsset(
            assetAddress
        );
        assertEq(vaultsForAsset.length, 1);
        assertEq(vaultsForAsset[0], vaultAddress);

        NFTXVaultUpgradeableV3 vault = NFTXVaultUpgradeableV3(vaultAddress);
        assertEq(vault.name(), name);
        assertEq(vault.symbol(), symbol);
        assertEq(vault.assetAddress(), assetAddress);
        assertEq(vault.is1155(), is1155);
        assertEq(vault.allowAllItems(), allowAllItems);
        assertEq(vault.manager(), address(this));
        assertEq(vault.owner(), vaultFactory.owner());
    }

    // NFTXVaultFactory#setFactoryFees
    function test_setFactoryFees_RevertsForNonOwner() external {
        uint64 newFactoryFees = 0.2 ether;

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        vaultFactory.setFactoryFees({
            mintFee: newFactoryFees,
            redeemFee: newFactoryFees,
            swapFee: newFactoryFees
        });
    }

    function test_setFactoryFees_RevertsIfLimitExceeded(
        uint256 feeDelta
    ) external {
        vm.assume(feeDelta > 1);
        // to prevent overflow in the tests below
        vm.assume(feeDelta < type(uint256).max - FEE_LIMIT);

        // reverts for mintFee
        vm.expectRevert(INFTXVaultFactoryV3.FeeExceedsLimit.selector);
        vaultFactory.setFactoryFees({
            mintFee: FEE_LIMIT + feeDelta,
            redeemFee: 0.3 ether,
            swapFee: 0.3 ether
        });

        // reverts for redeemFee
        vm.expectRevert(INFTXVaultFactoryV3.FeeExceedsLimit.selector);
        vaultFactory.setFactoryFees({
            mintFee: 0.3 ether,
            redeemFee: FEE_LIMIT + feeDelta,
            swapFee: 0.3 ether
        });

        // reverts for swapFee
        vm.expectRevert(INFTXVaultFactoryV3.FeeExceedsLimit.selector);
        vaultFactory.setFactoryFees({
            mintFee: 0.3 ether,
            redeemFee: 0.3 ether,
            swapFee: FEE_LIMIT + feeDelta
        });
    }

    function test_setFactoryFees_Success(
        uint256 mintFee,
        uint256 redeemFee,
        uint256 swapFee
    ) external {
        vm.assume(mintFee <= FEE_LIMIT);
        vm.assume(redeemFee <= FEE_LIMIT);
        vm.assume(swapFee <= FEE_LIMIT);

        vm.expectEmit(false, false, false, true);
        emit UpdateFactoryFees(mintFee, redeemFee, swapFee);
        vaultFactory.setFactoryFees({
            mintFee: mintFee,
            redeemFee: redeemFee,
            swapFee: swapFee
        });

        assertEq(vaultFactory.factoryMintFee(), uint64(mintFee));
        assertEq(vaultFactory.factoryRedeemFee(), uint64(redeemFee));
        assertEq(vaultFactory.factorySwapFee(), uint64(swapFee));
    }

    // NFTXVaultFactory#setVaultFees
    function test_setVaultFees_RevertsForNonOwnerAndNonVault() external {
        vaultFactory.createVault({
            name: "Test",
            symbol: "TST",
            assetAddress: address(nft),
            is1155: false,
            allowAllItems: true
        });

        hoax(makeAddr("nonOwnerAndNonVault"));
        vm.expectRevert(INFTXVaultFactoryV3.CallerIsNotVault.selector);
        vaultFactory.setVaultFees({
            vaultId: 0,
            mintFee: 0.3 ether,
            redeemFee: 0.3 ether,
            swapFee: 0.3 ether
        });
    }

    function test_setVaultFees_RevertsIfLimitExceeded(
        uint256 feeDelta
    ) external {
        vm.assume(feeDelta > 1);
        // to prevent overflow in the tests below
        vm.assume(feeDelta < type(uint256).max - FEE_LIMIT);

        startHoax(address(vtoken));

        // reverts for mintFee
        vm.expectRevert(INFTXVaultFactoryV3.FeeExceedsLimit.selector);
        vaultFactory.setVaultFees({
            vaultId: VAULT_ID,
            mintFee: FEE_LIMIT + feeDelta,
            redeemFee: 0.3 ether,
            swapFee: 0.3 ether
        });

        // reverts for redeemFee
        vm.expectRevert(INFTXVaultFactoryV3.FeeExceedsLimit.selector);
        vaultFactory.setVaultFees({
            vaultId: VAULT_ID,
            mintFee: 0.3 ether,
            redeemFee: FEE_LIMIT + feeDelta,
            swapFee: 0.3 ether
        });

        // reverts for swapFee
        vm.expectRevert(INFTXVaultFactoryV3.FeeExceedsLimit.selector);
        vaultFactory.setVaultFees({
            vaultId: VAULT_ID,
            mintFee: 0.3 ether,
            redeemFee: 0.3 ether,
            swapFee: FEE_LIMIT + feeDelta
        });
    }

    function test_setVaultFees_SuccessForOwnerAndVault(
        uint256 mintFee,
        uint256 redeemFee,
        uint256 swapFee,
        bool callerIsVault
    ) external {
        vm.assume(mintFee <= FEE_LIMIT);
        vm.assume(redeemFee <= FEE_LIMIT);
        vm.assume(swapFee <= FEE_LIMIT);

        if (callerIsVault) {
            startHoax(address(vtoken));
        }

        vm.expectEmit(false, false, false, true);
        // TODO: vaultId can be made indexed in this event
        emit UpdateVaultFees(VAULT_ID, mintFee, redeemFee, swapFee);
        vaultFactory.setVaultFees({
            vaultId: VAULT_ID,
            mintFee: mintFee,
            redeemFee: redeemFee,
            swapFee: swapFee
        });

        (uint256 _mintFee, uint256 _redeemFee, uint256 _swapFee) = vaultFactory
            .vaultFees(VAULT_ID);

        assertEq(_mintFee, mintFee);
        assertEq(_redeemFee, redeemFee);
        assertEq(_swapFee, swapFee);
    }

    // NFTXVaultFactory#disableVaultFees
    function test_disableVaultFees_RevertsForNonOwnerAndNonVault() external {
        hoax(makeAddr("nonOwnerAndNonVault"));
        vm.expectRevert(INFTXVaultFactoryV3.CallerIsNotVault.selector);
        vaultFactory.disableVaultFees(VAULT_ID);
    }

    function test_disableVaultFees_SuccessForOwnerAndVault(
        uint256 mintFee,
        uint256 redeemFee,
        uint256 swapFee,
        bool callerIsVault
    ) external {
        // set fees for vault first (different from vaultFactory fees)
        vm.assume(
            mintFee <= FEE_LIMIT && mintFee != DEFAULT_VAULT_FACTORY_FEES
        );
        vm.assume(
            redeemFee <= FEE_LIMIT && redeemFee != DEFAULT_VAULT_FACTORY_FEES
        );
        vm.assume(
            swapFee <= FEE_LIMIT && swapFee != DEFAULT_VAULT_FACTORY_FEES
        );
        vaultFactory.setVaultFees({
            vaultId: VAULT_ID,
            mintFee: mintFee,
            redeemFee: redeemFee,
            swapFee: swapFee
        });

        if (callerIsVault) {
            startHoax(address(vtoken));
        }

        vm.expectEmit(false, false, false, true);
        // TODO: vaultId can be made indexed in this event
        emit DisableVaultFees(VAULT_ID);
        vaultFactory.disableVaultFees(VAULT_ID);

        (uint256 _mintFee, uint256 _redeemFee, uint256 _swapFee) = vaultFactory
            .vaultFees(VAULT_ID);

        assertEq(_mintFee, DEFAULT_VAULT_FACTORY_FEES);
        assertEq(_redeemFee, DEFAULT_VAULT_FACTORY_FEES);
        assertEq(_swapFee, DEFAULT_VAULT_FACTORY_FEES);
    }

    // NFTXVaultFactory#setFeeDistributor
    function test_setFeeDistributor_RevertsForNonOwner() external {
        address newFeeDistributor = makeAddr("newFeeDistributor");

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        vaultFactory.setFeeDistributor(newFeeDistributor);
    }

    function test_setFeeDistributor_RevertsForZeroAddress() external {
        address newFeeDistributor = address(0);

        vm.expectRevert(INFTXVaultFactoryV3.ZeroAddress.selector);
        vaultFactory.setFeeDistributor(newFeeDistributor);
    }

    function test_setFeeDistributor_Success() external {
        address newFeeDistributor = makeAddr("newFeeDistributor");

        address preFeeDistributor = vaultFactory.feeDistributor();
        assertTrue(preFeeDistributor != newFeeDistributor);

        vm.expectEmit(false, false, false, true);
        emit NewFeeDistributor(preFeeDistributor, newFeeDistributor);
        vaultFactory.setFeeDistributor(newFeeDistributor);
        assertEq(vaultFactory.feeDistributor(), newFeeDistributor);
    }

    // NFTXVaultFactory#setFeeExclusion
    function test_setFeeExclusion_RevertsForNonOwner() external {
        address excludedAddr = makeAddr("excludedAddr");
        bool excluded = true;

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        vaultFactory.setFeeExclusion(excludedAddr, excluded);
    }

    function test_setFeeExclusion_Success(bool excluded) external {
        address excludedAddr = makeAddr("excludedAddr");

        vm.expectEmit(false, false, false, true);
        emit FeeExclusion(excludedAddr, excluded);
        vaultFactory.setFeeExclusion(excludedAddr, excluded);
        assertEq(vaultFactory.excludedFromFees(excludedAddr), excluded);
    }

    // NFTXVaultFactory#setEligibilityManager
    function test_setEligibilityManager_RevertsForNonOwner() external {
        address newEligibilityManager = makeAddr("newEligibilityManager");

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        vaultFactory.setEligibilityManager(newEligibilityManager);
    }

    function test_setEligibilityManager_Success() external {
        address newEligibilityManager = makeAddr("newEligibilityManager");

        address preEligibilityManager = vaultFactory.eligibilityManager();
        assertTrue(preEligibilityManager != newEligibilityManager);

        vm.expectEmit(false, false, false, true);
        emit NewEligibilityManager(
            preEligibilityManager,
            newEligibilityManager
        );
        vaultFactory.setEligibilityManager(newEligibilityManager);
        assertEq(vaultFactory.eligibilityManager(), newEligibilityManager);
    }

    // NFTXVaultFactory#setTwapInterval
    function test_setTwapInterval_RevertsForNonOwner() external {
        uint32 newTwapInterval = 60 minutes;

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        vaultFactory.setTwapInterval(newTwapInterval);
    }

    function test_setTwapInterval_RevertsForZeroTwapInterval() external {
        uint32 newTwapInterval = 0;

        vm.expectRevert(INFTXVaultFactoryV3.ZeroTwapInterval.selector);
        vaultFactory.setTwapInterval(newTwapInterval);
    }

    function test_setTwapInterval_Success() external {
        uint32 newTwapInterval = 60 minutes;

        uint32 preTwapInterval = vaultFactory.twapInterval();
        assertTrue(preTwapInterval != newTwapInterval);

        vm.expectEmit(false, false, false, true);
        emit NewTwapInterval(newTwapInterval);
        vaultFactory.setTwapInterval(newTwapInterval);
        assertEq(vaultFactory.twapInterval(), newTwapInterval);
    }

    // NFTXVaultFactory#setPremiumDuration
    function test_setPremiumDuration_RevertsForNonOwner() external {
        uint256 newPremiumDuration = 20 hours;

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        vaultFactory.setPremiumDuration(newPremiumDuration);
    }

    function test_setPremiumDuration_Success() external {
        uint256 newPremiumDuration = 20 hours;

        uint256 prePremiumDuration = vaultFactory.premiumDuration();
        assertTrue(prePremiumDuration != newPremiumDuration);

        vm.expectEmit(false, false, false, true);
        emit NewPremiumDuration(newPremiumDuration);
        vaultFactory.setPremiumDuration(newPremiumDuration);
        assertEq(vaultFactory.premiumDuration(), newPremiumDuration);
    }

    // NFTXVaultFactory#setPremiumMax
    function test_setPremiumMax_RevertsForNonOwner() external {
        uint256 newPremiumMax = 10 ether;

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        vaultFactory.setPremiumMax(newPremiumMax);
    }

    function test_setPremiumMax_Success() external {
        uint256 newPremiumMax = 10 ether;

        uint256 prePremiumMax = vaultFactory.premiumMax();
        assertTrue(prePremiumMax != newPremiumMax);

        vm.expectEmit(false, false, false, true);
        emit NewPremiumMax(newPremiumMax);
        vaultFactory.setPremiumMax(newPremiumMax);
        assertEq(vaultFactory.premiumMax(), newPremiumMax);
    }

    // NFTXVaultFactory#setDepositorPremiumShare
    function test_setDepositorPremiumShare_RevertsForNonOwner() external {
        uint256 newDepositorPremiumShare = 0.4 ether;

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        vaultFactory.setDepositorPremiumShare(newDepositorPremiumShare);
    }

    function test_setDepositorPremiumShare_RevertsIfLimitExceeded() external {
        uint256 newDepositorPremiumShare = 1 ether + 1;

        vm.expectRevert(
            INFTXVaultFactoryV3.DepositorPremiumShareExceedsLimit.selector
        );
        vaultFactory.setDepositorPremiumShare(newDepositorPremiumShare);
    }

    function test_setDepositorPremiumShare_Success() external {
        uint256 newDepositorPremiumShare = 0.4 ether;

        uint256 preDepositorPremiumShare = vaultFactory.depositorPremiumShare();
        assertTrue(preDepositorPremiumShare != newDepositorPremiumShare);

        vm.expectEmit(false, false, false, true);
        emit NewDepositorPremiumShare(newDepositorPremiumShare);
        vaultFactory.setDepositorPremiumShare(newDepositorPremiumShare);
        assertEq(
            vaultFactory.depositorPremiumShare(),
            newDepositorPremiumShare
        );
    }

    // NFTXVaultFactory#vaultFees
    function test_vaultFees_IfCustomFeesSet_Success(
        uint256 mintFee,
        uint256 redeemFee,
        uint256 swapFee
    ) external {
        vm.assume(
            mintFee <= FEE_LIMIT && mintFee != DEFAULT_VAULT_FACTORY_FEES
        );
        vm.assume(
            redeemFee <= FEE_LIMIT && redeemFee != DEFAULT_VAULT_FACTORY_FEES
        );
        vm.assume(
            swapFee <= FEE_LIMIT && swapFee != DEFAULT_VAULT_FACTORY_FEES
        );

        vaultFactory.setVaultFees({
            vaultId: VAULT_ID,
            mintFee: mintFee,
            redeemFee: redeemFee,
            swapFee: swapFee
        });

        (uint256 _mintFee, uint256 _redeemFee, uint256 _swapFee) = vaultFactory
            .vaultFees(VAULT_ID);

        assertEq(_mintFee, mintFee);
        assertEq(_redeemFee, redeemFee);
        assertEq(_swapFee, swapFee);
    }

    function test_vaultFees_IfCustomFeesNotSet_Success() external {
        (uint256 _mintFee, uint256 _redeemFee, uint256 _swapFee) = vaultFactory
            .vaultFees(VAULT_ID);

        assertEq(_mintFee, DEFAULT_VAULT_FACTORY_FEES);
        assertEq(_redeemFee, DEFAULT_VAULT_FACTORY_FEES);
        assertEq(_swapFee, DEFAULT_VAULT_FACTORY_FEES);
    }

    // NFTXVaultFactory#getVTokenPremium721
    function test_getVTokenPremium721_Success() external {
        uint256 qty = 1;
        uint256[] memory tokenIds = nft.mint(qty);
        uint256 tokenId = tokenIds[0];

        address depositor = makeAddr("depositor");

        nft.setApprovalForAll(address(vtoken), true);
        vtoken.mint({
            tokenIds: tokenIds,
            amounts: emptyAmounts,
            depositor: depositor,
            to: address(this)
        });

        (uint256 _vTokenPremium, address _depositor) = vaultFactory
            .getVTokenPremium721(VAULT_ID, tokenId);

        console.log("vTokenPremium: %s", _vTokenPremium);
        assertGt(_vTokenPremium, 0);
        assertEq(_depositor, depositor);

        (uint48 timestamp, ) = vtoken.tokenDepositInfo(tokenId);
        uint256 expectedVTokenPremium = ExponentialPremium.getPremium(
            timestamp,
            vaultFactory.premiumMax(),
            vaultFactory.premiumDuration()
        );
        assertEq(_vTokenPremium, expectedVTokenPremium);
    }

    // NFTXVaultFactory#getVTokenPremium1155
    function test_getVTokenPremium1155_RevertsIfZeroAmountRequested() external {
        uint256 qty = 1;
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        tokenIds[0] = nft1155.mint(qty);
        amounts[0] = qty;

        nft1155.setApprovalForAll(address(vtoken1155), true);
        vtoken1155.mint({
            tokenIds: tokenIds,
            amounts: amounts,
            depositor: address(this),
            to: address(this)
        });

        vm.expectRevert(INFTXVaultFactoryV3.ZeroAmountRequested.selector);
        vaultFactory.getVTokenPremium1155({
            vaultId: VAULT_ID_1155,
            tokenId: tokenIds[0],
            amount: 0
        });
    }

    function test_getVTokenPremium1155_RevertsIfAmountExceedsNFTBalance()
        external
    {
        uint256 qty = 1;
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        tokenIds[0] = nft1155.mint(qty);
        amounts[0] = qty;

        nft1155.setApprovalForAll(address(vtoken1155), true);
        vtoken1155.mint({
            tokenIds: tokenIds,
            amounts: amounts,
            depositor: address(this),
            to: address(this)
        });

        vm.expectRevert(INFTXVaultFactoryV3.NFTInventoryExceeded.selector);
        vaultFactory.getVTokenPremium1155({
            vaultId: VAULT_ID_1155,
            tokenId: tokenIds[0],
            amount: qty + 1
        });
    }

    // Storage
    uint256 s_tokenId;
    uint256 s_amount;
    uint256 s_vTokenPremium;
    uint256[] s_premiums;
    address[] s_depositors;

    function test_getVTokenPremium1155_Success(
        uint256[1000] memory values,
        uint256 depositCount,
        uint256 amount
    ) external {
        amount = bound(amount, 1, 10_000);
        depositCount = bound(depositCount, 1, values.length);

        // To avoid "The `vm.assume` cheatcode rejected too many inputs (65536 allowed)"
        // get 100 random values from depositAmounts, and then create a new array of length depositCount with those values
        uint256[] memory depositAmounts = new uint256[](depositCount);
        for (uint256 i; i < depositCount; i++) {
            depositAmounts[i] = values[i];
        }

        uint256 tokenId = nft1155.nextId();
        nft1155.setApprovalForAll(address(vtoken1155), true);

        uint256 totalDeposited;
        for (uint256 i; i < depositAmounts.length; i++) {
            depositAmounts[i] = bound(depositAmounts[i], 1, type(uint64).max);

            totalDeposited += depositAmounts[i];

            nft1155.mint(tokenId, depositAmounts[i]);

            uint256[] memory tokenIds = new uint256[](1);
            uint256[] memory amounts = new uint256[](1);
            tokenIds[0] = tokenId;
            amounts[0] = depositAmounts[i];

            vtoken1155.mint({
                tokenIds: tokenIds,
                amounts: amounts,
                depositor: makeAddr(
                    string.concat("depositor", Strings.toString(i))
                ),
                to: address(this)
            });
        }
        vm.assume(totalDeposited >= amount);

        // putting in a separate external call to avoid "EvmError: MemoryLimitOOG"
        // using storage instead to pass values
        // source: https://github.com/foundry-rs/foundry/issues/3971#issuecomment-1698653788
        s_tokenId = tokenId;
        s_amount = amount;
        this.getVTokenPremium1155();

        console.log("vTokenPremium: %s", s_vTokenPremium);
        assertGt(s_vTokenPremium, 0);
        assertEq(
            s_vTokenPremium,
            ExponentialPremium.getPremium(
                block.timestamp,
                vaultFactory.premiumMax(),
                vaultFactory.premiumDuration()
            ) * amount
        );

        assertEq(s_premiums.length, s_depositors.length);

        uint256 netDepositAmountUsed;
        for (uint256 i; i < s_depositors.length; i++) {
            uint256 depositAmountUsed;
            if (netDepositAmountUsed + depositAmounts[i] >= amount) {
                depositAmountUsed = amount - netDepositAmountUsed;
            } else {
                depositAmountUsed = depositAmounts[i];
            }
            netDepositAmountUsed += depositAmountUsed;

            assertEq(
                s_premiums[i],
                ExponentialPremium.getPremium(
                    block.timestamp,
                    vaultFactory.premiumMax(),
                    vaultFactory.premiumDuration()
                ) * depositAmountUsed
            );
            assertEq(
                s_depositors[i],
                makeAddr(string.concat("depositor", Strings.toString(i)))
            );
        }
        assertEq(netDepositAmountUsed, amount);
    }

    function getVTokenPremium1155() external {
        (s_vTokenPremium, s_premiums, s_depositors) = vaultFactory
            .getVTokenPremium1155(VAULT_ID_1155, s_tokenId, s_amount);
    }

    // NFTXVaultFactory#computeVaultAddress
    function test_computeVaultAddress_Success() external {
        string memory name = "CryptoPunk";
        string memory symbol = "PUNK";
        address assetAddress = address(nft);

        address vaultAddress = vaultFactory.computeVaultAddress(
            assetAddress,
            name,
            symbol
        );

        address expectedVaultAddress = Create2Upgradeable.computeAddress(
            keccak256(abi.encode(assetAddress, name, symbol)),
            keccak256(type(Create2BeaconProxy).creationCode),
            address(vaultFactory)
        );

        uint256 vaultId = vaultFactory.createVault({
            name: name,
            symbol: symbol,
            assetAddress: assetAddress,
            is1155: false,
            allowAllItems: true
        });
        address actualVaultAddress = vaultFactory.vault(vaultId);

        assertEq(vaultAddress, expectedVaultAddress);
        assertEq(vaultAddress, actualVaultAddress);
    }

    // NFTXVaultFactory#getTwapX96
    function test_getTwapX96(
        uint256 currentNFTPrice,
        uint256 waitForSecs
    ) external {
        // currentNFTPrice has to be min 10 wei to avoid lowerNFTPrice from being zero
        vm.assume(
            currentNFTPrice >= 10 && currentNFTPrice <= type(uint128).max
        );
        vm.assume(waitForSecs <= type(uint128).max);

        uint256 lowerNFTPrice = (currentNFTPrice * 95) / 100;
        uint256 upperNFTPrice = (currentNFTPrice * 105) / 100;

        _mintPosition({
            qty: 5,
            currentNFTPrice: currentNFTPrice,
            lowerNFTPrice: lowerNFTPrice,
            upperNFTPrice: upperNFTPrice,
            fee: DEFAULT_FEE_TIER
        });

        vm.warp(block.timestamp + waitForSecs);

        address pool = nftxRouter.getPool(address(vtoken), DEFAULT_FEE_TIER);
        uint256 twapX96 = vaultFactory.getTwapX96(pool);
        uint256 price;
        if (waitForSecs == 0) {
            // for same block, twapX96A will be zero
            assertEq(twapX96, 0);
        } else {
            assertGt(twapX96, 0, "twapX96A == 0");
            // twap should get set instantly from the next second
            if (nftxRouter.isVToken0(address(vtoken))) {
                price = FullMath.mulDiv(1 ether, twapX96, FixedPoint96.Q96);
            } else {
                price = FullMath.mulDiv(1 ether, FixedPoint96.Q96, twapX96);
            }
            assertGt(price, 0);
            assertGt(
                price,
                currentNFTPrice - 2 wei, // to account for any rounding errors
                "!price"
            );
        }
    }

    // UpgradeableBeacon#upgradeBeaconTo
    function test_upgradeBeaconTo_RevertsForNonOwner() external {
        address newImplementation = makeAddr("newImplementation");

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        vaultFactory.upgradeBeaconTo(newImplementation);
    }

    function test_upgradeBeaconTo_RevertsForNonContract() external {
        address newImplementation = makeAddr("newImplementation");

        vm.expectRevert(
            UpgradeableBeacon.ChildImplementationIsNotAContract.selector
        );
        vaultFactory.upgradeBeaconTo(newImplementation);
    }

    function test_upgradeBeaconTo_Success() external {
        NFTXVaultFactoryUpgradeableV3 newVaultFactory = new NFTXVaultFactoryUpgradeableV3();
        address newImplementation = address(newVaultFactory);

        address preImplementation = vaultFactory.implementation();
        assertTrue(preImplementation != newImplementation);

        vm.expectEmit(false, false, false, true);
        emit Upgraded(newImplementation);
        vaultFactory.upgradeBeaconTo(newImplementation);
        assertEq(vaultFactory.implementation(), newImplementation);
    }
}
