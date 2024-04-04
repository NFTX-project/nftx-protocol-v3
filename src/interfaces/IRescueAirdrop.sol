// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

interface IRescueAirdrop {
    function __RescueAirdrop_init() external;

    function rescueTokens(address token, address to, uint256 amount) external;
}
