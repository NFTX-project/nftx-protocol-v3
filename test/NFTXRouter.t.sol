// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";

import {INFTXRouter} from "@src/NFTXRouter.sol";

import {TestBase} from "./TestBase.sol";

contract NFTXRouterTests is TestBase {
    // TODO: addLiquidity test with just vTokens and a combo of both

    // TODO: all testcases with ETH vault fees enabled
    function testAddLiquidity() external {
        uint256 prePositionNFTBalance = positionManager.balanceOf(
            address(this)
        );

        (
            ,
            uint256 positionId,
            int24 _tickLower,
            int24 _tickUpper,
            uint256 ethUsed
        ) = _mintPosition(5);
        console.log("ETH Used: ", ethUsed);

        uint256 postPositionNFTBalance = positionManager.balanceOf(
            address(this)
        );
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = positionManager.positions(positionId);

        assertEq(
            postPositionNFTBalance - prePositionNFTBalance,
            1,
            "Position Balance didn't change"
        );
        assertGt(liquidity, 0, "Liquidity didn't increase");
        assertEqInt24(tickLower, _tickLower, "Incorrect tickLower");
        assertEqInt24(tickUpper, _tickUpper, "Incorrect tickUpper");
        assertEqUint24(fee, DEFAULT_FEE_TIER, "Incorrect fee");
        assertEq(
            token0,
            nftxRouter.isVToken0(address(vtoken))
                ? address(vtoken)
                : nftxRouter.WETH(),
            "Incorrect token0"
        );
        assertEq(
            token1,
            !nftxRouter.isVToken0(address(vtoken))
                ? address(vtoken)
                : nftxRouter.WETH(),
            "Incorrect token1"
        );
    }

    function testSellNFTs() external {
        _mintPosition(5);

        uint256 nftQty = 5;
        uint256 preETHBalance = address(this).balance;

        _sellNFTs(nftQty);

        uint256 postETHBalance = address(this).balance;
        assertGt(postETHBalance, preETHBalance, "ETH balance didn't increase");

        console.log(
            "ETH received: %s for selling %s NFTs",
            postETHBalance - preETHBalance,
            nftQty
        );
    }

    function testBuyNFTs() external {
        (uint256[] memory allTokenIds, , , , ) = _mintPosition(100);

        uint256 nftQty = 2;

        // buy first 2 NFTs from this position/pool
        uint256[] memory nftIds = new uint256[](nftQty);
        nftIds[0] = allTokenIds[0];
        nftIds[1] = allTokenIds[1];

        // fetch price to pay for those NFTs
        uint256 ethRequired = nftxRouter.quoteBuyNFTs({
            vtoken: address(vtoken),
            nftsCount: nftIds.length,
            fee: DEFAULT_FEE_TIER,
            sqrtPriceLimitX96: 0
        });

        uint256 preNFTBalance = nft.balanceOf(address(this));
        uint256 preETHBalance = address(this).balance;

        // execute swap
        nftxRouter.buyNFTs{value: ethRequired}(
            INFTXRouter.BuyNFTsParams({
                vtoken: address(vtoken),
                nftIds: nftIds,
                deadline: block.timestamp,
                fee: DEFAULT_FEE_TIER,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 postNFTBalance = nft.balanceOf(address(this));
        uint256 postETHBalance = address(this).balance;

        assertEq(
            postNFTBalance - preNFTBalance,
            nftQty,
            "NFT balance didn't increase"
        );
        assertLt(postETHBalance, preETHBalance, "ETH balance didn't decrease");

        console.log(
            "ETH spent: %s for buying %s NFTs",
            preETHBalance - postETHBalance,
            nftQty
        );
    }

    // ================================
    // Remove Liquidity
    // ================================

    function test_removeLiquidity_ToNFTs_Success() external {
        uint256 nftQty = 10;
        (
            uint256[] memory allTokenIds,
            uint256 positionId,
            ,
            ,

        ) = _mintPosition(nftQty);

        uint256 nftsSold = 5;
        uint256[] memory soldTokenIds = _sellNFTs(nftsSold);

        uint256 nftResidue = 1;
        uint256 expectedNFTQty = nftQty + nftsSold - nftResidue;
        uint256[] memory nftIds = new uint256[](expectedNFTQty);
        nftIds[0] = allTokenIds[0];
        nftIds[1] = allTokenIds[1];
        nftIds[2] = allTokenIds[2];
        nftIds[3] = allTokenIds[3];
        nftIds[4] = allTokenIds[4];
        nftIds[5] = allTokenIds[5];
        nftIds[6] = allTokenIds[6];
        nftIds[7] = allTokenIds[7];
        nftIds[8] = allTokenIds[8];
        nftIds[9] = allTokenIds[9];
        nftIds[10] = soldTokenIds[0];
        nftIds[11] = soldTokenIds[1];
        nftIds[12] = soldTokenIds[2];
        nftIds[13] = soldTokenIds[3];
        // nftIds[14] = soldTokenIds[4]; // redeeming less NFT(s) than the vTokens withdrawn from liquidity position

        uint128 liquidity = _getLiquidity(positionId);

        uint256 preNFTBalance = nft.balanceOf(address(this));
        uint256 preVTokenBalance = vtoken.balanceOf(address(this));
        uint256 preETHBalance = address(this).balance;

        positionManager.setApprovalForAll(address(nftxRouter), true);
        nftxRouter.removeLiquidity(
            INFTXRouter.RemoveLiquidityParams({
                positionId: positionId,
                vtoken: address(vtoken),
                nftIds: nftIds,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        uint256 postNFTBalance = nft.balanceOf(address(this));
        uint256 postVTokenBalance = vtoken.balanceOf(address(this));
        uint256 postETHBalance = address(this).balance;

        assertEq(
            postNFTBalance - preNFTBalance,
            expectedNFTQty,
            "Incorrect NFT balance change"
        );
        assertEq(
            postVTokenBalance - preVTokenBalance,
            nftResidue * 1 ether - 2, // 2 wei round down during txn
            "vToken balance didn't change"
        );
        assertGt(postETHBalance, preETHBalance, "ETH balance didn't change");
        assertEq(
            positionManager.ownerOf(positionId),
            address(this),
            "User is no longer the owner of PositionId"
        );

        console.log("ETH removed: ", postETHBalance - preETHBalance);
    }

    function test_removeLiquidity_ToVTokens_Success() external {
        uint256 nftQty = 10;
        (, uint256 positionId, , , ) = _mintPosition(nftQty);

        _sellNFTs(5);

        uint128 liquidity = _getLiquidity(positionId);

        uint256 preVTokenBalance = vtoken.balanceOf(address(this));
        uint256 preETHBalance = address(this).balance;

        positionManager.setApprovalForAll(address(nftxRouter), true);
        nftxRouter.removeLiquidity(
            INFTXRouter.RemoveLiquidityParams({
                positionId: positionId,
                vtoken: address(vtoken),
                nftIds: new uint256[](0),
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        uint256 postVTokenBalance = vtoken.balanceOf(address(this));
        uint256 postETHBalance = address(this).balance;

        assertGt(
            postVTokenBalance,
            preVTokenBalance,
            "vToken balance didn't change"
        );
        assertGt(postETHBalance, preETHBalance, "ETH balance didn't change");
        assertEq(
            positionManager.ownerOf(positionId),
            address(this),
            "User is no longer the owner of PositionId"
        );

        console.log("ETH removed: ", postETHBalance - preETHBalance);
    }

    // ================================
    // Pool Address
    // ================================

    // NFTXRouter#getPoolExists(vaultId)

    function test_getPoolExistsVaultId_IfPoolNonExistent() external {
        (address pool, bool exists) = nftxRouter.getPoolExists(
            0,
            DEFAULT_FEE_TIER
        );

        assertEq(exists, false);
        assertEq(pool, address(0));
    }

    function test_getPoolExistsVaultId_Success() external {
        // deploy pool
        _mintPosition(1);

        (address pool, bool exists) = nftxRouter.getPoolExists(
            0,
            DEFAULT_FEE_TIER
        );

        assertEq(exists, true);
        assertEq(
            pool,
            factory.getPool(address(vtoken), address(weth), DEFAULT_FEE_TIER)
        );
    }

    // NFTXRouter#getPoolExists(vToken)

    function test_getPoolExistsVToken_IfPoolNonExistent() external {
        (address pool, bool exists) = nftxRouter.getPoolExists(
            address(vtoken),
            DEFAULT_FEE_TIER
        );

        assertEq(exists, false);
        assertEq(pool, address(0));
    }

    function test_getPoolExistsVToken_Success() external {
        // deploy pool
        _mintPosition(1);

        (address pool, bool exists) = nftxRouter.getPoolExists(
            address(vtoken),
            DEFAULT_FEE_TIER
        );

        assertEq(exists, true);
        assertEq(
            pool,
            factory.getPool(address(vtoken), address(weth), DEFAULT_FEE_TIER)
        );
    }

    // NFTXRouter#getPool

    function test_getPool_RevertsIfPoolNonExistent() external {
        vm.expectRevert();
        nftxRouter.getPool(makeAddr("newVToken"), DEFAULT_FEE_TIER);
    }

    function test_getPool_Success() external {
        // deploy pool
        _mintPosition(1);

        assertEq(
            nftxRouter.getPool(address(vtoken), DEFAULT_FEE_TIER),
            factory.getPool(address(vtoken), address(weth), DEFAULT_FEE_TIER)
        );
    }

    // NFTXRouter#computePool
    function test_computePool_Success() external {
        address expectedPoolAddress = nftxRouter.computePool(
            address(vtoken),
            DEFAULT_FEE_TIER
        );

        // deploy pool
        _mintPosition(1);

        assertEq(
            expectedPoolAddress,
            nftxRouter.getPool(address(vtoken), DEFAULT_FEE_TIER)
        );
    }
}
