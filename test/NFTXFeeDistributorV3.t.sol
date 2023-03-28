// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {console} from "forge-std/Test.sol";

import {UniswapV3Pool} from "@uni-core/UniswapV3Pool.sol";
import {INFTXRouter} from "@src/NFTXRouter.sol";
import {INFTXFeeDistributorV3} from "@src/interfaces/INFTXFeeDistributorV3.sol";

import {TestBase} from "./TestBase.sol";

contract NFTXFeeDistributorV3Tests is TestBase {
    event AddFeeReceiver(address receiver, uint256 allocPoint);
    event UpdateFeeReceiverAlloc(address receiver, uint256 allocPoint);
    event UpdateFeeReceiverAddress(address oldReceiver, address newReceiver);
    event RemoveFeeReceiver(address receiver);
    event UpdateTreasuryAddress(address newTreasury);
    event PauseDistribution(bool paused);

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
        feeDistributor.removeReceiver(0);
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

    function test_feeDistribution_Success() external {
        uint256 poolAllocPoint = 0.8 ether;
        uint256 inventoryAllocPoint = 0.15 ether;
        uint256 addressAllocPoint = 0.05 ether;

        address receiverAddress = makeAddr("receiverAddress");

        // add remaining types of receivers as well
        feeDistributor.addReceiver(
            address(inventoryStaking),
            inventoryAllocPoint,
            INFTXFeeDistributorV3.ReceiverType.INVENTORY
        );
        feeDistributor.addReceiver(
            receiverAddress,
            addressAllocPoint,
            INFTXFeeDistributorV3.ReceiverType.ADDRESS
        );

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
        // ethReceived = ethDeposited + poolWethFees + swapped 0.9999..99 vToken into ETH
        console.log("ETH received", ethReceived);
    }

    // FeeDistributor#addReceiver

    function test_addReceiver_RevertsForNonOwner() external {
        address newReceiver = makeAddr("newReceiver");

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        feeDistributor.addReceiver(
            newReceiver,
            0.2 ether,
            INFTXFeeDistributorV3.ReceiverType.ADDRESS
        );
    }

    function test_addReceiver_Success() external {
        address newReceiver = makeAddr("newReceiver");
        uint256 allocPoint = 0.2 ether;

        uint256 prevAllocTotal = feeDistributor.allocTotal();

        vm.expectEmit(false, false, false, true);
        emit AddFeeReceiver(newReceiver, allocPoint);
        feeDistributor.addReceiver(
            newReceiver,
            allocPoint,
            INFTXFeeDistributorV3.ReceiverType.ADDRESS
        );

        uint256 postAllocTotal = feeDistributor.allocTotal();
        (
            address _receiver,
            uint256 _allocPoint,
            INFTXFeeDistributorV3.ReceiverType _receiverType
        ) = feeDistributor.feeReceivers(1);

        assertEq(postAllocTotal, prevAllocTotal + allocPoint);
        assertEq(_receiver, newReceiver);
        assertEq(_allocPoint, allocPoint);
        assertEq(
            uint8(_receiverType),
            uint8(INFTXFeeDistributorV3.ReceiverType.ADDRESS)
        );
    }

    // FeeDistributor#changeReceiverAlloc

    function test_changeReceiverAlloc_RevertsForNonOwner() external {
        uint256 receiverId = 0;
        uint256 newAllocPoint = 0.5 ether;

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        feeDistributor.changeReceiverAlloc(receiverId, newAllocPoint);
    }

    function test_changeReceiverAlloc_RevertsForIdOutOfBounds() external {
        uint256 receiverId = 10;
        uint256 newAllocPoint = 0.5 ether;

        vm.expectRevert(INFTXFeeDistributorV3.IdOutOfBounds.selector);
        feeDistributor.changeReceiverAlloc(receiverId, newAllocPoint);
    }

    function test_changeReceiverAlloc_Success() external {
        uint256 receiverId = 0;
        uint256 newAllocPoint = 0.5 ether;

        uint256 prevAllocTotal = feeDistributor.allocTotal();
        (
            address preReceiver,
            uint256 preAllocPoint,
            INFTXFeeDistributorV3.ReceiverType preReceiverType
        ) = feeDistributor.feeReceivers(receiverId);

        assertTrue(preAllocPoint != newAllocPoint);

        vm.expectEmit(false, false, false, true);
        emit UpdateFeeReceiverAlloc(preReceiver, newAllocPoint);
        feeDistributor.changeReceiverAlloc(receiverId, newAllocPoint);

        uint256 postAllocTotal = feeDistributor.allocTotal();
        (
            address postReceiver,
            uint256 postAllocPoint,
            INFTXFeeDistributorV3.ReceiverType postReceiverType
        ) = feeDistributor.feeReceivers(receiverId);

        assertEq(
            postAllocTotal,
            prevAllocTotal - preAllocPoint + newAllocPoint
        );
        assertEq(postAllocPoint, newAllocPoint);
        assertEq(postReceiver, preReceiver);
        assertEq(uint8(postReceiverType), uint8(preReceiverType));
    }

    // FeeDistributor#changeReceiverAddress

    function test_changeReceiverAddress_RevertsForNonOwner() external {
        uint256 receiverId = 0;
        address newReceiver = makeAddr("newReceiver");

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        feeDistributor.changeReceiverAddress(
            receiverId,
            newReceiver,
            INFTXFeeDistributorV3.ReceiverType.ADDRESS
        );
    }

    function test_changeReceiverAddress_RevertsForIdOutOfBounds() external {
        uint256 receiverId = 10;
        address newReceiver = makeAddr("newReceiver");

        vm.expectRevert(INFTXFeeDistributorV3.IdOutOfBounds.selector);
        feeDistributor.changeReceiverAddress(
            receiverId,
            newReceiver,
            INFTXFeeDistributorV3.ReceiverType.ADDRESS
        );
    }

    function test_changeReceiverAddress_Success() external {
        uint256 receiverId = 0;
        address newReceiver = makeAddr("newReceiver");
        INFTXFeeDistributorV3.ReceiverType newReceiverType = INFTXFeeDistributorV3
                .ReceiverType
                .ADDRESS;

        uint256 prevAllocTotal = feeDistributor.allocTotal();
        (
            address preReceiver,
            uint256 preAllocPoint,
            INFTXFeeDistributorV3.ReceiverType preReceiverType
        ) = feeDistributor.feeReceivers(receiverId);

        assertTrue(preReceiver != newReceiver);
        assertTrue(uint8(preReceiverType) != uint8(newReceiverType));

        vm.expectEmit(false, false, false, true);
        emit UpdateFeeReceiverAddress(preReceiver, newReceiver);
        feeDistributor.changeReceiverAddress(
            receiverId,
            newReceiver,
            newReceiverType
        );

        uint256 postAllocTotal = feeDistributor.allocTotal();
        (
            address postReceiver,
            uint256 postAllocPoint,
            INFTXFeeDistributorV3.ReceiverType postReceiverType
        ) = feeDistributor.feeReceivers(receiverId);

        assertEq(postReceiver, newReceiver);
        assertEq(uint8(postReceiverType), uint8(newReceiverType));
        assertEq(postAllocPoint, preAllocPoint);
        assertEq(postAllocTotal, prevAllocTotal);
    }

    // FeeDistributor#changeReceiverAddress

    function test_removeReceiver_RevertsForNonOwner() external {
        uint256 receiverId = 0;

        hoax(makeAddr("nonOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        feeDistributor.removeReceiver(receiverId);
    }

    function test_removeReceiver_RevertsForIdOutOfBounds() external {
        uint256 receiverId = 10;

        vm.expectRevert(INFTXFeeDistributorV3.IdOutOfBounds.selector);
        feeDistributor.removeReceiver(receiverId);
    }

    function test_removeReceiver_Success() external {
        uint256 receiverId = 0;

        uint256 prevAllocTotal = feeDistributor.allocTotal();
        (address preReceiver, uint256 preAllocPoint, ) = feeDistributor
            .feeReceivers(receiverId);

        vm.expectEmit(false, false, false, true);
        emit RemoveFeeReceiver(preReceiver);
        feeDistributor.removeReceiver(receiverId);

        uint256 postAllocTotal = feeDistributor.allocTotal();

        assertEq(postAllocTotal, prevAllocTotal - preAllocPoint);

        vm.expectRevert();
        feeDistributor.feeReceivers(receiverId);
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

        vm.expectRevert(INFTXFeeDistributorV3.AddressIsZero.selector);
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
