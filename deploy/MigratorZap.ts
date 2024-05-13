import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { deployMigratorZap } from "./modules/MigratorZap";
import { getConfig } from "./utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments } = await getConfig(hre);

  const vaultFactory = await deployments.get("NFTXVaultFactoryUpgradeableV3");
  const positionManager = await deployments.get("NonfungiblePositionManager");
  const inventoryStaking = await deployments.get(
    "NFTXInventoryStakingV3Upgradeable"
  );

  const { migratorZap } = await deployMigratorZap({
    hre,
    vaultFactory: vaultFactory.address,
    positionManager: positionManager.address,
    inventoryStaking: inventoryStaking.address,
  });
};
export default func;
func.tags = ["MigratorZap"];
func.dependencies = [];
