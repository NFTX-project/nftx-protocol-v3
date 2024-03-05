import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getConfig, getContract } from "../utils";
import { constants } from "ethers";
import { deployEligibilityManager } from "./EligibilityManager";

export const deployVaultFactory = async (hre: HardhatRuntimeEnvironment) => {
  const { deploy, execute, deployer, config } = await getConfig(hre);

  const vaultImpl = await deploy("NFTXVaultUpgradeableV3", {
    from: deployer,
    args: [config.WETH],
    log: true,
  });

  const vaultFactory = await deploy("NFTXVaultFactoryUpgradeableV3", {
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
  });

  const vaultFactoryContract = await getContract(
    hre,
    "NFTXVaultFactoryUpgradeableV3",
    vaultFactory.address
  );
  let eligibilityManager = await vaultFactoryContract.eligibilityManager();

  // if eligibility manager is not set yet
  if (eligibilityManager === constants.AddressZero) {
    eligibilityManager = await deployEligibilityManager(hre);

    console.log("Setting eligibilityManager in VaultFactory...");
    await execute(
      "NFTXVaultFactoryUpgradeableV3",
      { from: deployer },
      "setEligibilityManager",
      eligibilityManager
    );
    console.log("Set eligibilityManager in VaultFactory");
  }

  return vaultFactory.address;
};
