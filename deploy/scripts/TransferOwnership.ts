import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { getConfig, getContract } from "../utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { execute, deployments, deployer, config } = await getConfig(hre);

  if (!config.multisig) {
    console.log("🚨 No multisig set");
    return;
  }

  await Promise.all(
    [
      "DefaultProxyAdmin",
      "MarketplaceUniversalRouterZap",
      "MigratorZap",
      "FailSafe",
      "NFTXFeeDistributorV3",
      "NFTXInventoryStakingV3Upgradeable",
      "NFTXRouter",
      "NFTXVaultFactoryUpgradeableV3",
      "NonfungiblePositionManager",
      "UniswapV3FactoryUpgradeable",
    ].map(async (name) => {
      const contract = await getContract(hre, name);
      const owner = await contract.owner();

      if (owner.toLowerCase() === config.multisig.toLowerCase()) {
        console.log(`Ownership of ${name} already transferred`);
      } else {
        try {
          console.log(`⌛ Transferring ownership of ${name}...`);

          await execute(
            name,
            { from: deployer },
            "transferOwnership",
            config.multisig
          );

          console.log(`✅ Ownership of ${name} transferred`);
        } catch (e) {
          console.log(`🚨 Failed to transfer ownership of ${name}`);
          console.log(e);
        }
      }
    })
  );
};
export default func;
func.tags = ["TransferOwnership"];
