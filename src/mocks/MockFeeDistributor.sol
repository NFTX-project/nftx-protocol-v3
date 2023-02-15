// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IUniswapV3Factory} from "@uni-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uni-core/interfaces/IUniswapV3Pool.sol";

import {NFTXRouter} from "@src/NFTXRouter.sol";

import {vToken} from "./vToken.sol";

contract MockFeeDistributor {
    NFTXRouter public nftxRouter;
    vToken public vtoken;

    uint24 public constant FEE = 10000;

    constructor(NFTXRouter nftxRouter_, vToken vtoken_) {
        nftxRouter = nftxRouter_;
        vtoken = vtoken_;
    }

    function distribute(
        uint256 /** vaultId */
    ) external {
        IUniswapV3Pool pool = IUniswapV3Pool(
            nftxRouter.getPool(address(vtoken))
        );

        uint256 tokenBalance = vtoken.balanceOf(address(this));

        // send rewards to pool
        vtoken.transfer(address(pool), tokenBalance);
        // distribute rewards with LPs
        pool.distributeRewards(tokenBalance, nftxRouter.isVToken0());
    }
}
