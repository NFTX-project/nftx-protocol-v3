import { HardhatRuntimeEnvironment } from "hardhat/types";
import {
  executeOwnableFunction,
  getConfig,
  getContract,
  getDeployment,
} from "../utils";
import { constants } from "ethers";

// deploys feeDistributor
export const deployFeeDistributor = async ({
  hre,
  nftxRouter,
  uniswapFactory,
  inventoryStaking,
  vaultFactory,
}: {
  hre: HardhatRuntimeEnvironment;
  nftxRouter: string;
  uniswapFactory: string;
  inventoryStaking: string;
  vaultFactory: string;
}) => {
  const { deploy, deployer, config } = await getConfig(hre);

  const prevFeeDistributor = await getDeployment(hre, "NFTXFeeDistributorV3");

  const feeDistributor = await deploy("NFTXFeeDistributorV3", {
    from: deployer,
    args: [
      vaultFactory,
      uniswapFactory,
      inventoryStaking,
      nftxRouter,
      config.treasury,
      config.rewardFeeTier,
    ],
    log: true,
  });

  const isNewFeeDistributor =
    prevFeeDistributor && prevFeeDistributor.address !== feeDistributor.address;

  // == set states ==
  const uniswapFactoryContract = await getContract(
    hre,
    "UniswapV3FactoryUpgradeable",
    uniswapFactory
  );
  const feeDistributorAddress = await uniswapFactoryContract.feeDistributor();
  // => 1. if feeDistributor is not set yet in UniswapV3Factory
  // OR new fee distributor was deployed for upgrade
  if (feeDistributorAddress === constants.AddressZero || isNewFeeDistributor) {
    await executeOwnableFunction({
      hre,
      contractName: "UniswapV3FactoryUpgradeable",
      contractAddress: uniswapFactory,
      functionName: "setFeeDistributor",
      functionArgs: [feeDistributor.address],
    });
  }

  const vaultFactoryContract = await getContract(
    hre,
    "NFTXVaultFactoryUpgradeableV3",
    vaultFactory
  );
  const feeDistributorAddressInVaultFactory =
    await vaultFactoryContract.feeDistributor();
  // => 2. if feeDistributor is not set yet in NFTXVaultFactory
  // OR new fee distributor was deployed for upgrade
  if (
    feeDistributorAddressInVaultFactory === constants.AddressZero ||
    isNewFeeDistributor
  ) {
    await executeOwnableFunction({
      hre,
      contractName: "NFTXVaultFactoryUpgradeableV3",
      contractAddress: vaultFactory,
      functionName: "setFeeDistributor",
      functionArgs: [feeDistributor.address],
    });
  }

  return {
    feeDistributor: feeDistributor.address,
  };
};
