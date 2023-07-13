import { promises as fs } from "fs";
import prettier from "prettier";
import deployConfig from "../deployConfig";

// alphabetical order
const deploymentsList = [
  "CreateVaultZap",
  "MarketplaceUniversalRouterZap",
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

const main = async () => {
  console.log("Generating addresses.json...");

  let output: {
    goerli: { [label: string]: string };
  } = {
    goerli: {},
  };

  // TODO: add for mainnet
  for (var i = 0; i < deploymentsList.length; i++) {
    const data = JSON.parse(
      await fs.readFile(
        `./deployments/goerli/${deploymentsList[i]}.json`,
        "utf8"
      )
    ) as { address: string };

    output.goerli[deploymentsList[i]] = data.address;
  }
  deployConfigKeysList.map((k) => {
    // @ts-ignore
    output.goerli[k] = deployConfig["goerli"][k];
  });

  // make output alphabetical
  output.goerli = Object.keys(output.goerli)
    .sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()))
    .reduce((obj, key) => {
      // @ts-ignore
      obj[key] = output.goerli[key];
      return obj;
    }, {});

  const formattedJson = prettier.format(JSON.stringify(output), {
    parser: "json",
  });

  await fs.writeFile("./addresses.json", formattedJson);
};

main();
