// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EmyoToken} from "src/token/EmyoToken.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Roles} from "src/access/Roles.sol";
import {Errors} from "src/libs/Errors.sol";

contract EmyoTokenTest is Test {
    EmyoToken token;
    address treasury = address(0x1234567890123456789012345678901234567890);
    address deployer = address(this);

    function setUp() public {
        token = new EmyoToken("Emyo Token", "EMY", 10_000_000 ether, treasury);
    }

    function test_Constructor_SetsCorrectValues() public {
        assertEq(token.name(), "Emyo Token");
        assertEq(token.symbol(), "EMY");
        assertEq(token.totalSupply(), 10_000_000 ether);
        assertEq(token.totalSupplyCap(), 10_000_000 ether);
        assertEq(token.balanceOf(treasury), 10_000_000 ether);
        assertTrue(token.hasRole(0x00, deployer));
        assertTrue(token.hasRole(Roles.PAUSER_ROLE, deployer));
    }

    function test_Constructor_RevertIf_ZeroTreasury() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new EmyoToken("Emyo Token", "EMY", 10_000_000 ether, address(0));
    }

    address user1 = address(0x1111111111111111111111111111111111111111);
    address user2 = address(0x2222222222222222222222222222222222222222);
    address user3 = address(0x3333333333333333333333333333333333333333);

    function test_Transfer_Success() public {
        vm.prank(treasury);
        token.transfer(user1, 1_000 ether);
        assertEq(token.balanceOf(user1), 1_000 ether);
        assertEq(token.balanceOf(treasury), 10_000_000 ether - 1_000 ether);
    }

    function test_Transfer_RevertIf_Paused() public {
        vm.prank(deployer);
        token.pause();

        vm.expectRevert();
        vm.prank(treasury);
        token.transfer(user1, 1_000 ether);
    }

    function test_Approve_Success() public {
        vm.prank(treasury);
        token.approve(user1, 1_000 ether);
        assertEq(token.allowance(treasury, user1), 1_000 ether);
    }

    function test_TransferFrom_Success() public {
        vm.prank(treasury);
        token.approve(user1, 1_000 ether);

        vm.prank(user1);
        token.transferFrom(treasury, user2, 500 ether);
        assertEq(token.balanceOf(user2), 500 ether);
        assertEq(token.allowance(treasury, user1), 500 ether);
    }

    function test_TransferFrom_RevertIf_Paused() public {
        vm.prank(treasury);
        token.approve(user1, 1_000 ether);

        vm.prank(deployer);
        token.pause();

        vm.expectRevert();
        vm.prank(user1);
        token.transferFrom(treasury, user2, 500 ether);
    }

    function test_Pause_Unpause_Success() public {
        vm.prank(deployer);
        token.pause();
        assertTrue(token.paused());

        vm.prank(deployer);
        token.unpause();
        assertFalse(token.paused());
    }

    function test_Pause_RevertIf_Unauthorized() public {
        vm.expectRevert();
        vm.prank(address(0xBAD));
        token.pause();
    }

    function test_Permit_Success() public {
        address owner = vm.addr(1); // Use address corresponding to private key 1
        address spender = address(0x5555555555555555555555555555555555555555);
        uint256 value = 1_000 ether;
        
        // Fund owner with tokens
        vm.prank(treasury);
        token.transfer(owner, value);
        
        uint256 nonce = token.nonces(owner);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );

        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        vm.prank(owner);
        token.permit(owner, spender, value, deadline, v, r, s);

        assertEq(token.allowance(owner, spender), value);
        assertEq(token.nonces(owner), nonce + 1);
    }

    function testFuzz_Transfer_WithinBalance(uint256 amount) public {
        amount = bound(amount, 1, 10_000_000 ether);
        vm.prank(treasury);
        token.transfer(user1, amount);
        assertEq(token.balanceOf(user1), amount);
    }

    function testFuzz_Approve_AnyAmount(uint256 amount) public {
        vm.prank(treasury);
        token.approve(user1, amount);
        assertEq(token.allowance(treasury, user1), amount);
    }
}

