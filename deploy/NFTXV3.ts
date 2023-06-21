import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { utils } from "ethers";
import deployConfig from "../deployConfig";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, execute } = deployments;

  const { deployer } = await getNamedAccounts();
  const config = deployConfig[network.name];

  const positionManager = await deployments.get("NonfungiblePositionManager");
  const router = await deployments.get("SwapRouter");
  const quoter = await deployments.get("QuoterV2");
  const nft = await deployments.get("MockNFT");

  const vaultImpl = await deploy("NFTXVaultUpgradeable", {
    from: deployer,
    log: true,
  });

  const vaultFactory = await deploy("NFTXVaultFactoryUpgradeable", {
    from: deployer,
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        init: {
          methodName: "__NFTXVaultFactory_init",
          args: [vaultImpl.address],
        },
      },
    },
    log: true,
  });
  // set premium related values
  await execute(
    "NFTXVaultFactoryUpgradeable",
    { from: deployer },
    "setTwapInterval",
    20 * 60 // 20 mins
  );
  await execute(
    "NFTXVaultFactoryUpgradeable",
    { from: deployer },
    "setPremiumDuration",
    10 * 60 * 60 // 10 hrs
  );
  await execute(
    "NFTXVaultFactoryUpgradeable",
    { from: deployer },
    "setPremiumMax",
    utils.parseEther("5") // 5 ether
  );

  const nftxRouter = await deploy("NFTXRouter", {
    from: deployer,
    args: [
      positionManager.address,
      router.address,
      quoter.address,
      vaultFactory.address,
      config.permit2,
    ],
    log: true,
  });

  // NFTXRouter has in-built fee handling
  await execute(
    "NFTXVaultFactoryUpgradeable",
    { from: deployer },
    "setFeeExclusion",
    nftxRouter.address,
    true
  );

  const timelockExcludeList = await deploy("TimelockExcludeList", {
    from: deployer,
    log: true,
  });

  const inventoryStaking = await deploy("NFTXInventoryStakingV3Upgradeable", {
    from: deployer,
    args: [config.WETH, config.permit2, vaultFactory.address],
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        init: {
          methodName: "__NFTXInventoryStaking_init",
          args: [
            2 * 24 * 60 * 60, // 2 days timelock
            utils.parseEther("0.05"), // 5% penalty
            timelockExcludeList.address,
          ],
        },
      },
    },
    log: true,
  });
  await execute(
    "NFTXInventoryStakingV3Upgradeable",
    { from: deployer },
    "setIsGuardian",
    deployer,
    true
  );

  const feeDistributor = await deploy("NFTXFeeDistributorV3", {
    from: deployer,
    args: [
      vaultFactory.address,
      inventoryStaking.address,
      nftxRouter.address,
      config.treasury,
    ],
    log: true,
  });

  await execute(
    "UniswapV3FactoryUpgradeable",
    { from: deployer },
    "setFeeDistributor",
    feeDistributor.address
  );
  await execute(
    "NFTXVaultFactoryUpgradeable",
    { from: deployer },
    "setFeeDistributor",
    feeDistributor.address
  );

  const marketplaceZap = await deploy("MarketplaceUniversalRouterZap", {
    from: deployer,
    args: [
      vaultFactory.address,
      config.nftxUniversalRouter,
      config.permit2,
      inventoryStaking.address,
      config.WETH,
    ],
    log: true,
  });

  await execute(
    "NFTXVaultFactoryUpgradeable",
    { from: deployer },
    "createVault",
    "TEST",
    "TST",
    nft.address,
    false,
    true
  );
};
export default func;
func.tags = ["NFTXV3"];
func.dependencies = ["UniV3", "Mocks"];
