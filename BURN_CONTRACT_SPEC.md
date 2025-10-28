# Bittensor EVM Burn Contract Specification

## Overview
This specification defines a minimal, trustless smart contract for the Bittensor network that burns all native tokens (TAO) it holds by utilizing a precompiled contract. The contract includes a gas reimbursement mechanism to incentivize anyone to trigger burns.

## Contract Name
`Sink`

## Design Principles
- **No administrative functions** - No owners, no pause, no upgrades
- **Fully autonomous** - Anyone can trigger burns
- **Incentivized execution** - Callers are reimbursed for gas costs
- **Minimal attack surface** - Single public function, no state variables
- **Immutable** - Once deployed, behavior cannot be changed

## Functional Requirements

### Core Functionality
The contract must:
1. **Unstake** all staked tokens via an unstake precompile
2. **Burn** all unstaked tokens by sending them to `address(0)`
3. Reimburse the caller for gas costs
4. Emit events for tracking burn operations
5. Accept tokens only via forced sends (no receive/fallback functions)

### Key Design Decision: No receive() Function
The contract intentionally **does not implement** `receive()` or `fallback()` functions. Tokens can only enter the contract through:
- Forced sends (selfdestruct from another contract)
- Coinbase transactions (if contract address is miner/validator)
- Pre-funded before deployment

This simplifies the contract and prevents accidental deposits.

### Staking Context
On Bittensor, tokens received by the contract will be **staked tokens**. Before burning, the contract must:
1. Call the **unstake precompile** to convert staked tokens to liquid tokens
2. Then send liquid tokens to **`address(0)`** to burn them

This two-step process ensures proper token lifecycle management on the Bittensor network.

### Precompile Interface

#### Unstake Precompile
**Assumed Precompile Address:** `0x0000000000000000000000000000000000000801` (verify with Bittensor documentation)

**Precompile Function Signature:**
```solidity
function unstake(uint256 amount) external returns (bool);
```

The unstake precompile converts staked TAO to liquid TAO.

#### Burn Mechanism
Tokens are burned by sending them to `address(0)`:
```solidity
(bool success,) = payable(address(0)).call{value: amount}("");
```

This permanently removes the tokens from circulation as `address(0)` is a black hole address that cannot spend tokens.

## Technical Specification

### State Variables
```solidity
address private constant UNSTAKE_PRECOMPILE = 0x0000000000000000000000000000000000000801;
uint256 private constant REIMBURSEMENT_BUFFER = 90000; // Covers unstake + send to address(0) operations
```

**No other state variables** - The contract is completely stateless to minimize gas costs and attack surface.

### Events
```solidity
event Burned(
    uint256 amountUnstaked,
    uint256 amountBurned,
    uint256 gasReimbursement,
    address indexed caller,
    uint256 timestamp
);
```

### Functions

#### burnAll()
```solidity
function burnAll() external returns (bool)
```

**Behavior:**
1. Records starting gas: `uint256 startGas = gasleft()`
2. Calculates available balance: `uint256 balance = address(this).balance`
3. Estimates total gas cost for the transaction
4. Calculates gas reimbursement amount: `gasReimbursement = (gasUsed + buffer) * tx.gasprice`
5. **Unstakes** all staked tokens via unstake precompile
6. Sends gas reimbursement to `msg.sender`
7. **Burns** remaining liquid balance by sending to `address(0)`
8. Emits `Burned` event (with unstaked and burned amounts)
9. Returns success status

**Access Control:** Public - anyone can call

**Gas Reimbursement Formula:**
```solidity
uint256 gasUsed = startGas - gasleft() + REIMBURSEMENT_BUFFER;
uint256 gasReimbursement = gasUsed * tx.gasprice;
uint256 amountToBurn = balance - gasReimbursement;
```

**REIMBURSEMENT_BUFFER:** Additional gas units (e.g., 90,000) to cover:
- Gas for the **unstake** precompile call (~30k)
- Gas for the reimbursement transfer itself (~21k)
- Gas for the **send to address(0)** (~21k)
- Gas for event emission (~5k)
- Safety margin

**Error Conditions:**
- Reverts if balance is less than estimated gas cost (nothing to burn)
- Reverts if **unstake** precompile call fails
- Reverts if **send to address(0)** fails (extremely unlikely)

## Contract Behavior

### Burn Flow
1. Anyone calls `burnAll()`
2. Contract calculates gas reimbursement needed
3. **Contract calls unstake precompile** to convert staked TAO to liquid TAO
4. Contract sends gas reimbursement to caller
5. **Contract sends remaining liquid balance to address(0)** to permanently burn tokens
6. Tokens sent to address(0) are permanently removed from circulation (address(0) is a black hole)
7. `Burned` event is emitted with unstaked amount, burned amount, and gas reimbursement

### Example Scenario
```
Initial contract balance (staked): 10 TAO
Gas used: 80,000 units
Gas price: 20 gwei
Reimbursement buffer: 90,000 units

Total gas for reimbursement: (80,000 + 90,000) * 20 gwei = 0.0034 TAO
Amount unstaked: 10 TAO
Gas reimbursement sent to caller: 0.0034 TAO
Amount burned: 10 - 0.0034 = 9.9966 TAO
Caller receives: 0.0034 TAO
```

## Security Considerations

### Invariants
- Contract balance should be ≤ gas reimbursement after successful burn
- Burned tokens are permanently destroyed
- Caller is always reimbursed for gas (incentive alignment)

### Risks & Mitigations

#### 1. Gas Price Manipulation
**Risk:** Caller could use high gas price to extract more value
**Mitigation:** They pay for that gas upfront; net zero gain. Market-based gas pricing ensures fairness.

