// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {TickHelpers} from "@src/lib/TickHelpers.sol";

import {UniswapV3FactoryUpgradeable} from "@uni-core/UniswapV3FactoryUpgradeable.sol";
import {UniswapV3PoolUpgradeable} from "@uni-core/UniswapV3PoolUpgradeable.sol";
import {NonfungibleTokenPositionDescriptor} from "@uni-periphery/NonfungibleTokenPositionDescriptor.sol";
import {NonfungiblePositionManager} from "@uni-periphery/NonfungiblePositionManager.sol";
import {SwapRouter} from "@uni-periphery/SwapRouter.sol";
import {QuoterV2} from "@uni-periphery/lens/QuoterV2.sol";

import {NFTXVaultUpgradeableV3} from "@src/NFTXVaultUpgradeableV3.sol";
import {NFTXVaultFactoryUpgradeableV3} from "@src/NFTXVaultFactoryUpgradeableV3.sol";
import {InventoryStakingDescriptor} from "@src/custom/InventoryStakingDescriptor.sol";
import {ITimelockExcludeList} from "@src/interfaces/ITimelockExcludeList.sol";
import {TimelockExcludeList} from "@src/TimelockExcludeList.sol";
import {NFTXInventoryStakingV3Upgradeable} from "@src/NFTXInventoryStakingV3Upgradeable.sol";
import {NFTXRouter, INFTXRouter} from "@src/NFTXRouter.sol";
import {NFTXFeeDistributorV3} from "@src/NFTXFeeDistributorV3.sol";
import {IPermitAllowanceTransfer} from "@src/interfaces/external/IPermitAllowanceTransfer.sol";
import {NFTXEligibilityManager} from "@src/v2/NFTXEligibilityManager.sol";
import {NFTXListEligibility} from "@src/v2/eligibility/NFTXListEligibility.sol";
import {NFTXRangeEligibility} from "@src/v2/eligibility/NFTXRangeEligibility.sol";
import {NFTXGen0KittyEligibility} from "@src/v2/eligibility/NFTXGen0KittyEligibility.sol";
import {NFTXENSMerkleEligibility} from "@src/v2/eligibility/NFTXENSMerkleEligibility.sol";
import {MarketplaceUniversalRouterZap} from "@src/zaps/MarketplaceUniversalRouterZap.sol";

import {MockWETH} from "@mocks/MockWETH.sol";
import {IWETH9} from "@uni-periphery/interfaces/external/IWETH9.sol";
import {MockNFT} from "@mocks/MockNFT.sol";
import {Mock1155} from "@mocks/Mock1155.sol";
import {MockPermit2} from "@mocks/permit2/MockPermit2.sol";
import {MockDelegateRegistry} from "@mocks/MockDelegateRegistry.sol";
import {MockUniversalRouter} from "@mocks/MockUniversalRouter.sol";

import {TestExtend} from "@test/lib/TestExtend.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {Users} from "@test/utils/Users.sol";
import {Constants} from "@test/utils/Constants.sol";

