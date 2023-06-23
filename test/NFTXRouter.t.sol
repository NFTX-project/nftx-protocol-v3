// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";
import {TickHelpers} from "@src/lib/TickHelpers.sol";

import {INFTXRouter} from "@src/NFTXRouter.sol";

import {TestBase} from "@test/TestBase.sol";

contract NFTXRouterTests is TestBase {
    uint256 currentNFTPrice = 5 ether;

    // ================================
    // Add Liquidity
    // ================================

    function testAddLiquidity_withNFTs() external {
        _mintPositionWithTwap(currentNFTPrice);

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
        assertEq(
            positionManager.lockedUntil(positionId),
            block.timestamp + LP_TIMELOCK
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

    function testAddLiquidity_withVTokens() external {
        _mintPositionWithTwap(currentNFTPrice);

        uint256 prePositionNFTBalance = positionManager.balanceOf(
            address(this)
        );
        uint256 qty = 5;
        (
            int24 _tickLower,
            int24 _tickUpper,
            uint160 _currentSqrtP
        ) = _getTicks();
        uint256 positionId;
        {
            (uint256 mintedVTokens, ) = _mintVToken(qty);

            uint256 preETHBalance = address(this).balance;

            uint256[] memory tokenIds;
            vtoken.approve(address(nftxRouter), mintedVTokens);
            positionId = nftxRouter.addLiquidity{value: qty * 100 ether}(
                INFTXRouter.AddLiquidityParams({
                    vaultId: VAULT_ID,
                    vTokensAmount: mintedVTokens,
                    nftIds: tokenIds,
                    nftAmounts: emptyIds,
                    tickLower: _tickLower,
                    tickUpper: _tickUpper,
                    fee: DEFAULT_FEE_TIER,
                    sqrtPriceX96: _currentSqrtP,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                })
            );

            uint256 ethUsed = preETHBalance - address(this).balance;
            console.log("ETH Used: ", ethUsed);
        }

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
        assertEq(positionManager.lockedUntil(positionId), 0);
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

    function testAddLiquidity_withNFTs_and_VTokens() external {
        _mintPositionWithTwap(currentNFTPrice);

        uint256 prePositionNFTBalance = positionManager.balanceOf(
            address(this)
        );
        uint256 qty = 5;
        (
            int24 _tickLower,
            int24 _tickUpper,
            uint160 _currentSqrtP
        ) = _getTicks();
        uint256 positionId;
        {
            (uint256 mintedVTokens, ) = _mintVToken(qty);
            uint256[] memory tokenIds = nft.mint(qty);

            uint256 preETHBalance = address(this).balance;

            vtoken.approve(address(nftxRouter), mintedVTokens);
            nft.setApprovalForAll(address(nftxRouter), true);
            positionId = nftxRouter.addLiquidity{value: qty * 100 ether}(
                INFTXRouter.AddLiquidityParams({
                    vaultId: VAULT_ID,
                    vTokensAmount: mintedVTokens,
                    nftIds: tokenIds,
                    nftAmounts: emptyIds,
                    tickLower: _tickLower,
                    tickUpper: _tickUpper,
                    fee: DEFAULT_FEE_TIER,
                    sqrtPriceX96: _currentSqrtP,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                })
            );

            uint256 ethUsed = preETHBalance - address(this).balance;
            console.log("ETH Used: ", ethUsed);
        }

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
        assertEq(
            positionManager.lockedUntil(positionId),
            block.timestamp + LP_TIMELOCK
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

    // 1155

    function testAddLiquidity_withNFTs_1155() external {
        _mintPositionWithTwap1155(currentNFTPrice);

        uint256 prePositionNFTBalance = positionManager.balanceOf(
            address(this)
        );

        (
            ,
            uint256 positionId,
            int24 _tickLower,
            int24 _tickUpper,
            uint256 ethUsed
        ) = _mintPosition1155(5);
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
        assertEq(
            positionManager.lockedUntil(positionId),
            block.timestamp + LP_TIMELOCK
        );
        assertGt(liquidity, 0, "Liquidity didn't increase");
        assertEqInt24(tickLower, _tickLower, "Incorrect tickLower");
        assertEqInt24(tickUpper, _tickUpper, "Incorrect tickUpper");
        assertEqUint24(fee, DEFAULT_FEE_TIER, "Incorrect fee");
        assertEq(
            token0,
            nftxRouter.isVToken0(address(vtoken1155))
                ? address(vtoken1155)
                : nftxRouter.WETH(),
            "Incorrect token0"
        );
        assertEq(
            token1,
            !nftxRouter.isVToken0(address(vtoken1155))
                ? address(vtoken1155)
                : nftxRouter.WETH(),
            "Incorrect token1"
        );
    }

    // addLiquidityWithPermit2

    function testAddLiquidityWithPermit2_withVTokens() external {
        _mintPositionWithTwap(currentNFTPrice);

        uint256 prePositionNFTBalance = positionManager.balanceOf(from);
        uint256 qty = 5;
        (
            int24 _tickLower,
            int24 _tickUpper,
            uint160 _currentSqrtP
        ) = _getTicks();
        uint256 positionId;
        {
            (uint256 mintedVTokens, ) = _mintVToken(qty);
            vtoken.transfer(from, mintedVTokens);
            startHoax(from);

            uint256 preETHBalance = from.balance;

            uint256[] memory tokenIds;

            bytes memory encodedPermit2 = _getEncodedPermit2(
                address(vtoken),
                mintedVTokens,
                address(nftxRouter)
            );

            positionId = nftxRouter.addLiquidityWithPermit2{
                value: qty * 100 ether
            }(
                INFTXRouter.AddLiquidityParams({
                    vaultId: VAULT_ID,
                    vTokensAmount: mintedVTokens,
                    nftIds: tokenIds,
                    nftAmounts: emptyIds,
                    tickLower: _tickLower,
                    tickUpper: _tickUpper,
                    fee: DEFAULT_FEE_TIER,
                    sqrtPriceX96: _currentSqrtP,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                }),
                encodedPermit2
            );

            uint256 ethUsed = preETHBalance - from.balance;
            console.log("ETH Used: ", ethUsed);
        }

        uint256 postPositionNFTBalance = positionManager.balanceOf(from);
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
        assertEq(positionManager.lockedUntil(positionId), 0);
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

    function testAddLiquidityWithPermit2_withNFTs_and_VTokens() external {
        _mintPositionWithTwap(currentNFTPrice);

        uint256 prePositionNFTBalance = positionManager.balanceOf(from);
        uint256 qty = 5;
        (
            int24 _tickLower,
            int24 _tickUpper,
            uint160 _currentSqrtP
        ) = _getTicks();
        uint256 positionId;
        {
            (uint256 mintedVTokens, ) = _mintVToken(qty);
            vtoken.transfer(from, mintedVTokens);

            startHoax(from);
            uint256[] memory tokenIds = nft.mint(qty);

            uint256 preETHBalance = from.balance;

            bytes memory encodedPermit2 = _getEncodedPermit2(
                address(vtoken),
                mintedVTokens,
                address(nftxRouter)
            );

            nft.setApprovalForAll(address(nftxRouter), true);
            positionId = nftxRouter.addLiquidityWithPermit2{
                value: qty * 100 ether
            }(
                INFTXRouter.AddLiquidityParams({
                    vaultId: VAULT_ID,
                    vTokensAmount: mintedVTokens,
                    nftIds: tokenIds,
                    nftAmounts: emptyIds,
                    tickLower: _tickLower,
                    tickUpper: _tickUpper,
                    fee: DEFAULT_FEE_TIER,
                    sqrtPriceX96: _currentSqrtP,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                }),
                encodedPermit2
            );

            uint256 ethUsed = preETHBalance - from.balance;
            console.log("ETH Used: ", ethUsed);
        }

        uint256 postPositionNFTBalance = positionManager.balanceOf(from);
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
        assertEq(
            positionManager.lockedUntil(positionId),
            block.timestamp + LP_TIMELOCK
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

    // ================================
    // Increase Liquidity
    // ================================

    function testIncreaseLiquidity_withNFTs() external {
        uint256 positionId = _mintPositionWithTwap(currentNFTPrice);
        // after timelock ended
        vm.warp(positionManager.lockedUntil(positionId) + 1);

        uint256 qty = 3;
        uint256[] memory tokenIds = nft.mint(qty);
        nft.setApprovalForAll(address(nftxRouter), true);

        uint256 prePositionNFTBalance = positionManager.balanceOf(
            address(this)
        );
        uint256 preLiquidity = _getLiquidity(positionId);

        positionManager.setApprovalForAll(address(nftxRouter), true);
        nftxRouter.increaseLiquidity{value: qty * 100 ether}(
            INFTXRouter.IncreaseLiquidityParams({
                positionId: positionId,
                vaultId: VAULT_ID,
                vTokensAmount: 0,
                nftIds: tokenIds,
                nftAmounts: emptyIds,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        uint256 postPositionNFTBalance = positionManager.balanceOf(
            address(this)
        );
        uint256 postLiquidity = _getLiquidity(positionId);

        assertEq(
            postPositionNFTBalance,
            prePositionNFTBalance,
            "Position Balance changed"
        );
        assertGt(postLiquidity, preLiquidity, "Liquidity didn't increase");
        assertEq(
            positionManager.lockedUntil(positionId),
            block.timestamp + LP_TIMELOCK
        );
    }

    function testIncreaseLiquidity_withVTokens() external {
        uint256 positionId = _mintPositionWithTwap(currentNFTPrice);
        uint256 preTimelock = positionManager.lockedUntil(positionId);

        uint256 prePositionNFTBalance = positionManager.balanceOf(
            address(this)
        );
        uint256 preLiquidity = _getLiquidity(positionId);

        uint256 qty = 5;
        (uint256 mintedVTokens, ) = _mintVToken(qty);

        vtoken.approve(address(nftxRouter), mintedVTokens);
        positionManager.setApprovalForAll(address(nftxRouter), true);
        nftxRouter.increaseLiquidity{value: qty * 100 ether}(
            INFTXRouter.IncreaseLiquidityParams({
                positionId: positionId,
                vaultId: VAULT_ID,
                vTokensAmount: mintedVTokens,
                nftIds: emptyIds,
                nftAmounts: emptyIds,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        uint256 postPositionNFTBalance = positionManager.balanceOf(
            address(this)
        );
        uint256 postLiquidity = _getLiquidity(positionId);

        assertEq(
            postPositionNFTBalance,
            prePositionNFTBalance,
            "Position Balance changed"
        );
        assertGt(postLiquidity, preLiquidity, "Liquidity didn't increase");
        assertEq(
            positionManager.lockedUntil(positionId),
            preTimelock,
            "Timelock got updated"
        );
    }

    function testIncreaseLiquidity_withNFTs_and_VTokens() external {
        uint256 positionId = _mintPositionWithTwap(currentNFTPrice);
        // after timelock ended
        vm.warp(positionManager.lockedUntil(positionId) + 1);

        uint256 prePositionNFTBalance = positionManager.balanceOf(
            address(this)
        );
        uint256 preLiquidity = _getLiquidity(positionId);

        uint256 qty = 5;

        (uint256 mintedVTokens, ) = _mintVToken(qty);
        uint256[] memory tokenIds = nft.mint(qty);

        vtoken.approve(address(nftxRouter), mintedVTokens);
        nft.setApprovalForAll(address(nftxRouter), true);
        positionManager.setApprovalForAll(address(nftxRouter), true);
        nftxRouter.increaseLiquidity{value: qty * 100 ether}(
            INFTXRouter.IncreaseLiquidityParams({
                positionId: positionId,
                vaultId: VAULT_ID,
                vTokensAmount: mintedVTokens,
                nftIds: tokenIds,
                nftAmounts: emptyIds,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        uint256 postPositionNFTBalance = positionManager.balanceOf(
            address(this)
        );
        uint256 postLiquidity = _getLiquidity(positionId);

        assertEq(
            postPositionNFTBalance,
            prePositionNFTBalance,
            "Position Balance changed"
        );
        assertGt(postLiquidity, preLiquidity, "Liquidity didn't increase");
        assertEq(
            positionManager.lockedUntil(positionId),
            block.timestamp + LP_TIMELOCK
        );
    }

    // 1155

    function testIncreaseLiquidity_withNFTs_1155() external {
        uint256 positionId = _mintPositionWithTwap1155(currentNFTPrice);
        // after timelock ended
        vm.warp(positionManager.lockedUntil(positionId) + 1);

        uint256 qty = 3;
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        tokenIds[0] = nft1155.mint(qty);
        amounts[0] = qty;

        uint256 prePositionNFTBalance = positionManager.balanceOf(
            address(this)
        );
        uint256 preLiquidity = _getLiquidity(positionId);

        positionManager.setApprovalForAll(address(nftxRouter), true);
        nftxRouter.increaseLiquidity{value: qty * 100 ether}(
            INFTXRouter.IncreaseLiquidityParams({
                positionId: positionId,
                vaultId: VAULT_ID_1155,
                vTokensAmount: 0,
                nftIds: tokenIds,
                nftAmounts: amounts,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        uint256 postPositionNFTBalance = positionManager.balanceOf(
            address(this)
        );
        uint256 postLiquidity = _getLiquidity(positionId);

        assertEq(
            postPositionNFTBalance,
            prePositionNFTBalance,
            "Position Balance changed"
        );
        assertGt(postLiquidity, preLiquidity, "Liquidity didn't increase");
        assertEq(
            positionManager.lockedUntil(positionId),
            block.timestamp + LP_TIMELOCK
        );
    }

    // increaseLiquidityWithPermit2

    function testIncreaseLiquidityWithPermit2_withVTokens() external {
        uint256 positionId = _mintPositionWithTwap(currentNFTPrice);
        uint256 preTimelock = positionManager.lockedUntil(positionId);

        uint256 prePositionNFTBalance = positionManager.balanceOf(
            address(this)
        );
        uint256 preLiquidity = _getLiquidity(positionId);

        uint256 qty = 5;
        (uint256 mintedVTokens, ) = _mintVToken(qty);
        vtoken.transfer(from, mintedVTokens);
        startHoax(from);

        bytes memory encodedPermit2 = _getEncodedPermit2(
            address(vtoken),
            mintedVTokens,
            address(nftxRouter)
        );

        nftxRouter.increaseLiquidityWithPermit2{value: qty * 100 ether}(
            INFTXRouter.IncreaseLiquidityParams({
                positionId: positionId,
                vaultId: VAULT_ID,
                vTokensAmount: mintedVTokens,
                nftIds: emptyIds,
                nftAmounts: emptyIds,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            }),
            encodedPermit2
        );

        uint256 postPositionNFTBalance = positionManager.balanceOf(
            address(this)
        );
        uint256 postLiquidity = _getLiquidity(positionId);

        assertEq(
            postPositionNFTBalance,
            prePositionNFTBalance,
            "Position Balance changed"
        );
        assertGt(postLiquidity, preLiquidity, "Liquidity didn't increase");
        assertEq(
            positionManager.lockedUntil(positionId),
            preTimelock,
            "Timelock got updated"
        );
    }

    function testIncreaseLiquidityWithPermit2_withNFTs_and_VTokens() external {
        uint256 positionId = _mintPositionWithTwap(currentNFTPrice);
        // after timelock ended
        vm.warp(positionManager.lockedUntil(positionId) + 1);

        uint256 prePositionNFTBalance = positionManager.balanceOf(
            address(this)
        );
        uint256 preLiquidity = _getLiquidity(positionId);

        uint256 qty = 5;

        (uint256 mintedVTokens, ) = _mintVToken(qty);
        vtoken.transfer(from, mintedVTokens);

        startHoax(from);
        uint256[] memory tokenIds = nft.mint(qty);

        bytes memory encodedPermit2 = _getEncodedPermit2(
            address(vtoken),
            mintedVTokens,
            address(nftxRouter)
        );

        nft.setApprovalForAll(address(nftxRouter), true);
        nftxRouter.increaseLiquidityWithPermit2{value: qty * 100 ether}(
            INFTXRouter.IncreaseLiquidityParams({
                positionId: positionId,
                vaultId: VAULT_ID,
                vTokensAmount: mintedVTokens,
                nftIds: tokenIds,
                nftAmounts: emptyIds,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            }),
            encodedPermit2
        );

        uint256 postPositionNFTBalance = positionManager.balanceOf(
            address(this)
        );
        uint256 postLiquidity = _getLiquidity(positionId);

        assertEq(
            postPositionNFTBalance,
            prePositionNFTBalance,
            "Position Balance changed"
        );
        assertGt(postLiquidity, preLiquidity, "Liquidity didn't increase");
        assertEq(
            positionManager.lockedUntil(positionId),
            block.timestamp + LP_TIMELOCK
        );
    }

    // ================================
    // Sell NFTs
    // ================================

    function testSellNFTs() external {
        _mintPositionWithTwap(currentNFTPrice);
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

    function testSellNFTs_1155() external {
        _mintPositionWithTwap1155(currentNFTPrice);
        _mintPosition1155(5);

        uint256 nftQty = 5;
        uint256 preETHBalance = address(this).balance;

        _sellNFTs1155(nftQty);

        uint256 postETHBalance = address(this).balance;
        assertGt(postETHBalance, preETHBalance, "ETH balance didn't increase");

        console.log(
            "ETH received: %s for selling %s NFTs",
            postETHBalance - preETHBalance,
            nftQty
        );
    }

    // ================================
    // Buy NFTs
    // ================================

    function testBuyNFTs() external {
        _mintPositionWithTwap(currentNFTPrice);
        (uint256[] memory allTokenIds, , , , ) = _mintPosition(5);

        uint256 nftQty = 2;

        // buy first 2 NFTs from this position/pool
        uint256[] memory nftIds = new uint256[](nftQty);
        nftIds[0] = allTokenIds[0];
        nftIds[1] = allTokenIds[1];

        // fetch price to pay for those NFTs
        (, uint256 redeemFee, ) = vtoken.vaultFees();
        uint256 vTokenPremium = redeemFee * nftIds.length;
        for (uint256 i; i < nftIds.length; i++) {
            uint256 _vTokenPremium;
            (_vTokenPremium, ) = vtoken.getVTokenPremium721(nftIds[i]);
            vTokenPremium += _vTokenPremium;
        }
        uint256 ethRequired = nftxRouter.quoteBuyNFTs({
            vtoken: address(vtoken),
            nftsCount: nftIds.length,
            fee: DEFAULT_FEE_TIER,
            sqrtPriceLimitX96: 0
        }) + vtoken.vTokenToETH(vTokenPremium);

        uint256 preNFTBalance = nft.balanceOf(address(this));
        uint256 preETHBalance = address(this).balance;

        // execute swap
        nftxRouter.buyNFTs{value: ethRequired}(
            INFTXRouter.BuyNFTsParams({
                vaultId: VAULT_ID,
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

    // 1155

    function testBuyNFTs_1155() external {
        _mintPositionWithTwap1155(currentNFTPrice);
        (uint256[] memory allTokenIds, , , , ) = _mintPosition1155(5);

        uint256 nftQty = 2;

        // buy first 2 NFTs from this position/pool
        uint256[] memory nftIds = new uint256[](nftQty);
        nftIds[0] = allTokenIds[0];
        nftIds[1] = allTokenIds[0];

        // fetch price to pay for those NFTs
        (uint256 vTokenPremium, , ) = vtoken1155.getVTokenPremium1155(
            nftIds[0],
            nftQty
        );
        (, uint256 redeemFee, ) = vtoken1155.vaultFees();
        uint256 vTokenFee = redeemFee * nftIds.length + vTokenPremium;

        uint256 ethRequired = nftxRouter.quoteBuyNFTs({
            vtoken: address(vtoken1155),
            nftsCount: nftIds.length,
            fee: DEFAULT_FEE_TIER,
            sqrtPriceLimitX96: 0
        }) + vtoken1155.vTokenToETH(vTokenFee);

        uint256 preNFTBalance = nft1155.balanceOf(
            address(this),
            allTokenIds[0]
        );
        uint256 preETHBalance = address(this).balance;

        // execute swap
        nftxRouter.buyNFTs{value: ethRequired}(
            INFTXRouter.BuyNFTsParams({
                vaultId: VAULT_ID_1155,
                nftIds: nftIds,
                deadline: block.timestamp,
                fee: DEFAULT_FEE_TIER,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 postNFTBalance = nft1155.balanceOf(
            address(this),
            allTokenIds[0]
        );
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

    function test_removeLiquidity_RevertsIfTimelocked() external {
        (, uint256 positionId, , , ) = _mintPosition(
            10,
            currentNFTPrice,
            currentNFTPrice - 0.5 ether,
            currentNFTPrice + 0.5 ether,
            DEFAULT_FEE_TIER
        );
        assertGt(positionManager.lockedUntil(positionId), block.timestamp);

        positionManager.setApprovalForAll(address(nftxRouter), true);

        // vm.expectRevert() only detects the next top-level call, that's why adding `assertTrue` so the call status returns false
        (bool status, ) = address(nftxRouter).call(
            abi.encodeWithSelector(
                INFTXRouter.removeLiquidity.selector,
                INFTXRouter.RemoveLiquidityParams({
                    positionId: positionId,
                    vaultId: VAULT_ID,
                    nftIds: emptyIds,
                    liquidity: _getLiquidity(positionId),
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                })
            )
        );
        assertTrue(!status, "expectRevert: call did not revert");
    }

    function test_removeLiquidity_ToNFTs_Success() external {
        uint256 _positionId = _mintPositionWithTwap(currentNFTPrice);
        // after timelock ended
        vm.warp(positionManager.lockedUntil(_positionId) + 1);
        uint256[] memory _nftIds;
        positionManager.setApprovalForAll(address(nftxRouter), true);
        // removing liquidity so the `nftsSold` only shared with one position
        nftxRouter.removeLiquidity(
            INFTXRouter.RemoveLiquidityParams({
                positionId: _positionId,
                vaultId: VAULT_ID,
                nftIds: _nftIds,
                liquidity: _getLiquidity(_positionId),
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        uint256 nftQty = 10;
        (
            uint256[] memory allTokenIds,
            uint256 positionId,
            ,
            ,

        ) = _mintPosition(nftQty);
        // after timelock ended
        vm.warp(positionManager.lockedUntil(positionId) + 1);

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

        // sending ETH as vault fees more than withdrawn amount
        nftxRouter.removeLiquidity{value: 300 ether}(
            INFTXRouter.RemoveLiquidityParams({
                positionId: positionId,
                vaultId: VAULT_ID,
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
        // Because in this case ETH fees > withdrawn amount. so preBal > postBal
        // though for most cases post > pre
        assertGt(preETHBalance, postETHBalance, "ETH balance didn't change");
        assertEq(
            positionManager.ownerOf(positionId),
            address(this),
            "User is no longer the owner of PositionId"
        );
    }

    function test_removeLiquidity_ToVTokens_Success() external {
        _mintPositionWithTwap(currentNFTPrice);
        uint256 nftQty = 10;
        (, uint256 positionId, , , ) = _mintPosition(nftQty);
        // after timelock ended
        vm.warp(positionManager.lockedUntil(positionId) + 1);

        _sellNFTs(5);

        uint128 liquidity = _getLiquidity(positionId);

        uint256 preVTokenBalance = vtoken.balanceOf(address(this));
        uint256 preETHBalance = address(this).balance;

        positionManager.setApprovalForAll(address(nftxRouter), true);
        nftxRouter.removeLiquidity(
            INFTXRouter.RemoveLiquidityParams({
                positionId: positionId,
                vaultId: VAULT_ID,
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

    // 1155

    function test_removeLiquidity_ToNFTs_Success_1155() external {
        uint256 _positionId = _mintPositionWithTwap1155(currentNFTPrice);
        vm.warp(positionManager.lockedUntil(_positionId) + 1);

        positionManager.setApprovalForAll(address(nftxRouter), true);
        // removing liquidity as vTokens so the `nftsSold` only shared with one position
        nftxRouter.removeLiquidity(
            INFTXRouter.RemoveLiquidityParams({
                positionId: _positionId,
                vaultId: VAULT_ID_1155,
                nftIds: emptyIds,
                liquidity: _getLiquidity(_positionId),
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        uint256 nftQty = 10;
        (
            uint256[] memory allTokenIds,
            uint256 positionId,
            ,
            ,

        ) = _mintPosition1155(nftQty);
        // after timelock ended
        vm.warp(positionManager.lockedUntil(positionId) + 1);

        uint256 nftsSold = 5;
        uint256[] memory soldTokenIds = _sellNFTs1155(nftsSold);

        uint256 nftResidue = 1;
        uint256 expectedNFTQty = nftQty + nftsSold - nftResidue;
        uint256[] memory nftIds = new uint256[](expectedNFTQty);
        nftIds[0] = allTokenIds[0];
        nftIds[1] = allTokenIds[0];
        nftIds[2] = allTokenIds[0];
        nftIds[3] = allTokenIds[0];
        nftIds[4] = allTokenIds[0];
        nftIds[5] = allTokenIds[0];
        nftIds[6] = allTokenIds[0];
        nftIds[7] = allTokenIds[0];
        nftIds[8] = allTokenIds[0];
        nftIds[9] = allTokenIds[0];
        nftIds[10] = soldTokenIds[0];
        nftIds[11] = soldTokenIds[0];
        nftIds[12] = soldTokenIds[0];
        nftIds[13] = soldTokenIds[0];
        // nftIds[14] = soldTokenIds[0]; // redeeming less NFT(s) than the vTokens withdrawn from liquidity position

        uint128 liquidity = _getLiquidity(positionId);

        uint256 preNFTBalance = nft1155.balanceOf(
            address(this),
            allTokenIds[0]
        ) + nft1155.balanceOf(address(this), soldTokenIds[0]);
        uint256 preVTokenBalance = vtoken1155.balanceOf(address(this));
        uint256 preETHBalance = address(this).balance;

        // sending ETH as vault fees more than withdrawn amount
        nftxRouter.removeLiquidity{value: 300 ether}(
            INFTXRouter.RemoveLiquidityParams({
                positionId: positionId,
                vaultId: VAULT_ID_1155,
                nftIds: nftIds,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        uint256 postNFTBalance = nft1155.balanceOf(
            address(this),
            allTokenIds[0]
        ) + nft1155.balanceOf(address(this), soldTokenIds[0]);
        uint256 postVTokenBalance = vtoken1155.balanceOf(address(this));
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
        // Because in this case ETH fees > withdrawn amount. so preBal > postBal
        // though for most cases post > pre
        assertGt(preETHBalance, postETHBalance, "ETH balance didn't change");
        assertEq(
            positionManager.ownerOf(positionId),
            address(this),
            "User is no longer the owner of PositionId"
        );
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

    // Helpers

    function _getTicks()
        internal
        view
        returns (int24 tickLower, int24 tickUpper, uint160 currentSqrtP)
    {
        uint256 lowerNFTPrice = 3 ether;
        uint256 upperNFTPrice = 6 ether;

        uint256 tickDistance = _getTickDistance(DEFAULT_FEE_TIER);
        if (nftxRouter.isVToken0(address(vtoken))) {
            currentSqrtP = TickHelpers.encodeSqrtRatioX96(
                currentNFTPrice,
                1 ether
            );
            // price = amount1 / amount0 = 1.0001^tick => tick ∝ price
            tickLower = TickHelpers.getTickForAmounts(
                lowerNFTPrice,
                1 ether,
                tickDistance
            );
            tickUpper = TickHelpers.getTickForAmounts(
                upperNFTPrice,
                1 ether,
                tickDistance
            );
        } else {
            currentSqrtP = TickHelpers.encodeSqrtRatioX96(
                1 ether,
                currentNFTPrice
            );
            tickLower = TickHelpers.getTickForAmounts(
                1 ether,
                upperNFTPrice,
                tickDistance
            );
            tickUpper = TickHelpers.getTickForAmounts(
                1 ether,
                lowerNFTPrice,
                tickDistance
            );
        }
    }
}
