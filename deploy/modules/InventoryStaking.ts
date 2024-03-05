import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getConfig, getContract } from "../utils";
import { deployVaultFactory } from "./VaultFactory";

export const deployInventoryStaking = async (
  hre: HardhatRuntimeEnvironment
) => {
  const { deploy, execute, deployer, config } = await getConfig(hre);

  const vaultFactory = await deployVaultFactory(hre);

  const timelockExcludeList = await deploy("TimelockExcludeList", {
    from: deployer,
    log: true,
  });

  const inventoryDescriptor = await deploy("InventoryStakingDescriptor", {
    from: deployer,
    log: true,
  });

  const inventoryStaking = await deploy("NFTXInventoryStakingV3Upgradeable", {
    from: deployer,
    args: [config.WETH, config.permit2, vaultFactory],
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        init: {
          methodName: "__NFTXInventoryStaking_init",
          args: [
            config.inventoryTimelock,
            config.inventoryEarlyWithdrawPenaltyInWei,
            timelockExcludeList.address,
            inventoryDescriptor.address,
          ],
        },
      },
    },
    log: true,
  });

  const vaultFactoryContract = await getContract(
    hre,
    "NFTXVaultFactoryUpgradeableV3",
    vaultFactory
  );
  const isExcludedFromFees = await vaultFactoryContract.excludedFromFees(
    inventoryStaking.address
  );
  // add to fee exclusion if not added yet
  if (isExcludedFromFees === false) {
    // InventoryStaking has in-built fee handling
    console.log("Setting fee exclusion for InventoryStaking...");
    await execute(
      "NFTXVaultFactoryUpgradeableV3",
      { from: deployer },
      "setFeeExclusion",
      inventoryStaking.address,
      true
    );
    console.log("Fee exclusion set for InventoryStaking");
  }

  const inventoryStakingContract = await getContract(
    hre,
    "NFTXInventoryStakingV3Upgradeable",
    inventoryStaking.address
  );
  const isGuardian = await inventoryStakingContract.isGuardian(deployer);
  // add guardian if not added yet
  if (isGuardian === false) {
    console.log("Setting guardian on InventoryStaking...");
    await execute(
      "NFTXInventoryStakingV3Upgradeable",
      { from: deployer },
      "setIsGuardian",
      deployer,
      true
    );
    console.log("Set guardian on InventoryStaking");
  }

  return {
    inventoryStaking: inventoryStaking.address,
    vaultFactory,
  };
};
