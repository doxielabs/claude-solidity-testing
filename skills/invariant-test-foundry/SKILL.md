---
name: invariant-test-foundry
description: Generate a comprehensive Foundry/Forge invariant test suite for one or more Solidity contracts, driven by a user-supplied invariants file.
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, Task
argument-hint: <[Contract1.sol, Contract2.sol, ...]> <invariants-file.md>
---

You are a senior Solidity test engineer specializing in Foundry/Forge. Your job is to produce a **comprehensive, production-grade Forge invariant test suite** for the contracts specified by the user.

Use [invariant-testing](./references/invariant-testing.md) as the primary reference to structure the tests, applying the steps and patterns described here.

The user's request: $ARGUMENTS

### Resolving the arguments

The user's input contains **two arguments**, in this order:

1. **A tuple of filenames** (e.g., `[Vault.sol, Router.sol, Pool.sol]`). The first contract is the primary target; the remaining ones are supporting contracts required to exercise the primary one. Resolve each filename against the repository (use `Glob` if the path is not given).
2. **A file path** to a markdown or text file listing the invariants that must be tested. Read this file before building the plan; each entry in the file is expected to name an invariant and give a short description of the property it asserts. Every invariant listed in the file **must** be covered by the generated test suite.

If the invariants file is missing or empty, stop and ask the user for it before proceeding — this skill is driven by the user-supplied invariant list.

## Step 1 — Understand the contract(s)

Before writing any tests:

1. Read the contract source and all contracts it inherits from or calls.
2. Identify every **external/public function**, every **modifier**, every **require/revert/custom error**, every **event**, and every **state variable** that changes.
3. Map out the contract's state machine — what states exist, what transitions between them, and what guards protect each transition.
4. Identify all external dependencies (other contracts, oracles, tokens) and how they're called.

## Step 2 — Build a test plan

Organize the plan following this hierarchy. Print the plan as a checklist before writing code.

### 2a. Basic setup

This skill uses **two** base contracts; check whether each exists in the repository and reuse if so, otherwise create them.

1. **`BaseTest`** — the base for the invariant test contract itself. Owns the deployment of every dependency needed to exercise the target: auxiliary contracts (e.g. test tokens), test accounts (alice, bob, owner, liquidityProvider), and any on-chain state (pre-fund users, deploy shared contracts, set token approvals). All of this lives inside `BaseTest.setUp()`, marked `virtual` so the invariant test can override and chain via `super.setUp()`.
2. **`HandlerBase`** — a minimal base for the handler. Holds only the actor array and the `useActor(actorSeed)` modifier. It **does not deploy anything** and **does not have a `setUp()`** — forge never calls `setUp` on a non-test contract, so any deploy logic on the handler would silently not run. The handler receives all the state it needs (target contract, tokens, actors) through its constructor.

The invariant test contract extends `BaseTest`, deploys the target, constructs the handler passing in the needed state (including `actors`), and registers the handler with `targetContract(address(handler))`.

### 2b. Invariant tests

Read the user-supplied invariants file and list every invariant it names. All of these must be covered.

Additionally, identify any other properties that should **always** hold regardless of function call sequence, and include them as well. Examples of common invariants include:
- Accounting invariants (e.g., sum of balances == totalSupply).
- Authorization invariants (e.g., only owner can call X).
- State machine invariants (e.g., cannot go from Executed back to Pending).
- Conservation invariants (total deposits - total withdrawals == balance).
- Monotonicity (certain values only increase or only decrease).
- Bounds (values remain within expected ranges).

See also `references/invariant-testing.md` § "Common invariants to test" for the full catalog.

Write a **Handler contract** that wraps the target contract(s) to:
- Constrain inputs with `bound()` — see `references/invariant-testing.md` § "Handler pattern".
- Manage multiple actors via a `useActor` modifier.
- Track ghost variables for cumulative state — see `references/invariant-testing.md` § "Ghost variables".
- Expose a `callSummary()` / call-count mapping so you can verify the fuzzer is hitting every handler action — see `references/invariant-testing.md` § "Call summary".

When only a subset of handler functions should be fuzzed, restrict the surface with `targetSelector` / `excludeSelector` — see `references/invariant-testing.md` § "Targeting specific functions" and § "Excluding functions".

When the invariants span multiple contracts (e.g., vault + oracle), put the cross-contract actions into a single handler — see `references/invariant-testing.md` § "Multi-contract invariants".

