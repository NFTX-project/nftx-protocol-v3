// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IUniswapV3Factory} from "@uni-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uni-core/interfaces/IUniswapV3Pool.sol";

import {vToken} from "./vToken.sol";

contract MockFeeDistributor {
    IUniswapV3Factory public uniFactory;
    address public weth;
    vToken public vtoken;

    uint24 public constant FEE = 10000;

    constructor(
        IUniswapV3Factory uniFactory_,
        address weth_,
        vToken vtoken_
    ) {
        uniFactory = uniFactory_;
        weth = weth_;
        vtoken = vtoken_;
    }

    function distribute(uint256 vaultId) external {
        IUniswapV3Pool pool = IUniswapV3Pool(
            uniFactory.getPool(address(vtoken), weth, FEE)
        );

        uint256 tokenBalance = vtoken.balanceOf(address(this));

        // send rewards to pool
        vtoken.transfer(address(pool), tokenBalance);
        // distribute rewards with LPs
        pool.distributeRewards(tokenBalance, address(vtoken) < weth);
    }
}
