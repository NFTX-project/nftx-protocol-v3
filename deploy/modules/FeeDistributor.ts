import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getConfig, getContract } from "../utils";
import { constants } from "ethers";
import { deployNFTXRouter } from "./NFTXRouter";

// note: deploys all NFTXV3 core contracts
export const deployFeeDistributor = async (hre: HardhatRuntimeEnvironment) => {
  const { deploy, execute, deployer, config } = await getConfig(hre);

  const { nftxRouter, uniswapFactory, inventoryStaking, vaultFactory } =
    await deployNFTXRouter(hre);

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

  const uniswapFactoryContract = await getContract(
    hre,
    "UniswapV3FactoryUpgradeable",
    uniswapFactory
  );
  const feeDistributorAddress = await uniswapFactoryContract.feeDistributor();
  // if feeDistributor is not set yet in UniswapV3Factory
  if (feeDistributorAddress === constants.AddressZero) {
    console.log("Setting FeeDistributor in UniV3Factory...");
    await execute(
      "UniswapV3FactoryUpgradeable",
      { from: deployer },
      "setFeeDistributor",
      feeDistributor.address
    );
    console.log("Set FeeDistributor in UniV3Factory");
  }

  const vaultFactoryContract = await getContract(
    hre,
    "NFTXVaultFactoryUpgradeableV3",
    vaultFactory
  );
  const feeDistributorAddressInVaultFactory =
    await vaultFactoryContract.feeDistributor();
  // if feeDistributor is not set yet in NFTXVaultFactory
  if (feeDistributorAddressInVaultFactory === constants.AddressZero) {
    console.log("Setting FeeDistributor in NFTXVaultFactory...");
    await execute(
      "NFTXVaultFactoryUpgradeableV3",
      { from: deployer },
      "setFeeDistributor",
      feeDistributor.address
    );
    console.log("Set FeeDistributor in NFTXVaultFactory");
  }

  return {
    feeDistributor,
    nftxRouter,
    uniswapFactory,
    inventoryStaking,
    vaultFactory,
  };
};

export const deployNFTXV3Core = async (hre: HardhatRuntimeEnvironment) => {
  return await deployFeeDistributor(hre);
};
