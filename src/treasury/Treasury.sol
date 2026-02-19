// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Roles} from "../access/Roles.sol";
import {Errors} from "../libs/Errors.sol";
import {VestingLibrary} from "../vesting/VestingLibrary.sol";

/// @title Treasury
/// @notice Custody of tokens with vesting-based distribution and direct transfers.
contract Treasury is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using VestingLibrary for VestingLibrary.Schedule;

    mapping(IERC20 => mapping(address => VestingLibrary.Schedule)) public vestingSchedules;
    mapping(IERC20 => uint256) internal _totalVestingObligations;

    event EtherReceived(address indexed from, uint256 amount);
    event EtherWithdrawn(address indexed to, uint256 amount);
    event ERC20Withdrawn(address indexed token, address indexed to, uint256 amount);
    event VestingScheduleSet(
        address indexed token,
        address indexed beneficiary,
        uint256 total,
        uint64 start,
        uint64 periodLength,
        uint16[] percentages
    );
    event TokensReleased(
        address indexed token,
        address indexed beneficiary,
        uint256 amount
    );
    event VestingScheduleRevoked(
        address indexed token,
        address indexed beneficiary,
        uint256 remainingAmount
    );

    constructor(address admin) {
        if (admin == address(0)) revert Errors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(Roles.PAUSER_ROLE, admin);
        _grantRole(Roles.TREASURY_ROLE, admin);
    }

    // ============ External Functions ============

    /// @notice Release vested tokens to beneficiary.
    function release(IERC20 token) external whenNotPaused nonReentrant returns (uint256 amount) {
        if (address(token) == address(0)) revert Errors.ZeroAddress();
        VestingLibrary.Schedule storage s = vestingSchedules[token][msg.sender];
        amount = releasableAmount(token, msg.sender);
        if (amount == 0) return 0;
        if (amount > type(uint128).max) revert Errors.InvalidParam();
        if (s.released > type(uint128).max - uint128(amount)) revert Errors.InvalidParam();
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, amount);
        amount = balanceBefore - token.balanceOf(address(this));
        if (amount == 0) return 0;
        s.released += uint128(amount);
        _totalVestingObligations[token] -= amount;
        emit TokensReleased(address(token), msg.sender, amount);
    }

    // ============ Receive Function ============

    receive() external payable {
        emit EtherReceived(msg.sender, msg.value);
    }

    // ============ Admin Functions ============

    /// @notice Pause treasury withdrawals.
    function pause() external onlyRole(Roles.PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause treasury withdrawals.
    function unpause() external onlyRole(Roles.PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Withdraw Ether to recipient.
    function withdrawEther(address payable to, uint256 amount)
        external
        whenNotPaused
        nonReentrant
        onlyRole(Roles.TREASURY_ROLE)
    {
        if (to == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.ZeroAmount();
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "ETH_TRANSFER_FAILED");
        emit EtherWithdrawn(to, amount);
    }

    /// @notice Withdraw ERC20 to recipient (direct transfer, no vesting).
    function withdrawERC20(IERC20 token, address to, uint256 amount)
        external
        whenNotPaused
        nonReentrant
        onlyRole(Roles.TREASURY_ROLE)
    {
        if (address(token) == address(0) || to == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.ZeroAmount();
        uint256 balance = token.balanceOf(address(this));
        if (amount > balance) revert Errors.InsufficientBalance();
        uint256 obligations = _totalVestingObligations[token];
        if (balance - amount < obligations) revert Errors.InsufficientBalance();
        token.safeTransfer(to, amount);
        emit ERC20Withdrawn(address(token), to, amount);
    }

    /// @notice Set vesting schedule for a beneficiary (tokenomics distribution).
    /// @param token Token to vest
    /// @param beneficiary Address that will receive vested tokens
    /// @param total Total amount to vest
    /// @param start Vesting start timestamp
    /// @param periodLength Length of each vesting period
    /// @param percentages Array of percentages per period (basis points, must sum to 10000)
    function setVestingSchedule(
        IERC20 token,
        address beneficiary,
        uint128 total,
        uint64 start,
        uint64 periodLength,
        uint16[] calldata percentages
    ) external whenNotPaused onlyRole(Roles.TREASURY_ROLE) {
        if (address(token) == address(0) || beneficiary == address(0)) revert Errors.ZeroAddress();
        if (total == 0) revert Errors.ZeroAmount();
        if (periodLength == 0) revert Errors.InvalidPeriodLength();
        if (!VestingLibrary.validatePercentages(percentages)) revert Errors.InvalidVestingSchedule();

        uint256 contractBalance = token.balanceOf(address(this));
        if (_totalVestingObligations[token] + total > contractBalance) revert Errors.InsufficientBalance();
        if (start < block.timestamp) revert Errors.InvalidParam();

        VestingLibrary.Schedule storage s = vestingSchedules[token][beneficiary];
        if (s.total > 0) revert Errors.ScheduleAlreadyExists();

        s.total = total;
        s.start = start;
        s.periodLength = periodLength;
        s.percentages = percentages;
        _totalVestingObligations[token] += total;

        emit VestingScheduleSet(address(token), beneficiary, total, start, periodLength, percentages);
    }

    /// @notice Increase vesting schedule amount (top-up existing schedule).
    function increaseVestingSchedule(
        IERC20 token,
        address beneficiary,
        uint128 additionalAmount
    ) external whenNotPaused onlyRole(Roles.TREASURY_ROLE) {
        if (address(token) == address(0) || beneficiary == address(0)) revert Errors.ZeroAddress();
        if (additionalAmount == 0) revert Errors.ZeroAmount();

        VestingLibrary.Schedule storage s = vestingSchedules[token][beneficiary];
        if (s.total == 0) revert Errors.ScheduleNotFound();

        uint256 contractBalance = token.balanceOf(address(this));
        if (_totalVestingObligations[token] + additionalAmount > contractBalance) revert Errors.InsufficientBalance();
        if (s.total > type(uint128).max - additionalAmount) revert Errors.InvalidParam();

        s.total += additionalAmount;
        _totalVestingObligations[token] += additionalAmount;
        emit VestingScheduleSet(
            address(token),
            beneficiary,
            s.total,
            s.start,
            s.periodLength,
            s.percentages
        );
    }

    /// @notice Admin release vested tokens for a beneficiary.
    function releaseFor(IERC20 token, address beneficiary) external whenNotPaused nonReentrant onlyRole(Roles.TREASURY_ROLE) returns (uint256 amount) {
        if (address(token) == address(0) || beneficiary == address(0)) revert Errors.ZeroAddress();
        VestingLibrary.Schedule storage s = vestingSchedules[token][beneficiary];
        amount = releasableAmount(token, beneficiary);
        if (amount == 0) return 0;
        if (amount > type(uint128).max) revert Errors.InvalidParam();
        if (s.released > type(uint128).max - uint128(amount)) revert Errors.InvalidParam();
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransfer(beneficiary, amount);
        amount = balanceBefore - token.balanceOf(address(this));
        if (amount == 0) return 0;
        s.released += uint128(amount);
        _totalVestingObligations[token] -= amount;
        emit TokensReleased(address(token), beneficiary, amount);
    }

    /// @notice Emergency revoke vesting schedule.
    /// @dev Only allows revocation if no tokens have been released yet.
    /// @param token Token to revoke schedule for
    /// @param beneficiary Beneficiary whose schedule to revoke
    /// @param recoveryAddress Address to send remaining tokens to
    function revokeVestingSchedule(
        IERC20 token,
        address beneficiary,
        address recoveryAddress
    ) external whenNotPaused nonReentrant onlyRole(Roles.TREASURY_ROLE) {
        if (address(token) == address(0) || beneficiary == address(0) || recoveryAddress == address(0)) {
            revert Errors.ZeroAddress();
        }

        VestingLibrary.Schedule storage s = vestingSchedules[token][beneficiary];
        if (s.total == 0) revert Errors.ScheduleNotFound();
        if (s.released > 0) revert Errors.TokensAlreadyReleased();

        uint256 remaining = s.total;
        _totalVestingObligations[token] -= remaining;
        delete vestingSchedules[token][beneficiary];
        if (remaining > 0) {
            token.safeTransfer(recoveryAddress, remaining);
        }
        
        emit VestingScheduleRevoked(address(token), beneficiary, remaining);
    }

    // ============ View Functions ============

    /// @notice Compute releasable amount for a beneficiary.
    function releasableAmount(IERC20 token, address beneficiary) public view returns (uint256) {
        VestingLibrary.Schedule storage s = vestingSchedules[token][beneficiary];
        if (s.total == 0) return 0;
        return VestingLibrary.releasableAmount(s, uint64(block.timestamp));
    }

    /// @notice Get vesting schedule for a beneficiary.
    function getVestingSchedule(IERC20 token, address beneficiary) external view returns (
        uint128 total,
        uint128 released,
        uint64 start,
        uint64 periodLength,
        uint16[] memory percentages
    ) {
        VestingLibrary.Schedule storage s = vestingSchedules[token][beneficiary];
        return (s.total, s.released, s.start, s.periodLength, s.percentages);
    }
}
