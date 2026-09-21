//+------------------------------------------------------------------+
//|                                     EA_HOKKYDJONG_V4_ATR.mq4     |
//| Hardened single-file ATR rebuild of HOKKY V3.                    |
//|                                                                  |
//| IMPORTANT - All six distance inputs are ATR MULTIPLIERS:         |
//|   InpDistance, InpTP, InpIndivTP, InpBasketSL_Pips,              |
//|   InpSL, InpHardSLPips                                           |
//| ATR = iATR(Symbol(), Period(), InpATRPeriod, 1) - last CLOSED    |
//| bar. Recalculated once per new chart bar.                        |
//|                                                                  |
//| V4.10 hardening (preserved):                                     |
//|   - ADX + DI+ / DI- trend filter (with threshold)                |
//|   - Higher-timeframe MA trend filter (chart TF independent)      |
//|   - Recovery lot hard cap (InpMaxRecoveryLot)                    |
//|   - Initial-trade counter resets on session reset                |
//|   - Single margin check per order (removed double-check race)    |
//|   - Close-all retry pass (3 passes with Sleep)                   |
//|   - ATR-contraction hard-SL routed through state machine         |
//|   - Incremental history processing (O(delta) not O(n))           |
//|   - Improved hash range (2B vs 100M - fewer collisions)          |
//|   - CSV trade journal (MQL4/Files/HOKKY_trades.csv)              |
//|   - Dashboard throttle 5s; RefreshRates removed from ConformStops|
//|                                                                  |
//| V4.20 hardening (this build):                                    |
//|   - FIX: ECN naked-send fallback was unreachable (error code was |
//|     reset inside SendMarketAttempt before caller read it).       |
//|     Now uses a -2 sentinel.                                      |
//|   - FIX: lease loss no longer routes the OLD instance into       |
//|     close-all (stands down silently; the new owner acts).        |
//|   - OnTimer now drives close-all retries and cooldown checks     |
//|     during tickless periods (weekends, quiet markets).           |
//|   - ConformStops now enforces broker STOPLEVEL / FREEZELEVEL.    |
//|   - TriggerRiskStop sets g_latchAfterClose (was read-only).      |
//|   - Heartbeat touches persistent GVs hourly (MQL4 GlobalVariables|
//|     expire 4 weeks after last use on long uptimes).              |
//|   - Broker MINLOT validation; Alert() on risk latch / fault.     |
//|   - Journal inputs (InpJournalEnabled / InpJournalFile).         |
//|                                                                  |
//| RECONSTRUCTED SECTIONS:                                          |
//|   SafeOrderClose, CloseAllOwnOrdersPass, IsTradeContextUsable,   |
//|   IsTransientTradeError, IsWithinTradingHours,                   |
//|   CurrentSpreadPoints, ConformStops, NormalizePrice,             |
//|   NormalizeLotDown, LotDigits, LotEpsilon, PositiveHash,         |
//|   GenerateMagicNumber, WarnThrottled, LogTrade, IsTrendAligned,  |
//|   TouchPersistentState, dashboard functions, StateText.          |
//+------------------------------------------------------------------+
#property strict
#property copyright "HOKKY V4 ATR - hardened single-file rebuild"
#property link      "https://github.com/nhasibuan/HOKKY"
#property version   "4.20"
#property description "ATR-normalized grid/recovery EA with layered exits, persistent risk state, and instance lease."

#include <stderror.mqh>

//--- Lot sizing
enum ENUM_LOT_MODE
  {
   LOT_FIXED      = 0,
   LOT_MULTIPLIER = 1,
   LOT_RECOVERY   = 2
  };

//--- Drawdown basis
enum ENUM_DD_MODE
  {
   DD_ACCOUNT     = 0,
   DD_EA_FLOATING = 1
  };

//--- Persistent DD latch release
enum ENUM_EQUITY_RESET
  {
   EQRESET_LATCHED  = 0,
   EQRESET_COOLDOWN = 1
  };

//--- Runtime state
enum ENUM_EA_STATE
  {
   EA_STARTING          = 0,
   EA_WAIT_ATR          = 1,
   EA_RUNNING           = 2,
   EA_CLOSE_ALL_PENDING = 3,
   EA_DD_LATCHED        = 4,
   EA_PROTECTION_FAULT  = 5
  };

//--- Persistent-state command (bump InpStateCommandId to apply once)
enum ENUM_STATE_COMMAND
  {
   STATE_KEEP            = 0,
   STATE_RESET_DD_LATCH  = 1,
   STATE_RESET_RECOVERY  = 2,
   STATE_RESET_SESSION   = 3,
   STATE_RESET_ALL_RISK  = 4
  };

//--- General
input string            InpEA_Comment               = "HOKKY_V4_ATR";
input int               InpMagicNumber              = 0;      // 0 = persisted auto magic per account/server/symbol
input int               InpSlippage                 = 3;      // POINTS
input string            InpObjectPrefix             = "HOKKY_V4_";
input bool              InpPurgeStateOnInit         = false;  // One-shot; refused while own orders are open
input ENUM_STATE_COMMAND InpStateCommand            = STATE_KEEP;
input int               InpStateCommandId           = 0;      // Change to a new positive value to apply once

//--- Trade execution
input bool              InpAllowNewBaskets          = true;
input bool              InpAllowAddons              = true;
input int               InpLoop                     = 10000;  // Max initial trades per attach session
input int               InpStartTrade               = 0;      // Server hour, 0..24
input int               InpEndTrade                 = 24;     // Server hour, 0..24
input double            InpMaxSpreadPoints          = 40.0;   // POINTS, 0 = off

//--- ATR (all multipliers)
input int               InpATRPeriod                = 14;
input double            InpDistance                 = 1.00;   // ATR multiple: grid spacing
input double            InpTP                       = 0.75;   // ATR multiple: basket TP
input double            InpIndivTP                  = 0.00;   // ATR multiple: individual TP, 0 = off
input double            InpBasketSL_Pips            = 4.00;   // LEGACY NAME; ATR multiple
input double            InpSL                       = 0.00;   // ATR multiple: logical soft SL, 0 = off
input double            InpHardSLPips               = 6.00;   // LEGACY NAME; ATR multiple, broker hard SL

//--- Grid and lots
input ENUM_LOT_MODE     InpDbLots                   = LOT_MULTIPLIER;
input double            InpLots                     = 0.01;
input double            InpMultiplier               = 1.60;
input int               InpMaxLevel                 = 20;
input double            InpMaxLotPerOrder           = 1.00;   // Lots, 0 = off
input double            InpMaxTotalLots             = 5.00;   // Lots, 0 = off
input double            InpMaxRecoveryLot           = 0.10;   // ABSOLUTE CAP on next recovery lot, 0 = off

//--- Exit ownership
input bool              InpUseBasketTP              = true;
input bool              InpUseBasketSL              = false;
input int               InpMinModifyPoints          = 10;     // POINTS

//--- Risk
input ENUM_DD_MODE      InpDDMode                   = DD_EA_FLOATING;
input double            InpMaxDrawdownPct           = 20.0;   // Account/EA floating DD %, 0 = off
input double            InpMaxSessionDDPct          = 12.0;   // Own realized+floating high-water DD %, 0 = off
input bool              InpCloseAllOnDDStop         = true;
input ENUM_EQUITY_RESET InpDDResetMode              = EQRESET_LATCHED;
input int               InpDDCooldownMin            = 0;
input double            InpMinMarginLevel           = 150.0;  // Emergency %, 0 = off

//--- Trend filters
input bool              InpUseTrendFilter           = false;
input bool              InpTrendFilterAddons        = true;
input int               InpTrendMA_Period           = 50;
input ENUM_MA_METHOD    InpTrendMA_Method           = MODE_EMA;
input ENUM_TIMEFRAMES   InpTrendTimeframe           = PERIOD_H1; // Higher TF for MA confirmation

//--- ADX / DI filter
input bool              InpUseADXFilter             = false;
input int               InpADXPeriod                = 14;
input double            InpADXThreshold             = 20.0;   // Min ADX to consider trending
input bool              InpADXUseDI                 = true;   // Use DI+/DI- direction (else ADX slope)

//--- UI / journal
input bool              InpUseDashboard             = true;
input bool              InpJournalEnabled           = true;   // V4.20: CSV trade journal on/off
input string            InpJournalFile              = "HOKKY_trades.csv";

//--- Cached order record
struct COrderData
  {
   int               ticket;
   int               type;
   datetime          openTime;
   double            openPrice;
   double            lots;
   double            currentSL;
   double            currentTP;
  };

