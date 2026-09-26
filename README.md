# HOKKY V4.30 ATR Hardening Review

HOKKY is a single-file MetaTrader 4 Expert Advisor (EA) written in MQL4. The inspected source implements a directional ATR-scaled grid/recovery strategy with basket and per-order exits, persistent state, and layered risk controls. This review reflects the source at commit `5f69aa0f9947d40a8efaa8b4f4daec6add9710e8`.

> **Status:** This README documents the current source at commit `5f69aa0f9947d40a8efaa8b4f4daec6add9710e8`. The review is a static source review only; it does not claim profitability, broker compatibility, or compile validity for a particular MT4 terminal.

## Detailed paraphrase

At startup the EA:

1. Seeds the random generator and derives an owner token for lease ownership.
2. Validates the basic trading parameters, including lot and ATR values, trade-hour ranges, and exit configuration.
3. Resolves a magic number, either from an explicit input or from a persisted account/server/symbol-scoped global variable.
4. Builds persistent global-variable names and chart object prefixes used for state, lease tracking, and UI objects.
5. Attempts to acquire a single-instance lease, blocking a competing EA instance that uses the same account/server/symbol/magic identity.
6. Loads persisted state for basket, recovery lot, session baseline, and drawdown latch information.
7. Refreshes the open-order cache and previous basket state.
8. Optionally purges stale or incompatible state when `InpPurgeStateOnInit` is enabled and no positions are open.
9. Applies an optional state-reset command when requested and valid.
10. Restores an active basket if open orders already exist, updates the ATR, scans trade history, and sets the EA to a startup, wait-for-ATR, running, close-all-pending, or drawdown-latched state.

During operation, `OnTick` keeps the lease heartbeat alive, refreshes ATR, updates the order cache, and recalculates session/basket history. It prioritizes: close-all handling, drawdown latches, risk-stop checks, ATR validity, logical exits, broker protection reconciliation, and only then trading decisions. The sequence is designed to avoid continuing new trades after a protection fault or drawdown stop.

The trading model is directional rather than hedged. An initial trade is selected from the relationship between the two most recent completed closing prices, and add-on trades are only opened if the grid distance is met and the trend filter passes (if enabled). The code attempts to keep a single basket active per direction, with add-ons only allowed while the basket is open and before the configured level cap is reached.

Exits are layered:

- A basket TP can close the whole basket using ATR-scaled distance.
- Basket and individual SL logic can be evaluated on ticks and in the timer loop.
- Broker-side protection is enforced by modifying or closing orders through the terminal as required.
- A hard stop or close-all state can be triggered by drawdown, session loss, margin, or explicit protection faults.
- Persistent equity-stop latching can keep the EA from restarting new trades until an explicit reset or configured cooldown releases it.

Recovery mode persists the next recovery lot in a global variable. The code intends to increase the recovery lot after losses and reset it after a profitable basket, but it also contains explicit safeguards to stop adding orders when the lot cap has flattened the geometric progression. The design tries to avoid broken averaging math where continued add-ons produce no real benefit.

## Configuration notes

Important defaults visible in the implemented code include:

- `InpDbLots = LOT_MULTIPLIER`, `InpLots = 0.01`, `InpMultiplier = 1.60`.
- `InpMaxLevel = 8`, `InpMaxLotPerOrder = 1.00`, `InpMaxTotalLots = 5.00`.
- Basket TP is enabled by default at `InpTP = 0.75` and broker-side protection is enabled at `InpHardSLPips = 6.00`.
- `InpUseBasketSL = true`, `InpRequireBrokerSL = true`, and `InpUseTrendFilter = true`.
- `InpMaxDrawdownPct = 20.0`, `InpMaxSessionDDPct = 8.0`, and a margin floor of `InpMinMarginLevel = 150.0`.

Important design intent is described in the file header:

- The top comments say V4.30 hardened defaults changed the martingale multiplier from `1.60` to `1.30` and the max level from `20` to `8`.
- The code snippet, however, still currently shows `InpMultiplier = 1.60` and the comments say `InpMaxLevel = 8`, which suggests a mismatch between documented intent and the actual current source state.

