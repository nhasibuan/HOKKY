# HOKKY EA Review, Risk Audit, and Safe-Design Notes

This repository contains a single-file MetaTrader 4 Expert Advisor implementation and a review-oriented README. The source file remains intentionally unchanged.

Important: this README is a documentation and audit artifact only. It does not modify the EA source at `EA_HOKKYDJONG_V4_ATR.mq4`.

## 1) Paraphrased detail of the attached MQ4 file

The attached file is a complex MQL4 Expert Advisor built around a dual-engine ATR strategy. It does not simply place one trade; it manages two internal books:

- Classic book
- Pendulum book

The design is a hybrid of:

- a classic fade / martingale-style recovery engine in a ranging ADX regime
- a pendulum-grid / hedged trend-following engine in a trending ADX regime

At a high level, the EA does the following:

- validates input parameters at startup
- resolves unique magic numbers and persistent global variable paths per account/server/symbol
- acquires an instance lease so multiple copies of the EA do not run simultaneously
- restores persistent state after restart, including basket/session values and risk latch state
- updates ATR and ADX state from market data
- checks account and basket risk latches before opening new trades
- manages logical exits, protection reconciliation, and pending close-all logic
- monitors open order history and basket-level P&L/drawdown
- processes entry logic based on bar timing, ADX regime, trend filters, spread gating, and lot escalation rules
- logs and dashboards internal status for operational monitoring

The architecture is stateful and operationally defensive. It explicitly tracks:

- basket ID and active status
- session start and session base balance
- recovery lot progression
- previous basket direction and initial-order direction
- equity-stop latches and cooldown resets
- broker protection re-sync conditions
- spread and ATR gating
- trailing stop and close-all management

The EA is more than a simple indicator-following expert. It is a risk-managed trading engine with multiple protections, persistent state, and a recovery logic structure. That makes it suitable for a multi-branch strategy, but also high-risk if the parameter set is aggressive or market conditions are adverse.

## 2) Facts verified from the source

The following are directly supported by the visible code in the current file:

- The file is an MQL4 EA with `#property strict`.
- It includes `stderror.mqh`.
- Header comments describe it as `HOKKY V7.0` and `#property version "7.00"`.
- The main lifecycle functions are present: `OnInit()`, `OnTick()`, `OnTimer()`, and `OnDeinit()`.
- ATR is evaluated and treated as a required prerequisite for trading (`g_atrValid` and `!g_atrValid` gating).
- It contains explicit drawdown and equity-latch logic using persistent global variables.
- It has a dual-book model using `BOOK_CLASSIC` and `BOOK_PENDULUM`.
- It has a risk configuration audit routine (`AuditRiskConfiguration()`).
- It uses global variables for state persistence across restarts (`K_SCHEMA`, `K_NEXTLOT`, `K_BID`, `K_SSTART`, `K_SBASE`, `K_SPEAK`, `K_EQSTOP`, etc.).
- It supports lease-based single-instance protection and heartbeat renewal.
- It validates lot inputs, spread caps, ATR thresholds, quiet hours, and other safety gates.
- It maintains historical state and caches order arrays to reduce repeated scanning.

Important fact-check note: the source file currently shows `#property version "7.00"` and `HOKKY V7.0 CLEAN`, not a V4.30 claim. Any README or commentary that says V4.30 is likely stale or drifted documentation.

## 3) Reality check and likely mismatches

There are several important mismatches and documentation drift points:

- The file header and version string say `HOKKY V7.0 CLEAN` and `version "7.00"`.
- The `InpMultiplier` value is `1.60` and `InpMaxLevel` is `8`.
- The repository README may describe older hardening notes dated to a V4.30 / refactor era.
- The source is a V7 implementation, even though older documentation may reference a historical V4 review or safe reference.
- The code appears to be a full production-grade EA with explicit lifecycle protection, but it has not been compile-tested in the current environment, so compile validity is not proven here.
- The strategy is operationally sophisticated, but there is no guarantee that the broker-side execution semantics match all internal assumptions.

This suggests the repository contains multiple generations of documentation and versions. The safest interpretation is: the source code is authoritative for the current implementation, while any README claims older than the current file should be treated as historical or partially stale.

## 4) Adversarial review of the design

This EA deserves a skeptical review because the strategy is a recovery/grid system. It is not a passive low-risk strategy. High-risk concerns include:

1. Recovery stacking can amplify exposure.
   - `LOT_MULTIPLIER` and `LOT_RECOVERY` modes increase order size after losses.
   - If market continues against the basket, losses can accelerate quickly.

2. Grid logic can be mathematically fragile in strong trends.
   - The strategy is designed to trade reversals and fades, but continued directional movement can destroy the basket before recovery logic finishes its sequence.

3. Persistent state is operationally risky.
   - Global variables retain information across restarts.
   - If stale state remains, or duplicate magic values are reused, the EA may act on outdated basket assumptions.

4. Broker protection is not absolute.
   - Internal risk checks are valuable, but they still depend on broker acceptance of `ModifyOrder()`, `OrderClose()`, and SL/TP changes.
   - Network lag, slippage, and rejected modifications can create a gap between intended and actual protection.

5. Re-entrant runtime assumptions are not trivial.
   - The system uses crossing checks, basket state, and closure logic in a high-frequency environment.
   - A subtle bug in state transitions can create a dangerous open exposure even if the algorithm looks controlled on paper.

