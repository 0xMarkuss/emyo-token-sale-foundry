// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {Roles} from "../access/Roles.sol";
import {Errors} from "../libs/Errors.sol";
import {VestingLibrary} from "../vesting/VestingLibrary.sol";

/// @title TokenSale
/// @notice Multi-stage sale with integrated schedule-based vesting.
contract TokenSale is AccessControl, Pausable {
    using SafeERC20 for IERC20;
    using VestingLibrary for VestingLibrary.Schedule;

    /// @notice Price scale constant: 100000 = $1.00, 1 = $0.00001
    uint256 public constant PRICE_SCALE = 100000;
    
    /// @notice Maximum number of stages allowed
    uint256 public constant MAX_STAGES = 100;

    struct Stage {
        uint256 emyPriceUsd;
        uint64 end;
        uint64 vestStart;
        uint64 vestPeriodLength;
        uint16[] vestPercentages;
    }

    struct PurchaseConfig {
        uint128 min;
        uint128 max;
    }

    // ============ State Variables ============

    IERC20 public immutable paymentToken;
    IERC20 public immutable saleToken;
    address public immutable treasury;
    uint256 public immutable decimalScale;

    Stage[] public stages;
    /// @notice Remaining tokens available for sale. type(uint256).max = no cap. When > 0 and < max, decremented on each purchase.
    uint256 public totalCap = type(uint256).max;
    uint256 public totalSold;
    uint256 public totalAllocatedToVesting;
    mapping(address => PurchaseConfig) public userLimits;
    mapping(address => uint256) public totalPurchasedByUser;
    bytes32 public allowlistMerkleRoot;
    bool public allowlistEnabled;
    mapping(address => mapping(uint256 => VestingLibrary.Schedule)) public vestingSchedules;
    mapping(address => uint256[]) public userStages;

    event StageAdded(
        uint256 indexed id,
        uint256 emyPriceUsd,
        uint64 end,
        uint64 vestStart,
        uint64 vestPeriodLength,
        uint16[] vestPercentages
    );
    event Purchased(address indexed buyer, uint256 indexed stageId, uint256 payment, uint256 tokens);
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event VestingScheduleCreated(
        address indexed beneficiary,
        uint256 indexed stageId,
        uint128 total,
        uint64 start,
        uint64 periodLength,
        uint16[] percentages
    );
    event VestingScheduleUpdated(
        address indexed beneficiary,
        uint256 indexed stageId,
        uint128 newTotal,
        uint128 addedAmount
    );
    event AllowlistMerkleRootSet(bytes32 indexed merkleRoot);
    event AllowlistEnabledSet(bool enabled);
    event TotalCapSet(uint256 cap);
    event UserLimitsSet(address indexed account, uint128 min, uint128 max);
    event UndistributedTokensWithdrawn(address indexed to, uint256 amount);

    constructor(
        IERC20 paymentToken_,
        IERC20 saleToken_,
        address treasury_,
        address admin
    ) {
        if (address(paymentToken_) == address(0) || address(saleToken_) == address(0) || treasury_ == address(0) || admin == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (address(paymentToken_) == address(saleToken_)) revert Errors.PaymentTokenCannotEqualSaleToken();
        paymentToken = paymentToken_;
        saleToken = saleToken_;
        treasury = treasury_;

        uint8 payDec = IERC20Metadata(address(paymentToken_)).decimals();
        uint8 saleDec = IERC20Metadata(address(saleToken_)).decimals();
        if (saleDec < payDec) revert Errors.InvalidParam();
        decimalScale = 10 ** (saleDec - payDec);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(Roles.PAUSER_ROLE, admin);
        _grantRole(Roles.SALE_ADMIN_ROLE, admin);
    }

    // ============ External Functions ============

    /// @notice Buy tokens at the current active stage, paying with `paymentToken`.
    /// @param paymentAmount Amount of payment token to spend.
    /// @param merkleProof Merkle proof for the buyer's address (required if allowlist is enabled, can be empty array if disabled).
    /// @dev Each stage purchase creates a separate vesting schedule for the user.
    /// @dev If user buys at stage 0 and stage 1, tokens will be released according to their respective schedules.
    function buy(uint128 paymentAmount, bytes32[] calldata merkleProof) external whenNotPaused {
        if (paymentAmount == 0) revert Errors.ZeroAmount();

        (bool active, uint256 stageId, Stage memory st) = _currentStage();
        if (!active) revert Errors.NotStarted();
        
        if (allowlistEnabled) {
            if (allowlistMerkleRoot == bytes32(0)) revert Errors.InvalidParam();
            bytes32 leaf = keccak256(abi.encodePacked(block.chainid, address(this), msg.sender));
            if (!MerkleProof.verifyCalldata(merkleProof, allowlistMerkleRoot, leaf)) {
                revert Errors.NotAuthorized();
            }
        }

        PurchaseConfig memory lim = userLimits[msg.sender];
        if (lim.min > 0 && paymentAmount < lim.min) revert Errors.InvalidParam();
        if (lim.max > 0 && totalPurchasedByUser[msg.sender] + paymentAmount > lim.max) revert Errors.InvalidParam();

        uint256 tokensOut = (uint256(paymentAmount) * PRICE_SCALE * decimalScale) / uint256(st.emyPriceUsd);
        if (tokensOut == 0) revert Errors.InvalidParam();
        if (tokensOut > type(uint128).max) revert Errors.InvalidParam();
        if (totalCap != type(uint256).max && (tokensOut > totalCap || totalCap == 0)) revert Errors.InvalidParam();

        uint256 availableBalance = saleToken.balanceOf(address(this));
        if (totalAllocatedToVesting + tokensOut > availableBalance) revert Errors.InsufficientBalance();

        totalSold += tokensOut;
        if (totalCap != type(uint256).max) totalCap -= tokensOut;
        totalAllocatedToVesting += tokensOut;
        totalPurchasedByUser[msg.sender] += paymentAmount;
        _updateVestingSchedule(msg.sender, stageId, uint128(tokensOut), st.vestStart, st.vestPeriodLength, st.vestPercentages);
        paymentToken.safeTransferFrom(msg.sender, treasury, paymentAmount);

        emit Purchased(msg.sender, stageId, paymentAmount, tokensOut);
    }

    /// @notice Release vested tokens to beneficiary from all schedules.
    function release() external whenNotPaused returns (uint256 amount) {
        return _release(msg.sender);
    }

    // ============ Admin Functions ============

    /// @notice Add a new sale stage with vesting parameters.
    /// @param emyPriceUsd EMY price in USD, scaled by PRICE_SCALE (100_000). NOT payment token decimals.
    ///                    Examples (PRICE_SCALE = 100_000): 
    ///                    - 100_000 = $1.00 per EMY (1 USDC = 1 EMY)
    ///                    - 1 = $0.00001 per EMY
    ///                    - 125_000 = $1.25 per EMY
    /// @param end Stage end timestamp
    /// @param vestStart Vesting start timestamp (same for all users in this stage)
    /// @param vestPeriodLength Length of each vesting period
    /// @param vestPercentages Array of percentages per period (basis points, must sum to 10000)
    /// @dev Contract automatically handles decimals conversion via decimalScale.
    /// @dev Price calculation: tokensOut = (paymentAmount * PRICE_SCALE * decimalScale) / emyPriceUsd
    /// @dev All users who buy in this stage will start vesting at vestStart time.
    function addStage(
        uint256 emyPriceUsd,
        uint64 end,
        uint64 vestStart,
        uint64 vestPeriodLength,
        uint16[] calldata vestPercentages
    ) external onlyRole(Roles.SALE_ADMIN_ROLE) {
        if (stages.length >= MAX_STAGES) revert Errors.MaxStagesReached();
        if (emyPriceUsd == 0 || end == 0) revert Errors.InvalidParam();
        if (emyPriceUsd > 1e18) revert Errors.InvalidEmyPriceUsd();
        if (vestStart <= end) revert Errors.VestStartMustBeAfterStageEnd();
        if (vestPeriodLength == 0) revert Errors.InvalidPeriodLength();
        if (!VestingLibrary.validatePercentages(vestPercentages)) revert Errors.InvalidVestingSchedule();
        if (end <= block.timestamp) revert Errors.InvalidStageTiming();
        if (stages.length > 0) {
            if (end <= stages[stages.length - 1].end) revert Errors.InvalidParam();
        }
        stages.push(Stage({
            emyPriceUsd: emyPriceUsd,
            end: end,
            vestStart: vestStart,
            vestPeriodLength: vestPeriodLength,
            vestPercentages: vestPercentages
        }));
        emit StageAdded(stages.length - 1, emyPriceUsd, end, vestStart, vestPeriodLength, vestPercentages);
    }

    /// @notice Set per-user limits (optional).
    function setUserLimits(address user, uint128 minPayment, uint128 maxPayment) external onlyRole(Roles.SALE_ADMIN_ROLE) {
        if (user == address(0)) revert Errors.ZeroAddress();
        if (maxPayment > 0 && maxPayment < minPayment) revert Errors.InvalidParam();
        userLimits[user] = PurchaseConfig({min: minPayment, max: maxPayment});
        emit UserLimitsSet(user, minPayment, maxPayment);
    }

    /// @notice Set the Merkle root for the allowlist.
    /// @param merkleRoot The Merkle root hash of all whitelisted addresses.
    function setAllowlistMerkleRoot(bytes32 merkleRoot) external onlyRole(Roles.SALE_ADMIN_ROLE) {
        allowlistMerkleRoot = merkleRoot;
        emit AllowlistMerkleRootSet(merkleRoot);
    }

    /// @notice Enable or disable the allowlist check.
    function setAllowlistEnabled(bool enabled) external onlyRole(Roles.SALE_ADMIN_ROLE) {
        allowlistEnabled = enabled;
        emit AllowlistEnabledSet(enabled);
    }

    /// @notice Set remaining tokens available for sale.
    /// @dev totalCap = remaining to sell; buy() checks tokensOut <= totalCap and decrements totalCap.
    /// @dev Cap cannot exceed tokens available for sale (balance minus vesting allocations).
    /// @param cap Remaining tokens that may be sold. Use type(uint256).max to disable cap.
    function setTotalCap(uint256 cap) external onlyRole(Roles.SALE_ADMIN_ROLE) {
        if (cap == 0) revert Errors.InvalidParam();
        if (cap != type(uint256).max) {
            uint256 availableBalance = saleToken.balanceOf(address(this));
            uint256 availableForSale = availableBalance - totalAllocatedToVesting;
            if (cap > availableForSale) revert Errors.InsufficientBalance();
        }
        totalCap = cap;
        emit TotalCapSet(cap);
    }

    /// @notice Pause token sale.
    function pause() external onlyRole(Roles.PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause token sale.
    function unpause() external onlyRole(Roles.PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Admin release vested tokens for a beneficiary from all schedules.
    function releaseFor(address beneficiary) external whenNotPaused onlyRole(Roles.SALE_ADMIN_ROLE) returns (uint256 amount) {
        if (beneficiary == address(0)) revert Errors.ZeroAddress();
        return _release(beneficiary);
    }

    /// @notice Withdraw undistributed tokens after all stages have ended.
    /// @param to Address to receive the undistributed tokens.
    /// @dev Can only be called after all stages have ended.
    /// @dev Only withdraws tokens that are not allocated to vesting schedules.
    function withdrawUndistributedTokens(address to) external onlyRole(Roles.SALE_ADMIN_ROLE) {
        if (to == address(0)) revert Errors.ZeroAddress();
        if (!isSaleEnded()) revert Errors.SaleNotEnded();
        
        uint256 balance = saleToken.balanceOf(address(this));
        if (balance <= totalAllocatedToVesting) revert Errors.ZeroAmount();
        
        uint256 amount = balance - totalAllocatedToVesting;
        saleToken.safeTransfer(to, amount);
        emit UndistributedTokensWithdrawn(to, amount);
    }

    // ============ View Functions ============

    /// @notice Compute total releasable amount for a beneficiary across all schedules.
    function releasableAmount(address beneficiary) public view returns (uint256) {
        uint256[] storage userStageIds = userStages[beneficiary];
        uint256 len = userStageIds.length;
        uint256 total = 0;
        
        for (uint256 i = 0; i < len; i++) {
            uint256 stageId = userStageIds[i];
            VestingLibrary.Schedule storage s = vestingSchedules[beneficiary][stageId];
            if (s.total == 0) continue;
            total += VestingLibrary.releasableAmount(s, uint64(block.timestamp));
        }
        
        return total;
    }
    
    /// @notice Compute releasable amount for a beneficiary for a specific stage.
    function releasableAmountForStage(address beneficiary, uint256 stageId) public view returns (uint256) {
        VestingLibrary.Schedule storage s = vestingSchedules[beneficiary][stageId];
        if (s.total == 0) return 0;
        return VestingLibrary.releasableAmount(s, uint64(block.timestamp));
    }

    /// @notice Get vesting schedule for a beneficiary for a specific stage.
    function getVestingSchedule(address beneficiary, uint256 stageId) external view returns (
        uint128 total,
        uint128 released,
        uint64 start,
        uint64 periodLength,
        uint16[] memory percentages
    ) {
        VestingLibrary.Schedule storage s = vestingSchedules[beneficiary][stageId];
        return (s.total, s.released, s.start, s.periodLength, s.percentages);
    }
    
    /// @notice Get all stage IDs where a beneficiary has vesting schedules.
    function getUserStages(address beneficiary) external view returns (uint256[] memory) {
        return userStages[beneficiary];
    }

    /// @notice Get current active stage index.
    /// @return stageId Current active stage index, or type(uint256).max if no active stage.
    function getCurrentStageId() public view returns (uint256 stageId) {
        uint64 nowTs = uint64(block.timestamp);
        uint256 len = stages.length;
        for (uint256 i = 0; i < len; i++) {
            if (nowTs <= stages[i].end) {
                return i;
            }
        }
        return type(uint256).max;
    }

    /// @notice Get total number of stages.
    /// @return count Total number of stages added.
    function getStagesCount() public view returns (uint256 count) {
        return stages.length;
    }

    /// @notice Check if all sale stages have ended.
    /// @return True if all stages have ended, false otherwise.
    function isSaleEnded() public view returns (bool) {
        if (stages.length == 0) return false;
        uint64 nowTs = uint64(block.timestamp);
        uint256 len = stages.length;
        for (uint256 i = 0; i < len; i++) {
            if (nowTs <= stages[i].end) {
                return false;
            }
        }
        return true;
    }

    /// @notice Get amount of undistributed tokens available for withdrawal.
    /// @return Amount of tokens that can be withdrawn (contract balance minus allocated to vesting).
    function getUndistributedTokens() public view returns (uint256) {
        uint256 balance = saleToken.balanceOf(address(this));
        if (balance <= totalAllocatedToVesting) return 0;
        return balance - totalAllocatedToVesting;
    }

    // ============ Internal Functions ============

    /// @notice Internal function to release vested tokens for a beneficiary from all schedules.
    function _release(address beneficiary) internal returns (uint256 amount) {
        amount = releasableAmount(beneficiary);
        if (amount == 0) return 0;
        
        uint256[] storage userStageIds = userStages[beneficiary];
        uint256 len = userStageIds.length;
        uint256 remaining = amount;
        
        for (uint256 i = 0; i < len && remaining > 0; i++) {
            uint256 stageId = userStageIds[i];
            VestingLibrary.Schedule storage s = vestingSchedules[beneficiary][stageId];
            if (s.total == 0) continue;
            
            uint256 releasable = VestingLibrary.releasableAmount(s, uint64(block.timestamp));
            if (releasable == 0) continue;
            
            uint256 toRelease = releasable < remaining ? releasable : remaining;
            if (toRelease > type(uint128).max) revert Errors.InvalidParam();
            if (s.released > type(uint128).max - uint128(toRelease)) revert Errors.InvalidParam();
            s.released += uint128(toRelease);
            remaining -= toRelease;
        }
        if (remaining != 0) revert Errors.InvalidParam();
        
        if (totalAllocatedToVesting >= amount) {
            totalAllocatedToVesting -= amount;
        } else {
            totalAllocatedToVesting = 0;
        }
        saleToken.safeTransfer(beneficiary, amount);
        emit TokensReleased(beneficiary, amount);
    }

    /// @notice Create or update vesting schedule for a beneficiary for a specific stage.
    /// @dev All users who buy in the same stage share the same vestStart time.
    /// @dev Multiple purchases by the same user in the same stage are summed into one schedule.
    function _updateVestingSchedule(
        address beneficiary,
        uint256 stageId,
        uint128 amount,
        uint64 vestStart,
        uint64 vestPeriodLength,
        uint16[] memory vestPercentages
    ) internal {
        VestingLibrary.Schedule storage s = vestingSchedules[beneficiary][stageId];
        
        if (s.total == 0) {
            s.start = vestStart;
            s.periodLength = vestPeriodLength;
            s.percentages = vestPercentages;
            s.total = amount;
            userStages[beneficiary].push(stageId);
            emit VestingScheduleCreated(beneficiary, stageId, amount, vestStart, vestPeriodLength, vestPercentages);
        } else {
            if (s.total > type(uint128).max - amount) revert Errors.InvalidParam();
            s.total += amount;
            emit VestingScheduleUpdated(beneficiary, stageId, s.total, amount);
        }
    }

    /// @notice Returns current active stage if any.
    function _currentStage() internal view returns (bool active, uint256 stageId, Stage memory st) {
        uint64 nowTs = uint64(block.timestamp);
        uint256 len = stages.length;
        for (uint256 i = 0; i < len; i++) {
            Stage memory s = stages[i];
            if (nowTs <= s.end) {
                return (true, i, s);
            }
        }
        return (false, 0, st);
    }
}
