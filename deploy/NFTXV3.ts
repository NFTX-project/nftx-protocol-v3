import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { utils } from "ethers";
import deployConfig from "../deployConfig";
import { deployNFTXV3Core } from "./modules/FeeDistributor";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  await deployNFTXV3Core(hre);
};
export default func;
func.tags = ["NFTXV3"];
func.dependencies = [];
