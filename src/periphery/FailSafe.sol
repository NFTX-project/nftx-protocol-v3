// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

// inheriting
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IPausable {
    function pause(uint256 lockId) external;
}

/**
 * @title Fail Safe
 * @author @apoorvlathey
 *
 * @notice Pause all operations at once. This contract must be set as guardian.
 */
contract FailSafe is Ownable {
    // types
    struct Contract {
        address addr;
        uint256 lastLockId;
    }

    // storage
    Contract[] public contracts;
    mapping(address => bool) public isGuardian;

    // events
    event SetIsGuardian(address addr, bool isGuardian);

    // errors
    error NotGuardian();

    constructor(Contract[] memory _contracts) {
        setContracts(_contracts);
        isGuardian[msg.sender] = true;
    }

    // modifiers
    modifier onlyGuardian() {
        if (!isGuardian[msg.sender]) revert NotGuardian();
        _;
    }

    // external functions
    // onlyGuardian
    function pauseAll() external onlyGuardian {
        uint256 len = contracts.length;
        for (uint256 i; i < len; ) {
            Contract storage c = contracts[i];

            for (uint256 j; j <= c.lastLockId; ) {
                IPausable(c.addr).pause(j);

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    // onlyOwner
    function setContracts(Contract[] memory _contracts) public onlyOwner {
        delete contracts;

        uint256 len = _contracts.length;
        for (uint256 i; i < len; ) {
            contracts.push(_contracts[i]);

            unchecked {
                ++i;
            }
        }
    }

    function setIsGuardian(address addr, bool _isGuardian) external onlyOwner {
        isGuardian[addr] = _isGuardian;
        emit SetIsGuardian(addr, _isGuardian);
    }
}
