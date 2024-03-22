// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ShutdownRedeemerUpgradeable} from "@src/ShutdownRedeemerUpgradeable.sol";
import {PausableUpgradeable} from "@src/custom/PausableUpgradeable.sol";
import {NFTXVaultUpgradeableV3} from "@src/NFTXVaultUpgradeableV3.sol";
import {MockNFT} from "@mocks/MockNFT.sol";

import {ShutdownRedeemer_Unit_Test} from "../ShutdownRedeemer.t.sol";

contract ShutdownRedeemer_redeem_Unit_Test is ShutdownRedeemer_Unit_Test {
    uint256 constant PAUSE_REDEEM_LOCKID = 0;

    uint256 vaultId;
    uint256 vTokenAmount;

    uint256 ethPerVToken = 0.5 ether;
    NFTXVaultUpgradeableV3 vault;

    event Redeemed(
        uint256 indexed vaultId,
        uint256 vTokenAmount,
        uint256 ethAmount
    );

    function setUp() public virtual override {
        super.setUp();

        (vaultId, vault) = deployVToken721(vaultFactory);
    }

    function test_RevertGiven_TheRedeemOperationIsPaused() external {
        // pause redeem
        switchPrank(users.owner);
        shutdownRedeemer.setIsGuardian(users.owner, true);
        shutdownRedeemer.pause(PAUSE_REDEEM_LOCKID);
        switchPrank(users.alice);

        // it should revert
        vm.expectRevert(PausableUpgradeable.Paused.selector);
        shutdownRedeemer.redeem(vaultId, vTokenAmount);
    }

    modifier givenTheRedeemOperationIsNotPaused() {
        _;
    }

    modifier givenTheCallerHasApprovedThisContractToSpendTheirVTokens() {
        vault.approve(address(shutdownRedeemer), type(uint256).max);
        _;
    }

    function test_RevertGiven_TheRedeemHasNotBeenEnabledForTheRequestedVaultId()
        external
        givenTheRedeemOperationIsNotPaused
        givenTheCallerHasApprovedThisContractToSpendTheirVTokens
    {
        // it should revert
        vm.expectRevert(ShutdownRedeemerUpgradeable.RedeemNotEnabled.selector);
        shutdownRedeemer.redeem(vaultId, vTokenAmount);
    }

    function test_GivenTheRedeemHasBeenEnabledForTheRequestedVaultId()
        external
        givenTheRedeemOperationIsNotPaused
        givenTheCallerHasApprovedThisContractToSpendTheirVTokens
    {
        //  == addVaultForRedeem ==
        // mint vTokens to have totalSupply non zero
        uint256 nftQty = 2;

        MockNFT nft = MockNFT(vault.assetAddress());
        uint256[] memory tokenIds = nft.mint(nftQty);
        nft.setApprovalForAll(address(vault), true);

        vault.mint({
            tokenIds: tokenIds,
            amounts: emptyAmounts,
            depositor: users.alice,
            to: users.alice
        });
        // shutdown vault
        switchPrank(users.owner);
        vault.shutdown({recipient: users.owner, tokenIds: tokenIds});

        shutdownRedeemer.addVaultForRedeem{value: ethPerVToken * nftQty}(
            vaultId
        );
        switchPrank(users.alice);
        // ====
        vTokenAmount = 0.4 ether;
        uint256 expectedETH = 0.2 ether; // ethPerVToken * vTokenAmount / 1 ether

        uint256 preContractVTokenBalance = vault.balanceOf(
            address(shutdownRedeemer)
        );
        uint256 preUserETHBalance = users.alice.balance;

        // it should emit {Redeemed} event
        vm.expectEmit(true, false, false, true);
        emit Redeemed(vaultId, vTokenAmount, expectedETH);
        shutdownRedeemer.redeem(vaultId, vTokenAmount);

        uint256 postUserETHBalance = users.alice.balance;
        uint256 postContractVTokenBalance = vault.balanceOf(
            address(shutdownRedeemer)
        );

        // it should lock the vTokens in this contract
        assertEq(
            postContractVTokenBalance - preContractVTokenBalance,
            vTokenAmount
        );
        // it should transfer ETH to the caller
        assertEq(postUserETHBalance - preUserETHBalance, expectedETH);
    }
}
