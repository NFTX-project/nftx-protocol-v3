// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(uint256 amount) ERC20("MOCK", "MOCK") {
        _mint(msg.sender, amount);
    }
}
