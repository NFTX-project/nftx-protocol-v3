import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getConfig } from "../utils";
import { utils } from "ethers";

export const deployUniswapV3Periphery = async ({
  hre,
  uniswapFactory,
}: {
  hre: HardhatRuntimeEnvironment;
  uniswapFactory: string;
}) => {
  const { deploy, deployer, config } = await getConfig(hre);

  const NFTDescriptor = await deploy("NFTDescriptor", {
    from: deployer,
    log: true,
  });

  const descriptor = await deploy("NonfungibleTokenPositionDescriptor", {
    from: deployer,
    libraries: {
      NFTDescriptor: NFTDescriptor.address,
    },
    args: [config.WETH, utils.formatBytes32String("WETH")],
    log: true,
  });

  const positionManager = await deploy("NonfungiblePositionManager", {
    from: deployer,
    args: [uniswapFactory, config.WETH, descriptor.address],
    log: true,
  });

  const swapRouter = await deploy("SwapRouter", {
    from: deployer,
    args: [uniswapFactory, config.WETH],
    log: true,
  });

  const quoter = await deploy("QuoterV2", {
    from: deployer,
    args: [uniswapFactory, config.WETH],
    log: true,
  });

  const tickLens = await deploy("TickLens", {
    from: deployer,
    args: [],
    log: true,
  });

  return {
    positionManager: positionManager.address,
    swapRouter: swapRouter.address,
    quoter: quoter.address,
    tickLens: tickLens.address,
    descriptor: descriptor.address,
  };
};
