import { HardhatRuntimeEnvironment } from "hardhat/types";
import { executeOwnableFunction, getConfig, getContract } from "../utils";

export const deployMigratorZap = async ({
  hre,
  vaultFactory,
  positionManager,
  inventoryStaking,
}: {
  hre: HardhatRuntimeEnvironment;
  vaultFactory: string;
  positionManager: string;
  inventoryStaking: string;
}) => {
  const { deploy, deployer, config } = await getConfig(hre);

  const migratorZap = await deploy("MigratorZap", {
    from: deployer,
    args: [
      config.WETH,
      config.v2VaultFactory,
      config.v2Inventory,
      config.sushiRouter,
      positionManager,
      vaultFactory,
      inventoryStaking,
    ],
    log: true,
  });

  // == set states ==
  const vaultFactoryContract = await getContract(
    hre,
    "NFTXVaultFactoryUpgradeableV3",
    vaultFactory
  );
  const isExcludedFromFees = await vaultFactoryContract.excludedFromFees(
    migratorZap.address
  );
  // => 1. add to fee exclusion if not added yet
  if (isExcludedFromFees === false) {
    await executeOwnableFunction({
      hre,
      contractName: "NFTXVaultFactoryUpgradeableV3",
      contractAddress: vaultFactory,
      functionName: "setFeeExclusion",
      functionArgs: [migratorZap.address, true],
    });
  }

  console.warn(
    "[⚠️ NOTE!] Set fee exclusion for MigratorZap in V2 of the protocol"
  );

  return {
    migratorZap: migratorZap.address,
  };
};
