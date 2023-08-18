import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { utils } from "ethers";
import deployConfig from "../deployConfig";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, execute } = deployments;

  const { deployer } = await getNamedAccounts();
  const config = deployConfig[network.name];

  const vaultFactory = await deployments.get("NFTXVaultFactoryUpgradeableV3");
  const uniV3Factory = await deployments.get("UniswapV3FactoryUpgradeable");
  const positionManager = await deployments.get("NonfungiblePositionManager");
  const inventoryStaking = await deployments.get(
    "NFTXInventoryStakingV3Upgradeable"
  );
  const nftxRouter = await deployments.get("NFTXRouter");

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

  // MarketplaceZap has in-built fee handling
  console.log("Setting fee exclusion for MarketplaceZap...");
  await execute(
    "NFTXVaultFactoryUpgradeableV3",
    { from: deployer },
    "setFeeExclusion",
    marketplaceZap.address,
    true
  );
  console.log("Fee exclusion set for MarketplaceZap");

  const createVaultZap = await deploy("CreateVaultZap", {
    from: deployer,
    args: [nftxRouter.address, uniV3Factory.address, inventoryStaking.address],
    log: true,
  });

  // CreateVaultZap doesn't deduct fees
  console.log("Setting fee exclusion for CreateVaultZap...");
  await execute(
    "NFTXVaultFactoryUpgradeableV3",
    { from: deployer },
    "setFeeExclusion",
    createVaultZap.address,
    true
  );
  console.log("Fee exclusion set for CreateVaultZap");

  const migratorZap = await deploy("MigratorZap", {
    from: deployer,
    args: [
      config.WETH,
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
func.tags = ["Zaps"];
