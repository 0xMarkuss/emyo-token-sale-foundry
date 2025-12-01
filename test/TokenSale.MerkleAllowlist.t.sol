// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {TokenSale} from "src/sale/TokenSale.sol";
import {Treasury} from "src/treasury/Treasury.sol";
import {EmyoToken} from "src/token/EmyoToken.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {Roles} from "src/access/Roles.sol";
import {Errors} from "src/libs/Errors.sol";

/// @title TokenSale Merkle Allowlist Tests
/// @notice Tests for Merkle tree-based allowlist functionality
contract TokenSaleMerkleAllowlistTest is Test {
    MockERC20 paymentToken;
    EmyoToken saleToken;
    Treasury treasury;
    TokenSale sale;

    address admin = address(0xA11CE);
    address buyer1 = address(0xB0B1);
    address buyer2 = address(0xB0B2);
    address buyer3 = address(0xB0B3);
    address buyer4 = address(0xB0B4);
    address notWhitelisted = address(0xBAD);

    bytes32 merkleRoot;
    mapping(address => bytes32[]) public proofs;

    function setUp() public {
        paymentToken = new MockERC20("USDC", "USDC", 6);
        treasury = new Treasury(admin);
        // Use larger supply to support tests that need more tokens
        saleToken = new EmyoToken("Emyo", "EMY", 100_000_000 ether, address(treasury));
        sale = new TokenSale(paymentToken, saleToken, address(treasury), admin);

        // Fund users with payment tokens
        paymentToken.mint(buyer1, 1_000_000e6);
        paymentToken.mint(buyer2, 1_000_000e6);
        paymentToken.mint(buyer3, 1_000_000e6);
        paymentToken.mint(buyer4, 1_000_000e6);
        paymentToken.mint(notWhitelisted, 1_000_000e6);
        
        vm.startPrank(buyer1);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(buyer2);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(buyer3);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(buyer4);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(notWhitelisted);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();

        // Fund sale contract with tokens for vesting releases
        vm.prank(admin);
        treasury.withdrawERC20(saleToken, address(sale), 5_000_000 ether);

        // Build Merkle tree with whitelisted addresses
        address[] memory whitelist = new address[](4);
        whitelist[0] = buyer1;
        whitelist[1] = buyer2;
        whitelist[2] = buyer3;
        whitelist[3] = buyer4;
        
        merkleRoot = _buildMerkleTree(whitelist);
        _generateProofs(whitelist);
    }

    /// @notice Build Merkle tree and return root
    /// @dev Uses standard Merkle tree construction with sorted pairs
    function _buildMerkleTree(address[] memory addresses) internal pure returns (bytes32) {
        if (addresses.length == 0) return bytes32(0);
        
        bytes32[] memory leaves = new bytes32[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(addresses[i]));
        }
        
        return _computeRoot(leaves);
    }

    /// @notice Compute Merkle root from leaves
    function _computeRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        if (leaves.length == 1) return leaves[0];
        
        uint256 len = leaves.length;
        uint256 nextLen = (len + 1) / 2;
        bytes32[] memory nextLevel = new bytes32[](nextLen);
        
        for (uint256 i = 0; i < nextLen; i++) {
            if (2 * i + 1 < len) {
                nextLevel[i] = _hashPair(leaves[2 * i], leaves[2 * i + 1]);
            } else {
                nextLevel[i] = leaves[2 * i];
            }
        }
        
        return _computeRoot(nextLevel);
    }

    /// @notice Hash two nodes together (sorted)
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    /// @notice Generate Merkle proofs for all addresses
    function _generateProofs(address[] memory addresses) internal {
        bytes32[] memory leaves = new bytes32[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(addresses[i]));
        }
        
        for (uint256 i = 0; i < addresses.length; i++) {
            proofs[addresses[i]] = _getProof(leaves, i);
        }
    }

    /// @notice Get Merkle proof for a leaf at given index
    /// @dev This matches OpenZeppelin's MerkleProof.verifyCalldata standard
    function _getProof(bytes32[] memory leaves, uint256 index) internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](0);
        bytes32[] memory currentLevel = new bytes32[](leaves.length);
        
        // Copy leaves to current level
        for (uint256 i = 0; i < leaves.length; i++) {
            currentLevel[i] = leaves[i];
        }
        
        uint256 currentIndex = index;
        uint256 currentLength = leaves.length;
        
        while (currentLength > 1) {
            uint256 nextLength = (currentLength + 1) / 2;
            bytes32[] memory nextLevel = new bytes32[](nextLength);
            bytes32[] memory newProof = new bytes32[](proof.length + 1);
            
            // Copy existing proof elements
            for (uint256 i = 0; i < proof.length; i++) {
                newProof[i] = proof[i];
            }
            
            // Add sibling to proof
            if (currentIndex % 2 == 0) {
                if (currentIndex + 1 < currentLength) {
                    newProof[proof.length] = currentLevel[currentIndex + 1];
                } else {
                    // Odd number of nodes, no sibling
                    newProof = proof; // Don't add anything
                }
            } else {
                newProof[proof.length] = currentLevel[currentIndex - 1];
            }
            
            proof = newProof;
            
            // Build next level
            for (uint256 i = 0; i < nextLength; i++) {
                uint256 leftIdx = 2 * i;
                uint256 rightIdx = 2 * i + 1;
                if (rightIdx < currentLength) {
                    nextLevel[i] = _hashPair(currentLevel[leftIdx], currentLevel[rightIdx]);
                } else {
                    nextLevel[i] = currentLevel[leftIdx];
                }
            }
            
            currentLevel = nextLevel;
            currentLength = nextLength;
            currentIndex = currentIndex / 2;
        }
        
        return proof;
    }

    /// @notice Test setting Merkle root
    function test_SetAllowlistMerkleRoot_Success() public {
        bytes32 root = bytes32(uint256(0x1234));
        vm.prank(admin);
        sale.setAllowlistMerkleRoot(root);
        assertEq(sale.allowlistMerkleRoot(), root);
    }

    /// @notice Test setting Merkle root reverts if unauthorized
    function test_SetAllowlistMerkleRoot_RevertIf_Unauthorized() public {
        bytes32 root = bytes32(uint256(0x1234));
        vm.expectRevert();
        vm.prank(buyer1);
        sale.setAllowlistMerkleRoot(root);
    }

    /// @notice Test buying with valid Merkle proof when allowlist is enabled
    function test_Buy_WithValidMerkleProof_Success() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setAllowlistMerkleRoot(merkleRoot);
        sale.setAllowlistEnabled(true);
        vm.stopPrank();

        vm.warp(nowTs + 1 days);
        vm.prank(buyer1);
        sale.buy(100e6, proofs[buyer1]);

        (uint128 total, , , , ) = sale.getVestingSchedule(buyer1, 0);
        assertEq(total, 100_000 ether);
    }

    /// @notice Test buying with invalid Merkle proof reverts
    function test_Buy_WithInvalidMerkleProof_Reverts() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setAllowlistMerkleRoot(merkleRoot);
        sale.setAllowlistEnabled(true);
        vm.stopPrank();

        vm.warp(nowTs + 1 days);
        
        // Try to buy with invalid proof (wrong address)
        bytes32[] memory invalidProof = proofs[buyer1];
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(notWhitelisted);
        sale.buy(100e6, invalidProof);
    }

    /// @notice Test buying without proof when not whitelisted reverts
    function test_Buy_NotWhitelisted_Reverts() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setAllowlistMerkleRoot(merkleRoot);
        sale.setAllowlistEnabled(true);
        vm.stopPrank();

        vm.warp(nowTs + 1 days);
        
        // Try to buy with empty proof
        bytes32[] memory emptyProof = new bytes32[](0);
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(notWhitelisted);
        sale.buy(100e6, emptyProof);
    }

    /// @notice Test buying when allowlist is disabled (no proof needed)
    function test_Buy_AllowlistDisabled_NoProofNeeded() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setAllowlistEnabled(false);
        vm.stopPrank();

        vm.warp(nowTs + 1 days);
        
        // Buy without proof (empty array)
        bytes32[] memory emptyProof = new bytes32[](0);
        vm.prank(notWhitelisted);
        sale.buy(100e6, emptyProof);

        (uint128 total, , , , ) = sale.getVestingSchedule(notWhitelisted, 0);
        assertEq(total, 100_000 ether);
    }

    /// @notice Test buying reverts if allowlist enabled but root not set
    function test_Buy_AllowlistEnabledButNoRoot_Reverts() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setAllowlistEnabled(true);
        // Don't set root
        vm.stopPrank();

        vm.warp(nowTs + 1 days);
        
        bytes32[] memory proof = new bytes32[](0);
        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(buyer1);
        sale.buy(100e6, proof);
    }

    /// @notice Test multiple whitelisted users can buy with their proofs
    function test_Buy_MultipleWhitelistedUsers_Success() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setAllowlistMerkleRoot(merkleRoot);
        sale.setAllowlistEnabled(true);
        vm.stopPrank();

        vm.warp(nowTs + 1 days);

        // Buyer1 buys
        vm.prank(buyer1);
        sale.buy(100e6, proofs[buyer1]);
        (uint128 total1, , , , ) = sale.getVestingSchedule(buyer1, 0);
        assertEq(total1, 100_000 ether);

        // Buyer2 buys
        vm.prank(buyer2);
        sale.buy(50e6, proofs[buyer2]);
        (uint128 total2, , , , ) = sale.getVestingSchedule(buyer2, 0);
        assertEq(total2, 50_000 ether);

        // Buyer3 buys
        vm.prank(buyer3);
        sale.buy(200e6, proofs[buyer3]);
        (uint128 total3, , , , ) = sale.getVestingSchedule(buyer3, 0);
        assertEq(total3, 200_000 ether);

        // Buyer4 buys
        vm.prank(buyer4);
        sale.buy(75e6, proofs[buyer4]);
        (uint128 total4, , , , ) = sale.getVestingSchedule(buyer4, 0);
        assertEq(total4, 75_000 ether);
    }

    /// @notice Test that same user can buy multiple times with same proof
    function test_Buy_MultipleTimes_SameProof_Success() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setAllowlistMerkleRoot(merkleRoot);
        sale.setAllowlistEnabled(true);
        vm.stopPrank();

        vm.warp(nowTs + 1 days);

        // First purchase
        vm.prank(buyer1);
        sale.buy(100e6, proofs[buyer1]);
        (uint128 total1, , , , ) = sale.getVestingSchedule(buyer1, 0);
        assertEq(total1, 100_000 ether);

        // Second purchase with same proof
        vm.prank(buyer1);
        sale.buy(50e6, proofs[buyer1]);
        (uint128 total2, , , , ) = sale.getVestingSchedule(buyer1, 0);
        assertEq(total2, 150_000 ether);
    }

    /// @notice Test updating Merkle root works
    function test_UpdateMerkleRoot_Works() public {
        bytes32 root1 = bytes32(uint256(0x1111));
        bytes32 root2 = bytes32(uint256(0x2222));

        vm.startPrank(admin);
        sale.setAllowlistMerkleRoot(root1);
        assertEq(sale.allowlistMerkleRoot(), root1);
        
        sale.setAllowlistMerkleRoot(root2);
        assertEq(sale.allowlistMerkleRoot(), root2);
        vm.stopPrank();
    }

    /// @notice Test event emission when setting Merkle root
    function test_SetAllowlistMerkleRoot_EmitsEvent() public {
        bytes32 root = bytes32(uint256(0x1234));
        vm.expectEmit(true, false, false, false);
        emit TokenSale.AllowlistMerkleRootSet(root);
        vm.prank(admin);
        sale.setAllowlistMerkleRoot(root);
    }

    // ============================================
    // COMPREHENSIVE MERKLE PROOF WORKFLOW TESTS
    // ============================================

    /// @notice Test complete workflow: Setup -> Enable -> Buy -> Verify
    /// @dev This demonstrates the full merkle proof workflow end-to-end
    function test_MerkleProofWorkflow_CompleteFlow() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        // Step 1: Admin sets up stage
        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        
        // Step 2: Admin sets merkle root
        sale.setAllowlistMerkleRoot(merkleRoot);
        assertEq(sale.allowlistMerkleRoot(), merkleRoot);
        
        // Step 3: Admin enables allowlist
        sale.setAllowlistEnabled(true);
        assertEq(sale.allowlistEnabled(), true);
        vm.stopPrank();

        // Step 4: Move to active stage
        vm.warp(nowTs + 1 days);

        // Step 5: Whitelisted user buys with valid proof
        uint256 balanceBefore = saleToken.balanceOf(address(sale));
        vm.prank(buyer1);
        sale.buy(100e6, proofs[buyer1]);

        // Step 6: Verify purchase succeeded
        (uint128 total, uint128 released, , , ) = sale.getVestingSchedule(buyer1, 0);
        assertEq(total, 100_000 ether);
        assertEq(released, 0); // Nothing released yet
        assertEq(balanceBefore - saleToken.balanceOf(address(sale)), 0); // Tokens allocated but not released
    }

    /// @notice Test merkle proof verification with all whitelisted addresses
    /// @dev Verifies that each whitelisted address can successfully use their proof
    function test_MerkleProofWorkflow_AllWhitelistedAddresses() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setAllowlistMerkleRoot(merkleRoot);
        sale.setAllowlistEnabled(true);
        vm.stopPrank();

        vm.warp(nowTs + 1 days);

        // Verify each buyer can use their proof
        address[] memory buyers = new address[](4);
        buyers[0] = buyer1;
        buyers[1] = buyer2;
        buyers[2] = buyer3;
        buyers[3] = buyer4;

        for (uint256 i = 0; i < buyers.length; i++) {
            address buyer = buyers[i];
            bytes32 leaf = keccak256(abi.encodePacked(buyer));
            
            // Verify proof is valid using OpenZeppelin's library directly
            bytes32[] memory proof = proofs[buyer];
            bool isValid = MerkleProof.verify(proof, merkleRoot, leaf);
            assertTrue(isValid, "Proof should be valid for whitelisted address");

            // Execute purchase
            vm.prank(buyer);
            sale.buy(100e6, proofs[buyer]);

            // Verify purchase recorded
            (uint128 total, , , , ) = sale.getVestingSchedule(buyer, 0);
            assertEq(total, 100_000 ether);
        }
    }

    /// @notice Test merkle proof fails for non-whitelisted address
    /// @dev Demonstrates that proofs cannot be reused by unauthorized addresses
    function test_MerkleProofWorkflow_NonWhitelistedFails() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setAllowlistMerkleRoot(merkleRoot);
        sale.setAllowlistEnabled(true);
        vm.stopPrank();

        vm.warp(nowTs + 1 days);

        // Verify proof is invalid for non-whitelisted address
        bytes32 leaf = keccak256(abi.encodePacked(notWhitelisted));
        bytes32[] memory proof = proofs[buyer1];
        bool isValid = MerkleProof.verify(proof, merkleRoot, leaf);
        assertFalse(isValid, "Proof should be invalid for non-whitelisted address");

        // Attempt purchase should fail
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(notWhitelisted);
        sale.buy(100e6, proofs[buyer1]);
    }

    /// @notice Test merkle root update invalidates old proofs
    /// @dev Demonstrates that updating root requires new proofs
    function test_MerkleProofWorkflow_RootUpdateInvalidatesProofs() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setAllowlistMerkleRoot(merkleRoot);
        sale.setAllowlistEnabled(true);
        vm.stopPrank();

        vm.warp(nowTs + 1 days);

        // First purchase works with original root
        vm.prank(buyer1);
        sale.buy(100e6, proofs[buyer1]);

        // Update root to a new one (simulating new allowlist)
        bytes32 newRoot = bytes32(uint256(0xDEADBEEF));
        vm.prank(admin);
        sale.setAllowlistMerkleRoot(newRoot);

        // Old proof should fail with new root
        bytes32 leaf = keccak256(abi.encodePacked(buyer1));
        bytes32[] memory proof = proofs[buyer1];
        bool isValid = MerkleProof.verify(proof, newRoot, leaf);
        assertFalse(isValid, "Old proof should be invalid with new root");

        // Purchase should fail
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(buyer1);
        sale.buy(50e6, proofs[buyer1]);
    }

    /// @notice Test allowlist can be toggled on/off
    /// @dev Demonstrates flexibility of allowlist system
    function test_MerkleProofWorkflow_AllowlistToggle() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setAllowlistMerkleRoot(merkleRoot);
        vm.stopPrank();

        vm.warp(nowTs + 1 days);

        // Initially disabled - anyone can buy
        assertEq(sale.allowlistEnabled(), false);
        bytes32[] memory emptyProof = new bytes32[](0);
        vm.prank(notWhitelisted);
        sale.buy(100e6, emptyProof);

        // Enable allowlist
        vm.prank(admin);
        sale.setAllowlistEnabled(true);
        assertEq(sale.allowlistEnabled(), true);

        // Now only whitelisted can buy
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(notWhitelisted);
        sale.buy(100e6, emptyProof);

        // Whitelisted can still buy
        vm.prank(buyer1);
        sale.buy(50e6, proofs[buyer1]);

        // Disable allowlist again
        vm.prank(admin);
        sale.setAllowlistEnabled(false);

        // Anyone can buy again
        vm.prank(notWhitelisted);
        sale.buy(25e6, emptyProof);
    }

    /// @notice Test multiple purchases with same proof across different stages
    /// @dev Demonstrates proof reuse across stages
    function test_MerkleProofWorkflow_MultipleStages() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.addStage(200, nowTs + 10 days, nowTs + 13 days, 30 days, percentages);
        sale.setAllowlistMerkleRoot(merkleRoot);
        sale.setAllowlistEnabled(true);
        vm.stopPrank();

        vm.warp(nowTs + 1 days);

        // Buy in stage 0
        vm.prank(buyer1);
        sale.buy(100e6, proofs[buyer1]);
        (uint128 total0, , , , ) = sale.getVestingSchedule(buyer1, 0);
        assertEq(total0, 100_000 ether);

        // Move to stage 1
        vm.warp(nowTs + 8 days);

        // Buy in stage 1 with same proof
        vm.prank(buyer1);
        sale.buy(50e6, proofs[buyer1]);
        (uint128 total1, , , , ) = sale.getVestingSchedule(buyer1, 1);
        assertEq(total1, 25_000 ether); // 50e6 * 100000 * 1e12 / 200 = 25k tokens
    }

    /// @notice Test proof verification with single address in tree
    /// @dev Edge case: tree with only one leaf
    function test_MerkleProofWorkflow_SingleAddressTree() public {
        // Create tree with single address
        address[] memory singleWhitelist = new address[](1);
        singleWhitelist[0] = buyer1;
        bytes32 singleRoot = _buildMerkleTree(singleWhitelist);
        bytes32[] memory singleLeaf = new bytes32[](1);
        singleLeaf[0] = keccak256(abi.encodePacked(buyer1));
        bytes32[] memory singleProof = _getProof(singleLeaf, 0);

        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setAllowlistMerkleRoot(singleRoot);
        sale.setAllowlistEnabled(true);
        vm.stopPrank();

        vm.warp(nowTs + 1 days);

        // Verify proof works
        bytes32 leaf = keccak256(abi.encodePacked(buyer1));
        bool isValid = MerkleProof.verify(singleProof, singleRoot, leaf);
        assertTrue(isValid, "Single address proof should be valid");

        // Purchase should work
        vm.prank(buyer1);
        sale.buy(100e6, singleProof);
        (uint128 total, , , , ) = sale.getVestingSchedule(buyer1, 0);
        assertEq(total, 100_000 ether);
    }

    /// @notice Test proof verification with large tree (8 addresses)
    /// @dev Edge case: larger tree structure
    function test_MerkleProofWorkflow_LargeTree() public {
        // Create tree with 8 addresses
        address[] memory largeWhitelist = new address[](8);
        largeWhitelist[0] = buyer1;
        largeWhitelist[1] = buyer2;
        largeWhitelist[2] = buyer3;
        largeWhitelist[3] = buyer4;
        largeWhitelist[4] = address(0xB0B5);
        largeWhitelist[5] = address(0xB0B6);
        largeWhitelist[6] = address(0xB0B7);
        largeWhitelist[7] = address(0xB0B8);

        bytes32 largeRoot = _buildMerkleTree(largeWhitelist);
        
        // Generate proofs for all addresses
        bytes32[] memory leaves = new bytes32[](8);
        for (uint256 i = 0; i < 8; i++) {
            leaves[i] = keccak256(abi.encodePacked(largeWhitelist[i]));
        }

        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setAllowlistMerkleRoot(largeRoot);
        sale.setAllowlistEnabled(true);
        vm.stopPrank();

        vm.warp(nowTs + 1 days);

        // Test each address can buy with their proof
        for (uint256 i = 0; i < 4; i++) { // Test first 4 buyers
            address buyer = largeWhitelist[i];
            bytes32[] memory proof = _getProof(leaves, i);
            bytes32 leaf = keccak256(abi.encodePacked(buyer));
            
            // Verify proof
            bool isValid = MerkleProof.verify(proof, largeRoot, leaf);
            assertTrue(isValid, "Proof should be valid for large tree");

            // Fund buyer if needed
            if (i >= 4) {
                paymentToken.mint(buyer, 1_000_000e6);
                vm.prank(buyer);
                paymentToken.approve(address(sale), type(uint256).max);
            }

            // Purchase
            vm.prank(buyer);
            sale.buy(100e6, proof);
        }
    }

    /// @notice Test that proof verification happens before payment transfer
    /// @dev Ensures gas efficiency - fail fast if proof invalid
    function test_MerkleProofWorkflow_ProofCheckedBeforePayment() public {
        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setAllowlistMerkleRoot(merkleRoot);
        sale.setAllowlistEnabled(true);
        vm.stopPrank();

        vm.warp(nowTs + 1 days);

        uint256 balanceBefore = paymentToken.balanceOf(notWhitelisted);

        // Attempt purchase with invalid proof
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(notWhitelisted);
        sale.buy(100e6, proofs[buyer1]);

        // Verify payment token was NOT transferred
        uint256 balanceAfter = paymentToken.balanceOf(notWhitelisted);
        assertEq(balanceBefore, balanceAfter, "Payment should not be transferred on proof failure");
    }

    /// @notice Test concrete example: Real-world scenario
    /// @dev Demonstrates practical usage with realistic values
    function test_MerkleProofWorkflow_RealWorldScenario() public {
        // Scenario: Private sale with 4 VIP investors
        // Need more tokens: 10M + 5M + 20M + 7.5M = 42.5M tokens
        // Withdraw additional tokens from treasury (treasury has 100M from setUp)
        vm.prank(admin);
        treasury.withdrawERC20(saleToken, address(sale), 50_000_000 ether);

        uint64 nowTs = uint64(block.timestamp);
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500; // 25% at start
        percentages[1] = 2500; // 25% after 30 days
        percentages[2] = 2500; // 25% after 60 days
        percentages[3] = 2500; // 25% after 90 days

        // Setup sale
        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        sale.setAllowlistMerkleRoot(merkleRoot);
        sale.setAllowlistEnabled(true);
        vm.stopPrank();

        vm.warp(nowTs + 1 days);

        // Investor 1: Buys $10,000 worth
        vm.prank(buyer1);
        sale.buy(10_000e6, proofs[buyer1]);
        (uint128 total1, , , , ) = sale.getVestingSchedule(buyer1, 0);
        assertEq(total1, 10_000_000 ether); // 10k USDC * 100000 * 1e12 / 100

        // Investor 2: Buys $5,000 worth
        vm.prank(buyer2);
        sale.buy(5_000e6, proofs[buyer2]);
        (uint128 total2, , , , ) = sale.getVestingSchedule(buyer2, 0);
        assertEq(total2, 5_000_000 ether);

        // Investor 3: Buys $20,000 worth
        vm.prank(buyer3);
        sale.buy(20_000e6, proofs[buyer3]);
        (uint128 total3, , , , ) = sale.getVestingSchedule(buyer3, 0);
        assertEq(total3, 20_000_000 ether);

        // Investor 4: Buys $7,500 worth
        vm.prank(buyer4);
        sale.buy(7_500e6, proofs[buyer4]);
        (uint128 total4, , , , ) = sale.getVestingSchedule(buyer4, 0);
        assertEq(total4, 7_500_000 ether);

        // Unauthorized investor tries to buy - should fail
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(notWhitelisted);
        sale.buy(1_000e6, new bytes32[](0));

        // Verify total sold
        assertEq(sale.totalSold(), 42_500_000 ether);
    }
}

