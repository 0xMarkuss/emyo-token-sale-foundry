// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Roles} from "../access/Roles.sol";
import {Errors} from "../libs/Errors.sol";

/// @title StakingRewards
/// @notice Minimal single-sided staking with continuous rewards rate (per second).
/// @dev Reward rate is in rewards per second, scaled by rewards token decimals.
contract StakingRewards is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardsToken;
    uint8 public immutable rewardsTokenDecimals;

    uint256 public rewardRate;
    uint256 public periodFinish;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    uint256 public totalStaked;
    mapping(address => uint256) public balances;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 public constant DEFAULT_DISTRIBUTION_PERIOD = 30 days;
    uint256 public constant MIN_REWARD_DURATION = 1 days;

    event RewardRateUpdated(uint256 rate, uint256 periodEndTime);
    event RewardsToppedUp(uint256 amount, uint256 newRate, uint256 periodEndTime);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(IERC20 stakingToken_, IERC20 rewardsToken_, address admin) {
        if (address(stakingToken_) == address(0) || address(rewardsToken_) == address(0) || admin == address(0)) revert Errors.ZeroAddress();
        stakingToken = stakingToken_;
        rewardsToken = rewardsToken_;
        rewardsTokenDecimals = IERC20Metadata(address(rewardsToken_)).decimals();
        lastUpdateTime = block.timestamp;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(Roles.PAUSER_ROLE, admin);
        _grantRole(Roles.STAKING_ADMIN_ROLE, admin);
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        uint256 effectiveTime = (periodFinish > 0 && block.timestamp > periodFinish) ? periodFinish : block.timestamp;
        lastUpdateTime = effectiveTime;
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    // ============ External Functions ============

    /// @notice Stake tokens to earn rewards.
    function stake(uint256 amount) external whenNotPaused nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert Errors.ZeroAmount();
        uint256 balanceBefore = stakingToken.balanceOf(address(this));
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 actualReceived = stakingToken.balanceOf(address(this)) - balanceBefore;
        if (actualReceived == 0) revert Errors.ZeroAmount();
        totalStaked += actualReceived;
        balances[msg.sender] += actualReceived;
        emit Staked(msg.sender, actualReceived);
    }

    /// @notice Withdraw staked tokens.
    function withdraw(uint256 amount) public whenNotPaused nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert Errors.ZeroAmount();
        if (amount > balances[msg.sender]) revert Errors.InsufficientBalance();
        balances[msg.sender] -= amount;
        totalStaked -= amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Claim earned rewards.
    function getReward() public whenNotPaused nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        rewards[msg.sender] = 0;
        rewardsToken.safeTransfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward);
    }

    /// @notice Withdraw all staked tokens and claim rewards.
    function exit() external {
        withdraw(balances[msg.sender]);
        getReward();
    }

    // ============ Admin Functions ============

    /// @notice Pause staking operations.
    function pause() external onlyRole(Roles.PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause staking operations.
    function unpause() external onlyRole(Roles.PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Set reward rate (rewards per second).
    /// @dev Validates that contract has sufficient funds to sustain the rate over MIN_REWARD_DURATION.
    /// @param rate Rewards per second (in rewards token units with decimals).
    function setRewardRate(uint256 rate) external onlyRole(Roles.STAKING_ADMIN_ROLE) updateReward(address(0)) {
        if (rate > 0) {
            uint256 totalAvailableBalance = rewardsToken.balanceOf(address(this));
            uint256 availableFunds = totalAvailableBalance;
            if (address(stakingToken) == address(rewardsToken)) {
                availableFunds = totalAvailableBalance >= totalStaked ? totalAvailableBalance - totalStaked : 0;
            }
            uint256 requiredFunds = rate * MIN_REWARD_DURATION;
            if (availableFunds < requiredFunds) revert Errors.InvalidParam();
        }
        rewardRate = rate;
        lastUpdateTime = block.timestamp;
        uint256 periodEndTime = rate > 0 ? _calculatePeriodEndTime(rate) : 0;
        periodFinish = periodEndTime;
        emit RewardRateUpdated(rate, periodEndTime);
    }

    /// @notice Top-up rewards and set rate to distribute the new amount over default period.
    function topUpRewards(uint256 amount) external onlyRole(Roles.STAKING_ADMIN_ROLE) updateReward(address(0)) {
        _topUpRewards(amount, DEFAULT_DISTRIBUTION_PERIOD);
    }

    /// @notice Top-up rewards and set rate to distribute the new amount over custom period.
    function topUpRewardsWithPeriod(uint256 amount, uint256 periodSeconds) external onlyRole(Roles.STAKING_ADMIN_ROLE) updateReward(address(0)) {
        if (periodSeconds == 0 || periodSeconds < 1 days) revert Errors.InvalidParam();
        _topUpRewards(amount, periodSeconds);
    }

    // ============ View Functions ============

    /// @notice Calculate accumulated reward per token staked.
    /// @dev Uses rewards token decimals for precision. Caps at periodFinish.
    /// @return Current reward per token (scaled by 10^rewardsTokenDecimals).
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) return rewardPerTokenStored;
        uint256 lastTime = lastUpdateTime;
        uint256 endTime = block.timestamp;
        if (periodFinish > 0 && endTime > periodFinish) endTime = periodFinish;
        if (endTime <= lastTime) return rewardPerTokenStored;
        uint256 timeElapsed = endTime - lastTime;
        uint256 scale = 10**rewardsTokenDecimals;
        return rewardPerTokenStored + ((rewardRate * timeElapsed * scale) / totalStaked);
    }

    /// @notice Calculate earned rewards for an account.
    /// @param account User address.
    /// @return Total earned rewards (in rewards token units).
    function earned(address account) public view returns (uint256) {
        uint256 scale = 10**rewardsTokenDecimals;
        uint256 rewardPerTokenDelta = rewardPerToken() - userRewardPerTokenPaid[account];
        return ((balances[account] * rewardPerTokenDelta) / scale) + rewards[account];
    }

    /// @notice Calculate when current reward funds will run out.
    /// @return endTime Timestamp when funds will be exhausted, or 0 if no active rate.
    function getPeriodEndTime() external view returns (uint256 endTime) {
        return _calculatePeriodEndTime(rewardRate);
    }

    /// @notice Calculate required funds for a given reward rate over default period.
    /// @param rate Reward rate (rewards per second).
    /// @return requiredFunds Amount of rewards token needed.
    function calculateRequiredFunds(uint256 rate) external pure returns (uint256 requiredFunds) {
        return _calculateRequiredFunds(rate);
    }

    /// @notice Get current available rewards balance (excludes staked principal when stakingToken == rewardsToken).
    function getAvailableRewards() external view returns (uint256) {
        uint256 balance = rewardsToken.balanceOf(address(this));
        if (address(stakingToken) == address(rewardsToken) && balance >= totalStaked) {
            return balance - totalStaked;
        }
        return balance;
    }

    // ============ Internal Functions ============

    function _topUpRewards(uint256 amount, uint256 periodSeconds) internal {
        if (amount == 0) revert Errors.ZeroAmount();
        rewardsToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 newRate = amount / periodSeconds;
        if (newRate == 0) revert Errors.InvalidParam();
        rewardRate = newRate;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + periodSeconds;
        emit RewardsToppedUp(amount, newRate, periodFinish);
    }

    /// @notice Internal: Calculate when funds will run out for given rate.
    function _calculatePeriodEndTime(uint256 rate) internal view returns (uint256) {
        if (rate == 0) return 0;
        uint256 totalAvailableBalance = rewardsToken.balanceOf(address(this));
        uint256 availableFunds = totalAvailableBalance;
        if (address(stakingToken) == address(rewardsToken)) {
            availableFunds = totalAvailableBalance >= totalStaked ? totalAvailableBalance - totalStaked : 0;
        }
        if (availableFunds == 0) return block.timestamp;
        uint256 secondsRemaining = availableFunds / rate;
        return block.timestamp + secondsRemaining;
    }

    /// @notice Internal: Calculate required funds for rate over default period.
    function _calculateRequiredFunds(uint256 rate) internal pure returns (uint256) {
        if (rate == 0) return 0;
        return rate * DEFAULT_DISTRIBUTION_PERIOD;
    }
}
