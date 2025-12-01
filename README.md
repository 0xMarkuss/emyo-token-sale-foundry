# Emyo Token Sale System

A secure, production-ready token sale system with integrated schedule-based vesting, built with Foundry and Solidity 0.8.24.

## Overview

The Emyo Token Sale System provides a comprehensive solution for conducting multi-stage token sales with flexible vesting schedules. The system includes:

- **TokenSale**: Multi-stage token sale with integrated vesting
- **Treasury**: Secure token custody with vesting-based distribution
- **VestingLibrary**: Reusable library for schedule-based vesting calculations
- **StakingRewards**: Single-sided staking with continuous rewards
- **EmyoToken**: ERC20 token with permit functionality

## Features

- ? Multi-stage token sales with configurable pricing
- ? Schedule-based vesting (non-linear, percentage-based)
- ? Role-based access control (OpenZeppelin)
- ? Pausable functionality for emergency stops
- ? Comprehensive security fixes (all audit issues resolved)
- ? Full test coverage (224 tests)
- ? Gas-optimized with custom errors

## Security

All critical, high, medium, and low severity issues from security audits have been fixed and verified. The codebase is ready for external audit.

**Security Features:**
- Reentrancy protection (SafeERC20 + Checks-Effects-Interactions)
- Access control (OpenZeppelin AccessControl)
- Integer safety (Solidity 0.8.24 + explicit checks)
- Input validation (comprehensive checks)
- Balance accounting (prevents over-allocation)

See `docs/FINAL_AUDIT_SUMMARY.md` for complete security audit details.

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js (for dependencies)

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd emyo-token-sale-foundry

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test
```

### Environment Setup

Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
```

See `.env.example` for required environment variables.

## Usage

### TokenSale Contract

#### Adding a Sale Stage

```solidity
// Stage 1: $1.00 per EMY, ends in 7 days, 4 periods of 25% each
uint16[] memory percentages = new uint16[](4);
percentages[0] = 2500; // 25%
percentages[1] = 2500; // 25%
percentages[2] = 2500; // 25%
percentages[3] = 2500; // 25%

sale.addStage(
    100000,                    // Price: 100000 = $1.00 per EMY
    block.timestamp + 7 days,  // End time
    30 days,                   // Vesting period length
    percentages                // Vesting schedule
);
```

**Price Calculation:**
- `PRICE_SCALE = 100000` (represents $1.00)
- `100000` = $1.00 per EMY
- `1` = $0.00001 per EMY
- `125000` = $1.25 per EMY

**Formula:** `tokensOut = (paymentAmount * PRICE_SCALE * decimalScale) / emyPriceUsd`

#### Buying Tokens

```solidity
// User buys tokens with USDC
sale.buy(1000e6); // 1000 USDC (6 decimals)
```

#### Releasing Vested Tokens

```solidity
// User releases their vested tokens
uint256 amount = sale.release();
```

### Treasury Contract

#### Setting Vesting Schedule

```solidity
uint16[] memory percentages = new uint16[](4);
percentages[0] = 2500;
percentages[1] = 2500;
percentages[2] = 2500;
percentages[3] = 2500;

treasury.setVestingSchedule(
    token,
    beneficiary,
    1_000_000 ether,           // Total amount
    block.timestamp,           // Start time
    30 days,                   // Period length
    percentages                // Schedule
);
```

#### Releasing Tokens

```solidity
// Beneficiary releases vested tokens
treasury.release(token);
```

## Contract Architecture

### TokenSale

Multi-stage token sale with integrated vesting. Each stage can have:
- Different pricing
- Different vesting schedules
- Configurable end times

**Key Features:**
- Per-user purchase limits
- Allowlist support
- Total cap management
- Automatic vesting schedule creation

### Treasury

Secure custody of tokens with vesting-based distribution. Supports:
- Direct transfers (no vesting)
- Schedule-based vesting
- Emergency revoke functionality

### VestingLibrary

Reusable library for vesting calculations:
- Schedule-based (percentage per period)
- Non-linear vesting support
- Efficient gas usage

## Testing

Run all tests:
```bash
forge test
```

Run with verbosity:
```bash
forge test -vvv
```

Run specific test:
```bash
forge test --match-test test_Buy_Success
```

Test coverage:
- 224 tests passing
- Unit tests for all modules
- Integration tests
- E2E scenarios
- Security edge cases

## Deployment

### Development Deployment

```bash
forge script script/DevDeploy.s.sol:DevDeploy --rpc-url <RPC_URL> --broadcast
```

### Production Deployment

1. Update deployment script with production addresses
2. Set up multisig for admin roles
3. Configure RPC endpoints in `foundry.toml`
4. Deploy with appropriate network

## Documentation

- `docs/architecture.md` - System architecture
- `docs/USAGE_GUIDE.md` - Detailed usage guide
- `docs/FINAL_AUDIT_SUMMARY.md` - Security audit summary
- `docs/SECURITY_AUDIT.md` - Original security audit
- `docs/FINAL_SECURITY_AUDIT.md` - Post-fix audit

## Project Structure

```
emyo-token-sale-foundry/
??? src/
?   ??? sale/          # TokenSale contract
?   ??? treasury/      # Treasury contract
?   ??? vesting/       # Vesting contracts and library
?   ??? staking/       # StakingRewards contract
?   ??? token/         # EmyoToken contract
?   ??? access/        # Roles definitions
?   ??? libs/          # Error definitions
?   ??? interfaces/    # Contract interfaces
??? test/              # Test files
??? script/            # Deployment scripts
??? docs/              # Documentation
```

## Tips for Using Contracts

### TokenSale Tips

1. **Stage Timing**: Ensure stage `end` times are monotonically increasing
2. **Vesting Percentages**: Must sum to 10000 (100%)
3. **Price Precision**: Use `PRICE_SCALE` (100000) for $1.00
4. **Balance Management**: Contract tracks `totalAllocatedToVesting` to prevent over-allocation
5. **First Purchase**: Sets the vesting schedule for all subsequent purchases by the same user

### Treasury Tips

1. **Balance Verification**: Contract verifies sufficient balance before creating schedules
2. **Schedule Uniqueness**: Cannot overwrite existing schedules (use `increaseVestingSchedule` instead)
3. **Emergency Revoke**: Only works if no tokens have been released yet
4. **Direct Transfers**: Use `withdrawERC20` for non-vested distributions

### Vesting Tips

1. **Period Calculation**: Uses `(timestamp - start) / periodLength` to determine periods elapsed
2. **No Immediate Vesting**: First period vests only after `periodLength` has passed
3. **Final Period**: Always returns `s.total` when all periods have elapsed
4. **Percentage Validation**: Must sum to exactly 10000 (100%)

## Security Considerations

- All admin functions are protected by role-based access control
- Pausable functionality for emergency stops
- SafeERC20 used for all token transfers
- Checks-Effects-Interactions pattern followed
- Comprehensive input validation
- Balance accounting prevents over-allocation

## Contributing

1. Follow Solidity style guide
2. Write tests for new features
3. Update documentation
4. Run `forge fmt` before committing
5. Ensure all tests pass

## License

MIT

## Support

For questions or issues, please refer to the documentation in the `docs/` directory or open an issue.
