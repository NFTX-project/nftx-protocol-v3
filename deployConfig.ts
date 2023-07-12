import { utils, BigNumber } from "ethers";

const commonConfig: {
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
    twapInterval: number;
    premiumDuration: number;
    premiumMax: BigNumber;
    depositorPremiumShare: BigNumber;
    inventoryTimelock: number;
    inventoryEarlyWithdrawPenaltyInWei: BigNumber;
    lpTimelock: number;
    lpEarlyWithdrawPenaltyInWei: BigNumber;
    nftxRouterVTokenDustThreshold: BigNumber;
  };
} = {
  goerli: {
    treasury: "0xb06a64615842CbA9b3Bdb7e6F726F3a5BD20daC2",
    WETH: "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6",
    REWARD_TIER_CARDINALITY: "75",
    permit2: "0x000000000022d473030f116ddee9f6b43ac78ba3",
    nftxUniversalRouter: "0x9a9ac6e79E7750d6cFb847971370574Ca3CcB8e9",
    ...commonConfig,
  },
  mainnet: {
    treasury: "0x40D73Df4F99bae688CE3C23a01022224FE16C7b2",
    WETH: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    REWARD_TIER_CARDINALITY: "102",
    permit2: "0x000000000022d473030f116ddee9f6b43ac78ba3",
    nftxUniversalRouter: "0x000000000000000000000000000000000000dEaD", // FIXME: set valid address
    ...commonConfig,
  },
  arbitrum: {
    treasury: "0x000000000000000000000000000000000000dEaD", // FIXME: set valid address
    WETH: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
    REWARD_TIER_CARDINALITY: "75",
    permit2: "0x000000000022d473030f116ddee9f6b43ac78ba3",
    nftxUniversalRouter: "0x000000000000000000000000000000000000dEaD", // FIXME: set valid address
    ...commonConfig,
  },
};

export default config;
