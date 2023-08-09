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

import {NFTXVaultUpgradeableV3, INFTXVaultV3} from "@src/NFTXVaultUpgradeableV3.sol";
import {NFTXVaultFactoryUpgradeableV3} from "@src/NFTXVaultFactoryUpgradeableV3.sol";
import {InventoryStakingDescriptor} from "@src/custom/InventoryStakingDescriptor.sol";
import {NFTXInventoryStakingV3Upgradeable} from "@src/NFTXInventoryStakingV3Upgradeable.sol";
import {NFTXFeeDistributorV3} from "@src/NFTXFeeDistributorV3.sol";
import {TimelockExcludeList} from "@src/TimelockExcludeList.sol";
import {ITimelockExcludeList} from "@src/interfaces/ITimelockExcludeList.sol";
import {NFTXRouter, INFTXRouter} from "@src/NFTXRouter.sol";
import {MarketplaceUniversalRouterZap} from "@src/zaps/MarketplaceUniversalRouterZap.sol";
import {IPermitAllowanceTransfer} from "@src/interfaces/IPermitAllowanceTransfer.sol";

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
    NFTXRouter nftxRouter;
    InventoryStakingDescriptor inventoryDescriptor;
    NFTXInventoryStakingV3Upgradeable inventoryStaking;
    MarketplaceUniversalRouterZap marketplaceZap;

    uint24 constant DEFAULT_FEE_TIER = 10000;
    address immutable TREASURY = makeAddr("TREASURY");
    uint256 constant VAULT_ID = 0;
    uint256 constant VAULT_ID_1155 = 1;
    uint256 constant LP_TIMELOCK = 2 days;

    uint16 constant REWARD_TIER_CARDINALITY = 102; // considering 20 min interval with 1 block every 12 seconds on ETH Mainnet

    uint256 fromPrivateKey = 0x12341234;
    address from = vm.addr(fromPrivateKey);

    uint256[] emptyIds;
    uint256[] emptyAmounts;
    uint256 constant MAX_VTOKEN_PREMIUM_LIMIT = type(uint256).max;

    function setUp() public virtual {
        // to prevent underflow during calculations involving block.timestamp
        vm.warp(100 days);

        weth = new MockWETH();

        UniswapV3PoolUpgradeable poolImpl = new UniswapV3PoolUpgradeable();

        factory = new UniswapV3FactoryUpgradeable();
        factory.__UniswapV3FactoryUpgradeable_init(
            address(poolImpl),
            REWARD_TIER_CARDINALITY
        );
        descriptor = new NonfungibleTokenPositionDescriptor(
            address(weth),
            0x5745544800000000000000000000000000000000000000000000000000000000 // "WETH"
        );

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
        vaultFactory.__NFTXVaultFactory_init(
            address(vaultImpl),
            20 minutes, // twapInterval_
            10 hours, // premiumDuration_
            5 ether, // premiumMax_
            0.30 ether // depositorPremiumShare_
        );

        permit2 = new MockPermit2();

        timelockExcludeList = new TimelockExcludeList();
        inventoryDescriptor = new InventoryStakingDescriptor();
        inventoryStaking = new NFTXInventoryStakingV3Upgradeable(
            IWETH9(address(weth)),
            IPermitAllowanceTransfer(address(permit2)),
            vaultFactory
        );
        inventoryStaking.__NFTXInventoryStaking_init(
            2 days, // timelock
            0.05 ether, // 5% penalty
            ITimelockExcludeList(address(timelockExcludeList)),
            inventoryDescriptor
        );
        vaultFactory.setFeeExclusion(address(inventoryStaking), true);
        inventoryStaking.setIsGuardian(address(this), true);

        nftxRouter = new NFTXRouter(
            positionManager,
            router,
            quoter,
            vaultFactory,
            IPermitAllowanceTransfer(address(permit2)),
            LP_TIMELOCK,
            0.05 ether, // 5% penalty
            0.05 ether, // vTokenDustThreshold
            inventoryStaking
        );
        vaultFactory.setFeeExclusion(address(nftxRouter), true);
        positionManager.setTimelockExcluded(address(nftxRouter), true);

        feeDistributor = new NFTXFeeDistributorV3(
            vaultFactory,
            factory,
            inventoryStaking,
            nftxRouter,
            TREASURY
        );

        factory.setFeeDistributor(address(feeDistributor));
        vaultFactory.setFeeDistributor(address(feeDistributor));

        uint256 vaultId = vaultFactory.createVault(
            "TEST",
            "TST",
            address(nft),
            false, // is1155
            true // allowAllItems
        );
        vtoken = NFTXVaultUpgradeableV3(vaultFactory.vault(vaultId));
        vaultFactory.createVault(
            "TEST1155",
            "TST1155",
            address(nft1155),
            true, // is1155
            true // allowAllItems
        );
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
        return _mintVToken(qty, address(this), address(this));
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
                forceTimelock: false
            })
        );

        ethUsed = preETHBalance - address(this).balance;
    }

    function _mintPositionWithTwap(
        uint256 currentNFTPrice
    ) internal returns (uint256 positionId) {
        (, positionId, , , ) = _mintPosition(
            10,
            currentNFTPrice,
            currentNFTPrice - 0.5 ether,
            currentNFTPrice + 0.5 ether,
            DEFAULT_FEE_TIER
        );
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
        return _mintVTokenFor1155(qty, address(this), address(this));
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
                forceTimelock: false
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
