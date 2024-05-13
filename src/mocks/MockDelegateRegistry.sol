// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;
import {IDelegateRegistry} from "@src/interfaces/IDelegateRegistry.sol";

contract MockDelegateRegistry is IDelegateRegistry {
    mapping(address => mapping(address => mapping(bytes32 => bool)))
        public delegates;

    function delegateAll(
        address to,
        bytes32 rights,
        bool enable
    ) external payable override returns (bytes32 delegationHash) {
        delegates[msg.sender][to][rights] = enable;
        return bytes32(0);
    }

    function checkDelegateForAll(
        address to,
        address from,
        bytes32 rights
    ) external view override returns (bool valid) {
        valid = delegates[from][to][rights];
    }
}
