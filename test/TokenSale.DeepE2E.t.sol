// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TokenSale} from "src/sale/TokenSale.sol";
import {Treasury} from "src/treasury/Treasury.sol";
import {EmyoToken} from "src/token/EmyoToken.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {Roles} from "src/access/Roles.sol";
import {Errors} from "src/libs/Errors.sol";

/// @title TokenSale Deep E2E Tests
/// @notice Complex end-to-end scenarios testing the entire sale flow
contract TokenSaleDeepE2ETest is Test {
    MockERC20 paymentToken;
    EmyoToken saleToken;
    Treasury treasury;
    TokenSale sale;

    address admin = address(0xA11CE);
    address buyer1 = address(0xB0B1);
    address buyer2 = address(0xB0B2);
    address buyer3 = address(0xB0B3);
    address buyer4 = address(0xB0B4);
    address buyer5 = address(0xB0B5);

    function setUp() public {
        paymentToken = new MockERC20("USDC", "USDC", 6);
        treasury = new Treasury(admin);
        saleToken = new EmyoToken("Emyo", "EMY", 10_000_000 ether, address(treasury));
        sale = new TokenSale(paymentToken, saleToken, address(treasury), admin);

        // Fund users with payment tokens
        paymentToken.mint(buyer1, 1_000_000e6);
        paymentToken.mint(buyer2, 1_000_000e6);
        paymentToken.mint(buyer3, 1_000_000e6);
        paymentToken.mint(buyer4, 1_000_000e6);
        paymentToken.mint(buyer5, 1_000_000e6);
        
        vm.startPrank(buyer1);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(buyer2);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(buyer3);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(buyer4);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(buyer5);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();

        // Fund sale contract with tokens for vesting releases
        vm.prank(admin);
        treasury.withdrawERC20(saleToken, address(sale), 5_000_000 ether);
    }

    /// @notice Complex scenario: 3 stages, multiple users, different purchase patterns, vesting releases
    /// Stage 1: 1 week, 8 months vesting [10, 10, 10, 10, 10, 10, 20, 20] (8 periods)
    /// Stage 2: 2 weeks, 6 months vesting [16.67, 16.67, 16.67, 16.67, 16.67, 16.65] (6 periods)
    /// Stage 3: 1 month, 3 months vesting [33.33, 33.33, 33.34] (3 periods)
    function test_DeepE2E_ThreeStages_MultipleUsers_ComplexVesting() public {
        uint64 nowTs = uint64(block.timestamp);
        
        // Stage 1: 1 week long, 8 months vesting (8 periods of 1 month each)
        uint16[] memory percentages1 = new uint16[](8);
        percentages1[0] = 1000; percentages1[1] = 1000; percentages1[2] = 1000; percentages1[3] = 1000;
        percentages1[4] = 1000; percentages1[5] = 1000; percentages1[6] = 2000; percentages1[7] = 2000;

        // Stage 2: 2 weeks long, 6 months vesting
        uint16[] memory percentages2 = new uint16[](6);
        percentages2[0] = 1667; percentages2[1] = 1667; percentages2[2] = 1667;
        percentages2[3] = 1667; percentages2[4] = 1667; percentages2[5] = 1665;

        // Stage 3: 1 month long, 3 months vesting
        uint16[] memory percentages3 = new uint16[](3);
        percentages3[0] = 3333; percentages3[1] = 3333; percentages3[2] = 3334;

        uint64 vestStart0 = nowTs + 7 days + 3 days;
        uint64 vestStart1 = nowTs + 21 days + 3 days;
        uint64 vestStart2 = nowTs + 51 days + 3 days;
        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, vestStart0, 30 days, percentages1);
        sale.addStage(50, nowTs + 21 days, vestStart1, 30 days, percentages2);
        sale.addStage(33, nowTs + 51 days, vestStart2, 30 days, percentages3);
        sale.setTotalCap(3_000_000 ether);
        vm.stopPrank();

        // Buyer1: Purchases in Stage 0, then Stage 1, then Stage 2 (creates 3 separate schedules)
        vm.warp(nowTs + 7 days - 1);
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0)); // 100k tokens in stage 0

        vm.warp(nowTs + 7 days + 1);
        vm.prank(buyer1);
        sale.buy(50e6, new bytes32[](0)); // 200k tokens in stage 1 (50e6 * 100000 * 1e12 / 50)

        vm.warp(nowTs + 21 days + 1);
        vm.prank(buyer1);
        sale.buy(33e6, new bytes32[](0)); // 100k tokens in stage 2 (33e6 * 100000 * 1e12 / 33)

        // Buyer2: Purchases only in Stage 1
        vm.warp(nowTs + 7 days + 1);
        vm.prank(buyer2);
        sale.buy(200e6, new bytes32[](0)); // 400k tokens in stage 1

        // Buyer3: Purchases in Stage 0 and Stage 2
        vm.warp(nowTs);
        vm.prank(buyer3);
        sale.buy(150e6, new bytes32[](0)); // 150k tokens in stage 0

        vm.warp(nowTs + 21 days + 1);
        uint256 paymentFor75k = (75_000 ether * 33) / (sale.PRICE_SCALE() * sale.decimalScale());
        vm.prank(buyer3);
        sale.buy(uint128(paymentFor75k), new bytes32[](0)); // 75k tokens in stage 2

        // Buyer4: Purchases multiple times in Stage 0 (aggregates in same schedule)
        vm.warp(nowTs);
        vm.startPrank(buyer4);
        sale.buy(50e6, new bytes32[](0)); // 50k tokens
        sale.buy(30e6, new bytes32[](0)); // 30k tokens
        sale.buy(20e6, new bytes32[](0)); // 20k tokens
        vm.stopPrank();

        // Buyer5: Purchases at the very end of Stage 2
        vm.warp(nowTs + 51 days - 1);
        vm.prank(buyer5);
        sale.buy(100e6, new bytes32[](0)); // ~303k tokens in stage 2 (100e6 * 100000 * 1e12 / 33)

        // Verify buyer1 schedules (3 separate schedules - one per stage)
        (uint128 total1_0, , uint64 start1_0, uint64 periodLength1_0, uint16[] memory sched1_0) = 
            sale.getVestingSchedule(buyer1, 0);
        assertEq(total1_0, 100_000 ether);
        assertEq(start1_0, vestStart0);
        assertEq(periodLength1_0, 30 days);
        assertEq(sched1_0.length, 8);

        (uint128 total1_1, , uint64 start1_1, uint64 periodLength1_1, uint16[] memory sched1_1) = 
            sale.getVestingSchedule(buyer1, 1);
        assertEq(total1_1, 100_000 ether); // 50e6 * 100000 * 1e12 / 50 = 100k tokens
        assertEq(start1_1, vestStart1);
        assertEq(periodLength1_1, 30 days);
        assertEq(sched1_1.length, 6);

        (uint128 total1_2, , uint64 start1_2, uint64 periodLength1_2, uint16[] memory sched1_2) = 
            sale.getVestingSchedule(buyer1, 2);
        assertGe(total1_2, 99_999 ether);
        assertLe(total1_2, 100_001 ether);
        assertEq(start1_2, vestStart2);
        assertEq(periodLength1_2, 30 days);
        assertEq(sched1_2.length, 3);

        // Verify buyer2 schedule (stage 1 only)
        (uint128 total2, , uint64 start2, uint64 periodLength2, uint16[] memory sched2) = 
            sale.getVestingSchedule(buyer2, 1);
        // 200e6 * 100000 * 1e12 / 50 = 400k tokens
        assertEq(total2, 400_000 ether);
        assertEq(start2, vestStart1);
        assertEq(periodLength2, 30 days);
        assertEq(sched2.length, 6);

        // Verify buyer3 schedules (stage 0 and stage 2)
        (uint128 total3_0, , uint64 start3_0, uint64 periodLength3_0, uint16[] memory sched3_0) = 
            sale.getVestingSchedule(buyer3, 0);
        assertEq(total3_0, 150_000 ether);
        assertEq(start3_0, vestStart0);
        assertEq(periodLength3_0, 30 days);
        assertEq(sched3_0.length, 8);

        (uint128 total3_2, , uint64 start3_2, uint64 periodLength3_2, uint16[] memory sched3_2) = 
            sale.getVestingSchedule(buyer3, 2);
        assertGe(total3_2, 74_999 ether);
        assertLe(total3_2, 75_001 ether);
        assertEq(start3_2, vestStart2);
        assertEq(periodLength3_2, 30 days);
        assertEq(sched3_2.length, 3);

        // Verify buyer4 schedule (stage 0, aggregated)
        (uint128 total4, , uint64 start4, uint64 periodLength4, uint16[] memory sched4) = 
            sale.getVestingSchedule(buyer4, 0);
        assertEq(total4, 100_000 ether);
        assertEq(start4, vestStart0);
        assertEq(periodLength4, 30 days);
        assertEq(sched4.length, 8);

        // Verify buyer5 schedule (stage 2)
        (uint128 total5, , uint64 start5, uint64 periodLength5, uint16[] memory sched5) = 
            sale.getVestingSchedule(buyer5, 2);
        // Buyer5 purchases at Stage 2, so 100e6 at price 33 = ~303k tokens
        assertGe(total5, 299_999 ether);
        assertLe(total5, 303_100 ether); // Allow for rounding
        assertEq(start5, vestStart2); // Stage 2's vestStart
        assertEq(periodLength5, 30 days);
        assertEq(sched5.length, 3); // Uses Stage 2's schedule

        // Verify total sold
        // Buyer1: 100k (stage 0) + 200k (stage 1) + 100k (stage 2) = 400k
        // Buyer2: 400k (stage 1)
        // Buyer3: 150k (stage 0) + 75k (stage 2) = 225k
        // Buyer4: 50k + 30k + 20k = 100k (stage 0, aggregated)
        // Buyer5: ~303k (stage 2)
        // Total: 300k + 400k + 225k + 100k + 303030303030303030303030 = ~1.328M
        assertGe(sale.totalSold(), 1_325_000 ether);
        assertLe(sale.totalSold(), 1_330_000 ether);

        // Test vesting releases over time
        // buyer1 has 3 separate schedules:
        // - Schedule 0: 100k tokens, starts at vestStart0, 8 periods
        // - Schedule 1: 100k tokens, starts at vestStart1, 6 periods  
        // - Schedule 2: 100k tokens, starts at vestStart2, 3 periods
        
        // After 1 month from vestStart0 - period 0 is vested (10% = 10k) for schedule 0
        vm.warp(vestStart0 + 30 days);
        uint256 releasableAfter30Days = sale.releasableAmount(buyer1);
        assertEq(releasableAfter30Days, 10_000 ether); // Period 0 (10%) of schedule 0 only
        vm.prank(buyer1);
        sale.release();
        uint256 balanceAfter30Days = saleToken.balanceOf(buyer1);
        assertEq(balanceAfter30Days, 10_000 ether);

        // After 6 months from vestStart0 - periods 0-5 are vested (60% = 60k) for schedule 0
        // Schedule 1 starts at vestStart1 = nowTs + 24 days, which is before vestStart0 + 180 days
        // So schedule 1 will also have releasable tokens
        vm.warp(vestStart0 + 180 days);
        // Check individual schedule 0 releasable amount
        uint256 schedule0Releasable = sale.releasableAmountForStage(buyer1, 0);
        uint256 expectedSchedule0 = 50_000 ether; // 60k - 10k already released from schedule 0
        assertEq(schedule0Releasable, expectedSchedule0);
        // Total releasable includes all schedules
        uint256 releasableAfter180Days = sale.releasableAmount(buyer1);
        assertGe(releasableAfter180Days, expectedSchedule0); // At least schedule 0's amount
        vm.prank(buyer1);
        sale.release();
        uint256 balanceAfter180Days = saleToken.balanceOf(buyer1);
        assertGe(balanceAfter180Days, 60_000 ether); // At least 60% of schedule 0 (100k)

        // After 8 months from vestStart0 - 100% of schedule 0 vested
        // But schedule 1 and 2 also have releasable tokens at this point
        vm.warp(vestStart0 + 240 days);
        // Check individual schedule 0 releasable amount
        uint256 schedule0Releasable240 = sale.releasableAmountForStage(buyer1, 0);
        uint256 expectedSchedule0_240 = 40_000 ether; // 100% - 60% already released from schedule 0
        assertEq(schedule0Releasable240, expectedSchedule0_240);
        // Total releasable includes all schedules
        uint256 releasableAfter240Days = sale.releasableAmount(buyer1);
        assertGe(releasableAfter240Days, expectedSchedule0_240); // At least schedule 0's amount
        vm.prank(buyer1);
        sale.release();
        // Total balance should be at least 100k (schedule 0 fully released) plus releases from other schedules
        uint256 finalBalance = saleToken.balanceOf(buyer1);
        assertGe(finalBalance, 100_000 ether); // At least schedule 0 fully released

        // Buyer2's schedule (Stage 1): After 1 month (30 days) from vestStart1 - period 0 is vested (16.67% = 66.68k)
        vm.warp(vestStart1 + 30 days);
        // After 30 days: only period 0 = 16.67% of 400k = 66.68k
        uint256 buyer2Releasable = sale.releasableAmount(buyer2);
        assertEq(buyer2Releasable, 66_680 ether); // Period 0 (16.67%)
        vm.prank(buyer2);
        sale.release();
        uint256 buyer2Balance = saleToken.balanceOf(buyer2);
        assertEq(buyer2Balance, 66_680 ether);
    }

    /// @notice Test edge case: User purchases at exact stage boundaries
    function test_DeepE2E_PurchaseAtStageBoundaries() public {
        uint64 nowTs = uint64(block.timestamp);
        
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 7 days + 3 days, 30 days, percentages);
        sale.addStage(50, nowTs + 14 days, nowTs + 14 days + 3 days, 30 days, percentages);
        vm.stopPrank();

        // Purchase exactly at Stage 1 end
        vm.warp(nowTs + 7 days);
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0)); // Should succeed - still in Stage 1

        // Purchase exactly at Stage 2 start
        vm.warp(nowTs + 7 days + 1);
        vm.prank(buyer2);
        sale.buy(100e6, new bytes32[](0)); // Should succeed - in Stage 2

        // Try to purchase after Stage 2 ends
        vm.warp(nowTs + 14 days + 1);
        vm.expectRevert(Errors.NotStarted.selector);
        vm.prank(buyer3);
        sale.buy(100e6, new bytes32[](0)); // Should fail - no active stage
    }

    /// @notice Test scenario: Total cap reached across multiple stages
    function test_DeepE2E_TotalCapReachedAcrossStages() public {
        uint64 nowTs = uint64(block.timestamp);
        
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 1 days, nowTs + 1 days + 3 days, 30 days, percentages);
        sale.addStage(50, nowTs + 2 days, nowTs + 2 days + 3 days, 30 days, percentages);
        sale.setTotalCap(500_000 ether);
        vm.stopPrank();

        // Stage 1: Purchase 300k tokens
        vm.prank(buyer1);
        sale.buy(300e6, new bytes32[](0));

        // Move to Stage 2
        vm.warp(nowTs + 1 days + 1);
        
        // Stage 2: Purchase 100k tokens (50 USDC * 2000 * 1e12)
        vm.prank(buyer2);
        sale.buy(50e6, new bytes32[](0));

        // Total sold: 300k + 100k = 400k, cap is 500k, so 100k remaining
        // Try to purchase more than remaining - should fail
        // Need to buy exactly 100k tokens: payment = (100_000 ether * 50) / (PRICE_SCALE * decimalScale)
        uint256 paymentFor100k = (100_000 ether * 50) / (sale.PRICE_SCALE() * sale.decimalScale());
        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(buyer3);
        sale.buy(uint128(paymentFor100k + 1), new bytes32[](0)); // Would exceed cap

        // But can purchase exactly at cap (100k tokens remaining)
        vm.prank(buyer3);
        sale.buy(uint128(paymentFor100k), new bytes32[](0)); // Exactly 100k tokens = 500k total
    }

    /// @notice Test scenario: Pause/unpause during multi-stage sale
    function test_DeepE2E_PauseUnpauseDuringMultiStage() public {
        uint64 nowTs = uint64(block.timestamp);
        
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        uint64 vestStart1 = nowTs + 1 days + 3 days;
        vm.startPrank(admin);
        sale.addStage(100, nowTs + 1 days, vestStart1, 30 days, percentages);
        sale.addStage(50, nowTs + 2 days, nowTs + 2 days + 3 days, 30 days, percentages);
        vm.stopPrank();

        // Purchase in Stage 0
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        // Pause
        vm.prank(admin);
        sale.pause();

        // Cannot purchase in Stage 1 (while paused)
        vm.warp(nowTs + 1 days + 1);
        vm.expectRevert();
        vm.prank(buyer2);
        sale.buy(100e6, new bytes32[](0));

        // Cannot release while paused (warp to vestStart + 30 days)
        vm.warp(vestStart1 + 30 days);
        vm.expectRevert();
        vm.prank(buyer1);
        sale.release();

        // Unpause
        vm.prank(admin);
        sale.unpause();

        // Can purchase in Stage 1 (still within stage end time)
        vm.warp(nowTs + 1 days + 1); // Make sure we're still in Stage 1
        vm.prank(buyer2);
        sale.buy(100e6, new bytes32[](0));

        // Can release (period 0 vested after vestStart + 30 days)
        vm.warp(vestStart1 + 30 days); // Ensure we're at vestStart + 30 days
        vm.prank(buyer1);
        sale.release();
        assertEq(saleToken.balanceOf(buyer1), 25_000 ether); // 25% of 100k
    }

    /// @notice Test scenario: User limits change between stages
    function test_DeepE2E_UserLimitsChangeBetweenStages() public {
        uint64 nowTs = uint64(block.timestamp);
        
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 1 days, nowTs + 1 days + 3 days, 30 days, percentages);
        sale.addStage(50, nowTs + 2 days, nowTs + 2 days + 3 days, 30 days, percentages);
        sale.setUserLimits(buyer1, 50e6, 150e6);
        vm.stopPrank();

        // Stage 1: Purchase within limits
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        // Admin changes limits
        vm.prank(admin);
        sale.setUserLimits(buyer1, 10e6, 50e6); // Lower max

        // Move to Stage 2
        vm.warp(nowTs + 1 days + 1);
        
        // Cannot purchase above new max
        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        // Can purchase within new limits
        vm.prank(buyer1);
        sale.buy(50e6, new bytes32[](0));
    }

    /// @notice Test scenario: Allowlist enabled mid-sale
    function test_DeepE2E_AllowlistEnabledMidSale() public {
        uint64 nowTs = uint64(block.timestamp);
        
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        // Build Merkle tree with buyer1 and buyer2 only
        address[] memory whitelist = new address[](2);
        whitelist[0] = buyer1;
        whitelist[1] = buyer2;
        bytes32 merkleRoot = _buildMerkleTree(whitelist);
        bytes32[] memory proof1 = _getProof(whitelist, buyer1);
        bytes32[] memory proof2 = _getProof(whitelist, buyer2);

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 1 days, nowTs + 1 days + 3 days, 30 days, percentages);
        sale.addStage(50, nowTs + 2 days, nowTs + 2 days + 3 days, 30 days, percentages);
        sale.setAllowlistMerkleRoot(merkleRoot);
        sale.setAllowlistEnabled(true);
        vm.stopPrank();

        // Stage 1: Purchase without allowlist (allowlist not enabled yet)
        vm.startPrank(admin);
        sale.setAllowlistEnabled(false);
        vm.stopPrank();
        
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        // Enable allowlist
        vm.startPrank(admin);
        sale.setAllowlistEnabled(true);
        vm.stopPrank();

        // Move to Stage 2
        vm.warp(nowTs + 1 days + 1);
        
        // Buyer1 can purchase (on allowlist)
        vm.prank(buyer1);
        sale.buy(50e6, proof1);

        // Buyer2 can purchase (on allowlist)
        vm.prank(buyer2);
        sale.buy(100e6, proof2);

        // Buyer3 cannot purchase (not on allowlist)
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(buyer3);
        sale.buy(100e6, new bytes32[](0));
    }

    /// @notice Build Merkle tree and return root
    function _buildMerkleTree(address[] memory addresses) internal pure returns (bytes32) {
        if (addresses.length == 0) return bytes32(0);
        
        bytes32[] memory leaves = new bytes32[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(addresses[i]));
        }
        
        return _computeRoot(leaves);
    }

    /// @notice Compute Merkle root from leaves
    function _computeRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        if (leaves.length == 1) return leaves[0];
        
        uint256 len = leaves.length;
        uint256 nextLen = (len + 1) / 2;
        bytes32[] memory nextLevel = new bytes32[](nextLen);
        
        for (uint256 i = 0; i < nextLen; i++) {
            if (2 * i + 1 < len) {
                nextLevel[i] = _hashPair(leaves[2 * i], leaves[2 * i + 1]);
            } else {
                nextLevel[i] = leaves[2 * i];
            }
        }
        
        return _computeRoot(nextLevel);
    }

    /// @notice Hash a pair of nodes
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    /// @notice Get Merkle proof for an address
    function _getProof(address[] memory addresses, address target) internal pure returns (bytes32[] memory) {
        bytes32[] memory leaves = new bytes32[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(addresses[i]));
        }
        
        bytes32 leaf = keccak256(abi.encodePacked(target));
        uint256 index = 0;
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == target) {
                index = i;
                break;
            }
        }
        
        return _generateProof(leaves, index);
    }

    /// @notice Generate Merkle proof for a leaf at given index
    function _generateProof(bytes32[] memory leaves, uint256 index) internal pure returns (bytes32[] memory) {
        uint256 len = leaves.length;
        if (len == 1) return new bytes32[](0);
        
        uint256 proofLength = 0;
        uint256 temp = len;
        while (temp > 1) {
            proofLength++;
            temp = (temp + 1) / 2;
        }
        
        bytes32[] memory proof = new bytes32[](proofLength);
        uint256 proofIndex = 0;
        uint256 currentIndex = index;
        bytes32[] memory currentLevel = leaves;
        
        while (currentLevel.length > 1) {
            uint256 nextLen = (currentLevel.length + 1) / 2;
            bytes32[] memory nextLevel = new bytes32[](nextLen);
            
            for (uint256 i = 0; i < nextLen; i++) {
                if (2 * i + 1 < currentLevel.length) {
                    nextLevel[i] = _hashPair(currentLevel[2 * i], currentLevel[2 * i + 1]);
                } else {
                    nextLevel[i] = currentLevel[2 * i];
                }
            }
            
            uint256 pairIndex = currentIndex % 2 == 0 ? currentIndex + 1 : currentIndex - 1;
            if (pairIndex < currentLevel.length) {
                proof[proofIndex] = currentLevel[pairIndex];
                proofIndex++;
            }
            
            currentIndex = currentIndex / 2;
            currentLevel = nextLevel;
        }
        
        return proof;
    }

    /// @notice Test scenario: Multiple releases over time with different schedules
    function test_DeepE2E_MultipleReleases_DifferentSchedules() public {
        uint64 nowTs = uint64(block.timestamp);
        
        uint16[] memory percentages1 = new uint16[](4);
        percentages1[0] = 2500;
        percentages1[1] = 2500;
        percentages1[2] = 2500;
        percentages1[3] = 2500;

        uint16[] memory percentages2 = new uint16[](6);
        percentages2[0] = 1667;
        percentages2[1] = 1667;
        percentages2[2] = 1667;
        percentages2[3] = 1667;
        percentages2[4] = 1667;
        percentages2[5] = 1665;

        uint64 vestStart1 = nowTs + 1 days + 3 days;
        uint64 vestStart2 = nowTs + 2 days + 3 days;
        vm.startPrank(admin);
        sale.addStage(100, nowTs + 1 days, vestStart1, 30 days, percentages1);
        sale.addStage(50, nowTs + 2 days, vestStart2, 20 days, percentages2);
        vm.stopPrank();

        // Buyer1: Stage 0 purchase
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0)); // 100k tokens

        // Buyer2: Stage 1 purchase
        vm.warp(nowTs + 1 days + 1);
        vm.prank(buyer2);
        sale.buy(100e6, new bytes32[](0)); // 200k tokens (100e6 * 100000 * 1e12 / 50)

        // Release cycles for buyer1 (4 periods, 30 days each)
        // After vestStart1 + 30 days: period 0 is vested (25% total)
        vm.warp(vestStart1 + 30 days);
        vm.prank(buyer1);
        sale.release();
        // 25% of 100k = 25k
        assertEq(saleToken.balanceOf(buyer1), 25_000 ether);

        // After vestStart1 + 60 days: periods 0 and 1 are vested (50% total)
        vm.warp(vestStart1 + 60 days);
        vm.prank(buyer1);
        sale.release();
        // 50% of 100k = 50k total (25k already released, 25k more)
        assertEq(saleToken.balanceOf(buyer1), 50_000 ether);

        // After vestStart1 + 90 days: periods 0, 1, and 2 are vested (75% total)
        vm.warp(vestStart1 + 90 days);
        vm.prank(buyer1);
        sale.release();
        // 75% of 100k = 75k total (50k already released, 25k more)
        assertEq(saleToken.balanceOf(buyer1), 75_000 ether);

        // After vestStart1 + 120 days: all periods vested (100% total)
        vm.warp(vestStart1 + 120 days);
        vm.prank(buyer1);
        sale.release();
        // 100% of 100k = 100k total (75k already released, 25k more)
        assertEq(saleToken.balanceOf(buyer1), 100_000 ether);

        // Release cycles for buyer2 (6 periods, 20 days each)
        // After vestStart2 + 20 days: period 0 is vested (16.67% of 200k = 33.34k)
        vm.warp(vestStart2 + 20 days);
        vm.prank(buyer2);
        sale.release();
        // 16.67% of 200k = 33.34k
        assertEq(saleToken.balanceOf(buyer2), 33_340 ether);

        // After vestStart2 + 40 days: periods 0 and 1 are vested (33.34% of 200k = 66.68k)
        // Note: At exactly 40 days from vestStart2, we're at the start of period 2, so only periods 0 and 1 have completed
        vm.warp(vestStart2 + 40 days);
        vm.prank(buyer2);
        sale.release();
        // 33.34% of 200k = 66.68k total (already released 33.34k, so 33.34k more)
        assertEq(saleToken.balanceOf(buyer2), 66_680 ether);

        // After vestStart2 + 120 days: 100% vested
        vm.warp(vestStart2 + 120 days);
        vm.prank(buyer2);
        sale.release();
        assertEq(saleToken.balanceOf(buyer2), 200_000 ether); // 100% of 200k
    }

    /// @notice Test scenario: Admin releases for multiple beneficiaries
    function test_DeepE2E_AdminReleasesForMultipleBeneficiaries() public {
        uint64 nowTs = uint64(block.timestamp);
        
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        uint64 vestStart = nowTs + 7 days + 3 days;
        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, vestStart, 30 days, percentages);

        vm.startPrank(buyer1);
        sale.buy(100e6, new bytes32[](0));
        vm.stopPrank();
        vm.startPrank(buyer2);
        sale.buy(200e6, new bytes32[](0));
        vm.stopPrank();
        vm.startPrank(buyer3);
        sale.buy(50e6, new bytes32[](0));
        vm.stopPrank();

        // Warp to vestStart + 30 days to complete first period
        vm.warp(vestStart + 30 days);

        // Admin releases for all
        // After vestStart + 30 days: period 0 is vested (25% total)
        vm.startPrank(admin);
        sale.releaseFor(buyer1);
        sale.releaseFor(buyer2);
        sale.releaseFor(buyer3);
        vm.stopPrank();

        assertEq(saleToken.balanceOf(buyer1), 25_000 ether); // 25% of 100k
        assertEq(saleToken.balanceOf(buyer2), 50_000 ether); // 25% of 200k
        assertEq(saleToken.balanceOf(buyer3), 12_500 ether); // 25% of 50k
    }

    /// @notice Test scenario: Contract balance validation with totalCap
    function test_DeepE2E_ContractBalance_TotalCap_Interaction() public {
        uint64 nowTs = uint64(block.timestamp);
        
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 7 days + 3 days, 30 days, percentages);

        // Contract has 5M tokens
        assertEq(saleToken.balanceOf(address(sale)), 5_000_000 ether);

        // Set cap to 3M (below balance, accounting for vesting allocations)
        vm.prank(admin);
        sale.setTotalCap(3_000_000 ether);

        // Can purchase up to cap
        vm.prank(buyer1);
        sale.buy(3000e6, new bytes32[](0)); // 3M tokens

        // Verify allocation
        assertEq(sale.totalAllocatedToVesting(), 3_000_000 ether);
        assertEq(saleToken.balanceOf(address(sale)), 5_000_000 ether);
        // Available for sale = 5M - 3M = 2M, but cap is 3M and 3M sold, so can't buy more

        // Cannot purchase more (hits cap)
        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(buyer2);
        sale.buy(1e6, new bytes32[](0));

        // But if we add more tokens to contract, still can't exceed cap
        vm.prank(admin);
        treasury.withdrawERC20(saleToken, address(sale), 1_000_000 ether);
        
        // Contract now has 6M tokens, but 3M allocated to vesting
        // Available = 6M - 3M = 3M, but cap is 3M and 3M sold, so still can't purchase
        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(buyer2);
        sale.buy(1e6, new bytes32[](0));

        // Cannot increase cap to 4M - only 3M available (6M - 3M allocated)
        vm.expectRevert(Errors.InsufficientBalance.selector);
        vm.prank(admin);
        sale.setTotalCap(4_000_000 ether);

        // Verify that we can't set cap to 4M without enough available tokens
        // Contract has 6M tokens, 3M allocated to vesting
        // Available: 6M - 3M = 3M
        // Can't set cap to 4M (would require 4M available, but only 3M available)
        vm.expectRevert(Errors.InsufficientBalance.selector);
        vm.prank(admin);
        sale.setTotalCap(4_000_000 ether);
        
        // Add 1M more tokens to make 4M available
        vm.prank(admin);
        treasury.withdrawERC20(saleToken, address(sale), 1_000_000 ether);
        
        // Now contract balance: 7M, totalAllocatedToVesting: 3M
        // Available: 7M - 3M = 4M
        // Can set cap to 4M (3M sold + 1M available = 4M cap)
        vm.prank(admin);
        sale.setTotalCap(4_000_000 ether);
        
        // Verify cap was set
        assertEq(sale.totalCap(), 4_000_000 ether);
        
        // Now can purchase more (up to new cap), but stage has ended
        // Add a new stage to allow purchases
        vm.prank(admin);
        sale.addStage(100, nowTs + 60 days, nowTs + 60 days + 3 days, 30 days, percentages);
        
        // Warp to new stage
        vm.warp(nowTs + 7 days + 1);
        
        // Can purchase 1M more tokens (4M cap - 3M sold = 1M available)
        uint256 paymentFor1M = (1_000_000 ether * 100) / (sale.PRICE_SCALE() * sale.decimalScale());
        vm.prank(buyer2);
        sale.buy(uint128(paymentFor1M), new bytes32[](0)); // 1M tokens
        
        // Verify total sold increased
        assertEq(sale.totalSold(), 4_000_000 ether);
    }
}

