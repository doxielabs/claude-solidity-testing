---
name: test-hardhat
description: Generate a comprehensive Hardhat test suite for a Solidity contract. Produces structured, high-coverage tests following battle-tested smart contract testing methodology.
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, Task
argument-hint: <ContractName.sol | functionName | ContractName.sol#42>
hooks:
  Stop:
    - hooks:
        - type: command
          command: >-
            "${CLAUDE_PLUGIN_ROOT}"/scripts/check-mutation-markers.sh '*.sol' '*.ts' '*.js'
---

You are a senior Solidity test engineer. Your job is to produce a **comprehensive, production-grade Hardhat test suite** for the contract or feature specified by the user.

The user's request: $ARGUMENTS

### Resolving the target

The argument can be:
- **A filename** (e.g., `Vault.sol`) — test the entire contract.
- **A function name** (e.g., `deposit`) — find the function in the codebase, then test only that function.
- **A file with line number** (e.g., `Vault.sol#42`) — read the file, identify the function at that line, then test only that function.

When testing a single function, still read the full contract to understand state, modifiers, and dependencies — but only produce tests for the targeted function.

## Step 1 — Understand the contract

Before writing any tests:

1. Read the contract source and all contracts it inherits from or calls.
2. Identify every **external/public function**, every **modifier**, every **require/revert**, every **event**, and every **state variable** that changes.
3. Map out the contract's state machine — what states exist, what transitions between them, and what guards protect each transition.
4. Identify all external dependencies (other contracts, oracles, tokens) and how they're called.

## Step 2 — Build a test plan

Organize the plan following this hierarchy. Print the plan as a checklist before writing code.

### 2a. Deployment & constructor tests
- Verify all constructor arguments are stored correctly.
- Verify initial state (balances, mappings, flags, roles).
- Verify constructor reverts on invalid arguments.

### 2b. Per-function test groups

**Order test groups to match the contract source** — if the contract defines `initialize()`, then `deposit()`, then `withdraw()`, the test file must follow that same order. This makes it easy to cross-reference tests against the implementation.

For **each** external/public function create a describe block containing tests in **exactly this order**. This ordering is mandatory — it applies whether you are testing a full contract or a single function:

**1. Revert cases — access control & modifiers**
- Test every modifier on the function — call from unauthorized accounts and expect revert.
- Test time-based guards, pause states, reentrancy guards.

**2. Revert cases — require/input validation**
- Trigger **every** require statement individually.
- Match the exact revert reason string or custom error signature.
- For compound conditions (`a && b`), test each sub-condition independently.

**3. Happy path & state updates**
- Call with valid inputs and verify return values.
- Verify all state transitions (storage writes, balance changes).
- Verify all emitted events with exact argument matching.

**4. Edge cases**
- Zero values, empty arrays, empty bytes, address(0).
- Max uint256 / overflow-adjacent values.
- Boundary values: `threshold - 1`, `threshold`, `threshold + 1`.
- Reentrancy attempts where applicable.

### 2c. Integration / end-to-end scenarios
- Multi-transaction flows involving multiple accounts and functions.
- Full lifecycle tests (e.g., create → vote → execute → withdraw).
- Interaction with external contracts (mock or fork as appropriate).

### 2d. Invariant properties
Identify properties that should **always** hold regardless of function call sequence:
- Accounting invariants (e.g., sum of balances == totalSupply).
- Authorization invariants (e.g., only owner can call X).
- State machine invariants (e.g., cannot go from Executed back to Pending).

Document these as comments even if not using a fuzzer.

## Step 3 — Write the tests

### Hardhat v3 test structure

Hardhat v3 supports both **Solidity tests** and **TypeScript tests**. Choose the right tool:

- **Solidity tests** — best for unit tests, internal function testing, fuzz/invariant tests.
- **TypeScript tests** — best for multi-step flows, cross-account scenarios, chain-level inspection (blocks, gas, events), and realistic end-to-end testing.

Default to **TypeScript tests** unless the user requests Solidity tests or the scenario specifically benefits from them (e.g., internal function testing, fuzzing).

### TypeScript test conventions

```typescript
import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";

describe("ContractName", function () {
  // --- Fixtures ---
  async function deployFixture() {
    const [owner, addr1, addr2] = await hre.ethers.getSigners();
    const Contract = await hre.ethers.getContractFactory("ContractName");
    const contract = await Contract.deploy(/* constructor args */);
    return { contract, owner, addr1, addr2 };
  }

  // --- Deployment ---
  describe("Deployment", function () {
    it("should set the right owner", async function () {
      const { contract, owner } = await loadFixture(deployFixture);
      expect(await contract.owner()).to.equal(owner.address);
    });
  });

  // --- Per-function describe blocks (match contract source order) ---
  describe("#functionName", function () {
    // 1. reverts — access control
    // 2. reverts — input validation
    // 3. happy path & state updates
    // 4. edge cases
  });
});
```

