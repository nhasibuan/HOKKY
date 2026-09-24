# HOKKY V4.22 ATR

HOKKY is a single-file MetaTrader 4 Expert Advisor (EA) written in MQL4. The inspected source implements a directional ATR-scaled grid/recovery strategy with basket and per-order exits, persistent state in MT4 terminal global variables, drawdown/session controls, and a best-effort single-instance lease.

> **Status:** This README documents the source at commit `0fe2bae89fd0d5622ad74578c1000348d14d8a3f`. The review is a static source review; it is not a claim of profitable behavior, broker compatibility, or live-trading safety. Compile, Strategy Tester, demo, and broker-specific validation are still required.

## Detailed paraphrase

At startup the EA:

1. Seeds its pseudo-random generator and creates an owner token.
2. Validates a subset of the trading parameters.
3. Resolves a magic number, either from `InpMagicNumber` or from a persisted account/server/symbol-derived value.
4. Builds names for persistent global variables and chart objects.
5. Attempts to acquire an instance lease. A recent heartbeat blocks another instance using the same identity.
6. Loads persisted basket, recovery, session, and risk state.
7. Rebuilds its cache of open market orders for the current symbol and magic number.
8. Optionally purges persisted state, but only when no managed orders are open.
9. Applies an optional, numbered state-reset command.
10. Restores an active basket when open managed orders exist, obtains a closed-bar ATR value, scans history, and enters one of the startup, waiting, running, or drawdown-latched states.

During operation, `OnTick` refreshes the lease heartbeat, ATR, order cache, and history state. It then prioritizes close-all handling, persistent drawdown latches, risk stops, ATR availability, logical exits, and broker-side protection reconciliation. Only after those gates pass does it process a new chart bar and consider opening or adding to a basket. `OnTimer` maintains the heartbeat, persists state, retries pending close-all work, and refreshes the dashboard.

The trading model is directional rather than hedged: an initial position is selected from the relationship between the two most recent completed closes. If a position moves adversely by an ATR-scaled distance, same-direction add-ons may be opened, subject to level, lot, exposure, margin, spread, schedule, and optional trend checks. The source also defines ADX inputs, but their actual runtime use should be confirmed in the remainder of the file before describing ADX as an active filter.

Exits are layered:

- Basket TP and optional basket SL use the current ATR multiplied by the configured factor.
- Optional individual soft exits and individual TP are evaluated on ticks.
- A hard individual stop is reconciled to the broker using `OrderModify` when possible.
- Drawdown, session drawdown, and margin conditions can stop further activity and may request close-all behavior.
- A persistent equity-stop latch can keep the EA from restarting trading until an explicit reset or configured cooldown releases it.

Recovery mode persists the next recovery lot. After a basket closes, a losing basket increases the next base lot by `InpMultiplier`, while a non-losing basket resets it to `InpLots`; per-order and recovery caps are then applied.

## Configuration notes

Important defaults in the inspected source include:

- `InpDbLots = LOT_MULTIPLIER`, `InpLots = 0.01`, `InpMultiplier = 1.60`.
- `InpMaxLevel = 20`, `InpMaxLotPerOrder = 1.00`, `InpMaxTotalLots = 5.00`.
- Basket TP is enabled at an ATR factor of `0.75`; hard protection is enabled at an ATR factor of `6.00`.
- `InpMaxDrawdownPct = 20.0` and `InpMaxSessionDDPct = 12.0`.
- Trend and ADX filters are disabled by default.

Despite names ending in `Pips`, `InpBasketSL_Pips` and `InpHardSLPips` are passed through `ATRDistance()`. In the inspected implementation they are ATR multipliers, not literal pip distances. The same ATR-scaling convention applies to the other distance-style exit inputs.

The source exposes trading-hour, spread, trend, ADX, dashboard, and journal settings. Their operational behavior should be tested against the compiled full file and broker because declarations alone do not prove that an option affects every intended path.

## Functional requirements represented by the source

