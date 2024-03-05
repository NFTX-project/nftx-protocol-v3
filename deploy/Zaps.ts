import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { getConfig, getContract } from "./utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { config, deployments, deploy, execute, deployer } = await getConfig(
    hre
  );

  const vaultFactory = await deployments.get("NFTXVaultFactoryUpgradeableV3");
  const uniswapFactory = await deployments.get("UniswapV3FactoryUpgradeable");
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

  const vaultFactoryContract = await getContract(
    hre,
    "NFTXVaultFactoryUpgradeableV3",
    vaultFactory.address
  );
  const isMarketplaceZapExcludedFromFees =
    await vaultFactoryContract.excludedFromFees(marketplaceZap.address);
  if (!isMarketplaceZapExcludedFromFees) {
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
  }

  const createVaultZap = await deploy("CreateVaultZap", {
    from: deployer,
    args: [
      nftxRouter.address,
      uniswapFactory.address,
      inventoryStaking.address,
    ],
    log: true,
  });

  const isCreateVaultZapExcludedFromFees =
    await vaultFactoryContract.excludedFromFees(createVaultZap.address);
  if (!isCreateVaultZapExcludedFromFees) {
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
  }

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

  const isMigratorZapExcludedFromFees =
    await vaultFactoryContract.excludedFromFees(migratorZap.address);
  if (!isMigratorZapExcludedFromFees) {
    // MigratorZap doesn't deduct fees
    console.log("Setting fee exclusion for MigratorZap in V3...");
    await execute(
      "NFTXVaultFactoryUpgradeableV3",
      { from: deployer },
      "setFeeExclusion",
      migratorZap.address,
      true
    );
    console.log("Fee exclusion set for MigratorZap in V3");
  }

  console.warn(
    "[NOTE!] Set fee exclusion for MigratorZap in V2 of the protocol"
  );
};
export default func;
func.tags = ["Zaps"];
