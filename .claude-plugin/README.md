# Claude Solidity Testing Plugin

A Claude Code plugin providing production-grade skills for Solidity development. Each skill encodes battle-tested methodology from the best public resources in the ecosystem.

> Forked from [max-taylor/Claude-Solidity-Skills](https://github.com/max-taylor/Claude-Solidity-Skills) by Max Taylor. This is an opinionated variant maintained by doxielabs; credit for the original design and skill content goes to the upstream author.

## Installation

### One-Click Plugin Install (Recommended)

```bash
# Add marketplace
/plugin marketplace add doxielabs/claude-solidity-testing

# Install plugin
/plugin install solidity-testing-skills@claude-solidity-testing
```

Or via CLI:

```bash
claude plugin marketplace add doxielabs/claude-solidity-testing
claude plugin install solidity-testing-skills@claude-solidity-testing
```

### Local (for development)

```bash
claude --plugin-dir ./solidity-testing-skills
```

## Skills

### `/solidity-testing-skills:test-hardhat` — Hardhat Test Generation

Generates comprehensive Hardhat v3 test suites with structured coverage across unit, integration, and end-to-end testing layers.

**What it does:**

- Reads and analyzes the target contract's full interface (functions, modifiers, events, errors, state)
- Produces a test plan covering deployment, per-function happy/sad paths, access control, boundary cases, and multi-step integration flows
- Writes TypeScript tests using `loadFixture`, Chai matchers, and `hardhat-network-helpers`
- Outputs a coverage summary mapping tests to every require, event, and modifier

**Invoke:**

```
/solidity-testing-skills:test-hardhat MyContract.sol
```

**Resources used to build this skill:**

- [Hardhat v3 Testing Guide](https://hardhat.org/docs/guides/testing) — Hardhat's official dual Solidity/TypeScript testing approach, fixtures, and network helpers
- [Moloch DAO Test README](https://github.com/MolochVentures/moloch/blob/master/test/README.md) — Verification helper pattern, DRY test philosophy, per-require coverage discipline, and state machine testing methodology
- [Smart Contract Security Field Guide — Testing](https://scsfg.io/developers/testing/) — Test planning hierarchy (unit → integration → e2e → fuzz), TDD workflow, invariant testing philosophy
- [Ethereum.org — Smart Contract Testing](https://ethereum.org/developers/docs/smart-contracts/testing/) — Canonical testing taxonomy (unit, integration, property-based, static/dynamic analysis), tool landscape overview

---

### `/solidity-testing-skills:unit-test-foundry` — Foundry/Forge Unit & Fuzz Test Generation

Generates comprehensive Forge unit and fuzz test suites for a Solidity contract or a single function.

**What it does:**

- Reads and analyzes the target contract's full interface (functions, modifiers, events, errors, state)
- Produces a test plan covering deployment, per-function revert cases (access control, input validation), happy paths with state and event assertions, and edge cases (zero, max uint, boundaries)
- Writes Solidity tests using forge-std's `Test` base, cheatcodes (`vm.prank`, `vm.expectRevert`, `vm.expectEmit`, `vm.warp`, `deal`, etc.), and a shared `BaseTest` for setup reuse
- Emits a `testFuzz_` variant for every function with numeric or address inputs, using `bound()` to constrain ranges
- Outputs a coverage summary mapping tests to every modifier, require/revert, event, and edge case

**Invoke:**

```
/solidity-testing-skills:unit-test-foundry MyContract.sol
```

Supports a filename, a function name, or `File.sol#LineNumber` to scope the tests to a single function.

**Resources used to build this skill:**

- [Foundry Book — Writing Tests](https://book.getfoundry.sh/forge/writing-tests) — Test structure, `setUp()`, naming conventions (`test_`, `testFuzz_`), assertion library, verbosity flags
- [Foundry Book — Cheatcodes Overview](https://book.getfoundry.sh/forge/cheatcodes) — Full `vm.*` cheatcode reference (prank, expectRevert, expectEmit, warp, roll, deal, store, mockCall, etc.)
- [Moloch DAO Test README](https://github.com/MolochVentures/moloch/blob/master/test/README.md) — Verification helper pattern, per-require coverage discipline, state machine testing
- [Smart Contract Security Field Guide — Testing](https://scsfg.io/developers/testing/) — Test planning hierarchy, fuzz testing philosophy
- [Ethereum.org — Smart Contract Testing](https://ethereum.org/developers/docs/smart-contracts/testing/) — Testing taxonomy and property-based testing methodology

---

### `/solidity-testing-skills:invariant-test-foundry` — Foundry/Forge Invariant Test Generation

Generates a handler-driven Forge invariant test suite for one or more Solidity contracts, driven by a user-supplied list of invariants.

**What it does:**

- Takes a tuple of target contract files and a path to an invariants file (markdown/text) listing the properties that must hold
- Reads the contracts and the invariants file, maps out actors, ghost state, and the handler surface required to exercise every invariant
- Generates a `HandlerBase` (actor scaffolding, `useActor` modifier) and a `BaseTest` (deploys tokens, dependencies, approvals) — or reuses existing ones
- Writes a handler contract with `bound()`-constrained inputs, ghost variables, and per-selector call counters
- Writes the invariant test contract with every listed invariant plus any implied conservation / monotonicity / solvency properties
- Outputs a coverage summary tying each invariant back to its entry in the invariants file, plus a handler-action exercise count

**Invoke:**

```
/solidity-testing-skills:invariant-test-foundry [Vault.sol, Router.sol] invariants.md
```

**Resources used to build this skill:**

- [Foundry Book — Invariant Testing Guide](https://book.getfoundry.sh/guides/invariant-testing) — Handler pattern, ghost variables, `targetContract`, `targetSelector`, `bound()` vs `vm.assume()`, multi-actor simulation, configuration
- [Foundry Book — Fork Testing Guide](https://book.getfoundry.sh/guides/fork-testing) — `vm.createFork`, `vm.selectFork`, block pinning, `deal()` for ERC20s, RPC caching
- [Foundry Book — Cheatcodes Overview](https://book.getfoundry.sh/forge/cheatcodes) — `vm.prank`, `vm.deal`, `vm.mockCall`, `bound()` and the `useActor` building blocks
- [Moloch DAO Test README](https://github.com/MolochVentures/moloch/blob/master/test/README.md) — State-machine invariants and per-require coverage discipline
- [Smart Contract Security Field Guide — Testing](https://scsfg.io/developers/testing/) — Invariant property identification

---

### `/solidity-testing-skills:gas-optimize` — Gas Optimization Analysis

Analyzes a Solidity contract for gas optimization opportunities, ranked by impact with before/after code and estimated gas savings.

**What it does:**

- Analyzes storage layout, access patterns, and function hot paths
- Identifies savings across 7 categories: storage layout, data structures, function-level, arithmetic, assembly, compiler settings, and L2-specific considerations
- Provides before/after code with specific gas numbers for every recommendation
- Outputs a prioritized report (high/medium/low impact)

**Invoke:**

```
/solidity-testing-skills:gas-optimize MyContract.sol
```

**Resources used to build this skill:**

- [Cyfrin — 11 Solidity Gas Optimization Tips](https://www.cyfrin.io/blog/solidity-gas-optimization-tips) — 11 techniques with Foundry benchmarks and real gas savings numbers (90% on events vs storage, 89% on mappings vs arrays, etc.)
- [Alchemy — Solidity Gas Optimization](https://www.alchemy.com/overviews/solidity-gas-optimization) — 12 techniques with code examples, encoding patterns, unchecked arithmetic, calldata vs memory, and gas cost reference table
- [Hacken — Solidity Gas Optimization](https://hacken.io/discover/solidity-gas-optimization/) — Storage packing, gas refund mechanisms (15,000 refund on zero), compiler optimizer settings, `bytes32` vs `string`
- [Cyfrin — L2 Gas Efficiency Tips](https://www.cyfrin.io/blog/solidity-gas-efficiency-tips-tackle-rising-fees-base-other-l2) — L2-specific considerations (calldata dominates costs on rollups, storage relatively cheaper, batch operation value)

---

### `/solidity-testing-skills:audit` — Security Audit

Performs a systematic, checklist-driven security audit with SWC vulnerability classification and weird ERC20 edge case analysis.

**What it does:**

- Works through 115+ checklist items across variables, structs, functions, modifiers, code patterns, external calls, events, and contract-level concerns
- Scans for all 37 SWC (Smart Contract Weakness Classification) vulnerability types
- Checks token interactions against 20+ known weird ERC20 behaviors (fee-on-transfer, rebasing, missing return values, blocklists, etc.)
- Includes DeFi-specific checks (oracle manipulation, flash loans, first depositor attacks, rounding direction)
- Outputs a structured audit report with findings classified by severity (Critical/High/Medium/Low)

**Invoke:**

```
/solidity-testing-skills:audit MyContract.sol
```

**Resources used to build this skill:**

- [Smart Contract Audit Checklist](https://github.com/tamjid0x01/SmartContracts-audit-checklist) — 115+ actionable checklist items covering variables (10), structs (3), functions (19), modifiers (3), code patterns (51), external calls (8), static calls (4), events (5), contract-level (12)
- [Awesome Audits Checklists](https://github.com/TradMod/awesome-audits-checklists) — Meta-list linking to Cyfrin Solodit, ERC-specific checklists (ERC20, ERC721, ERC4626, ERC4337), DeFi protocol checklists (AMM, CDP, LSD), oracle security, bridge security
- [SlowMist Auditor Learning Roadmap](https://github.com/slowmist/SlowMist-Learning-Roadmap-for-Becoming-a-Smart-Contract-Auditor) — Vulnerability taxonomy referencing DASP Top 10, SWC registry, and EVM-specific exploit patterns
- [Weird ERC20 Tokens](https://github.com/d-xo/weird-erc20) — Complete catalog of non-standard ERC20 behaviors: missing return values (USDT), fee-on-transfer (STA, PAXG), rebasing (AMPL), flash minting (DAI), blocklists (USDC), pausable (BNB), approval race conditions, low/high decimals, and more
- [SWC Registry](https://swcregistry.io/) — Standardized vulnerability classification (SWC-100 through SWC-136) mapping to CWE IDs, used as the industry-standard reference in audit reports
- [Smart Contract Security Field Guide — Testing](https://scsfg.io/developers/testing/) — Security-focused testing methodology overlapping with audit concerns

## Plugin Structure

```
claude-solidity-testing/
├── .claude-plugin/
│   ├── marketplace.json
│   └── plugin.json
├── skills/
│   ├── test-hardhat/
│   │   └── SKILL.md                       # Hardhat test generation
│   ├── unit-test-foundry/
│   │   └── SKILL.md                       # Foundry unit + fuzz test generation
│   ├── invariant-test-foundry/
│   │   ├── SKILL.md                       # Foundry invariant test generation
│   │   └── references/
│   │       └── invariant-testing.md       # Handler pattern, ghost vars, targeting
│   ├── gas-optimize/
│   │   └── SKILL.md                       # Gas optimization analysis
│   └── audit/
│       └── SKILL.md                       # Security audit
└── README.md
```

## Contributing

To add a new skill, create a directory under `skills/` with a `SKILL.md` file. See existing skills for the frontmatter format and methodology structure.

## Acknowledgements

This plugin is a fork of [max-taylor/Claude-Solidity-Skills](https://github.com/max-taylor/Claude-Solidity-Skills). The original author, [Max Taylor](https://github.com/max-taylor), designed the skill structure and curated the underlying resources. This fork rebrands and extends the skill set for doxielabs' internal testing workflows.
