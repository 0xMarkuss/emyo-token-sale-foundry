# Emyo Token Sale System

Solidity 0.8.24 smart contract suite for a multi-stage token sale with integrated vesting, treasury custody, and staking rewards.

## Product Overview

Emyo is a token sale and distribution platform. Buyers purchase tokens with a payment token (e.g. USDC) and receive allocations that vest over time according to configurable schedules. The system includes:

- **TokenSale** - Multi-stage sale with stage-specific pricing and vesting. Purchases create vesting schedules; users claim vested tokens over time.
- **Treasury** - Token custody for direct withdrawals and vesting-based distributions (e.g. team, advisors).
- **Vesting** - Standalone vesting vault for a single ERC20 token.
- **StakingRewards** - Single-sided staking with configurable reward rate.
- **EmyoToken** - Fixed-supply ERC20 with permit and pausable transfers.

## Contracts

| Contract | Purpose |
|----------|---------|
| `TokenSale` | Sale stages, buy, vesting schedules, release, allowlist, caps |
| `Treasury` | Hold tokens, vesting schedules, release, withdraw, revoke |
| `Vesting` | Vesting vault with admin-created schedules |
| `StakingRewards` | Stake, withdraw, earn and claim rewards |
| `VestingLibrary` | Shared vesting math (vested amount, releasable, validation) |
| `EmyoToken` | ERC20 minted to treasury |

## Build & Test

```bash
forge install
forge build
forge test
```

## Security

- Access control: OpenZeppelin `AccessControl` with roles (PAUSER, SALE_ADMIN, TREASURY, STAKING_ADMIN, VESTING_ADMIN)
- Pausable: Admin can pause critical flows
- SafeERC20 for all token transfers
- Checks-Effects-Interactions pattern
- Balance accounting: `totalAllocatedToVesting`, `_totalVestingObligations`, `_totalObligations` to prevent over-allocation

## Project Structure

```
src/
  sale/       TokenSale
  treasury/   Treasury
  vesting/    Vesting, VestingLibrary
  staking/    StakingRewards
  token/      EmyoToken
  access/     Roles
  libs/       Errors
  interfaces/
test/
script/
```

## License

MIT