//--- Identity and persistent names
int       g_magic              = 0;
int       g_ownerToken         = 0;
string    g_prefix             = "";
string    g_magicGV            = "";
string    g_ownerGV            = "";
string    g_beatGV             = "";
string    g_objPrefix          = "";
bool      g_lockOwned          = false;
bool      g_leaseLost          = false;   // V4.20: stand-down flag

//--- Runtime state
ENUM_EA_STATE g_state          = EA_STARTING;
string    g_stateReason        = "starting";
datetime  g_lastBarTime        = 0;
datetime  g_atrChartBarTime    = 0;
datetime  g_atrSourceTime      = 0;
double    g_atr                = 0.0;
bool      g_atrValid           = false;
bool      g_protectionDirty    = true;
bool      g_latchAfterClose    = false;
datetime  g_nextRepairTime     = 0;
int       g_lastTradeError     = 0;
int       g_initialTrades      = 0;
int       g_previousOpenCount  = 0;
datetime  g_lastDashboard      = 0;
datetime  g_lastWarning        = 0;

//--- Incremental history tracking
int       g_lastHistoryTotal   = -1;
int       g_lastHistoryProcessed = 0;
datetime  g_lastHistoryScan    = 0;

//--- Order cache
COrderData g_buyOrders[];
COrderData g_sellOrders[];
int       g_buyCount           = 0;
int       g_sellCount          = 0;
double    g_buyLots            = 0.0;
double    g_sellLots           = 0.0;
double    g_buyAvg             = 0.0;
double    g_sellAvg            = 0.0;
double    g_buyNewestPrice     = 0.0;
double    g_sellNewestPrice    = 0.0;
datetime  g_buyNewestTime      = 0;
datetime  g_sellNewestTime     = 0;
int       g_buyNewestTicket    = 0;
int       g_sellNewestTicket   = 0;
double    g_ownFloatingPL      = 0.0;

//--- Basket / recovery
int       g_basketId           = 0;
datetime  g_basketStart        = 0;
bool      g_basketActive       = false;
double    g_basketRealized     = 0.0;
double    g_nextRecoveryLot    = 0.0;

//--- Session risk
datetime  g_sessionStart       = 0;
double    g_sessionBaseBalance = 0.0;
double    g_sessionRealized    = 0.0;
double    g_sessionPeakNet     = 0.0;
double    g_sessionDDPct       = 0.0;

//+------------------------------------------------------------------+
//| Lifecycle                                                        |
//+------------------------------------------------------------------+
int OnInit()
  {
   MathSrand((int)GetTickCount());
   g_ownerToken = (int)(GetTickCount() % 100000000) + MathRand() + 1;
   if(!ValidateInputs())
      return(INIT_PARAMETERS_INCORRECT);
   if(!ResolveMagic())
      return(INIT_FAILED);
   BuildPersistentNames();
   if(!AcquireInstanceLease())
     {
      Print("Initialization blocked: another active instance owns symbol/magic ", Symbol(), "/", g_magic);
      return(INIT_FAILED);
     }
   LoadPersistentState();
   RefreshCache();
   if(InpPurgeStateOnInit)
     {
      if(g_buyCount + g_sellCount > 0)
        {
         Print("InpPurgeStateOnInit refused: managed orders are open.");
         ReleaseInstanceLease();
         return(INIT_PARAMETERS_INCORRECT);
        }
      PurgeRiskState();
      LoadPersistentState();
      Print("Persistent risk/recovery state purged. Set InpPurgeStateOnInit=false.");
     }
   if(!ApplyStateCommand())
     {
      ReleaseInstanceLease();
      return(INIT_PARAMETERS_INCORRECT);
     }
   RestoreOrCreateBasketState();
   UpdateATR(true);
   InvalidateHistoryCache();
   UpdateHistoryState(true);
   if(IsEquityStopLatched())
     {
      g_state = EA_DD_LATCHED;
      g_stateReason = "persistent drawdown latch";
     }
   else
      if(!g_atrValid)
        {
         g_state = EA_WAIT_ATR;
         g_stateReason = "waiting for closed-bar ATR";
        }
      else
        {
         g_state = EA_RUNNING;
         g_stateReason = "monitoring";
        }
   EventSetTimer(1);
   UpdateHeartbeat();
   if(InpUseDashboard)
      UpdateDashboard();
   Print("HOKKY V4.20 ATR init. Magic=", g_magic,
         " ATR=", DoubleToString(g_atr, Digits),
         " source=", TimeToString(g_atrSourceTime),
         " nextRecoveryLot=", DoubleToString(g_nextRecoveryLot, LotDigits(MarketInfo(Symbol(), MODE_LOTSTEP))));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   ReleaseInstanceLease();
   DeleteOwnObjects();
   Print("HOKKY V4.20 ATR deinitialized. Reason=", reason);
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   UpdateHeartbeat();
   if(g_leaseLost)
      return;

   TouchPersistentState();

   if(g_state == EA_CLOSE_ALL_PENDING)
     {
      if(CloseAllOwnOrdersPass())
        {
         RefreshCache();
         if(g_buyCount + g_sellCount == 0)
           {
            FinalizeBasket();
            if(g_latchAfterClose || g_state == EA_PROTECTION_FAULT)
               LatchEquityStop(g_stateReason);
            else
              {
               g_state = g_atrValid ? EA_RUNNING : EA_WAIT_ATR;
               g_stateReason = "basket closed";
              }
            g_latchAfterClose = false;
           }
        }
      UpdateDashboardThrottled();
      return;
     }
   CheckLatchRelease();

   if(InpUseDashboard && TimeCurrent() - g_lastDashboard >= 5)
     {
      g_lastDashboard = TimeCurrent();
      UpdateDashboard();
     }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateHeartbeat();
   if(g_leaseLost)
      return;

   bool newBar = UpdateATR(false);
   RefreshCache();

   int openCount = g_buyCount + g_sellCount;
   if(g_previousOpenCount > 0 && openCount == 0)
      FinalizeBasket();
   g_previousOpenCount = openCount;

   UpdateHistoryState(false);

   if(g_state == EA_CLOSE_ALL_PENDING || g_state == EA_PROTECTION_FAULT)
     {
      bool protectionFault = (g_state == EA_PROTECTION_FAULT);
      if(CloseAllOwnOrdersPass())
        {
         RefreshCache();
         if(g_buyCount + g_sellCount == 0)
           {
            FinalizeBasket();
            if(g_latchAfterClose || protectionFault)
               LatchEquityStop(g_stateReason);
            else
              {
               g_state = g_atrValid ? EA_RUNNING : EA_WAIT_ATR;
               g_stateReason = "basket closed";
              }
            g_latchAfterClose = false;
           }
        }
      UpdateDashboardThrottled();
      return;
     }

   CheckLatchRelease();
   if(IsEquityStopLatched())
     {
      g_state = EA_DD_LATCHED;
      UpdateDashboardThrottled();
      return;
     }

   if(CheckRiskStops())
     {
      UpdateDashboardThrottled();
      return;
     }

   if(!g_atrValid)
     {
      g_state = EA_WAIT_ATR;
      g_stateReason = "ATR invalid/stale; entries blocked";
      UpdateDashboardThrottled();
      return;
     }

   if(ManageLogicalExits())
     {
      RefreshCache();
      UpdateDashboardThrottled();
      return;
     }

   if(newBar)
      g_protectionDirty = true;
   if(g_protectionDirty || TimeCurrent() >= g_nextRepairTime)
      ReconcileBrokerProtection();

   if(g_state == EA_PROTECTION_FAULT || g_state == EA_CLOSE_ALL_PENDING)
     {
      UpdateDashboardThrottled();
      return;
     }

   g_state = EA_RUNNING;
   g_stateReason = "monitoring";

   if(Time[0] != g_lastBarTime)
     {
      g_lastBarTime = Time[0];
      ProcessTrading();
     }
   UpdateDashboardThrottled();
  }

