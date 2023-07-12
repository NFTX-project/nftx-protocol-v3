#!/bin/bash

source .env && forge script ./script/v3ActionsTestnet.s.sol --broadcast --rpc-url https://eth-goerli.alchemyapi.io/v2/$ALCHEMY_GOERLI_API_KEY --sender $SENDER --private-key $DEPLOYER_PRIVATE_KEY