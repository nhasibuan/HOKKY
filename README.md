# HOKKY V4.30 ATR Hardening Review and Safe Reference

This repository is a single-file MetaTrader 4 Expert Advisor project. The primary production file is `EA_HOKKYDJONG_V4_ATR.mq4` and it implements a directional ATR-scaled grid/recovery strategy with persistent state, basket bookkeeping, and layered exits.

The original source file has been left untouched. A new safe reference implementation is included as a single-file, best-practice template in the same repository.

## 1) Detailed explanation

The source is designed around a single-symbol trading loop with a directional recovery grid:

- `OnInit()` validates inputs, resolves a magic number, acquires a single-instance lease, restores persistent state, and sets the EA lifecycle state.
- `OnTick()` updates the ATR, refreshes the order cache, checks risk latches, evaluates logical exits, reconciles broker-side protections, and only then performs new entries.
- `OnTimer()` handles the non-blocking close-all FSM and periodic dashboard refreshes.
- `RefreshCache()` enumerates open orders by symbol and magic number, rebuilds buy/sell buckets, and computes average price and floating PL.
- `ProcessTrading()` prevents hedging, enforces timing and spread gates, and only opens new trades when the basket is valid and in the configured trading window.
- `OpenInitialTrade()` selects the first direction using recent bar relationships and honors the trend filter when enabled.
- `OpenAddonTrade()` adds same-direction grid orders using ATR spacing and lot escalation controls.
- `UpdateHistoryState()` scans historical orders and recomputes basket/session realized P&L and drawdown percentage.
- `ManageLogicalExits()` / `ReconcileBrokerProtection()` trigger basket-level and order-level exits, and broker SL/TP re-sync when protection settings are active.
- Global variables maintain basket state, recovery lot, session baseline, and equity-stop latching across restarts.

The strategy is not a neutral mean-reversion bot; it is purpose-built for directional exposure with recovery after adverse moves. That makes it a classic grid/recovery EA design: profitable short bursts are possible, but persistent trends or gaps can cause large drawdowns when the recovery ladder continues past the risk budget.

## 2) Verified facts and likely mismatches

The following are supported by the inspected source:

- The file is a strict MQL4 EA with `#property strict`, `#property version "4.30"`, and `#include <stderror.mqh>`.
- The lifecycle includes `OnInit`, `OnTick`, `OnTimer`, and `OnDeinit`.
- ATR is derived from `iATR(Symbol(), Period(), InpATRPeriod, 1)` and trading is blocked until the ATR is valid.
- Orders are filtered by current symbol and magic number before any basket or risk logic runs.
- Persistent risk state is stored in global variables under an account/server/symbol/magic keyspace.
- Lease-based single-instance protection is implemented using token and heartbeat checks.
- `InpRequireBrokerSL` is defaulted to `true` and is validated against `InpHardSLPips`.
- The code contains explicit basket and session drawdown checks, spread gating, and lot caps.

The main fact-check issue is documentation drift:

- The file header claims V4.30 deliberately reduced `InpMultiplier` from `1.60` to `1.30` and `InpMaxLevel` from `20` to `8`.
- The actual source still declares `InpMultiplier = 1.60;` and `InpMaxLevel = 8;`.
- That means the hardening comments describe a desired state, but the current code has not fully matched that documented version.

Other important limitations:

- This is a static review only; no compile check, broker validation, or live execution proof is included here.
- Many protections are reactive and broker-dependent; they only work if the terminal and broker execution semantics remain healthy.
- Grid/recovery EAs can underperform under trend continuation, gap risk, spread widening, and execution slippage.

## 3) Adversarial review

High-priority concerns:

1. Risk defaults remain too aggressive for a recovery grid.
   - The strategy still uses lot growth, max level caps, and recovery logic that can force high exposure after adverse moves.

2. Persistent state introduces operational fragility.
   - Global variables are durable and shared; stale state, duplicate magic use, or manual edits can silently distort decision-making.

