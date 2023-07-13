import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { utils } from "ethers";
import deployConfig from "../../deployConfig";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, execute } = deployments;

  const { deployer } = await getNamedAccounts();
  const config = deployConfig[network.name];

  const vaultImpl = await deploy("NFTXVaultUpgradeableV3", {
    from: deployer,
    args: [config.WETH],
    log: true,
  });

  console.log("Setting new Vault Impl in NFTXVaultFactory...");
  await execute(
    "NFTXVaultFactoryUpgradeableV3",
    { from: deployer },
    "upgradeBeaconTo",
    vaultImpl.address
  );
  console.log("New Vault Impl set in NFTXVaultFactory");
};
export default func;
func.tags = ["NFTXVault"];
