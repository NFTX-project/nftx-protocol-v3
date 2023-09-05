contract UpgradeableBeacon is IBeacon, OwnableUpgradeable {
    address private _beaconImplementation;
    event Upgraded(address indexed beaconImplementation);
    error ChildImplementationIsNotAContract();
    function __UpgradeableBeacon__init(address beaconImplementation_) public onlyInitializing {
        __Ownable_init();
        _setBeaconImplementation(beaconImplementation_);
    }
    function implementation() public view virtual override returns (address) {
        return _beaconImplementation;
    }
    function upgradeBeaconTo(address newBeaconImplementation) public virtual override onlyOwner {
        _setBeaconImplementation(newBeaconImplementation);
    }
    function _setBeaconImplementation(address newBeaconImplementation) private {
        if (!Address.isContract(newBeaconImplementation))
            revert ChildImplementationIsNotAContract();
        _beaconImplementation = newBeaconImplementation;
        emit Upgraded(newBeaconImplementation);
    }
}
