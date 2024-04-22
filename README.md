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

Contract | mainnet | arbitrum | base | sepolia | goerli
--- | --- | --- | --- | --- | ---
[CreateVaultZap](./src/zaps/CreateVaultZap.sol) | [0x56dab32697B4A313f353DA0CE42B5113eD8E6f74](https://etherscan.io/address/0x56dab32697B4A313f353DA0CE42B5113eD8E6f74#code) | [0xF9E891AB1ECa89B7A4B3cBD45aEBFDF3Ec38946F](https://arbiscan.io/address/0xF9E891AB1ECa89B7A4B3cBD45aEBFDF3Ec38946F#code) | [0x2D77756C139ed3c25472Daf233F332E8F605Dd8E](https://basescan.org/address/0x2D77756C139ed3c25472Daf233F332E8F605Dd8E#code) | [0xD80b916470F8e79FD8d09874cb159CbB8D13d8da](https://sepolia.etherscan.io/address/0xD80b916470F8e79FD8d09874cb159CbB8D13d8da#code) | [0xc6464CC63bC20b64e1633A0293C2C9b202F4f1b6](https://goerli.etherscan.io/address/0xc6464CC63bC20b64e1633A0293C2C9b202F4f1b6#code)
DefaultProxyAdmin | [0xf8Cab5e4912e08c475033776d9472b81c1325e58](https://etherscan.io/address/0xf8Cab5e4912e08c475033776d9472b81c1325e58#code) | [0xdA7C2F023Dd30329d41483B95AFd24962f468A54](https://arbiscan.io/address/0xdA7C2F023Dd30329d41483B95AFd24962f468A54#code) | [0x33b381E2e0c4adC1dbd388888e9A29079e5b6702](https://basescan.org/address/0x33b381E2e0c4adC1dbd388888e9A29079e5b6702#code) | [0x36cBBb16F2FA71d4B773E9F4A11cF7FC53B13EfD](https://sepolia.etherscan.io/address/0x36cBBb16F2FA71d4B773E9F4A11cF7FC53B13EfD#code) | [0xa0d26F02D5e94C8E9ED524875D9fce36ab4838a2](https://goerli.etherscan.io/address/0xa0d26F02D5e94C8E9ED524875D9fce36ab4838a2#code)
[FailSafe](./src/FailSafe.sol) | [0x6bB724F11a8D7254800Cf34922E0D54407B0e698](https://etherscan.io/address/0x6bB724F11a8D7254800Cf34922E0D54407B0e698#code) | [0xBDA73b600435BF4309270438842dcE06f9a06fb7](https://arbiscan.io/address/0xBDA73b600435BF4309270438842dcE06f9a06fb7#code) | [0xb13907103606118D01D18c9Deb249B89F6c31545](https://basescan.org/address/0xb13907103606118D01D18c9Deb249B89F6c31545#code) | N/A | N/A
[MarketplaceUniversalRouterZap](./src/zaps/MarketplaceUniversalRouterZap.sol) | [0x293A0c49c85F1D8851C665Ac3cE1f1DC2a79bE3d](https://etherscan.io/address/0x293A0c49c85F1D8851C665Ac3cE1f1DC2a79bE3d#code) | [0xf56296B3010a59Ef7F0915569DD44E1302b9Ca40](https://arbiscan.io/address/0xf56296B3010a59Ef7F0915569DD44E1302b9Ca40#code) | [0x31cB832F661Cd90fc9Fca6fB70A39cA811a02aEd](https://basescan.org/address/0x31cB832F661Cd90fc9Fca6fB70A39cA811a02aEd#code) | [0xd88a3B9D0Fb2d39ec8394CfFD983aFBB2D4a6410](https://sepolia.etherscan.io/address/0xd88a3B9D0Fb2d39ec8394CfFD983aFBB2D4a6410#code) | [0x0be2D766Eef4b6a72F1fAe2e49619F013d647B8A](https://goerli.etherscan.io/address/0x0be2D766Eef4b6a72F1fAe2e49619F013d647B8A#code)
[MigratorZap](./src/zaps/MigratorZap.sol) | [0x089610Fb04c34C014B4B391f4eCEFAef94E98CEc](https://etherscan.io/address/0x089610Fb04c34C014B4B391f4eCEFAef94E98CEc#code) | [0x6E1537eD56f52414f0182FaebF79A5fB2Ad2CABd](https://arbiscan.io/address/0x6E1537eD56f52414f0182FaebF79A5fB2Ad2CABd#code) | N/A | [0x19762e505aF085284E287c8DAb931fb28545461f](https://sepolia.etherscan.io/address/0x19762e505aF085284E287c8DAb931fb28545461f#code) | [0xD4B67Fe6a1258fd5e1C4dF84f3De01F62e7ac127](https://goerli.etherscan.io/address/0xD4B67Fe6a1258fd5e1C4dF84f3De01F62e7ac127#code)
[NFTXEligibilityManager](./src/v2/NFTXEligibilityManager.sol) | [0x4086e98Cce041d286112d021612fD894cFed94D5](https://etherscan.io/address/0x4086e98Cce041d286112d021612fD894cFed94D5#code) | [0x6DCdfD7e94957cBAE9023c232dE18c0F72c2aD16](https://arbiscan.io/address/0x6DCdfD7e94957cBAE9023c232dE18c0F72c2aD16#code) | [0xcB62303a5Ecc5f9C5cF7B5AA967a25d9Bb2B4b08](https://basescan.org/address/0xcB62303a5Ecc5f9C5cF7B5AA967a25d9Bb2B4b08#code) | [0xa1ad09f8Fd789E3A940Ba9Dc5aE4D17021eF290D](https://sepolia.etherscan.io/address/0xa1ad09f8Fd789E3A940Ba9Dc5aE4D17021eF290D#code) | [0xA4e9e286CE7A34d19f774c36844225468290C3A8](https://goerli.etherscan.io/address/0xA4e9e286CE7A34d19f774c36844225468290C3A8#code)
[NFTXFeeDistributorV3](./src/NFTXFeeDistributorV3.sol) | [0x6845fF5f102bEF9D785468F0bEb535b4687406E7](https://etherscan.io/address/0x6845fF5f102bEF9D785468F0bEb535b4687406E7#code) | [0x0d50970C7848ebbE52661e70057D7D063B7de886](https://arbiscan.io/address/0x0d50970C7848ebbE52661e70057D7D063B7de886#code) | [0xA64c2F3f965f055E51482bF0960Ebb5f2904BF68](https://basescan.org/address/0xA64c2F3f965f055E51482bF0960Ebb5f2904BF68#code) | [0x53AE38742C78EE64fC077EF840B2Aa47A7E9c603](https://sepolia.etherscan.io/address/0x53AE38742C78EE64fC077EF840B2Aa47A7E9c603#code) | [0xA8076Ec5Dbb95165e14624Ff43dE2290e78A6905](https://goerli.etherscan.io/address/0xA8076Ec5Dbb95165e14624Ff43dE2290e78A6905#code)
[NFTXInventoryStakingV3Upgradeable](./src/NFTXInventoryStakingV3Upgradeable.sol) | [0x889f313e2a3FDC1c9a45bC6020A8a18749CD6152](https://etherscan.io/address/0x889f313e2a3FDC1c9a45bC6020A8a18749CD6152#code) | [0xe39a7E67d3E3b6eAF58BC02C4E80C3688847d155](https://arbiscan.io/address/0xe39a7E67d3E3b6eAF58BC02C4E80C3688847d155#code) | [0x47D9ACEE6aa260C36F4368091bE92F0824876C72](https://basescan.org/address/0x47D9ACEE6aa260C36F4368091bE92F0824876C72#code) | [0xfBFf0635f7c5327FD138E1EBa72BD9877A6a7C1C](https://sepolia.etherscan.io/address/0xfBFf0635f7c5327FD138E1EBa72BD9877A6a7C1C#code) | [0xEf771a17e6970d8B4b208a76e94F175277554230](https://goerli.etherscan.io/address/0xEf771a17e6970d8B4b208a76e94F175277554230#code)
[NFTXRouter](./src/NFTXRouter.sol) | [0x70A741A12262d4b5Ff45C0179c783a380EebE42a](https://etherscan.io/address/0x70A741A12262d4b5Ff45C0179c783a380EebE42a#code) | [0x52731751Dede22827ad47109f5e9697d75a3ef4d](https://arbiscan.io/address/0x52731751Dede22827ad47109f5e9697d75a3ef4d#code) | [0x590F8679964D4dEfB54DCD307b2941B053eb1821](https://basescan.org/address/0x590F8679964D4dEfB54DCD307b2941B053eb1821#code) | [0x441b7DE4340AAa5aA86dB4DA43d9Badf7B2DAA66](https://sepolia.etherscan.io/address/0x441b7DE4340AAa5aA86dB4DA43d9Badf7B2DAA66#code) | [0x8E16cdd0D9A15d2d0EFeA531660e8DbD0F6eE12D](https://goerli.etherscan.io/address/0x8E16cdd0D9A15d2d0EFeA531660e8DbD0F6eE12D#code)
[nftxUniversalRouter](https://github.com/NFTX-project/nftx-universal-router/blob/nftx-universal-router/contracts/UniversalRouter.sol) | [0x250d62a67254A46c0De472d2c9215E1d890cC90f](https://etherscan.io/address/0x250d62a67254A46c0De472d2c9215E1d890cC90f#code) | [0x0DA69287B4C1B28181E5d155dDDda7Fa5C32E5Ad](https://arbiscan.io/address/0x0DA69287B4C1B28181E5d155dDDda7Fa5C32E5Ad#code) | [0x7c656F0691Db983ee78f68189c55C36d1862c901](https://basescan.org/address/0x7c656F0691Db983ee78f68189c55C36d1862c901#code) | [0x12156cCA1958B6591CC49EaE03a5553458a4b424](https://sepolia.etherscan.io/address/0x12156cCA1958B6591CC49EaE03a5553458a4b424#code) | [0xF7c4FC5C2e30258e1E4d1197fc63aeDE371508f3](https://goerli.etherscan.io/address/0xF7c4FC5C2e30258e1E4d1197fc63aeDE371508f3#code)
[NFTXVaultFactoryUpgradeableV3](./src/NFTXVaultFactoryUpgradeableV3.sol) | [0xC255335bc5aBd6928063F5788a5E420554858f01](https://etherscan.io/address/0xC255335bc5aBd6928063F5788a5E420554858f01#code) | [0x4dEeb9D2Bff2e9C35ce1f013DcC4582F891cb711](https://arbiscan.io/address/0x4dEeb9D2Bff2e9C35ce1f013DcC4582F891cb711#code) | [0x0D74B761eAB5cC7Cc0E4e625A2e2B8251A4915c6](https://basescan.org/address/0x0D74B761eAB5cC7Cc0E4e625A2e2B8251A4915c6#code) | [0x31C56CaF49125043e80B4d3C7f8734f949d8178C](https://sepolia.etherscan.io/address/0x31C56CaF49125043e80B4d3C7f8734f949d8178C#code) | [0x1d552A0e6c2f680872C4a88b1e7def05F1858dF0](https://goerli.etherscan.io/address/0x1d552A0e6c2f680872C4a88b1e7def05F1858dF0#code)
[NonfungiblePositionManager](./src/uniswap/v3-periphery/NonfungiblePositionManager.sol) | [0x26387fcA3692FCac1C1e8E4E2B22A6CF0d4b71bF](https://etherscan.io/address/0x26387fcA3692FCac1C1e8E4E2B22A6CF0d4b71bF#code) | [0x8AD238377531547838370B9C4aC346b9Ed5466Ea](https://arbiscan.io/address/0x8AD238377531547838370B9C4aC346b9Ed5466Ea#code) | [0x4f566a711901168804A74F252680d85C9246188e](https://basescan.org/address/0x4f566a711901168804A74F252680d85C9246188e#code) | [0xA9bCC1e29d3460177875f68fDCC0264D22c40BF0](https://sepolia.etherscan.io/address/0xA9bCC1e29d3460177875f68fDCC0264D22c40BF0#code) | [0xDa9411C5455a1bfDb527d0988c0A2764E2a104be](https://goerli.etherscan.io/address/0xDa9411C5455a1bfDb527d0988c0A2764E2a104be#code)
[permit2](https://github.com/Uniswap/permit2/blob/main/src/Permit2.sol) | [0x000000000022d473030f116ddee9f6b43ac78ba3](https://etherscan.io/address/0x000000000022d473030f116ddee9f6b43ac78ba3#code) | [0x000000000022d473030f116ddee9f6b43ac78ba3](https://arbiscan.io/address/0x000000000022d473030f116ddee9f6b43ac78ba3#code) | [0x000000000022d473030f116ddee9f6b43ac78ba3](https://basescan.org/address/0x000000000022d473030f116ddee9f6b43ac78ba3#code) | [0x000000000022d473030f116ddee9f6b43ac78ba3](https://sepolia.etherscan.io/address/0x000000000022d473030f116ddee9f6b43ac78ba3#code) | [0x000000000022d473030f116ddee9f6b43ac78ba3](https://goerli.etherscan.io/address/0x000000000022d473030f116ddee9f6b43ac78ba3#code)
[QuoterV2](./src/uniswap/v3-periphery/lens/QuoterV2.sol) | [0x5493dF723c17B6A768aA61F79405bA56ffC5294a](https://etherscan.io/address/0x5493dF723c17B6A768aA61F79405bA56ffC5294a#code) | [0xff3957CB28aB34186543281e0bbe0De05C9e7D6D](https://arbiscan.io/address/0xff3957CB28aB34186543281e0bbe0De05C9e7D6D#code) | [0xFf40913CA69912212e00e93Ad4DD1480A7aeF13A](https://basescan.org/address/0xFf40913CA69912212e00e93Ad4DD1480A7aeF13A#code) | [0xb8EB27ca4715f7A04228c6F83935379D1f5AbABd](https://sepolia.etherscan.io/address/0xb8EB27ca4715f7A04228c6F83935379D1f5AbABd#code) | [0xBb473dbEF3363b5d7CDD5f12429Fd1C5F0c10499](https://goerli.etherscan.io/address/0xBb473dbEF3363b5d7CDD5f12429Fd1C5F0c10499#code)
[ShutdownRedeemerUpgradeable](./src/ShutdownRedeemerUpgradeable.sol) | [0x96cf14C2A61b7142421397735e702e25f1aa7F30](https://etherscan.io/address/0x96cf14C2A61b7142421397735e702e25f1aa7F30#code) | N/A | N/A | [0x4b25288f40C7e00F93f0DA261C314d67b640c9dF](https://sepolia.etherscan.io/address/0x4b25288f40C7e00F93f0DA261C314d67b640c9dF#code) | N/A
[SwapRouter](./src/uniswap/v3-periphery/SwapRouter.sol) | [0x1703f8111B0E7A10e1d14f9073F53680d64277A3](https://etherscan.io/address/0x1703f8111B0E7A10e1d14f9073F53680d64277A3#code) | [0xeA60242d7183E3d13Dc17fb2A4D0230d34eef502](https://arbiscan.io/address/0xeA60242d7183E3d13Dc17fb2A4D0230d34eef502#code) | [0x27124948dcc9EbF3113681898FF217d3E4f56900](https://basescan.org/address/0x27124948dcc9EbF3113681898FF217d3E4f56900#code) | [0xa7069da6a7e600e0348620484fD2B1f24E075d5f](https://sepolia.etherscan.io/address/0xa7069da6a7e600e0348620484fD2B1f24E075d5f#code) | [0x2E77A788fc66c5312354aaE0df1dC1895ce556f8](https://goerli.etherscan.io/address/0x2E77A788fc66c5312354aaE0df1dC1895ce556f8#code)
[TickLens](./src/uniswap/v3-periphery/lens/TickLens.sol) | [0x1650115DDD287bE6F4972180d290D0FF89a42c40](https://etherscan.io/address/0x1650115DDD287bE6F4972180d290D0FF89a42c40#code) | [0x3f2797b0E19CBf2377B8DE2d1CEC2698AcA7b081](https://arbiscan.io/address/0x3f2797b0E19CBf2377B8DE2d1CEC2698AcA7b081#code) | [0x95Eaddd888c0063B392B771d11Db9704843df8bE](https://basescan.org/address/0x95Eaddd888c0063B392B771d11Db9704843df8bE#code) | [0xA13E04fAEe08E784A44C27e9E77Ca7a02D45BFd7](https://sepolia.etherscan.io/address/0xA13E04fAEe08E784A44C27e9E77Ca7a02D45BFd7#code) | [0x32A7703773cBc265cf79D49340F656837169FEcD](https://goerli.etherscan.io/address/0x32A7703773cBc265cf79D49340F656837169FEcD#code)
[UniswapV3FactoryUpgradeable](./src/uniswap/v3-core/UniswapV3FactoryUpgradeable.sol) | [0xa70e10beB02fF9a44007D9D3695d4b96003db101](https://etherscan.io/address/0xa70e10beB02fF9a44007D9D3695d4b96003db101#code) | [0xF4D0512FB47319B0CE9144EF582862e2921CaBF8](https://arbiscan.io/address/0xF4D0512FB47319B0CE9144EF582862e2921CaBF8#code) | [0x5FD88cD0034A0B2FC77E75Ea09b6e512511b0Eb9](https://basescan.org/address/0x5FD88cD0034A0B2FC77E75Ea09b6e512511b0Eb9#code) | [0xDD2dce9C403f93c10af1846543870D065419E70b](https://sepolia.etherscan.io/address/0xDD2dce9C403f93c10af1846543870D065419E70b#code) | [0xf25081B098c5929A26F562aa2502795fE89BC73f](https://goerli.etherscan.io/address/0xf25081B098c5929A26F562aa2502795fE89BC73f#code)
[V3MigrateSwap](./src/V3MigrateSwap.sol) | N/A | N/A | N/A | [0xd26b2BFBB6E8c1B3B849751549B20abf5E5fb125](https://sepolia.etherscan.io/address/0xd26b2BFBB6E8c1B3B849751549B20abf5E5fb125#code) | N/A
[WETH](https://vscode.blockscan.com/ethereum/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) | [0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2](https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2#code) | [0x82aF49447D8a07e3bd95BD0d56f35241523fBab1](https://arbiscan.io/address/0x82aF49447D8a07e3bd95BD0d56f35241523fBab1#code) | [0x4200000000000000000000000000000000000006](https://basescan.org/address/0x4200000000000000000000000000000000000006#code) | [0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14](https://sepolia.etherscan.io/address/0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14#code) | [0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6](https://goerli.etherscan.io/address/0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6#code)
[UniswapV3Staker](https://github.com/Uniswap/v3-staker) | N/A | [0xd4E155135b7dFf66c9C3B34EcA4aE7d9555FE31F](https://arbiscan.io/address/0xd4E155135b7dFf66c9C3B34EcA4aE7d9555FE31F#code) | N/A | N/A | N/A

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
yarn deploy:mainnet --maxfee <inWei> --priorityfee <inWei> --tags NFTXV3
```

2. Deploy new Universal Router (https://github.com/NFTX-project/nftx-universal-router) with updated address for UniswapV3 Factory address.
3. Deploy all Zaps:

```sh
yarn deploy:mainnet --maxfee <inWei> --priorityfee <inWei> --tags Zaps
```

4. Run the following to generate `./addresses.json` for the deployed contract addresses

```sh
yarn gen:addresses
```

Note: Tags are defined in the deploy script at the end like: `func.tags = ["<tag>"]`

### Verify Contracts

`yarn verify:mainnet`

**Note:** For some UniswapV3 contracts there might be some error while verifying, so run this for those contracts:

`yarn verify:mainnet --license "GPL-2.0" --force-license --solc-input`

- How to verify the Create2BeaconProxy (for Vaults):

  ```
  source .env &&
  forge verify-contract --chain-id 1 \
    0x8e42595f46e5998332F51D3267830DE982A3E59a \
    src/custom/proxy/Create2BeaconProxy.sol:Create2BeaconProxy \
    --num-of-optimizations 800 \
    --compiler-version v0.8.15+commit.e14f2714 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY
  ```

  where `0x8e42595f46e5998332F51D3267830DE982A3E59a` = vault (proxy) address.

- How to verify the Create2BeaconProxy (for UniswapV3Pool):

  ```
  source .env &&
  forge verify-contract --chain-id 1 \
    0x2c2511250C3561F6E5f8999Ac777d9465E7e27FA \
    src/custom/proxy/Create2BeaconProxy.sol:Create2BeaconProxy \
    --num-of-optimizations 380 \
    --compiler-version v0.8.15+commit.e14f2714 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY
  ```

  where `0x2c2511250C3561F6E5f8999Ac777d9465E7e27FA` = pool (proxy) address.
