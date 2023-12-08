// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;
import {IDelegateRegistry} from "@src/interfaces/IDelegateRegistry.sol";

contract MockDelegateRegistry is IDelegateRegistry {
    function delegateAll(
        address to,
        bytes32 rights,
        bool enable
    ) external payable override returns (bytes32 delegationHash) {
        return bytes32(0);
    }
}
