import { HardhatRuntimeEnvironment } from "hardhat/types";
import { executeOwnableFunction, getConfig, getContract } from "../utils";

export const deployMarketplaceZap = async ({
  hre,
  vaultFactory,
  inventoryStaking,
}: {
  hre: HardhatRuntimeEnvironment;
  vaultFactory: string;
  inventoryStaking: string;
}) => {
  const { deploy, deployer, config } = await getConfig(hre);

  const marketplaceZap = await deploy("MarketplaceUniversalRouterZap", {
    from: deployer,
    args: [
      vaultFactory,
      config.nftxUniversalRouter,
      config.permit2,
      inventoryStaking,
      config.WETH,
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
    marketplaceZap.address
  );
  // => 1. add to fee exclusion if not added yet
  if (isExcludedFromFees === false) {
    await executeOwnableFunction({
      hre,
      contractName: "NFTXVaultFactoryUpgradeableV3",
      contractAddress: vaultFactory,
      functionName: "setFeeExclusion",
      functionArgs: [marketplaceZap.address, true],
    });
  }

  return {
    marketplaceZap: marketplaceZap.address,
  };
};