#### 2. Unstake Precompile Failure
**Risk:** Unstake precompile call fails
**Mitigation:** Function reverts, preserving contract state. Can be retried.

#### 3. Insufficient Balance
**Risk:** Balance too low to cover gas reimbursement
**Mitigation:** Function reverts early if `balance < estimatedGasReimbursement`

#### 4. Reentrancy
**Risk:** Reimbursement transfer could call back into contract
**Mitigation:** No state to corrupt (stateless design). Burning to address(0) cannot reenter. Use checks-effects-interactions pattern.

#### 5. Front-running
**Risk:** Multiple callers race to claim gas reimbursement
**Mitigation:** First transaction wins. Burns are idempotent. No value extraction beyond gas costs.

### No Admin Privileges
- **No owner** - No single point of control
- **No pause** - Cannot be stopped once deployed
- **No upgrades** - Behavior is immutable
- **No privileged functions** - All functions are public

This ensures the contract is **trustless and censorship-resistant**.

## Precompile Integration

### Implementation
```solidity
// Calculate reimbursement
uint256 startGas = gasleft();
uint256 balance = address(this).balance;

// ... gas calculation ...

// Step 1: Unstake all staked tokens
(bool unstakeSuccess, ) = UNSTAKE_PRECOMPILE.call(
    abi.encodeWithSignature("unstake(uint256)", balance)
);
require(unstakeSuccess, "Unstake failed");

// Step 2: Reimburse caller (checks-effects-interactions pattern)
(bool reimbursementSuccess, ) = msg.sender.call{value: gasReimbursement}("");
require(reimbursementSuccess, "Reimbursement failed");

// Step 3: Burn remaining liquid balance by sending to address(0)
uint256 amountToBurn = balance - gasReimbursement;
(bool burnSuccess, ) = payable(address(0)).call{value: amountToBurn}("");
require(burnSuccess, "Burn failed");

emit Burned(balance, amountToBurn, gasReimbursement, msg.sender, block.timestamp);
```

## Testing Requirements

### Unit Tests
1. `burnAll()` unstakes tokens correctly
2. `burnAll()` reimburses caller correctly
3. `burnAll()` burns remaining balance (sends to address(0))
4. Events emit proper values (unstaked, burned, gas reimbursement)
5. Reverts when balance insufficient
6. Reverts when **unstake** precompile fails
7. Reverts when **reimbursement** transfer fails
8. Gas reimbursement calculation is accurate

### Integration Tests
1. Precompile interaction succeeds on testnet
2. Tokens are permanently destroyed (verify via chain state)
3. Gas usage matches expectations
4. Multiple sequential burns work correctly

### Edge Cases
1. Balance exactly equals gas cost (should revert or burn 0)
2. Very small balances
3. Very large balances
4. Multiple callers racing (front-running scenario)
5. Different gas prices
6. Precompile call failure

### Gas Optimization Tests
1. Measure actual gas used vs. buffer
2. Tune REIMBURSEMENT_BUFFER for accuracy
3. Minimize overhead for small burns

## Gas Reimbursement Calibration

### Determining REIMBURSEMENT_BUFFER
The buffer must account for:
- Transfer to caller: ~21,000 gas (base) + ~9,000 (if caller is contract)
- Precompile call: ~21,000 base + precompile-specific cost
- Event emission: ~1,500 gas per indexed parameter
- SSTORE operations: None (stateless design)
- Safety margin: 10-20%

**Recommended starting value:** 60,000 gas units
**Tune via testing on Bittensor testnet**

### Potential Optimization
For maximum accuracy, consider a two-pass approach:
1. Estimate gas needed
2. Execute operations
3. Measure actual gas used
4. Adjust reimbursement on-chain

However, this adds complexity. Start with a conservative fixed buffer.

## Deployment Checklist
- [ ] Verify unstake precompile address for Bittensor (`0x0000000000000000000000000000000000000801`)
- [ ] Calibrate REIMBURSEMENT_BUFFER on testnet
- [ ] Test gas reimbursement accuracy with various gas prices
- [ ] Test on Bittensor testnet with real unstake precompile
- [ ] Verify burn behavior (tokens sent to address(0) are permanently destroyed)
- [ ] Audit contract (recommended for mainnet)
- [ ] Test forced send mechanisms (if applicable)
- [ ] Verify contract on block explorer
- [ ] Document contract address publicly

## Dependencies
- Solidity compiler: ^0.8.20 (for built-in overflow checks)
- No external libraries required (minimize dependencies)
- Bittensor network documentation for precompile addresses

## Open Questions
1. What is the exact address of the **unstake** precompile on Bittensor?
2. What is the exact function signature for the unstake precompile?
3. What are the gas costs for unstaking operations?
4. Is unstaking immediate or is there an unbonding period?
5. What is the expected mechanism for funding this contract (staked tokens)?
6. Should there be a minimum burn threshold to prevent dust attacks?
7. Do staked tokens appear in `address(this).balance` or do they require a different query method?

## Implementation Notes

### Why No State Variables?
- **Lower deployment cost** - No storage initialization
- **Lower execution cost** - No SLOAD/SSTORE operations
- **Simpler security model** - No state to corrupt
- **Fully deterministic** - Behavior depends only on balance

### Why No receive()?
- **Prevent accidental sends** - Users must use forced sends or pre-fund
- **Simpler interface** - Single entry point (`burnAll()`)
- **Clear intent** - Contract only burns, doesn't accept deposits

### Alternative: With receive()
If ease of use is preferred over minimalism, add:
```solidity
receive() external payable {
    // Accept deposits silently
}
```

However, this was explicitly excluded per requirements.

## References
- Bittensor documentation: [URL needed]
- EVM precompile standards
- Solidity gas optimization patterns
- EIP-150: Gas cost changes for IO-heavy operations
