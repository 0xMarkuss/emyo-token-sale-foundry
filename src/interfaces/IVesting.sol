// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IVesting {
    struct Schedule {
        uint128 total;
        uint128 released;
        uint64 start;
        uint64 periodLength;
        uint16[] percentages;
    }

    function pause() external;
    function unpause() external;
    /// @notice Allocate tokens to beneficiary using module's default vesting configuration.
    /// @dev Implementations should create a schedule if missing or increase existing one
    ///      using module-level defaults (e.g., start now, configured period length and schedule).
    function allocate(address beneficiary, uint128 amount) external;
    function createOrIncreaseSchedule(
        address beneficiary,
        uint128 amount,
        uint64 start,
        uint64 periodLength,
        uint16[] calldata percentages
    ) external;
    function release(address beneficiary) external returns (uint256);
    function releasableAmount(address beneficiary) external view returns (uint256);
    function schedules(address beneficiary) external view returns (
        uint128 total,
        uint128 released,
        uint64 start,
        uint64 periodLength,
        uint16[] memory percentages
    );
}


