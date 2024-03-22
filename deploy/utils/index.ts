import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployOptions, Deployment } from "hardhat-deploy/types";
import { promises as fs } from "fs";
import path from "path";
import { format } from "prettier";
import { keccak256, toUtf8Bytes, defaultAbiCoder } from "ethers/lib/utils";
import deployConfig from "../deployConfig";
import { Contract } from "ethers";

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
  // making optional for querying DefaultProxyAdmin
  contractAddress?: string
) => {
  // this fails to read "DefaultProxyAdmin":
  /** 
  const { deployments } = hre;
  const artifact = await deployments.getArtifact(contractName);
  const contractFactory = await hre.ethers.getContractFactory(
    artifact.abi,
    artifact.bytecode
  );
  const contract = contractFactory.attach(contractAddress);
  */

  const contractDeployment = await getDeploymentFileByName(
    contractName,
    hre.network
  );
  const contract = (
    await hre.ethers.getContractFactory(
      contractDeployment.abi,
      contractDeployment.bytecode
    )
  ).attach(contractAddress ?? contractDeployment.address);

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
}): Promise<Deployment> => {
  const { deploy, network, deployments } = await getConfig(hre);

  let defaultProxyAdminContract: Contract | undefined;
  try {
    // if the DefaultProxyAdmin is already deployed
    defaultProxyAdminContract = await getContract(hre, "DefaultProxyAdmin");
    // set the current owner of the proxy, in the deployOptions
    deployOptions.proxy = {
      ...(typeof deployOptions.proxy === "object" ? deployOptions.proxy : {}),
      owner: await defaultProxyAdminContract.owner(),
    };
  } catch {}

  let deployment: Deployment | undefined = undefined;
  try {
    deployment = await deploy(contractName, deployOptions);
  } catch (e) {
    // update the deployment file for correct implementation address
    await setImplementation(contractName, network);
    deployment = await deployments.get(contractName);

    console.warn(
      `[⚠️ NOTE!] call "upgrade" on DefaultProxyAdmin to upgrade the implementation for ${contractName}`
    );
  }

  return deployment;
};

const getEIP1967ProxyOwner = async (
  hre: HardhatRuntimeEnvironment,
  contractName: string
) => {
  const khash = keccak256(toUtf8Bytes(`eip1967.proxy.admin`));
  const num = BigInt(khash);
  const storageSlot = num - BigInt(1);

  const provider = hre.ethers.provider;
  const res = await provider.getStorageAt(contractName, storageSlot);

  const owner: string = defaultAbiCoder.decode(["address"], res)[0];
  console.log({ owner });

  return owner;
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
    path.join(
      __dirname,
      `../../deployments/${network.name}/${contractName}.json`
    ),
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
      path.join(
        __dirname,
        `../../deployments/${network.name}/${fileName}.json`
      ),
      "utf8"
    )
  );
};