- Single MQ4 deployment with the standard `stderror.mqh` include.
- Account/server/symbol/magic-scoped identity and persistent global-variable state.
- One active instance lease with a heartbeat and stale-lease timeout.
- ATR derived from a completed bar before trading is allowed.
- Directional initial entries and same-direction ATR-spaced add-ons.
- Fixed, multiplier, and recovery lot modes.
- Basket and individual logical exits plus broker-side hard protection.
- Maximum level, per-order lot, total-lot, margin, spread, and drawdown gates.
- Restart recovery for basket, session, recovery-lot, and equity-latch state.
- Dashboard and optional journal functionality as exposed by inputs.

## SWOT analysis

### Strengths

- **Defensive lifecycle:** initialization, timer, tick, and deinitialization paths are separated, and the explicit EA state enum makes major operating modes visible.
- **Restart continuity:** basket identity, session baseline, peak state, recovery lot, and equity latch are persisted rather than held only in RAM.
- **Volatility adaptation:** ATR-based spacing and exits can adjust to the symbol and timeframe's recent volatility.
- **Exposure controls:** the design includes level, total-lot, per-order, recovery-lot, free-margin, spread, and margin-level controls.
- **Layered protection:** logical exits are supplemented by broker-side SL/TP reconciliation and close-all retry paths.
- **Operational observability:** dashboard, alerts, state reasons, comments, and optional CSV journaling provide useful monitoring hooks.
- **Distribution simplicity:** a single strategy file reduces packaging and dependency problems.

### Weaknesses

- **Grid/recovery convexity:** adverse directional movement can accumulate exposure and losses faster than a user expects, even with caps.
- **Static global-variable state:** terminal global variables are mutable shared state; stale, manually edited, corrupted, or colliding values can change behavior.
- **Single-file maintenance cost:** strategy, persistence, execution, risk, UI, and logging concerns are tightly coupled, making regression testing difficult.
- **ATR is not a risk budget:** multiplying ATR by a factor does not guarantee a fixed monetary loss across symbols, contract sizes, gaps, or leverage.
- **Terminology risk:** pip-suffixed inputs are implemented as ATR factors, which can cause unsafe configuration assumptions.
- **Broker dependence:** execution, stop levels, freeze levels, requotes, disconnections, symbol digits, and market closures can defeat intended timing.

### Opportunities

- Add unit-testable pure functions for lot sizing, risk calculations, basket accounting, and state transitions.
- Replace implicit global-variable schema handling with versioned migration, checksums, timestamps, and explicit corruption recovery.
- Add a maximum monetary loss or percentage-of-equity budget per basket, not only distance and lot caps.
- Add broker/terminal fault-injection tests for partial close-all failure, lost connectivity, invalid stops, and lease races.
- Make every declared input auditable with a configuration table and automated checks that detect unused or weakly enforced inputs.
- Add a separate backtest/reporting harness for spread, slippage, commission, swap, gaps, and worst-case excursion.
- Prefer a modular implementation or generated single-file release so production distribution remains simple without sacrificing testability.

### Threats

- Persistent trends, volatility regime shifts, gaps, and thin liquidity can defeat mean-reversion/grid assumptions.
- Spread widening and slippage can make ATR-scaled exits materially worse than their nominal levels.
- A terminal crash, VPS outage, or lease race can leave positions dependent on already-installed broker protection.
- Incorrect state reset, magic-number reuse, or another EA using the same identity can mix operational ownership.
- Backtest overfitting can hide live execution and regime risks.
- A recovery multiplier can encourage users to increase risk after losses and may approach broker/account limits.

## Verified facts and limitations

The following are directly supported by the inspected source at the pinned commit:

- The source declares `#property strict`, version `4.22`, and a single EA file with `stderror.mqh`.
- `OnInit`, `OnTick`, `OnTimer`, and `OnDeinit` implement the lifecycle.
- The source uses `iATR(..., 1)`, i.e. the last completed bar, and blocks trading while ATR is invalid.
- Open orders are filtered by current symbol and `g_magic`; only market buys and sells are cached.
- Basket state and risk-related values are stored under account/server/symbol/magic-scoped terminal global-variable names.
- A lease uses owner and heartbeat global variables and refuses a fresh competing owner.
- The source explicitly checks the return value of `SafeOrderClose` in individual exits and documents the `CloseAll` return-value hardening in its header.
- The source has explicit operator parentheses in the history order-type/close-time condition.
- `InpBasketSL_Pips` and `InpHardSLPips` are converted through `ATRDistance()`, so they are not literal pip distances in the inspected code.

