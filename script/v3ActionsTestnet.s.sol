// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {MockNFT} from "@mocks/MockNFT.sol";
import {INFTXVaultV3} from "@src/interfaces/INFTXVaultV3.sol";
import {INFTXVaultFactoryV3} from "@src/interfaces/INFTXVaultFactoryV3.sol";
import {INFTXInventoryStakingV3} from "@src/interfaces/INFTXInventoryStakingV3.sol";
import {INFTXRouter} from "@src/interfaces/INFTXRouter.sol";
import {UniswapV3FactoryUpgradeable} from "@uni-core/UniswapV3FactoryUpgradeable.sol";
import {MarketplaceUniversalRouterZap} from "@src/zaps/MarketplaceUniversalRouterZap.sol";
import {CreateVaultZap} from "@src/zaps/CreateVaultZap.sol";
import {QuoterV2, IQuoterV2} from "@uni-periphery/lens/QuoterV2.sol";

import {TickHelpers} from "@src/lib/TickHelpers.sol";

import {console} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

/// @notice Script to perform testnet transactions on NFTX V3
contract V3ActionsTestnet is Script {
    using stdJson for string;

    struct Deployment {
        address payable CreateVaultZap;
        address payable MarketplaceUniversalRouterZap;
        address NFTXFeeDistributorV3;
        address NFTXInventoryStakingV3Upgradeable;
        address NFTXRouter;
        address NFTXVaultFactoryUpgradeableV3;
        address NonfungiblePositionManager;
        address QuoterV2;
        address SwapRouter;
        address TickLens;
        address UniswapV3FactoryUpgradeable;
    }

    string root = vm.projectRoot();
    string path = string.concat(root, "/addresses.json");
    string json = vm.readFile(path);

    bytes deploymentDetails = json.parseRaw(".goerli");

    Deployment deployment = abi.decode(deploymentDetails, (Deployment));

    MockNFT nft = MockNFT(0x04B267e1aB612C078C05657f34e30E5b4Fb4b73B);
    INFTXVaultFactoryV3 vaultFactory =
        INFTXVaultFactoryV3(deployment.NFTXVaultFactoryUpgradeableV3);
    INFTXInventoryStakingV3 inventoryStaking =
        INFTXInventoryStakingV3(deployment.NFTXInventoryStakingV3Upgradeable);
    INFTXRouter nftxRouter = INFTXRouter(deployment.NFTXRouter);
    UniswapV3FactoryUpgradeable ammFactory =
        UniswapV3FactoryUpgradeable(deployment.UniswapV3FactoryUpgradeable);
    MarketplaceUniversalRouterZap marketplaceZap =
        MarketplaceUniversalRouterZap(deployment.MarketplaceUniversalRouterZap);
    CreateVaultZap createVaultZap = CreateVaultZap(deployment.CreateVaultZap);
    QuoterV2 quoter = QuoterV2(deployment.QuoterV2);

    // UniversalRouter commands
    uint256 constant V3_SWAP_EXACT_IN = 0x00;
    uint256 constant V3_SWAP_EXACT_OUT = 0x01;

    uint24 REWARD_FEE_TIER = 10_000;
    uint256 LOWER_NFT_PRICE_IN_ETH = 0.0003 ether;
    uint256 UPPER_NFT_PRICE_IN_ETH = 0.0005 ether;
    uint256 CURRENT_NFT_PRICE_IN_ETH = 0.0004 ether;

    uint256[] emptyArr;

    address weth;

    function run() external {
        vm.startBroadcast();

        weth = nftxRouter.WETH();

        (uint256 vaultIdA, INFTXVaultV3 vaultA) = _createVault();
        (uint256 vaultIdB, INFTXVaultV3 vaultB) = _createVaultViaZap();

        // new pools
        _addLiquidityWithNFTs(vaultIdA, vaultA, REWARD_FEE_TIER);
        _addLiquidityWithNFTs(vaultIdB, vaultB, 3_000);

        // existing pool
        _addLiquidityWithVTokens(vaultIdB, vaultB, REWARD_FEE_TIER);

        _updateMetadata(vaultA);
        _disableFees(vaultA);

        _updateVaultFeatures(vaultA, true, true, false);
        _updateVaultFeatures(vaultA, true, true, true);

        // _buyNFT(vaultIdB, vaultB, 1);
        // _buyNFT(vaultIdB, vaultB, 2);

        // _sellNFT(vaultIdB, vaultB, 2);

        vm.stopBroadcast();
    }

    function _createVault()
        internal
        returns (uint256 vaultId, INFTXVaultV3 vault)
    {
        vaultId = vaultFactory.createVault(
            "Bored Ape Vault",
            "BAYC",
            address(nft),
            false, // is1155
            true // allowAllItems
        );
        vault = INFTXVaultV3(vaultFactory.vault(vaultId));
    }

    function _createVaultViaZap()
        internal
        returns (uint256 vaultId, INFTXVaultV3 vault)
    {
        uint256 qty = 10;
        uint256[] memory tokenIds = nft.mint(qty);
        if (!nft.isApprovedForAll(msg.sender, address(createVaultZap))) {
            nft.setApprovalForAll(address(createVaultZap), true);
        }

        vaultId = createVaultZap.createVault{value: 0.1 ether}(
            CreateVaultZap.CreateVaultParams({
                vaultInfo: CreateVaultZap.VaultInfo({
                    assetAddress: address(nft),
                    is1155: false,
                    allowAllItems: true,
                    name: "Mutant Ape Vault",
                    symbol: "MAYC"
                }),
                eligibilityStorage: CreateVaultZap.VaultEligibilityStorage({
                    moduleIndex: 0,
                    initData: ""
                }),
                nftIds: tokenIds,
                nftAmounts: emptyArr,
                vaultFeaturesFlag: 7, // = 1,1,1
                vaultFees: CreateVaultZap.VaultFees({
                    mintFee: 0.01 ether,
                    redeemFee: 0.01 ether,
                    swapFee: 0.01 ether
                }),
                liquidityParams: CreateVaultZap.LiquidityParams({
                    lowerNFTPriceInETH: LOWER_NFT_PRICE_IN_ETH,
                    upperNFTPriceInETH: UPPER_NFT_PRICE_IN_ETH,
                    fee: REWARD_FEE_TIER,
                    currentNFTPriceInETH: CURRENT_NFT_PRICE_IN_ETH,
                    vTokenMin: 0,
                    wethMin: 0,
                    deadline: block.timestamp
                })
            })
        );
        vault = INFTXVaultV3(vaultFactory.vault(vaultId));
    }

    function _addLiquidityWithNFTs(
        uint256 vaultId,
        INFTXVaultV3 vault,
        uint24 fee
    ) internal {
        uint256 qty = 4;
        uint256[] memory tokenIds = nft.mint(qty);
        if (!nft.isApprovedForAll(msg.sender, address(nftxRouter))) {
            nft.setApprovalForAll(address(nftxRouter), true);
        }

        (
            int24 tickLower,
            int24 tickUpper,
            uint160 currentSqrtPriceX96
        ) = _getTicks(
                CURRENT_NFT_PRICE_IN_ETH,
                LOWER_NFT_PRICE_IN_ETH,
                UPPER_NFT_PRICE_IN_ETH,
                fee,
                nftxRouter.isVToken0(address(vault))
            );
        nftxRouter.addLiquidity{value: 0.1 ether}(
            INFTXRouter.AddLiquidityParams({
                vaultId: vaultId,
                vTokensAmount: 0,
                nftIds: tokenIds,
                nftAmounts: emptyArr,
                tickLower: tickLower,
                tickUpper: tickUpper,
                fee: fee,
                sqrtPriceX96: currentSqrtPriceX96,
                vTokenMin: 0,
                wethMin: 0,
                deadline: block.timestamp + 100 * 60, // 100 mins
                forceTimelock: false
            })
        );
    }

    function _addLiquidityWithVTokens(
        uint256 vaultId,
        INFTXVaultV3 vault,
        uint24 fee
    ) internal {
        (uint256 vTokensMinted, ) = _mintVTokens(vault, 4);
        _vTokenApprove(vault, address(nftxRouter), vTokensMinted);

        (
            int24 tickLower,
            int24 tickUpper,
            uint160 currentSqrtPriceX96
        ) = _getTicks(
                CURRENT_NFT_PRICE_IN_ETH,
                LOWER_NFT_PRICE_IN_ETH,
                UPPER_NFT_PRICE_IN_ETH,
                fee,
                nftxRouter.isVToken0(address(vault))
            );
        nftxRouter.addLiquidity{value: 0.1 ether}(
            INFTXRouter.AddLiquidityParams({
                vaultId: vaultId,
                vTokensAmount: vTokensMinted,
                nftIds: emptyArr,
                nftAmounts: emptyArr,
                tickLower: tickLower,
                tickUpper: tickUpper,
                fee: fee,
                sqrtPriceX96: currentSqrtPriceX96,
                vTokenMin: 0,
                wethMin: 0,
                deadline: block.timestamp + 100 * 60, // 100 mins
                forceTimelock: false
            })
        );
    }

    function _updateMetadata(INFTXVaultV3 vault) internal {
        vault.setVaultMetadata("Milady", "MILADY");
    }

    function _disableFees(INFTXVaultV3 vault) internal {
        vault.disableVaultFees();
    }

    function _updateVaultFeatures(
        INFTXVaultV3 vault,
        bool enableMint_,
        bool enableRedeem_,
        bool enableSwap_
    ) internal {
        vault.setVaultFeatures(enableMint_, enableRedeem_, enableSwap_);
    }

    function _buyNFT(
        uint256 vaultId,
        INFTXVaultV3 vault,
        uint256 qtyOut
    ) internal {
        // deposit new NFTs to buy back with premium
        (, uint256[] memory idsOut) = _mintVTokens(vault, qtyOut);

        (, uint256 redeemFee, ) = vault.vaultFees();
        uint256 vTokenPremium;
        for (uint256 i; i < qtyOut; ++i) {
            (uint256 premium, ) = vault.getVTokenPremium721(idsOut[i]);
            vTokenPremium += premium;
        }
        uint256 netVaultFeesInETH = vault.vTokenToETH(
            redeemFee * qtyOut + vTokenPremium
        );

        (uint256 wethRequired, , , ) = quoter.quoteExactOutputSingle(
            IQuoterV2.QuoteExactOutputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(vault),
                amount: qtyOut * 1 ether,
                fee: REWARD_FEE_TIER,
                sqrtPriceLimitX96: 0
            })
        );
        bytes memory commands = hex"01"; // V3_SWAP_EXACT_OUT
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            // recipient
            address(marketplaceZap),
            // amountOut
            qtyOut * 1 ether,
            // amountInMax
            type(uint256).max,
            // pathBytes:
            abi.encodePacked(
                // tokenIn
                address(weth),
                REWARD_FEE_TIER,
                // tokenOut
                address(vault)
            ),
            true // payerIsUser
        );
        bytes memory executeCallData = abi.encodeWithSignature(
            "execute(bytes,bytes[],uint256)",
            commands,
            inputs,
            block.timestamp + 100 * 60 // deadline = 100 mins
        );

        marketplaceZap.buyNFTsWithETH{value: netVaultFeesInETH + wethRequired}(
            vaultId,
            idsOut,
            executeCallData,
            payable(msg.sender),
            true // deduct royalty
        );
    }

    function _sellNFT(
        uint256 vaultId,
        INFTXVaultV3 vault,
        uint256 qtyIn
    ) internal {
        // mint nfts to sell
        uint256[] memory idsIn = nft.mint(qtyIn);

        bytes memory commands = hex"00"; // V3_SWAP_EXACT_IN
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            // recipient
            address(marketplaceZap),
            // amountIn
            qtyIn * 1 ether,
            // amountOutMin
            0,
            // pathBytes:
            abi.encodePacked(
                // tokenIn
                address(vault),
                REWARD_FEE_TIER,
                // tokenOut
                address(weth)
            ),
            true // payerIsUser
        );
        bytes memory executeCallData = abi.encodeWithSignature(
            "execute(bytes,bytes[],uint256)",
            commands,
            inputs,
            block.timestamp + 100 * 60 // deadline = 100 mins
        );

        _nftApprove(address(marketplaceZap));
        marketplaceZap.sell721(
            vaultId,
            idsIn,
            executeCallData,
            payable(msg.sender),
            true // deduct royalty
        );
    }

    // helpers

    function _getTicks(
        uint256 currentNFTPriceInETH,
        uint256 lowerNFTPriceInETH,
        uint256 upperNFTPriceInETH,
        uint24 fee,
        bool isVToken0
    )
        internal
        view
        returns (int24 tickLower, int24 tickUpper, uint160 currentSqrtPriceX96)
    {
        uint256 tickDistance = uint24(ammFactory.feeAmountTickSpacing(fee));
        if (isVToken0) {
            currentSqrtPriceX96 = TickHelpers.encodeSqrtRatioX96(
                currentNFTPriceInETH,
                1 ether
            );
            // price = amount1 / amount0 = 1.0001^tick => tick ∝ price
            tickLower = TickHelpers.getTickForAmounts(
                lowerNFTPriceInETH,
                1 ether,
                tickDistance
            );
            tickUpper = TickHelpers.getTickForAmounts(
                upperNFTPriceInETH,
                1 ether,
                tickDistance
            );
        } else {
            currentSqrtPriceX96 = TickHelpers.encodeSqrtRatioX96(
                1 ether,
                currentNFTPriceInETH
            );
            tickLower = TickHelpers.getTickForAmounts(
                1 ether,
                upperNFTPriceInETH,
                tickDistance
            );
            tickUpper = TickHelpers.getTickForAmounts(
                1 ether,
                lowerNFTPriceInETH,
                tickDistance
            );
        }
    }

    function _nftApprove(address spender) internal {
        if (!nft.isApprovedForAll(msg.sender, spender)) {
            nft.setApprovalForAll(spender, true);
        }
    }

    function _vTokenApprove(
        INFTXVaultV3 vault,
        address spender,
        uint256 amount
    ) internal {
        if (vault.allowance(msg.sender, spender) < amount) {
            vault.approve(spender, type(uint256).max);
        }
    }

    function _mintVTokens(
        INFTXVaultV3 vault,
        uint256 qty
    ) internal returns (uint256 vTokensMinted, uint256[] memory tokenIds) {
        tokenIds = nft.mint(qty);

        (uint256 mintFee, , ) = vault.vaultFees();
        uint256 ethToPay = vault.vTokenToETH(mintFee);

        _nftApprove(address(vault));

        vTokensMinted = vault.mint{value: ethToPay}(
            tokenIds,
            emptyArr,
            msg.sender,
            msg.sender
        );
    }
}
