import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import * as readline from "readline";
import { getConfig } from "./utils";
import { deployMarketplaceZap } from "./modules/MarketplaceZap";
import { deployCreateVaultZap } from "./modules/CreateVaultZap";
import { deployMigratorZap } from "./modules/MigratorZap";

const waitForEnter = async () => {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return new Promise<void>((resolve) => {
    rl.question(
      "🚨🚨 Make sure the UniversalRouter is updated & set in deployConfig. Redeploy if UniswapV3Factory address or salt was modified 🚨🚨\n Press Enter to continue...",
      () => {
        rl.close();
        resolve();
      }
    );
  });
};

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  await waitForEnter();

  const { deployments } = await getConfig(hre);

  const vaultFactory = await deployments.get("NFTXVaultFactoryUpgradeableV3");
  const uniswapFactory = await deployments.get("UniswapV3FactoryUpgradeable");
  const positionManager = await deployments.get("NonfungiblePositionManager");
  const inventoryStaking = await deployments.get(
    "NFTXInventoryStakingV3Upgradeable"
  );
  const nftxRouter = await deployments.get("NFTXRouter");

  const { marketplaceZap } = await deployMarketplaceZap({
    hre,
    vaultFactory: vaultFactory.address,
    inventoryStaking: inventoryStaking.address,
  });

  const { createVaultZap } = await deployCreateVaultZap({
    hre,
    vaultFactory: vaultFactory.address,
    nftxRouter: nftxRouter.address,
    uniswapFactory: uniswapFactory.address,
    inventoryStaking: inventoryStaking.address,
  });

  const { migratorZap } = await deployMigratorZap({
    hre,
    vaultFactory: vaultFactory.address,
    positionManager: positionManager.address,
    inventoryStaking: inventoryStaking.address,
  });
};
export default func;
func.tags = ["Zaps"];
