import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployOptions, Deployment } from "hardhat-deploy/types";
import { promises as fs } from "fs";
import path from "path";
import { format } from "prettier";
import deployConfig from "../deployConfig";

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
    network,
  };
};

export const getContract = async (
  hre: HardhatRuntimeEnvironment,
  contractName: string,
  // keeping this param and not using deployments.get() because it helps to see the module's dependencies on other contracts
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

export const executeOwnableFunction = async ({
  hre,
  contractName,
  contractAddress,
  functionName,
  functionArgs,
}: {
  hre: HardhatRuntimeEnvironment;
  contractName: string;
  contractAddress: string;
  functionName: string;
  functionArgs: any[];
}) => {
  const { execute, deployer } = await getConfig(hre);

  const contract = await getContract(hre, contractName, contractAddress);
  const owner = await contract.owner();
  if (owner === deployer) {
    console.log(`⌛ Calling ${functionName} on ${contractName}...`);
    await execute(
      contractName,
      { from: deployer },
      functionName,
      ...functionArgs
    );
    console.log(`✅ Called ${functionName} on ${contractName}`);
  } else {
    console.warn(
      `[⚠️ NOTE!] call "${functionName}" on ${contractName} with args: ${JSON.stringify(
        functionArgs
      )}`
    );
  }
};

// @note get deployment without throwing error if not found
export const getDeployment = async (
  hre: HardhatRuntimeEnvironment,
  contractName: string
): Promise<Deployment | undefined> => {
  const { deployments } = await getConfig(hre);

  let deployment: Deployment | undefined = undefined;
  try {
    deployment = await deployments.get(contractName);
  } catch {}

  return deployment;
};

// @note upgrading will fail on mainnet, where the contract is owned by the multisig, instead of the deployer
// so let the following code deploy new implementation. It throws error, so the deployments need to be updated by this function
export const handleUpgradeDeploy = async ({
  hre,
  contractName,
  deployOptions,
}: {
  hre: HardhatRuntimeEnvironment;
  contractName: string;
  deployOptions: DeployOptions;
}): Promise<Deployment | undefined> => {
  const { deploy, network } = await getConfig(hre);

  let deployment: Deployment | undefined = undefined;
  try {
    deployment = await deploy(contractName, deployOptions);
  } catch (e) {
    // update the deployment file for correct implementation address
    await setImplementation(contractName, network);

    console.warn(
      `[⚠️ NOTE!] call "upgrade" on DefaultProxyAdmin to upgrade the implementation for ${contractName}`
    );
  }

  return deployment;
};

export const setImplementation = async (
  contractName: string,
  network: Network
) => {
  const contract = await getDeploymentFileByName(contractName, network);
  const contractImplementation = await getDeploymentFileByName(
    `${contractName}_Implementation`,
    network
  );

  contract.implementation = contractImplementation.address;

  await fs.writeFile(
    path.join(__dirname, `./deployments/${network.name}/${contractName}.json`),
    format(JSON.stringify(contract), {
      semi: false,
      parser: "json",
    })
  );

  return contractImplementation.address;
};

export const getDeploymentFileByName = async (
  fileName: string,
  network: Network
) => {
  return JSON.parse(
    await fs.readFile(
      path.join(__dirname, `./deployments/${network.name}/${fileName}.json`),
      "utf8"
    )
  );
};
