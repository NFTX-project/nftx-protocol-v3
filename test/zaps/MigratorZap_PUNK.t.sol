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
import {NFTXVaultFactoryUpgradeableV3} from "@src/NFTXVaultFactoryUpgradeableV3.sol";

import {MigratorZap} from "@src/zaps/MigratorZap.sol";

import {TestBase} from "@test/TestBase.sol";

contract MigratorZapTests is TestBase {
    uint256 mainnetFork;
    uint256 constant BLOCK_NUMBER = 19846896;
    uint256 CHAIN_ID = 1;

    uint256 private constant DEADLINE =
        0xf000000000000000000000000000000000000000000000000000000000000000;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    INFTXVaultFactoryV2 v2NFTXFactory =
        INFTXVaultFactoryV2(0xBE86f647b167567525cCAAfcd6f881F1Ee558216);
    address constant PUNK_NFT = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;
    address constant V2_PUNK_VTOKEN =
        0x269616D549D7e8Eaa82DFb17028d0B212D11232A;
    address constant PUNK_WETH_SLP = 0x0463a06fBc8bF28b3F120cd1BfC59483F099d332;

    address constant PUNK_WETH_SLP_Holder =
        0xaA29881aAc939A025A3ab58024D7dd46200fB93D;

    INFTXInventoryStakingV2 v2Inventory =
        INFTXInventoryStakingV2(0x3E135c3E981fAe3383A5aE0d323860a34CfAB893);
    IUniswapV2Router02 sushiRouter =
        IUniswapV2Router02(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    uint256 alicePrivateKey = 42;
    address alice = vm.addr(alicePrivateKey);

    MigratorZap migratorZap;

    uint256 vaultIdV3;

    uint256 liquidityToMigrate = 11799774773440875243;

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

        // set address to the mainnet instance
        vaultFactory = NFTXVaultFactoryUpgradeableV3(
            0xC255335bc5aBd6928063F5788a5E420554858f01
        );

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
        vm.prank(vaultFactory.owner());
        vaultFactory.setFeeExclusion(address(migratorZap), true);

        // PUNK vault in v3
        vaultIdV3 = 0;

        vm.prank(PUNK_WETH_SLP_Holder);
        // tranfer SLP into our private-key controlled address
        IUniswapV2Pair(PUNK_WETH_SLP).transfer(alice, liquidityToMigrate);
    }

    function test_sushiToNFTXAMM_PUNK_Success() external {
        bytes memory permitSig = _permit(
            PUNK_WETH_SLP,
            alice,
            address(migratorZap),
            liquidityToMigrate,
            DEADLINE,
            alicePrivateKey
        );
        uint256 v3VaultId = vaultFactory.createVault({
            name: "CryptoPunks",
            symbol: "PUNK TEST",
            assetAddress: address(PUNK_NFT),
            is1155: false,
            allowAllItems: true
        });
        address vTokenV3 = vaultFactory.vault(v3VaultId);
        (int24 tickLower, int24 tickUpper, uint160 currentSqrtP) = _getTicks(
            vTokenV3,
            DEFAULT_FEE_TIER
        );

        uint256 preV2Balance = IERC20(PUNK_WETH_SLP).balanceOf(alice);

        hoax(alice);
        uint256 positionId = migratorZap.sushiToNFTXAMM(
            MigratorZap.SushiToNFTXAMMParams({
                sushiPair: PUNK_WETH_SLP,
                lpAmount: liquidityToMigrate,
                vTokenV2: V2_PUNK_VTOKEN,
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

        uint256 postV2Balance = IERC20(PUNK_WETH_SLP).balanceOf(alice);
        assertEq(preV2Balance - postV2Balance, liquidityToMigrate);

        assertEq(positionManager.ownerOf(positionId), alice);
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
