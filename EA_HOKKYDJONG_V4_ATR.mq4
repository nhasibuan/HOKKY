# HOKKY V4.22 ATR

HOKKY is a single-file MetaTrader 4 Expert Advisor built around ATR-normalized grid and recovery logic. It combines basket-based trading, layered exits, persistent risk state, and a lease-based instance guard to reduce unsafe duplicate execution and improve restart continuity.

## Product purpose

- Automate a disciplined ATR-based grid/recovery strategy.
- Maintain risk state across restarts using Global Variables.
- Protect the account with drawdown, margin, and session safety gates.
- Keep deployment simple by using one self-contained MQ4 file.
- Prefer orderly protection and controlled close-all behavior over aggressive continuation.

## Product requirements

### Functional requirements
1. The EA must run as a single MQ4 source file with no external source dependencies beyond the standard MT4 library set.
2. It must maintain one account-bound magic number and a lease mechanism to prevent duplicate instances from operating against the same account/symbol state.
3. It must validate all critical inputs during initialization and reject unsafe configurations.
4. It must base spacing and exit logic on ATR values.
5. It must support initial basket entry, grid add-on entries, and recovery-lot progression.
6. It must enforce basket-level TP/SL logic, individual hard SL/TP logic, and account/session drawdown limits.
7. It must persist basket state and risk state between restarts using global variables.
8. It must journal significant trade actions when enabled.
9. It must expose a dashboard and state reporting for operator monitoring.
10. It must use safe order wrappers for send, modify, and close operations under transient broker conditions.

### Operational requirements
- Intended for MT4 strategy testing and controlled demo validation.
- Requires a compatible broker account, symbol, and timeframe configuration.
- Trading hours, spread limits, ATR validity, and market context must be checked before creating new trades.
- Invalid lot sizing, invalid ATR settings, or missing exit mechanisms must be rejected at initialization.
- Risk-latch reset and recovery actions must only be processed under safe conditions.

### Non-functional requirements
- Reliability: orders and state must reconcile consistently during runtime and after restart.
- Safety: drawdown, margin, and close-all routines must reduce runaway exposure.
- Maintainability: the code must remain self-contained and readable in a single file.
- Auditability: persistent state and logs must support later review.
- Reproducibility: all trade-critical settings must be explicit and visible in source.

## Best-practice MQL4 design pattern

This implementation follows a defensive MQL4 pattern designed for unstable broker conditions:

- A single lifecycle flow with Init, Timer, Tick, and Deinit handlers.
- Strict validation and initialization gates before trading begins.
- Global variable-backed persistence for recovery and state continuity.
- Cached order and history refresh logic for consistent internal state.
- Explicit state machine covering startup, waiting for ATR, running, close-all pending, drawdown latch, and protection fault states.
- Safe wrappers around OrderSend, OrderModify, and OrderClose to handle transient broker errors.
- Protection routing that triggers an immediate close-all before unsafe continuation.
- Market-context checks covering stop level, spread, margin safety, and trade availability.

## SWOT analysis summary

### Strengths
- Single-file structure makes distribution and deployment straightforward.
- ATR-based spacing adapts order placement to current volatility.
- Persistent state helps maintain continuity after restarts.
- Strong drawdown and risk-latch logic can stop further trade activity when risk exceeds limit.
- Safe trade wrappers improve resilience under broker-side transient errors.

### Weaknesses
- Grid and recovery systems can become dangerous during sustained adverse price action.
- Single-file complexity can make maintenance and debugging harder without disciplined structure.
- Global variable state can drift if stale values or duplicate instances are present.
- The EA depends heavily on broker execution quality and standard MT4 market conditions.

### Opportunities
- Improve observability with richer trade logs and event reporting.
- Add parameter presets for demo validation and controlled strategy testing.
- Expand the system with optional multi-symbol or portfolio logic in a future refactor.
- Add stricter regime filters to reduce poor entries during low-liquidity or erratic market conditions.

### Threats
- Overfitting and unrealistic assumptions can create fragile real-world behavior.
- Recovery logic can increase exposure beyond intended limits during long drawdown periods.
- Spread widening, quote volatility, and stop-level constraints can trigger repeated fail-safe paths.
- Duplicate instances or stale persistence can cause unsafe coordination issues.

## How to overcome the weaknesses

1. Use conservative default parameters and validate them before live deployment.
2. Treat recovery progression as a controlled fallback rather than the central strategy engine.
3. Enforce hard exposure caps before every order is sent.
4. Tie grid spacing and drawdown thresholds to verified historical behavior.
5. Require a demo-validation cycle before using the EA on a real account.
6. Review the reset path and ensure state commands only execute when no managed orders remain open.
7. Monitor broker behavior continuously and block trade entry when market conditions are unsuitable.

## Risk mitigation measures

- Keep basket exits clearly separated from hard individual exits.
- Block new order creation when drawdown or margin thresholds are breached.
- Latch an equity stop after risk events so the strategy does not continue trading in a failed state.
- Close all managed orders through safe close routines when protection is triggered.
- Check spread, stop level, and market readiness before each new order.
- Retry transient trade errors and stop only on persistent or non-transient failures.
- Maintain deterministic reset and recovery behavior through persistent state and confirmed commands.

## Verified fact

This repository contains the single-file EA source and a product requirement brief. The project is intended as a controlled MT4 strategy implementation and should be treated as a strategy artifact requiring validation before any live deployment. It is not a guarantee of profitability or a recommendation to trade real money.

## Adversarial review

The code shows strong defensive engineering compared with a typical naive grid EA. The strongest elements are the state machine, safe order wrappers, drawdown protection, and persistent state management. The biggest weaknesses are the exposure amplification from grid/recovery logic, the complexity of global variable coordination, and the dependency on broker execution quality. In short, this is safer than a basic grid bot, but it remains a high-risk strategy family and should be treated as an advanced experimental system rather than a turnkey investment engine.

## Repository update

The repository has been updated to include the hardened single-file EA and a clearer product requirement document.

- Source file: `EA_HOKKYDJONG_V4_ATR.mq4`
- Repository: https://github.com/nhasibuan/HOKKY
- Product requirements: https://github.com/nhasibuan/HOKKY/blob/main/README.md

## Disclaimer

This project is for educational and strategy-development use only. It is not financial advice. Demo testing, broker validation, and formal risk review are required before any live deployment.

---

HOKKY V4.22 ATR

"ATR-normalized grid/recovery EA with layered exits, persistent risk state, and instance lease."

