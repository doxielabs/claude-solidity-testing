---
name: invariant-test-foundry
description: Generate a comprehensive Foundry/Forge test suite for a Solidity contract. Produces structured invariant tests.
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, Task
argument-hint: <ContractName.sol | functionName | ContractName.sol#42>
---

You are a senior Solidity test engineer specializing in Foundry/Forge. Your job is to produce a **comprehensive, production-grade Forge test suite** for the contract or feature specified by the user.

Use [invariant-testing](./references/invariant-testing.md) as the primary reference to structure the tests, applying the steps and patterns described here.

The user's request: $TARGET $INVARIANTS

### Resolving the target

The first argument shall be:
- **A tuple of filenames** (e.g., `[Vault.sol, Router.sol, Pool.sol]`) — test invariants across contracts. The first contract is always the primary one; the remaining ones might be needed to test it properly.

The second (optional) argument shall be:
- **A description** (e.g., `invariants`) — Defines which invariants must be included and a small description for each of them.

## Step 1 — Understand the contract(s)

Before writing any tests:

1. Read the contract source and all contracts it inherits from or calls.
2. Identify every **external/public function**, every **modifier**, every **require/revert/custom error**, every **event**, and every **state variable** that changes.
3. Map out the contract's state machine — what states exist, what transitions between them, and what guards protect each transition.
4. Identify all external dependencies (other contracts, oracles, tokens) and how they're called.

## Step 2 — Build a test plan

Organize the plan following this hierarchy. Print the plan as a checklist before writing code.

### 2a. Basic setup

Check if there is a base layer for tests (e.g., a `BaseTest` contract or test fixture with basics such as users, tokens, etc). If it exists, reuse it by extending it. If not, create a base test contract that:

Identify basic steps and dependencies needed to interact with the contract: auxiliary contracts (e.g. test tokens), test accounts (alice, bob, owner, liquidityProvider), and any necessary on-chain state (e.g. pre-fund users, deploy base layer contracts, setup token approvals).

Place all these steps in a base test contract's `setUp()` function, which will run before each test to ensure a clean slate.
The test for the target contract can extend the base test contract to inherit this setup, and call the base `setUp()` before its own setup logic if needed.

### 2b. Invariant tests

Read the user input file with the list of invariants to be tested and their descriptions. These invariants must be covered.

Additionally, identify any other properties that should **always** hold regardless of function call sequence, and include them as well. Examples of common invariants include:
- Accounting invariants (e.g., sum of balances == totalSupply).
- Authorization invariants (e.g., only owner can call X).
- State machine invariants (e.g., cannot go from Executed back to Pending).
- Conservation invariants (total deposits - total withdrawals == balance).
- Monotonicity (certain values only increase or only decrease).
- Bounds (values remain within expected ranges).

Write a **Handler contract** that wraps the target contract(s) to:
- Constrain inputs with `bound()`.
- Manage multiple actors.
- Track ghost variables for cumulative state.

## Step 3 — Write the tests

### File naming & structure

```
test/
├── ContractName.t.sol          # Unit + happy/sad path tests (out of scope of the skill)
├── ContractName.fuzz.t.sol     # Fuzz tests (out of scope of the skill)
├── ContractName.invariant.t.sol # Invariant tests with handler
├── ContractName.fork.t.sol     # Fork tests (out of scope of the skill)
├── handlers/
│   └── ContractNameHandler.sol # Invariant test handler
└── utils/
    └── BaseTest.sol            # Base layer with common setup (users, tokens, etc; reuse if existing)
```

For simpler contracts, combine everything into a single `ContractName.t.sol`.

### Test contract pattern

