// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {Test, console} from "forge-std/Test.sol";

import {RescueAirdropFactory} from "@src/RescueAirdropFactory.sol";
import {RescueAirdropUpgradeable} from "@src/RescueAirdropUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

contract RescueAirdropTests is Test {
    uint256 baseFork;
    // uint256 BLOCK_NUMBER = 12683328;
    uint256 CHAIN_ID = 8453;

    address FACTORY_DEPLOYER = 0x6ce798Bc8C8C93F3C312644DcbdD2ad6698622C5;
    uint256 deployerNonce = 9;
    address NFTX_FACTORY = 0xBE86f647b167567525cCAAfcd6f881F1Ee558216;
    uint256 factoryNonce = 307;
    address MFER_VAULT = 0xDF7A2593A70fF1e69b5a20644Ae848558A2F7C86;
    address MFER_AIRDROP_TOKEN = 0xE3086852A4B125803C815a158249ae468A3254Ca;
    uint256 airdropAmount = 670_000 ether;

    RescueAirdropUpgradeable rescueAirdropImpl;
    RescueAirdropFactory rescueAidropFactory;

    function setUp() public {
        // Generate a base fork
        baseFork = vm.createFork(vm.envString("BASE_RPC_URL"));
        // Select our fork for the VM
        vm.selectFork(baseFork);

        // the MFER token on Base uses solc ^0.8.20 so the test will fail here with EvmError: NotActivated
        // so instead etching MockERC20 here
        MockERC20 token = new MockERC20(airdropAmount);
        vm.etch(MFER_AIRDROP_TOKEN, address(token).code);

        // transfer tokens to the vault address
        token.transfer(MFER_VAULT, airdropAmount);
    }

    function test_claim_MFER() public {
        // send some ETH to the deployer
        vm.deal(FACTORY_DEPLOYER, 10 ether);
        vm.startPrank(FACTORY_DEPLOYER);

        uint256 mferAirdropAmount = IERC20(MFER_AIRDROP_TOKEN).balanceOf(
            MFER_VAULT
        );

        rescueAirdropImpl = new RescueAirdropUpgradeable();

        for (uint256 i; i < deployerNonce; ++i) {
            rescueAidropFactory = new RescueAirdropFactory(
                address(rescueAirdropImpl)
            );
        }
        assertEq(address(rescueAidropFactory), NFTX_FACTORY);

        rescueAidropFactory.deployNewProxies(factoryNonce + 1);

        uint256 preMFERBalance = IERC20(MFER_AIRDROP_TOKEN).balanceOf(
            FACTORY_DEPLOYER
        );
        rescueAidropFactory.rescueTokens(
            MFER_VAULT,
            MFER_AIRDROP_TOKEN,
            FACTORY_DEPLOYER,
            mferAirdropAmount
        );
        uint256 postMFERBalance = IERC20(MFER_AIRDROP_TOKEN).balanceOf(
            FACTORY_DEPLOYER
        );

        assertEq(postMFERBalance - preMFERBalance, mferAirdropAmount);
    }
}
