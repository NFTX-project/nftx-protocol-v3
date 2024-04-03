// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

// inheriting
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

// interfaces
import {IRescueAirdrop} from "@src/interfaces/IRescueAirdrop.sol";

contract RescueAirdropFactory is UpgradeableBeacon {
    uint256 public proxyCount;

    event ProxyDeployed(uint256 indexed proxyCount, address proxy);

    constructor(
        address beaconImplementation
    ) UpgradeableBeacon(beaconImplementation) {}

    function deployNewProxy() external onlyOwner {
        address proxy = address(new BeaconProxy(address(this), ""));
        IRescueAirdrop(proxy).__RescueAirdrop_init();

        emit ProxyDeployed(proxyCount, proxy);

        proxyCount++;
    }

    function rescueTokens(
        address proxy,
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        IRescueAirdrop(proxy).rescueTokens(token, to, amount);
    }
}
