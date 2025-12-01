// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VestingLibrary} from "src/vesting/VestingLibrary.sol";

contract VestingLibraryTest is Test {
    using VestingLibrary for VestingLibrary.Schedule;

    function test_VestedAmount_ReturnsZero_BeforeStart() public {
        VestingLibrary.Schedule memory s = _createSchedule(1_000_000 ether, uint64(uint64(block.timestamp) + 1 days), 30 days);
        uint256 vested = VestingLibrary.vestedAmount(s, uint64(uint64(block.timestamp)));
        assertEq(vested, 0);
    }

    function test_VestedAmount_ReturnsZero_IfNoPercentages() public {
        VestingLibrary.Schedule memory s = _createSchedule(1_000_000 ether, uint64(block.timestamp), 30 days);
        s.percentages = new uint16[](0);
        uint256 vested = VestingLibrary.vestedAmount(s, uint64(uint64(block.timestamp) + 1 days));
        assertEq(vested, 0);
    }

    function test_VestedAmount_ReturnsZero_IfZeroPeriodLength() public {
        VestingLibrary.Schedule memory s = _createSchedule(1_000_000 ether, uint64(block.timestamp), 0);
        uint256 vested = VestingLibrary.vestedAmount(s, uint64(uint64(block.timestamp) + 1 days));
        assertEq(vested, 0);
    }

    function test_VestedAmount_FirstPeriod() public {
        VestingLibrary.Schedule memory s = _createSchedule(1_000_000 ether, uint64(block.timestamp), 30 days);
        // After periodLength (30 days), first period should vest
        uint256 vested = VestingLibrary.vestedAmount(s, uint64(uint64(block.timestamp) + 30 days));
        assertEq(vested, 250_000 ether);
    }

    function test_VestedAmount_SecondPeriod() public {
        VestingLibrary.Schedule memory s = _createSchedule(1_000_000 ether, uint64(block.timestamp), 30 days);
        // After 60 days (2 periods), periods 0 and 1 should vest (50%)
        uint256 vested = VestingLibrary.vestedAmount(s, uint64(uint64(block.timestamp) + 60 days));
        assertEq(vested, 500_000 ether);
    }

    function test_VestedAmount_AllPeriods() public {
        VestingLibrary.Schedule memory s = _createSchedule(1_000_000 ether, uint64(block.timestamp), 30 days);
        uint256 vested = VestingLibrary.vestedAmount(s, uint64(uint64(block.timestamp) + 150 days));
        assertEq(vested, 1_000_000 ether);
    }

    function test_VestedAmount_AfterAllPeriods() public {
        VestingLibrary.Schedule memory s = _createSchedule(1_000_000 ether, uint64(block.timestamp), 30 days);
        uint256 vested = VestingLibrary.vestedAmount(s, uint64(uint64(block.timestamp) + 300 days));
        assertEq(vested, 1_000_000 ether);
    }

    function test_VestedAmount_UnevenPercentages() public {
        VestingLibrary.Schedule memory s;
        s.total = 1_000_000 ether;
        s.start = uint64(uint64(block.timestamp));
        s.periodLength = 30 days;
        s.percentages = new uint16[](5);
        s.percentages[0] = 1000;
        s.percentages[1] = 1500;
        s.percentages[2] = 2000;
        s.percentages[3] = 2500;
        s.percentages[4] = 3000;

        // After 30 days: only period 0 is vested (10%)
        uint256 vested1 = VestingLibrary.vestedAmount(s, uint64(uint64(block.timestamp) + 30 days));
        assertEq(vested1, 100_000 ether);

        // After 60 days: periods 0 and 1 are vested (10% + 15% = 25%)
        uint256 vested2 = VestingLibrary.vestedAmount(s, uint64(uint64(block.timestamp) + 60 days));
        assertEq(vested2, 250_000 ether);

        // After 90 days: periods 0, 1, and 2 are vested (10% + 15% + 20% = 45%)
        uint256 vested3 = VestingLibrary.vestedAmount(s, uint64(uint64(block.timestamp) + 90 days));
        assertEq(vested3, 450_000 ether);
    }

    function test_ReleasableAmount_ReturnsZero_BeforeVesting() public {
        VestingLibrary.Schedule memory s = _createSchedule(1_000_000 ether, uint64(uint64(block.timestamp) + 1 days), 30 days);
        uint256 releasable = VestingLibrary.releasableAmount(s, uint64(block.timestamp));
        assertEq(releasable, 0);
    }

    function test_ReleasableAmount_ReturnsZero_IfAlreadyReleased() public {
        VestingLibrary.Schedule memory s = _createSchedule(1_000_000 ether, uint64(block.timestamp), 30 days);
        s.released = 250_000 ether;
        uint256 releasable = VestingLibrary.releasableAmount(s, uint64(uint64(block.timestamp) + 15 days));
        assertEq(releasable, 0);
    }

    function test_ReleasableAmount_CalculatesCorrectly() public {
        VestingLibrary.Schedule memory s = _createSchedule(1_000_000 ether, uint64(block.timestamp), 30 days);
        s.released = 0;
        // After 30 days, only period 0 is vested (25% total)
        uint256 releasable = VestingLibrary.releasableAmount(s, uint64(uint64(block.timestamp) + 30 days));
        assertEq(releasable, 250_000 ether);
    }

    function test_ReleasableAmount_PartialRelease() public {
        VestingLibrary.Schedule memory s = _createSchedule(1_000_000 ether, uint64(block.timestamp), 30 days);
        s.released = 100_000 ether;
        // After 30 days, only period 0 is vested (25% = 250k), minus 100k released = 150k
        uint256 releasable = VestingLibrary.releasableAmount(s, uint64(uint64(block.timestamp) + 30 days));
        assertEq(releasable, 150_000 ether);
    }

    function test_ValidatePercentages_ReturnsTrue_IfValid() public {
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;
        assertTrue(VestingLibrary.validatePercentages(percentages));
    }

    function test_ValidatePercentages_ReturnsFalse_IfInvalid() public {
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2000;
        percentages[1] = 2000;
        percentages[2] = 2000;
        percentages[3] = 2000;
        assertFalse(VestingLibrary.validatePercentages(percentages));
    }

    function test_ValidatePercentages_ReturnsFalse_IfEmpty() public {
        uint16[] memory percentages = new uint16[](0);
        assertFalse(VestingLibrary.validatePercentages(percentages));
    }

    function test_ValidatePercentages_ReturnsTrue_SinglePeriod() public {
        uint16[] memory percentages = new uint16[](1);
        percentages[0] = 10000;
        assertTrue(VestingLibrary.validatePercentages(percentages));
    }

    function testFuzz_VestedAmount_WithinBounds(uint64 timestamp) public {
        uint64 start = uint64(uint64(block.timestamp));
        VestingLibrary.Schedule memory s = _createSchedule(1_000_000 ether, start, 30 days);
        timestamp = uint64(bound(timestamp, start, start + 200 days));
        uint256 vested = VestingLibrary.vestedAmount(s, timestamp);
        assertLe(vested, 1_000_000 ether);
    }

    function testFuzz_ReleasableAmount_WithinBounds(uint64 timestamp, uint128 released) public {
        uint64 start = uint64(uint64(block.timestamp));
        VestingLibrary.Schedule memory s = _createSchedule(1_000_000 ether, start, 30 days);
        timestamp = uint64(bound(timestamp, start, start + 200 days));
        released = uint128(bound(released, 0, 1_000_000 ether));
        s.released = released;
        uint256 releasable = VestingLibrary.releasableAmount(s, timestamp);
        assertLe(releasable, 1_000_000 ether);
    }

    function testFuzz_ValidatePercentages_SumTo10000(uint16[] memory percentages) public {
        uint256 sum = 0;
        for (uint256 i = 0; i < percentages.length; i++) {
            sum += percentages[i];
        }
        bool expected = (sum == 10000);
        assertEq(VestingLibrary.validatePercentages(percentages), expected);
    }

    /// @notice CRITICAL #1: Test that vesting does NOT happen immediately at start time
    function test_VestedAmount_ShouldNotVestImmediately_AtStartTime() public {
        VestingLibrary.Schedule memory s = _createSchedule(1_000_000 ether, uint64(block.timestamp), 30 days);
        
        // At exact start time, should vest 0, not first period (25%)
        uint256 vested = VestingLibrary.vestedAmount(s, uint64(block.timestamp));
        assertEq(vested, 0, "Should not vest immediately at start time");
    }

    /// @notice CRITICAL #1: Test that vesting requires at least one period to pass
    function test_VestedAmount_ShouldNotVest_BeforeFirstPeriod() public {
        VestingLibrary.Schedule memory s = _createSchedule(1_000_000 ether, uint64(block.timestamp), 30 days);
        
        // After 1 day (still in period 0), should vest 0
        uint256 vested = VestingLibrary.vestedAmount(s, uint64(block.timestamp + 1 days));
        assertEq(vested, 0, "Should not vest before first period completes");
        
        // After 15 days (still in period 0), should vest 0
        vested = VestingLibrary.vestedAmount(s, uint64(block.timestamp + 15 days));
        assertEq(vested, 0, "Should not vest before first period completes");
        
        // After periodLength (30 days), first period should vest
        vested = VestingLibrary.vestedAmount(s, uint64(block.timestamp + 30 days));
        assertEq(vested, 250_000 ether, "Should vest first period after periodLength");
    }

    function _createSchedule(uint128 total, uint64 start, uint64 periodLength) internal pure returns (VestingLibrary.Schedule memory) {
        VestingLibrary.Schedule memory s;
        s.total = total;
        s.start = start;
        s.periodLength = periodLength;
        s.percentages = new uint16[](4);
        s.percentages[0] = 2500;
        s.percentages[1] = 2500;
        s.percentages[2] = 2500;
        s.percentages[3] = 2500;
        return s;
    }
}