6. No source-level proof of live profitability or simulated robustness.
   - This is a code review, not a validated live-trading confirmation.
   - The strategy may be well-structured but still be unsuitable for certain brokers or instruments.

## 5) Comprehensive SWOT analysis

### Strengths

- Multiple protective layers: account risk stop, book risk stop, latches, state reset support, and broker protection reconciliation.
- Explicit ATR/ADX regime split, which helps distinguish ranging from trending markets.
- Persistent state model that survives restarts to some degree.
- Clear separation between classic and pendulum books.
- Strong internal bookkeeping of basket-level order metrics and session metrics.
- Good operational instrumentation: dashboard, journaling, and global state visibility.

### Weaknesses

- The strategy is fundamentally a recovery/grid system, which is inherently risky in multi-leg adverse movement.
- Persistent state can create stale or invalid assumptions if not carefully validated.
- The EA depends on global variables and shared terminal state, which are fragile in some broker/hosting conditions.
- The code is dense and monolithic; it mixes logic, state management, journal handling, and strategy rules in one large file.
- The repository has documentation drift and version mismatches that can mislead operators.

### Opportunities

- Break the file into clearer subsystem boundaries, such as risk, state, market, trade execution, and exits.
- Add explicit guardrails for invalid parameter combinations before trading starts.
- Add risk-budget accounting for total exposure per book and per session.
- Improve audit logs to record spread, equity, drawdown, and basket decisions at each stage.
- Create a demo-only parameter calibration process and a stricter prelaunch validation checklist.

### Threats

- Persistent trend continuation, gap risk, broker disconnections, and spread spikes can violate assumptions.
- Overconfidence based on a strong-looking state machine can lead to unsafe live use.
- A single wrong magic number, stale global variable, or duplicate instance can dramatically distort the trade plan.
- The strategy can expose large risk in a short time if the market regime breaks from the expected pattern.

## 6) How to overcome the weaknesses

The strongest way to improve the system is not to remove the core strategy but to constrain the risk envelope and codify operational discipline.

Recommended improvements:

- Hard-stop the trade plan when account exposure exceeds configured limits.
- Require conservative defaults for lot escalation, even if the strategy concept is valid.
- Use one basket per symbol and avoid uncontrolled multi-book aggregation unless the account truly supports it.
- Validate broker-side SL/TP after order modification and after fills.
- Replace broad state-reset convenience logic with safer, auditable transitions.
- Add explicit anti-duplicate safety checks for magic numbers and terminal IDs.
- Log every basket creation, close-all trigger, and risk-latch event with enough context to reconstruct the outcome later.

## 7) Risk mitigation plan

These are the most important mitigation steps before live use:

- Start with demo trading only and a small lot size.
- Disable or strongly limit recovery escalation during initial testing.
- Set conservative drawdown caps and session limits.
- Require broker SL/TP confirmation after order placement or modification.
- Use spread and ATR gates that are stricter than defaults in volatile conditions.
- Validate that only one EA instance is running on the account/server/symbol combination.
- Rebuild the parameter set around worst-case drawdown, not only best-case performance.
- Maintain a clear rollback path if the state machine behaves unexpectedly.

## 8) Best-practice MQL4 design pattern to adopt

A safer MQL4 pattern for this type of strategy is:

- `ValidateInputs()` at startup
- `OnInit()` for initialization, magic resolution, and state restoration
- `OnTick()` for fast market checks and quick risk gating
- `OnTimer()` for housekeeping, state maintenance, and noncritical periodic tasks
- `RiskGuard()` to centralize account/basket exposure checks
- `NormalizeLot()` to protect lot scaling and broker minimum compatibility
- `SafeOrderSend()` to centralize execution and retry logic
- `LogTrade()` to record normalized, auditable trade events
- explicit state enums for lifecycle transitions
- protection reconciliation before any new order is allowed
- strict validation before allowing state reset or recovery changes

This pattern reduces hidden logic, lowers debugging burden, and makes the EA easier to reason about under stress.

## 9) Recommended repository position

This repository should be treated as:

- a research and strategy-development project
- a source review and architectural audit artifact
- a place to preserve historical and current EA variants
- a safe documentation space for risk analysis and design improvements

It should not be treated as a turnkey profit engine without broker-specific validation and trader-controlled risk controls.

## 10) What this README update does

This README update:

- paraphrases the core logic of the MQ4 source
- verifies supported facts from the present code
- identifies likely mismatches and documentation drift
- performs an adversarial risk assessment
- summarizes the project in SWOT form
- provides a weakness-overcoming strategy
- suggests risk mitigation steps
- recommends a safer MQL4 design pattern
- explicitly avoids modifying the original MQ4 file

## 11) Final assessment

The EA is sophisticated and operationally layered, but it is not a low-risk strategy. It is a high-complexity grid/recovery trading system with strong internal protections, but strong protections do not eliminate the risk of bad market conditions or state drift. The best path is to keep the strategy in a review/testing context, enforce strict risk controls, and treat any production use as a deliberately constrained, broker-specific operational decision.

This repository is therefore best used for critical review, controlled experimentation, and safer design references rather than direct blind deployment.

## Disclaimer

This project is for strategy review and educational analysis. It is not financial advice, and no source file is a guarantee of profit or risk safety. Grid and recovery systems can lose large amounts under strong trend continuation, slippage, spread widening, and broker execution problems.

The original MQ4 file remains unchanged and is not rewritten automatically by this documentation update.
