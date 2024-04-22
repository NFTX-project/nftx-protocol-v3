import * as fs from "fs";

// Define the path of your files
const jsonFilePath = "./addresses.json";
const baseMarkdownFilePath = "./script/base-README.md";
const outputMarkdownFilePath = "./README.md";

const baseExplorerURLs = {
  mainnet: "https://etherscan.io/address/",
  arbitrum: "https://arbiscan.io/address/",
  base: "https://basescan.org/address/",
  sepolia: "https://sepolia.etherscan.io/address/",
  goerli: "https://goerli.etherscan.io/address/",
};

// URLs for each contract
const contractURLs = {
  CreateVaultZap: "./src/zaps/CreateVaultZap.sol",
  FailSafe: "./src/FailSafe.sol",
  MarketplaceUniversalRouterZap: "./src/zaps/MarketplaceUniversalRouterZap.sol",
  MigratorZap: "./src/zaps/MigratorZap.sol",
  NFTXEligibilityManager: "./src/v2/NFTXEligibilityManager.sol",
  NFTXFeeDistributorV3: "./src/NFTXFeeDistributorV3.sol",
  NFTXInventoryStakingV3Upgradeable:
    "./src/NFTXInventoryStakingV3Upgradeable.sol",
  NFTXRouter: "./src/NFTXRouter.sol",
  nftxUniversalRouter:
    "https://github.com/NFTX-project/nftx-universal-router/blob/nftx-universal-router/contracts/UniversalRouter.sol",
  NFTXVaultFactoryUpgradeableV3: "./src/NFTXVaultFactoryUpgradeableV3.sol",
  NonfungiblePositionManager:
    "./src/uniswap/v3-periphery/NonfungiblePositionManager.sol",
  permit2: "https://github.com/Uniswap/permit2/blob/main/src/Permit2.sol",
  QuoterV2: "./src/uniswap/v3-periphery/lens/QuoterV2.sol",
  ShutdownRedeemerUpgradeable: "./src/ShutdownRedeemerUpgradeable.sol",
  SwapRouter: "./src/uniswap/v3-periphery/SwapRouter.sol",
  TickLens: "./src/uniswap/v3-periphery/lens/TickLens.sol",
  UniswapV3FactoryUpgradeable:
    "./src/uniswap/v3-core/UniswapV3FactoryUpgradeable.sol",
  UniswapV3Staker: "https://github.com/Uniswap/v3-staker",
  V3MigrateSwap: "./src/V3MigrateSwap.sol",
  WETH: "https://vscode.blockscan.com/ethereum/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
};

// Function to generate markdown table
function generateMarkdownTable(data: any): string {
  const networks = Object.keys(data);
  const contracts = Array.from(
    new Set(networks.flatMap((network) => Object.keys(data[network])))
  );

  // Prepare headers
  const headerRow = ["Contract", ...networks].join(" | ");
  const separatorRow = ["---", ...networks.map(() => "---")].join(" | ");

  // Prepare rows
  const rows = contracts.map((contract) => {
    const contractLink = contractURLs[contract]
      ? `[${contract}](${contractURLs[contract]})`
      : contract;
    const row = networks.map((network) => {
      const address = data[network][contract];
      return address
        ? `[${address}](${baseExplorerURLs[network] + address + "#code"})`
        : "N/A";
    });
    return [contractLink, ...row].join(" | ");
  });

  return [headerRow, separatorRow, ...rows].join("\n");
}

// Function to replace placeholder in base markdown with table
function replacePlaceholderWithTable(
  baseContent: string,
  table: string
): string {
  return baseContent.replace("[addresses-table]", table);
}

// Read JSON file and generate markdown table
fs.readFile(jsonFilePath, { encoding: "utf8" }, (err, jsonString) => {
  if (err) {
    console.error("Error reading file:", err);
    return;
  }

  try {
    const data = JSON.parse(jsonString);
    const markdownTable = generateMarkdownTable(data);

    // Read the base markdown file
    fs.readFile(
      baseMarkdownFilePath,
      { encoding: "utf8" },
      (err, baseContent) => {
        if (err) {
          console.error("Error reading base markdown file:", err);
          return;
        }

        // Replace the placeholder with the table
        const outputContent = replacePlaceholderWithTable(
          baseContent,
          markdownTable
        );

        // Write the output to a new markdown file
        fs.writeFile(outputMarkdownFilePath, outputContent, (err) => {
          if (err) {
            console.error("Error writing output markdown file:", err);
          } else {
            console.log(
              `Output markdown created successfully at ${outputMarkdownFilePath}`
            );
          }
        });
      }
    );
  } catch (err) {
    console.error("Error parsing JSON string:", err);
  }
});
