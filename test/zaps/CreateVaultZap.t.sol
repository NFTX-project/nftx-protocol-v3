// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";

import {CreateVaultZap} from "@src/zaps/CreateVaultZap.sol";
import {NFTXVaultUpgradeableV3, INFTXVaultV3} from "@src/NFTXVaultUpgradeableV3.sol";
import {TickMath} from "@uni-core/libraries/TickMath.sol";
import {FullMath} from "@uni-core/libraries/FullMath.sol";
import {TickHelpers} from "@src/lib/TickHelpers.sol";
import {Babylonian} from "@uniswap/lib/contracts/libraries/Babylonian.sol";

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

        uint256 vaultId = createVaultZap.createVault{value: 10 ether}(
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

        vm.warp(block.timestamp + 1);
        address vault = vaultFactory.vault(vaultId);
        uint256 vTokenTWAP = INFTXVaultV3(vault).vTokenToETH(1 ether);
        console.log("vTokenTWAP", vTokenTWAP);
        assertGt(vTokenTWAP, 0);
    }

    function test_createVault_InfiniteRange_Success() external {
        uint256 qty = 5;
        uint256[] memory tokenIds = nft.mint(qty);
        nft.setApprovalForAll(address(createVaultZap), true);

        uint256 vaultId = createVaultZap.createVault{value: 10 ether}(
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
                    lowerNFTPriceInETH: 1,
                    upperNFTPriceInETH: (type(uint256).max / (1 << 142)),
                    fee: DEFAULT_FEE_TIER,
                    currentNFTPriceInETH: 4 ether,
                    vTokenMin: 0,
                    wethMin: 0,
                    deadline: block.timestamp
                })
            })
        );

        vm.warp(block.timestamp + 1);
        address vault = vaultFactory.vault(vaultId);
        uint256 vTokenTWAP = INFTXVaultV3(vault).vTokenToETH(1 ether);
        console.log("vTokenTWAP", vTokenTWAP);
        assertGt(vTokenTWAP, 0);
        (int24 tickLower, int24 tickUpper) = _getTicks(1);
        console.logInt(int256(tickLower));
        console.logInt(int256(tickUpper));
    }

    function test_calcTicks() external view {
        uint256 tickDistance = 200;

        // Max possible value without overflow
        uint256 upperNFTPriceInETH = (type(uint256).max / (1 << 142));
        console.log("upperNFTPriceInETH", upperNFTPriceInETH);

        uint256 sqrtP = Babylonian.sqrt(
            (upperNFTPriceInETH * (2 ** 142)) / 1 ether // replacing "<<" with "2 **" to revert on overflow
        ) * 2 ** 25;
        console.log("upperSqrtP", uint256(sqrtP));

        int24 tickUpper = TickHelpers.getTickForAmounts(
            upperNFTPriceInETH,
            1 ether,
            tickDistance
        );
        console.log("tickUpper:");
        console.logInt(int256(tickUpper));

        console.log("tickMaxFromSqrtRatio:");
        console.logInt(
            int256(TickMath.getTickAtSqrtRatio(TickMath.MAX_SQRT_RATIO - 1))
        );

        uint256 lowerNFTPriceInETH = 1;
        sqrtP =
            Babylonian.sqrt(
                (upperNFTPriceInETH * (2 ** 142)) / 1 ether // replacing "<<" with "2 **" to revert on overflow
            ) *
            2 ** 25;
        console.log("lowerSqrtP", uint256(sqrtP));
        int24 tickLower = TickHelpers.getTickForAmounts(
            lowerNFTPriceInETH,
            1 ether,
            tickDistance
        );
        console.log("tickLower:");
        console.logInt(int256(tickLower));
    }
}
