// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";
import {TickHelpers} from "@src/lib/TickHelpers.sol";

import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {INFTXVaultV2} from "@src/v2/interfaces/INFTXVaultV2.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "@src/interfaces/external/IUniswapV2Router02.sol";
import {INFTXVaultFactoryV2} from "@src/v2/interfaces/INFTXVaultFactoryV2.sol";
import {INFTXInventoryStakingV2} from "@src/v2/interfaces/INFTXInventoryStakingV2.sol";

import {MigratorZap} from "@src/zaps/MigratorZap.sol";

import {TestBase} from "@test/TestBase.sol";

contract MigratorZapTests is TestBase {
    uint256 mainnetFork;
    uint256 constant BLOCK_NUMBER = 17531150;
    uint256 CHAIN_ID = 1;

    uint256 private constant DEADLINE =
        0xf000000000000000000000000000000000000000000000000000000000000000;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    INFTXVaultFactoryV2 v2NFTXFactory =
        INFTXVaultFactoryV2(0xBE86f647b167567525cCAAfcd6f881F1Ee558216);
    address constant MILADY_NFT = 0x5Af0D9827E0c53E4799BB226655A1de152A425a5;
    address constant V2_MILADY_VTOKEN =
        0x227c7DF69D3ed1ae7574A1a7685fDEd90292EB48;
    address constant MILADY_WETH_SLP =
        0x15A8E38942F9e353BEc8812763fb3C104c89eCf4;
    address constant xMILADY = 0x5D1C5Dee420004767d3e2fb7AA7C75AA92c33117;

    address constant MILADY_WETH_SLP_Holder =
        0x688c3E4658B5367da06fd629E41879beaB538E37;
    address constant xMILADY_Holder =
        0xB520F068a908A1782a543aAcC3847ADB77A04778;
    address constant MILADY_Holder = xMILADY;

    INFTXInventoryStakingV2 v2Inventory =
        INFTXInventoryStakingV2(0x3E135c3E981fAe3383A5aE0d323860a34CfAB893);
    IUniswapV2Router02 sushiRouter =
        IUniswapV2Router02(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    uint256 alicePrivateKey = 42;
    address alice = vm.addr(alicePrivateKey);

    MigratorZap migratorZap;

    uint256 vaultIdV3;

    constructor() {
        // Generate a mainnet fork
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));

        // Select our fork for the VM
        vm.selectFork(mainnetFork);

        // Set our block ID to a specific, test-suitable number
        vm.rollFork(BLOCK_NUMBER);

        // Confirm that our block number has set successfully
        assertEq(block.number, BLOCK_NUMBER);
    }

    function setUp() public override {
        super.setUp();

        migratorZap = new MigratorZap(
            IWETH9(WETH),
            v2NFTXFactory,
            v2Inventory,
            sushiRouter,
            positionManager,
            vaultFactory,
            inventoryStaking
        );
        // exclude from fees in both v2 and v3
        vm.prank(v2NFTXFactory.owner());
        v2NFTXFactory.setFeeExclusion(address(migratorZap), true);
        vaultFactory.setFeeExclusion(address(migratorZap), true);

        // create new Milady vault in v3
        vaultIdV3 = vaultFactory.createVault(
            "MILADY",
            "MILADY",
            address(MILADY_NFT),
            false, // is1155
            true // allowAllItems
        );

        vm.prank(MILADY_WETH_SLP_Holder);
        // tranfer SLP into our private-key controlled address
        IUniswapV2Pair(MILADY_WETH_SLP).transfer(alice, 10 ether);
    }

    function test_sushiToNFTXAMM_Success() external {
        uint256 liquidityToMigrate = 2 ether;
        bytes memory permitSig = _permit(
            MILADY_WETH_SLP,
            alice,
            address(migratorZap),
            liquidityToMigrate,
            DEADLINE,
            alicePrivateKey
        );
        address vTokenV3 = vaultFactory.vault(vaultIdV3);
        (int24 tickLower, int24 tickUpper, uint160 currentSqrtP) = _getTicks(
            vTokenV3,
            DEFAULT_FEE_TIER
        );

        uint256 preV2Balance = IERC20(MILADY_WETH_SLP).balanceOf(alice);

        hoax(alice);
        uint256 positionId = migratorZap.sushiToNFTXAMM(
            MigratorZap.SushiToNFTXAMMParams({
                sushiPair: MILADY_WETH_SLP,
                lpAmount: liquidityToMigrate,
                vTokenV2: V2_MILADY_VTOKEN,
                is1155: false,
                permitSig: permitSig,
                vaultIdV3: vaultIdV3,
                tickLower: tickLower,
                tickUpper: tickUpper,
                fee: DEFAULT_FEE_TIER,
                sqrtPriceX96: currentSqrtP,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        uint256 postV2Balance = IERC20(MILADY_WETH_SLP).balanceOf(alice);
        assertEq(preV2Balance - postV2Balance, liquidityToMigrate);

        assertEq(positionManager.ownerOf(positionId), alice);
    }

    function test_v2InventoryToXNFT_Success() external {
        uint256 vaultIdV2 = INFTXVaultV2(V2_MILADY_VTOKEN).vaultId();
        uint256 shares = IERC20(xMILADY).balanceOf(xMILADY_Holder);

        vm.startPrank(xMILADY_Holder);
        vm.warp(v2Inventory.timelockUntil(vaultIdV2, xMILADY_Holder) + 1);

        IERC20(xMILADY).approve(address(migratorZap), shares);
        uint256 xNFTId = migratorZap.v2InventoryToXNFT(
            vaultIdV2,
            shares,
            false, // is1155
            vaultIdV3,
            0
        );

        uint256 finalBalance = IERC20(xMILADY).balanceOf(xMILADY_Holder);
        assertEq(finalBalance, 0);

        assertEq(inventoryStaking.ownerOf(xNFTId), xMILADY_Holder);
    }

    function test_v2VaultToXNFT() external {
        uint256 amount = IERC20(V2_MILADY_VTOKEN).balanceOf(MILADY_Holder);

        startHoax(MILADY_Holder);

        IERC20(V2_MILADY_VTOKEN).approve(address(migratorZap), amount);
        uint256 xNFTId = migratorZap.v2VaultToXNFT(
            V2_MILADY_VTOKEN,
            amount,
            false, // is1155
            vaultIdV3,
            0
        );

        uint256 finalBalance = IERC20(V2_MILADY_VTOKEN).balanceOf(
            MILADY_Holder
        );
        assertEq(finalBalance, 0);

        assertEq(inventoryStaking.ownerOf(xNFTId), MILADY_Holder);
    }

    // =============================================================
    //                        INTERNAL HELPERS
    // =============================================================

    function _permit(
        address lpToken,
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint256 privateKey
    ) internal returns (bytes memory permitSig) {
        bytes32 digest = _getApprovalDigest(
            lpToken,
            owner,
            spender,
            amount,
            IUniswapV2Pair(lpToken).nonces(owner),
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        return bytes.concat(r, s, bytes1(v));
    }

    function _getApprovalDigest(
        address lpToken,
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal returns (bytes32) {
        bytes32 DOMAIN_SEPARATOR = _getDomainSeparator(
            lpToken,
            IUniswapV2Pair(lpToken).name(),
            "1",
            CHAIN_ID
        );
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        assertEq(DOMAIN_SEPARATOR, IUniswapV2Pair(lpToken).DOMAIN_SEPARATOR());
        assertEq(PERMIT_TYPEHASH, IUniswapV2Pair(lpToken).PERMIT_TYPEHASH());

        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            spender,
                            value,
                            nonce,
                            deadline
                        )
                    )
                )
            );
    }

    function _getDomainSeparator(
        address tokenAddress,
        string memory tokenName,
        string memory version,
        uint256 chainId
    ) internal pure returns (bytes32 DOMAIN_SEPARATOR) {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(tokenName)),
                keccak256(bytes(version)),
                chainId,
                tokenAddress
            )
        );
    }

    function _getTicks(
        address vToken,
        uint24 fee
    )
        internal
        view
        returns (int24 tickLower, int24 tickUpper, uint160 currentSqrtP)
    {
        uint256 currentNFTPrice = 5 ether;
        uint256 lowerNFTPrice = 3 ether;
        uint256 upperNFTPrice = 6 ether;

        uint256 tickDistance = _getTickDistance(fee);

        if (vToken < WETH) {
            currentSqrtP = TickHelpers.encodeSqrtRatioX96(
                currentNFTPrice,
                1 ether
            );
            // price = amount1 / amount0 = 1.0001^tick => tick ∝ price
            tickLower = TickHelpers.getTickForAmounts(
                lowerNFTPrice,
                1 ether,
                tickDistance
            );
            tickUpper = TickHelpers.getTickForAmounts(
                upperNFTPrice,
                1 ether,
                tickDistance
            );
        } else {
            currentSqrtP = TickHelpers.encodeSqrtRatioX96(
                1 ether,
                currentNFTPrice
            );
            tickLower = TickHelpers.getTickForAmounts(
                1 ether,
                upperNFTPrice,
                tickDistance
            );
            tickUpper = TickHelpers.getTickForAmounts(
                1 ether,
                lowerNFTPrice,
                tickDistance
            );
        }
    }
}
