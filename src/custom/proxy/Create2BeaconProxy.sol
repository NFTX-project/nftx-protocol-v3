contract Create2BeaconProxy is Proxy {
    bytes32 private constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;
    error BeaconIsNotAContract();
    error BeaconImplementationIsNotAContract();
    constructor() payable {
        assert(_BEACON_SLOT == bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1));
        _setBeacon(msg.sender, "");
    }
    function _beacon() internal view virtual returns (address beacon) {
        bytes32 slot = _BEACON_SLOT;
        assembly {
            beacon := sload(slot)
        }
    }
    function _implementation() internal view virtual override returns (address) {
        return IBeacon(_beacon()).implementation();
    }
    function _setBeacon(address beacon, bytes memory data) internal virtual {
        if (!Address.isContract(beacon)) revert BeaconIsNotAContract();
        if (!Address.isContract(IBeacon(beacon).implementation()))
            revert BeaconImplementationIsNotAContract();
        bytes32 slot = _BEACON_SLOT;
        assembly {
            sstore(slot, beacon)
        }
        if (data.length > 0) {
            Address.functionDelegateCall(
                _implementation(),
                data,
                "BeaconProxy: function call failed"
            );
        }
    }
}
