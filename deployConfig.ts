const config: {
  [networkName: string]: {
    treasury: string;
    WETH: string;
    REWARD_TIER_CARDINALITY: string;
    permit2: string;
    nftxUniversalRouter: string;
  };
} = {
  goerli: {
    treasury: "0x000000000000000000000000000000000000dEaD",
    WETH: "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6",
    REWARD_TIER_CARDINALITY: "75",
    permit2: "0x000000000022d473030f116ddee9f6b43ac78ba3",
    nftxUniversalRouter: "0x9a9ac6e79E7750d6cFb847971370574Ca3CcB8e9",
  },
  mainnet: {
    treasury: "0x40D73Df4F99bae688CE3C23a01022224FE16C7b2",
    WETH: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    REWARD_TIER_CARDINALITY: "102",
    permit2: "0x000000000022d473030f116ddee9f6b43ac78ba3",
    nftxUniversalRouter: "0x000000000000000000000000000000000000dEaD", // FIXME: set valid address
  },
  arbitrum: {
    treasury: "0x000000000000000000000000000000000000dEaD",
    WETH: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
    REWARD_TIER_CARDINALITY: "75",
    permit2: "0x000000000022d473030f116ddee9f6b43ac78ba3",
    nftxUniversalRouter: "0x000000000000000000000000000000000000dEaD", // FIXME: set valid address
  },
};

export default config;
