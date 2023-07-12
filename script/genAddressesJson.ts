import { promises as fs } from "fs";
import prettier from "prettier";

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

  const formattedJson = prettier.format(JSON.stringify(output), {
    parser: "json",
  });

  await fs.writeFile("./addresses.json", formattedJson);
};

main();
