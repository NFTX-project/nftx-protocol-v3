import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { utils } from "ethers";
import deployConfig from "../../deployConfig";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, execute } = deployments;

  const { deployer } = await getNamedAccounts();
  const config = deployConfig[network.name];

  const nftxRouter = await deployments.get("NFTXRouter");
  const uniV3Factory = await deployments.get("UniswapV3FactoryUpgradeable");
  const inventoryStaking = await deployments.get(
    "NFTXInventoryStakingV3Upgradeable"
  );

  const createVaultZap = await deploy("CreateVaultZap", {
    from: deployer,
    args: [nftxRouter.address, uniV3Factory.address, inventoryStaking.address],
    log: true,
  });

  console.log("Setting fee exclusion for CreateVaultZap...");
  await execute(
    "NFTXVaultFactoryUpgradeableV3",
    { from: deployer },
    "setFeeExclusion",
    createVaultZap.address,
    true
  );
  console.log("Fee exclusion set for CreateVaultZap");
};
export default func;
func.tags = ["CreateVaultZap"];
// func.dependencies = ["NFTXV3"];
