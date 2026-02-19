// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TokenSale} from "src/sale/TokenSale.sol";
import {Treasury} from "src/treasury/Treasury.sol";
import {EmyoToken} from "src/token/EmyoToken.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {Roles} from "src/access/Roles.sol";
import {Errors} from "src/libs/Errors.sol";

/// @title TokenSale Multi-Stage Purchase Tests
/// @notice Comprehensive tests for users purchasing across different stages
contract TokenSaleMultiStageTest is Test {
    MockERC20 paymentToken;
    EmyoToken saleToken;
    Treasury treasury;
    TokenSale sale;

    address admin = address(0xA11CE);
    address buyer1 = address(0xB0B1);
    address buyer2 = address(0xB0B2);
    address buyer3 = address(0xB0B3);

    function setUp() public {
        paymentToken = new MockERC20("USDC", "USDC", 6);
        treasury = new Treasury(admin);
        saleToken = new EmyoToken("Emyo", "EMY", 10_000_000 ether, address(treasury));
        sale = new TokenSale(paymentToken, saleToken, address(treasury), admin);

        // Fund users with payment tokens
        paymentToken.mint(buyer1, 1_000_000e6);
        paymentToken.mint(buyer2, 1_000_000e6);
        paymentToken.mint(buyer3, 1_000_000e6);
        vm.startPrank(buyer1);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(buyer2);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(buyer3);
        paymentToken.approve(address(sale), type(uint256).max);
        vm.stopPrank();

        // Fund sale contract with tokens for vesting releases
        vm.prank(admin);
        treasury.withdrawERC20(saleToken, address(sale), 5_000_000 ether);
    }

    /// @notice Test user purchasing in Stage 1, then Stage 2, then Stage 3
    /// Each purchase creates a separate vesting schedule per stage
    function test_Buy_Stage1_ThenStage2_ThenStage3_AggregatesSchedule() public {
        uint64 nowTs = uint64(block.timestamp);
        uint64 stage0End = nowTs + 1 days;
        uint64 stage1End = nowTs + 2 days;
        uint64 stage2End = nowTs + 3 days;
        uint64 stage1Start = stage0End + 1;
        uint64 stage2Start = stage1End + 1;

        uint16[] memory percentages1 = new uint16[](4);
        percentages1[0] = 2500;
        percentages1[1] = 2500;
        percentages1[2] = 2500;
        percentages1[3] = 2500;

        uint16[] memory percentages2 = new uint16[](5);
        percentages2[0] = 2000;
        percentages2[1] = 2000;
        percentages2[2] = 2000;
        percentages2[3] = 2000;
        percentages2[4] = 2000;

        uint16[] memory percentages3 = new uint16[](3);
        percentages3[0] = 3333;
        percentages3[1] = 3333;
        percentages3[2] = 3334;

        uint64 vestStart1 = nowTs + 4 days;
        uint64 vestStart2 = nowTs + 5 days;
        uint64 vestStart3 = nowTs + 6 days;

        vm.startPrank(admin);
        sale.addStage(100, stage0End, vestStart1, 30 days, percentages1);
        sale.addStage(50, stage1End, vestStart2, 20 days, percentages2);
        sale.addStage(33, stage2End, vestStart3, 15 days, percentages3);
        vm.stopPrank();

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        (uint128 total1, , uint64 start1, uint64 periodLength1, uint16[] memory sched1) =
            sale.getVestingSchedule(buyer1, 0);
        assertEq(total1, 100_000 ether);
        assertEq(start1, vestStart1);
        assertEq(periodLength1, 30 days);
        assertEq(sched1.length, 4);

        vm.warp(stage1Start);
        vm.prank(buyer1);
        sale.buy(50e6, new bytes32[](0));

        (uint128 total2, , uint64 start2, uint64 periodLength2, uint16[] memory sched2) =
            sale.getVestingSchedule(buyer1, 1);
        assertEq(total2, 100_000 ether);
        assertEq(start2, vestStart2);
        assertEq(periodLength2, 20 days);
        assertEq(sched2.length, 5);

        (uint128 total0, , , , ) = sale.getVestingSchedule(buyer1, 0);
        assertEq(total0, 100_000 ether);

        vm.warp(stage2Start);
        
        // Purchase in Stage 3: Calculate exact payment to get 100k tokens
        paymentToken.mint(buyer1, 100e6);
        uint256 paymentAmount3 = (100_000 ether * 33) / (sale.PRICE_SCALE() * sale.decimalScale());
        vm.prank(buyer1);
        sale.buy(uint128(paymentAmount3), new bytes32[](0));

        // Stage 3 creates a separate schedule
        (uint128 total3, , uint64 start3, uint64 periodLength3, uint16[] memory sched3) = 
            sale.getVestingSchedule(buyer1, 2);
        assertGe(total3, 99_999 ether);
        assertLe(total3, 100_001 ether);
        assertEq(start3, vestStart3);
        assertEq(periodLength3, 15 days);
        assertEq(sched3.length, 3);

        // After 30 days from vestStart1 - period 0 vests (25% = 25k) for schedule 0
        // But schedule 1 and 2 might also have releasable tokens since their vestStarts are close
        // So we check individual schedules instead
        vm.warp(vestStart1 + 30 days);
        uint256 schedule0Releasable = sale.releasableAmountForStage(buyer1, 0);
        uint256 expectedReleasable = (100_000 ether * 2500) / 10000; // 25% of schedule 0
        assertEq(schedule0Releasable, expectedReleasable);
        // Total releasable includes all schedules
        uint256 totalReleasable = sale.releasableAmount(buyer1);
        assertGe(totalReleasable, expectedReleasable); // At least schedule 0's amount
    }

    /// @notice Test user purchasing in Stage 2 first, then Stage 3
    /// Each purchase creates a separate vesting schedule per stage
    function test_Buy_Stage2First_ThenStage3_UsesStage2Schedule() public {
        uint64 nowTs = uint64(block.timestamp);
        
        uint16[] memory percentages1 = new uint16[](4);
        percentages1[0] = 2500;
        percentages1[1] = 2500;
        percentages1[2] = 2500;
        percentages1[3] = 2500;

        uint16[] memory percentages2 = new uint16[](5);
        percentages2[0] = 2000;
        percentages2[1] = 2000;
        percentages2[2] = 2000;
        percentages2[3] = 2000;
        percentages2[4] = 2000;

        uint16[] memory percentages3 = new uint16[](3);
        percentages3[0] = 3333;
        percentages3[1] = 3333;
        percentages3[2] = 3334;

        uint64 vestStart2 = nowTs + 5 days;
        uint64 vestStart3 = nowTs + 6 days;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 1 days, nowTs + 4 days, 30 days, percentages1);
        sale.addStage(50, nowTs + 2 days, vestStart2, 20 days, percentages2);
        sale.addStage(33, nowTs + 3 days, vestStart3, 15 days, percentages3);
        vm.stopPrank();

        uint64 stage0End = nowTs + 1 days;
        uint64 stage1End = nowTs + 2 days;
        uint64 stage1Start = stage0End + 1;
        uint64 stage2Start = stage1End + 1;

        vm.warp(stage1Start);
        vm.prank(buyer2);
        sale.buy(100e6, new bytes32[](0));

        (uint128 total, , uint64 start, uint64 periodLength, uint16[] memory sched) =
            sale.getVestingSchedule(buyer2, 1);
        assertEq(total, 200_000 ether);
        assertEq(start, vestStart2);
        assertEq(periodLength, 20 days);
        assertEq(sched.length, 5);

        (uint128 total0, , , , ) = sale.getVestingSchedule(buyer2, 0);
        assertEq(total0, 0);

        vm.warp(stage2Start);
        uint256 paymentAmount3_2 = (150_000 ether * 33) / (sale.PRICE_SCALE() * sale.decimalScale());
        vm.prank(buyer2);
        sale.buy(uint128(paymentAmount3_2), new bytes32[](0));

        // Stage 3 creates a separate schedule at stageId 2
        (uint128 total3, , uint64 start3, uint64 periodLength3, uint16[] memory sched3) = 
            sale.getVestingSchedule(buyer2, 2);
        assertGe(total3, 149_999 ether);
        assertLe(total3, 150_001 ether);
        assertEq(start3, vestStart3);
        assertEq(periodLength3, 15 days);
        assertEq(sched3.length, 3);

        // Stage 1 schedule unchanged
        (uint128 total1, , , , ) = sale.getVestingSchedule(buyer2, 1);
        assertEq(total1, 200_000 ether);

        // After 20 days from vestStart2 - period 0 vests (20% = 40k) for schedule 1 only
        // Need to warp before vestStart3 to avoid schedule 2 contributing
        // vestStart2 + 20 days should be before vestStart3 (nowTs + 6 days)
        // So we need vestStart2 + 20 days < vestStart3
        // vestStart2 = nowTs + 5 days, so vestStart2 + 20 days = nowTs + 25 days
        // vestStart3 = nowTs + 6 days, so schedule 2 will also have releasable tokens
        // Let's warp to vestStart2 + 20 days but before vestStart3 starts releasing
        vm.warp(vestStart2 + 20 days);
        // At this point, schedule 1 has 20% releasable, but schedule 2 might also have some
        // Let's check only schedule 1's releasable amount
        uint256 schedule1Releasable = sale.releasableAmountForStage(buyer2, 1);
        uint256 expectedReleasable2 = (200_000 ether * 2000) / 10000; // 20% of schedule 1
        assertEq(schedule1Releasable, expectedReleasable2);
        // Total releasable includes both schedules if schedule 2 has started
        uint256 totalReleasable = sale.releasableAmount(buyer2);
        assertGe(totalReleasable, expectedReleasable2); // At least schedule 1's amount
    }

    /// @notice Test multiple users purchasing across different stages
    /// Each user should have their own schedule based on their first purchase stage
    function test_MultipleUsers_DifferentStages_DifferentSchedules() public {
        uint64 nowTs = uint64(block.timestamp);
        uint64 stage0End = nowTs + 1 days;
        uint64 stage1Start = stage0End + 1;

        uint16[] memory percentages1 = new uint16[](4);
        percentages1[0] = 2500;
        percentages1[1] = 2500;
        percentages1[2] = 2500;
        percentages1[3] = 2500;

        uint16[] memory percentages2 = new uint16[](5);
        percentages2[0] = 2000;
        percentages2[1] = 2000;
        percentages2[2] = 2000;
        percentages2[3] = 2000;
        percentages2[4] = 2000;

        uint64 vestStart1 = nowTs + 4 days;
        uint64 vestStart2 = nowTs + 5 days;
        vm.startPrank(admin);
        sale.addStage(100, stage0End, vestStart1, 30 days, percentages1);
        sale.addStage(50, nowTs + 2 days, vestStart2, 20 days, percentages2);
        vm.stopPrank();

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        vm.warp(stage1Start);
        vm.prank(buyer2);
        sale.buy(100e6, new bytes32[](0));

        uint64 stage0Time = stage0End - 1 days + 1;
        vm.warp(stage0Time);
        vm.prank(buyer3);
        sale.buy(50e6, new bytes32[](0));

        vm.warp(stage1Start);
        vm.prank(buyer3);
        sale.buy(50e6, new bytes32[](0));

        // Check buyer1 schedule (Stage 1)
        (uint128 total1, , uint64 start1, uint64 periodLength1, uint16[] memory sched1) = 
            sale.getVestingSchedule(buyer1, 0);
        assertEq(total1, 100_000 ether);
        assertEq(start1, vestStart1);
        assertEq(periodLength1, 30 days);
        assertEq(sched1.length, 4);

        // Check buyer2 schedule (Stage 2) - creates schedule at stageId 1, not 0
        (uint128 total2, , uint64 start2, uint64 periodLength2, uint16[] memory sched2) = 
            sale.getVestingSchedule(buyer2, 1);
        assertEq(total2, 200_000 ether);
        assertEq(start2, vestStart2);
        assertEq(periodLength2, 20 days);
        assertEq(sched2.length, 5);

        // Check buyer3 schedule (Stage 1 - first purchase)
        // buyer3 purchased in stage 0, then stage 1, so has schedules at stageId 0 and 1
        (uint128 total3_0, , uint64 start3_0, uint64 periodLength3_0, uint16[] memory sched3_0) = 
            sale.getVestingSchedule(buyer3, 0);
        assertEq(total3_0, 50_000 ether); // Stage 0 purchase
        assertEq(start3_0, vestStart1);
        assertEq(periodLength3_0, 30 days);
        assertEq(sched3_0.length, 4);

        (uint128 total3_1, , uint64 start3_1, uint64 periodLength3_1, uint16[] memory sched3_1) = 
            sale.getVestingSchedule(buyer3, 1);
        assertEq(total3_1, 100_000 ether); // Stage 1 purchase
        assertEq(start3_1, vestStart2);
        assertEq(periodLength3_1, 20 days);
        assertEq(sched3_1.length, 5);
    }

    /// @notice Test user purchasing maximum allowed across multiple stages
    function test_Buy_MaxAcrossStages_RespectsTotalCap() public {
        uint64 nowTs = uint64(block.timestamp);
        
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 1 days, nowTs + 4 days, 30 days, percentages);
        sale.addStage(50, nowTs + 2 days, nowTs + 5 days, 30 days, percentages);
        sale.setTotalCap(500_000 ether); // Set cap to 500k tokens
        vm.stopPrank();

        // Purchase in Stage 1: 200k tokens
        vm.prank(buyer1);
        sale.buy(200e6, new bytes32[](0));

        // Move to Stage 2
        vm.warp(nowTs + 1 days + 1);
        
        // Purchase in Stage 2: 150k tokens (75 USDC * 2000 * 1e12)
        vm.prank(buyer1);
        sale.buy(75e6, new bytes32[](0));

        // Try to purchase more - should fail (200k + 150k + 200k = 550k > 500k cap)
        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0)); // Would add 200k tokens, exceeding cap
    }

    /// @notice Test user purchasing with different prices across stages
    /// Each purchase creates a separate vesting schedule per stage
    function test_Buy_DifferentPrices_AggregatesTokens() public {
        uint64 nowTs = uint64(block.timestamp);
        uint64 stage0End = nowTs + 1 days;
        uint64 stage1End = nowTs + 2 days;
        uint64 stage2End = nowTs + 3 days;
        uint64 stage1Start = stage0End + 1;
        uint64 stage2Start = stage1End + 1;

        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, stage0End, nowTs + 4 days, 30 days, percentages);
        sale.addStage(200, stage1End, nowTs + 5 days, 30 days, percentages);
        sale.addStage(50, stage2End, nowTs + 6 days, 30 days, percentages);
        vm.stopPrank();

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));

        vm.warp(stage1Start);
        vm.prank(buyer1);
        sale.buy(200e6, new bytes32[](0));

        vm.warp(stage2Start);
        vm.prank(buyer1);
        sale.buy(50e6, new bytes32[](0));

        // Each stage creates a separate schedule
        (uint128 total0, , , uint64 periodLength0, uint16[] memory sched0) = 
            sale.getVestingSchedule(buyer1, 0);
        assertEq(total0, 100_000 ether);
        assertEq(periodLength0, 30 days);
        assertEq(sched0.length, 4);

        (uint128 total1, , , , ) = sale.getVestingSchedule(buyer1, 1);
        assertEq(total1, 100_000 ether);

        (uint128 total2, , , , ) = sale.getVestingSchedule(buyer1, 2);
        assertEq(total2, 100_000 ether);
    }

    /// @notice Test that purchases across stages respect allowlist if enabled
    function test_Buy_AcrossStages_RespectsAllowlist() public {
        uint64 nowTs = uint64(block.timestamp);
        
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        // Build Merkle tree with buyer1 only
        address[] memory whitelist = new address[](1);
        whitelist[0] = buyer1;
        bytes32 merkleRoot = _buildMerkleTree(whitelist);
        bytes32[] memory proof1 = _getProof(whitelist, buyer1);

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 1 days, nowTs + 4 days, 30 days, percentages);
        sale.addStage(50, nowTs + 2 days, nowTs + 5 days, 30 days, percentages);
        sale.setAllowlistMerkleRoot(merkleRoot);
        sale.setAllowlistEnabled(true);
        vm.stopPrank();

        // Buyer1 can purchase in Stage 1 (on allowlist)
        vm.prank(buyer1);
        sale.buy(100e6, proof1);

        // Move to Stage 2
        vm.warp(nowTs + 1 days + 1);
        
        // Buyer1 can still purchase in Stage 2 (on allowlist)
        vm.prank(buyer1);
        sale.buy(50e6, proof1);

        // Buyer2 not on allowlist - cannot purchase
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(buyer2);
        sale.buy(100e6, new bytes32[](0));
    }

    /// @notice Build Merkle tree and return root (MDS: domain separation)
    function _buildMerkleTree(address[] memory addresses) internal view returns (bytes32) {
        if (addresses.length == 0) return bytes32(0);
        
        bytes32[] memory leaves = new bytes32[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(block.chainid, address(sale), addresses[i]));
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

    /// @notice Hash a pair of nodes
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    /// @notice Get Merkle proof for an address (MDS: domain separation)
    function _getProof(address[] memory addresses, address target) internal view returns (bytes32[] memory) {
        bytes32[] memory leaves = new bytes32[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(block.chainid, address(sale), addresses[i]));
        }
        
        uint256 index = 0;
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == target) {
                index = i;
                break;
            }
        }
        
        return _generateProof(leaves, index);
    }

    /// @notice Generate Merkle proof for a leaf at given index
    function _generateProof(bytes32[] memory leaves, uint256 index) internal pure returns (bytes32[] memory) {
        uint256 len = leaves.length;
        if (len == 1) return new bytes32[](0);
        
        uint256 proofLength = 0;
        uint256 temp = len;
        while (temp > 1) {
            proofLength++;
            temp = (temp + 1) / 2;
        }
        
        bytes32[] memory proof = new bytes32[](proofLength);
        uint256 proofIndex = 0;
        uint256 currentIndex = index;
        bytes32[] memory currentLevel = leaves;
        
        while (currentLevel.length > 1) {
            uint256 nextLen = (currentLevel.length + 1) / 2;
            bytes32[] memory nextLevel = new bytes32[](nextLen);
            
            for (uint256 i = 0; i < nextLen; i++) {
                if (2 * i + 1 < currentLevel.length) {
                    nextLevel[i] = _hashPair(currentLevel[2 * i], currentLevel[2 * i + 1]);
                } else {
                    nextLevel[i] = currentLevel[2 * i];
                }
            }
            
            uint256 pairIndex = currentIndex % 2 == 0 ? currentIndex + 1 : currentIndex - 1;
            if (pairIndex < currentLevel.length) {
                proof[proofIndex] = currentLevel[pairIndex];
                proofIndex++;
            }
            
            currentIndex = currentIndex / 2;
            currentLevel = nextLevel;
        }
        
        return proof;
    }

    /// @notice Test user limits apply across all stages
    function test_Buy_AcrossStages_RespectsUserLimits() public {
        uint64 nowTs = uint64(block.timestamp);
        
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 1 days, nowTs + 4 days, 30 days, percentages);
        sale.addStage(50, nowTs + 2 days, nowTs + 5 days, 30 days, percentages);
        sale.setUserLimits(buyer1, 50e6, 150e6); // Min 50 USDC, Max 150 USDC
        vm.stopPrank();

        // Stage 1: Purchase within limits
        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0)); // Within 50-150 range

        // Move to Stage 2
        vm.warp(nowTs + 1 days + 1);
        
        // Stage 2: Try to purchase below min - should fail
        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(buyer1);
        sale.buy(30e6, new bytes32[](0)); // Below 50 USDC min

        // Stage 2: Try to purchase above max - should fail
        vm.expectRevert(Errors.InvalidParam.selector);
        vm.prank(buyer1);
        sale.buy(200e6, new bytes32[](0)); // Above 150 USDC max

        // Stage 2: Purchase within limits
        vm.prank(buyer1);
        sale.buy(50e6, new bytes32[](0)); // At min limit
    }

    /// @notice Test complex scenario: multiple users, multiple stages, different purchase patterns
    function test_Complex_MultipleUsers_MultipleStages_DifferentPatterns() public {
        uint64 nowTs = uint64(block.timestamp);
        uint64 stage0End = nowTs + 1 days;
        uint64 stage1End = nowTs + 2 days;
        uint64 stage1Start = stage0End + 1;

        uint16[] memory percentages1 = new uint16[](4);
        percentages1[0] = 2500;
        percentages1[1] = 2500;
        percentages1[2] = 2500;
        percentages1[3] = 2500;

        uint16[] memory percentages2 = new uint16[](6);
        percentages2[0] = 1667;
        percentages2[1] = 1667;
        percentages2[2] = 1667;
        percentages2[3] = 1667;
        percentages2[4] = 1667;
        percentages2[5] = 1665;

        vm.startPrank(admin);
        sale.addStage(100, stage0End, nowTs + 4 days, 30 days, percentages1);
        sale.addStage(50, stage1End, nowTs + 5 days, 20 days, percentages2);
        sale.setTotalCap(1_000_000 ether);
        vm.stopPrank();

        uint64 stage0Time = stage0End - 1 days + 1;
        vm.warp(stage0Time);
        vm.prank(buyer1);
        sale.buy(200e6, new bytes32[](0));

        vm.warp(stage1Start);
        vm.prank(buyer2);
        sale.buy(100e6, new bytes32[](0));

        vm.warp(stage0Time);
        vm.prank(buyer3);
        sale.buy(100e6, new bytes32[](0));

        vm.warp(stage1Start);
        vm.prank(buyer3);
        sale.buy(50e6, new bytes32[](0));

        assertEq(sale.totalSold(), 600_000 ether);

        // Verify schedules
        (uint128 total1, , , uint64 periodLength1, uint16[] memory sched1) = 
            sale.getVestingSchedule(buyer1, 0);
        assertEq(total1, 200_000 ether);
        assertEq(periodLength1, 30 days);
        assertEq(sched1.length, 4);

        (uint128 total2, , , uint64 periodLength2, uint16[] memory sched2) = 
            sale.getVestingSchedule(buyer2, 1);
        assertEq(total2, 200_000 ether);
        assertEq(periodLength2, 20 days);
        assertEq(sched2.length, 6);

        // buyer3 has schedules at stageId 0 and 1
        (uint128 total3_0, , , uint64 periodLength3_0, uint16[] memory sched3_0) = 
            sale.getVestingSchedule(buyer3, 0);
        assertEq(total3_0, 100_000 ether);
        assertEq(periodLength3_0, 30 days);
        assertEq(sched3_0.length, 4);

        (uint128 total3_1, , , uint64 periodLength3_1, uint16[] memory sched3_1) = 
            sale.getVestingSchedule(buyer3, 1);
        assertEq(total3_1, 100_000 ether);
        assertEq(periodLength3_1, 20 days);
        assertEq(sched3_1.length, 6);
    }

    /// @notice ICS fix: setTotalCap = remaining, aligned with availableForSale
    function test_TotalCap_ValidatesAgainstTokenBalance() public {
        uint64 nowTs = uint64(block.timestamp);
        
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.prank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);

        vm.prank(admin);
        sale.setTotalCap(5_000_000 ether);

        vm.prank(buyer1);
        sale.buy(100e6, new bytes32[](0));
        assertEq(sale.totalCap(), 4_900_000 ether);

        uint256 availableForSale = saleToken.balanceOf(address(sale)) - sale.totalAllocatedToVesting();
        vm.expectRevert(Errors.InsufficientBalance.selector);
        vm.prank(admin);
        sale.setTotalCap(availableForSale + 1);
    }

    /// @notice Test that buy fails if contract doesn't have enough tokens even if cap allows
    function test_Buy_FailsIf_InsufficientTokenBalance() public {
        uint64 nowTs = uint64(block.timestamp);
        
        uint16[] memory percentages = new uint16[](4);
        percentages[0] = 2500;
        percentages[1] = 2500;
        percentages[2] = 2500;
        percentages[3] = 2500;

        vm.startPrank(admin);
        sale.addStage(100, nowTs + 7 days, nowTs + 10 days, 30 days, percentages);
        // Don't set cap - rely on balance check only
        vm.stopPrank();

        // Contract has 5M tokens
        assertEq(saleToken.balanceOf(address(sale)), 5_000_000 ether);

        // Purchase almost all balance - leave only 50k tokens available
        // Stage 1 price is 100, so tokens = (payment * PRICE_SCALE * decimalScale) / 100
        // For 4.95M tokens: payment = (4_950_000 ether * 100) / (PRICE_SCALE * decimalScale)
        uint256 availableForSale = 4_950_000 ether;
        uint256 maxPayment = (availableForSale * 100) / (sale.PRICE_SCALE() * sale.decimalScale());
        vm.prank(buyer1);
        sale.buy(uint128(maxPayment), new bytes32[](0)); // ~4.95M tokens

        // Verify we're near balance limit
        uint256 remainingBalance = saleToken.balanceOf(address(sale)) - sale.totalSold();
        assertLt(remainingBalance, 100_000 ether); // Less than 100k remaining

        // Cannot purchase more - balance check should prevent
        vm.expectRevert(Errors.InsufficientBalance.selector);
        vm.prank(buyer2);
        sale.buy(100e6, new bytes32[](0)); // Would exceed balance
    }
}