//+------------------------------------------------------------------+
//| Validation / identity                                            |
//+------------------------------------------------------------------+
bool ValidateInputs()
  {
   if(InpMagicNumber < 0)
      return InitError("InpMagicNumber must be >= 0");
   if(InpATRPeriod < 1)
      return InitError("InpATRPeriod must be >= 1");
   if(InpDistance <= 0.0)
      return InitError("InpDistance must be > 0 ATR");
   if(InpTP < 0.0 || InpIndivTP < 0.0 || InpBasketSL_Pips < 0.0 || InpSL < 0.0 || InpHardSLPips < 0.0)
      return InitError("ATR multipliers must be >= 0");
   if(InpLots <= 0.0)
      return InitError("InpLots must be > 0");
   if(InpMultiplier < 1.0)
      return InitError("InpMultiplier must be >= 1");
   if(InpMaxLevel < 1)
      return InitError("InpMaxLevel must be >= 1");
   if(InpMaxLotPerOrder < 0.0 || InpMaxTotalLots < 0.0 || InpMaxRecoveryLot < 0.0)
      return InitError("Lot caps must be >= 0");
   if(InpSlippage < 0 || InpMinModifyPoints < 0)
      return InitError("Point inputs must be >= 0");
   if(InpDDCooldownMin < 0)
      return InitError("InpDDCooldownMin must be >= 0");
   if(InpMaxDrawdownPct < 0.0 || InpMaxSessionDDPct < 0.0 || InpMinMarginLevel < 0.0)
      return InitError("Risk percentages must be >= 0");
   if(InpTrendMA_Period < 1)
      return InitError("InpTrendMA_Period must be >= 1");
   if(InpADXPeriod < 1)
      return InitError("InpADXPeriod must be >= 1");
   if(InpADXThreshold < 0.0)
      return InitError("InpADXThreshold must be >= 0");
   if(InpStartTrade < 0 || InpStartTrade > 24 || InpEndTrade < 0 || InpEndTrade > 24)
      return InitError("Trading hours must be 0..24");
   if(InpUseBasketTP && InpTP <= 0.0)
      return InitError("InpTP must be > 0 when basket TP is enabled");
   if(InpUseBasketSL && InpBasketSL_Pips <= 0.0)
      return InitError("Basket SL multiple must be > 0 when enabled");
   if(InpHardSLPips > 0.0 && InpSL > 0.0 && InpHardSLPips <= InpSL)
      return InitError("Hard-SL ATR multiple must be greater than individual soft-SL multiple");
   if(InpHardSLPips > 0.0 && InpUseBasketSL && InpHardSLPips <= InpBasketSL_Pips)
      return InitError("Hard-SL ATR multiple must be greater than basket-SL multiple");

   bool hasExit = (InpUseBasketTP && InpTP > 0.0) || (InpUseBasketSL && InpBasketSL_Pips > 0.0)
                  || InpIndivTP > 0.0 || InpSL > 0.0 || InpHardSLPips > 0.0
                  || InpMaxDrawdownPct > 0.0 || InpMaxSessionDDPct > 0.0;
   if(!hasExit)
      return InitError("No exit or drawdown mechanism is enabled");

   double firstLot = NormalizeLotDown(InpLots);
   if(firstLot <= 0.0)
      return InitError("InpLots is below the broker minimum lot size");
   if(InpMaxTotalLots > 0.0 && firstLot > InpMaxTotalLots + LotEpsilon())
      return InitError("Normalized initial lot exceeds InpMaxTotalLots");
   if(InpUseADXFilter && !InpUseTrendFilter)
      Print("Note: InpUseADXFilter=true has no effect while InpUseTrendFilter=false.");
   return(true);
  }

//+------------------------------------------------------------------+
bool InitError(string text)
  {
   Print("Parameter error: ", text);
   return(false);
  }

//+------------------------------------------------------------------+
bool ResolveMagic()
  {
   string accountKey = IntegerToString(AccountNumber());
   string serverKey  = IntegerToString(PositiveHash(AccountServer()));
   string symbolKey  = IntegerToString(PositiveHash(Symbol()));
   g_magicGV = "H4M_" + accountKey + "_" + serverKey + "_" + symbolKey;
   if(InpMagicNumber > 0)
     {
      g_magic = InpMagicNumber;
      return(true);
     }
   if(GlobalVariableCheck(g_magicGV))
      g_magic = (int)GlobalVariableGet(g_magicGV);
   else
     {
      g_magic = GenerateMagicNumber(Symbol() + AccountServer() + IntegerToString(AccountNumber()));
      GlobalVariableSet(g_magicGV, (double)g_magic);
      GlobalVariablesFlush();
     }
   return(g_magic > 0);
  }

//+------------------------------------------------------------------+
void BuildPersistentNames()
  {
   string root = "H4_" + IntegerToString(AccountNumber()) + "_"
                 + IntegerToString(PositiveHash(AccountServer())) + "_"
                 + IntegerToString(PositiveHash(Symbol())) + "_"
                 + IntegerToString(g_magic) + "_";
   g_prefix    = root;
   g_ownerGV   = root + "OWN";
   g_beatGV    = root + "BEAT";
   g_objPrefix = InpObjectPrefix + IntegerToString(g_magic) + "_";
  }

//+------------------------------------------------------------------+
bool AcquireInstanceLease()
  {
   datetime now = TimeLocal();
   if(!GlobalVariableCheck(g_ownerGV))
      GlobalVariableSet(g_ownerGV, 0.0);
   if(!GlobalVariableCheck(g_beatGV))
      GlobalVariableSet(g_beatGV, 0.0);
   double observed = GlobalVariableGet(g_ownerGV);
   datetime beat   = (datetime)GlobalVariableGet(g_beatGV);
   if(observed != 0.0 && (now - beat) < 15)
      return(false);
   if(!GlobalVariableSetOnCondition(g_ownerGV, (double)g_ownerToken, observed))
      return(false);
   GlobalVariableSet(g_beatGV, (double)now);
   GlobalVariablesFlush();
   g_lockOwned = true;
   return(true);
  }

//+------------------------------------------------------------------+
void UpdateHeartbeat()
  {
   if(!g_lockOwned)
      return;
   if((int)GlobalVariableGet(g_ownerGV) != g_ownerToken)
     {
      g_lockOwned = false;
      g_leaseLost = true;
      g_state = EA_PROTECTION_FAULT;
      g_stateReason = "instance lease lost";
      Alert("HOKKY V4: instance lease lost (another terminal owns ",
            Symbol(), "/", g_magic, "). This instance is standing down.");
      return;
     }
   GlobalVariableSet(g_beatGV, (double)TimeLocal());
  }

//+------------------------------------------------------------------+
void ReleaseInstanceLease()
  {
   if(!g_lockOwned)
      return;
   if((int)GlobalVariableGet(g_ownerGV) == g_ownerToken)
     {
      GlobalVariableSet(g_beatGV, 0.0);
      GlobalVariableSet(g_ownerGV, 0.0);
      GlobalVariablesFlush();
     }
   g_lockOwned = false;
  }

//+------------------------------------------------------------------+
//| Persistent state                                                 |
//+------------------------------------------------------------------+
void LoadPersistentState()
  {
   EnsureGV("SCHEMA", 4.0);
   EnsureGV("NEXTLOT", InpLots);
   EnsureGV("BID", 0.0);
   EnsureGV("BSTART", 0.0);
   EnsureGV("BACTIVE", 0.0);
   EnsureGV("SSTART", (double)TimeCurrent());
   EnsureGV("SBASE", AccountBalance());
   EnsureGV("SPEAK", 0.0);
   EnsureGV("LASTCMD", 0.0);
   g_nextRecoveryLot = GlobalVariableGet(g_prefix + "NEXTLOT");
   if(g_nextRecoveryLot <= 0.0)
      g_nextRecoveryLot = InpLots;
   g_basketId     = (int)GlobalVariableGet(g_prefix + "BID");
   g_basketStart  = (datetime)GlobalVariableGet(g_prefix + "BSTART");
   g_basketActive = (GlobalVariableGet(g_prefix + "BACTIVE") > 0.5);
   g_sessionStart       = (datetime)GlobalVariableGet(g_prefix + "SSTART");
   g_sessionBaseBalance = GlobalVariableGet(g_prefix + "SBASE");
   g_sessionPeakNet     = GlobalVariableGet(g_prefix + "SPEAK");
   if(g_sessionStart <= 0)
      g_sessionStart = TimeCurrent();
   if(g_sessionBaseBalance <= 0.0)
      g_sessionBaseBalance = AccountBalance();
  }

//+------------------------------------------------------------------+
void EnsureGV(string key, double value)
  {
   string name = g_prefix + key;
   if(!GlobalVariableCheck(name))
      GlobalVariableSet(name, value);
  }

//+------------------------------------------------------------------+
void PurgeRiskState()
  {
   string keys[12] = {"NEXTLOT","EQSTOP","EQTIME","BID","BSTART","BACTIVE",
                      "SSTART","SBASE","SPEAK","LASTCMD","SCHEMA","EQWHY"
                     };
   for(int i = 0; i < ArraySize(keys); i++)
      GlobalVariableDel(g_prefix + keys[i]);
   GlobalVariablesFlush();
  }

