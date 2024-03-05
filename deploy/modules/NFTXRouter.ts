import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getConfig, getContract } from "../utils";
import { deployUniswapV3Factory } from "./UniswapV3Factory";
import { deployInventoryStaking } from "./InventoryStaking";
import { utils } from "ethers";

export const deployNFTXRouter = async (hre: HardhatRuntimeEnvironment) => {
  const { deploy, execute, deployer, config } = await getConfig(hre);

  const uniswapFactory = await deployUniswapV3Factory(hre);
  const { inventoryStaking, vaultFactory } = await deployInventoryStaking(hre);

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

  const nftxRouter = await deploy("NFTXRouter", {
    from: deployer,
    args: [
      positionManager.address,
      swapRouter.address,
      quoter.address,
      vaultFactory,
      config.permit2,
      config.lpTimelock,
      config.lpEarlyWithdrawPenaltyInWei,
      config.nftxRouterVTokenDustThreshold,
      inventoryStaking,
    ],
    log: true,
  });

  const vaultFactoryContract = await getContract(
    hre,
    "NFTXVaultFactoryUpgradeableV3",
    vaultFactory
  );
  const isExcludedFromFees = await vaultFactoryContract.excludedFromFees(
    nftxRouter.address
  );
  // add to fee exclusion if not added yet
  if (isExcludedFromFees === false) {
    // NFTXRouter has in-built fee handling
    console.log("Setting fee exclusion for NFTXRouter...");
    await execute(
      "NFTXVaultFactoryUpgradeableV3",
      { from: deployer },
      "setFeeExclusion",
      nftxRouter.address,
      true
    );
    console.log("Fee exclusion set for NFTXRouter");
  }

  const positionManagerContract = await getContract(
    hre,
    "NonfungiblePositionManager",
    positionManager.address
  );
  const isTimelockExcluded = await positionManagerContract.timelockExcluded(
    nftxRouter.address
  );
  // add to timelock exclusion if not added yet
  if (isTimelockExcluded === false) {
    console.log(
      "Setting timelock exclusion for NFTXRouter on positionManager..."
    );
    await execute(
      "NonfungiblePositionManager",
      { from: deployer },
      "setTimelockExcluded",
      nftxRouter.address,
      true
    );
    console.log("Timelock exclusion set for NFTXRouter on positionManager");
  }

  return {
    nftxRouter: nftxRouter.address,
    uniswapFactory,
    inventoryStaking,
    vaultFactory,
    swapRouter: swapRouter.address,
  };
};
