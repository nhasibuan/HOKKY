# HOKKY EA Review, Risk Audit, and Safe-Design Notes

This repository contains a single-file MetaTrader 4 Expert Advisor and a review-oriented README. The source file remains intentionally unchanged.

Important: this README is a documentation and audit artifact only. It does not modify the EA source at `EA_HOKKYDJONG_V4_ATR.mq4`.

## 1) Detailed explanation of the attached MQ4 file

The attached source is a complex MQL4 Expert Advisor designed as a stateful risk-managed trading engine. It is not a simple one-trade strategy. It combines two internal operational books:

- Classic book
- Pendulum book

The design is effectively a hybrid of:

- a classic fade / martingale-style recovery engine for ranging or weakly directional conditions
- a pendulum-grid / hedged trend-following engine for more directional market behavior

At the top level, the EA does the following:

- validates configuration and runtime parameters at startup
- computes unique magic numbers and persistent keys per account/server/symbol combination
- acquires instance leases to prevent duplicate runs in the same account context
- restores persistent state after restart, including basket/session values and risk latches
- reads ATR and ADX conditions from market data
- blocks invalid or unsafe trading conditions before new orders are opened
- manages logical exits, protection reconciliation, and close-all procedures
- tracks basket-level P&L, order history, drawdown, and exposure
- processes entries using regime logic, trend filter checks, spread gating, and lot escalation rules
- logs execution, risk, and dashboard state for operational monitoring

### 1.1 Structural design

The EA defines several core concepts:

- `COrderData` stores per-order metadata such as ticket, type, level, open time, open price, lots, and SL/TP state.
- `CBookState` holds the risk and execution state of each book, including buy/sell counts, basket active status, recovery progression, session metrics, and latch conditions.
- `g_bk[BOOK_COUNT]` maintains persistent book state for both engines.
- `g_classicSeen[]` and `g_pendSeen[]` are deduplication/history ring buffers used to avoid repeated processing or redundant trade detection.

This indicates a deliberate architecture designed for operational continuity and runtime safety rather than a trivial indicator signal.

### 1.2 Lifecycle and runtime flow

The runtime flow is clear from the main functions:

- `OnInit()`: initializes arrays, validates inputs, resolves magic numbers, acquires leases, loads persistent state, restores baskets, refreshes market state, and sets the EA into `EA_RUNNING`, `EA_WAIT_ATR`, or `EA_DD_LATCHED` states.
- `OnTick()`: updates market state, refreshes book cache, checks previous open order counts, invokes history state updates, checks risk latches, ensures ATR validity, and eventually calls `ProcessTrading()` when the bar changes.
- `OnTimer()`: performs heartbeat updates, persistent state touching, journal flush, and pending close/fault handling.
- `OnDeinit()`: releases instance leases and shuts down journal/dashboard objects.

This is a robust MQL4 lifecycle pattern, though the code is dense and highly stateful.

### 1.3 Risk and state model

The fundamental risk philosophy is explicit:

- there is an account-level risk gate and per-book risk gate
- equity drawdown can latch the EA into a stopped state
- state resets are possible via `InpStateCommand`
- persistent global variables store basket, session, and recovery state across restarts
- `CheckLatchRelease()` can re-enable the system after a cooldown

The following constants and global state show the design intent:

- `K_SCHEMA`, `K_NEXTLOT`, `K_BID`, `K_SSTART`, `K_SBASE`, `K_SPEAK`, `K_EQSTOP`, `K_EQTIME`, `K_EQWHY`
- `HOKKY_STATE_SCHEMA`
- `PROTECTION_REPAIR_OK`, `PROTECTION_REPAIR_BAD`
- `HEARTBEAT_TOUCH_SEC`

This is not a passive EA; it is designed to survive broker or terminal disruptions while maintaining a controlled risk posture.

### 1.4 ATR and ADX regime logic

The EA explicitly monitors:

- `g_atr` and `g_atrValid`
- `g_adx` and `g_adxValid`

The code gates trading on `!g_atrValid` and checks the market regime before placing or modifying multiple orders. The user inputs include:

- `InpATRPeriod`
- `InpADXPeriod`
- `InpADXThreshold`
- `InpUseADXRegime`
- `InpUseTrendFilter`
- `InpTrendMA_Period`
- `InpTrendTimeframe`

This makes the strategy intention clear: it wants to divide market conditions into trending vs ranging behavior and adjust the trade engine accordingly.

### 1.5 Lot progression and basket management

The lot system is intentionally nontrivial:

- `LOT_FIXED`, `LOT_MULTIPLIER`, `LOT_RECOVERY`
- `InpDbLots` selects the lot progression mode
- `InpMultiplier` and `InpMaxLevel` shape recovery escalations
- `BaseLotsForBook()`, `MaxLevelForBook()`, `PerOrderCap()`, and `NormalizeLotDown()` define consistent scaling and broker compatibility