This review does **not** verify profitability, compile success on a particular MT4 build, broker execution semantics, or the behavior of functions beyond the excerpt available for static inspection. Those claims require reproducible compilation and tests.

## Adversarial review

### High-priority findings

1. **Lease loss does not close positions.** `UpdateHeartbeat()` sets `g_leaseLost` and a protection-fault state, but both `OnTick()` and `OnTimer()` return immediately when `g_leaseLost` is true. Therefore the advertised protection-fault close-all path is bypassed after lease loss. Existing broker-side stops may remain, but the EA no longer actively manages or closes those orders. Decide explicitly whether lease loss should fail closed by closing orders, or fail passive with a documented operator alert and guaranteed broker protection.

2. **Newest-order cache is not reset in `RefreshCache()`.** The function resets counts, lots, averages, and floating P/L, but the displayed source does not reset `g_buyNewestTime`, `g_buyNewestTicket`, `g_buyNewestPrice`, or the sell equivalents. Values from a prior basket or prior side can remain when no order of that side exists, producing stale add-on comparisons after a restart or basket transition. Reset all newest-order fields at the beginning of every cache rebuild.

3. **Distance names can mislead risk configuration.** Pip-suffixed parameters are ATR multipliers. A user setting `6` does not mean six pips; it means six times the current ATR. Rename them or document the conversion in the input comments and dashboard.

### Medium-priority findings

4. **History accounting is stateful and fragile.** `UpdateHistoryState()` resumes from an integer history position. History ordering, broker history visibility, or changes to the selected history range can make position-based incremental accounting miss or double-process records. Rebuild from a stable cursor such as ticket/close-time, or recompute the relevant scoped totals when correctness matters.

5. **Lease time uses local terminal time.** Lease freshness uses `TimeLocal()`, while trading and persistent state use server time (`TimeCurrent()`). Clock changes, VPS drift, daylight changes, or different machines can make a lease appear fresh or stale unexpectedly. Use a clearly defined clock source and test restarts across terminals.

6. **Protection is initially reactive.** Broker SL/TP reconciliation happens after an order is opened and on subsequent processing. A send/modify failure, disconnect, or immediate price move can leave a position temporarily without the intended broker-side protection. The close-all and retry behavior must be tested under forced trade-context failures.

7. **Static validation is incomplete.** The visible `ValidateInputs()` checks key ATR, lot, multiplier, level, and exit conditions, but does not itself reject every potentially unsafe value such as negative drawdown thresholds, invalid session hours, or inconsistent exposure settings. Add explicit range and cross-field validation, and fail closed on invalid risk inputs.

### Required validation before live use

- Compile with the target MT4 build using warnings treated as errors.
- Test the lease race with two terminals, restart timing, local-clock changes, and forced global-variable edits.
- Test every close-all path with requotes, off quotes, trade context busy, market closed, partial success, and terminal disconnects.
- Verify that broker-side hard stops are installed immediately and remain valid when ATR changes.
- Reconcile journal/history totals against broker statements after partial closes and terminal restarts.
- Run stress tests across trending, gapping, high-spread, low-liquidity, and rapidly changing ATR conditions.
- Use demo or a dedicated test account before any live deployment, with a separately enforced account-level loss limit.

## Repository update

- EA source: [`EA_HOKKYDJONG_V4_ATR.mq4`](EA_HOKKYDJONG_V4_ATR.mq4)
- Repository: <https://github.com/nhasibuan/HOKKY>
- Reviewed commit: `0fe2bae89fd0d5622ad74578c1000348d14d8a3f`

## Disclaimer

This project is for educational and strategy-development use. It is not financial advice and is not a guarantee of safety or performance. Grid and recovery trading can lose substantial capital, including during gaps or execution failures. Demo testing, broker validation, independent risk review, and conservative account-level limits are required before live deployment.
