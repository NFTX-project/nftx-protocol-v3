// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";
import {TickHelpers} from "@src/lib/TickHelpers.sol";
import {TestExtend} from "@test/lib/TestExtend.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {UniswapV3FactoryUpgradeable} from "@uni-core/UniswapV3FactoryUpgradeable.sol";
import {UniswapV3PoolUpgradeable} from "@uni-core/UniswapV3PoolUpgradeable.sol";
import {NonfungibleTokenPositionDescriptor} from "@uni-periphery/NonfungibleTokenPositionDescriptor.sol";
import {NonfungiblePositionManager, INonfungiblePositionManager} from "@uni-periphery/NonfungiblePositionManager.sol";
import {SwapRouter} from "@uni-periphery/SwapRouter.sol";
import {QuoterV2} from "@uni-periphery/lens/QuoterV2.sol";
import {TickMath} from "@uni-core/libraries/TickMath.sol";
import {FullMath} from "@uni-core/libraries/FullMath.sol";
import {FixedPoint128} from "@uni-core/libraries/FixedPoint128.sol";
import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";

import {MockWETH} from "@mocks/MockWETH.sol";
import {MockNFT} from "@mocks/MockNFT.sol";
import {Mock1155} from "@mocks/Mock1155.sol";
import {MockUniversalRouter} from "@mocks/MockUniversalRouter.sol";
import {MockPermit2} from "@mocks/permit2/MockPermit2.sol";
import {MockDelegateRegistry} from "@mocks/MockDelegateRegistry.sol";

import {NFTXVaultUpgradeableV3, INFTXVaultV3} from "@src/NFTXVaultUpgradeableV3.sol";
import {NFTXVaultFactoryUpgradeableV3} from "@src/NFTXVaultFactoryUpgradeableV3.sol";
import {NFTXEligibilityManager} from "@src/v2/NFTXEligibilityManager.sol";
import {NFTXListEligibility} from "@src/v2/eligibility/NFTXListEligibility.sol";
import {NFTXRangeEligibility} from "@src/v2/eligibility/NFTXRangeEligibility.sol";
import {NFTXGen0KittyEligibility} from "@src/v2/eligibility/NFTXGen0KittyEligibility.sol";
import {NFTXENSMerkleEligibility} from "@src/v2/eligibility/NFTXENSMerkleEligibility.sol";
import {InventoryStakingDescriptor} from "@src/custom/InventoryStakingDescriptor.sol";
import {NFTXInventoryStakingV3Upgradeable} from "@src/NFTXInventoryStakingV3Upgradeable.sol";
import {NFTXFeeDistributorV3} from "@src/NFTXFeeDistributorV3.sol";
import {TimelockExcludeList} from "@src/TimelockExcludeList.sol";
import {ITimelockExcludeList} from "@src/interfaces/ITimelockExcludeList.sol";
import {NFTXRouter, INFTXRouter} from "@src/NFTXRouter.sol";
import {MarketplaceUniversalRouterZap} from "@src/zaps/MarketplaceUniversalRouterZap.sol";
import {IPermitAllowanceTransfer} from "@src/interfaces/external/IPermitAllowanceTransfer.sol";
import {IDelegateRegistry} from "@src/interfaces/IDelegateRegistry.sol";

