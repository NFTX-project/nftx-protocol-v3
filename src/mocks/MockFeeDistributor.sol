// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IUniswapV3Factory} from "@uni-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uni-core/interfaces/IUniswapV3Pool.sol";

import {INFTXRouter} from "@src/interfaces/INFTXRouter.sol";

import {vToken} from "./vToken.sol";

contract MockFeeDistributor {
    INFTXRouter public nftxRouter;
    vToken public vtoken;

    IERC20 public immutable WETH;
    uint24 public constant REWARD_FEE_TIER = 10000;

    constructor(INFTXRouter nftxRouter_, vToken vtoken_) {
        WETH = IERC20(nftxRouter_.WETH());
        nftxRouter = nftxRouter_;
        vtoken = vtoken_;
    }

    function distribute(uint256 /** vaultId */) external {
        IUniswapV3Pool pool = IUniswapV3Pool(
            nftxRouter.getPool(address(vtoken), REWARD_FEE_TIER)
        );

        uint256 wethBalance = WETH.balanceOf(address(this));

        // send rewards to pool
        WETH.transfer(address(pool), wethBalance);
        // distribute rewards with LPs
        pool.distributeRewards(
            wethBalance,
            !nftxRouter.isVToken0(address(vtoken))
        );
    }
}
