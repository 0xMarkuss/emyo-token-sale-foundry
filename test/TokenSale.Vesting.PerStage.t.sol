// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TokenSale} from "src/sale/TokenSale.sol";
import {Treasury} from "src/treasury/Treasury.sol";
import {EmyoToken} from "src/token/EmyoToken.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {Roles} from "src/access/Roles.sol";
import {Errors} from "src/libs/Errors.sol";

/// @title TokenSale Per-Stage Vesting Tests
/// @notice Tests that verify separate vesting schedules per stage
contract TokenSaleVestingPerStageTest is Test {
    MockERC20 paymentToken;
    EmyoToken saleToken;
    Treasury treasury;
    TokenSale sale;

    address admin = address(0xA11CE);
    address buyer1 = address(0xB0B1);
    address buyer2 = address(0xB0B2);
    address buyer3 = address(0xB0B3);

    function setUp() public {
        paymentToken = new MockERC20("USDC", "USDC", 6);
        treasury = new Treasury(admin);
        saleToken = new EmyoToken("Emyo", "EMY", 10_000_000 ether, address(treasury));
        sale = new TokenSale(paymentToken, saleToken, address(treasury), admin);

        // Fund users with payment tokens
        paymentToken.mint(buyer1, 1_000_000e6);
        paymentToken.mint(buyer2, 1_000_000e6);
        paymentToken.mint(buyer3, 1_000_000e6);
        
        vm.startPrank(buyer1);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(buyer2);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(buyer3);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();

        // Fund sale contract with tokens for vesting releases
        vm.prank(admin);
        treasury.withdrawERC20(saleToken, address(sale), 5_000_000 ether);
    }

    /// @notice Test that all users buying in the same stage share the same vestStart
    function test_MultipleUsers_SameStage_ShareVestStart() public {
        uint64 nowTs = uint64(block.timestamp);
        uint64 stageEnd = nowTs + 7 days;
        uint64 vestStart = nowTs + 10 days; // Vesting starts 10 days from now
        uint64 vestPeriodLength = 30 days;
        
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(100, stageEnd, vestStart, vestPeriodLength, percentages);

        // Buyer1 buys at time T0
        vm.warp(nowTs + 1 days);
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        // Buyer2 buys at time T1 (different time, same stage)
        vm.warp(nowTs + 2 days);
        vm.prank(buyer2);
        sale.buy(100e6, new bytes32[](0));

        // Buyer3 buys at time T2 (different time, same stage)
        vm.warp(nowTs + 3 days);
        vm.prank(buyer3);
        sale.buy(100e6, new bytes32[](0));

        // All users should have the same vestStart (stage's vestStart, not their purchase time)
        (uint128 total1, , uint64 start1, , ) = sale.getVestingSchedule(buyer1, 0);
        (uint128 total2, , uint64 start2, , ) = sale.getVestingSchedule(buyer2, 0);
        (uint128 total3, , uint64 start3, , ) = sale.getVestingSchedule(buyer3, 0);

        assertEq(start1, vestStart, "Buyer1 vestStart should match stage vestStart");
        assertEq(start2, vestStart, "Buyer2 vestStart should match stage vestStart");
        assertEq(start3, vestStart, "Buyer3 vestStart should match stage vestStart");
        assertEq(start1, start2, "All users should share same vestStart");
        assertEq(start2, start3, "All users should share same vestStart");
        
        assertEq(total1, 100_000 ether);
        assertEq(total2, 100_000 ether);
        assertEq(total3, 100_000 ether);
    }

    /// @notice Test that multiple purchases by same user in same stage are summed
    function test_SameUser_MultiplePurchases_SameStage_Summed() public {
        uint64 nowTs = uint64(block.timestamp);
        uint64 stageEnd = nowTs + 7 days;
        uint64 vestStart = nowTs + 10 days;
        uint64 vestPeriodLength = 30 days;
        
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(100, stageEnd, vestStart, vestPeriodLength, percentages);

        // First purchase: 100 USDC => 100k tokens
        vm.warp(nowTs + 1 days);
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        (uint128 total1, , uint64 start1, , ) = sale.getVestingSchedule(buyer1, 0);
        assertEq(total1, 100_000 ether);
        assertEq(start1, vestStart);

        // Second purchase in same stage: 50 USDC => 50k tokens
        vm.warp(nowTs + 2 days);
        vm.prank(buyer1);
        sale.buy(50e6, new bytes32[](0));

        // Total should be summed, vestStart should remain the same
        (uint128 total2, , uint64 start2, , ) = sale.getVestingSchedule(buyer1, 0);
        assertEq(total2, 150_000 ether, "Purchases should be summed");
        assertEq(start2, vestStart, "vestStart should remain unchanged");
        
        // Third purchase in same stage: 25 USDC => 25k tokens
        vm.warp(nowTs + 3 days);
        vm.prank(buyer1);
        sale.buy(25e6, new bytes32[](0));

        (uint128 total3, , uint64 start3, , ) = sale.getVestingSchedule(buyer1, 0);
        assertEq(total3, 175_000 ether, "All purchases should be summed");
        assertEq(start3, vestStart, "vestStart should remain unchanged");
    }

    /// @notice Test that different stages have separate vesting schedules
    function test_DifferentStages_SeparateVestingSchedules() public {
        uint64 nowTs = uint64(block.timestamp);
        
        // Stage 0: 4 periods, 25% each, 30 days per period
        uint64 stage0End = nowTs + 7 days;
        uint64 stage0VestStart = nowTs + 10 days;
        uint64 stage0PeriodLength = 30 days;
        uint16[] memory percentages0 = new uint16[](4);
        percentages0[0] = 2500;
        percentages0[1] = 2500;
        percentages0[2] = 2500;
        percentages0[3] = 2500;

        // Stage 1: 3 periods, 33.33% each, 20 days per period
        uint64 stage1End = nowTs + 14 days;
        uint64 stage1VestStart = nowTs + 20 days;
        uint64 stage1PeriodLength = 20 days;
        uint16[] memory percentages1 = new uint16[](3);
        percentages1[0] = 3333;
        percentages1[1] = 3333;
        percentages1[2] = 3334;

        vm.startPrank(admin);
        sale.addStage(100, stage0End, stage0VestStart, stage0PeriodLength, percentages0);
        sale.addStage(50, stage1End, stage1VestStart, stage1PeriodLength, percentages1);
        vm.stopPrank();

        // Buy in Stage 0: 100 USDC => 100k tokens
        vm.warp(nowTs + 1 days);
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        // Buy in Stage 1: 50 USDC => 100k tokens (50 * 100000 * 1e12 / 50)
        vm.warp(nowTs + 8 days);
        vm.prank(buyer1);
        sale.buy(50e6, new bytes32[](0));

        // Verify Stage 0 schedule
        (uint128 total0, uint128 released0, uint64 start0, uint64 periodLength0, uint16[] memory sched0) = 
            sale.getVestingSchedule(buyer1, 0);
        assertEq(total0, 100_000 ether);
        assertEq(released0, 0);
        assertEq(start0, stage0VestStart);
        assertEq(periodLength0, stage0PeriodLength);
        assertEq(sched0.length, 4);

        // Verify Stage 1 schedule (separate)
        (uint128 total1, uint128 released1, uint64 start1, uint64 periodLength1, uint16[] memory sched1) = 
            sale.getVestingSchedule(buyer1, 1);
        assertEq(total1, 100_000 ether);
        assertEq(released1, 0);
        assertEq(start1, stage1VestStart);
        assertEq(periodLength1, stage1PeriodLength);
        assertEq(sched1.length, 3);

        // Verify schedules are independent
        assertNotEq(start0, start1, "Stages should have different vestStart");
        assertNotEq(periodLength0, periodLength1, "Stages should have different periodLength");
        assertNotEq(sched0.length, sched1.length, "Stages should have different schedules");

        // Verify userStages array
        uint256[] memory userStages = sale.getUserStages(buyer1);
        assertEq(userStages.length, 2);
        assertEq(userStages[0], 0);
        assertEq(userStages[1], 1);
    }

    /// @notice Test release from multiple stages works correctly
    function test_Release_MultipleStages_IndependentRelease() public {
        uint64 nowTs = uint64(block.timestamp);
        
        // Stage 0: 4 periods, 25% each, 30 days per period
        uint64 stage0End = nowTs + 7 days;
        uint64 stage0VestStart = nowTs + 10 days;
        uint64 stage0PeriodLength = 30 days;
        uint16[] memory percentages0 = new uint16[](4);
        percentages0[0] = 2500;
        percentages0[1] = 2500;
        percentages0[2] = 2500;
        percentages0[3] = 2500;

        // Stage 1: 3 periods, 33.33% each, 20 days per period
        uint64 stage1End = nowTs + 14 days;
        uint64 stage1VestStart = nowTs + 20 days;
        uint64 stage1PeriodLength = 20 days;
        uint16[] memory percentages1 = new uint16[](3);
        percentages1[0] = 3333;
        percentages1[1] = 3333;
        percentages1[2] = 3334;

        vm.startPrank(admin);
        sale.addStage(100, stage0End, stage0VestStart, stage0PeriodLength, percentages0);
        sale.addStage(50, stage1End, stage1VestStart, stage1PeriodLength, percentages1);
        vm.stopPrank();

        // Buy in Stage 0: 100 USDC => 100k tokens
        vm.warp(nowTs + 1 days);
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        // Buy in Stage 1: 50 USDC => 100k tokens
        vm.warp(nowTs + 8 days);
        vm.prank(buyer1);
        sale.buy(50e6, new bytes32[](0));

        // Before vestStart, nothing should be releasable
        vm.warp(stage0VestStart - 1);
        assertEq(sale.releasableAmount(buyer1), 0);
        assertEq(sale.releasableAmountForStage(buyer1, 0), 0);
        assertEq(sale.releasableAmountForStage(buyer1, 1), 0);

        // After Stage 0 vestStart + 30 days: Stage 0 period 0 vests (25% = 25k)
        // At this point: stage0VestStart + 30 days = nowTs + 40 days
        // Stage 1 vestStart = nowTs + 20 days, so Stage 1 has been vesting for 20 days
        // Stage 1 period length is 20 days, so period 0 is complete (33.33% = 33.33k)
        vm.warp(stage0VestStart + 30 days);
        assertEq(sale.releasableAmountForStage(buyer1, 0), 25_000 ether);
        assertEq(sale.releasableAmountForStage(buyer1, 1), 33_330 ether, "Stage 1 period 0 has completed");
        assertEq(sale.releasableAmount(buyer1), 58_330 ether, "Total releasable from both stages");

        // Release from both stages (releases all releasable tokens: 25k from Stage 0 + 33.33k from Stage 1)
        vm.prank(buyer1);
        sale.release();
        assertEq(saleToken.balanceOf(buyer1), 58_330 ether);
        assertEq(sale.releasableAmount(buyer1), 0);

        // After Stage 0 vestStart + 60 days: Stage 0 period 1 vests (25% = 25k more, total 50% vested)
        // Stage 1 period 1 needs 40 days total from vestStart (stage1VestStart + 40 days = nowTs + 60 days)
        // At nowTs + 70 days, Stage 1 has been vesting for 50 days, so period 1 (40 days) is complete
        vm.warp(stage0VestStart + 60 days);
        assertEq(sale.releasableAmountForStage(buyer1, 0), 25_000 ether, "Stage 0 period 1");
        assertEq(sale.releasableAmountForStage(buyer1, 1), 33_330 ether, "Stage 1 period 1 has completed");
        assertEq(sale.releasableAmount(buyer1), 58_330 ether, "Both Stage 0 period 1 and Stage 1 period 1");

        // Release from both stages (Stage 0 period 1 + Stage 1 period 1)
        vm.prank(buyer1);
        sale.release();
        assertEq(saleToken.balanceOf(buyer1), 116_660 ether, "Total: 58.33k (first release) + 58.33k (second release)");
        assertEq(sale.releasableAmount(buyer1), 0);
    }

    /// @notice Test that same user buying in same stage multiple times gets summed correctly
    function test_SameUser_SameStage_MultiplePurchases_ReleaseWorks() public {
        uint64 nowTs = uint64(block.timestamp);
        uint64 stageEnd = nowTs + 7 days;
        uint64 vestStart = nowTs + 10 days;
        uint64 vestPeriodLength = 30 days;
        
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(100, stageEnd, vestStart, vestPeriodLength, percentages);

        // First purchase: 100 USDC => 100k tokens
        vm.warp(nowTs + 1 days);
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        // Second purchase in same stage: 50 USDC => 50k tokens
        vm.warp(nowTs + 2 days);
        vm.prank(buyer1);
        sale.buy(50e6, new bytes32[](0));

        // Total should be 150k tokens, all in one schedule
        (uint128 total, , , , ) = sale.getVestingSchedule(buyer1, 0);
        assertEq(total, 150_000 ether);

        // After vestStart + 30 days: 25% of 150k = 37.5k should be releasable
        vm.warp(vestStart + 30 days);
        assertEq(sale.releasableAmount(buyer1), 37_500 ether, "Buyer1: 25% of 150k (single stage test)");
        assertEq(sale.releasableAmountForStage(buyer1, 0), 37_500 ether);

        // Release
        vm.prank(buyer1);
        sale.release();
        assertEq(saleToken.balanceOf(buyer1), 37_500 ether);

        // After vestStart + 60 days: 50% total = 75k, minus 37.5k released = 37.5k more
        vm.warp(vestStart + 60 days);
        assertEq(sale.releasableAmount(buyer1), 37_500 ether, "Buyer1: 50% of 150k - 37.5k released = 37.5k more");
    }

    /// @notice Test complex scenario: multiple users, multiple stages, multiple purchases
    function test_Complex_MultipleUsers_MultipleStages_MultiplePurchases() public {
        uint64 nowTs = uint64(block.timestamp);
        uint64 stage0End = nowTs + 7 days;
        uint64 stage1End = nowTs + 14 days;
        uint64 stage0VestStart = nowTs + 10 days;
        uint64 stage1VestStart = nowTs + 20 days;
        uint64 stage0PeriodLength = 30 days;
        uint64 stage1PeriodLength = 20 days;
        uint64 stage1Start = stage0End + 1;

        uint16[] memory percentages0 = new uint16[](4);
        percentages0[0] = 2500;
        percentages0[1] = 2500;
        percentages0[2] = 2500;
        percentages0[3] = 2500;

        uint16[] memory percentages1 = new uint16[](3);
        percentages1[0] = 3333;
        percentages1[1] = 3333;
        percentages1[2] = 3334;

        vm.startPrank(admin);
        sale.addStage(100, stage0End, stage0VestStart, stage0PeriodLength, percentages0);
        sale.addStage(50, stage1End, stage1VestStart, stage1PeriodLength, percentages1);
        vm.stopPrank();

        vm.warp(stage0End - 6 days);
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        vm.warp(stage0End - 5 days);
        vm.prank(buyer1);
        sale.buy(50e6, new bytes32[](0));

        vm.warp(stage1Start);
        vm.prank(buyer1);
        sale.buy(50e6, new bytes32[](0));

        vm.warp(stage0End - 4 days);
        vm.prank(buyer2);
        sale.buy(100e6, new bytes32[](0));

        vm.warp(stage1Start + 1 days);
        vm.prank(buyer2);
        sale.buy(25e6, new bytes32[](0));

        vm.warp(stage1Start + 2 days);
        vm.prank(buyer2);
        sale.buy(25e6, new bytes32[](0));

        // Verify Buyer1 schedules
        (uint128 total1_0, , uint64 start1_0, , ) = sale.getVestingSchedule(buyer1, 0);
        (uint128 total1_1, , uint64 start1_1, , ) = sale.getVestingSchedule(buyer1, 1);
        assertEq(total1_0, 150_000 ether, "Buyer1 Stage 0 should sum purchases");
        assertEq(total1_1, 100_000 ether, "Buyer1 Stage 1");
        assertEq(start1_0, stage0VestStart, "Buyer1 Stage 0 vestStart");
        assertEq(start1_1, stage1VestStart, "Buyer1 Stage 1 vestStart");

        // Verify Buyer2 schedules
        (uint128 total2_0, , uint64 start2_0, , ) = sale.getVestingSchedule(buyer2, 0);
        (uint128 total2_1, , uint64 start2_1, , ) = sale.getVestingSchedule(buyer2, 1);
        assertEq(total2_0, 100_000 ether, "Buyer2 Stage 0");
        assertEq(total2_1, 100_000 ether, "Buyer2 Stage 1 should sum purchases");
        assertEq(start2_0, stage0VestStart, "Buyer2 Stage 0 vestStart");
        assertEq(start2_1, stage1VestStart, "Buyer2 Stage 1 vestStart");

        // Verify all users in Stage 0 share same vestStart
        assertEq(start1_0, start2_0, "All users in Stage 0 should share vestStart");
        
        // Verify all users in Stage 1 share same vestStart
        assertEq(start1_1, start2_1, "All users in Stage 1 should share vestStart");

        // After Stage 0 vestStart + 30 days: Stage 0 period 0 vests (25% of totals)
        // Stage 1 has also been vesting: stage1VestStart = nowTs + 20 days, we're at nowTs + 40 days
        // Stage 1 period length is 20 days, so period 0 is complete (33.33% of totals)
        vm.warp(stage0VestStart + 30 days);
        assertEq(sale.releasableAmountForStage(buyer1, 0), 37_500 ether, "Buyer1 Stage 0: 25% of 150k");
        assertEq(sale.releasableAmountForStage(buyer1, 1), 33_330 ether, "Buyer1 Stage 1: 33.33% of 100k");
        assertEq(sale.releasableAmountForStage(buyer2, 0), 25_000 ether, "Buyer2 Stage 0: 25% of 100k");
        assertEq(sale.releasableAmountForStage(buyer2, 1), 33_330 ether, "Buyer2 Stage 1: 33.33% of 100k");
        assertEq(sale.releasableAmount(buyer1), 70_830 ether, "Buyer1 total: 37.5k + 33.33k");
        assertEq(sale.releasableAmount(buyer2), 58_330 ether, "Buyer2 total: 25k + 33.33k");

        // Release (both stages release together)
        vm.prank(buyer1);
        sale.release();
        vm.prank(buyer2);
        sale.release();
        
        assertEq(saleToken.balanceOf(buyer1), 70_830 ether, "Buyer1: 37.5k (Stage 0) + 33.33k (Stage 1)");
        assertEq(saleToken.balanceOf(buyer2), 58_330 ether, "Buyer2: 25k (Stage 0) + 33.33k (Stage 1)");
    }
}

