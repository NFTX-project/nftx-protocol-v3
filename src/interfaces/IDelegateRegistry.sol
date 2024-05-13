// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

interface IDelegateRegistry {
    function delegateAll(
        address to,
        bytes32 rights,
        bool enable
    ) external payable returns (bytes32 delegationHash);

    function checkDelegateForAll(
        address to,
        address from,
        bytes32 rights
    ) external view returns (bool valid);
}
