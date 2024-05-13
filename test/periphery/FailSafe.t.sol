// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";
import {TickHelpers} from "@src/lib/TickHelpers.sol";

import {FailSafe} from "@src/periphery/FailSafe.sol";
import {Pausable} from "@src/custom/Pausable.sol";

import {TestBase} from "@test/TestBase.sol";

contract FailSafeTests is TestBase {
    FailSafe failsafe;

    uint256 constant INVENTORY_LOCK_ID_DEPOSIT = 0;
    uint256 constant INVENTORY_LOCK_ID_DEPOSIT_WITH_NFT = 1;
    uint256 constant INVENTORY_LOCK_ID_WITHDRAW = 2;
    uint256 constant INVENTORY_LOCK_ID_COLLECT_WETH_FEES = 3;
    uint256 constant INVENTORY_LOCK_ID_INCREASE_POSITION = 4;

    uint256 constant VAULT_FACTORY_LOCK_ID_CREATE_VAULT = 0;

    uint256 constant FEE_DISTRIBUTOR_LOCK_ID_DISTRIBUTE = 0;
    uint256 constant FEE_DISTRIBUTOR_LOCK_ID_DISTRIBUTE_VTOKENS = 1;

    uint256 constant NFTX_ROUTER_LOCK_ID_ADDLIQ = 0;
    uint256 constant NFTX_ROUTER_LOCK_ID_INCREASELIQ = 1;
    uint256 constant NFTX_ROUTER_LOCK_ID_REMOVELIQ = 2;
    uint256 constant NFTX_ROUTER_LOCK_ID_SELLNFTS = 3;
    uint256 constant NFTX_ROUTER_LOCK_ID_BUYNFTS = 4;

    function setUp() public override {
        super.setUp();

        FailSafe.Contract[] memory contracts = new FailSafe.Contract[](4);
        contracts[0] = FailSafe.Contract({
            addr: address(inventoryStaking),
            lastLockId: 4
        });
        contracts[1] = FailSafe.Contract({
            addr: address(vaultFactory),
            lastLockId: 0
        });
        contracts[2] = FailSafe.Contract({
            addr: address(feeDistributor),
            lastLockId: 1
        });
        contracts[3] = FailSafe.Contract({
            addr: address(nftxRouter),
            lastLockId: 4
        });

        failsafe = new FailSafe(contracts);

        // add the failsafe as guardian
        for (uint256 i; i < contracts.length; i++) {
            Pausable(contracts[i].addr).setIsGuardian(address(failsafe), true);
        }
    }

    // FailSafe#pauseAll

    function test_FailSafe_pauseAll_RevertsForNonGuardian() external {
        hoax(makeAddr("nonGuardian"));
        vm.expectRevert(FailSafe.NotGuardian.selector);
        failsafe.pauseAll();
    }

    function test_FailSafe_pauseAll_Success() external {
        address newGuardian = makeAddr("newGuardian");
        failsafe.setIsGuardian(newGuardian, true);
        startHoax(newGuardian);

        failsafe.pauseAll();

        // check if all operations are paused
        assertTrue(inventoryStaking.isPaused(INVENTORY_LOCK_ID_DEPOSIT));
        assertTrue(
            inventoryStaking.isPaused(INVENTORY_LOCK_ID_DEPOSIT_WITH_NFT)
        );
        assertTrue(inventoryStaking.isPaused(INVENTORY_LOCK_ID_WITHDRAW));
        assertTrue(
            inventoryStaking.isPaused(INVENTORY_LOCK_ID_COLLECT_WETH_FEES)
        );
        assertTrue(
            inventoryStaking.isPaused(INVENTORY_LOCK_ID_INCREASE_POSITION)
        );

        assertTrue(vaultFactory.isPaused(VAULT_FACTORY_LOCK_ID_CREATE_VAULT));

        assertTrue(feeDistributor.isPaused(FEE_DISTRIBUTOR_LOCK_ID_DISTRIBUTE));
        assertTrue(
            feeDistributor.isPaused(FEE_DISTRIBUTOR_LOCK_ID_DISTRIBUTE_VTOKENS)
        );

        assertTrue(nftxRouter.isPaused(NFTX_ROUTER_LOCK_ID_ADDLIQ));
        assertTrue(nftxRouter.isPaused(NFTX_ROUTER_LOCK_ID_INCREASELIQ));
        assertTrue(nftxRouter.isPaused(NFTX_ROUTER_LOCK_ID_REMOVELIQ));
        assertTrue(nftxRouter.isPaused(NFTX_ROUTER_LOCK_ID_SELLNFTS));
        assertTrue(nftxRouter.isPaused(NFTX_ROUTER_LOCK_ID_BUYNFTS));
    }

    // FailSafe#setContracts

    function test_FailSafe_setContracts_RevertsForNonOwner() external {
        hoax(makeAddr("nonOwner"));
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        failsafe.setContracts(new FailSafe.Contract[](0));
    }

    function test_FailSafe_setContracts_Success() external {
        FailSafe.Contract[] memory contracts = new FailSafe.Contract[](5);
        contracts[0] = FailSafe.Contract({
            addr: address(inventoryStaking),
            lastLockId: 4
        });
        contracts[1] = FailSafe.Contract({
            addr: address(vaultFactory),
            lastLockId: 0
        });
        contracts[2] = FailSafe.Contract({
            addr: address(feeDistributor),
            lastLockId: 1
        });
        contracts[3] = FailSafe.Contract({
            addr: address(nftxRouter),
            lastLockId: 4
        });
        contracts[4] = FailSafe.Contract({
            addr: makeAddr("newContract"),
            lastLockId: 5
        });

        failsafe.setContracts(contracts);

        // check if the contracts are set
        for (uint256 i; i < contracts.length; i++) {
            (address addr, uint256 lastLockId) = failsafe.contracts(i);
            assertEq(addr, contracts[i].addr);
            assertEq(lastLockId, contracts[i].lastLockId);
        }
    }

    // FailSafe#setIsGuardian
    function test_FailSafe_setIsGuardian_RevertsForNonOwner() external {
        hoax(makeAddr("nonOwner"));
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        failsafe.setIsGuardian(makeAddr("addr"), true);
    }

    function test_FailSafe_setIsGuardian_Success() external {
        address newGuardian = makeAddr("newGuardian");
        failsafe.setIsGuardian(newGuardian, true);

        assertTrue(failsafe.isGuardian(newGuardian));
    }
}
