// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";

import {NFTXVaultFactoryUpgradeableV3} from "@src/NFTXVaultFactoryUpgradeableV3.sol";
import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";
import {Create2Upgradeable} from "@openzeppelin-upgradeable/contracts/utils/Create2Upgradeable.sol";
import {ExponentialPremium} from "@src/lib/ExponentialPremium.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Create2BeaconProxy} from "@src/custom/proxy/Create2BeaconProxy.sol";
import {FullMath} from "@uni-core/libraries/FullMath.sol";
import {FixedPoint96} from "@uni-core/libraries/FixedPoint96.sol";
import {UpgradeableBeacon} from "@src/custom/proxy/UpgradeableBeacon.sol";

import {TestBase} from "@test/TestBase.sol";

contract NFTXVaultFactoryTests is TestBase {
    uint256 constant CREATEVAULT_PAUSE_CODE = 0;
    uint256 constant FEE_LIMIT = 0.5 ether;
    uint64 constant DEFAULT_VAULT_FACTORY_FEES = 0.1 ether;

    event Upgraded(address indexed beaconImplementation);

    // NFTXVaultFactory#getVTokenPremium1155
    function test_getVTokenPremium1155_RevertsIfZeroAmountRequested() external {
        uint256 qty = 1;
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        tokenIds[0] = nft1155.mint(qty);
        amounts[0] = qty;

        nft1155.setApprovalForAll(address(vtoken1155), true);
        vtoken1155.mint({
            tokenIds: tokenIds,
            amounts: amounts,
            depositor: address(this),
            to: address(this)
        });

        vm.expectRevert(INFTXVaultFactoryV3.ZeroAmountRequested.selector);
        vaultFactory.getVTokenPremium1155({
            vaultId: VAULT_ID_1155,
            tokenId: tokenIds[0],
            amount: 0
        });
    }

    function test_getVTokenPremium1155_RevertsIfAmountExceedsNFTBalance()
        external
    {
        uint256 qty = 1;
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        tokenIds[0] = nft1155.mint(qty);
        amounts[0] = qty;

        nft1155.setApprovalForAll(address(vtoken1155), true);
        vtoken1155.mint({
            tokenIds: tokenIds,
            amounts: amounts,
            depositor: address(this),
            to: address(this)
        });

        vm.expectRevert(INFTXVaultFactoryV3.NFTInventoryExceeded.selector);
        vaultFactory.getVTokenPremium1155({
            vaultId: VAULT_ID_1155,
            tokenId: tokenIds[0],
            amount: qty + 1
        });
    }

    // Storage
    uint256 s_tokenId;
    uint256 s_amount;
    uint256 s_vTokenPremium;
    uint256[] s_premiums;
    address[] s_depositors;

    function test_getVTokenPremium1155_Success(
        uint256[1000] memory values,
        uint256 depositCount,
        uint256 amount
    ) external {
        amount = bound(amount, 1, 10_000);
        depositCount = bound(depositCount, 1, values.length);

        // To avoid "The `vm.assume` cheatcode rejected too many inputs (65536 allowed)"
        // get 100 random values from depositAmounts, and then create a new array of length depositCount with those values
        uint256[] memory depositAmounts = new uint256[](depositCount);
        for (uint256 i; i < depositCount; i++) {
            depositAmounts[i] = values[i];
        }

        uint256 tokenId = nft1155.nextId();
        nft1155.setApprovalForAll(address(vtoken1155), true);

        uint256 totalDeposited;
        for (uint256 i; i < depositAmounts.length; i++) {
            depositAmounts[i] = bound(depositAmounts[i], 1, type(uint64).max);

            totalDeposited += depositAmounts[i];

            nft1155.mint(tokenId, depositAmounts[i]);

            uint256[] memory tokenIds = new uint256[](1);
            uint256[] memory amounts = new uint256[](1);
            tokenIds[0] = tokenId;
            amounts[0] = depositAmounts[i];

            vtoken1155.mint({
                tokenIds: tokenIds,
                amounts: amounts,
                depositor: makeAddr(
                    string.concat("depositor", Strings.toString(i))
                ),
                to: address(this)
            });
        }
        vm.assume(totalDeposited >= amount);

        // putting in a separate external call to avoid "EvmError: MemoryLimitOOG"
        // using storage instead to pass values
        // source: https://github.com/foundry-rs/foundry/issues/3971#issuecomment-1698653788
        s_tokenId = tokenId;
        s_amount = amount;
        this.getVTokenPremium1155();

        console.log("vTokenPremium: %s", s_vTokenPremium);
        assertGt(s_vTokenPremium, 0);
        assertEq(
            s_vTokenPremium,
            ExponentialPremium.getPremium(
                block.timestamp,
                vaultFactory.premiumMax(),
                vaultFactory.premiumDuration()
            ) * amount
        );

        assertEq(s_premiums.length, s_depositors.length);

        uint256 netDepositAmountUsed;
        for (uint256 i; i < s_depositors.length; i++) {
            uint256 depositAmountUsed;
            if (netDepositAmountUsed + depositAmounts[i] >= amount) {
                depositAmountUsed = amount - netDepositAmountUsed;
            } else {
                depositAmountUsed = depositAmounts[i];
            }
            netDepositAmountUsed += depositAmountUsed;

            assertEq(
                s_premiums[i],
                ExponentialPremium.getPremium(
                    block.timestamp,
                    vaultFactory.premiumMax(),
                    vaultFactory.premiumDuration()
                ) * depositAmountUsed
            );
            assertEq(
                s_depositors[i],
                makeAddr(string.concat("depositor", Strings.toString(i)))
            );
        }
        assertEq(netDepositAmountUsed, amount);
    }

    function getVTokenPremium1155() external {
        (s_vTokenPremium, s_premiums, s_depositors) = vaultFactory
            .getVTokenPremium1155(VAULT_ID_1155, s_tokenId, s_amount);
    }

    // NFTXVaultFactory#computeVaultAddress
    function test_computeVaultAddress_Success() external {
        string memory name = "CryptoPunk";
        string memory symbol = "PUNK";
        address assetAddress = address(nft);

        address vaultAddress = vaultFactory.computeVaultAddress(
            assetAddress,
            name,
            symbol
        );

        address expectedVaultAddress = Create2Upgradeable.computeAddress(
            keccak256(abi.encode(assetAddress, name, symbol)),
            keccak256(type(Create2BeaconProxy).creationCode),
            address(vaultFactory)
        );

        uint256 vaultId = vaultFactory.createVault({
            name: name,
            symbol: symbol,
            assetAddress: assetAddress,
            is1155: false,
            allowAllItems: true
        });
        address actualVaultAddress = vaultFactory.vault(vaultId);

        assertEq(vaultAddress, expectedVaultAddress);
        assertEq(vaultAddress, actualVaultAddress);
    }

    // NFTXVaultFactory#getTwapX96
    function test_getTwapX96(
        uint256 currentNFTPrice,
        uint256 waitForSecs
    ) external {
        // currentNFTPrice has to be min 10 wei to avoid lowerNFTPrice from being zero
        vm.assume(
            currentNFTPrice >= 10 && currentNFTPrice <= type(uint128).max
        );
        // vm.warp doesn't work as expected for very large values
        vm.assume(waitForSecs <= 365 days);

        uint256 lowerNFTPrice = (currentNFTPrice * 95) / 100;
        uint256 upperNFTPrice = (currentNFTPrice * 105) / 100;

        _mintPosition({
            qty: 5,
            currentNFTPrice: currentNFTPrice,
            lowerNFTPrice: lowerNFTPrice,
            upperNFTPrice: upperNFTPrice,
            fee: DEFAULT_FEE_TIER
        });

        vm.warp(block.timestamp + waitForSecs);

        address pool = nftxRouter.getPool(address(vtoken), DEFAULT_FEE_TIER);
        uint256 twapX96 = vaultFactory.getTwapX96(pool);
        uint256 price;
        if (waitForSecs == 0) {
            // for same block, twapX96A will be zero
            assertEq(twapX96, 0);
        } else {
            assertGt(twapX96, 0, "twapX96A == 0");
            // twap should get set instantly from the next second
            if (nftxRouter.isVToken0(address(vtoken))) {
                price = FullMath.mulDiv(1 ether, twapX96, FixedPoint96.Q96);
            } else {
                price = FullMath.mulDiv(1 ether, FixedPoint96.Q96, twapX96);
            }
            assertGt(price, 0);
            assertGt(
                price,
                currentNFTPrice - 2 wei, // to account for any rounding errors
                "!price"
            );
        }
    }

    // UpgradeableBeacon#upgradeBeaconTo
    function test_upgradeBeaconTo_RevertsForNonOwner() external {
        address newImplementation = makeAddr("newImplementation");

        hoax(makeAddr("nonOwner"));
        vm.expectRevert(OWNABLE_NOT_OWNER_ERROR);
        vaultFactory.upgradeBeaconTo(newImplementation);
    }

    function test_upgradeBeaconTo_RevertsForNonContract() external {
        address newImplementation = makeAddr("newImplementation");

        vm.expectRevert(
            UpgradeableBeacon.ChildImplementationIsNotAContract.selector
        );
        vaultFactory.upgradeBeaconTo(newImplementation);
    }

    function test_upgradeBeaconTo_Success() external {
        NFTXVaultFactoryUpgradeableV3 newVaultFactory = new NFTXVaultFactoryUpgradeableV3();
        address newImplementation = address(newVaultFactory);

        address preImplementation = vaultFactory.implementation();
        assertTrue(preImplementation != newImplementation);

        vm.expectEmit(false, false, false, true);
        emit Upgraded(newImplementation);
        vaultFactory.upgradeBeaconTo(newImplementation);
        assertEq(vaultFactory.implementation(), newImplementation);
    }
}
