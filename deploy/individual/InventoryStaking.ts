import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { utils } from "ethers";
import deployConfig from "../../deployConfig";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, execute } = deployments;

  const { deployer } = await getNamedAccounts();
  const config = deployConfig[network.name];

  const vaultFactory = await deployments.get("NFTXVaultFactoryUpgradeableV3");
  const timelockExcludeList = await deployments.get("TimelockExcludeList");

  const inventoryDescriptor = await deploy("InventoryStakingDescriptor", {
    from: deployer,
    log: true,
  });
  const inventoryStaking = await deploy("NFTXInventoryStakingV3Upgradeable", {
    from: deployer,
    args: [config.WETH, config.permit2, vaultFactory.address],
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

  console.log("Setting guardian on InventoryStaking...");
  await execute(
    "NFTXInventoryStakingV3Upgradeable",
    { from: deployer },
    "setIsGuardian",
    deployer,
    true
  );
  console.log("Set guardian on InventoryStaking");
};
export default func;
func.tags = ["InventoryStaking"];
