import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, execute } = deployments;

  const { deployer } = await getNamedAccounts();

  const nft = await deploy("MockRoyaltyNFT", {
    args: [
      "CryptoPunks",
      "CryptoPunks",
      "https://ipfs.io/ipfs/QmcsX1EprrBwjPRT7dyDWvmGX7zvcRsmKKDaMTiFbSsZh2/",
    ],
    from: deployer,
    log: true,
  });
  await deploy("MockRoyaltyNFT", {
    args: [
      "Milady Maker",
      "Milady Maker",
      "https://www.miladymaker.net/milady/json/",
    ],
    from: deployer,
    log: true,
  });
  await deploy("MockRoyaltyNFT", {
    args: [
      "BoredApe",
      "BoredApe",
      "https://ipfs.io/ipfs/QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq/",
    ],
    from: deployer,
    log: true,
  });

  const nft1155 = await deploy("MockRoyalty1155", {
    from: deployer,
    log: true,
  });
};
export default func;
func.tags = ["Mocks"];
func.dependencies = [];
