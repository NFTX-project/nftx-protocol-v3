// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";

import {CreateVaultZap} from "@src/zaps/CreateVaultZap.sol";

import {TestBase} from "@test/TestBase.sol";

contract CreateVaultZapTests is TestBase {
    CreateVaultZap createVaultZap;

    function setUp() public override {
        super.setUp();

        createVaultZap = new CreateVaultZap(
            nftxRouter,
            factory,
            inventoryStaking
        );

        vaultFactory.setFeeExclusion(address(createVaultZap), true);
    }

    function test_createVault_Success() external {
        uint256 qty = 5;
        uint256[] memory tokenIds = nft.mint(qty);
        nft.setApprovalForAll(address(createVaultZap), true);

        createVaultZap.createVault{value: 10 ether}(
            CreateVaultZap.CreateVaultParams({
                vaultInfo: CreateVaultZap.VaultInfo({
                    assetAddress: address(nft),
                    is1155: false,
                    allowAllItems: true,
                    name: "MOCK Vault",
                    symbol: "MOCK"
                }),
                eligibilityStorage: CreateVaultZap.VaultEligibilityStorage({
                    moduleIndex: 0,
                    initData: ""
                }),
                nftIds: tokenIds,
                nftAmounts: emptyIds,
                vaultFeaturesFlag: 5, // = 1,0,1
                vaultFees: CreateVaultZap.VaultFees({
                    mintFee: 0.01 ether,
                    redeemFee: 0.01 ether,
                    swapFee: 0.01 ether
                }),
                liquidityParams: CreateVaultZap.LiquidityParams({
                    lowerNFTPriceInETH: 3 ether,
                    upperNFTPriceInETH: 5 ether,
                    fee: DEFAULT_FEE_TIER,
                    currentNFTPriceInETH: 4 ether,
                    vTokenMin: 0,
                    wethMin: 0,
                    deadline: block.timestamp
                })
            })
        );
    }
}
