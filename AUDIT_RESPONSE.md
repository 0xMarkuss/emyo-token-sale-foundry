# Audit Response - Operational Findings

**Purpose:** Acknowledge operational/admin findings and document mitigation plan for re-audit.

---

## Acknowledged Findings (Operational)

The following findings relate to key management and admin centralization. They are **acknowledged** and will be addressed through deployment and operational procedures, not contract code changes.

| ID | Finding | Severity | Status |
|----|---------|----------|--------|
| ST | Stops Transactions (EmyoToken pause) | Critical | Acknowledged |
| PF | Pausable Functionality | Medium | Acknowledged |
| OCTD | Transfers Contract's Tokens | Medium | Acknowledged |
| CCR | Contract Centralization Risk | Minor | Acknowledged |
| MPC | Merkle Proof Centralization | Minor | Acknowledged |
| TL | Targeted Limitation | Minor | Acknowledged |
| AME | Address Manipulation Exploit | Minor | Acknowledged |

---

## Planned Mitigation

### Phase 1: Deployment (Temporary Solutions)

- Use a **multi-signature wallet** (e.g. Gnosis Safe) as the admin for all roles:
  - `DEFAULT_ADMIN_ROLE`
  - `PAUSER_ROLE`
  - `SALE_ADMIN_ROLE`
  - `TREASURY_ROLE`
  - `STAKING_ADMIN_ROLE`
  - `VESTING_ADMIN_ROLE`
- Require multiple signers for any admin action.
- This reduces single-point-of-failure risk as recommended by the audit.

### Phase 2: Post-Launch (Permanent Solution)

- After all parameters are set and the sale/staking/vesting setup is complete:
  - **Renounce admin rights** by revoking all roles from the multisig.
- This is non-reversible and removes the ability to pause, withdraw, or change configuration.
- Contracts will then operate in a fully permissionless way.

---

## Implementation Notes

1. **Multisig setup:** Execute before mainnet deployment.
2. **Timelock:** Consider adding a timelock for critical admin actions if supported by the multisig.
3. **Renounce window:** Renounce only after:
   - Sale stages and caps are configured
   - Treasury vesting schedules are set
   - Staking reward parameters are finalized
   - All operational checks are complete

---

## For Auditors

These findings are **acknowledged** with a documented mitigation plan. The team commits to:

1. Using a multisig for all admin roles at deployment.
2. Renouncing admin rights after setup is complete.

No contract code changes are required; security is addressed through operational controls as recommended.
