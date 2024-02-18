// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console, stdError} from "forge-std/Test.sol";

import {FullMath} from "@uni-core/libraries/FullMath.sol";
import {FixedPoint128} from "@uni-core/libraries/FixedPoint128.sol";
import {PausableUpgradeable} from "@src/custom/PausableUpgradeable.sol";

import {MockNFT} from "@mocks/MockNFT.sol";
import {NFTXInventoryStakingV3Upgradeable, INFTXInventoryStakingV3} from "@src/NFTXInventoryStakingV3Upgradeable.sol";
import {InventoryStakingDescriptor} from "@src/custom/InventoryStakingDescriptor.sol";

import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {INFTXVaultV3} from "@src/interfaces/INFTXVaultV3.sol";
import {ITimelockExcludeList} from "@src/interfaces/ITimelockExcludeList.sol";
import {IPermitAllowanceTransfer} from "@src/interfaces/external/IPermitAllowanceTransfer.sol";

import {TestBase} from "@test/TestBase.sol";

contract NFTXInventoryStakingV3Tests is TestBase {
    uint256 constant DEPOSIT_PAUSE_CODE = 0;
    uint256 constant DEPOSITWITHNFT_PAUSE_CODE = 1;
    uint256 constant WITHDRAW_PAUSE_CODE = 2;
    uint256 constant COLLECTWETHFEES_PAUSE_CODE = 3;
    uint256 constant INCREASEPOSITION_PAUSE_CODE = 4;

    uint256 constant VTOKEN_TIMELOCK = 1 hours;

    event Deposit(
        uint256 indexed vaultId,
        uint256 indexed positionId,
        uint256 amount,
        bool forceTimelock
    );
    event DepositWithNFT(
        uint256 indexed vaultId,
        uint256 indexed positionId,
        uint256[] tokenIds,
        uint256[] amounts
    );
    event IncreasePosition(
        uint256 indexed vaultId,
        uint256 indexed positionId,
        uint256 amount
    );
    event Withdraw(
        uint256 indexed positionId,
        uint256 vTokenShares,
        uint256 vTokenAmount,
        uint256 wethAmount
    );
    event CollectWethFees(uint256 indexed positionId, uint256 wethAmount);
    event UpdateTimelock(uint256 newTimelock);
    event UpdateEarlyWithdrawPenalty(uint256 newEarlyWithdrawPenaltyInWei);

    // InventoryStaking#init

    function test_init_RevertsWhenTimelockTooLong() external {
        uint256 timelock = 15 days;
        uint256 earlyWithdrawPenaltyInWei = 0.05 ether;

        inventoryStaking = new NFTXInventoryStakingV3Upgradeable(
            IWETH9(address(weth)),
            IPermitAllowanceTransfer(address(permit2)),
            vaultFactory
        );
        vm.expectRevert(INFTXInventoryStakingV3.TimelockTooLong.selector);
        inventoryStaking.__NFTXInventoryStaking_init({
            timelock_: timelock,
            earlyWithdrawPenaltyInWei_: earlyWithdrawPenaltyInWei,
            timelockExcludeList_: ITimelockExcludeList(
                address(timelockExcludeList)
            ),
            descriptor_: inventoryDescriptor
        });
    }

    function test_init_RevertsForInvalidEarlyWithdrawPenalty() external {
        uint256 timelock = 2 days;
        uint256 earlyWithdrawPenaltyInWei = 2 ether;

        inventoryStaking = new NFTXInventoryStakingV3Upgradeable(
            IWETH9(address(weth)),
            IPermitAllowanceTransfer(address(permit2)),
            vaultFactory
        );
        vm.expectRevert(
            INFTXInventoryStakingV3.InvalidEarlyWithdrawPenalty.selector
        );
        inventoryStaking.__NFTXInventoryStaking_init({
            timelock_: timelock,
            earlyWithdrawPenaltyInWei_: earlyWithdrawPenaltyInWei,
            timelockExcludeList_: ITimelockExcludeList(
                address(timelockExcludeList)
            ),
            descriptor_: inventoryDescriptor
        });
    }

    function test_init_RevertsIfAlreadyInitialized() external {
        uint256 timelock = 2 days;
        uint256 earlyWithdrawPenaltyInWei = 0.05 ether;

        inventoryStaking = new NFTXInventoryStakingV3Upgradeable(
            IWETH9(address(weth)),
            IPermitAllowanceTransfer(address(permit2)),
            vaultFactory
        );
        inventoryStaking.__NFTXInventoryStaking_init({
            timelock_: timelock,
            earlyWithdrawPenaltyInWei_: earlyWithdrawPenaltyInWei,
            timelockExcludeList_: ITimelockExcludeList(
                address(timelockExcludeList)
            ),
            descriptor_: inventoryDescriptor
        });

        vm.expectRevert("Initializable: contract is already initialized");
        inventoryStaking.__NFTXInventoryStaking_init({
            timelock_: timelock,
            earlyWithdrawPenaltyInWei_: earlyWithdrawPenaltyInWei,
            timelockExcludeList_: ITimelockExcludeList(
                address(timelockExcludeList)
            ),
            descriptor_: inventoryDescriptor
        });
    }

    function test_init_Success() external {
        uint256 timelock = 2 days;
        uint256 earlyWithdrawPenaltyInWei = 0.05 ether;

        inventoryStaking = new NFTXInventoryStakingV3Upgradeable(
            IWETH9(address(weth)),
            IPermitAllowanceTransfer(address(permit2)),
            vaultFactory
        );
        inventoryStaking.__NFTXInventoryStaking_init({
            timelock_: timelock,
            earlyWithdrawPenaltyInWei_: earlyWithdrawPenaltyInWei,
            timelockExcludeList_: ITimelockExcludeList(
                address(timelockExcludeList)
            ),
            descriptor_: inventoryDescriptor
        });

        assertEq(address(inventoryStaking.WETH()), address(weth));
        assertEq(address(inventoryStaking.PERMIT2()), address(permit2));
        assertEq(
            address(inventoryStaking.nftxVaultFactory()),
            address(vaultFactory)
        );
        assertEq(inventoryStaking.owner(), address(this));
        assertEq(inventoryStaking.name(), "NFTX Inventory Staking");
        assertEq(inventoryStaking.symbol(), "xNFT");
        assertEq(inventoryStaking.timelock(), timelock);
        assertEq(
            inventoryStaking.earlyWithdrawPenaltyInWei(),
            earlyWithdrawPenaltyInWei
        );
        assertEq(
            address(inventoryStaking.timelockExcludeList()),
            address(timelockExcludeList)
        );
    }

    // InventoryStaking#deposit

    function test_deposit_RevertsForNonOwnerIfPaused() external {
        inventoryStaking.pause(DEPOSIT_PAUSE_CODE);

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(PausableUpgradeable.Paused.selector);
        inventoryStaking.deposit({
            vaultId: VAULT_ID,
            amount: 0,
            recipient: address(this),
            encodedPermit2: "",
            viaPermit2: false,
            forceTimelock: false
        });
    }

    function test_deposit_RevertsForInvalidVaultId() external {
        vm.expectRevert(stdError.indexOOBError);
        inventoryStaking.deposit({
            vaultId: 999,
            amount: 0,
            recipient: address(this),
            encodedPermit2: "",
            viaPermit2: false,
            forceTimelock: false
        });
    }

    function test_deposit_RevertsForLiqBelowMin_WhenPreTotalSharesZero(
        uint256 vTokensToDeposit
    ) external {
        vm.assume(vTokensToDeposit < 1_000);

        (uint256 preTotalVTokenShares, ) = inventoryStaking.vaultGlobal(
            VAULT_ID
        );
        assertEq(preTotalVTokenShares, 0);

        _mintVToken(3);

        vtoken.approve(address(inventoryStaking), type(uint256).max);

        vm.expectRevert(INFTXInventoryStakingV3.LiquidityBelowMinimum.selector);
        inventoryStaking.deposit({
            vaultId: VAULT_ID,
            amount: vTokensToDeposit,
            recipient: address(this),
            encodedPermit2: "",
            viaPermit2: false,
            forceTimelock: false
        });
    }

    function test_deposit_Success_WhenPreTotalSharesZero() external {
        (
            uint256 preTotalVTokenShares,
            uint256 globalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);
        assertEq(preTotalVTokenShares, 0);

        (uint256 mintedVTokens, ) = _mintVToken(3);

        vtoken.approve(address(inventoryStaking), type(uint256).max);
        address recipient = makeAddr("recipient");
        vm.expectEmit(true, true, false, true);
        emit Deposit(VAULT_ID, 1, mintedVTokens, false);
        uint256 positionId = inventoryStaking.deposit({
            vaultId: VAULT_ID,
            amount: mintedVTokens,
            recipient: recipient,
            encodedPermit2: "",
            viaPermit2: false,
            forceTimelock: false
        });

        assertEq(positionId, 1);
        // mints position nft to the recipient
        assertEq(inventoryStaking.ownerOf(positionId), recipient);

        (
            uint256 nonce,
            uint256 vaultId,
            uint256 timelockedUntil,
            uint256 vTokenShareBalance,
            uint256 wethFeesPerVTokenShareSnapshotX128,
            uint256 wethOwed
        ) = _getPositionDeposit(positionId);
        assertEq(nonce, 0);
        assertEq(vaultId, VAULT_ID);
        assertEq(timelockedUntil, 0);
        assertEq(
            vTokenShareBalance,
            mintedVTokens - inventoryStaking.MINIMUM_LIQUIDITY()
        );
        assertEq(
            wethFeesPerVTokenShareSnapshotX128,
            globalWethFeesPerVTokenShareX128
        );
        assertEq(wethOwed, 0);

        // should update total vToken shares
        (uint256 postTotalVTokenShares, ) = inventoryStaking.vaultGlobal(
            VAULT_ID
        );
        assertEq(postTotalVTokenShares, mintedVTokens);
    }

    function test_deposit_Success_WhenPreTotalSharesNonZero() external {
        // initial stake to make totalVTokenShares non zero
        _mintXNFT(1);

        uint256 preNetVTokenBalance = vtoken.balanceOf(
            address(inventoryStaking)
        );
        (
            uint256 preTotalVTokenShares,
            uint256 globalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);
        assertTrue(preTotalVTokenShares != 0);

        (uint256 mintedVTokens, ) = _mintVToken(3);
        address recipient = makeAddr("recipient");

        vm.expectEmit(true, true, false, true);
        emit Deposit(VAULT_ID, 2, mintedVTokens, false);
        uint256 positionId = inventoryStaking.deposit({
            vaultId: VAULT_ID,
            amount: mintedVTokens,
            recipient: recipient,
            encodedPermit2: "",
            viaPermit2: false,
            forceTimelock: false
        });

        // mints position nft to the recipient
        assertEq(inventoryStaking.ownerOf(positionId), recipient);

        (
            uint256 nonce,
            uint256 vaultId,
            uint256 timelockedUntil,
            uint256 vTokenShareBalance,
            uint256 wethFeesPerVTokenShareSnapshotX128,
            uint256 wethOwed
        ) = _getPositionDeposit(positionId);
        assertEq(nonce, 0);
        assertEq(vaultId, VAULT_ID);
        assertEq(timelockedUntil, 0);
        assertEq(
            vTokenShareBalance,
            (mintedVTokens * preTotalVTokenShares) / preNetVTokenBalance
        );
        assertEq(
            wethFeesPerVTokenShareSnapshotX128,
            globalWethFeesPerVTokenShareX128
        );
        assertEq(wethOwed, 0);

        // should update total vToken shares
        (uint256 postTotalVTokenShares, ) = inventoryStaking.vaultGlobal(
            VAULT_ID
        );
        assertEq(
            postTotalVTokenShares,
            preTotalVTokenShares + vTokenShareBalance
        );
    }

    function test_depositWithPermit2_Success_WhenPreTotalSharesZero() external {
        (
            uint256 preTotalVTokenShares,
            uint256 globalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);
        assertEq(preTotalVTokenShares, 0);

        (uint256 mintedVTokens, ) = _mintVToken(3);
        vtoken.transfer(from, mintedVTokens);
        startHoax(from);

        bytes memory encodedPermit2 = _getEncodedPermit2({
            token: address(vtoken),
            amount: mintedVTokens,
            spender: address(inventoryStaking)
        });
        // TODO: define recipient address once in TestBase
        address recipient = makeAddr("recipient");
        vm.expectEmit(true, true, false, true);
        emit Deposit(VAULT_ID, 1, mintedVTokens, false);
        uint256 positionId = inventoryStaking.deposit({
            vaultId: VAULT_ID,
            amount: mintedVTokens,
            recipient: recipient,
            encodedPermit2: encodedPermit2,
            viaPermit2: true,
            forceTimelock: false
        });

        assertEq(positionId, 1);
        // mints position nft to the recipient
        assertEq(inventoryStaking.ownerOf(positionId), recipient);

        (
            uint256 nonce,
            uint256 vaultId,
            uint256 timelockedUntil,
            uint256 vTokenShareBalance,
            uint256 wethFeesPerVTokenShareSnapshotX128,
            uint256 wethOwed
        ) = _getPositionDeposit(positionId);
        assertEq(nonce, 0);
        assertEq(vaultId, VAULT_ID);
        assertEq(timelockedUntil, 0);
        assertEq(
            vTokenShareBalance,
            mintedVTokens - inventoryStaking.MINIMUM_LIQUIDITY()
        );
        assertEq(
            wethFeesPerVTokenShareSnapshotX128,
            globalWethFeesPerVTokenShareX128
        );
        assertEq(wethOwed, 0);

        // should update total vToken shares
        (uint256 postTotalVTokenShares, ) = inventoryStaking.vaultGlobal(
            VAULT_ID
        );
        assertEq(postTotalVTokenShares, mintedVTokens);
    }

    function test_depositWithPermit2_Success_EmptyEncodedPermit2() external {
        (uint256 _mintedVTokens, ) = _mintVToken(3);
        vtoken.transfer(from, _mintedVTokens);
        startHoax(from);

        {
            bytes memory encodedPermit2 = _getEncodedPermit2({
                token: address(vtoken),
                amount: type(uint160).max, // MAX
                spender: address(inventoryStaking)
            });
            inventoryStaking.deposit({
                vaultId: VAULT_ID,
                amount: _mintedVTokens,
                recipient: address(this),
                encodedPermit2: encodedPermit2,
                viaPermit2: true,
                forceTimelock: false
            });
        }

        (, uint256 globalWethFeesPerVTokenShareX128) = inventoryStaking
            .vaultGlobal(VAULT_ID);

        vm.stopPrank();
        (uint256 mintedVTokens, ) = _mintVToken(3);
        vtoken.transfer(from, mintedVTokens);
        startHoax(from);

        // first position already minted above
        uint256 expectedPositionId = 1 + 1;

        address recipient = makeAddr("recipient");
        vm.expectEmit(true, true, false, true);
        emit Deposit(VAULT_ID, expectedPositionId, mintedVTokens, false);
        uint256 positionId = inventoryStaking.deposit({
            vaultId: VAULT_ID,
            amount: mintedVTokens,
            recipient: recipient,
            encodedPermit2: "", // EMPTY
            viaPermit2: true, // TRUE
            forceTimelock: false
        });

        assertEq(positionId, expectedPositionId);
        // mints position nft to the recipient
        assertEq(inventoryStaking.ownerOf(positionId), recipient);

        (
            uint256 nonce,
            uint256 vaultId,
            uint256 timelockedUntil,
            uint256 vTokenShareBalance,
            uint256 wethFeesPerVTokenShareSnapshotX128,
            uint256 wethOwed
        ) = _getPositionDeposit(positionId);
        assertEq(nonce, 0);
        assertEq(vaultId, VAULT_ID);
        assertEq(timelockedUntil, 0);
        assertEq(vTokenShareBalance, mintedVTokens);
        assertEq(
            wethFeesPerVTokenShareSnapshotX128,
            globalWethFeesPerVTokenShareX128
        );
        assertEq(wethOwed, 0);

        // should update total vToken shares
        (uint256 postTotalVTokenShares, ) = inventoryStaking.vaultGlobal(
            VAULT_ID
        );
        assertEq(postTotalVTokenShares, _mintedVTokens + mintedVTokens);
    }

    // InventoryStaking#depositWithNFT

    function test_depositWithNFT_RevertsForNonOwnerIfPaused() external {
        inventoryStaking.pause(DEPOSITWITHNFT_PAUSE_CODE);
        uint256[] memory tokenIds;

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(PausableUpgradeable.Paused.selector);
        inventoryStaking.depositWithNFT({
            vaultId: VAULT_ID,
            tokenIds: tokenIds,
            amounts: emptyAmounts,
            recipient: address(this)
        });
    }

    function test_depositWithNFT_RevertsForInvalidVaultId() external {
        uint256[] memory tokenIds;

        vm.expectRevert(stdError.indexOOBError);
        inventoryStaking.depositWithNFT({
            vaultId: 999,
            tokenIds: tokenIds,
            amounts: emptyAmounts,
            recipient: address(this)
        });
    }

    function test_depositWithNFT_721_Success_WhenPreTotalSharesZero() external {
        (
            uint256 preTotalVTokenShares,
            uint256 globalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);
        assertEq(preTotalVTokenShares, 0);

        uint256 mintedVTokens;
        uint256[] memory tokenIds;

        {
            uint256 nftQty = 3;
            mintedVTokens = nftQty * 1 ether;
            tokenIds = nft.mint(nftQty);
            nft.setApprovalForAll(address(inventoryStaking), true);
        }

        address recipient = makeAddr("recipient");
        vm.expectEmit(true, true, false, true);
        emit DepositWithNFT(VAULT_ID, 1, tokenIds, emptyAmounts);
        uint256 positionId = inventoryStaking.depositWithNFT({
            vaultId: VAULT_ID,
            tokenIds: tokenIds,
            amounts: emptyAmounts,
            recipient: recipient
        });

        assertEq(positionId, 1);
        // mints position nft to the recipient
        assertEq(inventoryStaking.ownerOf(positionId), recipient);

        (
            uint256 nonce,
            uint256 vaultId,
            uint256 timelockedUntil,
            uint256 vTokenShareBalance,
            uint256 wethFeesPerVTokenShareSnapshotX128,
            uint256 wethOwed
        ) = _getPositionDeposit(positionId);
        assertEq(nonce, 0);
        assertEq(vaultId, VAULT_ID);
        assertEq(
            timelockedUntil,
            block.timestamp + inventoryStaking.timelock()
        );
        assertEq(
            vTokenShareBalance,
            mintedVTokens - inventoryStaking.MINIMUM_LIQUIDITY()
        );
        assertEq(
            wethFeesPerVTokenShareSnapshotX128,
            globalWethFeesPerVTokenShareX128
        );
        assertEq(wethOwed, 0);

        // should update total vToken shares
        (uint256 postTotalVTokenShares, ) = inventoryStaking.vaultGlobal(
            VAULT_ID
        );
        assertEq(postTotalVTokenShares, mintedVTokens);
    }

    // TODO: use modifiers for pre and post checks (store the intermediate vars in storage if required)
    function test_depositWithNFT_721_Success_WhenPreTotalSharesNonZero()
        external
    {
        // initial stake to make totalVTokenShares non zero
        _mintXNFT(1);

        uint256 preNetVTokenBalance = vtoken.balanceOf(
            address(inventoryStaking)
        );
        (
            uint256 preTotalVTokenShares,
            uint256 globalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);
        assertTrue(preTotalVTokenShares != 0);

        uint256 mintedVTokens;
        uint256[] memory tokenIds;

        {
            uint256 nftQty = 3;
            mintedVTokens = nftQty * 1 ether;
            tokenIds = nft.mint(nftQty);
            nft.setApprovalForAll(address(inventoryStaking), true);
        }

        address recipient = makeAddr("recipient");

        vm.expectEmit(true, true, false, true);
        emit DepositWithNFT(VAULT_ID, 2, tokenIds, emptyAmounts);
        uint256 positionId = inventoryStaking.depositWithNFT({
            vaultId: VAULT_ID,
            tokenIds: tokenIds,
            amounts: emptyAmounts,
            recipient: recipient
        });

        // mints position nft to the recipient
        assertEq(inventoryStaking.ownerOf(positionId), recipient);

        (
            uint256 nonce,
            uint256 vaultId,
            uint256 timelockedUntil,
            uint256 vTokenShareBalance,
            uint256 wethFeesPerVTokenShareSnapshotX128,
            uint256 wethOwed
        ) = _getPositionDeposit(positionId);
        assertEq(nonce, 0);
        assertEq(vaultId, VAULT_ID);
        assertEq(
            timelockedUntil,
            block.timestamp + inventoryStaking.timelock()
        );
        assertEq(
            vTokenShareBalance,
            (mintedVTokens * preTotalVTokenShares) / preNetVTokenBalance
        );
        assertEq(
            wethFeesPerVTokenShareSnapshotX128,
            globalWethFeesPerVTokenShareX128
        );
        assertEq(wethOwed, 0);

        // should update total vToken shares
        (uint256 postTotalVTokenShares, ) = inventoryStaking.vaultGlobal(
            VAULT_ID
        );
        assertEq(
            postTotalVTokenShares,
            preTotalVTokenShares + vTokenShareBalance
        );
    }

    function test_depositWithNFT_721_Success_WhenOnTimelockExcludeList()
        external
    {
        timelockExcludeList.setExcludeFromAll(address(this), true);

        // initial stake to make totalVTokenShares non zero
        _mintXNFT(1);

        uint256 preNetVTokenBalance = vtoken.balanceOf(
            address(inventoryStaking)
        );
        (
            uint256 preTotalVTokenShares,
            uint256 globalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);
        assertTrue(preTotalVTokenShares != 0);

        uint256 mintedVTokens;
        uint256[] memory tokenIds;

        {
            uint256 nftQty = 3;
            mintedVTokens = nftQty * 1 ether;
            tokenIds = nft.mint(nftQty);
            nft.setApprovalForAll(address(inventoryStaking), true);
        }

        address recipient = makeAddr("recipient");

        vm.expectEmit(true, true, false, true);
        emit DepositWithNFT(VAULT_ID, 2, tokenIds, emptyAmounts);
        uint256 positionId = inventoryStaking.depositWithNFT({
            vaultId: VAULT_ID,
            tokenIds: tokenIds,
            amounts: emptyAmounts,
            recipient: recipient
        });

        // mints position nft to the recipient
        assertEq(inventoryStaking.ownerOf(positionId), recipient);

        (
            uint256 nonce,
            uint256 vaultId,
            uint256 timelockedUntil,
            uint256 vTokenShareBalance,
            uint256 wethFeesPerVTokenShareSnapshotX128,
            uint256 wethOwed
        ) = _getPositionDeposit(positionId);
        assertEq(nonce, 0);
        assertEq(vaultId, VAULT_ID);
        assertEq(timelockedUntil, 0);
        assertEq(
            vTokenShareBalance,
            (mintedVTokens * preTotalVTokenShares) / preNetVTokenBalance
        );
        assertEq(
            wethFeesPerVTokenShareSnapshotX128,
            globalWethFeesPerVTokenShareX128
        );
        assertEq(wethOwed, 0);

        // should update total vToken shares
        (uint256 postTotalVTokenShares, ) = inventoryStaking.vaultGlobal(
            VAULT_ID
        );
        assertEq(
            postTotalVTokenShares,
            preTotalVTokenShares + vTokenShareBalance
        );
    }

    // 1155

    function test_depositWithNFT_1155_Success_WhenPreTotalSharesZero()
        external
    {
        (
            uint256 preTotalVTokenShares,
            uint256 globalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID_1155);
        assertEq(preTotalVTokenShares, 0);

        uint256 mintedVTokens;
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        {
            uint256 nftQty = 3;
            mintedVTokens = nftQty * 1 ether;

            tokenIds[0] = nft1155.mint(nftQty);
            amounts[0] = nftQty;

            nft1155.setApprovalForAll(address(inventoryStaking), true);
        }

        address recipient = makeAddr("recipient");
        vm.expectEmit(true, true, false, true);
        emit DepositWithNFT(VAULT_ID_1155, 1, tokenIds, amounts);
        uint256 positionId = inventoryStaking.depositWithNFT({
            vaultId: VAULT_ID_1155,
            tokenIds: tokenIds,
            amounts: amounts,
            recipient: recipient
        });

        assertEq(positionId, 1);
        // mints position nft to the recipient
        assertEq(inventoryStaking.ownerOf(positionId), recipient);

        (
            uint256 nonce,
            uint256 vaultId,
            uint256 timelockedUntil,
            uint256 vTokenShareBalance,
            uint256 wethFeesPerVTokenShareSnapshotX128,
            uint256 wethOwed
        ) = _getPositionDeposit(positionId);
        assertEq(nonce, 0);
        assertEq(vaultId, VAULT_ID_1155);
        assertEq(
            timelockedUntil,
            block.timestamp + inventoryStaking.timelock()
        );
        assertEq(
            vTokenShareBalance,
            mintedVTokens - inventoryStaking.MINIMUM_LIQUIDITY()
        );
        assertEq(
            wethFeesPerVTokenShareSnapshotX128,
            globalWethFeesPerVTokenShareX128
        );
        assertEq(wethOwed, 0);

        // should update total vToken shares
        (uint256 postTotalVTokenShares, ) = inventoryStaking.vaultGlobal(
            VAULT_ID_1155
        );
        assertEq(postTotalVTokenShares, mintedVTokens);
    }

    // InventoryStaking#receiveRewards

    function test_receiveWethRewards_RevertsForNonFeeDistributor() external {
        hoax(makeAddr("nonFeeDistributor"));
        vm.expectRevert();
        inventoryStaking.receiveWethRewards({
            vaultId: VAULT_ID,
            wethAmount: 1 ether
        });
    }

    function test_receiveWethRewards_WhenTotalSharesZero() external {
        (
            uint256 totalVTokenShares,
            uint256 preGlobalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);
        assertEq(totalVTokenShares, 0);

        uint256 preWethBalance = weth.balanceOf(address(inventoryStaking));

        hoax(address(feeDistributor));
        bool rewardsDistributed = inventoryStaking.receiveWethRewards({
            vaultId: VAULT_ID,
            wethAmount: 1 ether
        });

        uint256 postWethBalance = weth.balanceOf(address(inventoryStaking));
        (, uint256 postGlobalWethFeesPerVTokenShareX128) = inventoryStaking
            .vaultGlobal(VAULT_ID);

        assertEq(rewardsDistributed, false);
        assertEq(
            postWethBalance,
            preWethBalance,
            "WETH tokens were transferred"
        );
        assertEq(
            postGlobalWethFeesPerVTokenShareX128,
            preGlobalWethFeesPerVTokenShareX128,
            "globalWethFeesPerVTokenShare was modified"
        );
    }

    function test_receiveWethRewards_Success() external {
        // initial stake to make totalVTokenShares non zero
        _mintXNFT(1);

        uint256 wethRewardAmt = 2 ether;

        uint256 preNetVTokenBalance = vtoken.balanceOf(
            address(inventoryStaking)
        );
        (
            uint256 totalVTokenShares,
            uint256 preGlobalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);
        uint256 preWethBalance = weth.balanceOf(address(inventoryStaking));

        bool rewardsDistributed = _distributeWethRewards(wethRewardAmt);

        uint256 postWethBalance = weth.balanceOf(address(inventoryStaking));
        uint256 postNetVTokenBalance = vtoken.balanceOf(
            address(inventoryStaking)
        );
        (, uint256 postGlobalWethFeesPerVTokenShareX128) = inventoryStaking
            .vaultGlobal(VAULT_ID);

        assertEq(rewardsDistributed, true);
        assertEq(
            postWethBalance - preWethBalance,
            wethRewardAmt,
            "WETH transferred amount incorrect"
        );
        assertEq(
            postGlobalWethFeesPerVTokenShareX128,
            preGlobalWethFeesPerVTokenShareX128 +
                FullMath.mulDiv(
                    wethRewardAmt,
                    FixedPoint128.Q128,
                    totalVTokenShares
                ),
            "globalWethFeesPerVTokenShare modified incorrectly"
        );
        assertEq(
            postNetVTokenBalance,
            preNetVTokenBalance,
            "netVTokenBalance was modified"
        );
    }

    function test_receiveVTokenRewards_Success() external {
        // initial stake to make totalVTokenShares non zero
        _mintXNFT(1);

        (uint256 vTokenRewardAmt, ) = _mintVToken(2);

        uint256 prePricePerShareVToken = inventoryStaking.pricePerShareVToken(
            VAULT_ID
        );

        vtoken.transfer(address(inventoryStaking), vTokenRewardAmt);

        uint256 postPricePerShareVToken = inventoryStaking.pricePerShareVToken(
            VAULT_ID
        );

        assertGt(
            postPricePerShareVToken,
            prePricePerShareVToken,
            "pricePerShare didn't increase"
        );
    }

    // InventoryStaking#collectWethFees

    function test_collectWethFees_RevertsForNonOwnerIfPaused() external {
        inventoryStaking.pause(COLLECTWETHFEES_PAUSE_CODE);

        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = 1;

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(PausableUpgradeable.Paused.selector);
        inventoryStaking.collectWethFees(positionIds);
    }

    function test_collectWethFees_RevertsForNonPositionOwner() external {
        // stake to mint positionId
        uint256 positionId = _mintXNFT(1);

        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;

        hoax(makeAddr("nonPositionOwner"));
        vm.expectRevert(INFTXInventoryStakingV3.NotPositionOwner.selector);
        inventoryStaking.collectWethFees(positionIds);
    }

    function test_collectWethFees_Success() external {
        // position where wethOwed > 0
        uint256 positionId = _mintXNFTWithWethOwed(1);

        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;

        (
            uint256 vTokenShareBalance,
            uint256 preWethFeesPerVTokenShareSnapshotX128,
            uint256 preWethOwed
        ) = _getPosition(positionId);
        assertGt(preWethOwed, 0);
        (, uint256 globalWethFeesPerVTokenShareX128) = inventoryStaking
            .vaultGlobal(VAULT_ID);

        uint256 preWethBalance = weth.balanceOf(address(this));

        uint256 expectedWethAmount = _calcWethOwed(
            globalWethFeesPerVTokenShareX128,
            preWethFeesPerVTokenShareSnapshotX128,
            vTokenShareBalance
        ) + preWethOwed;

        vm.expectEmit(true, false, false, true);
        emit CollectWethFees(positionId, expectedWethAmount);
        inventoryStaking.collectWethFees(positionIds);

        (
            ,
            uint256 postWethFeesPerVTokenShareSnapshotX128,
            uint256 postWethOwed
        ) = _getPosition(positionId);
        uint256 postWethBalance = weth.balanceOf(address(this));

        assertEq(postWethBalance - preWethBalance, expectedWethAmount);
        assertEq(
            postWethFeesPerVTokenShareSnapshotX128,
            globalWethFeesPerVTokenShareX128
        );
        assertEq(postWethOwed, 0);
    }

    // InventoryStaking#combinePositions

    function test_combinePositions_RevertsForNonParentPositionOwner() external {
        uint256 parentPositionId = _mintXNFT(1);
        uint256[] memory childPositionIds = new uint256[](0);

        hoax(makeAddr("nonParentPositionOwner"));
        vm.expectRevert(INFTXInventoryStakingV3.NotPositionOwner.selector);
        inventoryStaking.combinePositions(parentPositionId, childPositionIds);
    }

    function test_combinePositions_RevertsForNonChildPositionOwner() external {
        uint256 parentPositionId = _mintXNFT(1);
        uint256[] memory childPositionIds = new uint256[](3);
        childPositionIds[0] = _mintXNFT(1);
        childPositionIds[1] = _mintXNFT(1);
        childPositionIds[2] = _mintXNFT(1);

        inventoryStaking.safeTransferFrom(
            address(this),
            makeAddr("nonChildPositionOwner"),
            childPositionIds[1]
        );

        (
            uint256 parentTimelockedUntil,
            uint256 parentVTokenTimelockedUntil
        ) = _getPositionCombine(parentPositionId);
        // jumping into the future, so it doesn't throw timelocked error
        vm.warp(parentTimelockedUntil + parentVTokenTimelockedUntil + 1);

        vm.expectRevert(INFTXInventoryStakingV3.NotPositionOwner.selector);
        inventoryStaking.combinePositions(parentPositionId, childPositionIds);
    }

    function test_combinePositions_RevertsIfParentPositionTimelocked()
        external
    {
        uint256 parentPositionId = _mintXNFTWithTimelock(1);
        uint256[] memory childPositionIds = new uint256[](0);

        vm.expectRevert(INFTXInventoryStakingV3.Timelocked.selector);
        inventoryStaking.combinePositions(parentPositionId, childPositionIds);
    }

    function test_combinePositions_RevertsIfChildPositionTimelocked() external {
        uint256 parentPositionId = _mintXNFTWithTimelock(1);
        (uint256 parentTimelockedUntil, ) = _getPositionCombine(
            parentPositionId
        );
        vm.warp(parentTimelockedUntil + 1);

        uint256[] memory childPositionIds = new uint256[](1);
        childPositionIds[0] = _mintXNFTWithTimelock(1);

        vm.expectRevert(INFTXInventoryStakingV3.Timelocked.selector);
        inventoryStaking.combinePositions(parentPositionId, childPositionIds);
    }

    function test_combinePositions_RevertsIfChildVaultIdMismatch() external {
        uint256 parentPositionId = _mintXNFT(1);

        vaultFactory.setFeeExclusion(address(this), true); // setting fee exclusion to ease calulations below
        // deploy new NFT collection
        MockNFT newNFT = new MockNFT();
        uint256[] memory tokenIds = newNFT.mint(1);
        // create new vaultId
        uint256 newVaultId = vaultFactory.createVault({
            name: "TEST2",
            symbol: "TST2",
            assetAddress: address(newNFT),
            is1155: false,
            allowAllItems: true
        });
        INFTXVaultV3 newVtoken = INFTXVaultV3(vaultFactory.vault(newVaultId));
        newNFT.setApprovalForAll(address(newVtoken), true);
        uint256 mintedVTokens = newVtoken.mint({
            tokenIds: tokenIds,
            amounts: emptyAmounts,
            depositor: address(this),
            to: address(this)
        });
        vaultFactory.setFeeExclusion(address(this), false); // setting this back

        newVtoken.approve(address(inventoryStaking), type(uint256).max);

        uint256[] memory childPositionIds = new uint256[](1);
        childPositionIds[0] = inventoryStaking.deposit({
            vaultId: newVaultId,
            amount: mintedVTokens,
            recipient: address(this),
            encodedPermit2: "",
            viaPermit2: false,
            forceTimelock: false
        });
        (
            uint256 childTimelockedUntil,
            uint256 childVTokenTimelockedUntil
        ) = _getPositionCombine(childPositionIds[0]);
        vm.warp(childTimelockedUntil + childVTokenTimelockedUntil + 1);

        // combine positions
        vm.expectRevert(INFTXInventoryStakingV3.VaultIdMismatch.selector);
        inventoryStaking.combinePositions(parentPositionId, childPositionIds);
    }

    function test_combinePositions_RevertsIfChildAndParentPositionSame()
        external
    {
        uint256 parentPositionId = _mintXNFT(1);

        uint256[] memory childPositionIds = new uint256[](2);
        childPositionIds[0] = _mintXNFT(1);
        childPositionIds[1] = parentPositionId;

        (
            uint256 childTimelockedUntil,
            uint256 childVTokenTimelockedUntil
        ) = _getPositionCombine(childPositionIds[0]);
        vm.warp(childTimelockedUntil + childVTokenTimelockedUntil + 1);

        vm.expectRevert(INFTXInventoryStakingV3.ParentChildSame.selector);
        inventoryStaking.combinePositions(parentPositionId, childPositionIds);
    }

    function test_combinePositions_Success() external {
        uint256 parentPositionId = _mintXNFTWithWethOwed(3);

        uint256[] memory childPositionIds = new uint256[](2);
        childPositionIds[0] = _mintXNFTWithWethOwed(1);
        childPositionIds[1] = _mintXNFTWithWethOwed(2);

        (, uint256 globalWethFeesPerVTokenShareX128) = inventoryStaking
            .vaultGlobal(VAULT_ID);

        uint256 expectedParentWethOwed;
        uint256 expectedParentVTokenShareBalance;
        {
            (
                uint256 preParentVTokenShareBalance,
                uint256 preParentWethFeesPerVTokenShareSnapshotX128,
                uint256 preParentWethOwed
            ) = _getPosition(parentPositionId);
            (
                uint256 preChildAVTokenShareBalance,
                uint256 preChildAWethFeesPerVTokenShareSnapshotX128,
                uint256 preChildAWethOwed
            ) = _getPosition(childPositionIds[0]);
            (
                uint256 preChildBVTokenShareBalance,
                uint256 preChildBWethFeesPerVTokenShareSnapshotX128,
                uint256 preChildBWethOwed
            ) = _getPosition(childPositionIds[1]);

            expectedParentWethOwed =
                preParentWethOwed +
                preChildAWethOwed +
                preChildBWethOwed +
                _calcWethOwed(
                    globalWethFeesPerVTokenShareX128,
                    preParentWethFeesPerVTokenShareSnapshotX128,
                    preParentVTokenShareBalance
                ) +
                _calcWethOwed(
                    globalWethFeesPerVTokenShareX128,
                    preChildAWethFeesPerVTokenShareSnapshotX128,
                    preChildAVTokenShareBalance
                ) +
                _calcWethOwed(
                    globalWethFeesPerVTokenShareX128,
                    preChildBWethFeesPerVTokenShareSnapshotX128,
                    preChildBVTokenShareBalance
                );

            expectedParentVTokenShareBalance =
                preParentVTokenShareBalance +
                preChildAVTokenShareBalance +
                preChildBVTokenShareBalance;
        }

        inventoryStaking.combinePositions(parentPositionId, childPositionIds);

        (
            uint256 postParentVTokenShareBalance,
            uint256 postParentWethFeesPerVTokenShareSnapshotX128,
            uint256 postParentWethOwed
        ) = _getPosition(parentPositionId);
        (
            uint256 postChildAVTokenShareBalance,
            ,
            uint256 postChildAWethOwed
        ) = _getPosition(childPositionIds[0]);
        (
            uint256 postChildBVTokenShareBalance,
            ,
            uint256 postChildBWethOwed
        ) = _getPosition(childPositionIds[1]);

        assertEq(
            postParentVTokenShareBalance,
            expectedParentVTokenShareBalance
        );
        assertEq(
            postParentWethFeesPerVTokenShareSnapshotX128,
            globalWethFeesPerVTokenShareX128
        );
        assertEq(postParentWethOwed, expectedParentWethOwed);
        assertEq(postChildAVTokenShareBalance, 0);
        assertEq(postChildBVTokenShareBalance, 0);
        assertEq(postChildAWethOwed, 0);
        assertEq(postChildBWethOwed, 0);
    }

    // InventoryStaking#increasePosition
    function test_increasePosition_RevertsForNonOwnerIfPaused() external {
        address nonOwner = makeAddr("nonOwner");

        // mint position to nonOwner
        (uint256 _mintedVTokens, ) = _mintVToken(3);
        vtoken.approve(address(inventoryStaking), type(uint256).max);
        uint256 positionId = inventoryStaking.deposit({
            vaultId: VAULT_ID,
            amount: _mintedVTokens,
            recipient: nonOwner,
            encodedPermit2: "",
            viaPermit2: false,
            forceTimelock: false
        });
        // mint vTokens for increasePosition to nonOwner
        (uint256 mintedVTokens, ) = _mintVToken(3);
        vtoken.transfer(nonOwner, mintedVTokens);

        // Pause increasePosition
        inventoryStaking.pause(INCREASEPOSITION_PAUSE_CODE);

        startHoax(nonOwner);
        vtoken.approve(address(inventoryStaking), mintedVTokens);

        vm.expectRevert(PausableUpgradeable.Paused.selector);
        inventoryStaking.increasePosition({
            positionId: positionId,
            amount: mintedVTokens,
            encodedPermit2: "",
            viaPermit2: false,
            forceTimelock: false
        });
    }

    function test_increasePosition_RevertsForNonPositionOwner() external {
        uint256 positionId = _mintXNFTWithTimelock(2);
        (uint256 mintedVTokens, ) = _mintVToken(3);

        hoax(makeAddr("nonPositionOwner"));
        vm.expectRevert(INFTXInventoryStakingV3.NotPositionOwner.selector);
        inventoryStaking.increasePosition({
            positionId: positionId,
            amount: mintedVTokens,
            encodedPermit2: "",
            viaPermit2: false,
            forceTimelock: false
        });
    }

    function test_increasePosition_RevertsIfPositionNotCreatedWithVTokens()
        external
    {
        uint256[] memory tokenIds = nft.mint(1);
        nft.setApprovalForAll(address(inventoryStaking), true);
        uint256 positionId = inventoryStaking.depositWithNFT({
            vaultId: VAULT_ID,
            tokenIds: tokenIds,
            amounts: emptyAmounts,
            recipient: address(this)
        });

        (uint256 mintedVTokens, ) = _mintVToken(3);
        vtoken.approve(address(inventoryStaking), type(uint256).max);

        vm.expectRevert(
            INFTXInventoryStakingV3.PositionNotCreatedWithVTokens.selector
        );
        inventoryStaking.increasePosition({
            positionId: positionId,
            amount: mintedVTokens,
            encodedPermit2: "",
            viaPermit2: false,
            forceTimelock: false
        });
    }

    struct IncreasePositionData {
        uint256 mintedVTokens;
        uint256 moreMintedVTokens;
        uint256 preNetVTokenBalance;
        uint256 preTimelockedUntil;
        uint256 preVTokenShareBalance;
        uint256 preWethFeesPerVTokenShareSnapshotX128;
        uint256 preWethOwed;
    }
    IncreasePositionData id;

    function test_increasePosition_Success() external {
        // mint position with vTokens
        (id.mintedVTokens, ) = _mintVToken(3);
        vtoken.approve(address(inventoryStaking), type(uint256).max);
        uint256 positionId;
        {
            positionId = inventoryStaking.deposit({
                vaultId: VAULT_ID,
                amount: id.mintedVTokens,
                recipient: address(this),
                encodedPermit2: "",
                viaPermit2: false,
                forceTimelock: false
            });
        }

        (id.moreMintedVTokens, ) = _mintVToken(3);

        id.preNetVTokenBalance = vtoken.balanceOf(address(inventoryStaking));
        (
            id.preTimelockedUntil,
            ,
            id.preVTokenShareBalance,
            id.preWethFeesPerVTokenShareSnapshotX128,
            id.preWethOwed
        ) = _getPositionIncrease(positionId);
        (
            uint256 preTotalVTokenShares,
            uint256 globalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);

        vm.expectEmit(true, true, false, true);
        emit IncreasePosition(VAULT_ID, positionId, id.moreMintedVTokens);
        inventoryStaking.increasePosition({
            positionId: positionId,
            amount: id.moreMintedVTokens,
            encodedPermit2: "",
            viaPermit2: false,
            forceTimelock: false
        });

        uint256 postNetVTokenBalance = vtoken.balanceOf(
            address(inventoryStaking)
        );
        (
            uint256 postTimelockedUntil,
            uint256 postVTokenTimelockedUntil,
            uint256 postVTokenShareBalance,
            uint256 postWethFeesPerVTokenShareSnapshotX128,
            uint256 postWethOwed
        ) = _getPositionIncrease(positionId);
        (uint256 postTotalVTokenShares, ) = inventoryStaking.vaultGlobal(
            VAULT_ID
        );

        assertEq(
            postNetVTokenBalance - id.preNetVTokenBalance,
            id.moreMintedVTokens
        );
        assertEq(
            postWethOwed,
            _calcWethOwed(
                globalWethFeesPerVTokenShareX128,
                id.preWethFeesPerVTokenShareSnapshotX128,
                id.preVTokenShareBalance
            ) + id.preWethOwed
        );
        assertEq(
            postWethFeesPerVTokenShareSnapshotX128,
            globalWethFeesPerVTokenShareX128
        );
        // currently, vTokens per share = 1
        assertEq(
            postVTokenShareBalance,
            id.preVTokenShareBalance + id.mintedVTokens
        );
        assertEq(
            postTotalVTokenShares,
            preTotalVTokenShares + id.mintedVTokens
        );
        assertEq(postTimelockedUntil, id.preTimelockedUntil);
        assertEq(postVTokenTimelockedUntil, block.timestamp + VTOKEN_TIMELOCK);
    }

    function test_increasePosition_Success_WithPermit2() external {
        // mint position with vTokens
        (id.mintedVTokens, ) = _mintVToken(3);

        vtoken.approve(address(inventoryStaking), type(uint256).max);
        uint256 positionId;
        {
            positionId = inventoryStaking.deposit({
                vaultId: VAULT_ID,
                amount: id.mintedVTokens,
                recipient: from, // FROM
                encodedPermit2: "",
                viaPermit2: false,
                forceTimelock: false
            });
        }

        (id.moreMintedVTokens, ) = _mintVToken(3);
        vtoken.transfer(from, id.moreMintedVTokens);
        startHoax(from);

        bytes memory encodedPermit2 = _getEncodedPermit2({
            token: address(vtoken),
            amount: id.moreMintedVTokens,
            spender: address(inventoryStaking)
        });

        id.preNetVTokenBalance = vtoken.balanceOf(address(inventoryStaking));
        (
            id.preTimelockedUntil,
            ,
            id.preVTokenShareBalance,
            id.preWethFeesPerVTokenShareSnapshotX128,
            id.preWethOwed
        ) = _getPositionIncrease(positionId);
        (
            uint256 preTotalVTokenShares,
            uint256 globalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);

        vm.expectEmit(true, true, false, true);
        emit IncreasePosition(VAULT_ID, positionId, id.moreMintedVTokens);
        inventoryStaking.increasePosition({
            positionId: positionId,
            amount: id.moreMintedVTokens,
            encodedPermit2: encodedPermit2,
            viaPermit2: true,
            forceTimelock: false
        });

        uint256 postNetVTokenBalance = vtoken.balanceOf(
            address(inventoryStaking)
        );
        (
            uint256 postTimelockedUntil,
            uint256 postVTokenTimelockedUntil,
            uint256 postVTokenShareBalance,
            uint256 postWethFeesPerVTokenShareSnapshotX128,
            uint256 postWethOwed
        ) = _getPositionIncrease(positionId);
        (uint256 postTotalVTokenShares, ) = inventoryStaking.vaultGlobal(
            VAULT_ID
        );

        assertEq(
            postNetVTokenBalance - id.preNetVTokenBalance,
            id.moreMintedVTokens
        );
        assertEq(
            postWethOwed,
            _calcWethOwed(
                globalWethFeesPerVTokenShareX128,
                id.preWethFeesPerVTokenShareSnapshotX128,
                id.preVTokenShareBalance
            ) + id.preWethOwed
        );
        assertEq(
            postWethFeesPerVTokenShareSnapshotX128,
            globalWethFeesPerVTokenShareX128
        );
        // currently, vTokens per share = 1
        assertEq(
            postVTokenShareBalance,
            id.preVTokenShareBalance + id.mintedVTokens
        );
        assertEq(
            postTotalVTokenShares,
            preTotalVTokenShares + id.mintedVTokens
        );
        assertEq(postTimelockedUntil, id.preTimelockedUntil);
        assertEq(postVTokenTimelockedUntil, block.timestamp + VTOKEN_TIMELOCK);
    }

    function test_increasePosition_Success_WithPermit2_EmptyEncodedPermit2()
        external
    {
        // mint position with vTokens
        (id.mintedVTokens, ) = _mintVToken(3);
        vtoken.transfer(from, id.mintedVTokens);
        startHoax(from);

        uint256 positionId;
        {
            bytes memory encodedPermit2 = _getEncodedPermit2({
                token: address(vtoken),
                amount: type(uint160).max, // MAX APPROVAL during deposit
                spender: address(inventoryStaking)
            });
            positionId = inventoryStaking.deposit({
                vaultId: VAULT_ID,
                amount: id.mintedVTokens,
                recipient: from, // FROM
                encodedPermit2: encodedPermit2,
                viaPermit2: true,
                forceTimelock: false
            });
        }

        vm.stopPrank();

        (id.moreMintedVTokens, ) = _mintVToken(3);
        vtoken.transfer(from, id.moreMintedVTokens);

        startHoax(from);

        id.preNetVTokenBalance = vtoken.balanceOf(address(inventoryStaking));
        (
            id.preTimelockedUntil,
            ,
            id.preVTokenShareBalance,
            id.preWethFeesPerVTokenShareSnapshotX128,
            id.preWethOwed
        ) = _getPositionIncrease(positionId);
        (
            uint256 preTotalVTokenShares,
            uint256 globalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);

        vtoken.approve(address(inventoryStaking), type(uint256).max);

        vm.expectEmit(true, true, false, true);
        emit IncreasePosition(VAULT_ID, positionId, id.moreMintedVTokens);
        inventoryStaking.increasePosition({
            positionId: positionId,
            amount: id.moreMintedVTokens,
            encodedPermit2: "", // EMPTY
            viaPermit2: true, // TRUE
            forceTimelock: false
        });

        uint256 postNetVTokenBalance = vtoken.balanceOf(
            address(inventoryStaking)
        );
        (
            uint256 postTimelockedUntil,
            uint256 postVTokenTimelockedUntil,
            uint256 postVTokenShareBalance,
            uint256 postWethFeesPerVTokenShareSnapshotX128,
            uint256 postWethOwed
        ) = _getPositionIncrease(positionId);
        (uint256 postTotalVTokenShares, ) = inventoryStaking.vaultGlobal(
            VAULT_ID
        );

        assertEq(
            postNetVTokenBalance - id.preNetVTokenBalance,
            id.moreMintedVTokens
        );
        assertEq(
            postWethOwed,
            _calcWethOwed(
                globalWethFeesPerVTokenShareX128,
                id.preWethFeesPerVTokenShareSnapshotX128,
                id.preVTokenShareBalance
            ) + id.preWethOwed
        );
        assertEq(
            postWethFeesPerVTokenShareSnapshotX128,
            globalWethFeesPerVTokenShareX128
        );
        // currently, vTokens per share = 1
        assertEq(
            postVTokenShareBalance,
            id.preVTokenShareBalance + id.mintedVTokens
        );
        assertEq(
            postTotalVTokenShares,
            preTotalVTokenShares + id.mintedVTokens
        );
        assertEq(postTimelockedUntil, id.preTimelockedUntil);
        assertEq(postVTokenTimelockedUntil, block.timestamp + VTOKEN_TIMELOCK);
    }

    function test_increasePosition_Success_ForceTimelock() external {
        // mint position with vTokens
        (id.mintedVTokens, ) = _mintVToken(3);
        vtoken.approve(address(inventoryStaking), type(uint256).max);
        uint256 positionId;
        {
            positionId = inventoryStaking.deposit({
                vaultId: VAULT_ID,
                amount: id.mintedVTokens,
                recipient: address(this),
                encodedPermit2: "",
                viaPermit2: false,
                forceTimelock: false
            });
        }

        (uint256 moreMintedVTokens, ) = _mintVToken(3);

        id.preNetVTokenBalance = vtoken.balanceOf(address(inventoryStaking));
        (
            id.preVTokenShareBalance,
            id.preWethFeesPerVTokenShareSnapshotX128,
            id.preWethOwed
        ) = _getPosition(positionId);
        (
            uint256 preTotalVTokenShares,
            uint256 globalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);

        vm.expectEmit(true, true, false, true);
        emit IncreasePosition(VAULT_ID, positionId, moreMintedVTokens);
        inventoryStaking.increasePosition({
            positionId: positionId,
            amount: moreMintedVTokens,
            encodedPermit2: "",
            viaPermit2: false,
            forceTimelock: true // TRUE
        });

        uint256 postNetVTokenBalance = vtoken.balanceOf(
            address(inventoryStaking)
        );
        (
            uint256 postTimelockedUntil,
            uint256 postVTokenTimelockedUntil,
            uint256 postVTokenShareBalance,
            uint256 postWethFeesPerVTokenShareSnapshotX128,
            uint256 postWethOwed
        ) = _getPositionIncrease(positionId);
        (uint256 postTotalVTokenShares, ) = inventoryStaking.vaultGlobal(
            VAULT_ID
        );

        assertEq(
            postNetVTokenBalance - id.preNetVTokenBalance,
            moreMintedVTokens
        );
        assertEq(
            postWethOwed,
            _calcWethOwed(
                globalWethFeesPerVTokenShareX128,
                id.preWethFeesPerVTokenShareSnapshotX128,
                id.preVTokenShareBalance
            ) + id.preWethOwed
        );
        assertEq(
            postWethFeesPerVTokenShareSnapshotX128,
            globalWethFeesPerVTokenShareX128
        );
        // currently, vTokens per share = 1
        assertEq(
            postVTokenShareBalance,
            id.preVTokenShareBalance + id.mintedVTokens
        );
        assertEq(
            postTotalVTokenShares,
            preTotalVTokenShares + id.mintedVTokens
        );
        assertEq(
            postTimelockedUntil,
            block.timestamp + inventoryStaking.timelock()
        );
        assertEq(postVTokenTimelockedUntil, block.timestamp + VTOKEN_TIMELOCK);
    }

    // InventoryStaking#withdraw

    function test_withdraw_RevertsForNonOwnerIfPaused() external {
        inventoryStaking.pause(WITHDRAW_PAUSE_CODE);
        uint256[] memory nftIds;

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(PausableUpgradeable.Paused.selector);
        inventoryStaking.withdraw({
            positionId: 1,
            vTokenShares: 1 ether,
            nftIds: nftIds,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT
        });
    }

    function test_withdraw_RevertsForNonPositionOwner() external {
        uint256 positionId = _mintXNFT(1);
        uint256[] memory nftIds;

        hoax(makeAddr("nonPositionOwner"));
        vm.expectRevert(INFTXInventoryStakingV3.NotPositionOwner.selector);
        inventoryStaking.withdraw({
            positionId: positionId,
            vTokenShares: 1 ether,
            nftIds: nftIds,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT
        });
    }

    function test_withdraw_RevertsIfSharesRequestedMoreThanBalance() external {
        // timelock already up for combined positions
        uint256 positionId = _mintXNFTWithWethOwed(1);
        uint256[] memory nftIds;

        uint256 vTokenShareBalance = _getPositionVTokenShareBalance(positionId);

        vm.expectRevert(
            INFTXInventoryStakingV3.InsufficientVTokenShares.selector
        );
        inventoryStaking.withdraw({
            positionId: positionId,
            vTokenShares: vTokenShareBalance + 1,
            nftIds: nftIds,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT
        });
    }

    struct WithdrawData {
        uint256 preVTokenShareBalance;
        uint256 preWethFeesPerVTokenShareSnapshotX128;
        uint256 preWethOwed;
        uint256 vTokenSharesToWithdraw;
        uint256 preNetVTokenBalance;
        uint256 preTotalVTokenShares;
        uint256 globalWethFeesPerVTokenShareX128;
    }
    WithdrawData wd;

    function test_withdraw_ToVTokens_Success_WhenNoTimelock() external {
        // timelock already up for combined positions, so no penalty would be deducted on withdraw
        uint256 positionId = _mintXNFTWithWethOwed(2);
        // distributing rewards so that initially position's wethFeesPerVTokenShareSnapshotX128 different from the global value
        _distributeWethRewards(1 ether);

        (
            wd.preVTokenShareBalance,
            wd.preWethFeesPerVTokenShareSnapshotX128,
            wd.preWethOwed
        ) = _getPosition(positionId);
        assertGt(wd.preWethOwed, 0);

        wd.vTokenSharesToWithdraw = wd.preVTokenShareBalance / 2;

        wd.preNetVTokenBalance = vtoken.balanceOf(address(inventoryStaking));
        (
            wd.preTotalVTokenShares,
            wd.globalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);
        assertTrue(
            wd.globalWethFeesPerVTokenShareX128 !=
                wd.preWethFeesPerVTokenShareSnapshotX128
        );

        uint256 expectedWethAmount = _calcWethOwed(
            wd.globalWethFeesPerVTokenShareX128,
            wd.preWethFeesPerVTokenShareSnapshotX128,
            wd.preVTokenShareBalance
        ) + wd.preWethOwed;
        uint256 expectedVTokenAmount = (wd.preNetVTokenBalance *
            wd.vTokenSharesToWithdraw) / wd.preTotalVTokenShares;

        uint256 preWethBalance = weth.balanceOf(address(this));
        uint256 preVTokenBalance = vtoken.balanceOf(address(this));

        uint256[] memory nftIds;

        vm.expectEmit(true, false, false, true);
        emit Withdraw(
            positionId,
            wd.vTokenSharesToWithdraw,
            expectedVTokenAmount,
            expectedWethAmount
        );
        inventoryStaking.withdraw({
            positionId: positionId,
            vTokenShares: wd.vTokenSharesToWithdraw,
            nftIds: nftIds,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT
        });

        uint256 postWethBalance = weth.balanceOf(address(this));
        uint256 postVTokenBalance = vtoken.balanceOf(address(this));
        uint256 postNetVTokenBalance = vtoken.balanceOf(
            address(inventoryStaking)
        );

        (
            uint256 postVTokenShareBalance,
            uint256 postWethFeesPerVTokenShareSnapshotX128,
            uint256 postWethOwed
        ) = _getPosition(positionId);

        (uint256 postTotalVTokenShares, ) = inventoryStaking.vaultGlobal(
            VAULT_ID
        );

        assertEq(
            postWethBalance - preWethBalance,
            expectedWethAmount,
            "expectedWethAmount mismatch"
        );
        assertEq(
            postVTokenBalance - preVTokenBalance,
            expectedVTokenAmount,
            "expectedVTokenAmount mismatch"
        );
        assertEq(
            postVTokenShareBalance,
            wd.preVTokenShareBalance - wd.vTokenSharesToWithdraw,
            "postVTokenShareBalance mismatch"
        );
        assertEq(
            postWethFeesPerVTokenShareSnapshotX128,
            wd.globalWethFeesPerVTokenShareX128,
            "postWethFeesPerVTokenShareSnapshotX128 mismatch"
        );
        assertEq(postWethOwed, 0, "postWethOwed mismatch");
        assertEq(
            postNetVTokenBalance,
            wd.preNetVTokenBalance - expectedVTokenAmount,
            "postNetVTokenBalance mismatch"
        );
        assertEq(
            postTotalVTokenShares,
            wd.preTotalVTokenShares - wd.vTokenSharesToWithdraw,
            "postTotalVTokenShares mismatch"
        );
    }

    function test_withdraw_ToVTokens_Success_WithPenaltyForTimelock() external {
        uint256 timelockPercentLeft = 20; // 20% timelock left
        uint256 positionId = _mintXNFTWithTimelock(2);
        // distributing rewards so that initially position's wethFeesPerVTokenShareSnapshotX128 different from the global value
        _distributeWethRewards(1 ether);

        uint256 timelockedUntil;
        (
            timelockedUntil,
            wd.preVTokenShareBalance,
            wd.preWethFeesPerVTokenShareSnapshotX128,
            wd.preWethOwed
        ) = _getPositionWithdraw(positionId);
        // jump to when 20% timelock left
        vm.warp(
            timelockedUntil -
                (inventoryStaking.timelock() * timelockPercentLeft) /
                100
        );

        wd.vTokenSharesToWithdraw = wd.preVTokenShareBalance / 2;

        wd.preNetVTokenBalance = vtoken.balanceOf(address(inventoryStaking));
        (
            wd.preTotalVTokenShares,
            wd.globalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);
        assertTrue(
            wd.globalWethFeesPerVTokenShareX128 !=
                wd.preWethFeesPerVTokenShareSnapshotX128
        );

        uint256 expectedWethAmount = _calcWethOwed(
            wd.globalWethFeesPerVTokenShareX128,
            wd.preWethFeesPerVTokenShareSnapshotX128,
            wd.preVTokenShareBalance
        ) + wd.preWethOwed;
        uint256 expectedVTokenAmount = (wd.preNetVTokenBalance *
            wd.vTokenSharesToWithdraw) / wd.preTotalVTokenShares;
        expectedVTokenAmount -=
            (expectedVTokenAmount *
                inventoryStaking.earlyWithdrawPenaltyInWei() *
                timelockPercentLeft) /
            (100 * 1 ether);

        uint256 preWethBalance = weth.balanceOf(address(this));
        uint256 preVTokenBalance = vtoken.balanceOf(address(this));
        // pricePerShare should increase to represent penalty being distributed among the remaining stakers
        uint256 prePricePerShareVToken = inventoryStaking.pricePerShareVToken(
            VAULT_ID
        );
        uint256[] memory nftIds;

        vm.expectEmit(true, false, false, true);
        emit Withdraw(
            positionId,
            wd.vTokenSharesToWithdraw,
            expectedVTokenAmount,
            expectedWethAmount
        );
        inventoryStaking.withdraw({
            positionId: positionId,
            vTokenShares: wd.vTokenSharesToWithdraw,
            nftIds: nftIds,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT
        });

        uint256 postWethBalance = weth.balanceOf(address(this));
        uint256 postVTokenBalance = vtoken.balanceOf(address(this));
        uint256 postNetVTokenBalance = vtoken.balanceOf(
            address(inventoryStaking)
        );
        uint256 postPricePerShareVToken = inventoryStaking.pricePerShareVToken(
            VAULT_ID
        );

        (
            uint256 postVTokenShareBalance,
            uint256 postWethFeesPerVTokenShareSnapshotX128,
            uint256 postWethOwed
        ) = _getPosition(positionId);

        (uint256 postTotalVTokenShares, ) = inventoryStaking.vaultGlobal(
            VAULT_ID
        );

        assertEq(
            postWethBalance - preWethBalance,
            expectedWethAmount,
            "expectedWethAmount mismatch"
        );
        assertEq(
            postVTokenBalance - preVTokenBalance,
            expectedVTokenAmount,
            "expectedVTokenAmount mismatch"
        );
        assertEq(
            postVTokenShareBalance,
            wd.preVTokenShareBalance - wd.vTokenSharesToWithdraw,
            "postVTokenShareBalance mismatch"
        );
        assertEq(
            postWethFeesPerVTokenShareSnapshotX128,
            wd.globalWethFeesPerVTokenShareX128,
            "postWethFeesPerVTokenShareSnapshotX128 mismatch"
        );
        assertEq(postWethOwed, 0, "postWethOwed mismatch");
        assertEq(
            postNetVTokenBalance,
            wd.preNetVTokenBalance - expectedVTokenAmount,
            "postNetVTokenBalance mismatch"
        );
        assertEq(
            postTotalVTokenShares,
            wd.preTotalVTokenShares - wd.vTokenSharesToWithdraw,
            "postTotalVTokenShares mismatch"
        );
        assertGt(postPricePerShareVToken, prePricePerShareVToken);
    }

    // to NFTs

    // TODO: add test case for withdraw to NFTs from position with no timelock value
    function test_withdraw_ToNFTs_Success_ForPositionWithNoTimelock_OnlyVTokenTimelock()
        external
    {
        (uint256 mintedVTokens, uint256[] memory tokenIds) = _mintVToken(3);
        vtoken.approve(address(inventoryStaking), type(uint256).max);
        uint256 positionId = inventoryStaking.deposit({
            vaultId: VAULT_ID,
            amount: mintedVTokens,
            recipient: address(this),
            encodedPermit2: "",
            viaPermit2: false,
            forceTimelock: false
        });
        uint256 timelockedUntil = _getPositionTimelockedUntil(positionId);
        assertEq(timelockedUntil, 0);
        {
            // jump to when no vToken timelock
            uint256 vTokenTimelockedUntil = _getPositionVTokenTimelockedUntil(
                positionId
            );
            vm.warp(vTokenTimelockedUntil + 1);
        }

        _distributeWethRewards(1 ether);

        (
            wd.preVTokenShareBalance,
            wd.preWethFeesPerVTokenShareSnapshotX128,
            wd.preWethOwed
        ) = _getPosition(positionId);

        wd.preNetVTokenBalance = vtoken.balanceOf(address(inventoryStaking));
        (
            wd.preTotalVTokenShares,
            wd.globalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);

        wd.vTokenSharesToWithdraw = wd.preVTokenShareBalance / 2;
        uint256 expectedWethAmount = _calcWethOwed(
            wd.globalWethFeesPerVTokenShareX128,
            wd.preWethFeesPerVTokenShareSnapshotX128,
            wd.preVTokenShareBalance
        ) + wd.preWethOwed;

        uint256 expectedVTokenResidue = ((tokenIds.length *
            1 ether -
            inventoryStaking.MINIMUM_LIQUIDITY()) / 2) % 1 ether;
        uint256[] memory tokenIdsToRedeem = new uint256[](1);
        tokenIdsToRedeem[0] = tokenIds[0];

        uint256 preWethBalance = weth.balanceOf(address(this));
        uint256 preNFTBalance = nft.balanceOf(address(this));
        uint256 preVTokenBalance = vtoken.balanceOf(address(this));

        inventoryStaking.withdraw({
            positionId: positionId,
            vTokenShares: wd.vTokenSharesToWithdraw,
            nftIds: tokenIdsToRedeem,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT
        });

        uint256 postWethBalance = weth.balanceOf(address(this));
        uint256 postNFTBalance = nft.balanceOf(address(this));
        uint256 postVTokenBalance = vtoken.balanceOf(address(this));

        assertEq(
            postWethBalance - preWethBalance,
            expectedWethAmount,
            "expectedWethAmount mismatch"
        );
        assertEq(
            postNFTBalance - preNFTBalance,
            tokenIdsToRedeem.length,
            "postNFTBalance mismatch"
        );
        assertEq(
            postVTokenBalance - preVTokenBalance,
            expectedVTokenResidue,
            "postVTokenBalance mismatch"
        );
    }

    function test_withdraw_ToNFTs_RevertsIfVTokenOwedInsufficientForRedeem()
        external
    {
        uint256 nftQty = 3;
        uint256[] memory tokenIds = nft.mint(nftQty);
        nft.setApprovalForAll(address(inventoryStaking), true);

        uint256 positionId = inventoryStaking.depositWithNFT(
            VAULT_ID,
            tokenIds,
            emptyIds,
            address(this)
        );
        uint256[] memory nftIds = new uint256[](nftQty + 1);
        nftIds[0] = tokenIds[0];
        nftIds[1] = tokenIds[1];
        nftIds[2] = tokenIds[2];
        nftIds[3] = 999;

        uint256 vTokenShareBalance = _getPositionVTokenShareBalance(positionId);

        vm.expectRevert(INFTXInventoryStakingV3.InsufficientVTokens.selector);
        inventoryStaking.withdraw({
            positionId: positionId,
            vTokenShares: vTokenShareBalance,
            nftIds: nftIds,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT
        });
    }

    function test_withdraw_ToNFTs_Success_WithResidue() external {
        // minting with NFTs to have a timelock
        uint256 nftQty = 3;
        uint256[] memory tokenIds = nft.mint(nftQty);
        nft.setApprovalForAll(address(inventoryStaking), true);
        uint256 positionId = inventoryStaking.depositWithNFT(
            VAULT_ID,
            tokenIds,
            emptyIds,
            address(this)
        );
        // timelock expired
        vm.warp(block.timestamp + inventoryStaking.timelock() + 1);

        _distributeWethRewards(1 ether);

        (
            wd.preVTokenShareBalance,
            wd.preWethFeesPerVTokenShareSnapshotX128,
            wd.preWethOwed
        ) = _getPosition(positionId);

        wd.preNetVTokenBalance = vtoken.balanceOf(address(inventoryStaking));
        (
            wd.preTotalVTokenShares,
            wd.globalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);

        wd.vTokenSharesToWithdraw = wd.preVTokenShareBalance / 2;
        uint256 expectedWethAmount = _calcWethOwed(
            wd.globalWethFeesPerVTokenShareX128,
            wd.preWethFeesPerVTokenShareSnapshotX128,
            wd.preVTokenShareBalance
        ) + wd.preWethOwed;

        uint256 expectedVTokenResidue = ((nftQty *
            1 ether -
            inventoryStaking.MINIMUM_LIQUIDITY()) / 2) % 1 ether;
        uint256[] memory tokenIdsToRedeem = new uint256[](1);
        tokenIdsToRedeem[0] = tokenIds[0];

        uint256 preWethBalance = weth.balanceOf(address(this));
        uint256 preNFTBalance = nft.balanceOf(address(this));
        uint256 preVTokenBalance = vtoken.balanceOf(address(this));

        inventoryStaking.withdraw({
            positionId: positionId,
            vTokenShares: wd.vTokenSharesToWithdraw,
            nftIds: tokenIdsToRedeem,
            vTokenPremiumLimit: MAX_VTOKEN_PREMIUM_LIMIT
        });

        uint256 postWethBalance = weth.balanceOf(address(this));
        uint256 postNFTBalance = nft.balanceOf(address(this));
        uint256 postVTokenBalance = vtoken.balanceOf(address(this));

        assertEq(
            postWethBalance - preWethBalance,
            expectedWethAmount,
            "expectedWethAmount mismatch"
        );
        assertEq(
            postNFTBalance - preNFTBalance,
            tokenIdsToRedeem.length,
            "postNFTBalance mismatch"
        );
        assertEq(
            postVTokenBalance - preVTokenBalance,
            expectedVTokenResidue,
            "postVTokenBalance mismatch"
        );
    }

    // InventoryStaking#setTimelock

    function test_setTimelock_RevertsForNonOwner() external {
        uint256 newTimelock = 10 days;

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        inventoryStaking.setTimelock(newTimelock);
    }

    function test_setTimelock_RevertsWhenTimelockTooLong() external {
        uint256 newTimelock = 15 days;

        vm.expectRevert(INFTXInventoryStakingV3.TimelockTooLong.selector);
        inventoryStaking.setTimelock(newTimelock);
    }

    function test_setTimelock_Success() external {
        uint256 newTimelock = 10 days;

        uint256 prevTimelock = inventoryStaking.timelock();
        assertTrue(prevTimelock != newTimelock);

        vm.expectEmit(false, false, false, true);
        emit UpdateTimelock(newTimelock);
        inventoryStaking.setTimelock(newTimelock);

        uint256 postTimelock = inventoryStaking.timelock();

        assertEq(postTimelock, newTimelock);
    }

    // InventoryStaking#setEarlyWithdrawPenalty
    function test_setEarlyWithdrawPenalty_RevertsForNonOwner() external {
        uint256 newEarlyWithdrawPenalty = 0.20 ether;

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        inventoryStaking.setEarlyWithdrawPenalty(newEarlyWithdrawPenalty);
    }

    function test_setEarlyWithdrawPenalty_RevertsForInvalidEarlyWithdrawPenalty()
        external
    {
        uint256 newEarlyWithdrawPenalty = 2 ether;

        vm.expectRevert(
            INFTXInventoryStakingV3.InvalidEarlyWithdrawPenalty.selector
        );
        inventoryStaking.setEarlyWithdrawPenalty(newEarlyWithdrawPenalty);
    }

    function test_setEarlyWithdrawPenalty_Success() external {
        uint256 newEarlyWithdrawPenalty = 0.20 ether;

        uint256 prevEarlyWithdrawPenalty = inventoryStaking
            .earlyWithdrawPenaltyInWei();
        assertTrue(prevEarlyWithdrawPenalty != newEarlyWithdrawPenalty);

        vm.expectEmit(false, false, false, true);
        emit UpdateEarlyWithdrawPenalty(newEarlyWithdrawPenalty);
        inventoryStaking.setEarlyWithdrawPenalty(newEarlyWithdrawPenalty);

        uint256 postEarlyWithdrawPenalty = inventoryStaking
            .earlyWithdrawPenaltyInWei();

        assertEq(postEarlyWithdrawPenalty, newEarlyWithdrawPenalty);
    }

    // InventoryStaking#setDescriptor
    function test_setDescriptor_RevertsForNonOwner() external {
        InventoryStakingDescriptor newDescriptor = new InventoryStakingDescriptor();

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        inventoryStaking.setDescriptor(newDescriptor);
    }

    function test_setDescriptor_RevertsForZeroAddress() external {
        vm.expectRevert(INFTXInventoryStakingV3.ZeroAddress.selector);
        inventoryStaking.setDescriptor(InventoryStakingDescriptor(address(0)));
    }

    function test_setDescriptor_Success() external {
        address preDescriptor = address(inventoryStaking.descriptor());

        InventoryStakingDescriptor newDescriptor = new InventoryStakingDescriptor();
        assertTrue(address(newDescriptor) != preDescriptor);

        inventoryStaking.setDescriptor(newDescriptor);

        address postDescriptor = address(inventoryStaking.descriptor());
        assertEq(postDescriptor, address(newDescriptor));
    }

    // InventoryStaking#pricePerShareVToken

    function test_pricePerShareVToken_Success() external {
        uint256 nftsStaked = 3;
        _mintXNFT(nftsStaked);

        (uint256 totalVTokenShares, ) = inventoryStaking.vaultGlobal(VAULT_ID);
        assertEq(totalVTokenShares, nftsStaked * 1 ether);

        // 1 share = 1 vToken
        assertEq(inventoryStaking.pricePerShareVToken(VAULT_ID), 1 ether);

        // send more vTokens to inventory staking to increase pricePerShareVToken
        (uint256 mintedVTokens, ) = _mintVToken(2);
        vtoken.transfer(address(inventoryStaking), mintedVTokens);

        // 1 share = (3 + 2) / 3 vTokens
        assertEq(
            inventoryStaking.pricePerShareVToken(VAULT_ID),
            ((uint256(3) + 2) * 1 ether) / 3
        );
    }

    // InventoryStaking#wethBalance

    function test_wethBalance_Success() external {
        uint256 positionId = _mintXNFT(3);

        uint256 wethRewardAmt = 1 ether;
        _distributeWethRewards(wethRewardAmt);

        uint256 wethBalance = inventoryStaking.wethBalance(positionId);

        (
            ,
            ,
            ,
            ,
            ,
            uint256 vTokenShareBalance,
            uint256 wethFeesPerVTokenShareSnapshotX128,
            uint256 preWethOwed
        ) = inventoryStaking.positions(positionId);
        (, uint256 globalWethFeesPerVTokenShareX128) = inventoryStaking
            .vaultGlobal(VAULT_ID);

        uint256 expectedWethAmount = _calcWethOwed(
            globalWethFeesPerVTokenShareX128,
            wethFeesPerVTokenShareSnapshotX128,
            vTokenShareBalance
        ) + preWethOwed;

        assertEq(wethBalance, expectedWethAmount);
        // round-off error
        assertGt(wethBalance, wethRewardAmt - 700 wei);
    }

    // =============================================================
    //                        INTERNAL HELPERS
    // =============================================================

    function _mintXNFT(
        uint256 nftsToWrap
    ) internal returns (uint256 positionId) {
        (uint256 mintedVTokens, ) = _mintVToken(nftsToWrap);
        vtoken.approve(address(inventoryStaking), type(uint256).max);
        positionId = inventoryStaking.deposit({
            vaultId: VAULT_ID,
            amount: mintedVTokens,
            recipient: address(this),
            encodedPermit2: "",
            viaPermit2: false,
            forceTimelock: false
        });
    }

    function _mintXNFTWithTimelock(
        uint256 nftsToWrap
    ) internal returns (uint256 positionId) {
        uint256[] memory tokenIds = nft.mint(nftsToWrap);
        nft.setApprovalForAll(address(inventoryStaking), true);

        positionId = inventoryStaking.depositWithNFT({
            vaultId: VAULT_ID,
            tokenIds: tokenIds,
            amounts: emptyAmounts,
            recipient: address(this)
        });
    }

    function _mintXNFTWithWethOwed(
        uint256 nftsToWrap
    ) internal returns (uint256 parentPositionId) {
        parentPositionId = _mintXNFT(nftsToWrap);
        _distributeWethRewards(3 ether);
        // minting new position then combining, so that position.wethOwed is non zero
        uint256 newPositionId = _mintXNFT(1);
        (
            ,
            ,
            uint256 timelockedUntil,
            ,
            uint256 vTokenTimelockedUntil,
            ,
            ,

        ) = inventoryStaking.positions(newPositionId);
        // jump to future when both timelocks are over
        vm.warp(timelockedUntil + vTokenTimelockedUntil + 1);
        uint256[] memory childPositionIds = new uint256[](1);
        childPositionIds[0] = newPositionId;
        inventoryStaking.combinePositions(parentPositionId, childPositionIds);
    }

    function _distributeWethRewards(
        uint256 wethRewardAmt
    ) internal returns (bool rewardsDistributed) {
        weth.deposit{value: wethRewardAmt}();
        weth.transfer(address(feeDistributor), wethRewardAmt);

        startHoax(address(feeDistributor));
        weth.approve(address(inventoryStaking), type(uint256).max);

        rewardsDistributed = inventoryStaking.receiveWethRewards(
            VAULT_ID,
            wethRewardAmt
        );
        vm.stopPrank();
    }

    function _calcWethOwed(
        uint256 globalWethFeesPerVTokenShareX128,
        uint256 positionWethFeesPerVTokenShareSnapshotX128,
        uint256 positionVTokenShareBalance
    ) internal pure returns (uint256 wethOwed) {
        wethOwed = FullMath.mulDiv(
            globalWethFeesPerVTokenShareX128 -
                positionWethFeesPerVTokenShareSnapshotX128,
            positionVTokenShareBalance,
            FixedPoint128.Q128
        );
    }

    // only get the required position info
    function _getPosition(
        uint256 positionId
    )
        internal
        view
        returns (
            uint256 vTokenShareBalance,
            uint256 wethFeesPerVTokenShareSnapshotX128,
            uint256 wethOwed
        )
    {
        (
            ,
            ,
            ,
            ,
            ,
            vTokenShareBalance,
            wethFeesPerVTokenShareSnapshotX128,
            wethOwed
        ) = inventoryStaking.positions(positionId);
    }

    function _getPositionDeposit(
        uint256 positionId
    )
        internal
        view
        returns (
            uint256 nonce,
            uint256 vaultId,
            uint256 timelockedUntil,
            uint256 vTokenShareBalance,
            uint256 wethFeesPerVTokenShareSnapshotX128,
            uint256 wethOwed
        )
    {
        (
            nonce,
            vaultId,
            timelockedUntil,
            ,
            ,
            vTokenShareBalance,
            wethFeesPerVTokenShareSnapshotX128,
            wethOwed
        ) = inventoryStaking.positions(positionId);
    }

    function _getPositionCombine(
        uint256 positionId
    )
        internal
        view
        returns (uint256 timelockedUntil, uint256 vTokenTimelockedUntil)
    {
        (, , timelockedUntil, , vTokenTimelockedUntil, , , ) = inventoryStaking
            .positions(positionId);
    }

    function _getPositionIncrease(
        uint256 positionId
    )
        internal
        view
        returns (
            uint256 timelockedUntil,
            uint256 vTokenTimelockedUntil,
            uint256 vTokenShareBalance,
            uint256 wethFeesPerVTokenShareSnapshotX128,
            uint256 wethOwed
        )
    {
        (
            ,
            ,
            timelockedUntil,
            ,
            vTokenTimelockedUntil,
            vTokenShareBalance,
            wethFeesPerVTokenShareSnapshotX128,
            wethOwed
        ) = inventoryStaking.positions(positionId);
    }

    function _getPositionWithdraw(
        uint256 positionId
    )
        internal
        view
        returns (
            uint256 timelockedUntil,
            uint256 vTokenShareBalance,
            uint256 wethFeesPerVTokenShareSnapshotX128,
            uint256 wethOwed
        )
    {
        (
            ,
            ,
            timelockedUntil,
            ,
            ,
            vTokenShareBalance,
            wethFeesPerVTokenShareSnapshotX128,
            wethOwed
        ) = inventoryStaking.positions(positionId);
    }

    function _getPositionVTokenShareBalance(
        uint256 positionId
    ) internal view returns (uint256 vTokenShareBalance) {
        (, , , , , vTokenShareBalance, , ) = inventoryStaking.positions(
            positionId
        );
    }

    function _getPositionTimelockedUntil(
        uint256 positionId
    ) internal view returns (uint256 timelockedUntil) {
        (, , timelockedUntil, , , , , ) = inventoryStaking.positions(
            positionId
        );
    }

    function _getPositionVTokenTimelockedUntil(
        uint256 positionId
    ) internal view returns (uint256 vTokenTimelockedUntil) {
        (, , , , vTokenTimelockedUntil, , , ) = inventoryStaking.positions(
            positionId
        );
    }
}
