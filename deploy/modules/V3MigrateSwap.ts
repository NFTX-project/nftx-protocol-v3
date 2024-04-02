import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getConfig } from "../utils";

export const deployV3MigrateSwap = async ({
  hre,
}: {
  hre: HardhatRuntimeEnvironment;
}) => {
  const { deploy, deployer } = await getConfig(hre);

  const v3MigrateSwap = await deploy("V3MigrateSwap", {
    from: deployer,
    args: [],
    log: true,
  });

  return {
    v3MigrateSwap: v3MigrateSwap.address,
  };
};
