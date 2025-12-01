// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Roles {
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 internal constant SALE_ADMIN_ROLE = keccak256("SALE_ADMIN_ROLE");
    bytes32 internal constant VESTING_ADMIN_ROLE = keccak256("VESTING_ADMIN_ROLE");
    bytes32 internal constant STAKING_ADMIN_ROLE = keccak256("STAKING_ADMIN_ROLE");
    bytes32 internal constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
}



