// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITreasury {
    function pause() external;
    function unpause() external;
    function withdrawEther(address payable to, uint256 amount) external;
    function withdrawERC20(IERC20 token, address to, uint256 amount) external;
}


