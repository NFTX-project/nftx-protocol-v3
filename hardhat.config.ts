import dotenv from "dotenv";
dotenv.config();
import { parseEther } from "@ethersproject/units";

import { HardhatUserConfig } from "hardhat/types";
import "@typechain/hardhat";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";
import "hardhat-deploy";
import "hardhat-deploy-ethers";
import "hardhat-abi-exporter";
import "hardhat-tracer";
import "@nomicfoundation/hardhat-foundry";
import "hardhat-contract-sizer";

const DEFAULT_COMPILER_SETTINGS = {
  version: "0.8.15",
  settings: {
    optimizer: {
      enabled: true,
      runs: 800,
    },
    metadata: {
      bytecodeHash: "none",
    },
  },
};

const LOW_OPTIMIZER_COMPILER_SETTINGS = {
  version: "0.8.15",
  settings: {
    optimizer: {
      enabled: true,
      runs: 2_000,
    },
    metadata: {
      bytecodeHash: "none",
    },
  },
};

const LOWEST_OPTIMIZER_COMPILER_SETTINGS = {
  version: "0.8.15",
  settings: {
    viaIR: true,
    optimizer: {
      enabled: true,
      runs: 1_000,
    },
    metadata: {
      bytecodeHash: "none",
    },
  },
};

const UNICORE_OPTIMIZER_COMPILER_SETTINGS = {
  version: "0.8.15",
  settings: {
    optimizer: {
      enabled: true,
      runs: 380,
    },
    metadata: {
      bytecodeHash: "none",
    },
  },
};

const config: HardhatUserConfig = {
  solidity: {
    compilers: [DEFAULT_COMPILER_SETTINGS],
    overrides: {
      "src/uniswap/v3-core/UniswapV3FactoryUpgradeable.sol":
        UNICORE_OPTIMIZER_COMPILER_SETTINGS,
      "src/uniswap/v3-core/UniswapV3Pool.sol":
        UNICORE_OPTIMIZER_COMPILER_SETTINGS,
      "src/uniswap/v3-core/UniswapV3PoolDeployer.sol":
        UNICORE_OPTIMIZER_COMPILER_SETTINGS,
      "src/uniswap/v3-periphery/NonfungiblePositionManager.sol":
        LOW_OPTIMIZER_COMPILER_SETTINGS,
      "src/uniswap/v3-periphery/test/MockTimeNonfungiblePositionManager.sol":
        LOW_OPTIMIZER_COMPILER_SETTINGS,
      "src/uniswap/v3-periphery/test/NFTDescriptorTest.sol":
        LOWEST_OPTIMIZER_COMPILER_SETTINGS,
      "src/uniswap/v3-periphery/NonfungibleTokenPositionDescriptor.sol":
        LOWEST_OPTIMIZER_COMPILER_SETTINGS,
      "src/uniswap/v3-periphery/libraries/NFTDescriptor.sol":
        LOWEST_OPTIMIZER_COMPILER_SETTINGS,
      "src/uniswap/v3-periphery/libraries/NFTSVG.sol":
        LOWEST_OPTIMIZER_COMPILER_SETTINGS,
    },
  },
  namedAccounts: {
    deployer: 0,
  },
  defaultNetwork: "hardhat",
  networks: {
    local: {
      url: "http://127.0.0.1:8545",
      accounts: [process.env.DEPLOYER_PRIVATE_KEY!],
    },
    hardhat: {
      forking: {
        url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_MAINNET_API_KEY}`,
      },
      accounts: [
        {
          privateKey: process.env.DEPLOYER_PRIVATE_KEY!,
          balance: parseEther("100").toString(),
        },
      ],
    },
    goerli: {
      url: `https://eth-goerli.alchemyapi.io/v2/${process.env.ALCHEMY_GOERLI_API_KEY}`,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY!],
    },
    mainnet: {
      url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_MAINNET_API_KEY}`,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY!],
      timeout: 60000,
    },
    arbitrum: {
      url: `https://arb-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_ARBITRUM_API_KEY}`,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY!],
      timeout: 60000,
      verify: {
        etherscan: {
          apiKey: process.env.ARBISCAN_API_KEY,
          apiUrl: "https://api.arbiscan.io/",
        },
      },
    },
  },
  mocha: {
    timeout: 200000,
  },
  paths: {
    sources: "src",
    cache: "cache/hh",
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: true,
    strict: true,
  },
};

export default config;
