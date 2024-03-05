import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getConfig, getContract } from "../utils";

export const deployEligibilityManager = async (
  hre: HardhatRuntimeEnvironment
) => {
  const { deploy, execute, deployer } = await getConfig(hre);

  const NFTXEligibilityManager = await deploy("NFTXEligibilityManager", {
    from: deployer,
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        init: {
          methodName: "__NFTXEligibilityManager_init",
          args: [],
        },
      },
    },
    log: true,
  });

  // only deploy eligibility modules if the modules array is empty
  const eligibilityManagerContract = await getContract(
    hre,
    "NFTXEligibilityManager",
    NFTXEligibilityManager.address
  );
  const modules = await eligibilityManagerContract.allModules();

  // if no modules added yet
  if (modules.length === 0) {
    // Deploy the eligibility modules in this order
    const eligibilityModules = [
      "NFTXListEligibility",
      "NFTXRangeEligibility",
      "NFTXGen0KittyEligibility",
      "NFTXENSMerkleEligibility",
    ];

    for (let i = 0; i < eligibilityModules.length; ++i) {
      const eligibilityModule = await deploy(eligibilityModules[i], {
        from: deployer,
        log: true,
      });

      console.log(
        `Adding eligibility module ${eligibilityModules[i]} to NFTXEligibilityManager...`
      );
      await execute(
        "NFTXEligibilityManager",
        { from: deployer },
        "addModule",
        eligibilityModule.address
      );
      console.log(
        `Added eligibility module ${eligibilityModules[i]} to NFTXEligibilityManager`
      );
    }
  }

  return NFTXEligibilityManager.address;
};
