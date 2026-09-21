# HOKKY V4.22 ATR

HOKKY is a single-file MetaTrader 4 Expert Advisor focused on ATR-normalized grid/recovery trading with layered exits, persistent risk state, and instance lease protection. This repository is the reference codebase for the hardened rebuild described in the project and is intended for controlled demo testing before deployment to a live account.

## Product purpose

- Automate a directional grid/recovery strategy with ATR-based spacing.
- Maintain a persistent risk ledger across restarts using global variables.
- Enforce drawdown and session protection gates before new trades are opened.
- Support a single-file deployment model to simplify distribution and code review.
- Prioritize safety, restart recovery, and orderly close-all behavior over aggressive automation.

## Product requirements

### Functional requirements
1. The EA must run as a single MQ4 source file with no external dependencies beyond standard MQL4 includes.
2. It must maintain a single account-bound magic number and instance lease to prevent duplicate EA instances from conflicting.
3. It must validate trading inputs at initialization and reject unsafe configurations.
4. It must use ATR as the primary spacing and exit reference for basket and individual entries.
5. It must support initial basket entry, grid add-on entries, and recovery-lot progression.
6. It must enforce basket-level TP/SL logic, individual hard SL/TP logic, and account/session drawdown limits.
7. It must persist basket state and risk state across restarts via global variables.
8. It must maintain a journal log of major trade actions when enabled.
9. It must support dashboard labeling and state reporting for monitoring.
10. It must use safe order functions to modify, close, or protect orders under transient broker conditions.

### Operational requirements
- Intended for MT4 strategy testing and controlled demo validation.
- Requires a broker account / symbol / timeframe configuration that supports the relevant trading logic.
- Trading hours, maximum spread, ATR validity, and order protection conditions must be checked before opening new positions.
- Input validation must block invalid lot sizing, invalid ATR settings, or non-existent exit mechanisms.
- Any configured risk latch must require explicit reset or recovery logic.

### Non-functional requirements
- Reliability: Orders and state must be reconciled consistently during runtime and after restart.
- Safety: Risk stops and close-all routines must be able to prevent runaway exposure.
- Maintainability: Code must be self-contained and understandable in a single file.
- Auditability: Persistent risk state and journal entries should support later review.
- Reproducibility: Critical parameters must be explicit and visible in the source for testing and review.

## Best-practice MQL4 design pattern used

This implementation follows a defensive MQL4 design pattern intended for high-friction broker conditions:

- Single entrypoint lifecycle with init, timer, tick, and deinit functions.
- Atomic validation and initialization gates before trading begins.
- Global variable backed persistent state for strategy continuity and recovery.
- Cache refresh pattern for order state and history accumulation.
- Explicit state machine for startup, waiting for ATR, running, close-all pending, drawdown latch, and protection fault.
- Safe wrappers around OrderSend, OrderModify, and OrderClose to retry transient broker errors.
- Protection routes to trigger a fast close-all before the EA continues unsafe behavior.
- Local safety checks for stop-level, spread, margin, and market context usability before sending trades.

## SWOT analysis summary

### Strengths
- Single-file architecture minimizes distribution complexity.
- ATR-based grid spacing makes order placement and exits adaptive to volatility.
- Persistent state reduces the risk of forgetting prior risk context after restart.
- Strong risk-latch logic can stop the strategy from continuing after a drawdown breach.
- Safe order wrappers make retries and transient broker errors more resilient.

### Weaknesses
- Grid and recovery systems can become high-risk if volatility spikes or adverse momentum persists.
- Single-file complexity makes debugging and maintenance harder without disciplined code organization.
- Global-variable state can drift if the EA is not properly reset or if multiple instances conflict.
- The code depends heavily on broker behavior and standard MT4 market conditions, which may vary widely.

### Opportunities
- Improve observability with richer reporting and event logs.
- Add controlled strategy parameter presets for demo sessions and paper testing.
- Introduce optional portfolio logic or multi-symbol support in a future modular refactor.
- Add stricter market regime filters to reduce poor entry quality during high-volatility or low-liquidity periods.

### Threats
- Over-optimization and unrealistic assumptions can produce fragile behavior in live trading.
- Recovery logic may increase exposure beyond intended risk limits under extended losses.
- Broker outages, spread widening, or invalid stop conditions can trigger repeated fail-safe paths.
- Duplicate instances or stale global variables can cause unintended coordination issues.

## How to overcome the weaknesses

1. Use conservative input defaults and validate them before live deployment.
2. Treat recovery progression as a controlled fallback, not a strategy core.
3. Add hard exposure caps and enforce them before each order send.
4. Keep the grid spacing and drawdown thresholds grounded in actual prior test history.
5. Require a demo-validation loop before using the EA on a live account.
6. Review the persistent state reset path and ensure commands are only processed when no open managed orders exist.
7. Monitor broker behavior and spread conditions continuously so trades are blocked when the environment is not suitable.

## Risk mitigation measures

- Drawing a strict difference between basket-level exits and individual hard exits.
- Preventing new orders when drawdown or margin risk exceeds thresholds.
- Latching an equity stop after risk events so the EA does not continue trading in a failed state.
- Closing all managed orders using safe close routines during protection sequences.
- Checking spread, stop-level, and market context before order placement.
- Retrying transient trade errors and stopping only on non-transient conditions.
- Persisting reset commands and risk state through global variables for deterministic restarts.

## Verified fact

This repository currently contains the single-file EA source and a minimal README scaffold. The project is intended as a focused, self-contained MQL4 strategy implementation and is not a finished live-trading guarantee. It must be treated as a controlled strategy artifact requiring validation before real-money use.

## Adversarial review

This code demonstrates competent MQL4 guardrails but still carries the inherent dangers of grid/recovery logic. The strongest positives are the professional state machine, safe wrappers, drawdown enforcement, and persistent risk logic. The main weaknesses are exposure growth, global state complexity, and dependence on broker execution behavior. The code is safer than a naive grid EA, but it is not risk-free. It should be considered a defensive framework for a discretionary strategy concept rather than a guaranteed profit engine.

## Repository update

The repository is updated to include the hardened single-file EA and this product requirement summary.

- Source file: `EA_HOKKYDJONG_V4_ATR.mq4`
- Repository: https://github.com/nhasibuan/HOKKY
- Product requirements: https://github.com/nhasibuan/HOKKY/blob/main/README.md

## Disclaimer

This project is for educational and strategy-development use. It is not financial advice. Demo testing, broker validation, and risk review are required before any live deployment.

---

HOKKY V4.22 ATR

"ATR-normalized grid/recovery EA with layered exits, persistent risk state, and instance lease."



