import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { utils } from "ethers";
import deployConfig from "../../deployConfig";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, execute } = deployments;

  const { deployer } = await getNamedAccounts();
  const config = deployConfig[network.name];

  // `transferOwnership`:
  if (!config.multisig) return;

  await Promise.all(
    [
      "DefaultProxyAdmin",
      "MarketplaceUniversalRouterZap",
      "NFTXFeeDistributorV3",
      "NFTXInventoryStakingV3Upgradeable",
      "NFTXRouter",
      "NFTXVaultFactoryUpgradeable",
      "NonfungiblePositionManager",
      "UniswapV3FactoryUpgradeable",
    ].map(async (name) => {
      console.log(`Transferring ownership of ${name}...`);
      await execute(
        name,
        { from: deployer },
        "transferOwnership",
        config.multisig
      );
      console.log(`Ownership of ${name} transferred`);
    })
  );
};
export default func;
func.tags = ["TransferOwnership"];