The comments also state that `InpBasketSL_Pips` and `InpHardSLPips` are ATR multipliers, not literal pips. The implementation confirms this by routing these inputs through `ATRDistance()`. This is a critical configuration issue because traders may misread these values as literal pip distances.

The source exposes trading-hour, spread, trend, dashboard, and journal settings. Their behavior should be validated in a full MT4 compile and on a demo account because declarations alone do not guarantee operational safety.

## Functional requirements represented by the source

- Single-file MQ4 deployment with `stderror.mqh`.
- Account/server/symbol/magic-scoped identity and persistent state.
- Single instance lease with heartbeat and stale-lease timeout.
- ATR derived from a completed bar before trading is allowed.
- Directional initial entries and same-direction ATR-space add-ons.
- Fixed, multiplier, and recovery lot modes.
- Basket and per-order logical exits plus broker protection.
- Max level, per-order lot, total-lot, spread, margin, and drawdown gating.
- Recovery-lot persistence for basket and session state.
- Dashboard, alerts, and optional CSV journaling as exposed by inputs.

## SWOT analysis

### Strengths

- **Layered safety architecture:** the EA splits lifecycle, state management, risk stops, protection enforceability, and order caching into explicit operational phases.
- **Persistent continuity:** basket identity, session baseline, recovery lot, and drawdown latches are persisted rather than being held only in memory.
- **Volatility adaptation:** ATR spacing, TP/SL distances, and broker protection are normalized to recent volatility instead of fixed pip assumptions.
- **Exposure controls:** lot caps, max total lot, spread gate, max market level, margin floor, and session drawdown checks are all included.
- **Operational observability:** dashboard updates, alerts, state reasons, and journal logging increase visibility into live execution.
- **Single-file simplicity:** one source file reduces packaging complexity and deployment mismatch risk.

### Weaknesses

- **Grid/recovery convexity:** adverse directional moves can pile up exposure faster than expected even with caps.
- **State and persistence complexity:** terminal global variables are mutable shared state; stale values, manual edits, or lease races can distort behavior.
- **Sizing is not a true risk budget:** ATR multipliers do not guarantee a fixed dollar or percentage loss across symbols or market regimes.
- **Broker dependency:** stop levels, requotes, disconnections, spread spikes, and partial closes can defeat intended protection.
- **Terminology ambiguity:** inputs with names like `Pips` are implemented as ATR factors, which is a common source of incorrect user configuration.
- **Single-file maintenance cost:** strategy logic, risk management, UI, persistence, and state transitions are tightly coupled, reducing testability.

### Opportunities

- Add testable pure functions for lot sizing, basket accounting, and risk-stop conditions.
- Replace implicit global-variable schema migration with explicit checksum/version validation and corruption recovery.
- Add a strict monetary drawdown budget per basket and per session in addition to percentage and ATR checks.
- Add fault-injection tests for partial close-all behavior, invalid broker SL/TP, reconnects, and stale lease states.
- Make every input auditable in a configuration table and reject obviously unsafe combinations at startup.
- Add a dedicated backtest harness that records spread, slippage, gaps, and worst-case excursion to compare expected vs. realized risk.

### Threats

- Persistent trends or overnight gaps can defeat mean-reversion assumptions and widen losses dramatically.
- Spread expansion and slippage can materially worsen the practical result of ATR-scaled exits.
- Terminal crash, VPS outage, or lease race can leave positions dependent on broker protection that is not re-established.
- Incorrect state reset, magic-number reuse, or another EA using the same identity can cause mixed ownership of trades.
- Backtest overfitting can hide live execution problems under regime shifts or gap events.
- Recovery-lot escalation can encourage higher risk after losses, especially when `InpMultiplier` is allowed to stay high.

## Verified facts and limitations

The following are directly supported by the inspected source at the pinned commit:

