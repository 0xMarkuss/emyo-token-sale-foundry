// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title VestingLibrary
/// @notice Library for schedule-based vesting calculations
library VestingLibrary {
    struct Schedule {
        uint128 total;
        uint128 released;
        uint64 start;
        uint64 periodLength;
        uint16[] percentages;
    }

    /// @notice Calculate vested amount based on schedule
    /// @param s The vesting schedule
    /// @param timestamp Current timestamp
    /// @return vested The amount that has vested by the given timestamp
    function vestedAmount(Schedule memory s, uint64 timestamp) internal pure returns (uint256) {
        if (s.total == 0) return 0;
        if (timestamp < s.start) return 0;
        if (s.percentages.length == 0) return 0;
        if (s.periodLength == 0) return 0;

        uint256 periodsElapsed = (timestamp - s.start) / s.periodLength;
        if (periodsElapsed >= s.percentages.length) {
            return s.total;
        }

        uint256 totalPercentages = 0;
        for (uint256 i = 0; i < periodsElapsed; i++) {
            totalPercentages += s.percentages[i];
        }

        return (uint256(s.total) * totalPercentages) / 10000;
    }

    /// @notice Calculate releasable amount (vested - released)
    /// @param s The vesting schedule
    /// @param timestamp Current timestamp
    /// @return releasable The amount that can be released
    function releasableAmount(Schedule memory s, uint64 timestamp) internal pure returns (uint256) {
        uint256 vested = vestedAmount(s, timestamp);
        if (vested <= s.released) return 0;
        return vested - s.released;
    }

    uint256 internal constant MAX_PERCENTAGES_LENGTH = 100;

    /// @notice Validate schedule percentages sum to 10000 (100%)
    /// @param percentages Array of percentages in basis points
    /// @return valid True if percentages sum to 10000
    function validatePercentages(uint16[] memory percentages) internal pure returns (bool) {
        if (percentages.length == 0 || percentages.length > MAX_PERCENTAGES_LENGTH) return false;
        uint256 sum = 0;
        for (uint256 i = 0; i < percentages.length; i++) {
            sum += percentages[i];
        }
        return sum == 10000;
    }
}
