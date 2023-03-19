// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {INFTXVaultFactory} from "@src/v2/interface/INFTXVaultFactory.sol";

import {INFTXInventoryStakingV3} from "@src/interfaces/INFTXInventoryStakingV3.sol";

contract MockInventoryStakingV3 is INFTXInventoryStakingV3 {
    INFTXVaultFactory public override nftxVaultFactory;

    IERC20 public immutable WETH;

    constructor(INFTXVaultFactory nftxVaultFactory_, IERC20 WETH_) {
        nftxVaultFactory = nftxVaultFactory_;
        WETH = WETH_;
    }

    function deployXTokenForVault(uint256 vaultId) external override {}

    function receiveRewards(
        uint256 /** vaultId */,
        uint256 wethAmount
    ) external returns (bool) {
        WETH.transferFrom(msg.sender, address(this), wethAmount);
        return true;
    }
}
