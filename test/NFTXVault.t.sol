// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";

import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";
import {INFTXVaultV3} from "@src/interfaces/INFTXVaultV3.sol";
import {NFTXVaultUpgradeableV3} from "@src/NFTXVaultUpgradeableV3.sol";
import {PausableUpgradeable} from "@src/custom/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@src/custom/OwnableUpgradeable.sol";
import {MockNFT} from "@mocks/MockNFT.sol";
import {Mock1155} from "@mocks/Mock1155.sol";

import {TestBase} from "@test/TestBase.sol";

contract NFTXVaultTests is TestBase {
    uint256 constant MINT_PAUSE_CODE = 1;
    uint256 constant REDEEM_PAUSE_CODE = 2;
    uint256 constant SWAP_PAUSE_CODE = 3;

    uint256 constant CURRENT_NFT_PRICE = 10 ether;
    uint256 constant QTY = 5;

    event VaultInit(
        uint256 indexed vaultId,
        address assetAddress,
        bool is1155,
        bool allowAllItems
    );

    event MetadataUpdated(string name, string symbol);
    event EnableMintUpdated(bool enabled);
    event EnableRedeemUpdated(bool enabled);
    event EnableSwapUpdated(bool enabled);
    event UpdateVaultFees(
        uint256 vaultId,
        uint256 mintFee,
        uint256 redeemFee,
        uint256 swapFee
    );
    event DisableVaultFees(uint256 vaultId);
    event EligibilityDeployed(uint256 moduleIndex, address eligibilityAddr);
    event ManagerSet(address manager);
    event VaultShutdown(
        address assetAddress,
        uint256 numItems,
        address recipient
    );

    // NFTXVault#init
    function test_init_RevertsForZeroAssetAddress() external {
        NFTXVaultUpgradeableV3 newVault = new NFTXVaultUpgradeableV3(
            IWETH9(address(weth))
        );

        address assetAddress = address(0);

        hoax(address(vaultFactory));
        vm.expectRevert(INFTXVaultV3.ZeroAddress.selector);
        newVault.__NFTXVault_init({
            name_: "TEST",
            symbol_: "TST",
            assetAddress_: assetAddress,
            is1155_: false,
            allowAllItems_: true
        });
    }

    function test_init_RevertsIfAlreadyInitialized() external {
        NFTXVaultUpgradeableV3 newVault = new NFTXVaultUpgradeableV3(
            IWETH9(address(weth))
        );
        startHoax(address(vaultFactory));
        newVault.__NFTXVault_init({
            name_: "TEST",
            symbol_: "TST",
            assetAddress_: address(nft),
            is1155_: false,
            allowAllItems_: true
        });

        vm.expectRevert("Initializable: contract is already initialized");
        newVault.__NFTXVault_init({
            name_: "TEST",
            symbol_: "TST",
            assetAddress_: address(nft),
            is1155_: false,
            allowAllItems_: true
        });
    }

    function test_init_Success() external {
        NFTXVaultUpgradeableV3 newVault = new NFTXVaultUpgradeableV3(
            IWETH9(address(weth))
        );

        string memory name = "TEST";
        string memory symbol = "TST";
        address assetAddress = address(nft);
        bool is1155 = false;
        bool allowAllItems = true;
        uint256 vaultId = vaultFactory.numVaults();

        hoax(address(vaultFactory));

        vm.expectEmit(true, false, false, true);
        emit VaultInit(vaultId, assetAddress, is1155, allowAllItems);

        newVault.__NFTXVault_init(
            name,
            symbol,
            assetAddress,
            is1155,
            allowAllItems
        );

        assertEq(newVault.owner(), address(vaultFactory));
        assertEq(newVault.name(), name);
        assertEq(newVault.symbol(), symbol);
        assertEq(newVault.assetAddress(), assetAddress);
        assertEq(address(newVault.vaultFactory()), address(vaultFactory));
        assertEq(newVault.vaultId(), vaultId);
        assertEq(newVault.is1155(), is1155);
        assertEq(newVault.allowAllItems(), allowAllItems);
        assertEq(newVault.enableMint(), true);
        assertEq(newVault.enableRedeem(), true);
        assertEq(newVault.enableSwap(), true);

        assertEq(
            DELEGATE_REGISTRY.checkDelegateForAll(
                address(vaultFactory.owner()),
                address(newVault),
                bytes32("")
            ),
            true
        );
    }

    // NFTXVault#mint

    function test_mint_RevertsForNonOwnerIfPaused() external {
        vaultFactory.setIsGuardian(address(this), true);
        vaultFactory.pause(MINT_PAUSE_CODE);

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(PausableUpgradeable.Paused.selector);
        vtoken.mint{value: 0}({
            tokenIds: emptyIds,
            amounts: emptyAmounts,
            depositor: address(this),
            to: address(this)
        });
    }

    function test_mint_RevertsIfMintNotEnabled() external {
        vtoken.setVaultFeatures({
            enableMint_: false,
            enableRedeem_: true,
            enableSwap_: true
        });

        vm.expectRevert(INFTXVaultV3.MintingDisabled.selector);
        vtoken.mint{value: 0}({
            tokenIds: emptyIds,
            amounts: emptyAmounts,
            depositor: address(this),
            to: address(this)
        });
    }

    function test_mint_RevertsIfTokenIdNotInEligibilityModule() external {
        uint256[] memory tokenIds = nft.mint(QTY);
        nft.setApprovalForAll(address(vtoken), true);

        // only tokenIds from tokenIds[0] to tokenIds[2] are eligible, rest are not
        bytes memory rangeInitData = abi.encode(tokenIds[0], tokenIds[2]);
        vtoken.deployEligibilityStorage({
            moduleIndex: RANGE_MODULE_INDEX,
            initData: rangeInitData
        });

        vm.expectRevert(INFTXVaultV3.NotEligible.selector);
        vtoken.mint({
            tokenIds: tokenIds,
            amounts: emptyAmounts,
            depositor: address(this),
            to: address(this)
        });
    }

    function test_mint_721_RevertsIfUsingTokenIdAlreadyInHoldings() external {
        uint256[] memory tokenIds = nft.mint(1);
        nft.setApprovalForAll(address(vtoken), true);
        vtoken.mint{value: 0}({
            tokenIds: tokenIds,
            amounts: emptyAmounts,
            depositor: address(this),
            to: address(this)
        });

        vm.expectRevert(INFTXVaultV3.NFTAlreadyOwned.selector);
        vtoken.mint{value: 0}({
            tokenIds: tokenIds,
            amounts: emptyAmounts,
            depositor: address(this),
            to: address(this)
        });
    }

    function test_mint_721_WhenNFTExternallyTransferred_Success() external {
        uint256[] memory tokenIds = nft.mint(QTY);
        for (uint i; i < QTY; i++) {
            nft.safeTransferFrom(address(this), address(vtoken), tokenIds[i]);
        }

        address depositor = address(this);
        address to = address(this);

        vtoken.mint{value: 0}(tokenIds, emptyAmounts, depositor, to);

        _post721MintChecks(tokenIds, depositor, to);
    }

    function test_mint_721_ETHRefunds_WhenNoPoolExists_Success() external {
        uint256 expectedETHPaidIfPoolExisted = _calcExpectedMintETHFees(
            QTY,
            CURRENT_NFT_PRICE
        );

        uint256 prevETHBal = address(this).balance;

        uint256[] memory tokenIds = nft.mint(QTY);
        nft.setApprovalForAll(address(vtoken), true);

        address depositor = address(this);
        address to = address(this);

        // sending ETH to check if all is refunded back
        vtoken.mint{value: expectedETHPaidIfPoolExisted}(
            tokenIds,
            emptyAmounts,
            depositor,
            to
        );

        uint256 ethPaid = prevETHBal - address(this).balance;
        assertEq(ethPaid, 0, "ETH Fees deducted");

        _post721MintChecks(tokenIds, depositor, to);
    }

    function test_mint_721_RevertsWhenLessETHSent() external {
        _mintPositionWithTwap(CURRENT_NFT_PRICE);

        uint256[] memory tokenIds = nft.mint(QTY);
        nft.setApprovalForAll(address(vtoken), true);

        vm.expectRevert(INFTXVaultV3.InsufficientETHSent.selector);
        vtoken.mint{value: 0}({
            tokenIds: tokenIds,
            amounts: emptyAmounts,
            depositor: address(this),
            to: address(this)
        });
    }

    function test_mint_721_WhenPoolExists_Succcess() external {
        (
            uint256 exactETHPaid,
            uint256 expectedETHPaid
        ) = _twap721AndCalcMintETHFees(QTY, CURRENT_NFT_PRICE);

        uint256[] memory tokenIds = nft.mint(QTY);
        nft.setApprovalForAll(address(vtoken), true);

        address depositor = address(this);
        address to = address(this);

        uint256 prevETHBal = address(this).balance;
        uint256 gasBefore = gasleft();

        // double ETH value here to check if refund working as well
        vtoken.mint{value: expectedETHPaid * 2}(
            tokenIds,
            emptyAmounts,
            depositor,
            to
        );

        uint256 gasAfter = gasleft();
        console.log("gasUsed", gasBefore - gasAfter);

        console.log("expectedETHPaid", expectedETHPaid);
        console.log("exactETHPaid", exactETHPaid);

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid", ethPaid);
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);

        _post721MintChecks(tokenIds, depositor, to);
    }

    function test_mint_721_NoFeesWhenOnExcludeList_Success() external {
        _mintPositionWithTwap(CURRENT_NFT_PRICE);
        // verify that TWAP is set
        assertGt(vtoken.vTokenToETH(1 ether), 0);

        // add sender to exclusion list
        vaultFactory.setFeeExclusion(address(this), true);

        uint256[] memory tokenIds = nft.mint(QTY);
        nft.setApprovalForAll(address(vtoken), true);

        address depositor = address(this);
        address to = address(this);

        vtoken.mint{value: 0}(tokenIds, emptyAmounts, depositor, to);

        _post721MintChecks(tokenIds, depositor, to);
    }

    // 1155

    function test_mint_1155_RevertsForZeroAmount() external {
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        tokenIds[0] = nft1155.mint(QTY);
        amounts[0] = 0;

        nft1155.setApprovalForAll(address(vtoken1155), true);

        vm.expectRevert(INFTXVaultV3.TransferAmountIsZero.selector);
        vtoken1155.mint{value: 0}({
            tokenIds: tokenIds,
            amounts: amounts,
            depositor: address(this),
            to: address(this)
        });
    }

    function test_mint_1155_WhenPoolExists_Succcess() external {
        (
            uint256 exactETHPaid,
            uint256 expectedETHPaid
        ) = _twap1155AndCalcMintETHFees(QTY, CURRENT_NFT_PRICE);

        uint256 prevETHBal = address(this).balance;

        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        tokenIds[0] = nft1155.mint(QTY);
        amounts[0] = QTY;

        nft1155.setApprovalForAll(address(vtoken1155), true);

        address depositor = address(this);
        address to = address(this);

        uint256 preDepositLength = vtoken1155.depositInfo1155Length(
            tokenIds[0]
        );
        uint256 prevNFTBal = nft1155.balanceOf(
            address(vtoken1155),
            tokenIds[0]
        );

        // double ETH value here to check if refund working as well
        vtoken1155.mint{value: expectedETHPaid * 2}(
            tokenIds,
            amounts,
            depositor,
            to
        );

        uint256 ethPaid = prevETHBal - address(this).balance;
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);

        assertEq(vtoken1155.balanceOf(to), QTY * 1 ether, "!vTokens");

        assertEq(
            nft1155.balanceOf(address(vtoken1155), tokenIds[0]) - prevNFTBal,
            amounts[0]
        );

        assertEq(
            vtoken1155.depositInfo1155Length(tokenIds[0]),
            preDepositLength + 1
        );

        (uint256 _qty, address _depositor, uint48 timestamp) = vtoken1155
            .depositInfo1155(
                tokenIds[0],
                vtoken1155.pointerIndex1155(tokenIds[0])
            );
        assertEq(_qty, QTY);
        assertEq(_depositor, depositor);
        assertEq(timestamp, block.timestamp);
    }

    // NFTXVault#redeem

    function test_redeem_RevertsForNonOwnerIfPaused() external {
        vaultFactory.setIsGuardian(address(this), true);
        vaultFactory.pause(REDEEM_PAUSE_CODE);

        address nonOwner = makeAddr("nonOwner");
        (, uint256[] memory idsOut) = _mintVToken(QTY);
        vtoken.transfer(nonOwner, vtoken.balanceOf(address(this)));

        startHoax(nonOwner);
        vm.expectRevert(PausableUpgradeable.Paused.selector);
        vtoken.redeem({
            idsOut: idsOut,
            to: address(this),
            wethAmount: 0,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });
    }

    function test_redeem_RevertsIfRedeemNotEnabled() external {
        vtoken.setVaultFeatures({
            enableMint_: true,
            enableRedeem_: false,
            enableSwap_: true
        });

        (, uint256[] memory idsOut) = _mintVToken(QTY);

        vm.expectRevert(INFTXVaultV3.RedeemDisabled.selector);
        vtoken.redeem{value: 0}({
            idsOut: idsOut,
            to: address(this),
            wethAmount: 0,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });
    }

    function test_redeem_RevertsIfInsufficientETHSent() external {
        _mintPositionWithTwap(CURRENT_NFT_PRICE);
        (, uint256[] memory idsOut) = _mintVToken(QTY);

        vm.expectRevert(INFTXVaultV3.InsufficientETHSent.selector);
        vtoken.redeem{value: 1 wei}({
            idsOut: idsOut,
            to: address(this),
            wethAmount: 0,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });
    }

    function test_redeem_RevertsIfPremiumLimitExceeded() external {
        _mintPositionWithTwap(CURRENT_NFT_PRICE);
        (, uint256[] memory idsOut) = _mintVToken(QTY);

        vm.expectRevert(INFTXVaultV3.PremiumLimitExceeded.selector);
        vtoken.redeem{value: 0}({
            idsOut: idsOut,
            to: address(this),
            wethAmount: 0,
            vTokenPremiumLimit: 1 wei,
            forceFees: false
        });
    }

    function test_redeem_721_NoPremium_Success() external {
        (
            uint256[] memory idsOut,
            uint256 exactETHPaid,
            uint256 expectedETHPaid
        ) = _twap721AndCalcRedeemETHFees(QTY, CURRENT_NFT_PRICE);

        address to = address(this);

        uint256 prevETHBal = address(this).balance;
        uint256 prevVTokenBal = vtoken.balanceOf(address(this));

        // double ETH value here to check if refund working as well
        vtoken.redeem{value: expectedETHPaid * 2}({
            idsOut: idsOut,
            to: to,
            wethAmount: 0,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });

        uint256 ethPaid = prevETHBal - address(this).balance;
        uint256 vTokenBurned = prevVTokenBal - vtoken.balanceOf(address(this));

        console.log("ethPaid with No Premium", ethPaid);
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);

        assertEq(vTokenBurned, idsOut.length * 1 ether, "!vTokens");
        for (uint i; i < idsOut.length; i++) {
            assertEq(nft.ownerOf(idsOut[i]), to);
        }

        // No residue ETH should be left in the vault
        assertEq(address(vtoken).balance, 0);
    }

    function test_redeem_721_WithPremium_Success() external {
        (
            address depositor,
            uint256[] memory idsOut,
            uint256 exactETHPaid,
            uint256 expectedETHPaid,
            uint256 expectedDepositorShare
        ) = _twap721AndCalcRedeemETHFeesWithPremium(QTY, CURRENT_NFT_PRICE);

        address to = address(this);

        uint256 prevETHBal = address(this).balance;
        uint256 prevDepositorBal = weth.balanceOf(depositor);
        uint256 prevVTokenBal = vtoken.balanceOf(address(this));

        // double ETH value here to check if refund working as well
        vtoken.redeem{value: expectedETHPaid * 2}({
            idsOut: idsOut,
            to: to,
            wethAmount: 0,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });

        uint256 ethPaid = prevETHBal - address(this).balance;
        uint256 ethDepositorReceived = weth.balanceOf(depositor) -
            prevDepositorBal;
        uint256 vTokenBurned = prevVTokenBal - vtoken.balanceOf(address(this));
        console.log("ethPaid with Premium", ethPaid);
        console.log(
            "ethPremium share received by depositor",
            ethDepositorReceived
        );
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);

        assertGt(
            ethDepositorReceived,
            (_valueWithError(expectedDepositorShare) * 980) / 1000 // TODO: verify why higher precision loss here
        );
        assertLe(ethDepositorReceived, expectedDepositorShare);

        assertEq(vTokenBurned, idsOut.length * 1 ether, "!vTokens");
        for (uint i; i < idsOut.length; i++) {
            assertEq(nft.ownerOf(idsOut[i]), to);
        }

        // No residue ETH should be left in the vault
        assertEq(address(vtoken).balance, 0);
    }

    function test_redeem_721_WithPremium_WhenNoPoolExists_Success() external {
        (, uint256[] memory idsOut) = _mintVToken(QTY);

        address to = address(this);

        uint256 prevETHBal = address(this).balance;
        uint256 prevVTokenBal = vtoken.balanceOf(address(this));

        // sending some ETH here to check if refund working as well
        vtoken.redeem{value: 5 ether}({
            idsOut: idsOut,
            to: to,
            wethAmount: 0,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with Premium", ethPaid);
        assertEq(ethPaid, 0);

        uint256 vTokenBurned = prevVTokenBal - vtoken.balanceOf(address(this));
        assertEq(vTokenBurned, idsOut.length * 1 ether, "!vTokens");
        for (uint i; i < idsOut.length; i++) {
            assertEq(nft.ownerOf(idsOut[i]), to);
        }

        // No residue ETH should be left in the vault
        assertEq(address(vtoken).balance, 0);
    }

    function test_redeem_721_ForceFees_WhenOnExcludeList_Success() external {
        // add sender to exclusion list
        vaultFactory.setFeeExclusion(address(this), true);

        (
            uint256[] memory idsOut,
            uint256 exactETHPaid,
            uint256 expectedETHPaid
        ) = _twap721AndCalcRedeemETHFees(QTY, CURRENT_NFT_PRICE);

        address to = address(this);

        uint256 prevETHBal = address(this).balance;
        uint256 prevVTokenBal = vtoken.balanceOf(address(this));

        // double ETH value here to check if refund working as well
        vtoken.redeem{value: expectedETHPaid * 2}({
            idsOut: idsOut,
            to: to,
            wethAmount: 0,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: true // TRUE
        });

        uint256 ethPaid = prevETHBal - address(this).balance;
        uint256 vTokenBurned = prevVTokenBal - vtoken.balanceOf(address(this));

        console.log("ethPaid with No Premium", ethPaid);
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);

        assertEq(vTokenBurned, idsOut.length * 1 ether, "!vTokens");
        for (uint i; i < idsOut.length; i++) {
            assertEq(nft.ownerOf(idsOut[i]), to);
        }

        // No residue ETH should be left in the vault
        assertEq(address(vtoken).balance, 0);
    }

    function test_redeem_721_NoFeesWhenOnExcludeList_WithPremium_Success()
        external
    {
        // add sender to exclusion list
        vaultFactory.setFeeExclusion(address(this), true);

        (
            address depositor,
            uint256[] memory idsOut,
            ,
            ,

        ) = _twap721AndCalcRedeemETHFeesWithPremium(QTY, CURRENT_NFT_PRICE);

        address to = address(this);

        uint256 prevETHBal = address(this).balance;
        uint256 prevDepositorBal = weth.balanceOf(depositor);
        uint256 prevVTokenBal = vtoken.balanceOf(address(this));

        // sending some ETH to test refund
        vtoken.redeem{value: 5 ether}({
            idsOut: idsOut,
            to: to,
            wethAmount: 0,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });

        uint256 ethPaid = prevETHBal - address(this).balance;
        uint256 ethDepositorReceived = weth.balanceOf(depositor) -
            prevDepositorBal;
        uint256 vTokenBurned = prevVTokenBal - vtoken.balanceOf(address(this));

        console.log("ethPaid with Premium", ethPaid);
        console.log(
            "ethPremium share received by depositor",
            ethDepositorReceived
        );
        assertEq(ethPaid, 0);
        assertEq(vTokenBurned, idsOut.length * 1 ether, "!vTokens");
        assertEq(ethDepositorReceived, 0);

        for (uint i; i < idsOut.length; i++) {
            assertEq(nft.ownerOf(idsOut[i]), to);
        }

        // No residue ETH should be left in the vault
        assertEq(address(vtoken).balance, 0);
    }

    // WETH
    function test_redeem_721_RevertsIfETHSentWhenFeesInWeth() external {
        (, uint256[] memory idsOut) = _mintVToken(5);

        uint256 wethFeeAmt = 5 ether;

        vm.expectRevert(INFTXVaultV3.ETHSent.selector);
        vtoken.redeem{value: 1 wei}({
            idsOut: idsOut,
            to: address(this),
            wethAmount: wethFeeAmt,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });
    }

    function test_redeem_721_NoPremium_InWETH_Success() external {
        (
            uint256[] memory idsOut,
            uint256 exactETHPaid,
            uint256 expectedETHPaid
        ) = _twap721AndCalcRedeemETHFees(QTY, CURRENT_NFT_PRICE);

        address to = address(this);

        // mint some WETH
        weth.deposit{value: exactETHPaid}();
        uint256 wethAmount = exactETHPaid;
        weth.approve(address(vtoken), wethAmount);

        uint256 prevWETHBal = weth.balanceOf(address(this));
        uint256 prevVTokenBal = vtoken.balanceOf(address(this));

        vtoken.redeem{value: 0}({
            idsOut: idsOut,
            to: to,
            wethAmount: wethAmount,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });

        uint256 wethPaid = prevWETHBal - weth.balanceOf(address(this));
        console.log("wethPaid with No Premium", wethPaid);
        assertGt(wethPaid, expectedETHPaid);
        assertLe(wethPaid, exactETHPaid);

        uint256 vTokenBurned = prevVTokenBal - vtoken.balanceOf(address(this));
        assertEq(vTokenBurned, idsOut.length * 1 ether, "!vTokens");
        for (uint i; i < idsOut.length; i++) {
            assertEq(nft.ownerOf(idsOut[i]), to);
        }

        // No residue WETH should be left in the vault
        assertEq(weth.balanceOf(address(vtoken)), 0);
    }

    // 1155

    function test_redeem_1155_NoPremium_Success_pointerIndexUpdates() external {
        (
            uint256[] memory idsOut,
            uint256 exactETHPaid,
            uint256 expectedETHPaid
        ) = _twap1155AndCalcRedeemETHFees(QTY, CURRENT_NFT_PRICE);

        address to = address(this);

        uint256 prevETHBal = address(this).balance;
        uint256 prevVTokenBal = vtoken1155.balanceOf(address(this));
        uint256 prevNFTBal = nft1155.balanceOf(address(vtoken1155), idsOut[0]);
        uint256 prevPointerIndex = vtoken1155.pointerIndex1155(idsOut[0]);

        // double ETH value here to check if refund working as well
        vtoken1155.redeem{value: expectedETHPaid * 2}({
            idsOut: idsOut,
            to: to,
            wethAmount: 0,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with No Premium", ethPaid);
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);

        uint256 vTokenBurned = prevVTokenBal -
            vtoken1155.balanceOf(address(this));
        assertEq(vTokenBurned, idsOut.length * 1 ether, "!vTokens");
        assertEq(nft1155.balanceOf(to, idsOut[0]), QTY, "!nft");

        assertEq(
            prevNFTBal - nft1155.balanceOf(address(vtoken1155), idsOut[0]),
            QTY
        );
        assertEq(vtoken1155.pointerIndex1155(idsOut[0]) - prevPointerIndex, 1);

        // No residue ETH should be left in the vault
        assertEq(address(vtoken1155).balance, 0);
    }

    struct RedeemData {
        address depositor;
        address to;
        uint256[] idsOut;
        uint256 exactETHPaid;
        uint256 expectedETHPaid;
        uint256 expectedDepositorShare;
    }
    RedeemData r;

    function test_redeem_1155_WithPremium_Success_samePointerIndex() external {
        (
            r.depositor,
            r.idsOut,
            r.exactETHPaid,
            r.expectedETHPaid,
            r.expectedDepositorShare
        ) = _twap1155AndCalcRedeemETHFeesWithPremium(QTY, CURRENT_NFT_PRICE);

        r.to = address(this);

        uint256 prevETHBal = address(this).balance;
        uint256 prevVTokenBal = vtoken1155.balanceOf(address(this));
        uint256 prevDepositorBal = weth.balanceOf(r.depositor);
        uint256 prevNFTBal = nft1155.balanceOf(
            address(vtoken1155),
            r.idsOut[0]
        );
        uint256 prevPointerIndex = vtoken1155.pointerIndex1155(r.idsOut[0]);

        // double ETH value here to check if refund working as well
        vtoken1155.redeem{value: r.expectedETHPaid * 2}({
            idsOut: r.idsOut,
            to: r.to,
            wethAmount: 0,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });

        uint256 ethPaid = prevETHBal - address(this).balance;
        uint256 vTokenBurned = prevVTokenBal -
            vtoken1155.balanceOf(address(this));
        uint256 ethDepositorReceived = weth.balanceOf(r.depositor) -
            prevDepositorBal;

        console.log("ethPaid with Premium", ethPaid);
        console.log(
            "ethPremium share received by depositor",
            ethDepositorReceived
        );
        assertGt(ethPaid, r.expectedETHPaid);
        assertLe(ethPaid, r.exactETHPaid);
        assertGt(
            ethDepositorReceived,
            (_valueWithError(r.expectedDepositorShare) * 980) / 1000 // TODO: verify why higher precision loss here
        );
        assertLe(ethDepositorReceived, r.expectedDepositorShare);

        assertEq(vTokenBurned, r.idsOut.length * 1 ether, "!vTokens");
        assertEq(nft1155.balanceOf(r.to, r.idsOut[0]), r.idsOut.length, "!nft");

        assertEq(
            prevNFTBal - nft1155.balanceOf(address(vtoken1155), r.idsOut[0]),
            r.idsOut.length
        );
        assertEq(vtoken1155.pointerIndex1155(r.idsOut[0]), prevPointerIndex);

        // No residue ETH should be left in the vault
        assertEq(address(vtoken1155).balance, 0);
    }

    function test_redeem_1155_NoFeesWhenOnExcludeList_WithPremium_Success()
        external
    {
        // add sender to exclusion list
        vaultFactory.setFeeExclusion(address(this), true);

        _mintPositionWithTwap1155(CURRENT_NFT_PRICE);
        (, uint256[] memory idsOut) = _mintVTokenFor1155(QTY);

        address to = address(this);

        uint256 prevETHBal = address(this).balance;
        uint256 prevVTokenBal = vtoken1155.balanceOf(address(this));
        uint256 prevNFTBal = nft1155.balanceOf(address(vtoken1155), idsOut[0]);
        uint256 prevPointerIndex = vtoken1155.pointerIndex1155(idsOut[0]);

        // sending some ETH to test refund
        vtoken1155.redeem{value: 5 ether}({
            idsOut: idsOut,
            to: to,
            wethAmount: 0,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with No Premium", ethPaid);
        assertEq(ethPaid, 0);

        uint256 vTokenBurned = prevVTokenBal -
            vtoken1155.balanceOf(address(this));
        assertEq(vTokenBurned, idsOut.length * 1 ether, "!vTokens");
        assertEq(nft1155.balanceOf(to, idsOut[0]), QTY, "!nft");

        assertEq(
            prevNFTBal - nft1155.balanceOf(address(vtoken1155), idsOut[0]),
            QTY
        );
        assertEq(vtoken1155.pointerIndex1155(idsOut[0]) - prevPointerIndex, 1);

        // No residue ETH should be left in the vault
        assertEq(address(vtoken1155).balance, 0);
    }

    // NFTXVault#swap

    function test_swap_RevertsForNonOwnerIfPaused() external {
        vaultFactory.setIsGuardian(address(this), true);
        vaultFactory.pause(SWAP_PAUSE_CODE);

        (, uint256[] memory idsOut) = _mintVToken(5);

        startHoax(makeAddr("nonOwner"));
        uint256[] memory idsIn = nft.mint(5);

        vm.expectRevert(PausableUpgradeable.Paused.selector);
        vtoken.swap{value: 0}({
            idsIn: idsIn,
            amounts: emptyAmounts,
            idsOut: idsOut,
            depositor: address(this),
            to: address(this),
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });
    }

    function tets_swap_RevertsIfInsufficientETHSent() external {
        _mintPositionWithTwap(CURRENT_NFT_PRICE);
        (, uint256[] memory idsOut) = _mintVToken(5);

        uint256[] memory idsIn = nft.mint(5);

        vm.expectRevert(INFTXVaultV3.InsufficientETHSent.selector);
        vtoken.swap{value: 1 wei}({
            idsIn: idsIn,
            amounts: emptyAmounts,
            idsOut: idsOut,
            depositor: address(this),
            to: address(this),
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });
    }

    function test_swap_RevertsIfPremiumLimitExceeded() external {
        _mintPositionWithTwap(CURRENT_NFT_PRICE);
        (, uint256[] memory idsOut) = _mintVToken(5);

        uint256[] memory idsIn = nft.mint(5);

        vm.expectRevert(INFTXVaultV3.PremiumLimitExceeded.selector);
        vtoken.swap{value: 0}({
            idsIn: idsIn,
            amounts: emptyAmounts,
            idsOut: idsOut,
            depositor: address(this),
            to: address(this),
            vTokenPremiumLimit: 1 wei,
            forceFees: false
        });
    }

    function test_swap_ForceFees_WhenOnExcludeList_Success() external {
        // add sender to exclusion list
        vaultFactory.setFeeExclusion(address(this), true);

        (
            uint256[] memory idsOut,
            uint256[] memory idsIn,
            uint256 exactETHPaid,
            uint256 expectedETHPaid
        ) = _twap721AndCalcSwapETHFees(QTY, CURRENT_NFT_PRICE);

        address depositor = address(this);
        address to = address(this);

        uint256 prevETHBal = address(this).balance;

        // double ETH value here to check if refund working as well
        vtoken.swap{value: expectedETHPaid * 2}({
            idsIn: idsIn,
            amounts: emptyAmounts,
            idsOut: idsOut,
            depositor: depositor,
            to: to,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: true // TRUE
        });

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with No Premium", ethPaid);
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);

        for (uint i; i < QTY; i++) {
            assertEq(nft.ownerOf(idsIn[i]), address(vtoken));
            assertEq(nft.ownerOf(idsOut[i]), to);
        }

        // No residue ETH should be left in the vault
        assertEq(address(vtoken).balance, 0);
    }

    // 721
    function test_swap_721_RevertsForTokenLengthMismatch() external {
        // request less idsOut than idsIn
        (, uint256[] memory idsOut) = _mintVToken(QTY - 1);

        uint256[] memory idsIn = nft.mint(QTY);

        vm.expectRevert(INFTXVaultV3.TokenLengthMismatch.selector);
        vtoken.swap{value: 0}({
            idsIn: idsIn,
            amounts: emptyAmounts,
            idsOut: idsOut,
            depositor: address(this),
            to: address(this),
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });
    }

    function test_swap_721_NoPremium_Success() external {
        (
            uint256[] memory idsOut,
            uint256[] memory idsIn,
            uint256 exactETHPaid,
            uint256 expectedETHPaid
        ) = _twap721AndCalcSwapETHFees(QTY, CURRENT_NFT_PRICE);

        address depositor = address(this);
        address to = address(this);

        uint256 prevETHBal = address(this).balance;

        // double ETH value here to check if refund working as well
        vtoken.swap{value: expectedETHPaid * 2}({
            idsIn: idsIn,
            amounts: emptyAmounts,
            idsOut: idsOut,
            depositor: depositor,
            to: to,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with No Premium", ethPaid);
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);

        for (uint i; i < QTY; i++) {
            assertEq(nft.ownerOf(idsIn[i]), address(vtoken));
            assertEq(nft.ownerOf(idsOut[i]), to);
        }

        // No residue ETH should be left in the vault
        assertEq(address(vtoken).balance, 0);
    }

    function test_swap_721_WithPremium_Success() external {
        (
            address depositor,
            uint256[] memory idsOut,
            uint256[] memory idsIn,
            uint256 exactETHPaid,
            uint256 expectedETHPaid,
            uint256 expectedDepositorShare
        ) = _twap721AndCalcSwapETHFeesWithPremium(QTY, CURRENT_NFT_PRICE);

        address to = address(this);

        uint256 prevETHBal = address(this).balance;
        uint256 prevDepositorBal = weth.balanceOf(depositor);

        nft.setApprovalForAll(address(vtoken), true);
        // double ETH value here to check if refund working as well
        vtoken.swap{value: expectedETHPaid * 2}({
            idsIn: idsIn,
            amounts: emptyAmounts,
            idsOut: idsOut,
            depositor: depositor,
            to: to,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });

        uint256 ethPaid = prevETHBal - address(this).balance;
        uint256 ethDepositorReceived = weth.balanceOf(depositor) -
            prevDepositorBal;
        console.log("ethPaid With Premium", ethPaid);
        console.log(
            "ethPremium share received by depositor",
            ethDepositorReceived
        );
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);
        assertGt(
            ethDepositorReceived,
            (_valueWithError(expectedDepositorShare) * 980) / 1000 // TODO: verify why higher precision loss here
        );
        assertLe(ethDepositorReceived, expectedDepositorShare);

        for (uint i; i < QTY; i++) {
            assertEq(nft.ownerOf(idsIn[i]), address(vtoken));
            assertEq(nft.ownerOf(idsOut[i]), to);
        }

        // No residue ETH should be left in the vault
        assertEq(address(vtoken).balance, 0);
    }

    function test_swap_721_WithPremium_WhenNoPoolExists_Success() external {
        (, uint256[] memory idsOut) = _mintVToken(QTY);
        uint256[] memory idsIn = nft.mint(QTY);

        address depositor = address(this);
        address to = address(this);

        uint256 prevETHBal = address(this).balance;

        // sending some ETH here to check if refund working as well
        vtoken.swap{value: 5 ether}({
            idsIn: idsIn,
            amounts: emptyAmounts,
            idsOut: idsOut,
            depositor: depositor,
            to: to,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with Premium", ethPaid);
        assertEq(ethPaid, 0);

        for (uint i; i < QTY; i++) {
            assertEq(nft.ownerOf(idsIn[i]), address(vtoken));
            assertEq(nft.ownerOf(idsOut[i]), to);
        }

        // No residue ETH should be left in the vault
        assertEq(address(vtoken).balance, 0);
    }

    function test_swap_721_NoFeesWhenOnExcludeList_Success() external {
        (
            uint256[] memory idsOut,
            uint256[] memory idsIn,
            ,

        ) = _twap721AndCalcSwapETHFees(QTY, CURRENT_NFT_PRICE);

        // add sender to exclusion list
        vaultFactory.setFeeExclusion(address(this), true);

        address depositor = address(this);
        address to = address(this);

        uint256 prevETHBal = address(this).balance;

        // sending some ETH to test refund
        vtoken.swap{value: 5 ether}({
            idsIn: idsIn,
            amounts: emptyAmounts,
            idsOut: idsOut,
            depositor: depositor,
            to: to,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with No Premium", ethPaid);
        assertEq(ethPaid, 0);

        for (uint i; i < QTY; i++) {
            assertEq(nft.ownerOf(idsIn[i]), address(vtoken));
            assertEq(nft.ownerOf(idsOut[i]), to);
        }

        // No residue ETH should be left in the vault
        assertEq(address(vtoken).balance, 0);
    }

    // 1155

    function test_swap_1155_RevertsIfAmountIsZero() external {
        (, uint256[] memory idsOut) = _mintVTokenFor1155(QTY);

        uint256[] memory idsIn = new uint256[](2);
        uint256[] memory amountsIn = new uint256[](2);

        idsIn[0] = nft1155.mint(QTY);
        amountsIn[0] = QTY;
        // Set amount zero for this tokenId
        idsIn[1] = nft1155.mint(QTY);
        amountsIn[1] = 0;

        vm.expectRevert(INFTXVaultV3.TransferAmountIsZero.selector);
        vtoken1155.swap{value: 0}({
            idsIn: idsIn,
            amounts: amountsIn,
            idsOut: idsOut,
            depositor: address(this),
            to: address(this),
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });
    }

    function test_swap_1155_RevertsForTokenLengthMismatch() external {
        // request less idsOut than idsIn
        (, uint256[] memory idsOut) = _mintVTokenFor1155(QTY - 1);

        uint256[] memory idsIn = new uint256[](2);
        uint256[] memory amountsIn = new uint256[](2);

        // QTY = 5 = 3 + 2
        idsIn[0] = nft1155.mint(3);
        amountsIn[0] = 3;
        idsIn[1] = nft1155.mint(2);
        amountsIn[1] = 2;

        vm.expectRevert(INFTXVaultV3.TokenLengthMismatch.selector);
        vtoken1155.swap{value: 0}({
            idsIn: idsIn,
            amounts: amountsIn,
            idsOut: idsOut,
            depositor: address(this),
            to: address(this),
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });
    }

    function test_swap_1155_NoPremium_Success() external {
        (
            uint256[] memory idsOut,
            uint256[] memory idsIn,
            uint256[] memory amountsIn,
            uint256 exactETHPaid,
            uint256 expectedETHPaid
        ) = _twap1155AndCalcSwapETHFees(QTY, CURRENT_NFT_PRICE);

        address depositor = address(this);
        address to = address(this);

        uint256 prevETHBal = address(this).balance;

        // double ETH value here to check if refund working as well
        vtoken1155.swap{value: expectedETHPaid * 2}({
            idsIn: idsIn,
            amounts: amountsIn,
            idsOut: idsOut,
            depositor: depositor,
            to: to,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with No Premium", ethPaid);
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);

        assertEq(nft1155.balanceOf(address(vtoken1155), idsIn[0]), QTY);
        assertEq(nft1155.balanceOf(to, idsOut[0]), QTY);

        // No residue ETH should be left in the vault
        assertEq(address(vtoken1155).balance, 0);
    }

    function test_swap_1155_WithPremium_Success() external {
        (
            address depositor,
            uint256[] memory idsOut,
            uint256[] memory idsIn,
            uint256[] memory amountsIn,
            uint256 exactETHPaid,
            uint256 expectedETHPaid,
            uint256 expectedDepositorShare
        ) = _twap1155AndCalcSwapETHFeesWithPremium(QTY, CURRENT_NFT_PRICE);

        address to = address(this);

        uint256 prevETHBal = address(this).balance;
        uint256 prevDepositorBal = weth.balanceOf(depositor);

        nft1155.setApprovalForAll(address(vtoken1155), true);
        // double ETH value here to check if refund working as well
        vtoken1155.swap{value: expectedETHPaid * 2}({
            idsIn: idsIn,
            amounts: amountsIn,
            idsOut: idsOut,
            depositor: depositor,
            to: to,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });

        uint256 ethPaid = prevETHBal - address(this).balance;
        uint256 ethDepositorReceived = weth.balanceOf(depositor) -
            prevDepositorBal;
        console.log("ethPaid with Premium", ethPaid);
        console.log(
            "ethPremium share received by depositor",
            ethDepositorReceived
        );
        assertGt(ethPaid, expectedETHPaid);
        assertLe(ethPaid, exactETHPaid);
        assertGt(
            ethDepositorReceived,
            (_valueWithError(expectedDepositorShare) * 980) / 1000 // TODO: verify why higher precision loss here
        );
        assertLe(ethDepositorReceived, expectedDepositorShare);

        assertEq(nft1155.balanceOf(address(vtoken1155), idsIn[0]), QTY);
        assertEq(nft1155.balanceOf(to, idsOut[0]), QTY);

        // No residue ETH should be left in the vault
        assertEq(address(vtoken1155).balance, 0);
    }

    function test_swap_1155_NoFeesWhenOnExcludeList_Success() external {
        (
            uint256[] memory idsOut,
            uint256[] memory idsIn,
            uint256[] memory amountsIn,
            ,

        ) = _twap1155AndCalcSwapETHFees(QTY, CURRENT_NFT_PRICE);

        // add sender to exclusion list
        vaultFactory.setFeeExclusion(address(this), true);

        address depositor = address(this);
        address to = address(this);

        uint256 prevETHBal = address(this).balance;

        // sending some ETH to test refund
        vtoken1155.swap{value: 5 ether}({
            idsIn: idsIn,
            amounts: amountsIn,
            idsOut: idsOut,
            depositor: depositor,
            to: to,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT,
            forceFees: false
        });

        uint256 ethPaid = prevETHBal - address(this).balance;
        console.log("ethPaid with No Premium", ethPaid);
        assertEq(ethPaid, 0);

        assertEq(nft1155.balanceOf(address(vtoken1155), idsIn[0]), QTY);
        assertEq(nft1155.balanceOf(to, idsOut[0]), QTY);

        // No residue ETH should be left in the vault
        assertEq(address(vtoken1155).balance, 0);
    }

    // NFTXVault#finalizeVault
    function test_finalizeVault_RevertsForNonPrivileged() external {
        // when vault is not finalized
        hoax(makeAddr("nonPrivileged"));
        vm.expectRevert(INFTXVaultV3.NotManager.selector);
        vtoken.finalizeVault();

        _afterVaultFinalized();

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(INFTXVaultV3.NotOwner.selector);
        vtoken.finalizeVault();
    }

    function test_finalizeVault_Success() external {
        vm.expectEmit(false, false, false, true);
        emit ManagerSet(address(0));
        vtoken.finalizeVault();

        assertEq(vtoken.manager(), address(0));
    }

    // NFTXVault#setVaultMetadata
    function test_setVaultMetadata_RevertsForNonPriveleged() external {
        // when vault is not finalized
        hoax(makeAddr("nonPrivileged"));
        vm.expectRevert(INFTXVaultV3.NotManager.selector);
        vtoken.setVaultMetadata("newName", "newSymbol");

        _afterVaultFinalized();

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(INFTXVaultV3.NotOwner.selector);
        vtoken.setVaultMetadata("newName", "newSymbol");
    }

    function test_setVaultMetadata_Success() external {
        string memory name = "newName";
        string memory symbol = "newSymbol";

        vm.expectEmit(false, false, false, true);
        emit MetadataUpdated(name, symbol);
        vtoken.setVaultMetadata(name, symbol);

        assertEq(vtoken.name(), name);
        assertEq(vtoken.symbol(), symbol);
    }

    // NFTXVault#setVaultFeatures
    function test_setVaultFeatures_RevertsForNonPriveleged() external {
        // when vault is not finalized
        hoax(makeAddr("nonPrivileged"));
        vm.expectRevert(INFTXVaultV3.NotManager.selector);
        vtoken.setVaultFeatures(false, false, false);

        _afterVaultFinalized();

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(INFTXVaultV3.NotOwner.selector);
        vtoken.setVaultFeatures(false, false, false);
    }

    function test_setVaultFeatures_Success(
        bool enableMint,
        bool enableRedeem,
        bool enableSwap
    ) external {
        vm.expectEmit(false, false, false, true);
        emit EnableMintUpdated(enableMint);
        vm.expectEmit(false, false, false, true);
        emit EnableRedeemUpdated(enableRedeem);
        vm.expectEmit(false, false, false, true);
        emit EnableSwapUpdated(enableSwap);
        vtoken.setVaultFeatures(enableMint, enableRedeem, enableSwap);

        assertEq(vtoken.enableMint(), enableMint);
        assertEq(vtoken.enableRedeem(), enableRedeem);
        assertEq(vtoken.enableSwap(), enableSwap);
    }

    // NFTXVault#setFees
    function test_setFees_RevertsForNonPriveleged() external {
        // when vault is not finalized
        hoax(makeAddr("nonPrivileged"));
        vm.expectRevert(INFTXVaultV3.NotManager.selector);
        vtoken.setFees(0, 0, 0);

        _afterVaultFinalized();

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(INFTXVaultV3.NotOwner.selector);
        vtoken.setFees(0, 0, 0);
    }

    function test_setFees_Success(
        uint256 mintFee,
        uint256 redeemFee,
        uint256 swapFee
    ) external {
        vm.assume(mintFee >= 0 && mintFee < 0.5 ether);
        vm.assume(redeemFee >= 0 && redeemFee < 0.5 ether);
        vm.assume(swapFee >= 0 && swapFee < 0.5 ether);

        vm.expectEmit(false, false, false, true);
        emit UpdateVaultFees(vtoken.vaultId(), mintFee, redeemFee, swapFee);
        vtoken.setFees(mintFee, redeemFee, swapFee);

        (uint256 _mintFee, uint256 _redeemFee, uint256 _swapFee) = vtoken
            .vaultFees();
        assertEq(_mintFee, mintFee);
        assertEq(_redeemFee, redeemFee);
        assertEq(_swapFee, swapFee);
    }

    // NFTXVault#disableVaultFees
    function test_disableVaultFees_RevertsForNonPriveleged() external {
        // when vault is not finalized
        hoax(makeAddr("nonPrivileged"));
        vm.expectRevert(INFTXVaultV3.NotManager.selector);
        vtoken.disableVaultFees();

        _afterVaultFinalized();

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(INFTXVaultV3.NotOwner.selector);
        vtoken.disableVaultFees();
    }

    function test_disableVaultFees_Success() external {
        vtoken.setFees(0.4 ether, 0.4 ether, 0.4 ether);
        (uint256 _mintFee, uint256 _redeemFee, uint256 _swapFee) = vtoken
            .vaultFees();
        assertTrue(_mintFee != vaultFactory.factoryMintFee());
        assertTrue(_redeemFee != vaultFactory.factoryRedeemFee());
        assertTrue(_swapFee != vaultFactory.factorySwapFee());

        vm.expectEmit(false, false, false, true);
        emit DisableVaultFees(vtoken.vaultId());
        vtoken.disableVaultFees();

        (_mintFee, _redeemFee, _swapFee) = vtoken.vaultFees();
        assertEq(_mintFee, vaultFactory.factoryMintFee());
        assertEq(_redeemFee, vaultFactory.factoryRedeemFee());
        assertEq(_swapFee, vaultFactory.factorySwapFee());
    }

    // NFTXVault#deployEligibilityStorage
    function test_deployEligibilityStorage_RevertsForNonPriveleged() external {
        // when vault is not finalized
        hoax(makeAddr("nonPrivileged"));
        vm.expectRevert(INFTXVaultV3.NotManager.selector);
        vtoken.deployEligibilityStorage({
            moduleIndex: RANGE_MODULE_INDEX,
            initData: abi.encode(0, 100)
        });

        _afterVaultFinalized();

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(INFTXVaultV3.NotOwner.selector);
        vtoken.deployEligibilityStorage({
            moduleIndex: RANGE_MODULE_INDEX,
            initData: abi.encode(0, 100)
        });
    }

    function test_deployEligibilityStorage_RevertsIfAlreadySet() external {
        vtoken.deployEligibilityStorage({
            moduleIndex: RANGE_MODULE_INDEX,
            initData: abi.encode(0, 100)
        });

        vm.expectRevert(INFTXVaultV3.EligibilityAlreadySet.selector);
        vtoken.deployEligibilityStorage({
            moduleIndex: RANGE_MODULE_INDEX,
            initData: abi.encode(0, 100)
        });
    }

    function test_deployEligibilityStorage_Success() external {
        vm.expectEmit(
            false,
            false,
            false,
            false // the _eligibility address is not known here, so not checking the value
        );
        emit EligibilityDeployed(RANGE_MODULE_INDEX, address(0));
        address _eligibility = vtoken.deployEligibilityStorage({
            moduleIndex: RANGE_MODULE_INDEX,
            initData: abi.encode(0, 100)
        });

        assertTrue(address(vtoken.eligibilityStorage()) != address(0));
        assertEq(address(vtoken.eligibilityStorage()), _eligibility);
        assertEq(vtoken.allowAllItems(), false);
    }

    // NFTXVault#setManager
    function test_setManager_RevertsForNonPriveleged() external {
        address newManager = makeAddr("newManager");

        // when vault is not finalized
        hoax(makeAddr("nonPrivileged"));
        vm.expectRevert(INFTXVaultV3.NotManager.selector);
        vtoken.setManager(newManager);

        _afterVaultFinalized();

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(INFTXVaultV3.NotOwner.selector);
        vtoken.setManager(newManager);
    }

    function test_setManager_Success() external {
        address newManager = makeAddr("newManager");

        vm.expectEmit(false, false, false, true);
        emit ManagerSet(newManager);
        vtoken.setManager(newManager);

        assertEq(vtoken.manager(), newManager);
    }

    // NFTXVault#updateDelegate
    function test_updateDelegate_RevertsForNonPriveleged() external {
        // when vault is not finalized
        hoax(makeAddr("nonPrivileged"));
        vm.expectRevert(INFTXVaultV3.NotManager.selector);
        vtoken.updateDelegate();

        _afterVaultFinalized();

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(INFTXVaultV3.NotOwner.selector);
        vtoken.updateDelegate();
    }

    function test_updateDelegate_Success() external {
        address newOwner = makeAddr("newOwner");
        vaultFactory.transferOwnership(newOwner);

        vtoken.updateDelegate();
        assertEq(
            DELEGATE_REGISTRY.checkDelegateForAll(
                newOwner,
                address(vtoken),
                bytes32("")
            ),
            true
        );
    }

    // NFTXVault#rescueTokens
    function test_rescueTokens_RevertsForNonOwnerAndManager() external {
        hoax(makeAddr("nonOwner"));
        vm.expectRevert(OwnableUpgradeable.CallerIsNotTheOwner.selector);
        vtoken.rescueTokens({
            tt: INFTXVaultV3.TokenType.ERC20,
            token: address(0),
            ids: emptyIds,
            amounts: emptyAmounts
        });

        // setting manager different than owner
        address newManager = makeAddr("newManager");
        vtoken.setManager(newManager);
        hoax(newManager);
        vm.expectRevert(OwnableUpgradeable.CallerIsNotTheOwner.selector);
        vtoken.rescueTokens({
            tt: INFTXVaultV3.TokenType.ERC20,
            token: address(0),
            ids: emptyIds,
            amounts: emptyAmounts
        });
    }

    // ERC20
    function test_rescueTokens_ERC20_Success() external {
        // send weth (erc20) to the vault
        uint256 amount = 1 ether;
        weth.deposit{value: amount}();
        weth.transfer(address(vtoken), amount);

        uint256 prevBal = weth.balanceOf(address(this));
        vtoken.rescueTokens({
            tt: INFTXVaultV3.TokenType.ERC20,
            token: address(weth),
            ids: emptyIds,
            amounts: emptyAmounts
        });
        assertEq(weth.balanceOf(address(this)), prevBal + amount);
    }

    // ERC721
    function test_rescueTokens_ERC721_RevertsForAssetToken() external {
        vm.expectRevert(INFTXVaultV3.CantRescueAssetToken.selector);
        vtoken.rescueTokens({
            tt: INFTXVaultV3.TokenType.ERC721,
            token: address(nft),
            ids: emptyIds,
            amounts: emptyAmounts
        });
    }

    function test_rescueTokens_ERC721_Success() external {
        MockNFT newNFT = new MockNFT();
        uint256[] memory tokenIds = newNFT.mint(QTY);

        for (uint256 i; i < tokenIds.length; i++) {
            newNFT.transferFrom({
                from: address(this),
                to: address(vtoken),
                tokenId: tokenIds[i]
            });
        }

        vtoken.rescueTokens({
            tt: INFTXVaultV3.TokenType.ERC721,
            token: address(newNFT),
            ids: tokenIds,
            amounts: emptyAmounts
        });

        for (uint256 i; i < tokenIds.length; i++) {
            assertEq(newNFT.ownerOf(tokenIds[i]), address(this));
        }
    }

    // 1155
    function test_rescueTokens_ERC1155_RevertsForAssetToken() external {
        vm.expectRevert(INFTXVaultV3.CantRescueAssetToken.selector);
        vtoken1155.rescueTokens({
            tt: INFTXVaultV3.TokenType.ERC1155,
            token: address(nft1155),
            ids: emptyIds,
            amounts: emptyAmounts
        });
    }

    function test_rescueTokens_ERC1155_Success() external {
        Mock1155 newNFT1155 = new Mock1155();
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        tokenIds[0] = newNFT1155.mint(QTY);
        amounts[0] = QTY;

        newNFT1155.safeBatchTransferFrom({
            from: address(this),
            to: address(vtoken1155),
            ids: tokenIds,
            amounts: amounts,
            data: ""
        });

        vtoken1155.rescueTokens({
            tt: INFTXVaultV3.TokenType.ERC1155,
            token: address(newNFT1155),
            ids: tokenIds,
            amounts: amounts
        });

        for (uint256 i; i < tokenIds.length; i++) {
            assertEq(newNFT1155.balanceOf(address(this), tokenIds[0]), QTY);
        }
    }

    // NFTXVault#shutdown
    function test_shutdown_RevertsForNonOwnerAndManager() external {
        hoax(makeAddr("nonOwner"));
        vm.expectRevert(OwnableUpgradeable.CallerIsNotTheOwner.selector);
        vtoken.shutdown({recipient: address(this), tokenIds: emptyIds});

        // setting manager different than owner
        address newManager = makeAddr("newManager");
        vtoken.setManager(newManager);
        hoax(newManager);
        vm.expectRevert(OwnableUpgradeable.CallerIsNotTheOwner.selector);
        vtoken.shutdown({recipient: address(this), tokenIds: emptyIds});
    }

    function test_shutdown_RevertsForTooManyItems() external {
        // have more than 4 items in the vault
        (, uint256[] memory tokenIds) = _mintVToken(5);

        vm.expectRevert(INFTXVaultV3.TooManyItems.selector);
        vtoken.shutdown({recipient: address(this), tokenIds: tokenIds});
    }

    function test_shutdown_721_Success() external {
        (, uint256[] memory tokenIds) = _mintVToken(3);

        vm.expectEmit(false, false, false, true);
        emit VaultShutdown(address(nft), tokenIds.length, address(this));
        vtoken.shutdown({recipient: address(this), tokenIds: tokenIds});

        assertEq(vtoken.assetAddress(), address(0));
        for (uint256 i; i < tokenIds.length; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), address(this));
        }
    }

    function test_shutdown_1155_Success() external {
        uint256 qty = 3;
        (, uint256[] memory tokenIds) = _mintVTokenFor1155(qty);

        vm.expectEmit(false, false, false, true);
        emit VaultShutdown(address(nft1155), tokenIds.length, address(this));
        vtoken1155.shutdown({recipient: address(this), tokenIds: tokenIds});

        assertEq(vtoken1155.assetAddress(), address(0));
        assertEq(nft1155.balanceOf(address(this), tokenIds[0]), qty);
    }

    // =============================================================
    //                        INTERNAL HELPERS
    // =============================================================
    function _post721MintChecks(
        uint256[] memory tokenIds,
        address expectedDepositor,
        address expectedTo
    ) internal {
        assertEq(
            vtoken.balanceOf(expectedTo),
            tokenIds.length * 1 ether,
            "!vTokens"
        );

        for (uint i; i < tokenIds.length; i++) {
            assertEq(nft.ownerOf(tokenIds[i]), address(vtoken), "!ownerOf");

            (uint48 timestamp, address depositor) = vtoken.tokenDepositInfo(
                tokenIds[i]
            );
            assertEq(depositor, expectedDepositor, "!depositor");
            assertEq(timestamp, block.timestamp, "!timestamp");
        }

        // No residue ETH should be left in the vault
        assertEq(address(vtoken).balance, 0);
    }

    function _afterVaultFinalized() internal {
        vtoken.finalizeVault();
        assertEq(vtoken.manager(), address(0));
    }
}
