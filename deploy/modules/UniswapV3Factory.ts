import { HardhatRuntimeEnvironment } from "hardhat/types";
import {
  executeOwnableFunction,
  getConfig,
  getContract,
  getDeployment,
  handleUpgradeDeploy,
} from "../utils";

// deploys UniswapV3Factory along with UniswapV3Pool
export const deployUniswapV3Factory = async ({
  hre,
}: {
  hre: HardhatRuntimeEnvironment;
}) => {
  const { deploy, execute, deployments, deployer, config } = await getConfig(
    hre
  );

  const prevPoolImpl = await getDeployment(hre, "UniswapV3PoolUpgradeable");

  const poolImpl = await deploy("UniswapV3PoolUpgradeable", {
    from: deployer,
    log: true,
  });

  const uniswapFactory = await handleUpgradeDeploy({
    hre,
    contractName: "UniswapV3FactoryUpgradeable",
    deployOptions: {
      from: deployer,
      proxy: {
        proxyContract: "OpenZeppelinTransparentProxy",
        execute: {
          init: {
            methodName: "__UniswapV3FactoryUpgradeable_init",
            args: [poolImpl.address, config.REWARD_TIER_CARDINALITY],
          },
        },
      },
      log: true,
    },
  });

  // => check if new pool implementation was deployed for upgrade
  if (prevPoolImpl && prevPoolImpl.address !== poolImpl.address) {
    // => upgrade

    // == update states ==
    // set new pool implementation in UniswapV3Factory
    await executeOwnableFunction({
      hre,
      contractName: "UniswapV3FactoryUpgradeable",
      contractAddress: uniswapFactory.address,
      functionName: "upgradeBeaconTo",
      functionArgs: [poolImpl.address],
    });
  }

  return { uniswapFactory: uniswapFactory.address, poolImpl: poolImpl.address };
};
