// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TokenSale} from "src/sale/TokenSale.sol";
import {Treasury} from "src/treasury/Treasury.sol";
import {EmyoToken} from "src/token/EmyoToken.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {Roles} from "src/access/Roles.sol";

contract TokenSaleVestingE2E is Test {
    MockERC20 usdc;
    EmyoToken emyo;
    Treasury treasury;
    TokenSale sale;

    address admin = address(0xA11CE);
    address buyer1 = address(0xB0B1);
    address buyer2 = address(0xB0B2);
    address buyer3 = address(0xB0B3);

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);
        treasury = new Treasury(admin);
        emyo = new EmyoToken("Emyo", "EMY", 10_000_000 ether, address(treasury));
        sale = new TokenSale(usdc, emyo, address(treasury), admin);

        // Fund users with USDC and approve
        usdc.mint(buyer1, 1_000_000e6);
        usdc.mint(buyer2, 1_000_000e6);
        usdc.mint(buyer3, 1_000_000e6);
        vm.startPrank(buyer1);
        usdc.approve(address(sale), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(buyer2);
        usdc.approve(address(sale), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(buyer3);
        usdc.approve(address(sale), type(uint256).max);
        vm.stopPrank();

        // Fund sale contract with tokens for vesting releases
        vm.prank(admin);
        treasury.withdrawERC20(emyo, address(sale), 5_000_000 ether);
    }

    function test_Buy_SingleStage_ScheduleBasedVesting_ReleaseAfterPeriods() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500; // 25%
        percentages[1] = 2500; // 25%
        percentages[2] = 2500; // 25%
        percentages[3] = 2500; // 25%

        vm.prank(admin);
        sale.addStage(
            100, // emyPriceUsd: $0.001 per EMY (100000 / 1000 = 100, so 1 USDC = 1000 EMY)
            nowTs + 7 days,
            nowTs + 10 days, // vestStart
            30 days, // 30 days per period
            percentages
        );

        // Buy 100 USDC => 100k tokens
        uint64 vestStart = nowTs + 10 days;
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        // Check schedule - vesting starts at vestStart
        (uint128 total, uint128 released, uint64 start, uint64 periodLength, uint16[] memory sched) = 
            sale.getVestingSchedule(buyer1, 0);
        assertEq(total, 100_000 ether);
        assertEq(released, 0);
        assertEq(start, vestStart); // Starts at vestStart, not purchase time
        assertEq(periodLength, 30 days);
        assertEq(sched.length, 4);

        // Period 0 does NOT vest immediately (FIX CRITICAL #1)
        assertEq(sale.releasableAmount(buyer1), 0);
        
        // After first period (30 days from vestStart) - period 0 vests (25%)
        vm.warp(vestStart + 30 days);
        assertEq(sale.releasableAmount(buyer1), 25_000 ether);
        
        // Release first period
        vm.prank(buyer1);
        sale.release();
        assertEq(emyo.balanceOf(buyer1), 25_000 ether);
        assertEq(sale.releasableAmount(buyer1), 0);

        // After second period (60 days from vestStart) - periods 0 + 1 vested (50%)
        vm.warp(vestStart + 60 days);
        assertEq(sale.releasableAmount(buyer1), 25_000 ether);
        
        // Release second period
        vm.prank(buyer1);
        sale.release();
        assertEq(emyo.balanceOf(buyer1), 50_000 ether);

        // After third period (90 days from vestStart) - periods 0 + 1 + 2 vested (75%)
        vm.warp(vestStart + 90 days);
        assertEq(sale.releasableAmount(buyer1), 25_000 ether);
        
        // Release third period
        vm.prank(buyer1);
        sale.release();
        assertEq(emyo.balanceOf(buyer1), 75_000 ether);

        // After all periods (120 days from vestStart) - 100% vested
        vm.warp(vestStart + 120 days);
        assertEq(sale.releasableAmount(buyer1), 25_000 ether);
        
        // Release remaining
        vm.prank(buyer1);
        sale.release();
        assertEq(emyo.balanceOf(buyer1), 100_000 ether);
        assertEq(sale.releasableAmount(buyer1), 0);
    }

    function test_Buy_MultipleStages_DifferentVestingSchedules_CreatesSeparateSchedules() public {
        uint64 nowTs = uint64(block.timestamp);
        
        // Stage 1: 4 periods, 25% each, 30 days per period
        uint16[] memory percentages1 = new uint16[](4);
        percentages1[0] = 2500;
        percentages1[1] = 2500;
        percentages1[2] = 2500;
        percentages1[3] = 2500;

        // Stage 2: 5 periods, 20% each, 20 days per period
        uint16[] memory percentages2 = new uint16[](5);
        percentages2[0] = 2000; // 20%
        percentages2[1] = 2000; // 20%
        percentages2[2] = 2000; // 20%
        percentages2[3] = 2000; // 20%
        percentages2[4] = 2000; // 20%

        uint64 vestStart1 = nowTs + 1 days + 3 days;
        uint64 vestStart2 = nowTs + 2 days + 3 days;
        vm.startPrank(admin);
        sale.addStage(100, nowTs + 1 days, vestStart1, 30 days, percentages1);
        sale.addStage(50, nowTs + 2 days, vestStart2, 20 days, percentages2);
        vm.stopPrank();

        // Buy from stage 0 - 100k tokens
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        // Move to stage 1
        vm.warp(nowTs + 1 days + 1);
        
        // Buy from stage 1 - creates separate schedule
        vm.prank(buyer1);
        sale.buy(50e6, new bytes32[](0)); // 100k tokens (50e6 * 100000 * 1e12 / 50)

        // Check stage 0 schedule
        (uint128 total0, , uint64 start0, uint64 periodLength0, uint16[] memory sched0) = 
            sale.getVestingSchedule(buyer1, 0);
        assertEq(total0, 100_000 ether);
        assertEq(start0, vestStart1); // Starts at stage 0's vestStart
        assertEq(periodLength0, 30 days); // Uses stage 0's period length
        assertEq(sched0.length, 4);

        // Check stage 1 schedule (separate)
        (uint128 total1, , uint64 start1, uint64 periodLength1, uint16[] memory sched1) = 
            sale.getVestingSchedule(buyer1, 1);
        assertEq(total1, 100_000 ether);
        assertEq(start1, vestStart2); // Starts at stage 1's vestStart
        assertEq(periodLength1, 20 days); // Uses stage 1's period length
        assertEq(sched1.length, 5);

        // After vestStart1 + 30 days - period 0 of stage 0 vests (25% of 100k = 25k)
        // Stage 1 also vests (20% of 100k = 20k) since vestStart2 + 20 days has passed
        vm.warp(vestStart1 + 30 days);
        assertEq(sale.releasableAmount(buyer1), 45_000 ether); // 25k from stage 0 + 20k from stage 1
    }

    function test_Buy_MultipleTimes_SameStage_Aggregates() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        uint64 vestStart = nowTs + 7 days + 3 days;
        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, vestStart, 30 days, percentages);

        // Buy multiple times
        vm.startPrank(buyer1);
        sale.buy(50e6, new bytes32[](0));  // 50k tokens
        sale.buy(30e6, new bytes32[](0));  // 30k tokens
        sale.buy(20e6, new bytes32[](0));  // 20k tokens
        vm.stopPrank();

        // Total should be aggregated
        (uint128 total,, , , ) = sale.getVestingSchedule(buyer1, 0);
        assertEq(total, 100_000 ether);

        // After first period (30 days from vestStart), period 0 vests (25% of total)
        vm.warp(vestStart + 30 days);
        assertEq(sale.releasableAmount(buyer1), 25_000 ether);
    }

    function test_AdminRelease_ForBeneficiary() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        uint64 vestStart = nowTs + 7 days + 3 days;
        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, vestStart, 30 days, percentages);

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        // Period 0 does NOT vest immediately (FIX CRITICAL #1)
        assertEq(sale.releasableAmount(buyer1), 0);
        
        // After vestStart + 30 days - period 0 vests (25%)
        vm.warp(vestStart + 30 days);
        assertEq(sale.releasableAmount(buyer1), 25_000 ether);
        
        // Admin releases for buyer1
        vm.prank(admin);
        sale.releaseFor(buyer1);
        assertEq(emyo.balanceOf(buyer1), 25_000 ether);
        
        // After vestStart + 60 days - periods 0 + 1 vested (50% total, 25% more available)
        vm.warp(vestStart + 60 days);
        assertEq(sale.releasableAmount(buyer1), 25_000 ether); // 50% - 25% already released
    }

    function test_Release_ImmediatelyAfterPurchase_ReturnsZero() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        uint64 vestStart = nowTs + 7 days + 3 days;
        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, vestStart, 30 days, percentages);

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        // Period 0 does NOT vest immediately (FIX CRITICAL #1)
        assertEq(sale.releasableAmount(buyer1), 0);
        
        // After vestStart + 30 days, period 0 vests (25%)
        vm.warp(vestStart + 30 days);
        assertEq(sale.releasableAmount(buyer1), 25_000 ether);
        
        vm.prank(buyer1);
        uint256 released = sale.release();
        assertEq(released, 25_000 ether);
        assertEq(emyo.balanceOf(buyer1), 25_000 ether);
    }

    function test_MultipleBuyers_DifferentSchedules() public {
        uint64 nowTs = uint64(block.timestamp);
        
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 7 days + 3 days, 30 days, percentages);

        // Multiple buyers - each gets their own schedule starting at vestStart (same for all in same stage)
        uint64 vestStart = nowTs + 7 days + 3 days;
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));
        
        vm.prank(buyer2);
        sale.buy(200e6, new bytes32[](0));
        
        vm.prank(buyer3);
        sale.buy(50e6, new bytes32[](0));

        // Check all schedules - all start at same vestStart (they're in the same stage)
        (uint128 total1,, uint64 start1, , ) = sale.getVestingSchedule(buyer1, 0);
        (uint128 total2,, uint64 start2, , ) = sale.getVestingSchedule(buyer2, 0);
        (uint128 total3,, uint64 start3, , ) = sale.getVestingSchedule(buyer3, 0);
        
        assertEq(total1, 100_000 ether);
        assertEq(total2, 200_000 ether);
        assertEq(total3, 50_000 ether);
        assertEq(start1, vestStart); // All start at vestStart, not purchase time
        assertEq(start2, vestStart);
        assertEq(start3, vestStart);

        // After vestStart + 30 days, period 0 vests for all (25% each)
        vm.warp(vestStart + 30 days);
        
        vm.prank(buyer1);
        sale.release();
        vm.prank(buyer2);
        sale.release();
        vm.prank(buyer3);
        sale.release();

        assertEq(emyo.balanceOf(buyer1), 25_000 ether); // 25% of 100k
        assertEq(emyo.balanceOf(buyer2), 50_000 ether); // 25% of 200k
        assertEq(emyo.balanceOf(buyer3), 12_500 ether); // 25% of 50k
    }

    function test_PartialRelease_MultiplePeriods() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](5);
        percentages[0] = 2000; // 20%
        percentages[1] = 2000; // 20%
        percentages[2] = 2000; // 20%
        percentages[3] = 2000; // 20%
        percentages[4] = 2000; // 20%

        uint64 vestStart = nowTs + 7 days + 3 days;
        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, vestStart, 30 days, percentages);

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0)); // 100k tokens

        // After 2 periods (60 days from vestStart) - periods 0 + 1 vested (40%: 20% + 20%)
        vm.warp(vestStart + 60 days);
        assertEq(sale.releasableAmount(buyer1), 40_000 ether);
        
        vm.prank(buyer1);
        sale.release();
        assertEq(emyo.balanceOf(buyer1), 40_000 ether);

        // After all periods (150 days from vestStart) - 100% available, but 40k already released
        vm.warp(vestStart + 150 days);
        assertEq(sale.releasableAmount(buyer1), 60_000 ether); // 100% - 40% already released
        
        vm.prank(buyer1);
        sale.release();
        assertEq(emyo.balanceOf(buyer1), 100_000 ether);
    }

    function test_NonLinearSchedule_UnevenPercentages() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](5);
        percentages[0] = 1000; // 10%
        percentages[1] = 1500; // 15%
        percentages[2] = 2000; // 20%
        percentages[3] = 2500; // 25%
        percentages[4] = 3000; // 30%

        uint64 vestStart = nowTs + 7 days + 3 days;
        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, vestStart, 30 days, percentages);

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0)); // 100k tokens

        // Period 0 does NOT vest immediately (FIX CRITICAL #1)
        assertEq(sale.releasableAmount(buyer1), 0);

        // After period 0 (30 days from vestStart): 10% vested
        vm.warp(vestStart + 30 days);
        assertEq(sale.releasableAmount(buyer1), 10_000 ether);

        // After period 1 (60 days from vestStart): 25% total (10% + 15%)
        vm.warp(vestStart + 60 days);
        assertEq(sale.releasableAmount(buyer1), 25_000 ether);

        // After period 2 (90 days from vestStart): 45% total (10% + 15% + 20%)
        vm.warp(vestStart + 90 days);
        assertEq(sale.releasableAmount(buyer1), 45_000 ether);

        // After period 3 (120 days from vestStart): 70% total
        vm.warp(vestStart + 120 days);
        assertEq(sale.releasableAmount(buyer1), 70_000 ether);

        // After all periods (150 days from vestStart): 100%
        vm.warp(vestStart + 150 days);
        assertEq(sale.releasableAmount(buyer1), 100_000 ether);
    }

    function test_Revert_Release_WhenPaused() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 7 days + 3 days, 30 days, percentages);

        uint64 purchaseTime = uint64(block.timestamp);
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        vm.warp(purchaseTime + 30 days);
        
        vm.prank(admin);
        sale.pause();
        
        vm.expectRevert();
        vm.prank(buyer1);
        sale.release();
    }

    function test_Revert_AdminRelease_Unauthorized() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 7 days + 3 days, 30 days, percentages);

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        vm.warp(nowTs + 30 days);
        
        vm.expectRevert();
        vm.prank(buyer1);
        sale.releaseFor(buyer2);
    }

    /// @notice E2E test for the example scenario: 3 stages with different vesting schedules
    /// Stage 1: 1 week, 8 months vesting [10, 10, 10, 10, 10, 10, 20, 20] (8 periods)
    /// Stage 2: 2 weeks, 6 months vesting
    /// Stage 3: 1 month, 3 months vesting
    /// User purchases at different stages - each stage creates separate schedule
    function test_E2E_ThreeStages_DifferentVestingSchedules_UserPurchasesAcrossStages() public {
        uint64 nowTs = uint64(block.timestamp);
        
        // Stage 0: 1 week long, 8 months vesting (8 periods of 1 month each)
        uint16[] memory percentages1 = new uint16[](8);
        percentages1[0] = 1000; percentages1[1] = 1000; percentages1[2] = 1000; percentages1[3] = 1000;
        percentages1[4] = 1000; percentages1[5] = 1000; percentages1[6] = 2000; percentages1[7] = 2000;

        // Stage 1: 2 weeks long, 6 months vesting
        uint16[] memory percentages2 = new uint16[](6);
        percentages2[0] = 1667; percentages2[1] = 1667; percentages2[2] = 1667;
        percentages2[3] = 1667; percentages2[4] = 1667; percentages2[5] = 1665;

        // Stage 2: 1 month long, 3 months vesting
        uint16[] memory percentages3 = new uint16[](3);
        percentages3[0] = 3333; percentages3[1] = 3333; percentages3[2] = 3334;

        uint64 vestStart0 = nowTs + 7 days + 3 days;
        uint64 vestStart1 = nowTs + 21 days + 3 days;
        uint64 vestStart2 = nowTs + 51 days + 3 days;
        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, vestStart0, 30 days, percentages1);
        sale.addStage(50, nowTs + 21 days, vestStart1, 30 days, percentages2);
        sale.addStage(33, nowTs + 51 days, vestStart2, 30 days, percentages3);
        vm.stopPrank();

        // User purchases in Stage 0
        vm.warp(nowTs + 7 days - 1);
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0)); // 100k tokens

        // Check stage 0 schedule
        (uint128 total0, , uint64 start0, uint64 periodLength0, uint16[] memory sched0) = 
            sale.getVestingSchedule(buyer1, 0);
        assertEq(total0, 100_000 ether);
        assertEq(start0, vestStart0); // Starts at vestStart, not purchase time
        assertEq(periodLength0, 30 days);
        assertEq(sched0.length, 8);

        // Move to Stage 1 and purchase again - creates separate schedule
        vm.warp(nowTs + 7 days + 1);
        vm.prank(buyer1);
        sale.buy(50e6, new bytes32[](0)); // 100k tokens (50e6 * 100000 * 1e12 / 50)

        // Check stage 1 schedule (separate)
        (uint128 total1, , uint64 start1, uint64 periodLength1, uint16[] memory sched1) = 
            sale.getVestingSchedule(buyer1, 1);
        assertEq(total1, 100_000 ether);
        assertEq(start1, vestStart1);
        assertEq(periodLength1, 30 days);
        assertEq(sched1.length, 6);

        // Move to Stage 2 and purchase again - creates another separate schedule
        vm.warp(nowTs + 21 days + 1);
        vm.prank(buyer1);
        sale.buy(33e6, new bytes32[](0)); // 100k tokens (33e6 * 100000 * 1e12 / 33)

        // Check stage 2 schedule (separate)
        (uint128 total2, , uint64 start2, uint64 periodLength2, uint16[] memory sched2) = 
            sale.getVestingSchedule(buyer1, 2);
        assertEq(total2, 100_000 ether);
        assertEq(start2, vestStart2);
        assertEq(periodLength2, 30 days);
        assertEq(sched2.length, 3);

        // Period 0 does NOT vest immediately
        assertEq(sale.releasableAmount(buyer1), 0);

        // After vestStart0 + 30 days - period 0 of stage 0 vests (10% of 100k = 10k)
        vm.warp(vestStart0 + 30 days);
        assertEq(sale.releasableAmount(buyer1), 10_000 ether); // Only stage 0 vests
        vm.prank(buyer1);
        sale.release();
        assertEq(emyo.balanceOf(buyer1), 10_000 ether);

        // After vestStart1 + 30 days - period 0 of stage 1 also vests (16.67% of 100k = 16.67k)
        vm.warp(vestStart1 + 30 days);
        assertEq(sale.releasableAmount(buyer1), 16_670 ether); // Stage 1 period 0 vests
        vm.prank(buyer1);
        sale.release();
        assertEq(emyo.balanceOf(buyer1), 26_670 ether);
    }

    /// @notice Test user purchasing in Stage 1 first, then Stage 2
    /// Each stage creates separate schedule
    function test_E2E_UserPurchasesInStage2First_ThenStage3_CreatesSeparateSchedules() public {
        uint64 nowTs = uint64(block.timestamp);
        
        uint16[] memory percentages2 = new uint16[](6);
        percentages2[0] = 1667; percentages2[1] = 1667; percentages2[2] = 1667;
        percentages2[3] = 1667; percentages2[4] = 1667; percentages2[5] = 1665;

        uint16[] memory percentages3 = new uint16[](3);
        percentages3[0] = 3333; percentages3[1] = 3333; percentages3[2] = 3334;

        uint16[] memory percentages1 = new uint16[](4);
        percentages1[0] = 2500;
        percentages1[1] = 2500;
        percentages1[2] = 2500;
        percentages1[3] = 2500;

        uint64 vestStart1 = nowTs + 7 days + 3 days;
        uint64 vestStart2 = nowTs + 21 days + 3 days;
        uint64 vestStart3 = nowTs + 51 days + 3 days;
        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, vestStart1, 30 days, percentages1);
        sale.addStage(50, nowTs + 21 days, vestStart2, 30 days, percentages2);
        sale.addStage(33, nowTs + 51 days, vestStart3, 30 days, percentages3);
        vm.stopPrank();

        // Buy in stage 1 (index 1) - skip stage 0, buy when stage 1 is active
        // Stage 0 ends at nowTs + 7 days, stage 1 is active from nowTs + 7 days + 1 to nowTs + 21 days
        vm.warp(nowTs + 8 days); // Stage 1 is active
        vm.prank(buyer2);
        sale.buy(100e6, new bytes32[](0)); // 200k tokens at stage 1 price (50: 100e6 * 100000 * 1e12 / 50)

        // Buy in stage 2 (index 2) - stage 1 ends at nowTs + 21 days, stage 2 is active from nowTs + 21 days + 1 to nowTs + 51 days
        vm.warp(nowTs + 22 days); // Stage 2 is active
        uint256 paymentFor150k = (150_000 ether * 33) / (sale.PRICE_SCALE() * sale.decimalScale());
        vm.prank(buyer2);
        sale.buy(uint128(paymentFor150k), new bytes32[](0)); // 150k tokens

        // Check stage 1 schedule (separate) - first purchase was in stage 1
        (uint128 total1, , uint64 start1, uint64 periodLength1, uint16[] memory sched1) = 
            sale.getVestingSchedule(buyer2, 1);
        assertEq(total1, 200_000 ether); // 100e6 at price 50 = 200k tokens (100e6 * 100000 * 1e12 / 50)
        assertEq(start1, vestStart2); // Stage 1's vestStart
        assertEq(periodLength1, 30 days);
        assertEq(sched1.length, 6);

        // Check stage 2 schedule (separate)
        (uint128 total2, , uint64 start2, uint64 periodLength2, uint16[] memory sched2) = 
            sale.getVestingSchedule(buyer2, 2);
        assertGe(total2, 149_999 ether);
        assertLe(total2, 150_001 ether);
        assertEq(start2, vestStart3); // Stage 2's vestStart
        assertEq(periodLength2, 30 days);
        assertEq(sched2.length, 3);

        // Period 0 does NOT vest immediately
        assertEq(sale.releasableAmount(buyer2), 0);
        
        // After vestStart2 + 30 days - period 0 of stage 1 vests (16.67% of 200k)
        vm.warp(vestStart2 + 30 days);
        uint256 expectedReleasable1 = (total1 * 1667) / 10000; // 16.67% of stage 1
        assertEq(sale.releasableAmount(buyer2), expectedReleasable1);
        vm.prank(buyer2);
        sale.release();
        assertEq(emyo.balanceOf(buyer2), expectedReleasable1);

        // After vestStart3 + 30 days - period 0 of stage 2 also vests (33.33% of 150k)
        vm.warp(vestStart3 + 30 days);
        uint256 expectedReleasable2 = (total2 * 3333) / 10000; // 33.33% of stage 2
        assertGe(sale.releasableAmount(buyer2), expectedReleasable2 - 1); // Stage 2 period 0 vests
        vm.prank(buyer2);
        sale.release();
    }
}