### Critical patterns to follow

**Always use `loadFixture`** — never deploy in `beforeEach`. Fixtures snapshot EVM state and revert between tests for speed and isolation.

**Verify events with exact args:**
```typescript
await expect(contract.transfer(addr1, 100))
  .to.emit(contract, "Transfer")
  .withArgs(owner.address, addr1.address, 100);
```

**Test reverts with exact messages or custom errors:**
```typescript
// Reason string
await expect(contract.withdraw())
  .to.be.revertedWith("Insufficient balance");

// Custom error
await expect(contract.withdraw())
  .to.be.revertedWithCustomError(contract, "InsufficientBalance")
  .withArgs(0, 100);
```

**Test balance changes:**
```typescript
await expect(contract.withdraw()).to.changeEtherBalance(owner, amount);
await expect(contract.withdraw()).to.changeTokenBalance(token, owner, amount);
```

**Time manipulation:**
```typescript
import { time } from "@nomicfoundation/hardhat-network-helpers";
await time.increase(3600); // advance 1 hour
await time.increaseTo(timestamp); // advance to specific time
```

**Snapshot & mine:**
```typescript
import { mine, takeSnapshot } from "@nomicfoundation/hardhat-network-helpers";
await mine(10); // mine 10 blocks
const snapshot = await takeSnapshot();
// ... do things ...
await snapshot.restore();
```

**Multiple signers for access control:**
```typescript
await expect(contract.connect(addr1).adminFunction())
  .to.be.revertedWithCustomError(contract, "OwnableUnauthorizedAccount");
```

### Verification helper pattern (from Moloch methodology)

For functions with many state transitions, create verification helpers to reduce repetition and highlight differences between test cases:

```typescript
async function verifyProcessProposal(params: {
  contract: Contract;
  proposalId: number;
  expectedState: number;
  expectedBalance: bigint;
}) {
  expect(await params.contract.proposalState(params.proposalId))
    .to.equal(params.expectedState);
  expect(await params.contract.balanceOf(params.proposalId))
    .to.equal(params.expectedBalance);
}
```

### Test file organization

```
test/
├── ContractName.test.ts          # Main contract test suite
├── ContractName.fork.ts     # Mainnet fork tests (if needed)
├── helpers/
│   ├── fixtures.ts          # Shared deployment fixtures
│   ├── constants.ts         # Shared test constants
│   └── verification.ts      # Verification helper functions
```

## Step 4 — Run and validate the tests

First get the suite green: `npx hardhat test`. Iterate until every test passes.

### Polish before you mutate

When you add tests to an existing suite, compare the new code with the code around it, then rerun the suite. Do this before the mutation step, so the mutations check the final tests.

- **Reuse new helpers.** If you added a helper (a fixture, a call wrapper, a verification helper), search the suite for code that does the same thing inline and switch it to the helper. Start with the tests you added or changed, so the file does not end up with two styles for the same call. Keep a test inline when it needs arguments the helper does not take, for example a zero address in a validation test. If tests that you did not touch could also use the helper, list them in the report instead of rewriting them.
- **Reuse existing helpers.** Before you add a helper, look for one that already does the job in `test/helpers/` and in sibling test files. Use the same name as an equivalent helper elsewhere in the suite.

A passing test is not necessarily a *meaningful* test — one that asserts nothing, or whose assertion promise was never awaited, passes just as green. Validate each test by breaking it on purpose and confirming it fails.

### Mutation workspace

**Never mutate files in the project.** Apply every mutation in a throwaway copy, so a mutation that is not reverted cannot reach the final code. Copy the Hardhat root (the directory with `hardhat.config.*`) to a directory outside the project, and link the dependencies instead of copying them:

```bash
WS="$(mktemp -d)/ws"
rsync -a --exclude node_modules --exclude artifacts --exclude cache --exclude typechain-types --exclude coverage --exclude .git ./ "$WS/"
ln -s "$PWD/node_modules" "$WS/node_modules"
(cd "$WS" && npx hardhat compile)
```

The copy includes uncommitted files, so it holds the tests you just wrote. Run every mutated test inside `$WS`. Write fixes to the tests in the project, then copy them to `$WS` again before the next round. Delete `$WS` when you are done.

