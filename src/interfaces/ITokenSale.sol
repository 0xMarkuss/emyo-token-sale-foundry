// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITokenSale {
    function pause() external;
    function unpause() external;
    function addStage(uint256 emyPriceUsd, uint64 end, uint64 vestStart, uint64 vestPeriodLength, uint16[] calldata vestPercentages) external;
    function setUserLimits(address user, uint128 minPayment, uint128 maxPayment) external;
    function setAllowlistMerkleRoot(bytes32 merkleRoot) external;
    function buy(uint128 paymentAmount, bytes32[] calldata merkleProof) external;
}


