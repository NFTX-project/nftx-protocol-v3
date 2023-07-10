#!/bin/bash

# List of paths
paths_array=(
  "src/uniswap/v3-core/UniswapV3Factory.sol src/uniswap/v3-core/UniswapV3FactoryUpgradeable.sol"
  "src/uniswap/v3-core/UniswapV3PoolDeployer.sol src/uniswap/v3-core/UniswapV3PoolDeployerUpgradeable.sol"
  "src/uniswap/v3-core/UniswapV3Pool.sol src/uniswap/v3-core/UniswapV3PoolUpgradeable.sol"
  "src/uniswap/v3-core/interfaces/IUniswapV3Factory.sol src/uniswap/v3-core/interfaces/IUniswapV3Factory.sol"
  "src/uniswap/v3-core/interfaces/IUniswapV3Pool.sol src/uniswap/v3-core/interfaces/IUniswapV3Pool.sol"
  "src/uniswap/v3-core/interfaces/pool/IUniswapV3PoolActions.sol src/uniswap/v3-core/interfaces/pool/IUniswapV3PoolActions.sol"
  "src/uniswap/v3-core/libraries/Oracle.sol src/uniswap/v3-core/libraries/Oracle.sol"
  "src/uniswap/v3-periphery/NonfungiblePositionManager.sol src/uniswap/v3-periphery/NonfungiblePositionManager.sol"
  "src/uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol src/uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol"
  "src/uniswap/v3-periphery/interfaces/ISwapRouter.sol src/uniswap/v3-periphery/interfaces/ISwapRouter.sol"
  "src/uniswap/v3-periphery/libraries/NFTDescriptor.sol src/uniswap/v3-periphery/libraries/NFTDescriptor.sol"
  "src/uniswap/v3-periphery/libraries/NFTSVG.sol src/uniswap/v3-periphery/libraries/NFTSVG.sol"
  "src/uniswap/v3-periphery/libraries/PoolAddress.sol src/uniswap/v3-periphery/libraries/PoolAddress.sol"
)

# Loop through each path
for paths in "${paths_array[@]}"; do
  # Split the values into separate variables
  read -ra split_paths <<< "$paths"

  output_dir_html=./script/univ3-compare/html/${split_paths[1]}
  output_dir_diff=./script/univ3-compare/diff/${split_paths[1]}
  # create sub directories if required
  mkdir -p $output_dir_html
  mkdir -p $output_dir_diff
  # delete the "*.sol" directory just created
  rm -r $output_dir_html
  rm -r $output_dir_diff

  git diff orig-uni-v3:${split_paths[0]} master:${split_paths[1]} --color -U9999 | ./script/ansi2html.sh > $output_dir_html.html
  git diff orig-uni-v3:${split_paths[0]} master:${split_paths[1]} -U9999 > $output_dir_diff.diff
done