//+------------------------------------------------------------------+
bool ApplyStateCommand()
  {
   if(InpStateCommand == STATE_KEEP || InpStateCommandId <= 0)
      return(true);
   int last = (int)GlobalVariableGet(g_prefix + "LASTCMD");
   if(last == InpStateCommandId)
      return(true);
   if(g_buyCount + g_sellCount > 0)
     {
      Print("State command refused while managed orders are open.");
      return(false);
     }
   if(InpStateCommand == STATE_RESET_DD_LATCH || InpStateCommand == STATE_RESET_ALL_RISK)
     {
      GlobalVariableDel(g_prefix + "EQSTOP");
      GlobalVariableDel(g_prefix + "EQTIME");
      GlobalVariableDel(g_prefix + "EQWHY");
     }
   if(InpStateCommand == STATE_RESET_RECOVERY || InpStateCommand == STATE_RESET_ALL_RISK)
      GlobalVariableSet(g_prefix + "NEXTLOT", InpLots);
   if(InpStateCommand == STATE_RESET_SESSION || InpStateCommand == STATE_RESET_ALL_RISK)
      ResetSessionState();
   GlobalVariableSet(g_prefix + "LASTCMD", (double)InpStateCommandId);
   GlobalVariablesFlush();
   LoadPersistentState();
   Print("State command applied once. ID=", InpStateCommandId);
   return(true);
  }

//+------------------------------------------------------------------+
void ResetSessionState()
  {
   g_sessionStart       = TimeCurrent();
   g_sessionBaseBalance = AccountBalance();
   g_sessionRealized    = 0.0;
   g_sessionPeakNet     = 0.0;
   g_initialTrades      = 0;
   GlobalVariableSet(g_prefix + "SSTART", (double)g_sessionStart);
   GlobalVariableSet(g_prefix + "SBASE", g_sessionBaseBalance);
   GlobalVariableSet(g_prefix + "SPEAK", 0.0);
   InvalidateHistoryCache();
  }

//+------------------------------------------------------------------+
bool IsEquityStopLatched()
  {
   return(GlobalVariableCheck(g_prefix + "EQSTOP") && GlobalVariableGet(g_prefix + "EQSTOP") > 0.5);
  }

//+------------------------------------------------------------------+
void LatchEquityStop(string reason)
  {
   GlobalVariableSet(g_prefix + "EQSTOP", 1.0);
   GlobalVariableSet(g_prefix + "EQTIME", (double)TimeCurrent());
   GlobalVariableSet(g_prefix + "EQWHY", (double)PositiveHash(reason));
   GlobalVariablesFlush();
   g_state = EA_DD_LATCHED;
   g_stateReason = reason;
   Alert("HOKKY V4 RISK STOP latched on ", Symbol(), ": ", reason,
         ". Reset via state command", (InpDDResetMode == EQRESET_COOLDOWN ? " or cooldown." : "."));
   Print("Risk stop latched: ", reason, ". Reset via state command or cooldown.");
  }

//+------------------------------------------------------------------+
void CheckLatchRelease()
  {
   if(!IsEquityStopLatched())
      return;
   if(InpDDResetMode == EQRESET_COOLDOWN && InpDDCooldownMin > 0)
     {
      datetime when = (datetime)GlobalVariableGet(g_prefix + "EQTIME");
      if(TimeCurrent() - when >= InpDDCooldownMin * 60)
        {
         GlobalVariableDel(g_prefix + "EQSTOP");
         GlobalVariableDel(g_prefix + "EQTIME");
         GlobalVariableDel(g_prefix + "EQWHY");
         ResetSessionState();
         GlobalVariablesFlush();
         g_state = g_atrValid ? EA_RUNNING : EA_WAIT_ATR;
         g_stateReason = "risk cooldown released";
         Print("Risk stop released after cooldown.");
        }
     }
  }

//+------------------------------------------------------------------+
//| ATR service                                                      |
//+------------------------------------------------------------------+
bool UpdateATR(bool force)
  {
   datetime bar = iTime(Symbol(), Period(), 0);
   if(!force && bar == g_atrChartBarTime)
      return(false);
   g_atrChartBarTime = bar;
   double value  = iATR(Symbol(), Period(), InpATRPeriod, 1);
   datetime src  = iTime(Symbol(), Period(), 1);
   if(value > Point * 0.5 && src > 0)
     {
      bool changed = (src != g_atrSourceTime);
      g_atr            = value;
      g_atrSourceTime  = src;
      g_atrValid       = true;
      if(changed)
        {
         g_protectionDirty = true;
         g_nextRepairTime  = 0;
        }
      return(changed);
     }
   g_atrValid = false;
   return(false);
  }

//+------------------------------------------------------------------+
double ATRDistance(double multiplier)
  {
   if(!g_atrValid || multiplier <= 0.0)
      return(0.0);
   return(multiplier * g_atr);
  }

//+------------------------------------------------------------------+
//| Order cache                                                      |
//+------------------------------------------------------------------+
void RefreshCache()
  {
   int oldCount = g_buyCount + g_sellCount;
   g_buyCount = 0;
   g_sellCount = 0;
   g_buyLots = 0.0;
   g_sellLots = 0.0;
   g_buyAvg = 0.0;
   g_sellAvg = 0.0;
   g_buyNewestPrice = 0.0;
   g_sellNewestPrice = 0.0;
   g_buyNewestTime = 0;
   g_sellNewestTime = 0;
   g_buyNewestTicket = 0;
   g_sellNewestTicket = 0;
   g_ownFloatingPL = 0.0;
   ArrayResize(g_buyOrders, 0);
   ArrayResize(g_sellOrders, 0);
   double buyPV = 0.0, sellPV = 0.0;
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != g_magic)
         continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL)
         continue;
      COrderData rec;
      rec.ticket     = OrderTicket();
      rec.type       = type;
      rec.openTime   = OrderOpenTime();
      rec.openPrice  = OrderOpenPrice();
      rec.lots       = OrderLots();
      rec.currentSL  = OrderStopLoss();
      rec.currentTP  = OrderTakeProfit();
      g_ownFloatingPL += OrderProfit() + OrderSwap() + OrderCommission();
      if(type == OP_BUY)
        {
         int n = ArraySize(g_buyOrders);
         ArrayResize(g_buyOrders, n + 1);
         g_buyOrders[n] = rec;
         g_buyCount++;
         g_buyLots += rec.lots;
         buyPV += rec.openPrice * rec.lots;
         if(IsNewer(rec.openTime, rec.ticket, g_buyNewestTime, g_buyNewestTicket))
           { g_buyNewestTime = rec.openTime; g_buyNewestTicket = rec.ticket; g_buyNewestPrice = rec.openPrice; }
        }
      else
        {
         int n = ArraySize(g_sellOrders);
         ArrayResize(g_sellOrders, n + 1);
         g_sellOrders[n] = rec;
         g_sellCount++;
         g_sellLots += rec.lots;
         sellPV += rec.openPrice * rec.lots;
         if(IsNewer(rec.openTime, rec.ticket, g_sellNewestTime, g_sellNewestTicket))
           { g_sellNewestTime = rec.openTime; g_sellNewestTicket = rec.ticket; g_sellNewestPrice = rec.openPrice; }
        }
     }
   if(g_buyLots > 0.0)
      g_buyAvg  = NormalizeDouble(buyPV / g_buyLots, Digits);
   if(g_sellLots > 0.0)
      g_sellAvg = NormalizeDouble(sellPV / g_sellLots, Digits);
   if(oldCount != g_buyCount + g_sellCount)
      g_protectionDirty = true;
  }

//+------------------------------------------------------------------+
bool IsNewer(datetime candidateTime, int candidateTicket, datetime savedTime, int savedTicket)
  {
   if(candidateTime > savedTime)
      return(true);
   if(candidateTime == savedTime && candidateTicket > savedTicket)
      return(true);
   return(false);
  }

//+------------------------------------------------------------------+
//| Basket / recovery                                                |
//+------------------------------------------------------------------+
void RestoreOrCreateBasketState()
  {
   int total = g_buyCount + g_sellCount;
   g_previousOpenCount = total;
   if(total > 0 && !g_basketActive)
     {
      datetime earliest = 0;
      for(int i = 0; i < g_buyCount; i++)
         if(earliest == 0 || g_buyOrders[i].openTime < earliest)
            earliest = g_buyOrders[i].openTime;
      for(int j = 0; j < g_sellCount; j++)
         if(earliest == 0 || g_sellOrders[j].openTime < earliest)
            earliest = g_sellOrders[j].openTime;
      g_basketId++;
      g_basketStart = earliest;
      g_basketActive = true;
      SaveBasketState();
      Print("Inherited open basket assigned ID=", g_basketId, " start=", TimeToString(g_basketStart));
     }
  }

