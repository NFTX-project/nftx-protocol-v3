import { HardhatRuntimeEnvironment } from "hardhat/types";
import deployConfig from "../../deployConfig";

export const getConfig = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, execute } = deployments;

  const { deployer } = await getNamedAccounts();
  const config = deployConfig[network.name];

  return {
    deploy,
    execute,
    deployer,
    config,
    deployments,
  };
};

export const getContract = async (
  hre: HardhatRuntimeEnvironment,
  contractName: string,
  contractAddress: string
) => {
  const { deployments } = hre;

  const artifact = await deployments.getArtifact(contractName);
  const contractFactory = await hre.ethers.getContractFactory(
    artifact.abi,
    artifact.bytecode
  );
  const contract = contractFactory.attach(contractAddress);
  return contract;
};
