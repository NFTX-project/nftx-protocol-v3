// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract PausableUpgradeable is OwnableUpgradeable {
    function __Pausable_init() internal onlyInitializing {
        __Ownable_init();
    }

    event SetPaused(uint256 lockId, bool paused);
    event SetIsGuardian(address addr, bool isGuardian);

    // Errors
    error Paused();
    error NotGuardian();

    mapping(address => bool) public isGuardian;
    mapping(uint256 => bool) public isPaused;

    // 0 : createVault
    // 1 : mint
    // 2 : redeem
    // 3 : swap
    // 4 : flashloan

    function onlyOwnerIfPaused(uint256 lockId) public view virtual {
        if (isPaused[lockId] && msg.sender != owner()) revert Paused();
    }

    function unpause(uint256 lockId) public virtual onlyOwner {
        isPaused[lockId] = false;
        emit SetPaused(lockId, false);
    }

    function pause(uint256 lockId) public virtual {
        if (!isGuardian[msg.sender]) revert NotGuardian();
        isPaused[lockId] = true;
        emit SetPaused(lockId, true);
    }

    function setIsGuardian(
        address addr,
        bool _isGuardian
    ) public virtual onlyOwner {
        isGuardian[addr] = _isGuardian;
        emit SetIsGuardian(addr, _isGuardian);
    }
}