//+------------------------------------------------------------------+
void StartNewBasket()
  {
   g_basketId++;
   g_basketStart  = TimeCurrent();
   g_basketActive = true;
   g_basketRealized = 0.0;
   SaveBasketState();
  }

//+------------------------------------------------------------------+
void SaveBasketState()
  {
   GlobalVariableSet(g_prefix + "BID", (double)g_basketId);
   GlobalVariableSet(g_prefix + "BSTART", (double)g_basketStart);
   GlobalVariableSet(g_prefix + "BACTIVE", g_basketActive ? 1.0 : 0.0);
   GlobalVariablesFlush();
  }

//+------------------------------------------------------------------+
void InvalidateHistoryCache()
  {
   g_lastHistoryProcessed = 0;
   g_lastHistoryTotal     = -1;
   g_lastHistoryScan      = 0;
   g_sessionRealized      = 0.0;
   g_basketRealized       = 0.0;
  }

//+------------------------------------------------------------------+
void UpdateHistoryState(bool force)
  {
   int total = OrdersHistoryTotal();
   if(!force && total == g_lastHistoryTotal && TimeCurrent() - g_lastHistoryScan < 30)
      return;

   if(total < g_lastHistoryProcessed)
     {
      g_lastHistoryProcessed = 0;
      g_sessionRealized      = 0.0;
      g_basketRealized       = 0.0;
     }

   for(int i = g_lastHistoryProcessed; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != g_magic)
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(OrderCloseTime() <= 0)
         continue;
      double net = OrderProfit() + OrderSwap() + OrderCommission();
      if(OrderCloseTime() >= g_sessionStart)
         g_sessionRealized += net;
      if(g_basketActive && OrderOpenTime() >= g_basketStart)
         g_basketRealized += net;
     }
   g_lastHistoryProcessed = total;
   g_lastHistoryTotal     = total;
   g_lastHistoryScan      = TimeCurrent();

   double sessionNet = g_sessionRealized + g_ownFloatingPL;
   if(sessionNet > g_sessionPeakNet)
     {
      g_sessionPeakNet = sessionNet;
      GlobalVariableSet(g_prefix + "SPEAK", g_sessionPeakNet);
     }
   double denom = MathMax(g_sessionBaseBalance + g_sessionPeakNet, 1.0);
   g_sessionDDPct = MathMax(0.0, (g_sessionPeakNet - sessionNet) / denom * 100.0);
  }

//+------------------------------------------------------------------+
void FinalizeBasket()
  {
   if(!g_basketActive)
      return;
   UpdateHistoryState(true);

   if(InpDbLots == LOT_RECOVERY)
     {
      if(g_basketRealized < 0.0)
         g_nextRecoveryLot = NormalizeLotDown(MathMax(InpLots, g_nextRecoveryLot) * InpMultiplier);
      else
         g_nextRecoveryLot = NormalizeLotDown(InpLots);

      if(InpMaxRecoveryLot > 0.0 && g_nextRecoveryLot > InpMaxRecoveryLot)
        {
         Print("Recovery lot capped: ", DoubleToString(g_nextRecoveryLot, 2),
               " -> ", DoubleToString(InpMaxRecoveryLot, 2));
         g_nextRecoveryLot = NormalizeLotDown(InpMaxRecoveryLot);
        }
      if(InpMaxLotPerOrder > 0.0 && g_nextRecoveryLot > InpMaxLotPerOrder)
         g_nextRecoveryLot = NormalizeLotDown(InpMaxLotPerOrder);

      GlobalVariableSet(g_prefix + "NEXTLOT", g_nextRecoveryLot);
     }

   Print("Basket ", g_basketId, " finalized. Net=", DoubleToString(g_basketRealized, 2),
         " nextRecoveryLot=", DoubleToString(g_nextRecoveryLot, LotDigits(MarketInfo(Symbol(), MODE_LOTSTEP))));

   g_basketActive   = false;
   g_basketStart    = 0;
   g_basketRealized = 0.0;
   SaveBasketState();
   InvalidateHistoryCache();
  }

//+------------------------------------------------------------------+
//| Trading engine                                                   |
//+------------------------------------------------------------------+
void ProcessTrading()
  {
   if(!g_atrValid || !IsTradeContextUsable())
      return;
   if(!InpAllowNewBaskets && !InpAllowAddons)
      return;
   if(g_initialTrades >= InpLoop)
     {
      WarnThrottled("Initial-trade limit reached (" + IntegerToString(InpLoop) +
                    "). Reset via session state command.");
      return;
     }
   if(!IsWithinTradingHours())
      return;
   if(InpMaxSpreadPoints > 0.0 && CurrentSpreadPoints() > InpMaxSpreadPoints)
      return;

   int own = g_buyCount + g_sellCount;
   if(g_buyCount > 0 && g_sellCount > 0)
     {
      WarnThrottled("Mixed-side basket detected; new exposure blocked.");
      return;
     }
   if(own == 0)
     {
      if(InpAllowNewBaskets)
         OpenInitialTrade();
      return;
     }
   if(own >= InpMaxLevel || !InpAllowAddons)
      return;

   double distance = ATRDistance(InpDistance);
   if(g_buyCount > 0 && g_buyNewestPrice > 0.0 && g_buyNewestPrice - Ask >= distance)
      if(!InpUseTrendFilter || !InpTrendFilterAddons || IsTrendAligned(OP_BUY))
         OpenAddonTrade(OP_BUY);
   if(g_sellCount > 0 && g_sellNewestPrice > 0.0 && Bid - g_sellNewestPrice >= distance)
      if(!InpUseTrendFilter || !InpTrendFilterAddons || IsTrendAligned(OP_SELL))
         OpenAddonTrade(OP_SELL);
  }

//+------------------------------------------------------------------+
void OpenInitialTrade()
  {
   double close2 = iClose(Symbol(), Period(), 2);
   double close1 = iClose(Symbol(), Period(), 1);
   if(close2 <= 0.0 || close1 <= 0.0 || MathAbs(close2 - close1) < Point * 0.5)
      return;
   int cmd = (close2 > close1) ? OP_SELL : OP_BUY;
   if(InpUseTrendFilter && !IsTrendAligned(cmd))
      return;
   double lot = CalculateLotSize(0);
   StartNewBasket();
   string comment = BuildOrderComment(0);
   int ticket = SafeOrderSend(cmd, lot, comment);
   if(ticket > 0)
     {
      g_initialTrades++;
      RefreshCache();
      g_previousOpenCount = g_buyCount + g_sellCount;
      g_protectionDirty = true;
      LogTrade("OPEN_INIT", ticket, lot, (cmd == OP_BUY ? Ask : Bid), 0, 0, comment);
     }
   else
     {
      if(g_buyCount + g_sellCount == 0)
        {
         g_basketActive = false;
         g_basketStart  = 0;
         SaveBasketState();
        }
     }
  }

//+------------------------------------------------------------------+
void OpenAddonTrade(int cmd)
  {
   int level = g_buyCount + g_sellCount;
   double lot = CalculateLotSize(level);
   string comment = BuildOrderComment(level);
   int ticket = SafeOrderSend(cmd, lot, comment);
   if(ticket > 0)
     {
      RefreshCache();
      g_previousOpenCount = g_buyCount + g_sellCount;
      g_protectionDirty = true;
      LogTrade("OPEN_ADDON", ticket, lot, (cmd == OP_BUY ? Ask : Bid), 0, 0, comment);
     }
  }

