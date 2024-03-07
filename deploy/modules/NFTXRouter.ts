import { HardhatRuntimeEnvironment } from "hardhat/types";
import {
  executeOwnableFunction,
  getConfig,
  getContract,
  getDeployment,
} from "../utils";

// deploys NFTXRouter
export const deployNFTXRouter = async ({
  hre,
  vaultFactory,
  inventoryStaking,
  positionManager,
  swapRouter,
  quoter,
}: {
  hre: HardhatRuntimeEnvironment;
  vaultFactory: string;
  inventoryStaking: string;
  positionManager: string;
  swapRouter: string;
  quoter: string;
}) => {
  const { deploy, execute, deployments, deployer, config } = await getConfig(
    hre
  );

  const prevNFTXRouter = await getDeployment(hre, "NFTXRouter");

  const nftxRouter = await deploy("NFTXRouter", {
    from: deployer,
    args: [
      positionManager,
      swapRouter,
      quoter,
      vaultFactory,
      config.permit2,
      config.lpTimelock,
      config.lpEarlyWithdrawPenaltyInWei,
      config.nftxRouterVTokenDustThreshold,
      inventoryStaking,
    ],
    log: true,
  });

  // == set states ==
  const vaultFactoryContract = await getContract(
    hre,
    "NFTXVaultFactoryUpgradeableV3",
    vaultFactory
  );
  const isExcludedFromFees = await vaultFactoryContract.excludedFromFees(
    nftxRouter.address
  );
  // => 1. add to fee exclusion if not added yet
  if (isExcludedFromFees === false) {
    // NFTXRouter has in-built fee handling
    await executeOwnableFunction({
      hre,
      contractName: "NFTXVaultFactoryUpgradeableV3",
      contractAddress: vaultFactory,
      functionName: "setFeeExclusion",
      functionArgs: [nftxRouter.address, true],
    });
  }

  const positionManagerContract = await getContract(
    hre,
    "NonfungiblePositionManager",
    positionManager
  );
  const isTimelockExcluded = await positionManagerContract.timelockExcluded(
    nftxRouter.address
  );
  // => 2. add to timelock exclusion if not added yet
  if (isTimelockExcluded === false) {
    await executeOwnableFunction({
      hre,
      contractName: "NonfungiblePositionManager",
      contractAddress: positionManager,
      functionName: "setTimelockExcluded",
      functionArgs: [nftxRouter.address, true],
    });
  }

  // => check if new NFTXRouter was deployed for upgrade
  if (prevNFTXRouter && prevNFTXRouter.address !== nftxRouter.address) {
    // => upgrade

    // == update states ==
    // => 3. set new NFTXRouter in FeeDistributor

    // @note getting FeeDistributor's from deployments, and not from params because for normal deployments the feeDistributor is deployed at last
    // this case is for the upgrade:
    const feeDistributor = await deployments.get("NFTXFeeDistributorV3");
    await executeOwnableFunction({
      hre,
      contractName: "NFTXFeeDistributorV3",
      contractAddress: feeDistributor.address,
      functionName: "setNFTXRouter",
      functionArgs: [nftxRouter.address],
    });
  }

  return {
    nftxRouter: nftxRouter.address,
  };
};