The design is specifically built so that order size can escalate under loss conditions. This is a classic feature of martingale/recovery systems and is the major source of risk.

### 1.6 Hedge, basket exits, and close-all controls

The code includes explicit close paths and protective actions:

- `ApplyHedgeOffset()` for pendulum hedging offset
- `ManageLogicalExits()`
- `CheckBookRiskStops()`
- `CheckAccountRiskStops()`
- `ReconcileBrokerProtection()`
- `DriveCloseAllFSM()`

This indicates a deliberate attempt to handle failed broker-side protection, stale state, and forced offsetting. It is a sophisticated operational layer but introduces mechanical complexity and failure points.

### 1.7 Dashboard, journaling, and operational transparency

The EA includes:

- dashboard updates
- journaling to `HOKKY_V7_trades.csv`
- heartbeat global variable touch
- risk warnings with throttling

This is an operationally mature pattern for monitoring a live trading bot, especially in multi-book systems.

## 2) Facts verified from the source

The following facts are directly supported by the visible code in the current file:

- The file is an MQL4 Expert Advisor using `#property strict`.
- It includes `stderror.mqh`.
- The file header and metadata say `HOKKY V7.0 CLEAN` and `#property version "7.00"`.
- Major lifecycle functions are present: `OnInit()`, `OnTick()`, `OnTimer()`, and `OnDeinit()`.
- ATR validity is treated as a required gating condition for trading (`g_atrValid` and `!g_atrValid` checks).
- The strategy has a dual-book model using `BOOK_CLASSIC` and `BOOK_PENDULUM`.
- It implements persistent global variable state and risk-latching logic.
- It includes instance lease protection and heartbeat renewal.
- It validates lot inputs, spread caps, ATR thresholds, quiet hours, and risk configuration.
- It maintains order arrays and ring buffers for deduplication/history tracking.
- It contains concrete action flows for drawdown latching, risk resets, and broker protection reconciliation.

Important fact-check note: the source currently says `HOKKY V7.0 CLEAN` and `version "7.00"`, not a V4.30 or V4-era claim. Any documentation claiming V4 or V4.30 should be treated as stale unless corroborated by a separate commit or historical file.

## 3) Reality check and likely mismatches

There are several important drift and documentation issues in the repository story:

- The current source file is clearly V7-era code, not a historical V4 implementation.
- Older README text may mention earlier safe-reference or review variants.
- The repository appears to contain multiple generations of files and notes.
- The code is not compile-verified in this environment, so compile validity is not proven here.
- The strategy is highly complex, and broker-side execution semantics may differ from assumptions in the code.

Therefore, the safest interpretation is: the current file is authoritative for the present implementation, while historical notes and older versions should be treated as documentation drift unless explicitly mapped to a specific commit.

## 4) Adversarial review of the design

This EA deserves a skeptical review because it is a recovery and grid-style system with multiple escalation paths. It is not a low-risk or simplistic trend-following bot.

### 4.1 Recovery stacking can amplify exposure

The `LOT_MULTIPLIER` and `LOT_RECOVERY` modes naturally increase order size after losses. If the market continues against the basket, losses can accelerate sharply. Recovery systems are mathematically vulnerable to prolonged adverse moves.

### 4.2 Grid logic can break under strong directional pressure

The strategy is designed around reversal or fade logic, but continued directional movement can overwhelm the basket before recovery logic completes its sequence. This is a known failure mode in grid/recovery systems.

### 4.3 Persistent state is operationally risky

Global variables survive restarts and can hold stale assumptions. If stale basket state, duplicate magic values, or out-of-sync session values remain, the EA may behave on invalid historical assumptions.

### 4.4 Broker protection is not absolute

Internal risk checks are valuable, but they are still dependent on broker acceptance of order modifications, SL/TP adjustments, and order closures. Network lag, rejected modifications, and spread spikes may create gaps between intended and actual protection.

### 4.5 Structural complexity increases failure probability

The EA mixes market-state logic, risk gating, state persistence, order history, and execution decisions in one large file. This can make debugging difficult under live stress and can hide subtle logic errors behind a polished operational facade.

### 4.6 No source-level proof of live profitability

A code review is not proof of profitability or robustness. The code may be well-structured but still be unsuitable for specific brokers, sessions, or instrument regimes.

## 5) Comprehensive SWOT analysis

### Strengths

- Multiple protective layers: account risk checks, book checks, latches, cooldown resets, and broker reconciliation.
- Explicit ATR/ADX regime split to distinguish ranging vs trending conditions.
- Strong internal bookkeeping for basket state, session metrics, and order history.
- Clear separation between classic and pendulum books.
- Persistent state handling improves restart survivability.
- Professional operational instrumentation via dashboard, heartbeat, and journaling.

