import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getConfig } from "../utils";

export const deployRescueAidrop = async ({
  hre,
}: {
  hre: HardhatRuntimeEnvironment;
}) => {
  const { deploy, deployer } = await getConfig(hre);

  const rescueAirdropImpl = await deploy("RescueAirdropUpgradeable", {
    from: deployer,
    args: [],
    log: true,
  });

  return {
    rescueAirdropImpl: rescueAirdropImpl.address,
  };
};
