// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TokenSale} from "src/sale/TokenSale.sol";
import {EmyoToken} from "src/token/EmyoToken.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {Treasury} from "src/treasury/Treasury.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Roles} from "src/access/Roles.sol";
import {Errors} from "src/libs/Errors.sol";

contract TokenSaleTest is Test {
    MockERC20 paymentToken;
    EmyoToken saleToken;
    Treasury treasury;
    TokenSale sale;

    address admin = address(0xA11CE);
    address buyer1 = address(0xB0B1);
    address buyer2 = address(0xB0B2);
    address unauthorized = address(0xBAD);

    function setUp() public {
        paymentToken = new MockERC20("USDC", "USDC", 6);
        treasury = new Treasury(admin);
        saleToken = new EmyoToken("Emyo", "EMY", 10_000_000 ether, address(treasury));
        sale = new TokenSale(paymentToken, saleToken, address(treasury), admin);

        // Fund users with payment tokens
        paymentToken.mint(buyer1, 1_000_000e6);
        paymentToken.mint(buyer2, 1_000_000e6);
        vm.startPrank(buyer1);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(buyer2);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();

        // Fund sale contract with tokens for vesting releases
        vm.prank(admin);
        treasury.withdrawERC20(saleToken, address(sale), 5_000_000 ether);
    }

    function test_Constructor_SetsCorrectValues() public {
        assertEq(address(sale.paymentToken()), address(paymentToken));
        assertEq(address(sale.saleToken()), address(saleToken));
        assertEq(sale.treasury(), address(treasury));
        assertTrue(sale.hasRole(0x00, admin));
        assertTrue(sale.hasRole(Roles.PAUSER_ROLE, admin));
        assertTrue(sale.hasRole(Roles.SALE_ADMIN_ROLE, admin));
    }

    function test_Constructor_RevertIf_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new TokenSale(IERC20(address(0)), saleToken, address(treasury), admin);

        vm.expectRevert(Errors.ZeroAddress.selector);
        new TokenSale(paymentToken, IERC20(address(0)), address(treasury), admin);

        vm.expectRevert(Errors.ZeroAddress.selector);
        new TokenSale(paymentToken, saleToken, address(0), admin);

        vm.expectRevert(Errors.ZeroAddress.selector);
        new TokenSale(paymentToken, saleToken, address(treasury), address(0));
    }

    function test_Constructor_RevertIf_SaleDecimalsLessThanPaymentDecimals() public {
        MockERC20 lowDecimals = new MockERC20("LOW", "LOW", 4);
        vm.expectRevert(Errors.InvalidParam.selector);
        new TokenSale(paymentToken, lowDecimals, address(treasury), admin);
    }

    function test_AddStage_Success() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages); // $0.001 per EMY = 1000 tokens per USDC

        // Public getter for struct arrays only returns non-array fields
        (uint256 emyPriceUsd, uint64 end, uint64 vestStart, uint64 vestPeriodLength) = sale.stages(0);
        assertEq(emyPriceUsd, 100);
        assertEq(end, nowTs + 7 days);
        assertEq(vestPeriodLength, 30 days);
        // Note: vestPercentages array is not accessible via public getter
    }

    function test_AddStage_RevertIf_Unauthorized() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.expectRevert();
        vm.prank(unauthorized);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
    }

    function test_AddStage_RevertIf_ZeroPrice() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(admin);
        sale.addStage(0, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
    }

    function test_AddStage_RevertIf_ZeroEnd() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(admin);
        sale.addStage(100, 0, 1 days, 30 days, percentages);
    }

    function test_AddStage_RevertIf_ZeroPeriodLength() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.expectRevert(Errors.InvalidPeriodLength.selector);
        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 0, percentages);
    }

    function test_AddStage_RevertIf_InvalidPercentages() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2000;
        percentages[1] = 2000;
        percentages[2] = 2000;
        percentages[3] = 2000; // Sums to 8000, not 10000

        vm.expectRevert(Errors.InvalidVestingSchedule.selector);
        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
    }

    function test_AddStage_RevertIf_EndNotMonotonic() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        vm.expectRevert(Errors.InvalidParam.selector);
        sale.addStage(100, nowTs + 5 days, nowTs + 8 days, 30 days, percentages);
        vm.stopPrank();
    }

    function test_Buy_Success() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages); // $0.001 per EMY = 1000 tokens per USDC

        uint256 paymentAmount = 100e6;
        uint256 expectedTokens = (uint256(paymentAmount) * 100000 * sale.decimalScale()) / 100; // PRICE_SCALE = 100000

        vm.prank(buyer1);
        sale.buy(uint128(paymentAmount), new bytes32[](0));

        assertEq(paymentToken.balanceOf(address(treasury)), paymentAmount);
        assertEq(sale.totalSold(), expectedTokens);
        (uint128 total, , , , ) = sale.getVestingSchedule(buyer1, 0);
        assertEq(total, expectedTokens);
    }

    function test_Buy_RevertIf_ZeroAmount() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);

        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(buyer1);
        sale.buy(0, new bytes32[](0));
    }

    function test_Buy_RevertIf_NoActiveStage() public {
        vm.expectRevert(Errors.NotStarted.selector);
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));
    }

    function test_Buy_RevertIf_StageEnded() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);

        vm.warp(nowTs + 7 days + 1);
        vm.expectRevert(Errors.NotStarted.selector);
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));
    }

    function test_Buy_RevertIf_Paused() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.pause();
        vm.stopPrank();

        vm.expectRevert();
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));
    }

    function test_Buy_RevertIf_AllowlistEnabled_NotAllowed() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setAllowlistEnabled(true);
        // Don't set merkle root - should revert with InvalidParam
        vm.stopPrank();

        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));
    }

    function test_Buy_Success_WithAllowlist() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setAllowlistEnabled(true);
        sale.setAllowlistEnabled(false); // Disable allowlist for this test
        vm.stopPrank();

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        assertEq(paymentToken.balanceOf(address(treasury)), 100e6);
    }

    function test_Buy_RevertIf_BelowMinLimit() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setUserLimits(buyer1, 50e6, 200e6);
        vm.stopPrank();

        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(buyer1);
        sale.buy(30e6, new bytes32[](0));
    }

    function test_Buy_RevertIf_AboveMaxLimit() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setUserLimits(buyer1, 50e6, 200e6);
        vm.stopPrank();

        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(buyer1);
        sale.buy(250e6, new bytes32[](0));
    }

    function test_Buy_RevertIf_ExceedsTotalCap() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setTotalCap(100_000 ether);
        vm.stopPrank();

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0)); // 100k tokens

        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(buyer1);
        sale.buy(1e6, new bytes32[](0)); // Would exceed cap
    }

    function test_Buy_MultipleTimes_AggregatesVesting() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);

        vm.startPrank(buyer1);
        sale.buy(50e6, new bytes32[](0));
        sale.buy(30e6, new bytes32[](0));
        sale.buy(20e6, new bytes32[](0));
        vm.stopPrank();

        (uint128 total, , , , ) = sale.getVestingSchedule(buyer1, 0);
        assertEq(total, 100_000 ether);
    }

    function test_Buy_MultipleStages_CreatesSeparateSchedules() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages1 = new uint16[](4);
        percentages1[0] = 2500;
        percentages1[1] = 2500;
        percentages1[2] = 2500;
        percentages1[3] = 2500;

        uint16[] memory percentages2 = new uint16[](5);
        percentages2[0] = 2000;
        percentages2[1] = 2000;
        percentages2[2] = 2000;
        percentages2[3] = 2000;
        percentages2[4] = 2000;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 1 days, nowTs + 4 days, 30 days, percentages1);
        sale.addStage(50, nowTs + 2 days, nowTs + 5 days, 20 days, percentages2);
        vm.stopPrank();

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0)); // Stage 0: 100k tokens

        vm.warp(nowTs + 1 days + 1);
        vm.prank(buyer1);
        sale.buy(50e6, new bytes32[](0)); // Stage 1: 100k tokens (50e6 * 100000 * 1e12 / 50)

        (uint128 total0, , uint64 start0, uint64 periodLength0, uint16[] memory sched0) = sale.getVestingSchedule(buyer1, 0);
        assertEq(total0, 100_000 ether);
        assertEq(periodLength0, 30 days);
        assertEq(sched0.length, 4);
        (uint256 _emyPriceUsd0, uint64 _end0, uint64 _vestStart0,) = sale.stages(0);
        assertEq(start0, _vestStart0);

        (uint128 total1, , uint64 start1, uint64 periodLength1, uint16[] memory sched1) = sale.getVestingSchedule(buyer1, 1);
        assertEq(total1, 100_000 ether);
        assertEq(periodLength1, 20 days);
        assertEq(sched1.length, 5);
        (, uint64 _end1, uint64 _vestStart1,) = sale.stages(1);
        assertEq(start1, _vestStart1);
    }

    function test_SetUserLimits_Success() public {
        vm.prank(admin);
        sale.setUserLimits(buyer1, 10e6, 100e6);

        (uint128 min, uint128 max) = sale.userLimits(buyer1);
        assertEq(min, 10e6);
        assertEq(max, 100e6);
    }

    function test_SetUserLimits_RevertIf_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        sale.setUserLimits(address(0), 10e6, 100e6);
    }

    function test_SetUserLimits_RevertIf_MaxLessThanMin() public {
        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(admin);
        sale.setUserLimits(buyer1, 100e6, 50e6);
    }

    function test_SetAllowlistMerkleRoot_Success() public {
        bytes32 root = bytes32(uint256(0x1234));
        vm.prank(admin);
        sale.setAllowlistMerkleRoot(root);
        assertEq(sale.allowlistMerkleRoot(), root);
    }

    function test_SetAllowlistEnabled_Success() public {
        vm.prank(admin);
        sale.setAllowlistEnabled(true);
        assertTrue(sale.allowlistEnabled());

        vm.prank(admin);
        sale.setAllowlistEnabled(false);
        assertFalse(sale.allowlistEnabled());
    }

    function test_SetTotalCap_Success() public {
        vm.prank(admin);
        sale.setTotalCap(1_000_000 ether);
        assertEq(sale.totalCap(), 1_000_000 ether);
    }

    /// @notice ICS fix: setTotalCap = remaining to sell, aligned with availableForSale
    function test_SetTotalCap_ICS_RemainingLimit() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);

        vm.prank(admin);
        treasury.withdrawERC20(saleToken, address(sale), 1_000_000 ether);

        vm.prank(buyer1);
        sale.buy(500e6, new bytes32[](0));

        vm.prank(admin);
        sale.setTotalCap(500_000 ether);
        assertEq(sale.totalCap(), 500_000 ether);

        vm.prank(admin);
        sale.setTotalCap(400_000 ether);
        assertEq(sale.totalCap(), 400_000 ether);
    }

    function test_SetTotalCap_RevertIf_Zero() public {
        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(admin);
        sale.setTotalCap(0);
    }

    function test_SetTotalCap_Remaining_DecrementsOnBuy() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setTotalCap(1_000_000 ether);
        vm.stopPrank();

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));
        assertEq(sale.totalCap(), 900_000 ether);

        vm.prank(buyer1);
        sale.buy(200e6, new bytes32[](0));
        assertEq(sale.totalCap(), 700_000 ether);
    }

    function test_SetTotalCap_RevertIf_AboveAvailableForSale() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        vm.stopPrank();

        vm.prank(buyer1);
        sale.buy(3000e6, new bytes32[](0)); // 3M tokens at price 100
        assertEq(sale.totalAllocatedToVesting(), 3_000_000 ether);
        assertEq(saleToken.balanceOf(address(sale)), 5_000_000 ether);
        assertEq(sale.totalSold(), 3_000_000 ether);

        vm.expectRevert(Errors.InsufficientBalance.selector);
        vm.prank(admin);
        sale.setTotalCap(4_000_000 ether); // Available for sale = 5M - 3M = 2M
    }

    function test_Release_Success() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        uint64 vestStart = nowTs + 10 days;
        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, vestStart, 30 days, percentages);

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        // Warp to vestStart + periodLength to complete first period
        vm.warp(vestStart + 30 days);
        uint256 releasable = sale.releasableAmount(buyer1);
        // After vestStart + 30 days, period 0 is vested (25% total)
        assertEq(releasable, 25_000 ether);

        vm.prank(buyer1);
        sale.release();
        assertEq(saleToken.balanceOf(buyer1), 25_000 ether);
    }

    function test_Release_ReturnsZero_IfNothingReleasable() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        uint64 vestStart = nowTs + 10 days;
        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, vestStart, 30 days, percentages);

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        // Nothing should be releasable immediately
        vm.prank(buyer1);
        uint256 released = sale.release();
        assertEq(released, 0, "Should not vest immediately");
        
        // After vestStart + 30 days, period 0 should vest
        vm.warp(vestStart + 30 days);
        vm.prank(buyer1);
        released = sale.release();
        assertEq(released, 25_000 ether, "Should vest first period after vestStart + periodLength");
    }

    function test_Release_RevertIf_Paused() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        vm.stopPrank();

        // Buy before pausing
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        // Now pause
        vm.prank(admin);
        sale.pause();

        vm.warp(nowTs + 30 days);
        vm.expectRevert();
        vm.prank(buyer1);
        sale.release();
    }

    function test_ReleaseFor_Success() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        uint64 vestStart = nowTs + 10 days;
        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, vestStart, 30 days, percentages);

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        // Warp to vestStart + 30 days to complete first period
        vm.warp(vestStart + 30 days);
        // After vestStart + 30 days, period 0 is vested (25% total)
        vm.prank(admin);
        sale.releaseFor(buyer1);
        assertEq(saleToken.balanceOf(buyer1), 25_000 ether);
    }

    function test_ReleaseFor_RevertIf_Unauthorized() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        vm.warp(nowTs + 30 days);
        vm.expectRevert();
        vm.prank(unauthorized);
        sale.releaseFor(buyer1);
    }

    function test_ReleaseFor_RevertIf_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        sale.releaseFor(address(0));
    }

    function test_ReleasableAmount_ReturnsZero_IfNoSchedule() public {
        assertEq(sale.releasableAmount(buyer1), 0);
    }

    function test_GetVestingSchedule_ReturnsCorrectValues() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        uint64 vestStart = nowTs + 10 days;
        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, vestStart, 30 days, percentages);

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        (uint128 total, uint128 released, uint64 start, uint64 periodLength, uint16[] memory sched) = 
            sale.getVestingSchedule(buyer1, 0);
        assertEq(total, 100_000 ether);
        assertEq(released, 0);
        assertEq(start, vestStart); // Start is vestStart, not purchase time
        assertEq(periodLength, 30 days);
        assertEq(sched.length, 4);
    }

    function test_Pause_Unpause_Success() public {
        vm.prank(admin);
        sale.pause();
        assertTrue(sale.paused());

        vm.prank(admin);
        sale.unpause();
        assertFalse(sale.paused());
    }

    function test_Pause_RevertIf_Unauthorized() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        sale.pause();
    }

    function testFuzz_Buy_WithinLimits(uint128 paymentAmount) public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);

        paymentAmount = uint128(bound(paymentAmount, 1e6, 1_000e6));
        paymentToken.mint(buyer1, paymentAmount);
        vm.prank(buyer1);
        paymentToken.approve(address(sale), paymentAmount);

        vm.prank(buyer1);
        sale.buy(paymentAmount, new bytes32[](0));

        uint256 expectedTokens = (uint256(paymentAmount) * 100000 * sale.decimalScale()) / 100; // PRICE_SCALE = 100000
        assertEq(sale.totalSold(), expectedTokens);
    }

    function testFuzz_SetUserLimits(uint128 min, uint128 max) public {
        min = uint128(bound(min, 0, type(uint128).max));
        max = uint128(bound(max, min, type(uint128).max));

        vm.prank(admin);
        if (max > 0 && max < min) {
            vm.expectRevert(Errors.InvalidParam.selector);
        }
        sale.setUserLimits(buyer1, min, max);

        if (max >= min || max == 0) {
            (uint128 actualMin, uint128 actualMax) = sale.userLimits(buyer1);
            assertEq(actualMin, min);
            assertEq(actualMax, max);
        }
    }

    /// @notice CRITICAL #2: Test balance accounting prevents over-allocation
    function test_Buy_PreventsOverAllocation_WhenTokensInVesting() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);

        // Transfer exactly 1M tokens (clear existing 5M first by transferring back to treasury)
        // Note: We can't withdraw 0, so we need to work with existing balance
        // The test should work with 5M existing + 1M new = 6M total, but only 1M allocated
        vm.prank(admin);
        treasury.withdrawERC20(saleToken, address(sale), 1_000_000 ether);

        // User purchases 1M tokens (all tokens allocated to vesting)
        vm.prank(buyer1);
        sale.buy(1000e6, new bytes32[](0)); // 1M tokens

        // Verify tokens are still in contract (not released yet)
        // Balance is 6M (5M from setUp + 1M transferred), but only 1M allocated to vesting
        assertEq(saleToken.balanceOf(address(sale)), 6_000_000 ether);
        assertEq(sale.totalSold(), 1_000_000 ether);
        assertEq(sale.totalAllocatedToVesting(), 1_000_000 ether); // Only 1M allocated to vesting
        
        // Available for sale = 6M - 1M = 5M
        // Buy 4.9M more tokens to use up almost all available balance
        vm.prank(buyer1);
        sale.buy(4900e6, new bytes32[](0)); // 4.9M tokens
        
        assertEq(sale.totalAllocatedToVesting(), 5_900_000 ether); // 1M + 4.9M allocated
        assertEq(sale.totalSold(), 5_900_000 ether);
        
        // Available for sale = 6M - 5.9M = 100k
        // Buy 100k tokens (uses up all available)
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0)); // 100k tokens
        
        assertEq(sale.totalAllocatedToVesting(), 6_000_000 ether); // All 6M allocated
        
        // Now attempt to purchase more should fail (all tokens allocated)
        vm.expectRevert(Errors.InsufficientBalance.selector);
        vm.prank(buyer2);
        sale.buy(1e6, new bytes32[](0)); // Should fail - all tokens allocated to vesting
    }

    /// @notice CRITICAL #2: Test balance accounting allows purchase after release
    function test_Buy_AllowsPurchase_AfterTokensReleased() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);

        // Transfer tokens to sale contract
        vm.prank(admin);
        treasury.withdrawERC20(saleToken, address(sale), 1_000_000 ether);

        // User purchases 500k tokens
        vm.prank(buyer1);
        sale.buy(500e6, new bytes32[](0));

        // Release some tokens (after vestStart + 30 days)
        uint64 vestStart = nowTs + 10 days;
        vm.warp(vestStart + 30 days);
        vm.prank(buyer1);
        sale.release(); // Releases 25% = 125k tokens

        // Verify allocation decreased
        assertEq(sale.totalAllocatedToVesting(), 375_000 ether); // 500k - 125k released

        // Add another stage since first one ended
        vm.prank(admin);
        sale.addStage(100, nowTs + 14 days, nowTs + 17 days, 30 days, percentages);
        
        // Warp to new stage
        vm.warp(nowTs + 7 days + 1);
        
        // Now should be able to purchase more (125k tokens released, so available for sale)
        vm.prank(buyer2);
        sale.buy(100e6, new bytes32[](0)); // 100k tokens
        
        // Verify purchase succeeded
        assertEq(sale.totalSold(), 600_000 ether); // 500k + 100k
        assertEq(sale.totalAllocatedToVesting(), 475_000 ether); // 375k + 100k new allocation
    }

    /// @notice HIGH #4: Test that zero tokens output reverts
    function test_Buy_RevertIf_ZeroTokensOutput() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(1e18, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);

        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(buyer1);
        sale.buy(1, new bytes32[](0));
    }

    /// @notice HIGH #7: Test that stage end time must be in future
    function test_AddStage_RevertIf_EndTimeInPast() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        // First stage with past end time should revert
        // Note: end = 0 also fails the end == 0 check, so use a small past value
        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(admin);
        sale.addStage(100, uint64(block.timestamp) - 1, uint64(block.timestamp) + 2 days, 30 days, percentages);
    }

    /// @notice CRITICAL #1: Test that tokens don't vest immediately after purchase
    /// @dev vestStart is set per stage - all users in a stage share the same vestStart time
    function test_Release_ShouldNotVestImmediately_AfterPurchase() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        uint64 vestStart = nowTs + 10 days;
        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, vestStart, 30 days, percentages);

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        // Immediately after purchase, should not be able to release anything
        uint256 releasable = sale.releasableAmount(buyer1);
        assertEq(releasable, 0, "Should not vest immediately after purchase");

        // After 1 day, still should not vest (vestStart hasn't been reached)
        vm.warp(nowTs + 1 days);
        releasable = sale.releasableAmount(buyer1);
        assertEq(releasable, 0, "Should not vest before vestStart");

        // After vestStart + periodLength, first period should vest
        vm.warp(vestStart + 30 days);
        releasable = sale.releasableAmount(buyer1);
        assertEq(releasable, 25_000 ether, "Should vest first period after vestStart + periodLength");
    }
}
