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
  const inventoryStaking = await deployments.get(
    "NFTXInventoryStakingV3Upgradeable"
  );

  const marketplaceZap = await deploy("MarketplaceUniversalRouterZap", {
    from: deployer,
    args: [
      vaultFactory.address,
      config.nftxUniversalRouter,
      config.permit2,
      inventoryStaking.address,
      config.WETH,
    ],
    log: true,
  });

  // MarketplaceZap has in-built fee handling
  console.log("Setting fee exclusion for MarketplaceZap...");
  await execute(
    "NFTXVaultFactoryUpgradeableV3",
    { from: deployer },
    "setFeeExclusion",
    marketplaceZap.address,
    true
  );
  console.log("Fee exclusion set for MarketplaceZap");
};
export default func;
func.tags = ["MarketplaceZap"];
