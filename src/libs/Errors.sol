// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

library Errors {
    error ZeroAddress();
    error ZeroAmount();
    error NotAuthorized();
    error InvalidParam();
    error NotStarted();
    error AlreadyStarted();
    error AlreadyEnded();
    error Paused();
    error InsufficientBalance();
    error InvalidStageTiming();
    error MaxStagesReached();
    error InvalidVestingSchedule();
    error ScheduleAlreadyExists();
    error ScheduleNotFound();
    error TokensAlreadyReleased();
    error InvalidPeriodLength();
    error SaleNotEnded();
    error VestStartMustBeAfterStageEnd();
    error InvalidEmyPriceUsd();
    error PaymentTokenCannotEqualSaleToken();
}



