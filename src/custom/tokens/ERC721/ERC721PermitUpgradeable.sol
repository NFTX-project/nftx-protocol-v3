abstract contract ERC721PermitUpgradeable is BlockTimestamp, ERC721EnumerableUpgradeable, IERC721PermitUpgradeable {
    function _getAndIncrementNonce(uint256 tokenId) internal virtual returns (uint256);
    bytes32 private nameHash;
    bytes32 private versionHash;
    error PermitExpired();
    error ApprovalToCurrentOwner();
    error InvalidSignature();
    error Unauthorized();
    function __ERC721PermitUpgradeable_init(string memory name_, string memory symbol_, string memory version_) internal onlyInitializing {
        __ERC721_init(name_, symbol_);
        nameHash = keccak256(bytes(name_));
        versionHash = keccak256(bytes(version_));
    }
    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
                    nameHash,
                    versionHash,
                    ChainId.get(),
                    address(this)
                )
            );
    }
    bytes32 public constant override PERMIT_TYPEHASH = 0x49ecf333e5b8c95c40fdafc95c1ad136e8914a8fb55e9dc8bb01eaa83a2df9ad;
    function permit(address spender, uint256 tokenId, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external payable override {
        if (_blockTimestamp() > deadline) revert PermitExpired();
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        spender,
                        tokenId,
                        _getAndIncrementNonce(tokenId),
                        deadline
                    )
                )
            )
        );
        address owner = ownerOf(tokenId);
        if (spender == owner) revert ApprovalToCurrentOwner();
        if (AddressUpgradeable.isContract(owner)) {
            if (
                IERC1271(owner).isValidSignature(
                    digest,
                    abi.encodePacked(r, s, v)
                ) != 0x1626ba7e
            ) revert Unauthorized();
        } else {
            address recoveredAddress = ecrecover(digest, v, r, s);
            if (recoveredAddress == address(0)) revert InvalidSignature();
            if (recoveredAddress != owner) revert Unauthorized();
        }
        _approve(spender, tokenId);
    }
}
