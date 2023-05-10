import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers, constants } from "ethers";
import deployConfig from "../deployConfig";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, execute } = deployments;

  const { deployer } = await getNamedAccounts();
  const config = deployConfig[network.name];

  const poolImpl = await deploy("UniswapV3PoolUpgradeable", {
    from: deployer,
    log: true,
  });

  const factory = await deploy("UniswapV3FactoryUpgradeable", {
    from: deployer,
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        init: {
          methodName: "__UniswapV3FactoryUpgradeable_init",
          args: [poolImpl.address],
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
    args: [config.WETH, ethers.utils.formatBytes32String("WETH")],
    log: true,
  });

  const positionManager = await deploy("NonfungiblePositionManager", {
    from: deployer,
    args: [factory.address, config.WETH, descriptor.address],
    log: true,
  });

  const router = await deploy("SwapRouter", {
    from: deployer,
    args: [factory.address, config.WETH],
    log: true,
  });

  const quoter = await deploy("QuoterV2", {
    from: deployer,
    args: [factory.address, config.WETH],
    log: true,
  });

  const tickLens = await deploy("TickLens", {
    from: deployer,
    args: [],
    log: true,
  });
};
export default func;
func.tags = ["UniV3"];
func.dependencies = [];
