import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { deployShutdownRedeemer } from "./modules/ShutdownRedeemer";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { shutdownRedeemer } = await deployShutdownRedeemer({
    hre,
  });
};
export default func;
func.tags = ["ShutdownRedeemer"];
func.dependencies = [];
