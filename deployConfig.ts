import { utils, BigNumber } from "ethers";

const commonConfig: {
  rewardFeeTier: number;
  twapInterval: number;
  premiumDuration: number;
  premiumMax: BigNumber;
  depositorPremiumShare: BigNumber;
  inventoryTimelock: number;
  inventoryEarlyWithdrawPenaltyInWei: BigNumber;
  lpTimelock: number;
  lpEarlyWithdrawPenaltyInWei: BigNumber;
  nftxRouterVTokenDustThreshold: BigNumber;
} = {
  rewardFeeTier: 3_000, // 0.3%
  twapInterval: 20 * 60, // 20 mins
  premiumDuration: 10 * 60 * 60, // 10 hrs
  premiumMax: utils.parseEther("5"), // 5 ether = 5x premium
  depositorPremiumShare: utils.parseEther("0.90"), // 0.90 ether = 90% to original depositor, 10% to the stakers
  lpTimelock: 48 * 60 * 60, // 48 hrs
  inventoryTimelock: 72 * 60 * 60, // 72 hrs
  inventoryEarlyWithdrawPenaltyInWei: utils.parseEther("0.10"), // 0.10 ether = 10%
  lpEarlyWithdrawPenaltyInWei: utils.parseEther("0.10"), // 0.10 ether = 10%
  nftxRouterVTokenDustThreshold: utils.parseEther("0.05"),
};

const config: {
  [networkName: string]: {
    treasury: string;
    WETH: string;
    REWARD_TIER_CARDINALITY: string;
    permit2: string;
    nftxUniversalRouter: string;
    v2VaultFactory: string;
    v2Inventory: string;
    sushiRouter: string;
    rewardFeeTier: number;
    twapInterval: number;
    premiumDuration: number;
    premiumMax: BigNumber;
    depositorPremiumShare: BigNumber;
    inventoryTimelock: number;
    inventoryEarlyWithdrawPenaltyInWei: BigNumber;
    lpTimelock: number;
    lpEarlyWithdrawPenaltyInWei: BigNumber;
    nftxRouterVTokenDustThreshold: BigNumber;
    multisig?: string;
  };
} = {
  goerli: {
    ...commonConfig,
    treasury: "0xb06a64615842CbA9b3Bdb7e6F726F3a5BD20daC2",
    WETH: "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6",
    REWARD_TIER_CARDINALITY: "75",
    permit2: "0x000000000022d473030f116ddee9f6b43ac78ba3",
    nftxUniversalRouter: "0xF7c4FC5C2e30258e1E4d1197fc63aeDE371508f3", // NOTE: update this if new UniswapV3Factory deployed.
    v2VaultFactory: "0x1478bEB5D18B23d2bA90FcEe91d66460AC585e6b",
    v2Inventory: "0x6e91A3f27cE6753f47C66B76B03E6A7bFdDB605B",
    sushiRouter: "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506",
    // MODIFIED for testnet
    premiumDuration: 10 * 60, // 10 mins
    lpTimelock: 10 * 60, // 10 mins
    inventoryTimelock: 10 * 60, // 10 mins
  },
  sepolia: {
    ...commonConfig,
    treasury: "0xb06a64615842CbA9b3Bdb7e6F726F3a5BD20daC2",
    WETH: "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14",
    REWARD_TIER_CARDINALITY: "102",
    permit2: "0x000000000022d473030f116ddee9f6b43ac78ba3",
    nftxUniversalRouter: "0x12156cCA1958B6591CC49EaE03a5553458a4b424", // NOTE: update this if new UniswapV3Factory deployed.
    v2VaultFactory: "0xE77b89FEc41A7b7dC74eb33602e82F0672FbB33C",
    v2Inventory: "0x2724f135e00a1078BC003D093D94Cc3718F6F591",
    sushiRouter: "0xEa8D67a95E1172718CbD601F0742B2ba4E45bC7C",
    // MODIFIED for testnet
    premiumDuration: 10 * 60, // 10 mins
    lpTimelock: 10 * 60, // 10 mins
    inventoryTimelock: 10 * 60, // 10 mins
  },
  mainnet: {
    ...commonConfig,
    treasury: "0x40D73Df4F99bae688CE3C23a01022224FE16C7b2",
    WETH: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    REWARD_TIER_CARDINALITY: "102",
    permit2: "0x000000000022d473030f116ddee9f6b43ac78ba3",
    nftxUniversalRouter: "0x250d62a67254A46c0De472d2c9215E1d890cC90f", // NOTE: update this if new UniswapV3Factory deployed.
    v2VaultFactory: "0xBE86f647b167567525cCAAfcd6f881F1Ee558216",
    v2Inventory: "0x3E135c3E981fAe3383A5aE0d323860a34CfAB893",
    sushiRouter: "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F",
    multisig: "0xaA29881aAc939A025A3ab58024D7dd46200fB93D",
  },
  arbitrum: {
    ...commonConfig,
    treasury: "0x000000000000000000000000000000000000dEaD", // FIXME: set valid address
    WETH: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
    REWARD_TIER_CARDINALITY: "75",
    permit2: "0x000000000022d473030f116ddee9f6b43ac78ba3",
    nftxUniversalRouter: "0x000000000000000000000000000000000000dEaD", // FIXME: set valid address
    v2VaultFactory: "0xE77b89FEc41A7b7dC74eb33602e82F0672FbB33C",
    v2Inventory: "0x1A2C03ABD4Af7C87d8b4d5aD39b56fa98E8C4Cc6",
    sushiRouter: "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506",
  },
};

export default config;