contract TestBase is TestExtend, ERC721Holder, ERC1155Holder {
    UniswapV3FactoryUpgradeable factory;
    NonfungibleTokenPositionDescriptor descriptor;
    MockWETH weth;
    NonfungiblePositionManager positionManager;
    SwapRouter router;
    QuoterV2 quoter;

    MockNFT nft;
    Mock1155 nft1155;
    MockUniversalRouter universalRouter;
    MockPermit2 permit2;

    NFTXVaultUpgradeableV3 vtoken;
    INFTXVaultV3 vtoken1155;
    TimelockExcludeList timelockExcludeList;
    NFTXFeeDistributorV3 feeDistributor;
    NFTXVaultUpgradeableV3 vaultImpl;
    NFTXVaultFactoryUpgradeableV3 vaultFactory;
    NFTXEligibilityManager eligibilityManager;
    NFTXRouter nftxRouter;
    InventoryStakingDescriptor inventoryDescriptor;
    NFTXInventoryStakingV3Upgradeable inventoryStaking;
    MarketplaceUniversalRouterZap marketplaceZap;

    uint24 constant DEFAULT_FEE_TIER = 10000;
    address immutable TREASURY = makeAddr("TREASURY");
    uint256 constant VAULT_ID = 0;
    uint256 constant VAULT_ID_1155 = 1;
    uint256 constant LP_TIMELOCK = 2 days;
    uint256 constant RANGE_MODULE_INDEX = 1; // eligibility manager

    uint16 constant REWARD_TIER_CARDINALITY = 102; // considering 20 min interval with 1 block every 12 seconds on ETH Mainnet

    uint256 fromPrivateKey = 0x12341234;
    address from = vm.addr(fromPrivateKey);

    uint256[] emptyIds;
    uint256[] emptyAmounts;
    uint256 constant MAX_VTOKEN_PREMIUM_LIMIT = type(uint256).max;

    IDelegateRegistry constant DELEGATE_REGISTRY =
        IDelegateRegistry(0x00000000000000447e69651d841bD8D104Bed493);

    function setUp() public virtual {
        // to prevent underflow during calculations involving block.timestamp
        vm.warp(100 days);

        MockDelegateRegistry delegateRegistry = new MockDelegateRegistry();
        vm.etch(address(DELEGATE_REGISTRY), address(delegateRegistry).code);

        weth = new MockWETH();

        UniswapV3PoolUpgradeable poolImpl = new UniswapV3PoolUpgradeable();

        factory = new UniswapV3FactoryUpgradeable();
        factory.__UniswapV3FactoryUpgradeable_init({
            beaconImplementation_: address(poolImpl),
            rewardTierCardinality_: REWARD_TIER_CARDINALITY
        });
        descriptor = new NonfungibleTokenPositionDescriptor({
            _WETH9: address(weth),
            _nativeCurrencyLabelBytes: 0x5745544800000000000000000000000000000000000000000000000000000000 // "WETH"
        });

        positionManager = new NonfungiblePositionManager(
            address(factory),
            address(weth),
            address(descriptor)
        );
        router = new SwapRouter(address(factory), address(weth));
        quoter = new QuoterV2(address(factory), address(weth));

        nft = new MockNFT();
        nft1155 = new Mock1155();

        vaultImpl = new NFTXVaultUpgradeableV3(IWETH9(address(weth)));
        vaultFactory = new NFTXVaultFactoryUpgradeableV3();
        vaultFactory.__NFTXVaultFactory_init({
            vaultImpl: address(vaultImpl),
            twapInterval_: 20 minutes,
            premiumDuration_: 10 hours,
            premiumMax_: 5 ether,
            depositorPremiumShare_: 0.30 ether
        });
        eligibilityManager = new NFTXEligibilityManager();
        eligibilityManager.__NFTXEligibilityManager_init();
        vaultFactory.setEligibilityManager(address(eligibilityManager));
        eligibilityManager.addModule(address(new NFTXListEligibility()));
        eligibilityManager.addModule(address(new NFTXRangeEligibility()));
        eligibilityManager.addModule(address(new NFTXGen0KittyEligibility()));
        eligibilityManager.addModule(address(new NFTXENSMerkleEligibility()));

        permit2 = new MockPermit2();

        timelockExcludeList = new TimelockExcludeList();
        inventoryDescriptor = new InventoryStakingDescriptor();
        inventoryStaking = new NFTXInventoryStakingV3Upgradeable(
            IWETH9(address(weth)),
            IPermitAllowanceTransfer(address(permit2)),
            vaultFactory
        );
        inventoryStaking.__NFTXInventoryStaking_init({
            timelock_: 2 days,
            earlyWithdrawPenaltyInWei_: 0.05 ether, // 5%
            timelockExcludeList_: ITimelockExcludeList(
                address(timelockExcludeList)
            ),
            descriptor_: inventoryDescriptor
        });
        vaultFactory.setFeeExclusion(address(inventoryStaking), true);
        inventoryStaking.setIsGuardian(address(this), true);

        nftxRouter = new NFTXRouter({
            positionManager_: positionManager,
            router_: router,
            quoter_: quoter,
            nftxVaultFactory_: vaultFactory,
            PERMIT2_: IPermitAllowanceTransfer(address(permit2)),
            lpTimelock_: LP_TIMELOCK,
            earlyWithdrawPenaltyInWei_: 0.05 ether, // 5%
            vTokenDustThreshold_: 0.05 ether,
            inventoryStaking_: inventoryStaking
        });
        vaultFactory.setFeeExclusion(address(nftxRouter), true);
        positionManager.setTimelockExcluded(address(nftxRouter), true);

        feeDistributor = new NFTXFeeDistributorV3(
            vaultFactory,
            factory,
            inventoryStaking,
            nftxRouter,
            TREASURY,
            DEFAULT_FEE_TIER
        );

        factory.setFeeDistributor(address(feeDistributor));
        vaultFactory.setFeeDistributor(address(feeDistributor));

        uint256 vaultId = vaultFactory.createVault({
            name: "TEST",
            symbol: "TST",
            assetAddress: address(nft),
            is1155: false,
            allowAllItems: true
        });
        vtoken = NFTXVaultUpgradeableV3(vaultFactory.vault(vaultId));
        vaultFactory.createVault({
            name: "TEST1155",
            symbol: "TST1155",
            assetAddress: address(nft1155),
            is1155: true,
            allowAllItems: true
        });
        vtoken1155 = INFTXVaultV3(vaultFactory.vault(vaultId + 1));

        // Zaps
        universalRouter = new MockUniversalRouter(
            IPermitAllowanceTransfer(address(permit2)),
            router
        );
        marketplaceZap = new MarketplaceUniversalRouterZap(
            vaultFactory,
            address(universalRouter),
            IPermitAllowanceTransfer(address(permit2)),
            address(inventoryStaking),
            IWETH9(address(weth))
        );
        vaultFactory.setFeeExclusion(address(marketplaceZap), true);
    }

    function _mintVToken(
        uint256 qty,
        address depositor,
        address receiver
    ) internal returns (uint256 mintedVTokens, uint256[] memory tokenIds) {
        tokenIds = nft.mint(qty);

        nft.setApprovalForAll(address(vtoken), true);
        uint256[] memory amounts = new uint256[](0);
        mintedVTokens = vtoken.mint{value: 100 ether * qty}(
            tokenIds,
            amounts,
            depositor,
            receiver
        );
    }

    function _mintVToken(
        uint256 qty
    ) internal returns (uint256 mintedVTokens, uint256[] memory tokenIds) {
        return
            _mintVToken({
                qty: qty,
                depositor: address(this),
                receiver: address(this)
            });
    }

    function _mintPosition(
        uint256 qty
    )
        internal
        returns (
            uint256[] memory tokenIds,
            uint256 positionId,
            int24 tickLower,
            int24 tickUpper,
            uint256 ethUsed
        )
    {
        // Current Eg: 1 NFT = 5 ETH, and liquidity provided in the range: 3-6 ETH per NFT
        uint256 currentNFTPrice = 5 ether; // 5 * 10^18 wei for 1*10^18 vTokens
        uint256 lowerNFTPrice = 3 ether;
        uint256 upperNFTPrice = 6 ether;

        uint24 fee = DEFAULT_FEE_TIER;

        return
            _mintPosition(
                qty,
                currentNFTPrice,
                lowerNFTPrice,
                upperNFTPrice,
                fee
            );
    }

    function _mintPosition(
        uint256 qty,
        uint256 currentNFTPrice,
        uint256 lowerNFTPrice,
        uint256 upperNFTPrice,
        uint24 fee
    )
        internal
        returns (
            uint256[] memory tokenIds,
            uint256 positionId,
            int24 tickLower,
            int24 tickUpper,
            uint256 ethUsed
        )
    {
        tokenIds = nft.mint(qty);
        nft.setApprovalForAll(address(nftxRouter), true);

        uint160 currentSqrtP;
        uint256 tickDistance = _getTickDistance(fee);
        if (nftxRouter.isVToken0(address(vtoken))) {
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

        uint256 preETHBalance = address(this).balance;

        positionId = nftxRouter.addLiquidity{value: qty * 100 ether}(
            INFTXRouter.AddLiquidityParams({
                vaultId: VAULT_ID,
                vTokensAmount: 0,
                nftIds: tokenIds,
                nftAmounts: emptyIds,
                tickLower: tickLower,
                tickUpper: tickUpper,
                fee: fee,
                sqrtPriceX96: currentSqrtP,
                vTokenMin: 0,
                wethMin: 0,
                deadline: block.timestamp,
                forceTimelock: false,
                recipient: address(this)
            })
        );

        ethUsed = preETHBalance - address(this).balance;
    }

    function _mintPositionWithTwap(
        uint256 currentNFTPrice
    ) internal returns (uint256 positionId) {
        (, positionId, , , ) = _mintPosition({
            qty: 10,
            currentNFTPrice: currentNFTPrice,
            lowerNFTPrice: currentNFTPrice - 0.5 ether,
            upperNFTPrice: currentNFTPrice + 0.5 ether,
            fee: DEFAULT_FEE_TIER
        });
        vm.warp(block.timestamp + vaultFactory.twapInterval());
    }

    function _sellNFTs(
        uint256 qty
    ) internal returns (uint256[] memory tokenIds) {
        tokenIds = nft.mint(qty);
        nft.setApprovalForAll(address(nftxRouter), true);

        uint256 preNFTBalance = nft.balanceOf(address(this));

        nftxRouter.sellNFTs(
            INFTXRouter.SellNFTsParams({
                vaultId: VAULT_ID,
                nftIds: tokenIds,
                nftAmounts: emptyIds,
                deadline: block.timestamp,
                fee: DEFAULT_FEE_TIER,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 postNFTBalance = nft.balanceOf(address(this));
        assertEq(
            preNFTBalance - postNFTBalance,
            qty,
            "NFT balance didn't decrease"
        );
    }

    function _mintVTokenFor1155(
        uint256 qty,
        address depositor,
        address receiver
    ) internal returns (uint256 mintedVTokens, uint256[] memory tokenIds) {
        uint256[] memory _tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        _tokenIds[0] = nft1155.mint(qty);
        amounts[0] = qty;

        nft1155.setApprovalForAll(address(vtoken1155), true);

        mintedVTokens = vtoken1155.mint{value: 100 ether * qty}(
            _tokenIds,
            amounts,
            depositor,
            receiver
        );

        tokenIds = new uint256[](qty);
        for (uint256 i; i < qty; i++) {
            tokenIds[i] = _tokenIds[0];
        }
    }

    function _mintVTokenFor1155(
        uint256 qty
    ) internal returns (uint256 mintedVTokens, uint256[] memory tokenIds) {
        return
            _mintVTokenFor1155({
                qty: qty,
                depositor: address(this),
                receiver: address(this)
            });
    }

    function _mintPosition1155(
        uint256 qty
    )
        internal
        returns (
            uint256[] memory tokenIds,
            uint256 positionId,
            int24 tickLower,
            int24 tickUpper,
            uint256 ethUsed
        )
    {
        // Current Eg: 1 NFT = 5 ETH, and liquidity provided in the range: 3-6 ETH per NFT
        uint256 currentNFTPrice = 5 ether; // 5 * 10^18 wei for 1*10^18 vTokens
        uint256 lowerNFTPrice = 3 ether;
        uint256 upperNFTPrice = 6 ether;

        uint24 fee = DEFAULT_FEE_TIER;

        return
            _mintPosition1155(
                qty,
                currentNFTPrice,
                lowerNFTPrice,
                upperNFTPrice,
                fee
            );
    }

    function _mintPosition1155(
        uint256 qty,
        uint256 currentNFTPrice,
        uint256 lowerNFTPrice,
        uint256 upperNFTPrice,
        uint24 fee
    )
        internal
        returns (
            uint256[] memory tokenIds,
            uint256 positionId,
            int24 tickLower,
            int24 tickUpper,
            uint256 ethUsed
        )
    {
        tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        tokenIds[0] = nft1155.mint(qty);
        amounts[0] = qty;

        nft1155.setApprovalForAll(address(nftxRouter), true);

        uint160 currentSqrtP;
        uint256 tickDistance = _getTickDistance(fee);
        if (nftxRouter.isVToken0(address(vtoken1155))) {
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

        uint256 preETHBalance = address(this).balance;

        positionId = nftxRouter.addLiquidity{value: qty * 100 ether}(
            INFTXRouter.AddLiquidityParams({
                vaultId: VAULT_ID_1155,
                vTokensAmount: 0,
                nftIds: tokenIds,
                nftAmounts: amounts,
                tickLower: tickLower,
                tickUpper: tickUpper,
                fee: fee,
                sqrtPriceX96: currentSqrtP,
                vTokenMin: 0,
                wethMin: 0,
                deadline: block.timestamp,
                forceTimelock: false,
                recipient: address(this)
            })
        );

        ethUsed = preETHBalance - address(this).balance;
    }

    function _mintPositionWithTwap1155(
        uint256 currentNFTPrice
    ) internal returns (uint256 positionId) {
        (, positionId, , , ) = _mintPosition1155(
            10,
            currentNFTPrice,
            currentNFTPrice - 0.5 ether,
            currentNFTPrice + 0.5 ether,
            DEFAULT_FEE_TIER
        );
        vm.warp(block.timestamp + vaultFactory.twapInterval());
    }

    function _sellNFTs1155(
        uint256 qty
    ) internal returns (uint256[] memory tokenIds) {
        tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        tokenIds[0] = nft1155.mint(qty);
        amounts[0] = qty;

        nft1155.setApprovalForAll(address(nftxRouter), true);

        uint256 preNFTBalance = nft1155.balanceOf(address(this), tokenIds[0]);

        nftxRouter.sellNFTs(
            INFTXRouter.SellNFTsParams({
                vaultId: VAULT_ID_1155,
                nftIds: tokenIds,
                nftAmounts: amounts,
                deadline: block.timestamp,
                fee: DEFAULT_FEE_TIER,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 postNFTBalance = nft1155.balanceOf(address(this), tokenIds[0]);
        assertEq(
            preNFTBalance - postNFTBalance,
            qty,
            "NFT balance didn't decrease"
        );
    }

    function _calcExpectedMintETHFees(
        uint256 qty,
        uint256 currentNFTPrice
    ) internal view returns (uint256 expectedETHPaid) {
        (uint256 mintFee, , ) = vtoken.vaultFees();

        uint256 exactETHPaid = (mintFee * qty * currentNFTPrice) / 1 ether;

        expectedETHPaid = _valueWithError(exactETHPaid);
    }

    function _twap721AndCalcMintETHFees(
        uint256 qty,
        uint256 currentNFTPrice
    ) internal returns (uint256 exactETHPaid, uint256 expectedETHPaid) {
        _mintPositionWithTwap(currentNFTPrice);

        (uint256 mintFee, , ) = vtoken.vaultFees();

        // exactETHPaid = (mintFee * qty * currentNFTPrice) / 1 ether;
        exactETHPaid = vtoken.vTokenToETH(mintFee * qty);
        expectedETHPaid = _valueWithError(exactETHPaid);
    }

    function _twap1155AndCalcMintETHFees(
        uint256 qty,
        uint256 currentNFTPrice
    ) internal returns (uint256 exactETHPaid, uint256 expectedETHPaid) {
        _mintPositionWithTwap1155(currentNFTPrice);

        (uint256 mintFee, , ) = vtoken1155.vaultFees();

        // exactETHPaid = (mintFee * qty * currentNFTPrice) / 1 ether;
        exactETHPaid = vtoken1155.vTokenToETH(mintFee * qty);
        expectedETHPaid = _valueWithError(exactETHPaid);
    }

    function _twap721AndCalcRedeemETHFees(
        uint256 qty,
        uint256 currentNFTPrice
    )
        internal
        returns (
            uint256[] memory idsOut,
            uint256 exactETHPaid,
            uint256 expectedETHPaid
        )
    {
        _mintPositionWithTwap(currentNFTPrice);
        (, idsOut) = _mintVToken(qty);

        (, uint256 redeemFee, ) = vtoken.vaultFees();

        exactETHPaid = vtoken.vTokenToETH(redeemFee * qty);
        expectedETHPaid = _valueWithError(exactETHPaid);

        // jump to time such that no premium applicable
        vm.warp(block.timestamp + vaultFactory.premiumDuration() + 1);
    }

    function _twap1155AndCalcRedeemETHFees(
        uint256 qty,
        uint256 currentNFTPrice
    )
        internal
        returns (
            uint256[] memory idsOut,
            uint256 exactETHPaid,
            uint256 expectedETHPaid
        )
    {
        _mintPositionWithTwap1155(currentNFTPrice);
        (, idsOut) = _mintVTokenFor1155(qty);

        (, uint256 redeemFee, ) = vtoken1155.vaultFees();
        exactETHPaid = vtoken1155.vTokenToETH(redeemFee * qty);
        expectedETHPaid = _valueWithError(exactETHPaid);

        // jump to time such that no premium applicable
        vm.warp(block.timestamp + vaultFactory.premiumDuration() + 1);
    }

    function _twap721AndCalcRedeemETHFeesWithPremium(
        uint256 qty,
        uint256 currentNFTPrice
    )
        internal
        returns (
            address depositor,
            uint256[] memory idsOut,
            uint256 exactETHPaid,
            uint256 expectedETHPaid,
            uint256 expectedDepositorShare
        )
    {
        _mintPositionWithTwap(currentNFTPrice);

        // have a separate depositor address that receives share of premium
        depositor = makeAddr("depositor");
        startHoax(depositor);

        uint256 mintedVTokens;
        (mintedVTokens, idsOut) = _mintVToken({
            qty: qty,
            depositor: depositor,
            receiver: depositor
        });
        vtoken.transfer(address(this), mintedVTokens);
        vm.stopPrank();

        (, uint256 redeemFee, ) = vtoken.vaultFees();

        exactETHPaid = vtoken.vTokenToETH(
            (redeemFee + vaultFactory.premiumMax()) * qty
        );
        expectedETHPaid = _valueWithError(exactETHPaid);

        expectedDepositorShare =
            (exactETHPaid * vaultFactory.depositorPremiumShare()) /
            1 ether;
    }

    function _twap1155AndCalcRedeemETHFeesWithPremium(
        uint256 qty,
        uint256 currentNFTPrice
    )
        internal
        returns (
            address depositor,
            uint256[] memory idsOut,
            uint256 exactETHPaid,
            uint256 expectedETHPaid,
            uint256 expectedDepositorShare
        )
    {
        _mintPositionWithTwap1155(currentNFTPrice);

        // have a separate depositor address that receives share of premium
        depositor = makeAddr("depositor");
        startHoax(depositor);

        (uint256 mintedVTokens, uint256[] memory idsIn) = _mintVTokenFor1155({
            qty: qty,
            depositor: depositor,
            receiver: depositor
        });
        vtoken1155.transfer(address(this), mintedVTokens);
        vm.stopPrank();

        // decreasing idsOut length for withdrawal so that same pointerIndex remains
        qty -= 1;
        idsOut = new uint256[](qty);
        for (uint256 i; i < qty; i++) {
            idsOut[i] = idsIn[i];
        }

        (, uint256 redeemFee, ) = vtoken1155.vaultFees();

        exactETHPaid = vtoken1155.vTokenToETH(
            (redeemFee + vaultFactory.premiumMax()) * qty
        );
        expectedETHPaid = _valueWithError(exactETHPaid);

        expectedDepositorShare =
            (exactETHPaid * vaultFactory.depositorPremiumShare()) /
            1 ether;
    }

    function _twap721AndCalcSwapETHFees(
        uint256 qty,
        uint256 currentNFTPrice
    )
        internal
        returns (
            uint256[] memory idsOut,
            uint256[] memory idsIn,
            uint256 exactETHPaid,
            uint256 expectedETHPaid
        )
    {
        _mintPositionWithTwap(currentNFTPrice);
        (, idsOut) = _mintVToken(qty);

        (, , uint256 swapFee) = vtoken.vaultFees();

        exactETHPaid = vtoken.vTokenToETH(swapFee * qty);
        expectedETHPaid = _valueWithError(exactETHPaid);

        // jump to time such that no premium applicable
        vm.warp(block.timestamp + vaultFactory.premiumDuration() + 1);

        idsIn = nft.mint(qty);
    }

    function _twap1155AndCalcSwapETHFees(
        uint256 qty,
        uint256 currentNFTPrice
    )
        internal
        returns (
            uint256[] memory idsOut,
            uint256[] memory idsIn,
            uint256[] memory amountsIn,
            uint256 exactETHPaid,
            uint256 expectedETHPaid
        )
    {
        _mintPositionWithTwap1155(currentNFTPrice);
        (, idsOut) = _mintVTokenFor1155(qty);

        (, , uint256 swapFee) = vtoken1155.vaultFees();

        exactETHPaid = vtoken1155.vTokenToETH(swapFee * qty);
        expectedETHPaid = _valueWithError(exactETHPaid);

        // jump to time such that no premium applicable
        vm.warp(block.timestamp + vaultFactory.premiumDuration() + 1);

        idsIn = new uint256[](1);
        amountsIn = new uint256[](1);

        idsIn[0] = nft1155.mint(qty);
        amountsIn[0] = qty;
    }

    function _twap721AndCalcSwapETHFeesWithPremium(
        uint256 qty,
        uint256 currentNFTPrice
    )
        internal
        returns (
            address depositor,
            uint256[] memory idsOut,
            uint256[] memory idsIn,
            uint256 exactETHPaid,
            uint256 expectedETHPaid,
            uint256 expectedDepositorShare
        )
    {
        _mintPositionWithTwap(currentNFTPrice);
        // have a separate depositor address that receives share of premium
        depositor = makeAddr("depositor");
        startHoax(depositor);
        (, idsOut) = _mintVToken({
            qty: qty,
            depositor: depositor,
            receiver: depositor
        });
        vm.stopPrank();

        (, , uint256 swapFee) = vtoken.vaultFees();

        exactETHPaid = vtoken.vTokenToETH(
            (swapFee + vaultFactory.premiumMax()) * qty
        );
        expectedETHPaid = _valueWithError(exactETHPaid);

        expectedDepositorShare =
            (exactETHPaid * vaultFactory.depositorPremiumShare()) /
            1 ether;

        idsIn = nft.mint(qty);
    }

    function _twap1155AndCalcSwapETHFeesWithPremium(
        uint256 qty,
        uint256 currentNFTPrice
    )
        internal
        returns (
            address depositor,
            uint256[] memory idsOut,
            uint256[] memory idsIn,
            uint256[] memory amountsIn,
            uint256 exactETHPaid,
            uint256 expectedETHPaid,
            uint256 expectedDepositorShare
        )
    {
        _mintPositionWithTwap1155(currentNFTPrice);
        // have a separate depositor address that receives share of premium
        depositor = makeAddr("depositor");
        startHoax(depositor);
        (, idsOut) = _mintVTokenFor1155({
            qty: qty,
            depositor: depositor,
            receiver: depositor
        });
        vm.stopPrank();

        (, , uint256 swapFee) = vtoken1155.vaultFees();

        exactETHPaid = vtoken1155.vTokenToETH(
            (swapFee + vaultFactory.premiumMax()) * qty
        );
        expectedETHPaid = _valueWithError(exactETHPaid);

        expectedDepositorShare =
            (exactETHPaid * vaultFactory.depositorPremiumShare()) /
            1 ether;

        idsIn = new uint256[](1);
        amountsIn = new uint256[](1);

        idsIn[0] = nft1155.mint(qty);
        amountsIn[0] = qty;
    }

    // the actual value can be off by few decimals so accounting for 0.3% error.
    function _valueWithError(uint256 value) internal pure returns (uint256) {
        return (value * (10_000 - 30)) / 10_000;
    }

    function _getTickDistance(
        uint24 fee
    ) internal view returns (uint256 tickDistance) {
        tickDistance = uint256(uint24(factory.feeAmountTickSpacing(fee)));
    }

    function _getLiquidity(
        uint256 positionId
    ) internal view returns (uint128 liquidity) {
        (, , , , , , , liquidity, , , , ) = positionManager.positions(
            positionId
        );
    }

    function _getTicks(
        uint256 positionId
    ) internal view returns (int24 tickLower, int24 tickUpper) {
        (, , , , , tickLower, tickUpper, , , , , ) = positionManager.positions(
            positionId
        );
    }

    function _getAccumulatedFees(
        uint256 positionId
    ) internal returns (uint256 vTokenFees, uint256 wethFees) {
        // "simulating" call here. Similar to "callStatic" in ethers.js for executing non-view function to just get return values.
        uint256 snapshot = vm.snapshot();
        (uint256 amount0, uint256 amount1) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: positionId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        vm.revertTo(snapshot);

        (vTokenFees, wethFees) = nftxRouter.isVToken0(address(vtoken))
            ? (amount0, amount1)
            : (amount1, amount0);
    }

    function _getPermitSignature(
        IPermitAllowanceTransfer.PermitSingle memory permit,
        uint256 privateKey
    ) internal view returns (bytes memory sig) {
        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignatureRaw(
            permit,
            privateKey,
            permit2.DOMAIN_SEPARATOR()
        );
        return bytes.concat(r, s, bytes1(v));
    }

    bytes32 public constant _PERMIT_DETAILS_TYPEHASH =
        keccak256(
            "PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
        );
    bytes32 public constant _PERMIT_SINGLE_TYPEHASH =
        keccak256(
            "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
        );

    function _getPermitSignatureRaw(
        IPermitAllowanceTransfer.PermitSingle memory permit,
        uint256 privateKey,
        bytes32 domainSeparator
    ) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 permitHash = keccak256(
            abi.encode(_PERMIT_DETAILS_TYPEHASH, permit.details)
        );

        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        _PERMIT_SINGLE_TYPEHASH,
                        permitHash,
                        permit.spender,
                        permit.sigDeadline
                    )
                )
            )
        );

        (v, r, s) = vm.sign(privateKey, msgHash);
    }

    function _getEncodedPermit2(
        address token,
        uint256 amount,
        address spender
    ) internal returns (bytes memory encodedPermit2) {
        IERC20(token).approve(address(permit2), type(uint256).max);
        IPermitAllowanceTransfer.PermitSingle
            memory permitSingle = IPermitAllowanceTransfer.PermitSingle({
                details: IPermitAllowanceTransfer.PermitDetails({
                    token: token,
                    amount: uint160(amount),
                    expiration: uint48(block.timestamp + 100),
                    nonce: 0
                }),
                spender: spender,
                sigDeadline: block.timestamp + 100
            });
        bytes memory signature = _getPermitSignature(
            permitSingle,
            fromPrivateKey
        );
        encodedPermit2 = abi.encode(
            from, // owner
            permitSingle,
            signature
        );
    }

    // to receive the refunded ETH
    receive() external payable {}
}
