// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Treasury} from "src/treasury/Treasury.sol";
import {EmyoToken} from "src/token/EmyoToken.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Roles} from "src/access/Roles.sol";
import {Errors} from "src/libs/Errors.sol";

contract TreasuryTest is Test {
    Treasury treasury;
    EmyoToken emyo;
    MockERC20 usdc;

    address admin = address(0xA11CE);
    address beneficiary1 = address(0xB0B1);
    address beneficiary2 = address(0xB0B2);
    address unauthorized = address(0xBAD);

    function setUp() public {
        treasury = new Treasury(admin);
        emyo = new EmyoToken("Emyo", "EMY", 10_000_000 ether, address(treasury));
        usdc = new MockERC20("USDC", "USDC", 6);
        usdc.mint(address(treasury), 1_000_000e6);
        vm.deal(address(treasury), 100 ether);
    }

    function test_Constructor_SetsCorrectValues() public {
        assertTrue(treasury.hasRole(0x00, admin));
        assertTrue(treasury.hasRole(Roles.PAUSER_ROLE, admin));
        assertTrue(treasury.hasRole(Roles.TREASURY_ROLE, admin));
    }

    function test_Constructor_RevertIf_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new Treasury(address(0));
    }

    function test_ReceiveEther_Success() public {
        uint256 amount = 10 ether;
        (bool success, ) = address(treasury).call{value: amount}("");
        assertTrue(success);
        assertEq(address(treasury).balance, 100 ether + amount);
    }

    function test_WithdrawEther_Success() public {
        uint256 amount = 10 ether;
        vm.prank(admin);
        treasury.withdrawEther(payable(beneficiary1), amount);

        assertEq(beneficiary1.balance, amount);
        assertEq(address(treasury).balance, 100 ether - amount);
    }

    function test_WithdrawEther_RevertIf_Unauthorized() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        treasury.withdrawEther(payable(beneficiary1), 1 ether);
    }

    function test_WithdrawEther_RevertIf_Paused() public {
        vm.prank(admin);
        treasury.pause();

        vm.expectRevert();
        vm.prank(admin);
        treasury.withdrawEther(payable(beneficiary1), 1 ether);
    }

    function test_WithdrawEther_RevertIf_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        treasury.withdrawEther(payable(address(0)), 1 ether);
    }

    function test_WithdrawEther_RevertIf_ZeroAmount() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(admin);
        treasury.withdrawEther(payable(beneficiary1), 0);
    }

    function test_WithdrawERC20_Success() public {
        uint256 amount = 100e6;
        vm.prank(admin);
        treasury.withdrawERC20(usdc, beneficiary1, amount);

        assertEq(usdc.balanceOf(beneficiary1), amount);
        assertEq(usdc.balanceOf(address(treasury)), 1_000_000e6 - amount);
    }

    function test_WithdrawERC20_RevertIf_Unauthorized() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        treasury.withdrawERC20(usdc, beneficiary1, 100e6);
    }

    function test_WithdrawERC20_RevertIf_Paused() public {
        vm.prank(admin);
        treasury.pause();

        vm.expectRevert();
        vm.prank(admin);
        treasury.withdrawERC20(usdc, beneficiary1, 100e6);
    }

    function test_WithdrawERC20_RevertIf_ZeroTokenAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        treasury.withdrawERC20(IERC20(address(0)), beneficiary1, 100e6);
    }

    function test_WithdrawERC20_RevertIf_ZeroRecipient() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        treasury.withdrawERC20(usdc, address(0), 100e6);
    }

    function test_WithdrawERC20_RevertIf_ZeroAmount() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(admin);
        treasury.withdrawERC20(usdc, beneficiary1, 0);
    }

    function test_SetVestingSchedule_Success() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        treasury.setVestingSchedule(emyo, beneficiary1, 1_000_000 ether, nowTs, 30 days, percentages);

        (uint128 total, uint128 released, uint64 start, uint64 periodLength, uint16[] memory sched) = 
            treasury.getVestingSchedule(emyo, beneficiary1);
        assertEq(total, 1_000_000 ether);
        assertEq(released, 0);
        assertEq(start, nowTs);
        assertEq(periodLength, 30 days);
        assertEq(sched.length, 4);
    }

    function test_SetVestingSchedule_RevertIf_Unauthorized() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.expectRevert();
        vm.prank(unauthorized);
        treasury.setVestingSchedule(emyo, beneficiary1, 1_000_000 ether, nowTs, 30 days, percentages);
    }

    function test_SetVestingSchedule_RevertIf_Paused() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        treasury.pause();

        vm.expectRevert();
        vm.prank(admin);
        treasury.setVestingSchedule(emyo, beneficiary1, 1_000_000 ether, nowTs, 30 days, percentages);
    }

    function test_SetVestingSchedule_RevertIf_ZeroToken() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        treasury.setVestingSchedule(IERC20(address(0)), beneficiary1, 1_000_000 ether, nowTs, 30 days, percentages);
    }

    function test_SetVestingSchedule_RevertIf_ZeroBeneficiary() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        treasury.setVestingSchedule(emyo, address(0), 1_000_000 ether, nowTs, 30 days, percentages);
    }

    function test_SetVestingSchedule_RevertIf_ZeroAmount() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(admin);
        treasury.setVestingSchedule(emyo, beneficiary1, 0, nowTs, 30 days, percentages);
    }

    function test_SetVestingSchedule_RevertIf_ZeroPeriodLength() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.expectRevert(Errors.InvalidPeriodLength.selector);
        vm.prank(admin);
        treasury.setVestingSchedule(emyo, beneficiary1, 1_000_000 ether, nowTs, 0, percentages);
    }

    function test_SetVestingSchedule_RevertIf_InvalidPercentages() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2000;
        percentages[1] = 2000;
        percentages[2] = 2000;
        percentages[3] = 2000;

        vm.expectRevert(Errors.InvalidVestingSchedule.selector);
        vm.prank(admin);
        treasury.setVestingSchedule(emyo, beneficiary1, 1_000_000 ether, nowTs, 30 days, percentages);
    }

    function test_SetVestingSchedule_RevertIf_Overwrite() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        treasury.setVestingSchedule(emyo, beneficiary1, 1_000_000 ether, nowTs, 30 days, percentages);
        vm.expectRevert(Errors.ScheduleAlreadyExists.selector);
        treasury.setVestingSchedule(emyo, beneficiary1, 500_000 ether, nowTs, 30 days, percentages);
        vm.stopPrank();
    }

    function test_IncreaseVestingSchedule_Success() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        treasury.setVestingSchedule(emyo, beneficiary1, 1_000_000 ether, nowTs, 30 days, percentages);
        treasury.increaseVestingSchedule(emyo, beneficiary1, 500_000 ether);
        vm.stopPrank();

        (uint128 total, , , , ) = treasury.getVestingSchedule(emyo, beneficiary1);
        assertEq(total, 1_500_000 ether);
    }

    function test_IncreaseVestingSchedule_RevertIf_NoSchedule() public {
        vm.expectRevert(Errors.ScheduleNotFound.selector);
        vm.prank(admin);
        treasury.increaseVestingSchedule(emyo, beneficiary1, 500_000 ether);
    }

    function test_IncreaseVestingSchedule_RevertIf_ZeroToken() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        treasury.increaseVestingSchedule(IERC20(address(0)), beneficiary1, 500_000 ether);
    }

    function test_IncreaseVestingSchedule_RevertIf_ZeroBeneficiary() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        treasury.increaseVestingSchedule(emyo, address(0), 500_000 ether);
    }

    function test_IncreaseVestingSchedule_RevertIf_ZeroAmount() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        treasury.setVestingSchedule(emyo, beneficiary1, 1_000_000 ether, nowTs, 30 days, percentages);
        vm.expectRevert(Errors.ZeroAmount.selector);
        treasury.increaseVestingSchedule(emyo, beneficiary1, 0);
        vm.stopPrank();
    }

    function test_Release_Success() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        treasury.setVestingSchedule(emyo, beneficiary1, 1_000_000 ether, nowTs, 30 days, percentages);
        treasury.withdrawERC20(emyo, address(treasury), 1_000_000 ether);
        vm.stopPrank();

        vm.warp(nowTs + 30 days);
        uint256 releasable = treasury.releasableAmount(emyo, beneficiary1);
        // After 30 days, only period 0 is vested (25% total) - FIX CRITICAL #1
        assertEq(releasable, 250_000 ether);

        vm.prank(beneficiary1);
        treasury.release(emyo);
        assertEq(emyo.balanceOf(beneficiary1), 250_000 ether);
    }

    function test_Release_ReturnsZero_IfNothingReleasable() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        treasury.setVestingSchedule(emyo, beneficiary1, 1_000_000 ether, nowTs, 30 days, percentages);
        treasury.withdrawERC20(emyo, address(treasury), 1_000_000 ether);
        vm.stopPrank();

        // Nothing should be releasable immediately
        vm.prank(beneficiary1);
        uint256 released = treasury.release(emyo);
        assertEq(released, 0, "Should not vest immediately");
        
        // After 30 days, period 0 should vest
        vm.warp(nowTs + 30 days);
        vm.prank(beneficiary1);
        released = treasury.release(emyo);
        assertEq(released, 250_000 ether, "Should vest first period after 30 days");
    }

    function test_Release_RevertIf_ZeroToken() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(beneficiary1);
        treasury.release(IERC20(address(0)));
    }

    function test_Release_RevertIf_Paused() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        treasury.setVestingSchedule(emyo, beneficiary1, 1_000_000 ether, nowTs, 30 days, percentages);
        treasury.pause();
        vm.stopPrank();

        vm.warp(nowTs + 30 days);
        vm.expectRevert();
        vm.prank(beneficiary1);
        treasury.release(emyo);
    }

    function test_ReleaseFor_Success() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        treasury.setVestingSchedule(emyo, beneficiary1, 1_000_000 ether, nowTs, 30 days, percentages);
        treasury.withdrawERC20(emyo, address(treasury), 1_000_000 ether);
        vm.stopPrank();

        vm.warp(nowTs + 30 days);
        // After 30 days, only period 0 is vested (25% total)
        vm.prank(admin);
        treasury.releaseFor(emyo, beneficiary1);
        assertEq(emyo.balanceOf(beneficiary1), 250_000 ether);
    }

    function test_ReleaseFor_RevertIf_Unauthorized() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        treasury.setVestingSchedule(emyo, beneficiary1, 1_000_000 ether, nowTs, 30 days, percentages);
        vm.stopPrank();

        vm.warp(nowTs + 30 days);
        vm.expectRevert();
        vm.prank(unauthorized);
        treasury.releaseFor(emyo, beneficiary1);
    }

    function test_ReleaseFor_RevertIf_ZeroToken() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        treasury.releaseFor(IERC20(address(0)), beneficiary1);
    }

    function test_ReleaseFor_RevertIf_ZeroBeneficiary() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        treasury.releaseFor(emyo, address(0));
    }

    function test_ReleasableAmount_ReturnsZero_IfNoSchedule() public {
        assertEq(treasury.releasableAmount(emyo, beneficiary1), 0);
    }

    function test_ReleasableAmount_CalculatesCorrectly() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        treasury.setVestingSchedule(emyo, beneficiary1, 1_000_000 ether, nowTs, 30 days, percentages);

        vm.warp(nowTs + 30 days);
        // After 30 days, only period 0 is vested (25% total)
        assertEq(treasury.releasableAmount(emyo, beneficiary1), 250_000 ether);

        vm.warp(nowTs + 60 days);
        // After 60 days, periods 0 and 1 are vested (50% total)
        assertEq(treasury.releasableAmount(emyo, beneficiary1), 500_000 ether);
    }

    function test_GetVestingSchedule_ReturnsCorrectValues() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        treasury.setVestingSchedule(emyo, beneficiary1, 1_000_000 ether, nowTs, 30 days, percentages);

        (uint128 total, uint128 released, uint64 start, uint64 periodLength, uint16[] memory sched) = 
            treasury.getVestingSchedule(emyo, beneficiary1);
        assertEq(total, 1_000_000 ether);
        assertEq(released, 0);
        assertEq(start, nowTs);
        assertEq(periodLength, 30 days);
        assertEq(sched.length, 4);
    }

    function test_Pause_Unpause_Success() public {
        vm.prank(admin);
        treasury.pause();
        assertTrue(treasury.paused());

        vm.prank(admin);
        treasury.unpause();
        assertFalse(treasury.paused());
    }

    function testFuzz_WithdrawERC20_WithinBalance(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e6);
        vm.prank(admin);
        treasury.withdrawERC20(usdc, beneficiary1, amount);
        assertEq(usdc.balanceOf(beneficiary1), amount);
    }

    function testFuzz_SetVestingSchedule_ValidPercentages(uint256 total) public {
        total = bound(total, 1, 10_000_000 ether);
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        treasury.setVestingSchedule(emyo, beneficiary1, uint128(total), nowTs, 30 days, percentages);

        (uint128 actualTotal, , , , ) = treasury.getVestingSchedule(emyo, beneficiary1);
        assertEq(actualTotal, total);
    }

    /// @notice HIGH #6: Test that setVestingSchedule requires sufficient balance
    function test_SetVestingSchedule_RevertIf_InsufficientBalance() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        // Treasury only has 10M tokens (from constructor)
        // Try to set schedule for more than available
        vm.expectRevert(Errors.InsufficientBalance.selector);
        vm.prank(admin);
        treasury.setVestingSchedule(emyo, beneficiary1, 20_000_000 ether, nowTs, 30 days, percentages);
    }

    /// @notice HIGH #6: Test that increaseVestingSchedule requires sufficient balance
    function test_IncreaseVestingSchedule_RevertIf_InsufficientBalance() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        // Set initial schedule for 5M tokens
        treasury.setVestingSchedule(emyo, beneficiary1, 5_000_000 ether, nowTs, 30 days, percentages);
        
        // Try to increase by more than available (only 5M left)
        vm.expectRevert(Errors.InsufficientBalance.selector);
        treasury.increaseVestingSchedule(emyo, beneficiary1, 10_000_000 ether);
        vm.stopPrank();
    }

    /// @notice HIGH #6: Test that setVestingSchedule succeeds with sufficient balance
    function test_SetVestingSchedule_Success_WithSufficientBalance() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        // Treasury has 10M tokens, set schedule for 5M (should succeed)
        vm.prank(admin);
        treasury.setVestingSchedule(emyo, beneficiary1, 5_000_000 ether, nowTs, 30 days, percentages);

        (uint128 total, , , , ) = treasury.getVestingSchedule(emyo, beneficiary1);
        assertEq(total, 5_000_000 ether);
    }
}
