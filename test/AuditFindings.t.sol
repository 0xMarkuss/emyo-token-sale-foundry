// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {TokenSale} from "src/sale/TokenSale.sol";
import {Treasury} from "src/treasury/Treasury.sol";
import {EmyoToken} from "src/token/EmyoToken.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {StakingRewards} from "src/staking/StakingRewards.sol";
import {Vesting} from "src/vesting/Vesting.sol";
import {VestingLibrary} from "src/vesting/VestingLibrary.sol";
import {Roles} from "src/access/Roles.sol";
import {Errors} from "src/libs/Errors.sol";

contract AuditFindingsTest is Test {
    MockERC20 paymentToken;
    EmyoToken saleToken;
    Treasury treasury;
    TokenSale sale;
    StakingRewards staking;
    Vesting vesting;

    address admin = address(0xA11CE);
    address user1 = address(0xB0B1);
    address user2 = address(0xB0B2);

    function setUp() public {
        paymentToken = new MockERC20("USDC", "USDC", 6);
        treasury = new Treasury(admin);
        saleToken = new EmyoToken("Emyo", "EMY", 10_000_000 ether, address(treasury));
        sale = new TokenSale(paymentToken, saleToken, address(treasury), admin);

        EmyoToken stakingToken = new EmyoToken("Stake", "STK", 10_000_000 ether, address(this));
        staking = new StakingRewards(stakingToken, stakingToken, admin);

        EmyoToken vestToken = new EmyoToken("Vest", "VST", 10_000_000 ether, address(this));
        vesting = new Vesting(vestToken, admin);

        paymentToken.mint(user1, 1_000_000e6);
        paymentToken.mint(user2, 1_000_000e6);
        vm.startPrank(user1);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(user2);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();

        vm.prank(admin);
        treasury.withdrawERC20(saleToken, address(sale), 5_000_000 ether);

        stakingToken.transfer(user1, 10_000 ether);
        stakingToken.transfer(address(staking), 100_000 ether);
        vm.prank(user1);
        stakingToken.approve(address(staking), type(uint256).max);

        vestToken.transfer(address(vesting), 5_000_000 ether);
    }

    function test_ICS_setTotalCap_ConsistentAbsoluteLimit() public {
        uint16[] memory pct = new uint16[](4);
        pct[0] = 2500; pct[1] = 2500; pct[2] = 2500; pct[3] = 2500;
        uint64 nowTs = uint64(block.timestamp);

        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, pct);

        vm.prank(admin);
        sale.setTotalCap(1_000_000 ether);

        vm.prank(user1);
        sale.buy(100e6, new bytes32[](0));

        assertEq(sale.totalCap(), 1_000_000 ether);
        assertEq(sale.totalSold(), 100_000 ether);
    }

    function test_PETR_addStage_RevertIf_vestStartNotAfterEnd() public {
        uint16[] memory pct = new uint16[](4);
        pct[0] = 2500; pct[1] = 2500; pct[2] = 2500; pct[3] = 2500;
        uint64 nowTs = uint64(block.timestamp);

        vm.expectRevert(Errors.VestStartMustBeAfterStageEnd.selector);
        vm.prank(admin);
        sale.addStage(100, nowTs + 10 days, nowTs + 7 days, 30 days, pct);
    }

    function test_IEV_addStage_RevertIf_EndInPast() public {
        uint16[] memory pct = new uint16[](4);
        pct[0] = 2500; pct[1] = 2500; pct[2] = 2500; pct[3] = 2500;

        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(Errors.InvalidStageTiming.selector);
        vm.prank(admin);
        sale.addStage(100, uint64(block.timestamp) - 1 days, uint64(block.timestamp) + 2 days, 30 days, pct);
    }

    function test_ILR_UserLimit_CumulativeCheck() public {
        uint16[] memory pct = new uint16[](4);
        pct[0] = 2500; pct[1] = 2500; pct[2] = 2500; pct[3] = 2500;
        uint64 nowTs = uint64(block.timestamp);

        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, pct);
        vm.prank(admin);
        sale.setUserLimits(user1, 50e6, 100e6);

        vm.prank(user1);
        sale.buy(60e6, new bytes32[](0));

        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(user1);
        sale.buy(50e6, new bytes32[](0));
    }

    function test_MC_validatePercentages_RevertIf_Empty() public {
        uint16[] memory empty = new uint16[](0);
        assertFalse(VestingLibrary.validatePercentages(empty));
    }

    function test_Constructor_RevertIf_PaymentEqualsSaleToken() public {
        vm.expectRevert(Errors.PaymentTokenCannotEqualSaleToken.selector);
        new TokenSale(saleToken, saleToken, address(treasury), admin);
    }

    function test_TSI_Treasury_OverAllocationReverts() public {
        uint16[] memory pct = new uint16[](4);
        pct[0] = 2500; pct[1] = 2500; pct[2] = 2500; pct[3] = 2500;
        uint64 nowTs = uint64(block.timestamp);

        vm.startPrank(admin);
        treasury.withdrawERC20(saleToken, user2, 2_000_000 ether);
        treasury.setVestingSchedule(saleToken, user1, 3_000_000 ether, nowTs, 30 days, pct);
        vm.expectRevert(Errors.InsufficientBalance.selector);
        treasury.setVestingSchedule(saleToken, user2, 3_000_000 ether, nowTs, 30 days, pct);
        vm.stopPrank();
    }

    function test_IIC_Treasury_IncreaseAccountsForReleased() public {
        uint16[] memory pct = new uint16[](4);
        pct[0] = 2500; pct[1] = 2500; pct[2] = 2500; pct[3] = 2500;
        uint64 nowTs = uint64(block.timestamp);

        vm.startPrank(admin);
        treasury.withdrawERC20(saleToken, address(treasury), 2_000_000 ether);
        treasury.setVestingSchedule(saleToken, user1, 1_000_000 ether, nowTs, 30 days, pct);
        vm.stopPrank();

        vm.warp(nowTs + 30 days);
        vm.prank(user1);
        treasury.release(saleToken);

        vm.prank(admin);
        treasury.increaseVestingSchedule(saleToken, user1, 500_000 ether);
    }

    function test_TRRP_topUpRewards_RestrictedToAdmin() public {
        vm.expectRevert();
        vm.prank(user1);
        staking.topUpRewards(10_000 ether);
    }

    function test_URA_RewardsCapAtPeriodFinish() public {
        vm.prank(admin);
        staking.setRewardRate(1 ether);

        vm.prank(user1);
        staking.stake(1_000 ether);

        uint256 periodEnd = staking.getPeriodEndTime();
        vm.warp(periodEnd + 1000);
        uint256 earned = staking.earned(user1);
        assertGt(earned, 0);
        vm.prank(user1);
        staking.getReward();
    }

    function test_IARR_getAvailableRewards_ExcludesStakedWhenSameToken() public {
        vm.prank(user1);
        staking.stake(1_000 ether);

        uint256 rawBalance = staking.stakingToken().balanceOf(address(staking));
        uint256 reported = staking.getAvailableRewards();
        assertEq(reported, rawBalance - 1_000 ether, "getAvailableRewards must exclude staked principal when same token");
    }

    function test_IRRV_setRewardRate_ValidatesMinDuration() public {
        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(admin);
        staking.setRewardRate(200_000 ether);
    }

    function test_Treasury_withdrawERC20_RevertIf_BelowObligations() public {
        uint16[] memory pct = new uint16[](4);
        pct[0] = 2500; pct[1] = 2500; pct[2] = 2500; pct[3] = 2500;

        vm.prank(admin);
        treasury.setVestingSchedule(saleToken, user1, 2_000_000 ether, uint64(block.timestamp), 30 days, pct);

        vm.prank(admin);
        vm.expectRevert();
        treasury.withdrawERC20(saleToken, user2, 9_000_000 ether);
    }

    function test_Vesting_TSI_OverAllocationReverts() public {
        uint16[] memory pct = new uint16[](4);
        pct[0] = 2500; pct[1] = 2500; pct[2] = 2500; pct[3] = 2500;

        vm.startPrank(admin);
        vesting.createOrIncreaseSchedule(user1, 4_000_000 ether, uint64(block.timestamp + 1), 30 days, pct);
        vm.expectRevert(Errors.InsufficientBalance.selector);
        vesting.createOrIncreaseSchedule(user2, 2_000_000 ether, uint64(block.timestamp + 1), 30 days, pct);
        vm.stopPrank();
    }

    function test_Vesting_StartMustNotBePast() public {
        uint16[] memory pct = new uint16[](4);
        pct[0] = 2500; pct[1] = 2500; pct[2] = 2500; pct[3] = 2500;

        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(admin);
        vesting.createOrIncreaseSchedule(user1, 1_000 ether, uint64(block.timestamp) - 1, 30 days, pct);
    }

    function test_Treasury_SetVestingSchedule_RevertIf_StartInPast() public {
        uint16[] memory pct = new uint16[](4);
        pct[0] = 2500; pct[1] = 2500; pct[2] = 2500; pct[3] = 2500;

        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(admin);
        treasury.setVestingSchedule(saleToken, user1, 1_000 ether, uint64(block.timestamp) - 1, 30 days, pct);
    }
}