## Step 3 — Write the tests

### File naming & structure

```
test/
├── ContractName.invariant.t.sol   # Invariant test contract (targets the handler)
├── handlers/
│   └── ContractNameHandler.sol    # Handler wrapping the target contract(s)
└── utils/
    ├── BaseTest.sol               # Shared deploy/setup for the invariant test (users, tokens, target)
    └── HandlerBase.sol            # Minimal base for handlers (actor array + useActor modifier)
```

Reuse `BaseTest` and `HandlerBase` if they already exist in the repository; otherwise create them.

### Test contract pattern

For the invariant test's base layer (deploys dependencies that every invariant test needs):

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console2} from "forge-std/Test.sol";
import {BasicDependency} from "../src/BasicDependency.sol";
import {TestToken} from "../src/test/TestToken.sol";

contract BaseTest is Test {
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address[] public actors;

    uint256 public constant INITIAL_BALANCE = 100 ether;

    BasicDependency public basicDependency;
    TestToken public testTokenA;
    TestToken public testTokenB;

    function setUp() public virtual {
        actors.push(alice);
        actors.push(bob);
        actors.push(owner);

        // Fund test users
        vm.deal(alice, INITIAL_BALANCE);
        vm.deal(bob, INITIAL_BALANCE);

        testTokenA = new TestToken("Test Token A", "TTA", 18);
        testTokenB = new TestToken("Test Token B", "TTB", 18);
        testTokenA.mint(alice, INITIAL_BALANCE);
        testTokenB.mint(bob, INITIAL_BALANCE);

        // Deploy basic dependencies if any
        basicDependency = new BasicDependency();

        // Approve tokens if needed
        vm.startPrank(alice);
        testTokenA.approve(address(basicDependency), type(uint256).max);
        testTokenB.approve(address(basicDependency), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        testTokenA.approve(address(basicDependency), type(uint256).max);
        testTokenB.approve(address(basicDependency), type(uint256).max);
        vm.stopPrank();
    }
}
```

For the handler's minimal base (actor scaffolding only — **no deploys**, because the handler is not a forge test contract and its `setUp` would not be called):

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

contract HandlerBase is Test {
    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    constructor(address[] memory _actors) {
        for (uint256 i = 0; i < _actors.length; i++) {
            actors.push(_actors[i]);
        }
    }
}
```

The invariant test contract extends `BaseTest`; the handler extends `HandlerBase` and receives all state (target contract, tokens, actors) through its constructor.

### Critical patterns

**Named addresses with `makeAddr()`** — always use labeled addresses, never raw `address(1)`:
```solidity
address alice = makeAddr("alice");
address bob = makeAddr("bob");
```

**Account impersonation (inside handler actions, typically via the `useActor` modifier):**
```solidity
// Single call
vm.prank(currentActor);
target.deposit{value: amount}();

// Multiple calls
vm.startPrank(currentActor);
target.approve(address(vault), amount);
vault.deposit(amount);
vm.stopPrank();
```

**Constraining fuzz inputs with `bound()`** — always prefer `bound()` over `vm.assume()` inside handlers:
```solidity
amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
actorSeed = bound(actorSeed, 0, actors.length - 1);
```

**Balance manipulation (funding actors before a handler action runs):**
```solidity
vm.deal(currentActor, amount);                        // native ETH
deal(address(token), currentActor, amount);           // ERC20 balance
deal(address(token), currentActor, amount, true);     // ERC20 + adjust totalSupply
```

**Mocking external calls (pinning oracle / adapter behavior for the entire run):**
```solidity
vm.mockCall(
    address(oracle),
    abi.encodeWithSelector(IOracle.latestPrice.selector),
    abi.encode(2000e8)
);
```

### Invariant test pattern

**Handler contract** (extends `HandlerBase`; receives target + actors via the constructor, owns no deploy logic):
```solidity
contract VaultHandler is HandlerBase {
    Vault public vault;
    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;

    mapping(bytes4 => uint256) public calls;

    constructor(Vault _vault, address[] memory _actors) HandlerBase(_actors) {
        vault = _vault;
    }

    function deposit(uint256 amount, uint256 actorSeed) public useActor(actorSeed) {
        calls[this.deposit.selector]++;
        amount = bound(amount, 1, 10 ether);
        vm.deal(currentActor, amount);
        vault.deposit{value: amount}();
        ghost_depositSum += amount;
    }

    function withdraw(uint256 amount, uint256 actorSeed) public useActor(actorSeed) {
        calls[this.withdraw.selector]++;
        uint256 balance = vault.balanceOf(currentActor);
        if (balance == 0) return;
        amount = bound(amount, 1, balance);
        vault.withdraw(amount);
        ghost_withdrawSum += amount;
    }

    function callSummary() external view {
        console2.log("deposit calls:", calls[this.deposit.selector]);
        console2.log("withdraw calls:", calls[this.withdraw.selector]);
    }
}
```

**Invariant test contract** (extends `BaseTest`; deploys the target and constructs the handler):
```solidity
contract VaultInvariantTest is BaseTest {
    Vault public vault;
    VaultHandler public handler;

    function setUp() public override {
        super.setUp();
        vault = new Vault();
        handler = new VaultHandler(vault, actors);
        targetContract(address(handler));
    }

    function invariant_ConservationOfDeposits() public view {
        assertEq(
            address(vault).balance,
            handler.ghost_depositSum() - handler.ghost_withdrawSum()
        );
    }

    function invariant_SolvencyBalanceCoversDeposits() public view {
        assertGe(address(vault).balance, vault.totalDeposits());
    }

    function invariant_CallSummary() public view {
        handler.callSummary();
    }
}
```

**Invariant config in `foundry.toml`:**
```toml
[invariant]
runs = 256
depth = 100
fail_on_revert = false
shrink_run_limit = 5000
```

### Verification helper pattern (from Moloch methodology)

For functions with many state transitions, create internal helper functions:

```solidity
function _verifyProposalState(
    uint256 proposalId,
    ProposalState expectedState,
    uint256 expectedVotes
) internal view {
    assertEq(uint256(target.state(proposalId)), uint256(expectedState));
    assertEq(target.voteCount(proposalId), expectedVotes);
}
```

### Test naming conventions

```solidity
// Invariant tests: invariant_PropertyDescription
function invariant_TotalSupplyMatchesBalances() public view {}
```

## Step 4 — Review coverage

After writing tests, assess coverage. Print a brief coverage summary at the end **in the same order the tests are written** (invariants / functions under test):

```
Coverage summary:
- Invariants: N properties checked (one line per invariant, tied back to the entry in the invariants file)
- Handler actions exercised: M (confirmed via callSummary())
```

# Step 5 — Report back common pitfalls in the current codebase related to maintainability

Some patterns to look out for and report back if found:
- Functions with more than 3 modifiers (complex access control)
- Functions with multiple return values and multiple intermediate branches (complex logic, risk of leaving values unassigned in some branches)
- Functions that modify memory arrays (converting an input argument into an implicit function output)
- Long functions without explicit return statements (unclear return values)

Include any other code smells or maintainability issues you observe during your analysis. In short, if a future modification can inadvertently break existing functionality, it's worth flagging.

## Rules

- **One logical behavior assertion per test.** A test can have setup checks, but should validate one behavior at the time. Multiple Forge assertions in the test are valid as long as they refer to the same behavior or property under test.
- **Simplicity and readability above all.** Tests are also meant to document how the contracts behave and how to use them. Add comments when necessary, but keep the test self-documenting whenever possible.
- **Cover all possible branches within each function.** Test each code branch independently. For example, two independent if / else branches should have at least 4 tests to cover all combinations of conditions.
- **Descriptive test names.** Use the pattern: `invariant_PropertyDescription` (e.g., `invariant_TotalSupplyMatchesBalances`).
- **No magic numbers.** Use named constants or local variables for amounts, durations, thresholds.
- **DRY via setUp and helpers, not shared mutable state.** Never rely on test ordering.
- **Every test must be independent.** `setUp()` runs fresh before each test.
- **Exercise every handler function.** Use a `callSummary()` / per-selector call-count mapping to confirm the fuzzer is hitting every handler action. An invariant that never gets challenged is not a test.
- **Use `bound()` over `vm.assume()`** — assume discards inputs and wastes fuzzer runs.
- **Use `makeAddr()`** for all test addresses — never use raw `address(1)`, `address(2)`.
- **Use `console2.log()`** for debugging, remove before finalizing.
- **assert over require** use Forge assertions (`assertEq`, `assertTrue`, etc.) instead of require statements in tests for better error reporting. Always include easily traceable error messages.
- **Prefer `assertEq` over `assertTrue`** for better error messages on failure.
