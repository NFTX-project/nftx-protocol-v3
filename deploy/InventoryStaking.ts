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
            2 * 24 * 60 * 60, // timelock = 2 days timelock
            utils.parseEther("0.05"), // penalty = 5%
            timelockExcludeList.address,
            inventoryDescriptor.address,
          ],
        },
      },
    },
    log: true,
  });
};
export default func;
func.tags = ["InventoryStaking"];
