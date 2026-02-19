// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IStakingRewards {
    function pause() external;
    function unpause() external;
    function setRewardRate(uint256 rate) external;
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
    function exit() external;
    function rewardPerToken() external view returns (uint256);
    function earned(address account) external view returns (uint256);
}


