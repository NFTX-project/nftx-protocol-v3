import { HardhatRuntimeEnvironment } from "hardhat/types";
import {
  executeOwnableFunction,
  getConfig,
  getContract,
  getDeployment,
  handleUpgradeDeploy,
} from "../utils";
import { constants } from "ethers";
import { deployEligibilityManager } from "./EligibilityManager";

export const deployVaultFactory = async ({
  hre,
}: {
  hre: HardhatRuntimeEnvironment;
}) => {
  const { deploy, execute, deployer, config } = await getConfig(hre);

  const prevVaultImpl = await getDeployment(hre, "NFTXVaultUpgradeableV3");

  const vaultImpl = await deploy("NFTXVaultUpgradeableV3", {
    from: deployer,
    args: [config.WETH],
    log: true,
  });

  const vaultFactory = await handleUpgradeDeploy({
    hre,
    contractName: "NFTXVaultFactoryUpgradeableV3",
    deployOptions: {
      from: deployer,
      proxy: {
        proxyContract: "OpenZeppelinTransparentProxy",
        execute: {
          init: {
            methodName: "__NFTXVaultFactory_init",
            args: [
              vaultImpl.address,
              config.twapInterval,
              config.premiumDuration,
              config.premiumMax,
              config.depositorPremiumShare,
            ],
          },
        },
      },
      log: true,
    },
  });

  const vaultFactoryContract = await getContract(
    hre,
    "NFTXVaultFactoryUpgradeableV3",
    vaultFactory.address
  );
  let eligibilityManager: string =
    await vaultFactoryContract.eligibilityManager();

  // == set states ==
  // => 1. if eligibility manager is not set yet
  if (eligibilityManager === constants.AddressZero) {
    eligibilityManager = (await deployEligibilityManager({ hre }))
      .NFTXEligibilityManager;

    console.log("Setting eligibilityManager in VaultFactory...");
    await execute(
      "NFTXVaultFactoryUpgradeableV3",
      { from: deployer },
      "setEligibilityManager",
      eligibilityManager
    );
    console.log("Set eligibilityManager in VaultFactory");
  }

  // => check if new pool implementation was deployed for upgrade
  if (prevVaultImpl && prevVaultImpl.address !== vaultImpl.address) {
    // => upgrade

    // == update states ==
    // set new vault implementation in VaultFactory
    await executeOwnableFunction({
      hre,
      contractName: "NFTXVaultFactoryUpgradeableV3",
      contractAddress: vaultFactory.address,
      functionName: "upgradeBeaconTo",
      functionArgs: [vaultImpl.address],
    });
  }

  return { vaultFactory: vaultFactory.address };
};
