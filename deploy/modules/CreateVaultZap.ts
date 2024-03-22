import { HardhatRuntimeEnvironment } from "hardhat/types";
import { executeOwnableFunction, getConfig, getContract } from "../utils";

export const deployCreateVaultZap = async ({
  hre,
  vaultFactory,
  nftxRouter,
  uniswapFactory,
  inventoryStaking,
}: {
  hre: HardhatRuntimeEnvironment;
  vaultFactory: string;
  nftxRouter: string;
  uniswapFactory: string;
  inventoryStaking: string;
}) => {
  const { deploy, deployer, config } = await getConfig(hre);

  const createVaultZap = await deploy("CreateVaultZap", {
    from: deployer,
    args: [nftxRouter, uniswapFactory, inventoryStaking],
    log: true,
  });

  // == set states ==
  const vaultFactoryContract = await getContract(
    hre,
    "NFTXVaultFactoryUpgradeableV3",
    vaultFactory
  );
  const isExcludedFromFees = await vaultFactoryContract.excludedFromFees(
    createVaultZap.address
  );
  // => 1. add to fee exclusion if not added yet
  if (isExcludedFromFees === false) {
    await executeOwnableFunction({
      hre,
      contractName: "NFTXVaultFactoryUpgradeableV3",
      contractAddress: vaultFactory,
      functionName: "setFeeExclusion",
      functionArgs: [createVaultZap.address, true],
    });
  }

  return {
    createVaultZap: createVaultZap.address,
  };
};