3. Broker protection is not absolute.
   - A delayed SL/TP modification, partial close, or disconnect can produce a temporary mismatch between intended protection and actual broker-side state.

4. State reset commands are convenience features, not a substitute for safety validation.
   - Resetting the latch or session baseline does not prove the broker state is synchronized with the terminal state.

5. Recovery logic can mathematically beat the lot cap.
   - The logic tries to stop when the lot escalates to a cap, but cap flattening can still create an unstable sequence if other inputs or broker-level constraints interact badly.

## 4) SWOT summary

### Strengths

- Layered lifecycle and risk architecture.
- Persistent basket/session tracking across restarts.
- ATR-normalized spacing and broker protection logic.
- Strong internal bookkeeping and dashboard visibility.
- Single-file deployment simplifies distribution.

### Weaknesses

- Grid/recovery convexity remains inherently risky.
- State persistence and shared terminal state make failures hard to debug.
- The strategy relies on assumptions about volatility and trend reversals that are not guaranteed in live markets.
- A single-file mix of logic, UI, state, and protection reduces maintainability.

### Opportunities

- Split logic into cleaner functions and explicit risk states.
- Add explicit sanity checks for unchecked input combinations.
- Add a strict, audited risk budget per basket and per session.
- Record backtest/export logs for spread, slippage, and worst-case excursion.

### Threats

- Persistent trends, gaps, spread spikes, and slippage can destroy the grid logic.
- If the terminal or VPS is unstable, risk protections may not stay in sync.
- Overconfidence from default parameter names and comments can lead to unsafe live use.

## 5) Repository update status

This README is refreshed to reflect the current source review and a safer design reference. The original EA file remains unchanged.

Reference legacy file:

- `EA_HOKKYDJONG_V4_ATR.mq4`

Reference hardened/safe single-file copy:

- `EA_HOKKYDJONG_V4_ATR_REFRACTOR_SAFE.mq4`

## 6) Clean code in a single MQ4 file

The repository now includes a safe single-file, best-practice MQL4 reference implementation named `EA_HOKKYDJONG_V4_ATR_REFRACTOR_SAFE.mq4`.

Key design principles in that template include:

- strict input validation
- single responsibility functions
- explicit risk gating before entry
- clear lifecycle states
- no silent default tolerance of invalid SL/TP conditions
- no reliance on stale global state without recovery checks
- strict position and exposure caps
- safe logging and audit trail integration

## 7) Weaknesses addressed

The refactor version reduces risk by:

- refusing trade entry when the account is under a configured risk floor
- validating spread, ATR, margin, and exposure levels before trade entry
- requiring broker-side protection when configured
- keeping the state machine explicit and easy to reason about
- avoiding hidden, non-obvious parameter drift between comments and code

## 8) Risk mitigation

The safe template recommends the following:

- use conservative lot sizing and strict max drawdown limits
- enforce one basket/one symbol rule unless explicitly designed
- disable recovery escalation unless verified on demo and with strict limits
- require broker SL/TP validation after each fill
- log every state transition and order action for auditability

## 9) Best-practice MQL4 design pattern

The reference implementation follows a safer MQL4 pattern:

- `ValidateInputs()` at startup
- `OnInit()` for initialization and state recovery
- `OnTick()` for fast safety checks and entry control
- `OnTimer()` for periodic state maintenance and cleanup
- `SafeOrderSend()` for all order execution
- `RiskGuard()` as a central gate before every new order
- `NormalizeLot()` and `AccountExposureOk()` for consistent sizing and limits
- `LogTrade()` for debug/audit events

## 10) Original file protection

The original source at:

`https://github.com/nhasibuan/HOKKY/blob/main/EA_HOKKYDJONG_V4_ATR.mq4`

remains intentionally unchanged. All review and hardening work is represented in documentation and in the new single-file reference copy instead.

## Disclaimer

This project remains a strategy-development and review exercise only. It is not financial advice, and no source file is a guarantee of profit or safety. Grid and recovery systems can lose large amounts of capital under adverse market behavior.