- The source declares `#property strict`, version `4.30`, and includes `stderror.mqh`.
- `OnInit`, `OnTick`, `OnTimer`, and `OnDeinit` implement the EA lifecycle.
- `UpdateATR()` uses `iATR(Symbol(), Period(), InpATRPeriod, 1)` and blocks trading when ATR is invalid.
- Open orders are filtered by the current symbol and magic number before being processed.
- Basket state, recovery lot, and session state are persisted under account/server/symbol/magic-scoped global variables.
- The EA asserts a single active instance lease using heartbeat and token checks.
- The file includes explicit state transitions for `EA_STARTING`, `EA_WAIT_ATR`, `EA_RUNNING`, `EA_CLOSE_ALL_PENDING`, `EA_DD_LATCHED`, and `EA_PROTECTION_FAULT`.
- `InpRequireBrokerSL` defaults to `true` and is validated against `InpHardSLPips`.
- The code includes special logic for cap-flattening and order-addition halting when calculated lots are effectively capped.
- The file header claims a 4.30 hardening plan that changes the martingale default from `1.60` to `1.30` and `MaxLevel` from `20` to `8`, but the visible default declarations in the code still show `InpMultiplier = 1.60` and `InpMaxLevel = 8`.

This review does not verify profitability, compile success on a particular MT4 build, broker execution semantics, or live performance. It is a static review based only on the available source excerpt.

## Adversarial review

### High-priority findings

1. **Risk defaults and documentation are inconsistent.** The file header says V4.30 deliberately reduced the martingale multiplier and max levels, but the code still shows `InpMultiplier = 1.60` while the max level is already `8`. This is a high-risk ambiguity because users and reviewers cannot tell whether the defaults are intentional, stale comments, or an uncommitted mismatch.
2. **Persistent state can silently drift.** Global-variable state is shared and durable across restarts. If a stale or corrupted value survives, the EA can reuse an invalid basket ID, session baseline, or `NEXTLOT` value even after the broker state differs from the terminal state.
3. **Protection is still reactive in important paths.** Broker-side SL/TP reconciliation is not guaranteed to happen immediately; a disconnect, requote, or delay can leave broker protection stale before the next repair pass. This is especially important in a recovery grid strategy.

### Medium-priority findings

4. **State reset commands are not a substitute for safety validation.** `InpStateCommand` can reset risk state, but those commands do not prove that the broker side of the strategy is synchronized with the terminal-side state. This matters in automated or remote deployments.
5. **Lease freshness uses local clock time.** `UpdateHeartbeat()` and `AcquireInstanceLease()` use `TimeLocal()` while trading state and order checks use `TimeCurrent()`. That mismatch can create false stale leases or false lease validity under clock drift, daylight changes, or VPS timing anomalies.
6. **The file still depends on a potentially unsafe strategy premise.** A directional ATR grid with recovery can survive short bursts but can be destroyed by persistent adverse trend, gap risk, or widened spreads. The controls reduce, rather than eliminate, this risk.
7. **Static validation is not exhaustive.** The initializer checks several dangerous conditions, but many edge cases remain unvalidated without a full compile and broker-specific stress test.

### Required validation before live use

- Compile the full file with the target MT4 build using warnings treated as errors.
- Verify the source-state mismatch between the header comments and the code defaults.
- Test heartbeat and stale-lease scenarios across multiple terminals and restarts.
- Validate every close-all and protection-fault path with partial fills, disconnections, and requotes.
- Confirm that broker SL/TP modifications are populated immediately and remain valid when ATR changes.
- Reconcile journal and global-variable state after terminal restarts and partial closes.
- Run demo or dedicated account tests across trending, gapping, and high-spread conditions.
- Use a separately enforced account-level loss limit before any live deployment.

## Repository update

- EA source: [`EA_HOKKYDJONG_V4_ATR.mq4`](EA_HOKKYDJONG_V4_ATR.mq4)
- README: [`README.md`](README.md)
- Repository: <https://github.com/nhasibuan/HOKKY>
- Reviewed commit: `5f69aa0f9947d40a8efaa8b4f4daec6add9710e8`

## Disclaimer

This project is for educational and strategy-development use. It is not financial advice and is not a guarantee of safety or performance. Grid and recovery trading can lose substantial capital, including more than the initial account balance under extreme adverse conditions.
