# NFTX Protocol V3

<img alt="NFTX Logo" src=".github/nftx-logo.jpg" />

## Overview

NFTX is a platform for creating liquid markets for illiquid Non-Fungible Tokens (NFTs).
<br>
Users deposit their NFT into an NFTX vault to fractionalize and mint a fungible ERC20 token (vToken). This vToken can be redeem back for any NFT from the vault, by paying a redeem fee in ETH.
<br><br>
The vTokens can then be used to earn yield by:<br>

1. Depositing into InventoryStaking to earn ETH (from vault fees) + vTokens (from early withdrawal fees)
2. Pairing the vTokens with ETH and providing concentrated liquidity into the NFTX AMM to earn trading fees and additional ETH (from vault fees).

<hr />

## Contracts

[addresses-table]

## Core Contracts

### 1. NFTXVaultUpgradeableV3

Allows the following 3 main operations:<br />
i. `mint`: Deposits NFTs and mints vault tokens in exchange.<br />
ii. `redeem`: Burn vault tokens to redeem NFTs from the vault in exchange.<br />
iii. `swap`: Swap an array of NFTs into a desired array of NFTs from the vault.

All of the above operations require the user to pay vault fees in ETH, calculated as a % of the ~20 min TWAP of the vToken from our AMM pool (with fee tier = `FeeDistributor.rewardFeeTier()`). If the pool doesn't exist yet, then no vault fees are deducted.<br /><br />
The vault fees collected here are sent to the `NFTXFeeDistributorV3` in the same transaction to distribute to Inventory stakers and Liquidity Providers.<br />
<br />
In case of redeeming/swapping into a newly deposited NFT from a vault, an extra premium in ETH needs to be paid along with the vault fees. This premium is shared with the original depositor of the redeemed tokenId and the rest of the stakers. This premium amount goes down exponentially since being deposited into the vault and finally settling on 0.<br />
<br />
Additional features:

- Flash-minting without any added fees.
- Using Eligibility modules to only allow certain tokenIds into the Vault.

### 2. NFTXVaultFactoryUpgradeableV3

Allows to deploy Beacon Proxies for the Vaults.

### 3. NFTXFeeDistributorV3

Allows to distribute WETH (vault fees) between multiple receivers including inventory stakers and NFTX AMM liquidity providers in the `rewardFeeTier` pool.

### 4. NFTXInventoryStakingV3Upgradeable

Allows users to stake vTokens and mint xNFT in exchange that earns WETH and vTokens as fees. The WETH vault fees are distributed equally among all the stakers.<br />

- NFTs can also be directly staked via Inventory, which internally mints vTokens but without deducting any vault fees. As users can use this to game and avoid the mint fees, so a redeem timelock is placed on the xNFT.
- There is an option to early withdraw (while still in timelock) by paying a % of your vTokens as penalty, which gets distributed among rest of the stakers. This penalty goes down linearly overtime.
- Users can collect and withdraw the WETH accumulated by their position
- During withdrawal, users have the option to redeem NFTs from the vault with their underlying vToken balance. No vault fees is paid if initially the xNFT position was created by depositing NFTs.
- Users can combine multiple xNFT positions into one, after each of their timelocks have run out.

### 5. UniswapV3FactoryUpgradeable

Forked from Uniswap, and converted into an upgradeable contract. Allows to deploy NFTX AMM pools as Create2 Beacon Proxies.

### 6. UniswapV3PoolUpgradeable

Forked from Uniswap. Added `distributeRewards` function, to be called by the FeeDistributor, which allows to distribute the WETH vault fees to the LPs in the current tick, proportional to their share of the liquidity. <br />
If the pool is in `rewardFeeTier`, then cardinality is set during initialization of the pool so that it's able to provide TWAP for the vault fee calculations. The cost of initialization of the observations slots is forwarded & distributed to the first swappers.

### 7. NonfungiblePositionManager

Forked from Uniswap. Allows NFTX AMM positions to be represented as ERC721 NFTs. Allows the NFTXRouter to timelock positions from withdrawing liquidity, though more liquidity can still be added.

- Vault fees accumulated as WETH show up the same way as normal LP fees.

### 8. NFTXRouter

Router to facilitate vault tokens minting/burning + addition/removal of concentrated liquidity, all in one transaction. <br />

