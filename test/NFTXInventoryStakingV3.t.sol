// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console, stdError} from "forge-std/Test.sol";
import {Helpers} from "./lib/Helpers.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITimelockExcludeList} from "@src/v2/interface/ITimelockExcludeList.sol";
import {FullMath} from "@uni-core/libraries/FullMath.sol";
import {FixedPoint128} from "@uni-core/libraries/FixedPoint128.sol";
import {NFTXInventoryStakingV3Upgradeable, INFTXInventoryStakingV3} from "@src/NFTXInventoryStakingV3Upgradeable.sol";

import {TestBase} from "./TestBase.sol";

contract NFTXInventoryStakingV3Tests is TestBase {
    event Deposit(
        uint256 indexed vaultId,
        uint256 indexed positionId,
        uint256 amount
    );
    event UpdateTimelock(uint256 newTimelock);
    event UpdateEarlyWithdrawPenalty(uint256 newEarlyWithdrawPenaltyInWei);

    // InventoryStaking#init

    function test_init_RevertsWhenTimelockTooLong() external {
        uint256 timelock = 15 days;
        uint256 earlyWithdrawPenaltyInWei = 0.05 ether;

        inventoryStaking = new NFTXInventoryStakingV3Upgradeable();
        vm.expectRevert(INFTXInventoryStakingV3.TimelockTooLong.selector);
        inventoryStaking.__NFTXInventoryStaking_init(
            vaultFactory,
            timelock,
            earlyWithdrawPenaltyInWei,
            ITimelockExcludeList(address(timelockExcludeList))
        );
    }

    function test_init_RevertsForInvalidEarlyWithdrawPenalty() external {
        uint256 timelock = 2 days;
        uint256 earlyWithdrawPenaltyInWei = 2 ether;

        inventoryStaking = new NFTXInventoryStakingV3Upgradeable();
        vm.expectRevert(
            INFTXInventoryStakingV3.InvalidEarlyWithdrawPenalty.selector
        );
        inventoryStaking.__NFTXInventoryStaking_init(
            vaultFactory,
            timelock,
            earlyWithdrawPenaltyInWei,
            ITimelockExcludeList(address(timelockExcludeList))
        );
    }

    function test_init_Success() external {
        uint256 timelock = 2 days;
        uint256 earlyWithdrawPenaltyInWei = 0.05 ether;

        inventoryStaking = new NFTXInventoryStakingV3Upgradeable();
        inventoryStaking.__NFTXInventoryStaking_init(
            vaultFactory,
            timelock,
            earlyWithdrawPenaltyInWei,
            ITimelockExcludeList(address(timelockExcludeList))
        );

        assertEq(inventoryStaking.name(), "NFTX Inventory Staking");
        assertEq(inventoryStaking.symbol(), "xNFT");
        assertEq(
            address(inventoryStaking.nftxVaultFactory()),
            address(vaultFactory)
        );
        assertEq(address(inventoryStaking.WETH()), address(weth));
        assertEq(inventoryStaking.timelock(), timelock);
        assertEq(
            inventoryStaking.earlyWithdrawPenaltyInWei(),
            earlyWithdrawPenaltyInWei
        );
        assertEq(
            address(inventoryStaking.timelockExcludeList()),
            address(timelockExcludeList)
        );
        assertEq(inventoryStaking.owner(), address(this));
    }

    // InventoryStaking#deposit

    function test_deposit_RevertsForNonOwnerIfPaused() external {
        inventoryStaking.pause(0);

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Paused");
        inventoryStaking.deposit(VAULT_ID, 0, address(this));
    }

    function test_deposit_RevertsForInvalidVaultId() external {
        vm.expectRevert(stdError.indexOOBError);
        inventoryStaking.deposit(999, 0, address(this));
    }

    function test_deposit_Success_WhenPreTotalSharesZero() external {
        (
            ,
            uint256 preTotalVTokenShares,
            uint256 globalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);
        assertEq(preTotalVTokenShares, 0);

        uint256 mintedVTokens = _mintVToken(3);

        vtoken.approve(address(inventoryStaking), type(uint256).max);
        address recipient = makeAddr("recipient");
        vm.expectEmit(true, true, false, true);
        emit Deposit(VAULT_ID, 1, mintedVTokens);
        uint256 positionId = inventoryStaking.deposit(
            VAULT_ID,
            mintedVTokens,
            recipient
        );

        // mints position nft to the recipient
        assertEq(inventoryStaking.ownerOf(positionId), recipient);

        (
            uint256 nonce,
            uint256 vaultId,
            uint256 timelockedUntil,
            uint256 vTokenShareBalance,
            uint256 wethFeesPerVTokenShareSnapshotX128,
            uint256 wethOwed
        ) = inventoryStaking.positions(positionId);
        assertEq(nonce, 0);
        assertEq(vaultId, VAULT_ID);
        assertEq(
            timelockedUntil,
            block.timestamp + inventoryStaking.timelock()
        );
        assertEq(vTokenShareBalance, mintedVTokens);
        assertEq(
            wethFeesPerVTokenShareSnapshotX128,
            globalWethFeesPerVTokenShareX128
        );
        assertEq(wethOwed, 0);

        // should update total vToken shares
        (, uint256 postTotalVTokenShares, ) = inventoryStaking.vaultGlobal(
            VAULT_ID
        );
        assertEq(postTotalVTokenShares, vTokenShareBalance);
    }

    function test_deposit_Success_WhenPreTotalSharesNonZero() external {
        // initial stake to make totalVTokenShares non zero
        uint256 mintedVTokens = _mintVToken(1);
        vtoken.approve(address(inventoryStaking), type(uint256).max);
        address recipient = makeAddr("recipient");
        inventoryStaking.deposit(VAULT_ID, mintedVTokens, recipient);

        (
            uint256 preNetVTokenBalance,
            uint256 preTotalVTokenShares,
            uint256 globalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);
        assertTrue(preTotalVTokenShares != 0);

        mintedVTokens = _mintVToken(3);

        vm.expectEmit(true, true, false, true);
        emit Deposit(VAULT_ID, 2, mintedVTokens);
        uint256 positionId = inventoryStaking.deposit(
            VAULT_ID,
            mintedVTokens,
            recipient
        );

        // mints position nft to the recipient
        assertEq(inventoryStaking.ownerOf(positionId), recipient);

        (
            uint256 nonce,
            uint256 vaultId,
            uint256 timelockedUntil,
            uint256 vTokenShareBalance,
            uint256 wethFeesPerVTokenShareSnapshotX128,
            uint256 wethOwed
        ) = inventoryStaking.positions(positionId);
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
        (, uint256 postTotalVTokenShares, ) = inventoryStaking.vaultGlobal(
            VAULT_ID
        );
        assertEq(
            postTotalVTokenShares,
            preTotalVTokenShares + vTokenShareBalance
        );
    }

    function test_deposit_Success_WhenOnTimelockExcludeList() external {
        timelockExcludeList.setExcludeFromAll(address(this), true);

        // initial stake to make totalVTokenShares non zero
        uint256 mintedVTokens = _mintVToken(1);
        vtoken.approve(address(inventoryStaking), type(uint256).max);
        address recipient = makeAddr("recipient");
        inventoryStaking.deposit(VAULT_ID, mintedVTokens, recipient);

        (
            uint256 preNetVTokenBalance,
            uint256 preTotalVTokenShares,
            uint256 globalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);
        assertTrue(preTotalVTokenShares != 0);

        mintedVTokens = _mintVToken(3);

        vm.expectEmit(true, true, false, true);
        emit Deposit(VAULT_ID, 2, mintedVTokens);
        uint256 positionId = inventoryStaking.deposit(
            VAULT_ID,
            mintedVTokens,
            recipient
        );

        // mints position nft to the recipient
        assertEq(inventoryStaking.ownerOf(positionId), recipient);

        (
            uint256 nonce,
            uint256 vaultId,
            uint256 timelockedUntil,
            uint256 vTokenShareBalance,
            uint256 wethFeesPerVTokenShareSnapshotX128,
            uint256 wethOwed
        ) = inventoryStaking.positions(positionId);
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
        (, uint256 postTotalVTokenShares, ) = inventoryStaking.vaultGlobal(
            VAULT_ID
        );
        assertEq(
            postTotalVTokenShares,
            preTotalVTokenShares + vTokenShareBalance
        );
    }

    // InventoryStaking#receiveRewards

    function test_receiveRewards_RevertsForNonFeeDistributor() external {
        hoax(makeAddr("nonFeeDistributor"));
        vm.expectRevert();
        inventoryStaking.receiveRewards(VAULT_ID, 1 ether, true);
    }

    function test_receiveRewards_WhenTotalSharesZero() external {
        (
            uint256 preNetVTokenBalance,
            uint256 totalVTokenShares,
            uint256 preGlobalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);
        assertEq(totalVTokenShares, 0);

        uint256 preWethBalance = weth.balanceOf(address(inventoryStaking));

        hoax(address(feeDistributor));
        bool rewardsDistributed = inventoryStaking.receiveRewards(
            VAULT_ID,
            1 ether,
            true
        );

        uint256 postWethBalance = weth.balanceOf(address(inventoryStaking));
        (
            uint256 postNetVTokenBalance,
            ,
            uint256 postGlobalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);

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
        assertEq(
            postNetVTokenBalance,
            preNetVTokenBalance,
            "netVTokenBalance was modified"
        );
    }

    function test_receiveRewards_Success_WhenRewardIsWeth() external {
        // initial stake to make totalVTokenShares non zero
        uint256 mintedVTokens = _mintVToken(1);
        vtoken.approve(address(inventoryStaking), type(uint256).max);
        address recipient = makeAddr("recipient");
        inventoryStaking.deposit(VAULT_ID, mintedVTokens, recipient);

        uint256 wethRewardAmt = 2 ether;
        weth.deposit{value: wethRewardAmt}();
        weth.transfer(address(feeDistributor), wethRewardAmt);

        startHoax(address(feeDistributor));
        weth.approve(address(inventoryStaking), type(uint256).max);

        (
            uint256 preNetVTokenBalance,
            uint256 totalVTokenShares,
            uint256 preGlobalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);
        uint256 preWethBalance = weth.balanceOf(address(inventoryStaking));

        bool rewardsDistributed = inventoryStaking.receiveRewards(
            VAULT_ID,
            wethRewardAmt,
            true
        );
        vm.stopPrank();

        uint256 postWethBalance = weth.balanceOf(address(inventoryStaking));
        (
            uint256 postNetVTokenBalance,
            ,
            uint256 postGlobalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);

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

    function test_receiveRewards_Success_WhenRewardIsVToken() external {
        // initial stake to make totalVTokenShares non zero
        uint256 mintedVTokens = _mintVToken(1);
        vtoken.approve(address(inventoryStaking), type(uint256).max);
        address recipient = makeAddr("recipient");
        inventoryStaking.deposit(VAULT_ID, mintedVTokens, recipient);

        uint256 vTokenRewardAmt = _mintVToken(2);
        vtoken.transfer(address(feeDistributor), vTokenRewardAmt);

        startHoax(address(feeDistributor));
        vtoken.approve(address(inventoryStaking), type(uint256).max);

        (
            uint256 preNetVTokenBalance,
            ,
            uint256 preGlobalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);
        uint256 preVTokenBalance = vtoken.balanceOf(address(inventoryStaking));

        bool rewardsDistributed = inventoryStaking.receiveRewards(
            VAULT_ID,
            vTokenRewardAmt,
            false
        );
        vm.stopPrank();

        uint256 postVTokenBalance = vtoken.balanceOf(address(inventoryStaking));
        (
            uint256 postNetVTokenBalance,
            ,
            uint256 postGlobalWethFeesPerVTokenShareX128
        ) = inventoryStaking.vaultGlobal(VAULT_ID);

        assertEq(rewardsDistributed, true);
        assertEq(
            postVTokenBalance - preVTokenBalance,
            vTokenRewardAmt,
            "vToken transferred amount incorrect"
        );
        assertEq(
            postGlobalWethFeesPerVTokenShareX128,
            preGlobalWethFeesPerVTokenShareX128,
            "globalWethFeesPerVTokenShare was modified"
        );
        assertEq(
            postNetVTokenBalance - preNetVTokenBalance,
            vTokenRewardAmt,
            "netVTokenBalance was modified incorrectly"
        );
    }

    // InventoryStaking#setTimelock

    function test_setTimelock_RevertsForNonOwner() external {
        uint256 newTimelock = 10 days;

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
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
        vm.expectRevert("Ownable: caller is not the owner");
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
}
