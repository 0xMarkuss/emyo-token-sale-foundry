// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Roles} from "../access/Roles.sol";
import {Errors} from "../libs/Errors.sol";
import {IVesting} from "../interfaces/IVesting.sol";
import {VestingLibrary} from "./VestingLibrary.sol";

/// @title Vesting
/// @notice Schedule-based vesting; schedules are created by authorized roles.
contract Vesting is AccessControl, Pausable, IVesting {
    using SafeERC20 for IERC20;
    using VestingLibrary for VestingLibrary.Schedule;

    IERC20 public immutable token;

    mapping(address => IVesting.Schedule) internal _schedules;

    uint64 public defaultStartDelay;
    uint64 public defaultPeriodLength;
    uint16[] public defaultPercentages;

    event ScheduleCreated(
        address indexed beneficiary,
        uint256 total,
        uint64 start,
        uint64 periodLength,
        uint16[] percentages
    );
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event DefaultsUpdated(uint64 startDelay, uint64 periodLength, uint16[] percentages);

    constructor(IERC20 token_, address admin) {
        if (address(token_) == address(0) || admin == address(0)) revert Errors.ZeroAddress();
        token = token_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(Roles.PAUSER_ROLE, admin);
        _grantRole(Roles.VESTING_ADMIN_ROLE, admin);

        defaultStartDelay = 0;
        defaultPeriodLength = 30 days;
        defaultPercentages = new uint16[](4);
        defaultPercentages[0] = 2500;
        defaultPercentages[1] = 2500;
        defaultPercentages[2] = 2500;
        defaultPercentages[3] = 2500;
    }

    // ============ External Functions ============

    /// @notice Release vested tokens to beneficiary.
    function release(address beneficiary) external whenNotPaused returns (uint256 amount) {
        if (beneficiary == address(0)) revert Errors.ZeroAddress();
        IVesting.Schedule storage s = _schedules[beneficiary];
        amount = releasableAmount(beneficiary);
        if (amount == 0) return 0;
        if (amount > type(uint128).max) revert Errors.InvalidParam();
        if (s.released > type(uint128).max - uint128(amount)) revert Errors.InvalidParam();
        s.released += uint128(amount);
        token.safeTransfer(beneficiary, amount);
        emit TokensReleased(beneficiary, amount);
    }

    // ============ Admin Functions ============

    /// @notice Pause vesting actions.
    function pause() external onlyRole(Roles.PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause vesting actions.
    function unpause() external onlyRole(Roles.PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Update default vesting parameters used by allocate().
    function setDefaults(uint64 startDelay, uint64 periodLength, uint16[] calldata percentages) external onlyRole(Roles.VESTING_ADMIN_ROLE) {
        if (periodLength == 0) revert Errors.InvalidParam();
        if (!VestingLibrary.validatePercentages(percentages)) revert Errors.InvalidParam();
        defaultStartDelay = startDelay;
        defaultPeriodLength = periodLength;
        defaultPercentages = percentages;
        emit DefaultsUpdated(startDelay, periodLength, percentages);
    }

    /// @notice Allocate tokens under default vesting configuration.
    function allocate(address beneficiary, uint128 amount) external whenNotPaused onlyRole(Roles.VESTING_ADMIN_ROLE) {
        IVesting.Schedule storage s = _schedules[beneficiary];
        uint64 start;
        uint64 periodLength;
        uint16[] memory percentages;
        if (s.total == 0) {
            start = uint64(block.timestamp) + defaultStartDelay;
            periodLength = defaultPeriodLength;
            percentages = defaultPercentages;
        } else {
            start = s.start;
            periodLength = s.periodLength;
            percentages = s.percentages;
        }
        _createOrIncreaseSchedule(beneficiary, amount, start, periodLength, percentages);
    }

    /// @notice Create or top-up a beneficiary vesting schedule.
    function createOrIncreaseSchedule(
        address beneficiary,
        uint128 amount,
        uint64 start,
        uint64 periodLength,
        uint16[] calldata percentages
    ) external whenNotPaused onlyRole(Roles.VESTING_ADMIN_ROLE) {
        _createOrIncreaseSchedule(beneficiary, amount, start, periodLength, percentages);
    }

    // ============ View Functions ============

    /// @notice Get schedule for a beneficiary
    function schedules(address beneficiary) external view returns (
        uint128 total,
        uint128 released,
        uint64 start,
        uint64 periodLength,
        uint16[] memory percentages
    ) {
        IVesting.Schedule storage s = _schedules[beneficiary];
        return (s.total, s.released, s.start, s.periodLength, s.percentages);
    }

    /// @notice Compute releasable amount for a beneficiary.
    function releasableAmount(address beneficiary) public view returns (uint256) {
        IVesting.Schedule storage s = _schedules[beneficiary];
        if (s.total == 0) return 0;
        VestingLibrary.Schedule memory libSchedule = _toLibrarySchedule(s);
        return VestingLibrary.releasableAmount(libSchedule, uint64(block.timestamp));
    }

    // ============ Internal Functions ============

    function _createOrIncreaseSchedule(
        address beneficiary,
        uint128 amount,
        uint64 start,
        uint64 periodLength,
        uint16[] memory percentages
    ) internal {
        if (beneficiary == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.ZeroAmount();
        if (periodLength == 0) revert Errors.InvalidParam();
        if (!VestingLibrary.validatePercentages(percentages)) revert Errors.InvalidParam();
        
        IVesting.Schedule storage s = _schedules[beneficiary];
        if (s.total == 0) {
            s.start = start;
            s.periodLength = periodLength;
            s.percentages = percentages;
        } else {
            if (s.start != start || s.periodLength != periodLength) revert Errors.InvalidParam();
            if (s.percentages.length != percentages.length) revert Errors.InvalidParam();
            for (uint256 i = 0; i < percentages.length; i++) {
                if (s.percentages[i] != percentages[i]) revert Errors.InvalidParam();
            }
            if (s.total > type(uint128).max - amount) revert Errors.InvalidParam();
        }
        s.total += amount;
        emit ScheduleCreated(beneficiary, amount, start, periodLength, percentages);
    }

    /// @notice Convert IVesting.Schedule to VestingLibrary.Schedule
    function _toLibrarySchedule(IVesting.Schedule storage s) internal view returns (VestingLibrary.Schedule memory) {
        return VestingLibrary.Schedule({
            total: s.total,
            released: s.released,
            start: s.start,
            periodLength: s.periodLength,
            percentages: s.percentages
        });
    }
}