contract NewTestBase is TestExtend, Constants, ERC721Holder, ERC1155Holder {
    uint24 constant DEFAULT_FEE_TIER = 3_000;
    uint16 constant REWARD_TIER_CARDINALITY = 102; // considering 20 min interval with 1 block every 12 seconds on ETH Mainnet
    uint256 constant LP_TIMELOCK = 2 days;
    address DELEGATE_REGISTRY = 0x00000000000000447e69651d841bD8D104Bed493;

    Users internal users;

    IWETH9 internal weth;
    MockNFT nft721;
    Mock1155 nft1155;

    address permit2;

    uint256[] emptyIds;
    uint256[] emptyAmounts;

    function setUp() public virtual {
        // to prevent underflow during calculations involving block.timestamp
        vm.warp(100 days);

        users = Users({
            owner: createUser("owner"),
            alice: createUser("alice"),
            treasury: payable(makeAddr("treasury"))
        });

        weth = IWETH9(address(new MockWETH()));
        nft721 = new MockNFT();
        nft1155 = new Mock1155();
        permit2 = address(new MockPermit2());

        // set mock delegate registry at the mainnet address
        MockDelegateRegistry delegateRegistry = new MockDelegateRegistry();
        vm.etch(DELEGATE_REGISTRY, address(delegateRegistry).code);

        vm.startPrank(users.alice);
    }

    // HELPERS

    /// @dev Generates a user, labels its address, and funds it with ETH.
    function createUser(string memory name) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        vm.deal({account: user, newBalance: 10_000 ether});
        return user;
    }

    function switchPrank(address newAddress) internal {
        vm.stopPrank();
        vm.startPrank(newAddress);
    }

    function deployUniswapFactory()
        internal
        returns (UniswapV3FactoryUpgradeable uniswapFactory)
    {
        address uniswapPoolImpl = address(new UniswapV3PoolUpgradeable());

        uniswapFactory = new UniswapV3FactoryUpgradeable();
        uniswapFactory.__UniswapV3FactoryUpgradeable_init({
            beaconImplementation_: uniswapPoolImpl,
            rewardTierCardinality_: REWARD_TIER_CARDINALITY
        });
    }

    function deployEligibilityManager()
        internal
        returns (NFTXEligibilityManager eligibilityManager)
    {
        eligibilityManager = new NFTXEligibilityManager();
        eligibilityManager.__NFTXEligibilityManager_init();

        eligibilityManager.addModule(address(new NFTXListEligibility()));
        eligibilityManager.addModule(address(new NFTXRangeEligibility()));
        eligibilityManager.addModule(address(new NFTXGen0KittyEligibility()));
        eligibilityManager.addModule(address(new NFTXENSMerkleEligibility()));
    }

    /// @dev Deploys a new vault factory and sets the eligibility manager.
    /// @notice Fee Distributor is not set yet
    function deployVaultFactory()
        internal
        returns (NFTXVaultFactoryUpgradeableV3 vaultFactory)
    {
        address vaultImpl = address(new NFTXVaultUpgradeableV3(weth));

        vaultFactory = new NFTXVaultFactoryUpgradeableV3();
        vaultFactory.__NFTXVaultFactory_init({
            vaultImpl: vaultImpl,
            twapInterval_: 20 minutes,
            premiumDuration_: 10 hours,
            premiumMax_: 5 ether,
            depositorPremiumShare_: 0.30 ether
        });

        address eligibilityManager = address(deployEligibilityManager());
        vaultFactory.setEligibilityManager(eligibilityManager);
    }

    function deployInventoryStaking()
        internal
        returns (
            NFTXInventoryStakingV3Upgradeable inventoryStaking,
            NFTXVaultFactoryUpgradeableV3 vaultFactory
        )
    {
        vaultFactory = deployVaultFactory();

        ITimelockExcludeList timelockExcludeList = ITimelockExcludeList(
            address(new TimelockExcludeList())
        );
        InventoryStakingDescriptor inventoryDescriptor = new InventoryStakingDescriptor();
        inventoryStaking = new NFTXInventoryStakingV3Upgradeable(
            weth,
            IPermitAllowanceTransfer(permit2),
            vaultFactory
        );
        inventoryStaking.__NFTXInventoryStaking_init({
            timelock_: 2 days,
            earlyWithdrawPenaltyInWei_: 0.05 ether, // 5%
            timelockExcludeList_: timelockExcludeList,
            descriptor_: inventoryDescriptor
        });

        vaultFactory.setFeeExclusion(address(inventoryStaking), true);
    }

    function deployNFTXRouter()
        internal
        returns (
            NFTXRouter nftxRouter,
            UniswapV3FactoryUpgradeable uniswapFactory,
            NFTXInventoryStakingV3Upgradeable inventoryStaking,
            NFTXVaultFactoryUpgradeableV3 vaultFactory,
            SwapRouter router
        )
    {
        uniswapFactory = deployUniswapFactory();
        (inventoryStaking, vaultFactory) = deployInventoryStaking();

        address descriptor = address(
            new NonfungibleTokenPositionDescriptor({
                _WETH9: address(weth),
                _nativeCurrencyLabelBytes: 0x5745544800000000000000000000000000000000000000000000000000000000 // "WETH"
            })
        );
        NonfungiblePositionManager positionManager = new NonfungiblePositionManager(
                address(uniswapFactory),
                address(weth),
                descriptor
            );
        router = new SwapRouter(address(uniswapFactory), address(weth));
        QuoterV2 quoter = new QuoterV2(address(uniswapFactory), address(weth));

        nftxRouter = new NFTXRouter({
            positionManager_: positionManager,
            router_: router,
            quoter_: quoter,
            nftxVaultFactory_: vaultFactory,
            PERMIT2_: IPermitAllowanceTransfer(permit2),
            lpTimelock_: LP_TIMELOCK,
            earlyWithdrawPenaltyInWei_: 0.05 ether, // 5%
            vTokenDustThreshold_: 0.05 ether,
            inventoryStaking_: inventoryStaking
        });

        vaultFactory.setFeeExclusion(address(nftxRouter), true);
        positionManager.setTimelockExcluded(address(nftxRouter), true);
    }

    function deployFeeDistributor()
        internal
        returns (
            NFTXFeeDistributorV3 feeDistributor,
            NFTXRouter nftxRouter,
            UniswapV3FactoryUpgradeable uniswapFactory,
            NFTXInventoryStakingV3Upgradeable inventoryStaking,
            NFTXVaultFactoryUpgradeableV3 vaultFactory,
            SwapRouter router
        )
    {
        (
            nftxRouter,
            uniswapFactory,
            inventoryStaking,
            vaultFactory,
            router
        ) = deployNFTXRouter();

        feeDistributor = new NFTXFeeDistributorV3(
            vaultFactory,
            uniswapFactory,
            inventoryStaking,
            nftxRouter,
            users.treasury,
            DEFAULT_FEE_TIER
        );

        uniswapFactory.setFeeDistributor(address(feeDistributor));
        vaultFactory.setFeeDistributor(address(feeDistributor));
    }

    function deployNFTXV3Core()
        internal
        returns (
            NFTXFeeDistributorV3 feeDistributor,
            NFTXRouter nftxRouter,
            UniswapV3FactoryUpgradeable uniswapFactory,
            NFTXInventoryStakingV3Upgradeable inventoryStaking,
            NFTXVaultFactoryUpgradeableV3 vaultFactory,
            SwapRouter router
        )
    {
        return deployFeeDistributor();
    }

    function deployMarketplaceZap()
        internal
        returns (MarketplaceUniversalRouterZap marketplaceZap)
    {
        (
            ,
            ,
            ,
            NFTXInventoryStakingV3Upgradeable inventoryStaking,
            NFTXVaultFactoryUpgradeableV3 vaultFactory,
            SwapRouter router
        ) = deployNFTXV3Core();
        MockUniversalRouter universalRouter = new MockUniversalRouter(
            IPermitAllowanceTransfer(permit2),
            router
        );

        marketplaceZap = new MarketplaceUniversalRouterZap(
            vaultFactory,
            address(universalRouter),
            IPermitAllowanceTransfer(permit2),
            address(inventoryStaking),
            weth
        );

        vaultFactory.setFeeExclusion(address(marketplaceZap), true);
    }

    function deployVToken721(
        NFTXVaultFactoryUpgradeableV3 vaultFactory
    ) internal returns (uint256 vaultId, NFTXVaultUpgradeableV3 vault) {
        vaultId = vaultFactory.createVault({
            name: "Test",
            symbol: "TST",
            assetAddress: address(nft721),
            is1155: false,
            allowAllItems: true
        });
        vault = NFTXVaultUpgradeableV3(vaultFactory.vault(vaultId));
    }

    function deployVToken1155(
        NFTXVaultFactoryUpgradeableV3 vaultFactory
    ) internal returns (uint256 vaultId, NFTXVaultUpgradeableV3 vault) {
        vaultId = vaultFactory.createVault({
            name: "Test",
            symbol: "TST",
            assetAddress: address(nft1155),
            is1155: true,
            allowAllItems: true
        });
        vault = NFTXVaultUpgradeableV3(vaultFactory.vault(vaultId));
    }

    function valueWithError(
        uint256 value,
        uint256 errorBps
    ) internal pure returns (uint256) {
        return (value * (10_000 - errorBps)) / 10_000;
    }

    // @dev the actual value can be off by few decimals so accounting for 0.3% error.
    function valueWithError(uint256 value) internal pure returns (uint256) {
        return valueWithError(value, 30);
    }

    function getTickDistance(
        NFTXRouter nftxRouter,
        uint24 feeTier
    ) internal view returns (uint256 tickDistance) {
        UniswapV3FactoryUpgradeable uniswapFactory = UniswapV3FactoryUpgradeable(
                nftxRouter.positionManager().factory()
            );
        tickDistance = uint256(
            uint24(uniswapFactory.feeAmountTickSpacing(feeTier))
        );
    }

    function getTicks(
        bool isVToken0,
        uint256 tickDistance,
        uint256 currentNFTPrice,
        uint256 lowerNFTPrice,
        uint256 upperNFTPrice
    )
        internal
        pure
        returns (uint160 currentSqrtPriceX96, int24 tickLower, int24 tickUpper)
    {
        if (isVToken0) {
            currentSqrtPriceX96 = TickHelpers.encodeSqrtRatioX96(
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
            currentSqrtPriceX96 = TickHelpers.encodeSqrtRatioX96(
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

    // to receive the refunded ETH
    receive() external payable {}
}
