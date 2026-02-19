// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StakingRewards} from "src/staking/StakingRewards.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";

contract Handler is Test {
    StakingRewards public staking;
    MockERC20 public stakingToken;
    MockERC20 public rewardsToken;
    address[3] public users;
    address public admin;

    uint256 public constant MIN_TOPUP_AMOUNT = 30 days;
    uint256 public constant MAX_AMOUNT = 1_000_000e18;

    constructor(
        StakingRewards _staking,
        MockERC20 _stakingToken,
        MockERC20 _rewardsToken,
        address[3] memory _users,
        address _admin
    ) {
        staking = _staking;
        stakingToken = _stakingToken;
        rewardsToken = _rewardsToken;
        users = _users;
        admin = _admin;
    }

    function stake(uint256 seed) external {
        uint256 userIndex = seed % 3;
        address user = users[userIndex];
        uint256 amount = bound(seed >> 8, 1e18, 100_000e18);
        stakingToken.mint(user, amount);
        vm.prank(user);
        try staking.stake(amount) {} catch {}
    }

    function withdraw(uint256 seed) external {
        uint256 userIndex = seed % 3;
        address user = users[userIndex];
        uint256 bal = staking.balances(user);
        if (bal == 0) return;
        uint256 amount = bound(seed >> 8, 1, bal);
        vm.prank(user);
        try staking.withdraw(amount) {} catch {}
    }

    function getReward(uint256 seed) external {
        uint256 userIndex = seed % 3;
        address user = users[userIndex];
        vm.prank(user);
        try staking.getReward() {} catch {}
    }

    function exit(uint256 seed) external {
        uint256 userIndex = seed % 3;
        address user = users[userIndex];
        vm.prank(user);
        try staking.exit() {} catch {}
    }

    function topUpRewards(uint256 seed) external {
        uint256 amount = bound(seed, MIN_TOPUP_AMOUNT, MAX_AMOUNT);
        rewardsToken.mint(admin, amount);
        vm.prank(admin);
        staking.topUpRewards(amount);
    }

    function topUpRewardsWithPeriod(uint256 seed) external {
        uint256 period = bound(seed & 0xFFFF, 1 days, 365 days);
        uint256 amount = bound(seed >> 16, period, MAX_AMOUNT);
        rewardsToken.mint(admin, amount);
        vm.prank(admin);
        staking.topUpRewardsWithPeriod(amount, period);
    }

}
