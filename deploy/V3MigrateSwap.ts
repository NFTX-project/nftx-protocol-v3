import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { deployV3MigrateSwap } from "./modules/V3MigrateSwap";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { v3MigrateSwap } = await deployV3MigrateSwap({
    hre,
  });
};
export default func;
func.tags = ["V3MigrateSwap"];
func.dependencies = [];
