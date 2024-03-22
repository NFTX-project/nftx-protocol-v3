import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getConfig, handleUpgradeDeploy } from "../utils";

export const deployShutdownRedeemer = async ({
  hre,
}: {
  hre: HardhatRuntimeEnvironment;
}) => {
  const { deployer, config } = await getConfig(hre);

  const shutdownRedeemer = await handleUpgradeDeploy({
    hre,
    contractName: "ShutdownRedeemerUpgradeable",
    deployOptions: {
      from: deployer,
      args: [config.v2VaultFactory],
      proxy: {
        proxyContract: "OpenZeppelinTransparentProxy",
        execute: {
          init: {
            methodName: "__ShutdownRedeemer_init",
            args: [],
          },
        },
      },
      log: true,
    },
  });

  return {
    shutdownRedeemer: shutdownRedeemer.address,
  };
};
