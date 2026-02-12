// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vesting} from "src/vesting/Vesting.sol";
import {EmyoToken} from "src/token/EmyoToken.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Roles} from "src/access/Roles.sol";
import {Errors} from "src/libs/Errors.sol";

contract VestingTest is Test {
    EmyoToken token;
    Vesting vesting;

    address admin = address(0xA11CE);
    address beneficiary1 = address(0xB0B1);
    address beneficiary2 = address(0xB0B2);
    address unauthorized = address(0xBAD);

    function setUp() public {
        token = new EmyoToken("Emyo", "EMY", 10_000_000 ether, address(this));
        vesting = new Vesting(token, admin);
        token.transfer(address(vesting), 5_000_000 ether);
    }

    function test_Constructor_SetsCorrectValues() public {
        assertEq(address(vesting.token()), address(token));
        assertTrue(vesting.hasRole(0x00, admin));
        assertTrue(vesting.hasRole(Roles.PAUSER_ROLE, admin));
        assertTrue(vesting.hasRole(Roles.VESTING_ADMIN_ROLE, admin));
        assertEq(vesting.defaultStartDelay(), 0);
        assertEq(vesting.defaultPeriodLength(), 30 days);
        assertEq(vesting.defaultPercentages(0), 2500);
        assertEq(vesting.defaultPercentages(1), 2500);
        assertEq(vesting.defaultPercentages(2), 2500);
        assertEq(vesting.defaultPercentages(3), 2500);
    }

    function test_Constructor_RevertIf_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new Vesting(IERC20(address(0)), admin);

        vm.expectRevert(Errors.ZeroAddress.selector);
        new Vesting(token, address(0));
    }

    function test_SetDefaults_Success() public {
        uint64 startDelay = 7 days;
        uint64 periodLength = 60 days;
        uint16[] memory percentages = new uint16[](5);
        percentages[0] = 2000;
        percentages[1] = 2000;
        percentages[2] = 2000;
        percentages[3] = 2000;
        percentages[4] = 2000;

        vm.prank(admin);
        vesting.setDefaults(startDelay, periodLength, percentages);

        assertEq(vesting.defaultStartDelay(), startDelay);
        assertEq(vesting.defaultPeriodLength(), periodLength);
        assertEq(vesting.defaultPercentages(0), 2000);
        assertEq(vesting.defaultPercentages(1), 2000);
        assertEq(vesting.defaultPercentages(2), 2000);
        assertEq(vesting.defaultPercentages(3), 2000);
        assertEq(vesting.defaultPercentages(4), 2000);
    }

    function test_SetDefaults_RevertIf_Unauthorized() public {
        uint64 startDelay = 7 days;
        uint64 periodLength = 60 days;
        uint16[] memory percentages = new uint16[](5);
        percentages[0] = 2000;
        percentages[1] = 2000;
        percentages[2] = 2000;
        percentages[3] = 2000;
        percentages[4] = 2000;

        vm.expectRevert();
        vm.prank(unauthorized);
        vesting.setDefaults(startDelay, periodLength, percentages);
    }

    function test_SetDefaults_RevertIf_ZeroPeriodLength() public {
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(admin);
        vesting.setDefaults(0, 0, percentages);
    }

    function test_SetDefaults_RevertIf_InvalidPercentages() public {
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2000;
        percentages[1] = 2000;
        percentages[2] = 2000;
        percentages[3] = 2000;

        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(admin);
        vesting.setDefaults(0, 30 days, percentages);
    }

    function test_Allocate_Success() public {
        uint128 amount = 1_000_000 ether;
        vm.prank(admin);
        vesting.allocate(beneficiary1, amount);

        (uint128 total, , uint64 start, uint64 periodLength, uint16[] memory percentages) = 
            vesting.schedules(beneficiary1);
        assertEq(total, amount);
        assertEq(start, block.timestamp);
        assertEq(periodLength, 30 days);
        assertEq(percentages.length, 4);
    }

    function test_Allocate_WithStartDelay() public {
        uint64 startDelay = 7 days;
        uint16[] memory defaultPct = new uint16[](4);
        defaultPct[0] = vesting.defaultPercentages(0);
        defaultPct[1] = vesting.defaultPercentages(1);
        defaultPct[2] = vesting.defaultPercentages(2);
        defaultPct[3] = vesting.defaultPercentages(3);
        vm.prank(admin);
        vesting.setDefaults(startDelay, 30 days, defaultPct);

        uint128 amount = 1_000_000 ether;
        vm.prank(admin);
        vesting.allocate(beneficiary1, amount);

        (uint128 total, , uint64 start, , ) = vesting.schedules(beneficiary1);
        assertEq(total, amount);
        assertEq(start, block.timestamp + startDelay);
    }

    function test_Allocate_TopUp_ExistingSchedule() public {
        uint128 amount1 = 1_000_000 ether;
        vm.prank(admin);
        vesting.allocate(beneficiary1, amount1);

        uint128 amount2 = 500_000 ether;
        vm.prank(admin);
        vesting.allocate(beneficiary1, amount2);

        (uint128 total, , , , ) = vesting.schedules(beneficiary1);
        assertEq(total, amount1 + amount2);
    }

    function test_Allocate_RevertIf_Unauthorized() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        vesting.allocate(beneficiary1, 1_000_000 ether);
    }

    function test_Allocate_RevertIf_Paused() public {
        vm.prank(admin);
        vesting.pause();

        vm.expectRevert();
        vm.prank(admin);
        vesting.allocate(beneficiary1, 1_000_000 ether);
    }

    function test_CreateOrIncreaseSchedule_Success() public {
        uint64 start = uint64(block.timestamp);
        uint64 periodLength = 30 days;
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        uint128 amount = 1_000_000 ether;
        vm.prank(admin);
        vesting.createOrIncreaseSchedule(beneficiary1, amount, start, periodLength, percentages);

        (uint128 total, , uint64 actualStart, uint64 actualPeriodLength, uint16[] memory actualPercentages) = 
            vesting.schedules(beneficiary1);
        assertEq(total, amount);
        assertEq(actualStart, start);
        assertEq(actualPeriodLength, periodLength);
        assertEq(actualPercentages.length, 4);
    }

    function test_CreateOrIncreaseSchedule_TopUp_MatchingParams() public {
        uint64 start = uint64(block.timestamp);
        uint64 periodLength = 30 days;
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        vesting.createOrIncreaseSchedule(beneficiary1, 1_000_000 ether, start, periodLength, percentages);
        vesting.createOrIncreaseSchedule(beneficiary1, 500_000 ether, start, periodLength, percentages);
        vm.stopPrank();

        (uint128 total, , , , ) = vesting.schedules(beneficiary1);
        assertEq(total, 1_500_000 ether);
    }

    function test_CreateOrIncreaseSchedule_RevertIf_MismatchedParams() public {
        uint64 start = uint64(block.timestamp);
        uint64 periodLength = 30 days;
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        vesting.createOrIncreaseSchedule(beneficiary1, 1_000_000 ether, start, periodLength, percentages);
        vm.expectRevert(Errors.InvalidParam.selector);
        vesting.createOrIncreaseSchedule(beneficiary1, 500_000 ether, start + 1, periodLength, percentages);
        vm.stopPrank();
    }

    function test_CreateOrIncreaseSchedule_RevertIf_ZeroAddress() public {
        uint64 start = uint64(block.timestamp);
        uint64 periodLength = 30 days;
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        vesting.createOrIncreaseSchedule(address(0), 1_000_000 ether, start, periodLength, percentages);
    }

    function test_CreateOrIncreaseSchedule_RevertIf_ZeroAmount() public {
        uint64 start = uint64(block.timestamp);
        uint64 periodLength = 30 days;
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(admin);
        vesting.createOrIncreaseSchedule(beneficiary1, 0, start, periodLength, percentages);
    }

    function test_CreateOrIncreaseSchedule_RevertIf_ZeroPeriodLength() public {
        uint64 start = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(admin);
        vesting.createOrIncreaseSchedule(beneficiary1, 1_000_000 ether, start, 0, percentages);
    }

    function test_CreateOrIncreaseSchedule_RevertIf_InvalidPercentages() public {
        uint64 start = uint64(block.timestamp);
        uint64 periodLength = 30 days;
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2000;
        percentages[1] = 2000;
        percentages[2] = 2000;
        percentages[3] = 2000;

        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(admin);
        vesting.createOrIncreaseSchedule(beneficiary1, 1_000_000 ether, start, periodLength, percentages);
    }

    function test_Release_Success() public {
        uint64 start = uint64(block.timestamp);
        uint64 periodLength = 30 days;
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        vesting.createOrIncreaseSchedule(beneficiary1, 1_000_000 ether, start, periodLength, percentages);

        vm.warp(start + 30 days);
        uint256 releasable = vesting.releasableAmount(beneficiary1);
        // After 30 days, only period 0 is vested (25% total) - FIX CRITICAL #1
        assertEq(releasable, 250_000 ether);

        vm.prank(beneficiary1);
        vesting.release(beneficiary1);
        assertEq(token.balanceOf(beneficiary1), 250_000 ether);
    }

    function test_Release_ReturnsZero_IfNothingReleasable() public {
        uint64 start = uint64(block.timestamp);
        uint64 periodLength = 30 days;
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        vesting.createOrIncreaseSchedule(beneficiary1, 1_000_000 ether, start, periodLength, percentages);

        // Period 0 vests immediately, so release it first
        vm.prank(beneficiary1);
        vesting.release(beneficiary1);
        
        // Now nothing should be releasable until period 1 vests (after 30 days)
        vm.prank(beneficiary1);
        uint256 released = vesting.release(beneficiary1);
        assertEq(released, 0);
    }

    function test_Release_RevertIf_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(beneficiary1);
        vesting.release(address(0));
    }

    function test_Release_RevertIf_Paused() public {
        uint64 start = uint64(block.timestamp);
        uint64 periodLength = 30 days;
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        vesting.createOrIncreaseSchedule(beneficiary1, 1_000_000 ether, start, periodLength, percentages);
        vesting.pause();
        vm.stopPrank();

        vm.warp(start + 30 days);
        vm.expectRevert();
        vm.prank(beneficiary1);
        vesting.release(beneficiary1);
    }

    function test_ReleasableAmount_ReturnsZero_IfNoSchedule() public {
        assertEq(vesting.releasableAmount(beneficiary1), 0);
    }

    function test_ReleasableAmount_CalculatesCorrectly() public {
        uint64 start = uint64(block.timestamp);
        uint64 periodLength = 30 days;
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        vesting.createOrIncreaseSchedule(beneficiary1, 1_000_000 ether, start, periodLength, percentages);

        vm.warp(start + 30 days);
        // After 30 days, only period 0 is vested (25% total) - FIX CRITICAL #1
        assertEq(vesting.releasableAmount(beneficiary1), 250_000 ether);

        vm.warp(start + 60 days);
        // After 60 days, periods 0 and 1 are vested (50% total)
        assertEq(vesting.releasableAmount(beneficiary1), 500_000 ether);

        vm.warp(start + 120 days);
        assertEq(vesting.releasableAmount(beneficiary1), 1_000_000 ether);
    }

    function test_Schedules_ReturnsCorrectValues() public {
        uint64 start = uint64(block.timestamp);
        uint64 periodLength = 30 days;
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        vesting.createOrIncreaseSchedule(beneficiary1, 1_000_000 ether, start, periodLength, percentages);

        (uint128 total, uint128 released, uint64 actualStart, uint64 actualPeriodLength, uint16[] memory actualPercentages) = 
            vesting.schedules(beneficiary1);
        assertEq(total, 1_000_000 ether);
        assertEq(released, 0);
        assertEq(actualStart, start);
        assertEq(actualPeriodLength, periodLength);
        assertEq(actualPercentages.length, 4);
    }

    function test_Pause_Unpause_Success() public {
        vm.prank(admin);
        vesting.pause();
        assertTrue(vesting.paused());

        vm.prank(admin);
        vesting.unpause();
        assertFalse(vesting.paused());
    }

    function testFuzz_Allocate_ValidAmount(uint128 amount) public {
        amount = uint128(bound(amount, 1, 5_000_000 ether));
        vm.prank(admin);
        vesting.allocate(beneficiary1, amount);

        (uint128 total, , , , ) = vesting.schedules(beneficiary1);
        assertEq(total, amount);
    }

    function testFuzz_ReleasableAmount_OverTime(uint64 timestamp) public {
        uint64 start = uint64(block.timestamp);
        uint64 periodLength = 30 days;
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        vesting.createOrIncreaseSchedule(beneficiary1, 1_000_000 ether, start, periodLength, percentages);

        timestamp = uint64(bound(timestamp, start, start + 200 days));
        vm.warp(timestamp);

        uint256 releasable = vesting.releasableAmount(beneficiary1);
        assertLe(releasable, 1_000_000 ether);
    }
}
