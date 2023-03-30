import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers, constants } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, execute } = deployments;

  const { deployer } = await getNamedAccounts();

  const weth = await deployments.get("MockWETH");

  const factory = await deploy("UniswapV3FactoryUpgradeable", {
    from: deployer,
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        init: {
          methodName: "__UniswapV3FactoryUpgradeable_init",
          args: [],
        },
      },
    },
    log: true,
  });

  const NFTDescriptor = await deploy("NFTDescriptor", {
    from: deployer,
    log: true,
  });

  const descriptor = await deploy("NonfungibleTokenPositionDescriptor", {
    from: deployer,
    libraries: {
      NFTDescriptor: NFTDescriptor.address,
    },
    args: [weth.address, constants.HashZero],
    log: true,
  });

  const positionManager = await deploy("NonfungiblePositionManager", {
    from: deployer,
    args: [factory.address, weth.address, descriptor.address],
    log: true,
  });

  const router = await deploy("SwapRouter", {
    from: deployer,
    args: [factory.address, weth.address],
    log: true,
  });

  const quoter = await deploy("QuoterV2", {
    from: deployer,
    args: [factory.address, weth.address],
    log: true,
  });
};
export default func;
func.tags = ["UniV3"];
func.dependencies = ["Mocks"];
