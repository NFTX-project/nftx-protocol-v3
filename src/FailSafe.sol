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
    struct Contract {
        address addr;
        uint256 lastLockId;
    }

    Contract[] public contracts;

    constructor(Contract[] memory _contracts) {
        setContracts(_contracts);
    }

    function pauseAll() external onlyOwner {
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
}
