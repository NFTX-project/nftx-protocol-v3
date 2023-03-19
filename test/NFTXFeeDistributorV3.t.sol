// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";

import {UniswapV3Pool} from "@uni-core/UniswapV3Pool.sol";
import {INFTXRouter} from "@src/NFTXRouter.sol";

import {TestBase} from "./TestBase.sol";

contract NFTXFeeDistributorV3Tests is TestBase {
    // UniswapV3Factory#setFeeDistributor

    function test_setFeeDistributor_RevertsForNonOwner() external {
        hoax(makeAddr("nonOwner"));
        vm.expectRevert();
        factory.setFeeDistributor(address(feeDistributor));
    }

    function test_setFeeDistributor_Success() external {
        address newFeeDistributor = makeAddr("newFeeDistributor");
        factory.setFeeDistributor(newFeeDistributor);
        assertEq(factory.feeDistributor(), newFeeDistributor);
    }

    // UniswapV3Pool#distributeRewards
    function test_distributeRewards_RevertsForNonFeeDistributor() external {
        // minting so that Pool is deployed
        _mintPosition(1);
        UniswapV3Pool pool = UniswapV3Pool(
            nftxRouter.getPool(address(vtoken), DEFAULT_FEE_TIER)
        );

        hoax(makeAddr("nonFeeDistributor"));
        vm.expectRevert();
        pool.distributeRewards(1 ether, true);
    }

    // FeeDistributor#distribute

    function test_feeDistribution_Success() external {
        uint256 mintQty = 5;

        // mint position
        (
            uint256[] memory mintTokenIds,
            uint256 positionId, // uint256 ethDeposited
            ,
            ,

        ) = _mintPosition(mintQty);
        // have another position, so that the pool doesn't have 0 liquidity to facilitate swapping fractional vTokens during removeLiquidity
        _mintPosition(mintQty);
        // TODO: add console logs for initial values as well, in all test cases

        uint256 wethFees = 2 ether;

        // distribute fees
        weth.deposit{value: wethFees}();
        weth.transfer(address(feeDistributor), wethFees);
        feeDistributor.distribute(0);

        // NOTE: We have 2 LP positions with the exact same liquidity. So the fees is distributed equally between them both
        // So for wethFees = 2, each position should get 1 weth as fees, but due to rounding gets 0.999..999 of weth as fees

        // Findings: On liquidity withdrawal 1 wei gets left in the pool as well.
        // So 1 wei of distributed weth and 1 wei from initial provided liquidity gets stuck in the pool (for a total of 2 wei)

        (, uint256 _wethFees) = _getAccumulatedFees(positionId);
        console.log("_wethFees", _wethFees);
        assertGe(_wethFees, wethFees / 2 - 1);

        // remove liquidity
        uint256[] memory nftIds = new uint256[](mintQty - 1); // accounting for that 1 wei difference allows us to redeem 1 less NFT
        nftIds[0] = mintTokenIds[0];
        nftIds[1] = mintTokenIds[1];
        nftIds[2] = mintTokenIds[2];
        nftIds[3] = mintTokenIds[3];
        // nftIds[4] = mintTokenIds[4];

        uint128 liquidity = _getLiquidity(positionId);

        uint256 preNFTBalance = nft.balanceOf(address(this));
        uint256 preETHBalance = address(this).balance;

        positionManager.setApprovalForAll(address(nftxRouter), true);
        nftxRouter.removeLiquidity(
            INFTXRouter.RemoveLiquidityParams({
                positionId: positionId,
                vtoken: address(vtoken),
                nftIds: nftIds,
                receiveVTokens: false,
                liquidity: liquidity,
                swapPoolFee: 10000,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        uint256 nftReceived = nft.balanceOf(address(this)) - preNFTBalance;
        uint256 ethReceived = address(this).balance - preETHBalance;

        console.log("NFT received", nftReceived);
        // ethReceived = ethDeposited + _wethFees + swapped 0.9999..99 vToken into ETH
        console.log("ETH received", ethReceived);
    }
}