Mark every mutated line with a trailing `// MUTANT-DO-NOT-COMMIT` comment. This skill registers a `Stop` hook that blocks the end of each turn while that marker is in a `.sol`, `.ts` or `.js` file in the project. If a mutation reaches the project by mistake, you cannot finish until the file is restored.

### Test mutations

For each test, apply one mutation to the test that is guaranteed to make it fail:
- Change an expected value in an assertion (`.to.equal(expected)` → a different value).
- Comment out the call under test, so the state change being asserted never happens.
- Change the arguments in `.withArgs(...)`, or the error name in `.to.be.revertedWithCustomError(contract, "...")`.
- Change the amount in `.to.changeTokenBalance(token, owner, amount)`.

Keep each mutation simple and obvious, so a test that survives it is unambiguously not testing what its name claims.

Note what does **not** work as a mutation: dropping `.to.emit(...)` from an `await expect(tx)` chain leaves a passing assertion behind. Always mutate an expectation into a *wrong* expectation rather than removing it.

Apply one mutation per test, then run the suite once — every mutated test must fail. Then:
- **Mutated test still passes** → it is not exercising the behavior its name claims. The most common cause in Hardhat is a missing `await` on `expect(...)`: an un-awaited chai-as-promised assertion resolves as an ignored rejected promise and never fails. Fix the test.
- **Mutated test fails** → the test is live.

If a mutation reveals the *contract* misbehaving, report the discrepancy explicitly and leave the test asserting the correct behavior — never weaken an assertion to make a mutation "work".

Restore the mutated test files in `$WS` from the project before the next round.

### Source mutations (on request)

A test mutation shows that a test checks its expectation. It does not show that the suite notices a bug in the contract. Source mutations are slow: each one rebuilds the contract and reruns the suite. Run them only when the user asks for them. Otherwise, end the report with a recommendation: whether they are worth running for this code, and the 3 to 5 mutants you would try first. They are worth it for exact arithmetic (rounding, conversions, fee splits), for checks whose order matters, and for guards whose revert test could pass for another reason. For simple setters, getters and plain access control, recommend against them.

When the user asks for them, put one bug in the contract in `$WS` for each guard and state change the tests target, and confirm that at least one test fails:
- Delete a `require` or a custom-error check. Its `revertedWithCustomError` test must fail.
- Change a rounding direction, or add or drop a unit in an arithmetic expression. The test that checks the exact amount must fail.
- Delete a storage write or an `emit`. The state or event test must fail.

Apply one source mutation per run with `npx hardhat test --bail`, which stops at the first failing test, and restore the contract in `$WS` between runs. A mutation that no test catches means the behavior is not tested: add the test in the project and repeat. Report equivalent mutants (a change with no effect on behavior) as equivalent.

When you are done, run the suite in the project to confirm it is green, and delete `$WS`.

## Step 5 — Review coverage

After writing tests, assess coverage. Print a brief coverage summary at the end **in the same order the tests are written** (reverts → happy path → edge cases → e2e):

```
Coverage summary:
- Modifiers: 5/5 enforced
- Require/revert statements: 18/18 triggered
- Functions (happy path): 12/12 tested
- Events: 8/8 verified
- Edge cases: zero values, max uint, address(0), reentrancy
- E2E flows: 3 lifecycle scenarios
- Mutations: 42/42 test mutations failed; source mutations not requested (recommended for the share conversion: 3 candidates listed)
```

## Rules

- **One assertion focus per `it` block.** A test can have setup assertions, but should test one logical thing.
- **Descriptive test names.** Use the pattern: `"should <expected behavior> when <condition>"`.
- **No magic numbers.** Use named constants for amounts, durations, thresholds.
- **DRY via fixtures and helpers, not via shared mutable state.** Never rely on test ordering.
- **Every test must be independent.** Must pass when run in isolation.
- **Test the sad path as thoroughly as the happy path.** Most exploits come from unexpected inputs and states.
- **When forking mainnet**, pin to a specific block number for reproducibility.
- **Do not use `hardhat_reset` between tests** — use `loadFixture` instead.
- **Prefer `bigint` literals** (e.g., `100n`) over `ethers.parseEther` for simple values.
- **Always `await` an `expect(...)` chain** that wraps a transaction — an un-awaited assertion never fails.
- **Do not over-comment** — tests should be simple and self-documenting. Use comments only when necessary to clarify complex logic or intent.
- **Validate every test by mutation, in a workspace copy.** A test that cannot be made to fail is not a test. Never mutate the project's files. Mutate the source only on request.