//+------------------------------------------------------------------+
bool ExposureAllows(double lot, int cmd)
  {
   if(lot <= 0.0)
      return(false);
   double total = g_buyLots + g_sellLots;
   if(InpMaxTotalLots > 0.0 && total + lot > InpMaxTotalLots + LotEpsilon())
     {
      WarnThrottled("Order blocked by total-lot cap.");
      return(false);
     }
   if(cmd != OP_BUY && cmd != OP_SELL)
      cmd = (g_sellCount > 0) ? OP_SELL : OP_BUY;
   ResetLastError();
   double after = AccountFreeMarginCheck(Symbol(), cmd, lot);
   int err = GetLastError();
   if(after <= 0.0 || err == ERR_NOT_ENOUGH_MONEY)
     {
      WarnThrottled("Order blocked by insufficient free margin.");
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
double CalculateLotSize(int orderIndex)
  {
   double lot = InpLots;
   if(InpDbLots == LOT_MULTIPLIER)
      lot = InpLots * MathPow(InpMultiplier, orderIndex);
   else
      if(InpDbLots == LOT_RECOVERY)
        {
         double base = (g_nextRecoveryLot > 0.0) ? g_nextRecoveryLot : InpLots;
         lot = base * MathPow(InpMultiplier, orderIndex);
        }
   lot = NormalizeLotDown(lot);
   if(InpMaxLotPerOrder > 0.0 && lot > InpMaxLotPerOrder)
      lot = NormalizeLotDown(InpMaxLotPerOrder);
   if(InpMaxRecoveryLot > 0.0 && lot > InpMaxRecoveryLot)
      lot = NormalizeLotDown(InpMaxRecoveryLot);
   return(lot);
  }

//+------------------------------------------------------------------+
string BuildOrderComment(int level)
  {
   return(InpEA_Comment + "|B" + IntegerToString(g_basketId) + "|L" + IntegerToString(level));
  }

//+------------------------------------------------------------------+
//| Logical exits and protection                                     |
//+------------------------------------------------------------------+
bool ManageLogicalExits()
  {
   if(g_buyCount == 0 && g_sellCount == 0)
      return(false);
   double basketTP = ATRDistance(InpTP);
   double basketSL = ATRDistance(InpBasketSL_Pips);
   if(g_buyCount > 0)
     {
      if(InpUseBasketTP && basketTP > 0.0 && Bid >= g_buyAvg + basketTP)
        { TriggerCloseAll("buy basket ATR TP"); return(true); }
      if(InpUseBasketSL && basketSL > 0.0 && Bid <= g_buyAvg - basketSL)
        { TriggerCloseAll("buy basket ATR SL"); return(true); }
     }
   if(g_sellCount > 0)
     {
      if(InpUseBasketTP && basketTP > 0.0 && Ask <= g_sellAvg - basketTP)
        { TriggerCloseAll("sell basket ATR TP"); return(true); }
      if(InpUseBasketSL && basketSL > 0.0 && Ask >= g_sellAvg + basketSL)
        { TriggerCloseAll("sell basket ATR SL"); return(true); }
     }

   bool acted = false;
   double softSL   = ATRDistance(InpSL);
   double indivTP  = ATRDistance(InpIndivTP);
   double hardSL   = ATRDistance(InpHardSLPips);
   for(int i = 0; i < g_buyCount; i++)
     {
      bool exitNow = (softSL > 0.0  && Bid <= g_buyOrders[i].openPrice - softSL)
                     || (indivTP > 0.0 && Bid >= g_buyOrders[i].openPrice + indivTP)
                     || (hardSL > 0.0  && Bid <= g_buyOrders[i].openPrice - hardSL);
      if(exitNow && SafeOrderClose(g_buyOrders[i].ticket, g_buyOrders[i].lots))
        {
         acted = true;
         LogTrade("CLOSE_LOGICAL", g_buyOrders[i].ticket, g_buyOrders[i].lots, Bid, 0, 0, "buy logical exit");
        }
     }
   for(int j = 0; j < g_sellCount; j++)
     {
      bool exitNow = (softSL > 0.0  && Ask >= g_sellOrders[j].openPrice + softSL)
                     || (indivTP > 0.0 && Ask <= g_sellOrders[j].openPrice - indivTP)
                     || (hardSL > 0.0  && Ask >= g_sellOrders[j].openPrice + hardSL);
      if(exitNow && SafeOrderClose(g_sellOrders[j].ticket, g_sellOrders[j].lots))
        {
         acted = true;
         LogTrade("CLOSE_LOGICAL", g_sellOrders[j].ticket, g_sellOrders[j].lots, Ask, 0, 0, "sell logical exit");
        }
     }
   return(acted);
  }

//+------------------------------------------------------------------+
void TriggerCloseAll(string reason)
  {
   g_state = EA_CLOSE_ALL_PENDING;
   g_stateReason = reason;
   Print("Close-all triggered: ", reason);
   if(!CloseAllOwnOrdersPass())
      Print("Close-all incomplete; will retry on subsequent ticks/timer.");
  }

//+------------------------------------------------------------------+
void ReconcileBrokerProtection()
  {
   if(!g_atrValid)
      return;
   if(!IsTradeContextUsable())
     {
      g_nextRepairTime = TimeCurrent() + 5;
      return;
     }
   RefreshRates();
   bool allGood = true;
   for(int i = 0; i < g_buyCount; i++)
      if(!ReconcileOne(g_buyOrders[i]))
         allGood = false;
   for(int j = 0; j < g_sellCount; j++)
      if(!ReconcileOne(g_sellOrders[j]))
         allGood = false;
   g_protectionDirty = !allGood;
   g_nextRepairTime  = allGood ? TimeCurrent() + 60 : TimeCurrent() + 5;
  }

//+------------------------------------------------------------------+
bool ReconcileOne(COrderData &ord)
  {
   double sl = 0.0, tp = 0.0;
   if(InpHardSLPips > 0.0)
      sl = (ord.type == OP_BUY) ? ord.openPrice - ATRDistance(InpHardSLPips)
           : ord.openPrice + ATRDistance(InpHardSLPips);
   if(InpIndivTP > 0.0)
      tp = (ord.type == OP_BUY) ? ord.openPrice + ATRDistance(InpIndivTP)
           : ord.openPrice - ATRDistance(InpIndivTP);

   if(sl > 0.0)
     {
      if((ord.type == OP_BUY && Bid <= sl) || (ord.type == OP_SELL && Ask >= sl))
        {
         Print("Hard-SL breached via ATR contraction on ticket ", ord.ticket,
               "; routing through close-all state machine");
         TriggerCloseAll("hard SL breach ticket " + IntegerToString(ord.ticket));
         return(false);
        }
     }

   ConformStops(ord.type, sl, tp);
   double threshold = MathMax(InpMinModifyPoints * Point, Point * 0.5);
   if(MathAbs(sl - ord.currentSL) < threshold && MathAbs(tp - ord.currentTP) < threshold)
      return(true);
   if(SafeOrderModify(ord.ticket, sl, tp))
     {
      LogTrade("MODIFY", ord.ticket, ord.lots, 0, sl, tp, "reconcile");
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Risk management                                                  |
//+------------------------------------------------------------------+
bool CheckRiskStops()
  {
   if(InpMinMarginLevel > 0.0 && AccountMargin() > 0.0)
     {
      double marginLevel = AccountEquity() / AccountMargin() * 100.0;
      if(marginLevel <= InpMinMarginLevel)
        {
         TriggerRiskStop("margin level " + DoubleToString(marginLevel, 1) + "%", true);
         return(true);
        }
     }
   UpdateHistoryState(false);
   if(InpMaxSessionDDPct > 0.0 && g_sessionDDPct >= InpMaxSessionDDPct)
     {
      TriggerRiskStop("session DD " + DoubleToString(g_sessionDDPct, 2) + "%", true);
      return(true);
     }
   if(InpMaxDrawdownPct <= 0.0)
      return(false);
   double balance = AccountBalance();
   if(balance <= 0.0)
      return(false);
   double dd = (InpDDMode == DD_EA_FLOATING)
               ? MathMax(0.0, -g_ownFloatingPL / balance * 100.0)
               : MathMax(0.0, (balance - AccountEquity()) / balance * 100.0);
   if(dd >= InpMaxDrawdownPct)
     {
      TriggerRiskStop("drawdown " + DoubleToString(dd, 2) + "%", InpCloseAllOnDDStop);
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
void TriggerRiskStop(string reason, bool closeOrders)
  {
   Print("RISK STOP: ", reason);
   g_stateReason = reason;
   if(closeOrders && g_buyCount + g_sellCount > 0)
     {
      g_latchAfterClose = true;
      g_state = EA_CLOSE_ALL_PENDING;
      if(CloseAllOwnOrdersPass())
        {
         RefreshCache();
         if(g_buyCount + g_sellCount == 0)
           {
            FinalizeBasket();
            LatchEquityStop(reason);
           }
        }
     }
   else
      LatchEquityStop(reason);
  }

//+------------------------------------------------------------------+
//| Safe trade operations                                            |
//+------------------------------------------------------------------+
int SafeOrderSend(int cmd, double lot, string comment)
  {
   if(!g_atrValid || !IsTradeContextUsable() || lot <= 0.0)
      return(-1);
   if(!ExposureAllows(lot, cmd))
      return(-1);
   RefreshRates();
   double entry = (cmd == OP_BUY) ? Ask : Bid;
   double sl = 0.0, tp = 0.0;
   if(InpHardSLPips > 0.0)
      sl = (cmd == OP_BUY) ? entry - ATRDistance(InpHardSLPips)
           : entry + ATRDistance(InpHardSLPips);
   if(InpIndivTP > 0.0)
      tp = (cmd == OP_BUY) ? entry + ATRDistance(InpIndivTP)
           : entry - ATRDistance(InpIndivTP);

   ConformStops(cmd, sl, tp);

   int ticket = SendMarketAttempt(cmd, lot, sl, tp, comment);
   if(ticket > 0)
      return(ticket);

   if(ticket != -2)
      return(-1);

   ticket = SendMarketAttempt(cmd, lot, 0.0, 0.0, comment);
   if(ticket <= 0)
      return(-1);
   bool protectedOK = SafeOrderModify(ticket, sl, tp);
   if(protectedOK)
      return(ticket);

   Print("Protection attachment failed for new ticket ", ticket, "; attempting fail-safe close.");
   if(OrderSelect(ticket, SELECT_BY_TICKET) && SafeOrderClose(ticket, OrderLots()))
      return(-1);
   g_state = EA_PROTECTION_FAULT;
   g_stateReason = "unprotected order " + IntegerToString(ticket);
   Alert("HOKKY V4: unprotected order ", ticket, " could not be closed - MANUAL ACTION REQUIRED.");
   return(ticket);
  }

//+------------------------------------------------------------------+
int SendMarketAttempt(int cmd, double lot, double sl, double tp, string comment)
  {
   for(int attempt = 0; attempt < 3; attempt++)
     {
      if(!IsTradeContextUsable())
         return(-1);
      RefreshRates();
      double price = (cmd == OP_BUY) ? Ask : Bid;
      ResetLastError();
      int ticket = OrderSend(Symbol(), cmd, lot, price, InpSlippage,
                             NormalizePrice(sl), NormalizePrice(tp),
                             comment, g_magic, 0,
                             (cmd == OP_BUY) ? clrBlue : clrRed);
      if(ticket > 0)
         return(ticket);
      int err = GetLastError();
      if(err == ERR_INVALID_STOPS)
         return(-2);
      if(!IsTransientTradeError(err))
        {
         Print("OrderSend failed. Error=", err);
         return(-1);
        }
      Sleep(50 + attempt * 50);
     }
   return(-1);
  }

//+------------------------------------------------------------------+
bool SafeOrderModify(int ticket, double newSL, double newTP)
  {
   for(int attempt = 0; attempt < 3; attempt++)
     {
      if(!OrderSelect(ticket, SELECT_BY_TICKET))
         return(false);
      if(OrderCloseTime() > 0)
         return(true);
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != g_magic)
         return(false);
      if(!IsTradeContextUsable())
         return(false);
      int cmd = OrderType();
      double sl = newSL, tp = newTP;
      RefreshRates();
      ConformStops(cmd, sl, tp);
      if(MathAbs(sl - OrderStopLoss()) < Point * 0.5 &&
         MathAbs(tp - OrderTakeProfit()) < Point * 0.5)
         return(true);
      ResetLastError();
      if(OrderModify(ticket, OrderOpenPrice(), NormalizePrice(sl), NormalizePrice(tp), 0, clrNONE))
         return(true);
      int err = GetLastError();
      if(err == ERR_NO_RESULT)
         return(true);
      if(err == ERR_INVALID_STOPS)
        {
         double pad = (attempt + 1) * 2.0 * Point;
         if(cmd == OP_BUY)
           { if(newSL > 0.0) newSL -= pad; if(newTP > 0.0) newTP += pad; }
         else
           { if(newSL > 0.0) newSL += pad; if(newTP > 0.0) newTP -= pad; }
        }
      else
         if(!IsTransientTradeError(err))
           {
            Print("OrderModify failed. Ticket=", ticket, " error=", err);
            return(false);
           }
      Sleep(50 + attempt * 50);
     }
   return(false);
  }

//+------------------------------------------------------------------+
bool SafeOrderClose(int ticket, double lots)
  {
   for(int attempt = 0; attempt < 3; attempt++)
     {
      if(!OrderSelect(ticket, SELECT_BY_TICKET))
         return(false);
      if(OrderCloseTime() > 0)
         return(true);
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != g_magic)
         return(false);
      if(!IsTradeContextUsable())
         return(false);
      RefreshRates();
      double price = (OrderType() == OP_BUY) ? Bid : Ask;
      ResetLastError();
      if(OrderClose(ticket, lots, price, InpSlippage, clrYellow))
         return(true);
      int err = GetLastError();
      if(!IsTransientTradeError(err))
        {
         Print("OrderClose failed. Ticket=", ticket, " error=", err);
         return(false);
        }
      Sleep(50 + attempt * 50);
     }
   return(false);
  }

//+------------------------------------------------------------------+
bool CloseAllOwnOrdersPass()
  {
   if(!IsTradeContextUsable())
      return(false);
   for(int pass = 0; pass < 3; pass++)
     {
      RefreshRates();
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
            continue;
         if(OrderSymbol() != Symbol() || OrderMagicNumber() != g_magic)
            continue;
         int type = OrderType();
         if(type != OP_BUY && type != OP_SELL)
            continue;
         double price = (type == OP_BUY) ? Bid : Ask;
         ResetLastError();
         if(OrderClose(OrderTicket(), OrderLots(), price, InpSlippage, clrYellow))
            LogTrade("CLOSE_ALL", OrderTicket(), OrderLots(), price, 0, 0, g_stateReason);
         else
           {
            int err = GetLastError();
            if(!IsTransientTradeError(err))
               Print("CloseAll failed. Ticket=", OrderTicket(), " error=", err);
           }
        }
      RefreshCache();
      if(g_buyCount + g_sellCount == 0)
         return(true);
      if(pass < 2)
         Sleep(120);
     }
   RefreshCache();
   return(g_buyCount + g_sellCount == 0);
  }

//+------------------------------------------------------------------+
bool IsTradeContextUsable()
  {
   if(IsTesting())
      return(IsTradeAllowed());
   if(IsTradeAllowed() && !IsTradeContextBusy())
      return(true);
   for(int waited = 0; waited < 1000 && IsTradeContextBusy(); waited += 50)
      Sleep(50);
   return(IsTradeAllowed() && !IsTradeContextBusy());
  }

//+------------------------------------------------------------------+
bool IsTransientTradeError(int err)
  {
   switch(err)
     {
      case ERR_SERVER_BUSY:
      case ERR_NO_CONNECTION:
      case ERR_TRADE_TIMEOUT:
      case ERR_PRICE_CHANGED:
      case ERR_OFF_QUOTES:
      case ERR_BROKER_BUSY:
      case ERR_REQUOTE:
      case ERR_TRADE_CONTEXT_BUSY:
      case ERR_TOO_MANY_REQUESTS:
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
bool IsWithinTradingHours()
  {
   if(InpStartTrade == InpEndTrade)
      return(false);
   int hour = TimeHour(TimeCurrent());
   if(InpStartTrade < InpEndTrade)
      return(hour >= InpStartTrade && hour < InpEndTrade);
   return(hour >= InpStartTrade || hour < InpEndTrade);
  }

//+------------------------------------------------------------------+
double CurrentSpreadPoints()
  {
   return((Ask - Bid) / Point);
  }

//+------------------------------------------------------------------+
void ConformStops(int cmd, double &sl, double &tp)
  {
   if(cmd != OP_BUY && cmd != OP_SELL)
      return;
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   double freeze    = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
   double minDist   = MathMax(stopLevel, freeze);
   if(cmd == OP_BUY)
     {
      if(sl > 0.0 && (Bid - sl) < minDist)
         sl = Bid - minDist;
      if(tp > 0.0 && (tp - Bid) < minDist)
         tp = Bid + minDist;
     }
   else
     {
      if(sl > 0.0 && (sl - Ask) < minDist)
         sl = Ask + minDist;
      if(tp > 0.0 && (Ask - tp) < minDist)
         tp = Ask - minDist;
     }
   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);
  }

//+------------------------------------------------------------------+
double NormalizePrice(double price)
  {
   if(price <= 0.0)
      return(0.0);
   return(NormalizeDouble(price, Digits));
  }

//+------------------------------------------------------------------+
double NormalizeLotDown(double lot)
  {
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0.0)
      step = 0.01;
   double result = MathFloor(lot / step + 1e-9) * step;
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   if(maxLot > 0.0 && result > maxLot)
      result = maxLot;
   if(result < MarketInfo(Symbol(), MODE_MINLOT))
      return(0.0);
   return(NormalizeDouble(result, 8));
  }

//+------------------------------------------------------------------+
int LotDigits(double lotStep)
  {
   if(lotStep >= 1.0)
      return(0);
   if(lotStep >= 0.1)
      return(1);
   if(lotStep >= 0.01)
      return(2);
   return(3);
  }

//+------------------------------------------------------------------+
double LotEpsilon()
  {
   return(0.0000001);
  }

//+------------------------------------------------------------------+
int PositiveHash(string text)
  {
   uint hash = 5381;
   int  len  = StringLen(text);
   for(int i = 0; i < len; i++)
      hash = hash * 33 + (uint)StringGetChar(text, i);
   return((int)(hash & 0x7FFFFFFF));
  }

//+------------------------------------------------------------------+
int GenerateMagicNumber(string seed)
  {
   int magic = PositiveHash(seed);
   if(magic <= 0)
      magic = 100000 + (MathAbs(magic) % 100000000);
   return(magic);
  }

//+------------------------------------------------------------------+
void WarnThrottled(string text)
  {
   if(TimeCurrent() - g_lastWarning < 300)
      return;
   g_lastWarning = TimeCurrent();
   Print("WARN: ", text);
  }

//+------------------------------------------------------------------+
void LogTrade(string action, int ticket, double lots, double price,
              double sl, double tp, string note)
  {
   if(!InpJournalEnabled)
      return;
   int handle = FileOpen(InpJournalFile, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ';');
   if(handle == INVALID_HANDLE)
      return;
   FileSeek(handle, 0, SEEK_END);
   if(FileSize(handle) == 0)
      FileWrite(handle, "time","action","ticket","symbol","lots","price","sl","tp",
                "balance","equity","note");
   FileWrite(handle,
             TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
             action,
             IntegerToString(ticket),
             Symbol(),
             DoubleToString(lots, 2),
             DoubleToString(price, Digits),
             DoubleToString(sl, Digits),
             DoubleToString(tp, Digits),
             DoubleToString(AccountBalance(), 2),
             DoubleToString(AccountEquity(), 2),
             note);
   FileClose(handle);
  }

//+------------------------------------------------------------------+
bool IsTrendAligned(int cmd)
  {
   double ma    = iMA(Symbol(), InpTrendTimeframe, InpTrendMA_Period, 0,
                      InpTrendMA_Method, PRICE_CLOSE, 1);
   double close = iClose(Symbol(), InpTrendTimeframe, 1);
   if(ma <= 0.0 || close <= 0.0)
      return(false);
   bool maOk = (cmd == OP_BUY) ? (close > ma) : (close < ma);
   if(!InpUseADXFilter)
      return(maOk);
   double adx = iADX(Symbol(), InpTrendTimeframe, InpADXPeriod, PRICE_CLOSE, MODE_MAIN, 1);
   if(adx < InpADXThreshold)
      return(false);
   if(InpADXUseDI)
     {
      double diP = iADX(Symbol(), InpTrendTimeframe, InpADXPeriod, PRICE_CLOSE, MODE_PLUSDI, 1);
      double diM = iADX(Symbol(), InpTrendTimeframe, InpADXPeriod, PRICE_CLOSE, MODE_MINUSDI, 1);
      bool diOk = (cmd == OP_BUY) ? (diP > diM) : (diM > diP);
      return(maOk && diOk);
     }
   return(maOk);
  }

//+------------------------------------------------------------------+
void TouchPersistentState()
  {
   static datetime lastTouch = 0;
   if(TimeCurrent() - lastTouch < 3600)
      return;
   lastTouch = TimeCurrent();
   int total = GlobalVariablesTotal();
   for(int i = 0; i < total; i++)
     {
      string name = GlobalVariableName(i);
      if(StringFind(name, g_prefix) == 0)
         GlobalVariableSet(name, GlobalVariableGet(name));
     }
  }

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void UpdateDashboardThrottled()
  {
   if(!InpUseDashboard)
      return;
   if(TimeCurrent() - g_lastDashboard < 1)
      return;
   g_lastDashboard = TimeCurrent();
   UpdateDashboard();
  }

//+------------------------------------------------------------------+
string StateText(ENUM_EA_STATE s)
  {
   switch(s)
     {
      case EA_STARTING:
         return("STARTING");
      case EA_WAIT_ATR:
         return("WAIT_ATR");
      case EA_RUNNING:
         return("RUNNING");
      case EA_CLOSE_ALL_PENDING:
         return("CLOSE_ALL");
      case EA_DD_LATCHED:
         return("DD_LATCHED");
      case EA_PROTECTION_FAULT:
         return("PROTECTION_FAULT");
     }
   return("?");
  }

//+------------------------------------------------------------------+
void SetLabel(string id, int x, int y, string text, color clrText, int fontsize)
  {
   string obj = g_objPrefix + id;
   if(ObjectFind(0, obj) < 0)
     {
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, fontsize);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clrText);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
  }

//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   if(!InpUseDashboard)
      return;
   int   x  = 12, y = 22, dy = 15, line = 0;
   color stateClr = clrRed;
   if(g_state == EA_RUNNING)
      stateClr = clrLime;
   else
      if(g_state == EA_WAIT_ATR)
         stateClr = clrYellow;
      else
         if(g_state == EA_CLOSE_ALL_PENDING)
            stateClr = clrOrange;
   double marginLevel = (AccountMargin() > 0.0)
                        ? AccountEquity() / AccountMargin() * 100.0 : 0.0;
   SetLabel("00", x, y + dy*line++, "HOKKY V4.20 ATR | magic " + IntegerToString(g_magic) +
            " | " + Symbol() + " M" + IntegerToString(Period()), clrWhite, 9);
   SetLabel("01", x, y + dy*line++, "State: " + StateText(g_state) + " - " + g_stateReason, stateClr, 9);
   SetLabel("02", x, y + dy*line++, "ATR(" + IntegerToString(InpATRPeriod) + "): " +
            (g_atrValid ? DoubleToString(g_atr, Digits) : "INVALID") +
            "   spread: " + DoubleToString(CurrentSpreadPoints(), 1) + " pts", clrSilver, 9);
   SetLabel("03", x, y + dy*line++, "BUY  n=" + IntegerToString(g_buyCount) +
            "  lots=" + DoubleToString(g_buyLots, 2) +
            "  avg=" + DoubleToString(g_buyAvg, Digits), clrDodgerBlue, 9);
   SetLabel("04", x, y + dy*line++, "SELL n=" + IntegerToString(g_sellCount) +
            "  lots=" + DoubleToString(g_sellLots, 2) +
            "  avg=" + DoubleToString(g_sellAvg, Digits), clrTomato, 9);
   SetLabel("05", x, y + dy*line++, "Float P/L: " + DoubleToString(g_ownFloatingPL, 2) +
            "   basket #" + IntegerToString(g_basketId) +
            (g_basketActive ? " active" : " idle"), clrSilver, 9);
   SetLabel("06", x, y + dy*line++, "Session DD: " + DoubleToString(g_sessionDDPct, 2) +
            "% / " + DoubleToString(InpMaxSessionDDPct, 1) +
            "%   peak: " + DoubleToString(g_sessionPeakNet, 2),
            (InpMaxSessionDDPct > 0.0 && g_sessionDDPct > 0.7 * InpMaxSessionDDPct)
            ? clrOrange : clrSilver, 9);
   SetLabel("07", x, y + dy*line++, "Margin level: " +
            (marginLevel > 0.0 ? DoubleToString(marginLevel, 1) + "%" : "n/a") +
            "   free margin: " + DoubleToString(AccountFreeMargin(), 2), clrSilver, 9);
   SetLabel("08", x, y + dy*line++, "Next recovery lot: " + DoubleToString(g_nextRecoveryLot, 2) +
            "   latch: " + (IsEquityStopLatched() ? "ACTIVE" : "clear"),
            IsEquityStopLatched() ? clrRed : clrSilver, 9);
   SetLabel("09", x, y + dy*line++, "Session realized: " + DoubleToString(g_sessionRealized, 2) +
            "   initial trades: " + IntegerToString(g_initialTrades) + "/" + IntegerToString(InpLoop),
            clrSilver, 9);
   SetLabel("10", x, y + dy*line++, "Not financial advice - demo-test before live use.", clrGray, 8);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
void DeleteOwnObjects()
  {
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
     {
      string name = ObjectName(i);
      if(StringFind(name, g_objPrefix) == 0)
         ObjectDelete(name);
     }
  }
//+------------------------------------------------------------------+
