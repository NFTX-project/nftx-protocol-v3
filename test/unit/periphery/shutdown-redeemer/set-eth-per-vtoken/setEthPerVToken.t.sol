// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ShutdownRedeemer_Unit_Test} from "../ShutdownRedeemer.t.sol";

contract ShutdownRedeemer_setEthPerVToken_Unit_Test is
    ShutdownRedeemer_Unit_Test
{
    uint256 vaultId = 1;
    uint256 ethPerVToken = 0.5 ether;

    event EthPerVTokenSet(uint256 indexed vaultId, uint256 value);

    function test_RevertWhen_TheCallerIsNotTheOwner() external {
        // it should revert
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        shutdownRedeemer.setEthPerVToken(vaultId, ethPerVToken);
    }

    function test_WhenTheCallerIsTheOwner() external {
        switchPrank(users.owner);

        // it should emit {EthPerVTokenSet} event
        vm.expectEmit(true, false, false, true);
        emit EthPerVTokenSet(vaultId, ethPerVToken);
        // it should be payable
        shutdownRedeemer.setEthPerVToken{value: 1 ether}(vaultId, ethPerVToken);
        // it should set eth per vtoken value
        assertEq(shutdownRedeemer.ethPerVToken(vaultId), ethPerVToken);
    }
}
