import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, execute } = deployments;

  const { deployer } = await getNamedAccounts();

  const weth = await deploy("MockWETH", {
    from: deployer,
    log: true,
  });

  const nft = await deploy("MockNFT", {
    from: deployer,
    log: true,
  });
};
export default func;
func.tags = ["Mocks"];
func.dependencies = [];
