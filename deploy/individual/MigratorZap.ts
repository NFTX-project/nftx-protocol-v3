import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { utils } from "ethers";
import deployConfig from "../../deployConfig";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, execute } = deployments;

  const { deployer } = await getNamedAccounts();
  const config = deployConfig[network.name];

  const positionManager = await deployments.get("NonfungiblePositionManager");
  const vaultFactory = await deployments.get("NFTXVaultFactoryUpgradeableV3");
  const inventoryStaking = await deployments.get(
    "NFTXInventoryStakingV3Upgradeable"
  );

  const migratorZap = await deploy("MigratorZap", {
    from: deployer,
    args: [
      config.WETH,
      config.v2VaultFactory,
      config.v2Inventory,
      config.sushiRouter,
      positionManager.address,
      vaultFactory.address,
      inventoryStaking.address,
    ],
    log: true,
  });

  console.log("Setting fee exclusion for MigratorZap in V3...");
  await execute(
    "NFTXVaultFactoryUpgradeableV3",
    { from: deployer },
    "setFeeExclusion",
    migratorZap.address,
    true
  );
  console.log("Fee exclusion set for MigratorZap in V3");
  console.warn(
    "[NOTE!] Set fee exclusion for MigratorZap in V2 of the protocol"
  );
};
export default func;
func.tags = ["MigratorZap"];
// func.dependencies = ["NFTXV3"];
