// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";
import {TickHelpers} from "@src/lib/TickHelpers.sol";

import {UniswapV3PoolUpgradeable, IUniswapV3Pool} from "@uni-core/UniswapV3PoolUpgradeable.sol";
import {INFTXRouter} from "@src/NFTXRouter.sol";
import {INFTXFeeDistributorV3} from "@src/interfaces/INFTXFeeDistributorV3.sol";

import {TestBase} from "@test/TestBase.sol";

contract NFTXFeeDistributorV3Tests is TestBase {
    event AddFeeReceiver(address receiver, uint256 allocPoint);
    event UpdateFeeReceiverAlloc(address receiver, uint256 allocPoint);
    event UpdateFeeReceiverAddress(address oldReceiver, address newReceiver);
    event RemoveFeeReceiver(address receiver);
    event UpdateTreasuryAddress(address newTreasury);
    event PauseDistribution(bool paused);

    // UniswapV3FactoryUpgradeable#setFeeDistributor

    function test_setFeeDistributor_RevertsForNonOwner() external {
        hoax(makeAddr("nonOwner"));
        vm.expectRevert();
        factory.setFeeDistributor(address(feeDistributor));
    }

    function test_setFeeDistributor_Success() external {
        address newFeeDistributor = makeAddr("newFeeDistributor");

        address preFeeDistributor = factory.feeDistributor();
        assertTrue(preFeeDistributor != newFeeDistributor);

        factory.setFeeDistributor(newFeeDistributor);
        assertEq(factory.feeDistributor(), newFeeDistributor);
    }

    // UniswapV3PoolUpgradeable#distributeRewards

    function test_distributeRewards_RevertsForNonFeeDistributor() external {
        // minting so that Pool is deployed
        _mintPosition(1);
        UniswapV3PoolUpgradeable pool = UniswapV3PoolUpgradeable(
            nftxRouter.getPool(address(vtoken), DEFAULT_FEE_TIER)
        );

        hoax(makeAddr("nonFeeDistributor"));
        vm.expectRevert();
        pool.distributeRewards(1 ether, true);
    }

    // FeeDistributor#distribute

    function test_feeDistribuion_whenDistributionPaused() external {
        _mintPosition(1);

        // Pause distribution
        feeDistributor.pauseFeeDistribution(true);
        assertEq(feeDistributor.distributionPaused(), true);

        uint256 preTreasuryWethBalance = weth.balanceOf(TREASURY);

        uint256 wethFees = 2 ether;

        // distribute fees
        weth.deposit{value: wethFees}();
        weth.transfer(address(feeDistributor), wethFees);
        feeDistributor.distribute(0);

        uint256 postTreasuryWethBalance = weth.balanceOf(TREASURY);
        assertEq(postTreasuryWethBalance - preTreasuryWethBalance, wethFees);
    }

    function test_feeDistribuion_whenZeroAllocTotal() external {
        _mintPosition(1);

        // Remove all receivers
        INFTXFeeDistributorV3.FeeReceiver[] memory feeReceivers;
        feeDistributor.setReceivers(feeReceivers);
        assertEq(feeDistributor.allocTotal(), 0);

        uint256 preTreasuryWethBalance = weth.balanceOf(TREASURY);

        uint256 wethFees = 2 ether;

        // distribute fees
        weth.deposit{value: wethFees}();
        weth.transfer(address(feeDistributor), wethFees);
        feeDistributor.distribute(0);

        uint256 postTreasuryWethBalance = weth.balanceOf(TREASURY);
        assertEq(postTreasuryWethBalance - preTreasuryWethBalance, wethFees);
    }

    function test_feeDistribution_whenZeroLiquidity() external {
        // remove inventory staking from receiver
        INFTXFeeDistributorV3.FeeReceiver[]
            memory feeReceivers = new INFTXFeeDistributorV3.FeeReceiver[](1);
        feeReceivers[0] = INFTXFeeDistributorV3.FeeReceiver({
            receiver: address(0),
            allocPoint: 1 ether,
            receiverType: INFTXFeeDistributorV3.ReceiverType.POOL
        });
        feeDistributor.setReceivers(feeReceivers);

        // deploy pool, but not provide any liquidity
        positionManager.createAndInitializePoolIfNecessary(
            address(vtoken) < address(weth) ? address(vtoken) : address(weth),
            address(vtoken) < address(weth) ? address(weth) : address(vtoken),
            feeDistributor.rewardFeeTier(),
            TickHelpers.encodeSqrtRatioX96(5 ether, 1 ether)
        );

        (address pool, bool exists) = nftxRouter.getPoolExists(
            0,
            feeDistributor.rewardFeeTier()
        );
        uint256 liquidity = IUniswapV3Pool(pool).liquidity();
        assertTrue(exists);
        assertEq(liquidity, 0);

        uint256 wethFees = 2 ether;

        uint256 preTreasuryWethBalance = weth.balanceOf(TREASURY);

        // distribute fees
        weth.deposit{value: wethFees}();
        weth.transfer(address(feeDistributor), wethFees);
        feeDistributor.distribute(0);

        uint256 postTreasuryWethBalance = weth.balanceOf(TREASURY);
        assertEq(postTreasuryWethBalance - preTreasuryWethBalance, wethFees);
    }

    function test_feeDistribution_Success() external {
        uint256 poolAllocPoint = 0.8 ether; // this value is set in the constructor of NFTXFeeDistributorV3
        uint256 inventoryAllocPoint = 0.15 ether; // this value is different from the one set in constructor, so updating below
        uint256 addressAllocPoint = 0.05 ether;

        address receiverAddress = makeAddr("receiverAddress");

        // add remaining types of receivers as well
        {
            INFTXFeeDistributorV3.FeeReceiver[]
                memory feeReceivers = new INFTXFeeDistributorV3.FeeReceiver[](
                    3
                );
            feeReceivers[0] = INFTXFeeDistributorV3.FeeReceiver({
                receiver: address(0),
                allocPoint: poolAllocPoint,
                receiverType: INFTXFeeDistributorV3.ReceiverType.POOL
            });
            feeReceivers[1] = INFTXFeeDistributorV3.FeeReceiver({
                receiver: address(inventoryStaking),
                allocPoint: inventoryAllocPoint,
                receiverType: INFTXFeeDistributorV3.ReceiverType.INVENTORY
            });
            feeReceivers[2] = INFTXFeeDistributorV3.FeeReceiver({
                receiver: receiverAddress,
                allocPoint: addressAllocPoint,
                receiverType: INFTXFeeDistributorV3.ReceiverType.ADDRESS
            });
            feeDistributor.setReceivers(feeReceivers);
        }

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

        {
            // stake vTokens so that inventoryStaking has stakers to distribute to
            (uint256 mintedVTokens, ) = _mintVToken(1);
            vtoken.approve(address(inventoryStaking), type(uint256).max);
            inventoryStaking.deposit(
                0,
                mintedVTokens,
                address(this),
                "",
                false,
                false
            );

            (uint256 totalVTokenShares, ) = inventoryStaking.vaultGlobal(0);
            console.log("totalVTokenShares", totalVTokenShares);
        }

        uint256 preInventoryStakingWethBalance = weth.balanceOf(
            address(inventoryStaking)
        );
        uint256 preReceiverAddressWethBalance = weth.balanceOf(
            address(receiverAddress)
        );

        uint256 wethFees = 2 ether;

        // distribute fees
        weth.deposit{value: wethFees}();
        weth.transfer(address(feeDistributor), wethFees);
        feeDistributor.distribute(0);

        uint256 postInventoryStakingWethBalance = weth.balanceOf(
            address(inventoryStaking)
        );
        uint256 postReceiverAddressWethBalance = weth.balanceOf(
            address(receiverAddress)
        );

        uint256 expectedPoolWethFees = (wethFees * poolAllocPoint) / 1 ether;

        // NOTE: We have 2 LP positions with the exact same liquidity. So the fees is distributed equally between them both
        // So for wethFees = 2, each position should get 1 weth as fees, but due to rounding gets 0.999..999 of weth as fees

        // Findings: On liquidity withdrawal 1 wei gets left in the pool as well.
        // So 1 wei of distributed weth and 1 wei from initial provided liquidity gets stuck in the pool (for a total of 2 wei)

        (, uint256 poolWethFees) = _getAccumulatedFees(positionId);
        console.log("poolWethFees", poolWethFees);
        assertGe(poolWethFees, expectedPoolWethFees / 2 - 1);
        assertEq(
            postInventoryStakingWethBalance - preInventoryStakingWethBalance,
            (wethFees * inventoryAllocPoint) / 1 ether
        );
        assertEq(
            postReceiverAddressWethBalance - preReceiverAddressWethBalance,
            (wethFees * addressAllocPoint) / 1 ether
        );

        // remove liquidity
        uint256[] memory nftIds = new uint256[](mintQty - 1); // accounting for that 1 wei difference allows us to redeem 1 less NFT
        nftIds[0] = mintTokenIds[0];
        nftIds[1] = mintTokenIds[1];
        nftIds[2] = mintTokenIds[2];
        nftIds[3] = mintTokenIds[3];
        // nftIds[4] = mintTokenIds[4];

        uint128 liquidity = _getLiquidity(positionId);
        vm.warp(positionManager.lockedUntil(positionId) + 1);

        uint256 preNFTBalance = nft.balanceOf(address(this));
        uint256 preETHBalance = address(this).balance;

        positionManager.setApprovalForAll(address(nftxRouter), true);
        nftxRouter.removeLiquidity(
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

        uint256 nftReceived = nft.balanceOf(address(this)) - preNFTBalance;
        uint256 ethReceived = address(this).balance - preETHBalance;

        console.log("NFT received", nftReceived);
        // ethReceived = ethDeposited + poolWethFees + swapped 0.9999..99 vToken into ETH
        console.log("ETH received", ethReceived);
    }

    // FeeDistributor#setTreasuryAddress

    function test_setTreasuryAddress_RevertsForNonOwner() external {
        address newTreasury = makeAddr("newTreasury");

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        feeDistributor.setTreasuryAddress(newTreasury);
    }

    function test_setTreasuryAddress_RevertsForNullAddress() external {
        address newTreasury = address(0);

        vm.expectRevert(INFTXFeeDistributorV3.ZeroAddress.selector);
        feeDistributor.setTreasuryAddress(newTreasury);
    }

    function test_setTreasuryAddress_Success() external {
        address newTreasury = makeAddr("newTreasury");

        address preTreasury = feeDistributor.treasury();
        assertTrue(preTreasury != newTreasury);

        vm.expectEmit(false, false, false, true);
        emit UpdateTreasuryAddress(newTreasury);
        feeDistributor.setTreasuryAddress(newTreasury);

        address postTreasury = feeDistributor.treasury();
        assertEq(postTreasury, newTreasury);
    }

    // FeeDistributor#setNFTXRouter

    function test_setNFTXRouter_RevertsForNonOwner() external {
        address newNFTXRouter = makeAddr("newNFTXRouter");

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        feeDistributor.setNFTXRouter(INFTXRouter(newNFTXRouter));
    }

    function test_setNFTXRouter_Success() external {
        address newNFTXRouter = makeAddr("newNFTXRouter");

        address preNFTXRouter = address(feeDistributor.nftxRouter());
        assertTrue(preNFTXRouter != newNFTXRouter);

        feeDistributor.setNFTXRouter(INFTXRouter(newNFTXRouter));

        address postNFTXRouter = address(feeDistributor.nftxRouter());
        assertEq(postNFTXRouter, newNFTXRouter);
    }

    // FeeDistributor#pauseFeeDistribution

    function test_pauseFeeDistribution_RevertsForNonOwner() external {
        bool newPause = true;

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        feeDistributor.pauseFeeDistribution(newPause);
    }

    function test_pauseFeeDistribution_Success() external {
        bool preDistributionPaused = feeDistributor.distributionPaused();

        bool newPause = !preDistributionPaused;

        vm.expectEmit(false, false, false, true);
        emit PauseDistribution(newPause);
        feeDistributor.pauseFeeDistribution(newPause);

        bool postDistributionPaused = feeDistributor.distributionPaused();

        assertEq(postDistributionPaused, newPause);
    }

    // FeeDistributor#rescueTokens

    function test_rescueTokens_RevertsForNonOwner() external {
        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        feeDistributor.rescueTokens(weth);
    }

    function test_rescueTokens_Success() external {
        // send tokens to be rescued
        uint256 tokenAmt = 5 ether;
        weth.deposit{value: tokenAmt}();
        weth.transfer(address(feeDistributor), tokenAmt);

        uint256 preOwnerTokenBalance = weth.balanceOf(address(this));

        feeDistributor.rescueTokens(weth);

        uint256 postOwnerTokenBalance = weth.balanceOf(address(this));
        assertEq(postOwnerTokenBalance - preOwnerTokenBalance, tokenAmt);
    }
}
