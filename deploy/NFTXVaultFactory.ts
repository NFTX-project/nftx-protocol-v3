import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { utils } from "ethers";
import deployConfig from "../deployConfig";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, execute } = deployments;

  const { deployer } = await getNamedAccounts();
  const config = deployConfig[network.name];

  const vaultImpl = await deployments.get("NFTXVaultUpgradeableV3");

  const vaultFactory = await deploy("NFTXVaultFactoryUpgradeableV3", {
    from: deployer,
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        init: {
          methodName: "__NFTXVaultFactory_init",
          args: [
            vaultImpl.address,
            20 * 60, // twapInterval = 20 mins
            10 * 60 * 60, // premiumDuration = 10 hrs
            utils.parseEther("5"), // premiumMax = 5 ether
            utils.parseEther("0.30"), // depositorPremiumShare = 0.30 ether
          ],
        },
      },
    },
    log: true,
  });
};
export default func;
func.tags = ["NFTXVaultFactory"];
