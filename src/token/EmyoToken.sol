// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {Roles} from "../access/Roles.sol";
import {Errors} from "../libs/Errors.sol";

/// @title EmyoToken
/// @notice Fixed supply ERC20 with permit; minted once to `treasury`.
contract EmyoToken is ERC20, ERC20Permit, AccessControl, Pausable {
    /// @notice Total supply cap (immutable for explicitness).
    uint256 public immutable totalSupplyCap;

    /// @param name_ Token name.
    /// @param symbol_ Token symbol.
    /// @param totalSupply_ Fixed total supply minted at deploy.
    /// @param treasury_ Recipient of initial supply.
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        address treasury_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (treasury_ == address(0)) revert Errors.ZeroAddress();
        totalSupplyCap = totalSupply_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(Roles.PAUSER_ROLE, msg.sender);
        _mint(treasury_, totalSupply_);
    }

    /// @notice Pause token transfers.
    function pause() external onlyRole(Roles.PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause token transfers.
    function unpause() external onlyRole(Roles.PAUSER_ROLE) {
        _unpause();
    }

    /// @inheritdoc ERC20
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20)
        whenNotPaused
    {
        super._update(from, to, value);
    }
}