- NFTs can be directly deposited into the pool via NFTXRouter, which internally mints vTokens but without deducting any vault fees. As users can use this to game and avoid the mint fees, so a redeem timelock is placed on the LP NFT.
- During withdrawal, users have the option to redeem NFTs from the vault with their underlying vToken balance. No vault fees is paid if initially the position was created by depositing NFTs.
- NFTs can be directly sold and bought from the pool in exchange for ETH, via the AMM.

## Zaps

### 1. CreateVaultZap

An amalgomation of vault creation steps, merged and optimised in a single contract call. <br />
Allows to create a new Vault, mint vTokens in exchange for NFTs, deploy new NFTX AMM pool, deposit the minted vTokens and the ETH sent into the AMM pool to mint liquidity position NFT, deposit the remaining vTokens into inventory staking to mint xNFT.

### 2. MarketplaceUniversalRouterZap

Marketplace Zap that utilizes Uniswap's Universal Router to facilitate tokens swaps via Sushiswap and NFTX AMM. Enables deducting creator royalties via ERC2981.<br />

- `sell721`/`sell1155`: sell NFT tokenIds to ETH.<br />
  `idsIn --{--mint-> [vault] -> vTokens --sell-> [UniversalRouter] --}-> ETH`
- `swap721`/`swap1155`: Swap an array of NFTs into a desired array of NFTs from the vault, by paying ETH for vault fees.
- `buyNFTsWithETH`: buy NFT tokenIds with ETH.<br />
  `ETH --{-sell-> [UniversalRouter] -> vTokens + ETH --redeem-> [vault] --}-> idsOut`
- `buyNFTsWithERC20`: buy NFT tokenIds with ERC20.<br/>
  `ERC20 --{-sell-> [UniversalRouter] -> ETH -> [UniversalRouter] -> vTokens + ETH --redeem-> [vault] --}-> idsOut`

### 3. MigratorZap

Allows the users to migrate their NFTX v2 positions to v3:

- from v2 vTokens in sushiswap liquidity to v3 vTokens in NFTX AMM.
- from v2 vTokens in v2 inventory staking to v3 vTokens in xNFT.
- from v2 vTokens to v3 vTokens in xNFT.

<hr />

## Project Setup

We use [Foundry](https://book.getfoundry.sh/) for tests and [Hardhat](https://hardhat.org/docs) for contract deployments. Refer to installation instructions for foundry [here](https://github.com/foundry-rs/foundry#installation).

```sh
git clone https://github.com/NFTX-project/nftx-protocol-v3.git
cd nftx-protocol-v3
forge install
yarn install
```

Copy `.env.sample` into `.env` and fill out the env variables.

### Tests

```sh
forge test
```

### Deployment

1. To deploy core V3 contracts (including Uniswap V3 Fork):

```sh
yarn deploy:goerli --maxfee <inWei> --priorityfee <inWei> --tags NFTXV3
```

2. Deploy new Universal Router (https://github.com/NFTX-project/nftx-universal-router) with updated address for UniswapV3 Factory address.
3. Deploy all Zaps:

```sh
yarn deploy:goerli --maxfee <inWei> --priorityfee <inWei> --tags Zaps
```

4. Run the following to generate `./addresses.json` for the deployed contract addresses

```sh
yarn gen:addresses
```

Note: Tags are defined in the deploy script at the end like: `func.tags = ["<tag>"]`

### Verify Contracts

`yarn verify:goerli`

**Note:** For some UniswapV3 contracts there might be some error while verifying, so run this for those contracts:

`yarn verify:goerli --license "GPL-2.0" --force-license --solc-input`

How to verify the BeaconProxy (for Vaults):
`source .env && forge verify-contract --chain-id 5 --num-of-optimizations 800 --watch --etherscan-api-key $ETHERSCAN_API_KEY --compiler-version v0.8.15+commit.e14f2714 0xffE5d77309efd6e9391Ac14D95f2035A1e138659 lib/openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol:BeaconProxy --constructor-args $(cast abi-encode "constructor(address,bytes)" 0x1d552A0e6c2f680872C4a88b1e7def05F1858dF0 "")`

where `0xffE5d77309efd6e9391Ac14D95f2035A1e138659` = vault (proxy) address\
and `0x1d552A0e6c2f680872C4a88b1e7def05F1858dF0` = vault factory
