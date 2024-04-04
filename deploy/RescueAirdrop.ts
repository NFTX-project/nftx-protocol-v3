import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { deployRescueAidrop } from "./modules/RescueAirdrop";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { rescueAirdropImpl } = await deployRescueAidrop({
    hre,
  });
};
export default func;
func.tags = ["RescueAirdrop"];
func.dependencies = [];
