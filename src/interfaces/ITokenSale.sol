// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITokenSale {
    function pause() external;
    function unpause() external;
    function addStage(uint128 price, uint128 cap, uint64 start, uint64 end, bool useAllowlist) external;
    function setUserLimits(address user, uint128 minPayment, uint128 maxPayment) external;
    function setAllowlistMerkleRoot(bytes32 merkleRoot) external;
    function buy(uint256 stageId, uint128 paymentAmount, uint64 vestStart, uint64 vestCliff, uint64 vestDuration) external;
}


