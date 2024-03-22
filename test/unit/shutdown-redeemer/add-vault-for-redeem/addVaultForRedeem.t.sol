// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ShutdownRedeemerUpgradeable} from "@src/ShutdownRedeemerUpgradeable.sol";
import {NFTXVaultUpgradeableV3} from "@src/NFTXVaultUpgradeableV3.sol";
import {MockNFT} from "@mocks/MockNFT.sol";

import {ShutdownRedeemer_Unit_Test} from "../ShutdownRedeemer.t.sol";

contract ShutdownRedeemer_addVaultForRedeem_Unit_Test is
    ShutdownRedeemer_Unit_Test
{
    uint256 vaultId;
    uint256 ethToSend;

    event EthPerVTokenSet(uint256 indexed vaultId, uint256 value);

    function setUp() public virtual override {
        super.setUp();

        (vaultId, ) = deployVToken721(vaultFactory);
    }

    function test_RevertWhen_TheCallerIsNotTheOwner() external {
        // it should revert
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        shutdownRedeemer.addVaultForRedeem(vaultId);
    }

    modifier whenTheCallerIsTheOwner() {
        switchPrank(users.owner);
        _;
    }

    function test_RevertWhen_NoEthIsSent() external whenTheCallerIsTheOwner {
        ethToSend = 0;

        // it should revert
        vm.expectRevert(ShutdownRedeemerUpgradeable.NoETHSent.selector);
        shutdownRedeemer.addVaultForRedeem(vaultId);
    }

    function test_WhenEthIsSent() external whenTheCallerIsTheOwner {
        ethToSend = 0.5 ether;
        uint256 nftQty = 2;
        uint256 expectedEthPerVToken = 0.25 ether;

        // mint vTokens to have totalSupply non zero
        NFTXVaultUpgradeableV3 vault = NFTXVaultUpgradeableV3(
            vaultFactory.vault(vaultId)
        );

        MockNFT nft = MockNFT(vault.assetAddress());
        uint256[] memory tokenIds = nft.mint(nftQty);
        nft.setApprovalForAll(address(vault), true);

        vault.mint({
            tokenIds: tokenIds,
            amounts: emptyAmounts,
            depositor: users.owner,
            to: users.owner
        });
        // shutdown vault
        vault.shutdown({recipient: users.owner, tokenIds: tokenIds});

        // it should emit {EthPerVTokenSet} event
        vm.expectEmit(true, false, false, true);
        emit EthPerVTokenSet(vaultId, expectedEthPerVToken);
        shutdownRedeemer.addVaultForRedeem{value: ethToSend}(vaultId);

        // it should set eth per vtoken value
        assertEq(shutdownRedeemer.ethPerVToken(vaultId), expectedEthPerVToken);
    }
}