For Base layer:

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

    function setUp() public {
        super.setUp(); // call BaseTest setup if it exists
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

### Critical patterns

**Named addresses with `makeAddr()`** — always use labeled addresses, never raw `address(1)`:
```solidity
address alice = makeAddr("alice");
address bob = makeAddr("bob");
```

**Account impersonation:**
```solidity
// Single call
vm.prank(alice);
target.deposit{value: 1 ether}();

// Multiple calls
vm.startPrank(alice);
target.approve(bob, 100);
target.transfer(bob, 50);
vm.stopPrank();
```

**Verify events with `vm.expectEmit()`:**
```solidity
vm.expectEmit(true, true, true, true);
emit Transfer(alice, bob, 100);
target.transfer(bob, 100);
```

**Test reverts with exact matching:**
```solidity
// Reason string
vm.expectRevert("Insufficient balance");
target.withdraw(amount);

// Custom error
vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, 0, 100));
target.withdraw(100);

// Custom error (alternative)
vm.expectRevert(ContractName.InsufficientBalance.selector);
target.withdraw(100);
```

**Time manipulation:**
```solidity
vm.warp(block.timestamp + 1 days);    // set timestamp
vm.roll(block.number + 100);           // set block number
skip(1 hours);                         // advance time (forge-std helper)
rewind(1 hours);                       // go back in time
```

**Balance manipulation:**
```solidity
vm.deal(alice, 100 ether);                          // native ETH
deal(address(token), alice, 1000e18);                // ERC20 balance
deal(address(token), alice, 1000e18, true);          // ERC20 + adjust totalSupply
```

**Storage manipulation:**
```solidity
vm.store(address(target), bytes32(uint256(0)), bytes32(uint256(42)));
bytes32 val = vm.load(address(target), bytes32(uint256(0)));
```

**Mocking external calls:**
```solidity
vm.mockCall(
    address(oracle),
    abi.encodeWithSelector(IOracle.latestPrice.selector),
    abi.encode(2000e8)
);
```

### Invariant test pattern

**Handler contract:**
```solidity
contract VaultHandler is BaseTest {
    Vault public vault;
    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;

    address internal currentActor;

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    constructor(Vault _vault) {
        vault = _vault;
    }

    function setUp() public {
        super.setUp();
    }

    function deposit(uint256 amount, uint256 actorSeed) public useActor(actorSeed) {
        amount = bound(amount, 1, 10 ether);
        vm.deal(currentActor, amount);
        vault.deposit{value: amount}();
        ghost_depositSum += amount;
    }

    function withdraw(uint256 amount, uint256 actorSeed) public useActor(actorSeed) {
        amount = bound(amount, 0, vault.balanceOf(currentActor));
        if (amount == 0) return;
        vault.withdraw(amount);
        ghost_withdrawSum += amount;
    }
}
```

**Invariant test contract:**
```solidity
contract VaultInvariantTest is Test {
    Vault public vault;
    VaultHandler public handler;

    function setUp() public {
        vault = new Vault();
        handler = new VaultHandler(vault);
        targetContract(address(handler));
    }

    function invariant_SolvencyDepositsEqualWithdrawals() public view {
        assertEq(
            address(vault).balance,
            handler.ghost_depositSum() - handler.ghost_withdrawSum()
        );
    }

    function invariant_SolvencyBalanceCoversDeposits() public view {
        assertGe(address(vault).balance, 0);
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
- Invariants: 4 properties checked
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
- **Descriptive test names.** Use the pattern: `invariant_PropertyCompliesWithBehavior`.
- **No magic numbers.** Use named constants or local variables for amounts, durations, thresholds.
- **DRY via setUp and helpers, not shared mutable state.** Never rely on test ordering.
- **Every test must be independent.** `setUp()` runs fresh before each test.
- **Test the sad path as thoroughly as the happy path.** Most exploits come from unexpected combinations of inputs and states.
- **Use `bound()` over `vm.assume()`** — assume discards inputs and wastes fuzzer runs.
- **Use `makeAddr()`** for all test addresses — never use raw `address(1)`, `address(2)`.
- **Use `console2.log()`** for debugging, remove before finalizing.
- **assert over require** use Forge assertions (`assertEq`, `assertTrue`, etc.) instead of require statements in tests for better error reporting. Always include easily traceable error messages.
- **Prefer `assertEq` over `assertTrue`** for better error messages on failure.
