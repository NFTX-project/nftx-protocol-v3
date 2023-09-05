abstract contract ERC20FlashMintUpgradeable is Initializable, ERC20Upgradeable, IERC3156FlashLenderUpgradeable{
    error WrongToken();
    error AmountExceedsMaxFlashLoan();
    error InvalidReturnValue();
    function __ERC20FlashMint_init() internal onlyInitializing {}
    function __ERC20FlashMint_init_unchained() internal onlyInitializing {}
    bytes32 private constant _RETURN_VALUE =
        keccak256("ERC3156FlashBorrower.onFlashLoan");
    function maxFlashLoan(address token) public view virtual override returns (uint256) {
        return
            token == address(this)
                ? type(uint256).max - ERC20Upgradeable.totalSupply()
                : 0;
    }
    function flashFee(address token, uint256 amount) public view virtual override returns (uint256) {
        if (token != address(this)) revert WrongToken();
        return _flashFee(token, amount);
    }
    function _flashFee(address token, uint256 amount) internal view virtual returns (uint256) {
        token;
        amount;
        return 0;
    }
    function _flashFeeReceiver() internal view virtual returns (address) {
        return address(0);
    }
    function flashLoan(IERC3156FlashBorrowerUpgradeable receiver, address token, uint256 amount, bytes calldata data) public virtual override returns (bool) {
        if (amount > maxFlashLoan(token)) revert AmountExceedsMaxFlashLoan();
        uint256 fee = flashFee(token, amount);
        _mint(address(receiver), amount);
        if (receiver.onFlashLoan(msg.sender, token, amount, fee, data) != _RETURN_VALUE)
            revert InvalidReturnValue();
        address flashFeeReceiver = _flashFeeReceiver();
        _spendAllowance(address(receiver), address(this), amount + fee);
        if (fee == 0 || flashFeeReceiver == address(0)) {
            _burn(address(receiver), amount + fee);
        } else {
            _burn(address(receiver), amount);
            _transfer(address(receiver), flashFeeReceiver, fee);
        }
        return true;
    }
    uint256[50] private __gap;
}
