import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getConfig } from "../utils";

export const deployUniswapV3Factory = async (
  hre: HardhatRuntimeEnvironment
) => {
  const { deploy, deployer, config } = await getConfig(hre);

  const poolImpl = await deploy("UniswapV3PoolUpgradeable", {
    from: deployer,
    log: true,
  });

  const factory = await deploy("UniswapV3FactoryUpgradeable", {
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
  });

  return factory.address;
};
