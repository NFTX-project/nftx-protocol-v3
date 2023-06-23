// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IBeacon} from "@src/custom/proxy/IBeacon.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

/**
 * @dev This contract is used in conjunction with one or more instances of {BeaconProxy} to determine their
 * implementation contract, which is where they will delegate all function calls.
 *
 * An owner is able to change the implementation the beacon points to, thus upgrading the proxies that use this beacon.
 */
contract UpgradeableBeacon is IBeacon, OwnableUpgradeable {
    address private _beaconImplementation;

    /**
     * @dev Emitted when the child implementation returned by the beacon is changed.
     */
    event Upgraded(address indexed beaconImplementation);

    /**
     * @dev Sets the address of the initial implementation, and the deployer account as the owner who can upgrade the
     * beacon.
     */
    function __UpgradeableBeacon__init(
        address beaconImplementation_
    ) public onlyInitializing {
        __Ownable_init();
        _setBeaconImplementation(beaconImplementation_);
    }

    function implementation() public view virtual override returns (address) {
        return _beaconImplementation;
    }

    /**
     * @dev Upgrades the beacon to a new implementation.
     *
     * Emits an {Upgraded} event.
     *
     * Requirements:
     *
     * - msg.sender must be the owner of the contract.
     * - `newChildImplementation` must be a contract.
     */
    function upgradeBeaconTo(
        address newBeaconImplementation
    ) public virtual override onlyOwner {
        _setBeaconImplementation(newBeaconImplementation);
    }

    /**
     * @dev Sets the implementation contract address for this beacon
     *
     * Requirements:
     *
     * - `newBeaconImplementation` must be a contract.
     */
    function _setBeaconImplementation(address newBeaconImplementation) private {
        // TODO: custom error
        require(
            Address.isContract(newBeaconImplementation),
            "UpgradeableBeacon: child implementation is not a contract"
        );
        _beaconImplementation = newBeaconImplementation;
        emit Upgraded(newBeaconImplementation);
    }
}