### Weaknesses

- The strategy fundamentally relies on recovery/grid logic, which is inherently risky under persistent adverse movement.
- Global variables and persistent state increase the chance of stale or invalid assumptions.
- The file is monolithic and dense, making maintenance and debugging harder.
- Documentation drift and version mismatches can mislead operators.
- The system depends heavily on broker execution behavior, which is outside the code's control.

### Opportunities

- Modularize the EA into risk, market-state, execution, and journaling subsystems.
- Add stricter parameter validation and policy guardrails before live trading.
- Introduce static risk budgets for each book, session, and account exposure level.
- Add audit logs that record spread, drawdown, regime changes, and all close-all triggers.
- Build a reproducible strategy validation checklist before production use.

### Threats

- Long trend continuation or a gap event can cause large adverse movement.
- Broker disconnections or rejected order modifications can create protection gaps.
- Duplicate instances or stale global variables can distort operating assumptions.
- Overconfidence from a sophisticated state machine can lead to unsafe deployment decisions.

## 6) How to overcome the weaknesses

The strongest route is not to eliminate the concept, but to constrain the risk envelope and codify operational discipline.

Recommended improvements:

- hard-stop new entries when total exposure exceeds configured limits
- use conservative defaults for recovery escalation during early validation
- keep one basket per symbol unless there is a demonstrated need for multi-book exposure
- verify broker SL/TP acceptance after every order or modification
- replace broad state-reset logic with strictly auditable transitions
- add anti-duplicate safeguards for magic numbers and terminal-local state
- log every basket creation, close-all trigger, and risk latch with enough context to reconstruct outcomes later

## 7) Risk mitigation plan

Before any live deployment, the following measures are essential:

- Use demo trading first with small lot sizes.
- Disable or strongly reduce recovery escalation during initial testing.
- Set conservative drawdown caps and session loss limits.
- Require broker-side confirmation of SL and TP after order placement/modification.
- Use tighter spread and ATR gates than the defaults during volatile conditions.
- Verify that only one EA instance is active on the account/server/symbol set.
- Test using worst-case drawdown assumptions, not only best-case performance.
- Maintain a rollback path for stale state or incorrect behavior.

## 8) Best-practice MQL4 design pattern to adopt

A safer MQL4 pattern for this type of strategy is:

- `ValidateInputs()` at startup
- `OnInit()` for initialization, magic resolution, and state restoration
- `OnTick()` for fast market checks and risk gating
- `OnTimer()` for housekeeping and periodic maintenance
- `RiskGuard()` to centralize account/basket exposure checks
- `NormalizeLot()` to protect broker minimum compatibility and scale consistency
- `SafeOrderSend()` to centralize execution and retry logic
- `LogTrade()` to maintain normalized, auditable trade events
- explicit lifecycle state enums for strategy transitions
- mandatory broker protection reconciliation before any new order is allowed
- strict validation before allowing recovery or state reset actions

This pattern reduces hidden logic, lowers debugging burden, and makes the EA easier to reason about under stress.

## 9) Recommended repository position

This repository should be treated as:

- a research and strategy-development project
- a source review and architectural audit artifact
- a historical/current EA variant archive
- a safe documentation space for risk analysis and design improvement

It should not be treated as a turnkey profit engine without broker-specific validation and trader-controlled risk controls.

## 10) Final assessment

The EA is sophisticated and operationally layered, but it is not a low-risk strategy. It is a high-complexity recovery/grid system with strong internal protections, but those measures do not eliminate the core risk of adverse market continuation, stale state, or broker-side execution uncertainty.

This repository is best used for critical review, controlled experimentation, and safer design references rather than direct blind deployment.

## 11) Disclaimer

This project is for strategy review and educational analysis. It is not financial advice, and no source file is a guarantee of profit or risk safety. Grid and recovery systems can lose large amounts of capital in adverse conditions. Any live use must be accompanied by conservative risk controls, testing, and independent verification of your broker and account conditions.

The original MQ4 file remains unchanged and is not rewritten automatically by this documentation update.

## 12) Repository status

This README intentionally documents the code as it exists in the repository and focuses on risk realism, verification, and improvement guidance. It does not alter the EA implementation itself.

## 13) Practical conclusion

The current code is best understood as a well-structured but deliberately aggressive multi-book trading engine. It is a serious engineering artifact with lifecycle control, state persistence, and risk accounting. It is also an example of why recovery/grid EAs require especially careful validation before any live use.

This README update is intended to make the risk profile explicit while preserving the integrity of the source file.
