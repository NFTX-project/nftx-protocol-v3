import { promises as fs } from "fs";
import prettier from "prettier";
import deployConfig from "../deploy/deployConfig";

// alphabetical order
const deploymentsList = [
  "CreateVaultZap",
  "DefaultProxyAdmin",
  "MarketplaceUniversalRouterZap",
  "MigratorZap",
  "NFTXEligibilityManager",
  "NFTXFeeDistributorV3",
  "NFTXInventoryStakingV3Upgradeable",
  "NFTXRouter",
  "NFTXVaultFactoryUpgradeableV3",
  "NonfungiblePositionManager",
  "QuoterV2",
  "SwapRouter",
  "TickLens",
  "UniswapV3FactoryUpgradeable",
];
const deployConfigKeysList = ["nftxUniversalRouter", "permit2", "WETH"];

const chains = ["mainnet", "sepolia", "goerli"];

const main = async () => {
  console.log("Generating addresses.json...");

  let output: {
    [chain: string]: { [label: string]: string };
  } = {};

  // as we are using Promise all here, so the order of the chains might not be maintained
  await Promise.all(
    chains.map(async (chain) => {
      output[chain] = await addressesForChain(chain);
    })
  );

  let orderedOutput: { [chain: string]: { [label: string]: string } } = {};
  chains.forEach((chain) => {
    orderedOutput[chain] = output[chain];
  });

  const formattedJson = prettier.format(JSON.stringify(orderedOutput), {
    parser: "json",
  });

  await fs.writeFile("./addresses.json", formattedJson);
};

const addressesForChain = async (chain: string) => {
  let res: { [label: string]: string } = {};

  for (var i = 0; i < deploymentsList.length; i++) {
    try {
      const data = JSON.parse(
        await fs.readFile(
          `./deployments/${chain}/${deploymentsList[i]}.json`,
          "utf8"
        )
      ) as { address: string };

      res[deploymentsList[i]] = data.address;
    } catch (e) {
      res[deploymentsList[i]] = "";
    }
  }
  deployConfigKeysList.map((k) => {
    // @ts-ignore
    res[k] = deployConfig[chain][k];
  });

  // make output alphabetical
  res = Object.keys(res)
    .sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()))
    .reduce((obj, key) => {
      // @ts-ignore
      obj[key] = res[key];
      return obj;
    }, {});

  return res;
};
main();
