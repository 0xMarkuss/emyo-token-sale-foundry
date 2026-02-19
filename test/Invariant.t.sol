// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {StakingRewards} from "src/staking/StakingRewards.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantTest is StdInvariant, Test {
    StakingRewards public staking;
    MockERC20 public stakingToken;
    MockERC20 public rewardsToken;

    address public admin = makeAddr("admin");
    address[3] public users;

    Handler public handler;

    function setUp() external {
        stakingToken = new MockERC20("Stake", "STK", 18);
        rewardsToken = new MockERC20("Reward", "RWD", 18);
        staking = new StakingRewards(stakingToken, rewardsToken, admin);
        _createUsersAndApprove();
        handler = new Handler(staking, stakingToken, rewardsToken, users, admin);
        targetContract(address(handler));
    }

    function invariant_rewardSolvencyShouldNotBreak() external view {
        uint256 sum;
        for (uint256 i; i < users.length; i++) {
            sum += staking.earned(users[i]);
        }
        assertGe(rewardsToken.balanceOf(address(staking)), sum);
    }

    function _createUsersAndApprove() internal {
        users[0] = makeAddr("user0");
        users[1] = makeAddr("user1");
        users[2] = makeAddr("user2");
        for (uint256 i; i < 3; i++) {
            stakingToken.mint(users[i], 1_000_000e18);
            vm.prank(users[i]);
            stakingToken.approve(address(staking), type(uint256).max);
        }
        rewardsToken.mint(admin, 1_000_000e18);
        vm.prank(admin);
        rewardsToken.approve(address(staking), type(uint256).max);
    }
}
