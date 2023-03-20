const config: {
  [networkName: string]: {
    treasury: string;
  };
} = {
  goerli: {
    treasury: "0x000000000000000000000000000000000000dEaD",
  },
  mainnet: {
    treasury: "0x40D73Df4F99bae688CE3C23a01022224FE16C7b2",
  },
  arbitrum: {
    treasury: "0x000000000000000000000000000000000000dEaD",
  },
};

export default config;
