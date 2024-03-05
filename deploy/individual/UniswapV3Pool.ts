import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { getConfig, getContract } from "../utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy, execute, deployer, deployments } = await getConfig(hre);

  const poolImpl = await deploy("UniswapV3PoolUpgradeable", {
    from: deployer,
    log: true,
  });

  // ==
  const uniswapFactory = await deployments.get("UniswapV3FactoryUpgradeable");
  const uniswapFactoryContract = await getContract(
    hre,
    "UniswapV3FactoryUpgradeable",
    uniswapFactory.address
  );
  const owner = await uniswapFactoryContract.owner();
  if (owner === deployer) {
    console.log("Setting new Pool Impl in UniswapV3Factory...");
    await execute(
      "UniswapV3FactoryUpgradeable",
      { from: deployer },
      "upgradeBeaconTo",
      poolImpl.address
    );
    console.log("New Pool Impl set in UniswapV3Factory");
  } else {
    console.warn(
      "[⚠️ NOTE!] call upgradeBeaconTo on UniswapV3FactoryUpgradeable to set the new Pool Impl"
    );
  }
};
export default func;
func.tags = ["UniswapV3Pool"];
