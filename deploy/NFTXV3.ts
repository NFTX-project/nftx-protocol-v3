import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { deployVaultFactory } from "./modules/VaultFactory";
import { deployUniswapV3Factory } from "./modules/UniswapV3Factory";
import { deployInventoryStaking } from "./modules/InventoryStaking";
import { deployUniswapV3Periphery } from "./modules/UniswapV3Periphery";
import { deployNFTXRouter } from "./modules/NFTXRouter";
import { deployFeeDistributor } from "./modules/FeeDistributor";
import { deployFailSafe } from "./modules/FailSafe";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { vaultFactory } = await deployVaultFactory({ hre });

  const { inventoryStaking } = await deployInventoryStaking({
    hre,
    vaultFactory,
  });

  const { uniswapFactory } = await deployUniswapV3Factory({
    hre,
  });

  const { positionManager, swapRouter, quoter } =
    await deployUniswapV3Periphery({
      hre,
      uniswapFactory,
    });

  const { nftxRouter } = await deployNFTXRouter({
    hre,
    vaultFactory,
    inventoryStaking,
    positionManager,
    swapRouter,
    quoter,
  });

  const { feeDistributor } = await deployFeeDistributor({
    hre,
    nftxRouter,
    uniswapFactory,
    inventoryStaking,
    vaultFactory,
  });

  const { failSafe } = await deployFailSafe({
    hre,
    inventoryStaking,
    vaultFactory,
    feeDistributor,
    nftxRouter,
  });
};
export default func;
func.tags = ["NFTXV3"];
func.dependencies = [];
