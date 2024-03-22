import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getConfig } from "../utils";

export const deployFailSafe = async ({
  hre,
  inventoryStaking,
  vaultFactory,
  feeDistributor,
  nftxRouter,
}: {
  hre: HardhatRuntimeEnvironment;
  inventoryStaking: string;
  vaultFactory: string;
  feeDistributor: string;
  nftxRouter: string;
}) => {
  const { deploy, deployer } = await getConfig(hre);

  const failSafe = await deploy("FailSafe", {
    args: [
      [
        {
          addr: inventoryStaking,
          lastLockId: 4,
        },
        {
          addr: vaultFactory,
          lastLockId: 0,
        },
        {
          addr: feeDistributor,
          lastLockId: 1,
        },
        {
          addr: nftxRouter,
          lastLockId: 4,
        },
      ],
    ],
    from: deployer,
    log: true,
  });

  return { failSafe: failSafe.address };
};
