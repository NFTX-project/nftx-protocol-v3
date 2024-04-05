// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TransferLib} from "@src/lib/TransferLib.sol";

import {ShutdownRedeemer_Unit_Test} from "../ShutdownRedeemer.t.sol";

contract ShutdownRedeemer_recoverETH_Unit_Test is ShutdownRedeemer_Unit_Test {
    uint256 ethAmount = 2 ether;

    function test_RevertWhen_TheCallerIsNotTheOwner() external {
        // it should revert
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        shutdownRedeemer.recoverETH(ethAmount);
    }

    function test_WhenTheCallerIsTheOwner() external {
        switchPrank(users.owner);

        // send some ETH beforehand
        TransferLib.transferETH(address(shutdownRedeemer), ethAmount);

        // it should transfer the requested ETH to the owner
        uint256 preETHBalance = users.owner.balance;

        shutdownRedeemer.recoverETH(ethAmount);

        uint256 postETHBalance = users.owner.balance;
        assertEq(postETHBalance - preETHBalance, ethAmount);
    }
}
