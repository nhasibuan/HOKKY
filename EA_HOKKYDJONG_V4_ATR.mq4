//+------------------------------------------------------------------+
//|  EA_HOKKY_V7_CLEAN.mq4                                           |
//|  HOKKY V7.0 - Dual-engine ATR EA (classic fade + pendulum grid). |
//|  Complete build. Fixes V6.1 seen-array crash + all V7 hardening. |
//+------------------------------------------------------------------+
#property copyright "HOKKY V7.0 CLEAN - from HOKKY V6.1"
#property link      "https://github.com/nhasibuan/HOKKY"
#property version   "7.00"
#property description "Dual-engine ATR EA: fading martingale in ranging ADX, pendulum grid in trending ADX."
#property strict

#include <stderror.mqh>

//====================================================================
// ENUMS
//====================================================================
enum ENUM_LOT_MODE          { LOT_FIXED = 0, LOT_MULTIPLIER = 1, LOT_RECOVERY = 2 };
enum ENUM_DD_MODE           { DD_ACCOUNT = 0, DD_EA_FLOATING = 1 };
enum ENUM_EQUITY_RESET      { EQRESET_LATCHED = 0, EQRESET_COOLDOWN = 1 };
enum ENUM_HEDGE_OFFSET_SIZE { HEDGE_OFF_FIXED = 0, HEDGE_OFF_PCT = 1 };
enum ENUM_BOOK              { BOOK_CLASSIC = 0, BOOK_PENDULUM = 1, BOOK_COUNT = 2 };
enum ENUM_EA_STATE          { EA_STARTING = 0, EA_WAIT_ATR = 1, EA_RUNNING = 2,
                              EA_CLOSE_ALL_PENDING = 3, EA_DD_LATCHED = 4,
                              EA_PROTECTION_FAULT = 5, EA_ACCOUNT_FAULT = 6
                            };
enum ENUM_STATE_COMMAND     { STATE_KEEP = 0, STATE_RESET_DD_LATCH = 1,
                              STATE_RESET_RECOVERY = 2, STATE_RESET_SESSION = 3,
                              STATE_RESET_ALL_RISK = 4
                            };

//====================================================================
// INPUTS
//====================================================================
input string              InpEA_Comment           = "";
input int                 InpMagicNumber          = 0;
input int                 InpSlippage             = 5;
input int                 InpExitSlippage         = 50;
input bool                InpPurgeStateOnInit     = false;
input ENUM_STATE_COMMAND  InpStateCommand         = STATE_KEEP;
input int                 InpStateCommandId       = 0;
input bool                InpRequireBrokerSL      = true;
input int                 InpLeaseStaleSeconds    = 10;
input bool                InpBlockOnNetting       = true;

input bool                InpUseClassicEngine     = true;
input bool                InpUsePendulumEngine    = true;

input bool                InpAllowNewBaskets      = true;
input bool                InpAllowAddons          = true;
input int                 InpLoop                 = 10000;
input int                 InpStartTrade           = 0;
input int                 InpEndTrade             = 24;
input double              InpMaxSpreadPoints      = 60.0;
input bool                InpUseSpreadATRCap      = true;
input double              InpMaxSpreadATR         = 0.35;

input int                 InpATRPeriod            = 14;
input double              InpDistance             = 1.00;
input double              InpTP                   = 0.75;
input double              InpIndivTP              = 0.00;
input double              InpBasketSL_ATR         = 4.00;
input double              InpSL                   = 0.00;
input double              InpHardSL_ATR           = 6.00;

input ENUM_LOT_MODE       InpDbLots               = LOT_MULTIPLIER;
input double              InpLots                 = 0.01;
input double              InpMultiplier           = 1.60;
input int                 InpMaxLevel             = 8;
input double              InpMaxOrderLot          = 1.00;
input double              InpMaxTotalLots         = 5.00;
input double              InpMaxRecoveryLot       = 0.10;
input bool                InpHaltAddonsWhenCapped = true;

input int                 InpClassicMaxLevel      = 0;
input double              InpClassicLots          = 0.0;
input double              InpClassicMaxOrderLot   = 0.0;
input int                 InpPendulumMaxLevel     = 0;
input double              InpPendulumLots         = 0.0;
input double              InpPendulumMaxOrderLot  = 0.0;

input bool                InpAllowBothDirections  = true;
input bool                InpUseHedgeOffset       = true;
input ENUM_HEDGE_OFFSET_SIZE InpHedgeOffsetSize   = HEDGE_OFF_PCT;
input double              InpHedgeOffsetMinProfit = 0.5;
input double              InpHedgeOffsetMaxLoss   = 2.0;
input int                 InpHedgeOffsetCooldown  = 60;

input bool                InpUseTrailingStop      = true;
input double              InpTrailStartATR        = 1.00;
input double              InpTrailDistanceATR     = 0.50;
input int                 InpTrailStepPoints      = 20;

input bool                InpUseBasketTP          = true;
input bool                InpUseBasketSL          = true;
input int                 InpMinModifyPoints      = 10;

input ENUM_DD_MODE        InpDDMode               = DD_EA_FLOATING;
input double              InpMinEquity            = 0.0;
input double              InpMinMarginLevel       = 150.0;
input double              InpMaxDrawdownPct       = 20.0;
input double              InpMaxBasketLossMoney   = 0.0;
input double              InpMaxSessionDDPct      = 8.0;
input bool                InpCloseAllOnDDStop     = true;
input ENUM_EQUITY_RESET   InpDDResetMode          = EQRESET_COOLDOWN;
input int                 InpDDCooldownMin        = 60;
input int                 InpMaxCloseFailures     = 20;

input bool                InpUseADXRegime         = true;
input int                 InpADXPeriod            = 14;
input double              InpADXThreshold         = 20.0;
input bool                InpADXUseDI             = true;

input bool                InpUseTrendFilter       = true;
input bool                InpTrendFilterAddons    = true;
input int                 InpTrendMA_Period       = 9;
input ENUM_MA_METHOD      InpTrendMA_Method       = MODE_EMA;
input ENUM_TIMEFRAMES     InpTrendTimeframe       = PERIOD_M1;

input bool                InpUseQuietHours        = true;
input int                 InpQuietStartHour       = 23;
input int                 InpQuietEndHour         = 1;

input bool                InpUseDashboard         = true;
input bool                InpJournalEnabled       = true;
input string              InpJournalFile          = "HOKKY_V7_trades.csv";

//====================================================================
// CONSTANTS
//====================================================================
#define HOKKY_STATE_SCHEMA      8.0
#define HOKKY_ID_TAG            "HOKKY_V70"
#define HOKKY_GV_ROOT           "A"
#define HOKKY_GV_MAGIC          "A"

#define K_SCHEMA    "SCHEMA"
#define K_NEXTLOT   "NEXTLOT"
#define K_BID       "BID"
#define K_BSTART    "BSTART"
#define K_BACTIVE   "BACTIVE"
#define K_SSTART    "SSTART"
#define K_SBASE     "SBASE"
#define K_SPEAK     "SPEAK"
#define K_LASTCMD   "LASTCMD"
#define K_LASTDIR   "LASTDIR"
#define K_LASTDIR_SHARED "LASTDIRS"
#define K_EQSTOP    "EQSTOP"
#define K_EQTIME    "EQTIME"
#define K_EQWHY     "EQWHY"

#define LOT_EPSILON             0.0000001
#define TRADE_CTX_WAIT_STEPS    4
#define TRADE_CTX_WAIT_MS       25
#define PROTECTION_REPAIR_OK    60
#define PROTECTION_REPAIR_BAD   5
#define DASHBOARD_THROTTLE      1
#define WARN_THROTTLE_SEC       300
#define HEARTBEAT_TOUCH_SEC     3600
#define HISTORY_RING_MAX        1024
#define TRAIL_LOG_THROTTLE_SEC  30
#define MAX_CLOSE_ATTEMPTS      3
#define MAX_SEND_ATTEMPTS       3
#define CACHE_REFRESH_SEC       1

//====================================================================
// STRUCTS
//====================================================================
struct COrderData
  {
   int               ticket;
   int               type;
   int               level;
   datetime          openTime;
   double            openPrice;
   double            lots;
   double            currentSL;
   double            currentTP;
  };

struct CBookState
  {
   bool              enabled;
   int               magic;
   ENUM_EA_STATE     state;

   int               buyCount, sellCount;
   double            buyLots, sellLots;
   double            buyAvg, sellAvg;
   double            buyPL, sellPL, floatingPL;
   datetime          buyNewestTime, sellNewestTime;
   double            buyNewestPrice, sellNewestPrice;
   int               buyNewestTicket, sellNewestTicket;
   int               buyNewestLevel, sellNewestLevel;

   int               basketId;
   datetime          basketStart;
   bool              basketActive;
   double            basketRealized;
   double            nextRecoveryLot;

   datetime          sessionStart;
   double            sessionBaseBalance;
   double            sessionRealized;
   double            sessionPeakNet;
   double            sessionDDPct;

   int               lastHistoryTotal;
   int               lastHistoryScanCount;
   datetime          lastHistoryScan;
   int               seenCount;

   int               initialTrades;
   int               previousOpenCount;
   datetime          lastBarTime;
   bool              protectionDirty;
   datetime          nextRepairTime;
   int               closeSidePending;
   int               closeFailStreak;
   bool              latchAfterClose;
   datetime          lastCloseFailAlert;
   datetime          lastHedgeOffset;
   bool              nettingDetected;
   bool              nettingProbed;

   bool              cacheDirty;
   datetime          lastCacheRefresh;
   datetime          lastWarning;
   int               lastInitDirection;   // OP_BUY / OP_SELL / 0 (unknown)
  };

//====================================================================
// GLOBAL STATE
//====================================================================
CBookState g_bk[BOOK_COUNT];
string     g_stateReason[BOOK_COUNT];
string     g_prefix[BOOK_COUNT], g_ownerGV[BOOK_COUNT], g_beatGV[BOOK_COUNT];
string     g_magicGV[BOOK_COUNT], g_bookComment[BOOK_COUNT];

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
COrderData g_classicBuy[], g_classicSell[];
COrderData g_pendBuy[],    g_pendSell[];
int        g_classicSeen[], g_pendSeen[];

int        g_ownerToken = 0;
bool       g_lockOwned = false, g_leaseLost = false;

datetime   g_atrChartBarTime = 0, g_atrSourceTime = 0;
double     g_atr = 0.0;
bool       g_atrValid = false;
datetime   g_adxBarTime = 0;
double     g_adx = 0.0;
bool       g_adxValid = false;

datetime   g_lastDashboard = 0, g_lastTrailLog = 0, g_nettingAlertTime = 0;
string     g_objPrefix = "";
int        g_journalHandle = INVALID_HANDLE;
datetime   g_lastJournalFlush = 0;
string     g_sharedLastDirGV = "";

//====================================================================
// EVENT HANDLERS
//====================================================================
int OnInit()
  {
   MathSrand((int)GetTickCount());
   g_ownerToken = (int)(GetTickCount() % 100000000) + MathRand() + 1;

   g_bk[BOOK_CLASSIC].enabled  = InpUseClassicEngine;
   g_bk[BOOK_PENDULUM].enabled = InpUsePendulumEngine;

   for(int b = 0; b < BOOK_COUNT; b++)
     {
      g_bk[b].state            = EA_STARTING;
      g_stateReason[b]         = "starting";
      g_bk[b].magic            = 0;
      g_bk[b].cacheDirty       = true;
      g_bk[b].lastCacheRefresh = 0;
      g_bk[b].lastWarning      = 0;
      g_bk[b].lastInitDirection = 0;
     }

   if(!g_bk[BOOK_CLASSIC].enabled && !g_bk[BOOK_PENDULUM].enabled)
      return InitFail("both engines are disabled - nothing would trade");

   if(!InitArrayBuffers())
      return InitFail("could not allocate dedupe buffers");
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;
   if(!ResolveMagics())
      return INIT_FAILED;

   BuildPersistentNames();

   if(!AcquireInstanceLeases())
     {
      Print("HOKKY V7.0: instance lease blocked.");
      return INIT_FAILED;
     }

   for(int b2 = 0; b2 < BOOK_COUNT; b2++)
      LoadPersistentState(b2);

   RefreshCache(BOOK_CLASSIC);
   RefreshCache(BOOK_PENDULUM);

   if(InpPurgeStateOnInit)
     {
      if(TotalAccountOrders() > 0)
        {
         Print("HOKKY V7.0: cannot purge - managed orders are open.");
         ReleaseInstanceLeases();
         return INIT_PARAMETERS_INCORRECT;
        }
      for(int b3 = 0; b3 < BOOK_COUNT; b3++)
        {
         PurgeRiskState(b3);
         LoadPersistentState(b3);
        }
      PurgeSharedState(); // Patch 2b: once, not per-book
     }

   for(int b4 = 0; b4 < BOOK_COUNT; b4++)
     {
      if(!ApplyStateCommand(b4))
        {
         ReleaseInstanceLeases();
         return INIT_PARAMETERS_INCORRECT;
        }
     }

   for(int b5 = 0; b5 < BOOK_COUNT; b5++)
      if(g_bk[b5].enabled)
         RestoreOrCreateBasketState(b5);

   UpdateMarketState(true);

   for(int b6 = 0; b6 < BOOK_COUNT; b6++)
     {
      InvalidateHistoryCache(b6);
      UpdateHistoryState(b6, true);
      if(IsEquityStopLatched(b6))
        {
         g_bk[b6].state    = EA_DD_LATCHED;
         g_stateReason[b6] = "persistent drawdown latch";
        }
      else
         if(!g_atrValid)
           {
            g_bk[b6].state    = EA_WAIT_ATR;
            g_stateReason[b6] = "waiting for closed-bar ATR";
           }
         else
           {
            g_bk[b6].state    = EA_RUNNING;
            g_stateReason[b6] = "monitoring";
           }
     }

   EventSetTimer(1);
   UpdateHeartbeat();
   OpenJournal();
   AuditRiskConfiguration();
   if(InpUseDashboard)
      UpdateDashboard();

   Print("HOKKY V7.0 init. Classic magic=", g_bk[BOOK_CLASSIC].magic,
         "  Pendulum magic=", g_bk[BOOK_PENDULUM].magic);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   CloseJournal();
   ReleaseInstanceLeases();
   DeleteOwnObjects();
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   UpdateHeartbeat();
   if(g_leaseLost)
      return;
   TouchPersistentState();
   FlushJournal(false);

   for(int b = 0; b < BOOK_COUNT; b++)
     {
      if(!g_bk[b].enabled)
         continue;
      if(g_bk[b].state == EA_CLOSE_ALL_PENDING || g_bk[b].state == EA_PROTECTION_FAULT)
        { DriveCloseAllFSM(b); continue; }
      CheckLatchRelease(b);
     }
   UpdateDashboardThrottled();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateHeartbeat();
   if(g_leaseLost)
      return;

   bool newBar = UpdateMarketState(false);
   if(newBar)
      for(int b = 0; b < BOOK_COUNT; b++)
         if(g_bk[b].enabled)
            g_bk[b].protectionDirty = true;

   for(int b2 = 0; b2 < BOOK_COUNT; b2++)
     {
      if(!g_bk[b2].enabled)
         continue;
      if(g_bk[b2].cacheDirty || newBar ||
         TimeCurrent() - g_bk[b2].lastCacheRefresh >= CACHE_REFRESH_SEC)
         RefreshCache(b2);
     }

   for(int b3 = 0; b3 < BOOK_COUNT; b3++)
     {
      if(!g_bk[b3].enabled)
         continue;
      if(g_bk[b3].previousOpenCount > 0 && CountOwnOrders(b3) == 0)
         FinalizeBasket(b3);
      g_bk[b3].previousOpenCount = CountOwnOrders(b3);
      UpdateHistoryState(b3, false);
     }

   for(int b4 = 0; b4 < BOOK_COUNT; b4++)
     {
      if(!g_bk[b4].enabled)
         continue;
      if(g_bk[b4].state == EA_CLOSE_ALL_PENDING || g_bk[b4].state == EA_PROTECTION_FAULT)
        { DriveCloseAllFSM(b4); continue; }
      if(g_bk[b4].state == EA_ACCOUNT_FAULT)
         continue;
      CheckLatchRelease(b4);
     }

   if(CheckAccountRiskStops())
     {
      UpdateDashboardThrottled();
      return;
     }

   bool bookHalted = false;
   for(int b5 = 0; b5 < BOOK_COUNT; b5++)
     {
      if(!g_bk[b5].enabled)
         continue;
      if(IsEquityStopLatched(b5))
        {
         g_bk[b5].state = EA_DD_LATCHED;
         bookHalted = true;
         continue;
        }
      if(CheckBookRiskStops(b5))
         bookHalted = true;
     }
   if(bookHalted)
     {
      UpdateDashboardThrottled();
      return;
     }

   if(!g_atrValid)
     {
      for(int b6 = 0; b6 < BOOK_COUNT; b6++)
         if(g_bk[b6].enabled)
            g_bk[b6].state = EA_WAIT_ATR;
      UpdateDashboardThrottled();
      return;
     }

   for(int b7 = 0; b7 < BOOK_COUNT; b7++)
     {
      if(!g_bk[b7].enabled)
         continue;
      if(g_bk[b7].state == EA_CLOSE_ALL_PENDING || g_bk[b7].state == EA_PROTECTION_FAULT ||
         g_bk[b7].state == EA_DD_LATCHED)
         continue;

      if(b7 == BOOK_PENDULUM)
         ApplyHedgeOffset(b7);
      if(ManageLogicalExits(b7))
        {
         RefreshCache(b7);
         continue;
        }

      if(g_bk[b7].protectionDirty || TimeCurrent() >= g_bk[b7].nextRepairTime)
         ReconcileBrokerProtection(b7);

      if(g_bk[b7].state == EA_PROTECTION_FAULT || g_bk[b7].state == EA_CLOSE_ALL_PENDING)
         continue;

      g_bk[b7].state    = EA_RUNNING;
      g_stateReason[b7] = "monitoring";

      if(Time[0] != g_bk[b7].lastBarTime)
        {
         g_bk[b7].lastBarTime = Time[0];
         ProcessTrading(b7);
        }
     }

   UpdateDashboardThrottled();
  }

//====================================================================
// INIT / VALIDATION
//====================================================================
bool InitArrayBuffers()
  {
   if(ArrayResize(g_classicSeen, HISTORY_RING_MAX) < HISTORY_RING_MAX)
      return(false);
   if(ArrayResize(g_pendSeen, HISTORY_RING_MAX)    < HISTORY_RING_MAX)
      return(false);
   for(int i = 0; i < HISTORY_RING_MAX; i++)
     {
      g_classicSeen[i] = 0;
      g_pendSeen[i] = 0;
     }
   return(true);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int InitFail(string text) { Print("HOKKY V7.0 init failure: ", text); return(INIT_FAILED); }
bool InitError(string text) { Print("HOKKY V7.0 parameter error: ", text); return(false); }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool ValidateInputs()
  {
   if(InpMagicNumber < 0)
      return InitError("InpMagicNumber must be >= 0");
   if(InpATRPeriod < 1)
      return InitError("InpATRPeriod must be >= 1");
   if(InpDistance <= 0.0)
      return InitError("InpDistance must be > 0");
   if(InpTP < 0.0 || InpIndivTP < 0.0 || InpBasketSL_ATR < 0.0 ||
      InpSL < 0.0 || InpHardSL_ATR < 0.0)
      return InitError("ATR distances must be >= 0");
   if(InpLots <= 0.0 || InpMultiplier < 1.0 || InpMaxLevel < 1)
      return InitError("Lot/grid parameters invalid");
   if(InpClassicMaxLevel < 0 || InpPendulumMaxLevel < 0)
      return InitError("per-book max level must be >= 0");
   if(InpStartTrade < 0 || InpStartTrade > 23)
      return InitError("InpStartTrade must be 0..23");
   if(InpEndTrade < 0 || InpEndTrade > 24)
      return InitError("InpEndTrade must be 0..24");
   if(InpSlippage < 0 || InpExitSlippage < 0)
      return InitError("Slippage must be >= 0");
   if(InpLeaseStaleSeconds < 5)
      return InitError("InpLeaseStaleSeconds must be >= 5");
   if(InpRequireBrokerSL && InpHardSL_ATR <= 0.0)
      return InitError("InpRequireBrokerSL requires InpHardSL_ATR > 0");
   if(InpUseBasketTP && InpTP <= 0.0)
      return InitError("InpTP must be > 0 when basket TP is enabled");
   if(InpUseTrailingStop && InpTrailDistanceATR <= 0.0)
      return InitError("Trailing stop requires InpTrailDistanceATR > 0");
   if(InpUseTrailingStop && InpTrailStartATR < InpTrailDistanceATR)
      return InitError("InpTrailStartATR must be >= InpTrailDistanceATR");
   if(InpMaxOrderLot <= 0.0)
      return InitError("InpMaxOrderLot must be > 0");
   if(InpClassicMaxOrderLot < 0.0 || InpPendulumMaxOrderLot < 0.0)
      return InitError("per-book max order lot must be >= 0");
   if(InpHedgeOffsetMaxLoss <= 0.0)
      return InitError("InpHedgeOffsetMaxLoss must be > 0");
   if(InpUseADXRegime && InpADXThreshold <= 0.0)
      return InitError("InpADXThreshold must be > 0 when the regime split is enabled");
   if(InpUseQuietHours && (InpQuietStartHour < 0 || InpQuietStartHour > 23 ||
                           InpQuietEndHour < 0 || InpQuietEndHour > 24))
      return InitError("quiet hours out of range");
   if(NormalizeLotDown(BaseLotsForBook(BOOK_CLASSIC)) <= 0.0)
      return InitError("classic book lot below broker minimum");
   if(g_bk[BOOK_PENDULUM].enabled && NormalizeLotDown(BaseLotsForBook(BOOK_PENDULUM)) <= 0.0)
      return InitError("pendulum book lot below broker minimum");
   return(true);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void AuditRiskConfiguration()
  {
   bool martingale  = (InpDbLots != LOT_FIXED) || (InpMultiplier > 1.0);
   bool hasAbsolute = (InpMinEquity > 0.0) || (InpMaxBasketLossMoney > 0.0);
   bool hasPctCap   = (InpMaxDrawdownPct > 0.0) || (InpMaxSessionDDPct > 0.0);
   int  booksOn     = (g_bk[BOOK_CLASSIC].enabled ? 1 : 0) + (g_bk[BOOK_PENDULUM].enabled ? 1 : 0);
   if(martingale && !hasAbsolute)
      Print("RISK-CONFIG WARNING: lot escalation enabled but NEITHER InpMinEquity NOR InpMaxBasketLossMoney is set.");
   if(martingale && !hasPctCap && !hasAbsolute)
      Print("RISK-CONFIG CRITICAL: escalation with no percentage and no absolute stop.");
   if(InpMinMarginLevel <= 0.0)
      Print("RISK-CONFIG WARNING: InpMinMarginLevel = 0 (off).");
   if(InpDDResetMode == EQRESET_COOLDOWN && InpDDCooldownMin <= 0)
      Print("RISK-CONFIG WARNING: cooldown mode with InpDDCooldownMin <= 0 makes the latch PERMANENT.");
   if(booksOn > 1)
      Print("RISK-CONFIG: BOTH engines live. Exposure bounded by InpMaxTotalLots.");
   if(g_bk[BOOK_PENDULUM].enabled)
      Print("RISK-CONFIG: pendulum needs a HEDGING (non-netting) account.");
   if(!InpRequireBrokerSL)
      Print("RISK-CONFIG WARNING: InpRequireBrokerSL off.");
  }

//====================================================================
// IDENTITY
//====================================================================
bool ResolveMagics()
  {
   string acct = IntegerToString(AccountNumber());
   string srv  = IntegerToString(PositiveHash(AccountServer()));
   string sym  = IntegerToString(PositiveHash(Symbol()));
   for(int b = 0; b < BOOK_COUNT; b++)
     {
      g_magicGV[b] = HOKKY_GV_MAGIC + acct + "_" + srv + "_" + sym + "_" + BookTag(b) + "_MAGIC";
      if(InpMagicNumber > 0)
         g_bk[b].magic = InpMagicNumber + b;
      else
         g_bk[b].magic = DeriveAutoMagic(acct, srv, sym, b);
      if(GlobalVariableCheck(g_magicGV[b]))
        {
         int stored = (int)GlobalVariableGet(g_magicGV[b]);
         if(stored > 0 && stored != g_bk[b].magic)
            Print("HOKKY V7.0: stored magic ", stored, " != derived ", g_bk[b].magic, " for ", BookTag(b));
        }
      GlobalVariableSet(g_magicGV[b], (double)g_bk[b].magic);
     }
   GlobalVariablesFlush();
   return(g_bk[BOOK_CLASSIC].magic > 0 && g_bk[BOOK_PENDULUM].magic > 0);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int DeriveAutoMagic(string acct, string srv, string sym, int book)
  {
   string seed = HOKKY_ID_TAG + "|" + BookTag(book) + "|" + acct + "|" + srv + "|" + sym;
   int magic = PositiveHash(seed);
   if(magic <= 0)
      magic = 300000 + (MathAbs(magic) % 100000000);
   return(magic);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string BookTag(int book)  { return(book == BOOK_PENDULUM ? "PEND" : "CLASSIC"); }
string BookName(int book) { return(book == BOOK_PENDULUM ? "PENDULUM" : "CLASSIC"); }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string BookComment(int book)
  {
   string base = (book == BOOK_PENDULUM) ? "P7" : "C7";
   string user = InpEA_Comment;
   if(StringLen(user) > 12)
      user = StringSubstr(user, 0, 12);
   return(user + base);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void BuildPersistentNames()
  {
   string acct = IntegerToString(AccountNumber());
   string srv  = IntegerToString(PositiveHash(AccountServer()));
   string sym  = IntegerToString(PositiveHash(Symbol()));
   for(int b = 0; b < BOOK_COUNT; b++)
     {
      string root = HOKKY_GV_ROOT + acct + "_" + srv + "_" + sym + "_" +
                    IntegerToString(g_bk[b].magic) + "_";
      g_prefix[b]      = root;
      g_ownerGV[b]     = root + "OWN";
      g_beatGV[b]      = root + "BEAT";
      g_bookComment[b] = BookComment(b);
     }
   g_objPrefix = "A" + IntegerToString(g_bk[BOOK_CLASSIC].magic) + "_";
   string sharedRoot = HOKKY_GV_ROOT + acct + "_" + srv + "_" + sym + "_SHARED_";
   g_sharedLastDirGV = sharedRoot + K_LASTDIR_SHARED;
  }

//====================================================================
// LEASES
//====================================================================
bool AcquireInstanceLeases()
  {
   datetime now = TimeLocal();
   for(int b = 0; b < BOOK_COUNT; b++)
     {
      if(!GlobalVariableCheck(g_ownerGV[b]))
         GlobalVariableSet(g_ownerGV[b], 0.0);
      if(!GlobalVariableCheck(g_beatGV[b]))
         GlobalVariableSet(g_beatGV[b],  0.0);
      double   observed = GlobalVariableGet(g_ownerGV[b]);
      datetime beat     = (datetime)GlobalVariableGet(g_beatGV[b]);
      if(observed != 0.0 && (now - beat) < InpLeaseStaleSeconds)
        {
         for(int rl = 0; rl < b; rl++)
            ReleaseLease(rl);
         return(false);
        }
      if(!GlobalVariableSetOnCondition(g_ownerGV[b], (double)g_ownerToken, observed))
        {
         for(int rl2 = 0; rl2 < b; rl2++)
            ReleaseLease(rl2);
         return(false);
        }
      GlobalVariableSet(g_beatGV[b], (double)now);
     }
   GlobalVariablesFlush();
   g_lockOwned = true;
   return(true);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ReleaseLease(int book)
  {
   if((int)GlobalVariableGet(g_ownerGV[book]) == g_ownerToken)
     {
      GlobalVariableSet(g_beatGV[book],  0.0);
      GlobalVariableSet(g_ownerGV[book], 0.0);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ReleaseInstanceLeases()
  {
   if(!g_lockOwned)
      return;
   for(int b = 0; b < BOOK_COUNT; b++)
      ReleaseLease(b);
   GlobalVariablesFlush();
   g_lockOwned = false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateHeartbeat()
  {
   if(!g_lockOwned)
      return;
   for(int b = 0; b < BOOK_COUNT; b++)
     {
      if((int)GlobalVariableGet(g_ownerGV[b]) != g_ownerToken)
        {
         g_lockOwned = false;
         g_leaseLost = true;
         for(int k = 0; k < BOOK_COUNT; k++)
           {
            g_bk[k].state    = EA_PROTECTION_FAULT;
            g_stateReason[k] = "instance lease lost";
           }
         Alert("HOKKY V7.0: instance lease lost - standing down.");
         return;
        }
      GlobalVariableSet(g_beatGV[b], (double)TimeLocal());
     }
  }

//====================================================================
// PERSISTENT STATE
//====================================================================
void LoadPersistentState(int book)
  {
   string p = g_prefix[book];
   if(GlobalVariableCheck(p + K_SCHEMA))
     {
      double oldSchema = GlobalVariableGet(p + K_SCHEMA);
      if(oldSchema > 0.0 && oldSchema < HOKKY_STATE_SCHEMA)
        {
         Print("HOKKY V7.0: book ", BookTag(book), " schema ", oldSchema, " -> ", HOKKY_STATE_SCHEMA);
         PurgeRiskState(book);
        }
     }
   EnsureGV(book, K_SCHEMA,  HOKKY_STATE_SCHEMA);
   EnsureGV(book, K_NEXTLOT, BaseLotsForBook(book));
   EnsureGV(book, K_BID,     0.0);
   EnsureGV(book, K_BSTART,  0.0);
   EnsureGV(book, K_BACTIVE, 0.0);
   EnsureGV(book, K_SSTART, (double)TimeCurrent());
   EnsureGV(book, K_SBASE,   AccountBalance());
   EnsureGV(book, K_SPEAK,   0.0);
   EnsureGV(book, K_LASTCMD, 0.0);
   EnsureGV(book, K_LASTDIR, 0.0);
   g_bk[book].lastInitDirection = (int)GlobalVariableGet(p + K_LASTDIR);
   g_bk[book].nextRecoveryLot = GlobalVariableGet(p + K_NEXTLOT);
   if(g_bk[book].nextRecoveryLot <= 0.0)
      g_bk[book].nextRecoveryLot = BaseLotsForBook(book);
   g_bk[book].basketId           = (int)GlobalVariableGet(p + K_BID);
   g_bk[book].basketStart        = (datetime)GlobalVariableGet(p + K_BSTART);
   g_bk[book].basketActive       = (GlobalVariableGet(p + K_BACTIVE) > 0.5);
   g_bk[book].sessionStart       = (datetime)GlobalVariableGet(p + K_SSTART);
   g_bk[book].sessionBaseBalance = GlobalVariableGet(p + K_SBASE);
   g_bk[book].sessionPeakNet     = GlobalVariableGet(p + K_SPEAK);
   if(g_bk[book].sessionStart <= 0)
      g_bk[book].sessionStart = TimeCurrent();
   if(g_bk[book].sessionBaseBalance <= 0)
      g_bk[book].sessionBaseBalance = AccountBalance();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void EnsureGV(int book, string key, double value)
  {
   if(!GlobalVariableCheck(g_prefix[book] + key))
      GlobalVariableSet(g_prefix[book] + key, value);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void PurgeRiskState(int book)
  {
   string p = g_prefix[book];
   string keys[12] = { K_NEXTLOT, K_EQSTOP, K_EQTIME, K_BID, K_BSTART, K_BACTIVE,
                       K_SSTART, K_SBASE, K_SPEAK, K_LASTCMD, K_SCHEMA, K_LASTDIR
                     };
   for(int i = 0; i < 12; i++)
      GlobalVariableDel(p + keys[i]);
   GlobalVariableDel(p + K_EQWHY);
   GlobalVariablesFlush();
  }

//+------------------------------------------------------------------+
//| Delete the cross-book shared gate. Called ONCE per purge, not    |
//| once per book, because the GV is shared by both books.           |
//+------------------------------------------------------------------+
void PurgeSharedState()
  {
   if(g_sharedLastDirGV != "" && GlobalVariableCheck(g_sharedLastDirGV))
      GlobalVariableDel(g_sharedLastDirGV);
   GlobalVariablesFlush();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool ApplyStateCommand(int book)
  {
   if(InpStateCommand == STATE_KEEP || InpStateCommandId <= 0)
      return(true);
   if((int)GlobalVariableGet(g_prefix[book] + K_LASTCMD) == InpStateCommandId)
      return(true);
   if(CountOwnOrders(book) > 0)
     {
      Print("HOKKY V7.0: state command refused - book ", BookTag(book), " has open orders.");
      return(false);
     }
   string p = g_prefix[book];
   if(InpStateCommand == STATE_RESET_DD_LATCH || InpStateCommand == STATE_RESET_ALL_RISK)
     {
      GlobalVariableDel(p + K_EQSTOP);
      GlobalVariableDel(p + K_EQTIME);
      GlobalVariableDel(p + K_EQWHY);
     }
   if(InpStateCommand == STATE_RESET_RECOVERY || InpStateCommand == STATE_RESET_ALL_RISK)
      GlobalVariableSet(p + K_NEXTLOT, BaseLotsForBook(book));
   if(InpStateCommand == STATE_RESET_SESSION || InpStateCommand == STATE_RESET_ALL_RISK)
      ResetSessionState(book);
   if(InpStateCommand == STATE_RESET_ALL_RISK)
     {
      GlobalVariableSet(p + K_LASTDIR, 0.0);
      g_bk[book].lastInitDirection = 0;
      PurgeSharedState(); // Patch 2c: centralised
     }
   GlobalVariableSet(p + K_LASTCMD, (double)InpStateCommandId);
   GlobalVariablesFlush();
   LoadPersistentState(book);
   return(true);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ResetSessionState(int book)
  {
   g_bk[book].sessionStart       = TimeCurrent();
   g_bk[book].sessionBaseBalance = AccountBalance();
   g_bk[book].sessionRealized    = 0.0;
   g_bk[book].sessionPeakNet     = 0.0;
   g_bk[book].initialTrades      = 0;
   GlobalVariableSet(g_prefix[book] + K_SSTART, (double)g_bk[book].sessionStart);
   GlobalVariableSet(g_prefix[book] + K_SBASE,  g_bk[book].sessionBaseBalance);
   GlobalVariableSet(g_prefix[book] + K_SPEAK,  0.0);
   InvalidateHistoryCache(book);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsEquityStopLatched(int book)
  {
   return(GlobalVariableCheck(g_prefix[book] + K_EQSTOP) &&
          GlobalVariableGet(g_prefix[book] + K_EQSTOP) > 0.5);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void LatchEquityStop(int book, string reason)
  {
   string p = g_prefix[book];
   GlobalVariableSet(p + K_EQSTOP, 1.0);
   GlobalVariableSet(p + K_EQTIME, (double)TimeCurrent());
   GlobalVariableSet(p + K_EQWHY, (double)PositiveHash(reason));
   GlobalVariablesFlush();
   g_bk[book].state    = EA_DD_LATCHED;
   g_stateReason[book] = reason;
   LogTrade(book, "RISK-LATCH", 0, 0.0, 0.0, 0.0, 0.0, reason);
   Alert("HOKKY V7.0 RISK STOP LATCHED [", BookName(book), "]: ", reason);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckLatchRelease(int book)
  {
   if(!IsEquityStopLatched(book))
      return;
   if(InpDDResetMode != EQRESET_COOLDOWN || InpDDCooldownMin <= 0)
      return;
   if(TimeCurrent() - (datetime)GlobalVariableGet(g_prefix[book] + K_EQTIME) < InpDDCooldownMin * 60)
      return;
   string p = g_prefix[book];
   GlobalVariableDel(p + K_EQSTOP);
   GlobalVariableDel(p + K_EQTIME);
   GlobalVariableDel(p + K_EQWHY);
   ResetSessionState(book);
   GlobalVariablesFlush();
   g_bk[book].state    = g_atrValid ? EA_RUNNING : EA_WAIT_ATR;
   g_stateReason[book] = "risk cooldown released";
   LogTrade(book, "LATCH-RELEASE", 0, 0.0, 0.0, 0.0, 0.0, "cooldown expired");
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void TouchPersistentState()
  {
   static datetime lastTouch = 0;
   if(TimeCurrent() - lastTouch < HEARTBEAT_TOUCH_SEC)
      return;
   lastTouch = TimeCurrent();
   for(int i = 0; i < GlobalVariablesTotal(); i++)
     {
      string name = GlobalVariableName(i);
      for(int tb = 0; tb < BOOK_COUNT; tb++)
         if(StringFind(name, g_prefix[tb]) == 0)
            GlobalVariableSet(name, GlobalVariableGet(name));
     }
   for(int tb2 = 0; tb2 < BOOK_COUNT; tb2++)
      if(g_magicGV[tb2] != "")
         GlobalVariableSet(g_magicGV[tb2], (double)g_bk[tb2].magic);
   if(g_sharedLastDirGV != "" && GlobalVariableCheck(g_sharedLastDirGV))
      GlobalVariableSet(g_sharedLastDirGV, GlobalVariableGet(g_sharedLastDirGV));
  }

//====================================================================
// PER-BOOK PARAMETERS
//====================================================================
double BaseLotsForBook(int book)
  { double v = (book == BOOK_PENDULUM) ? InpPendulumLots : InpClassicLots; return(v > 0.0 ? v : InpLots); }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int MaxLevelForBook(int book)
  { int v = (book == BOOK_PENDULUM) ? InpPendulumMaxLevel : InpClassicMaxLevel; return(v > 0 ? v : InpMaxLevel); }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double MaxOrderLotForBook(int book)
  { double v = (book == BOOK_PENDULUM) ? InpPendulumMaxOrderLot : InpClassicMaxOrderLot; return(v > 0.0 ? v : InpMaxOrderLot); }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double PerOrderCap(int book)
  { if(InpDbLots == LOT_RECOVERY) return(InpMaxRecoveryLot); return(MaxOrderLotForBook(book)); }

//+------------------------------------------------------------------+
//| Shared last-init-direction gate (CROSS-BOOK).                    |
//| The next L0 opened in EITHER book must be the OPPOSITE of the    |
//| last L0 opened in EITHER book. Returns OP_BUY / OP_SELL / 0      |
//| (0 = unknown, no constraint yet).                                |
//| Falls back to an open L0 in either book when the GV is missing.  |
//+------------------------------------------------------------------+
int GetSharedLastInitDirection()
  {
   if(g_sharedLastDirGV != "" && GlobalVariableCheck(g_sharedLastDirGV))
     {
      int d = (int)GlobalVariableGet(g_sharedLastDirGV);
      if(d == OP_BUY || d == OP_SELL)
         return(d);
     }
   for(int b = 0; b < BOOK_COUNT; b++)
     {
      for(int i = 0; i < g_bk[b].buyCount; i++)
        {
         COrderData ob = BookBuy(b, i);
         if(ob.ticket > 0 && ob.level == 0)
           {
            if(g_sharedLastDirGV != "")
              { GlobalVariableSet(g_sharedLastDirGV, (double)OP_BUY); GlobalVariablesFlush(); }
            return(OP_BUY);
           }
        }
      for(int j = 0; j < g_bk[b].sellCount; j++)
        {
         COrderData os = BookSell(b, j);
         if(os.ticket > 0 && os.level == 0)
           {
            if(g_sharedLastDirGV != "")
              { GlobalVariableSet(g_sharedLastDirGV, (double)OP_SELL); GlobalVariablesFlush(); }
            return(OP_SELL);
           }
        }
     }
   return(-1);
  }

//+------------------------------------------------------------------+
void SetSharedLastInitDirection(int dir)
  {
   if(dir != OP_BUY && dir != OP_SELL)
      return;
   if(g_sharedLastDirGV != "")
     {
      GlobalVariableSet(g_sharedLastDirGV, (double)dir);
      GlobalVariablesFlush();
     }
  }

int CountOwnOrders(int book) { return(g_bk[book].buyCount + g_bk[book].sellCount); }

//====================================================================
// ORDER CACHE
//====================================================================
int BookBuySize(int book)  { return(book == BOOK_PENDULUM ? ArraySize(g_pendBuy)  : ArraySize(g_classicBuy)); }
int BookSellSize(int book) { return(book == BOOK_PENDULUM ? ArraySize(g_pendSell) : ArraySize(g_classicSell)); }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void BookClearOrders(int book)
  {
   if(book == BOOK_PENDULUM)
     {
      ArrayResize(g_pendBuy, 0);
      ArrayResize(g_pendSell, 0);
     }
   else
     {
      ArrayResize(g_classicBuy, 0);
      ArrayResize(g_classicSell, 0);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void BookAppendBuy(int book, const COrderData &rec)
  {
   if(book == BOOK_PENDULUM)
     { int n = ArraySize(g_pendBuy);    ArrayResize(g_pendBuy, n + 1);    g_pendBuy[n] = rec; }
   else
     { int n2 = ArraySize(g_classicBuy); ArrayResize(g_classicBuy, n2 + 1); g_classicBuy[n2] = rec; }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void BookAppendSell(int book, const COrderData &rec)
  {
   if(book == BOOK_PENDULUM)
     { int n = ArraySize(g_pendSell);    ArrayResize(g_pendSell, n + 1);    g_pendSell[n] = rec; }
   else
     { int n2 = ArraySize(g_classicSell); ArrayResize(g_classicSell, n2 + 1); g_classicSell[n2] = rec; }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
COrderData BookBuy(int book, int idx)
  {
   COrderData empty;
   empty.ticket = 0;
   if(idx < 0 || idx >= BookBuySize(book))
      return(empty);
   return(book == BOOK_PENDULUM ? g_pendBuy[idx] : g_classicBuy[idx]);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
COrderData BookSell(int book, int idx)
  {
   COrderData empty;
   empty.ticket = 0;
   if(idx < 0 || idx >= BookSellSize(book))
      return(empty);
   return(book == BOOK_PENDULUM ? g_pendSell[idx] : g_classicSell[idx]);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void BookSeenClear(int book)
  {
   if(book == BOOK_PENDULUM)
     {
      if(ArraySize(g_pendSeen) < HISTORY_RING_MAX)
         ArrayResize(g_pendSeen, HISTORY_RING_MAX);
      for(int i = 0; i < HISTORY_RING_MAX; i++)
         g_pendSeen[i] = 0;
     }
   else
     {
      if(ArraySize(g_classicSeen) < HISTORY_RING_MAX)
         ArrayResize(g_classicSeen, HISTORY_RING_MAX);
      for(int j = 0; j < HISTORY_RING_MAX; j++)
         g_classicSeen[j] = 0;
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool BookSeenHas(int book, int ticket)
  {
   if(book == BOOK_PENDULUM)
     {
      int n = MathMin(g_bk[book].seenCount, ArraySize(g_pendSeen));
      for(int i = 0; i < n; i++)
         if(g_pendSeen[i] == ticket)
            return(true);
     }
   else
     {
      int n2 = MathMin(g_bk[book].seenCount, ArraySize(g_classicSeen));
      for(int j = 0; j < n2; j++)
         if(g_classicSeen[j] == ticket)
            return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void BookSeenAdd(int book, int ticket)
  {
   if(g_bk[book].seenCount >= HISTORY_RING_MAX)
      return;
   if(book == BOOK_PENDULUM)
     {
      if(g_bk[book].seenCount >= ArraySize(g_pendSeen))
         ArrayResize(g_pendSeen, g_bk[book].seenCount + 1);
      g_pendSeen[g_bk[book].seenCount] = ticket;
     }
   else
     {
      if(g_bk[book].seenCount >= ArraySize(g_classicSeen))
         ArrayResize(g_classicSeen, g_bk[book].seenCount + 1);
      g_classicSeen[g_bk[book].seenCount] = ticket;
     }
   g_bk[book].seenCount++;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void RefreshCache(int book)
  {
   g_bk[book].buyCount = 0;
   g_bk[book].sellCount = 0;
   g_bk[book].buyLots = 0.0;
   g_bk[book].sellLots = 0.0;
   g_bk[book].buyAvg = 0.0;
   g_bk[book].sellAvg = 0.0;
   g_bk[book].buyPL = 0.0;
   g_bk[book].sellPL = 0.0;
   g_bk[book].floatingPL = 0.0;
   g_bk[book].buyNewestTime = 0;
   g_bk[book].sellNewestTime = 0;
   g_bk[book].buyNewestPrice = 0.0;
   g_bk[book].sellNewestPrice = 0.0;
   g_bk[book].buyNewestTicket = 0;
   g_bk[book].sellNewestTicket = 0;
   g_bk[book].buyNewestLevel = -1;
   g_bk[book].sellNewestLevel = -1;
   BookClearOrders(book);

   double buyPV = 0.0, sellPV = 0.0;
   int magic = g_bk[book].magic;

   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != magic)
         continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL)
         continue;
      COrderData rec;
      rec.ticket    = OrderTicket();
      rec.type      = type;
      rec.openTime  = OrderOpenTime();
      rec.openPrice = OrderOpenPrice();
      rec.lots      = OrderLots();
      rec.currentSL = OrderStopLoss();
      rec.currentTP = OrderTakeProfit();
      rec.level     = ParseLevelFromComment(OrderComment());
      double net = OrderProfit() + OrderSwap() + OrderCommission();
      g_bk[book].floatingPL += net;
      if(type == OP_BUY)
        {
         BookAppendBuy(book, rec);
         g_bk[book].buyCount++;
         g_bk[book].buyLots += rec.lots;
         g_bk[book].buyPL   += net;
         buyPV += rec.openPrice * rec.lots;
         if(IsNewer(rec.openTime, rec.ticket, g_bk[book].buyNewestTime, g_bk[book].buyNewestTicket))
           {
            g_bk[book].buyNewestTime = rec.openTime;
            g_bk[book].buyNewestTicket = rec.ticket;
            g_bk[book].buyNewestPrice = rec.openPrice;
            g_bk[book].buyNewestLevel = rec.level;
           }
        }
      else
        {
         BookAppendSell(book, rec);
         g_bk[book].sellCount++;
         g_bk[book].sellLots += rec.lots;
         g_bk[book].sellPL   += net;
         sellPV += rec.openPrice * rec.lots;
         if(IsNewer(rec.openTime, rec.ticket, g_bk[book].sellNewestTime, g_bk[book].sellNewestTicket))
           {
            g_bk[book].sellNewestTime = rec.openTime;
            g_bk[book].sellNewestTicket = rec.ticket;
            g_bk[book].sellNewestPrice = rec.openPrice;
            g_bk[book].sellNewestLevel = rec.level;
           }
        }
     }
   if(g_bk[book].buyLots  > 0.0)
      g_bk[book].buyAvg  = NormalizeDouble(buyPV  / g_bk[book].buyLots,  Digits);
   if(g_bk[book].sellLots > 0.0)
      g_bk[book].sellAvg = NormalizeDouble(sellPV / g_bk[book].sellLots, Digits);

   g_bk[book].cacheDirty       = false;
   g_bk[book].lastCacheRefresh = TimeCurrent();
  }

void MarkCacheDirty(int book) { g_bk[book].cacheDirty = true; }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double TotalAccountFloatingPL()
  { return(g_bk[BOOK_CLASSIC].floatingPL + g_bk[BOOK_PENDULUM].floatingPL); }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double TotalAccountLots()
  {
   return(g_bk[BOOK_CLASSIC].buyLots + g_bk[BOOK_CLASSIC].sellLots +
          g_bk[BOOK_PENDULUM].buyLots + g_bk[BOOK_PENDULUM].sellLots);
  }

int TotalAccountOrders() { return(CountOwnOrders(BOOK_CLASSIC) + CountOwnOrders(BOOK_PENDULUM)); }

//+------------------------------------------------------------------+
//|                                                                  |
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
//|                                                                  |
//+------------------------------------------------------------------+
int ParseLevelFromComment(string comment)
  {
   int pos = StringFind(comment, "|L");
   if(pos < 0)
      return(-1);
   return((int)StringToInteger(StringSubstr(comment, pos + 2)));
  }

//====================================================================
// BASKET LIFECYCLE
//====================================================================
void RestoreOrCreateBasketState(int book)
  {
   int total = CountOwnOrders(book);
   g_bk[book].previousOpenCount = total;
   if(total <= 0 || g_bk[book].basketActive)
      return;
   datetime earliest = 0;
   for(int i = 0; i < g_bk[book].buyCount; i++)
     { COrderData ob = BookBuy(book, i); if(ob.ticket > 0 && (earliest == 0 || ob.openTime < earliest)) earliest = ob.openTime; }
   for(int j = 0; j < g_bk[book].sellCount; j++)
     { COrderData os = BookSell(book, j); if(os.ticket > 0 && (earliest == 0 || os.openTime < earliest)) earliest = os.openTime; }
   g_bk[book].basketId++;
   g_bk[book].basketStart  = earliest;
   g_bk[book].basketActive = true;
   SaveBasketState(book);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void StartNewBasket(int book)
  {
   g_bk[book].basketId++;
   g_bk[book].basketStart    = TimeCurrent();
   g_bk[book].basketActive   = true;
   g_bk[book].basketRealized = 0.0;
   SaveBasketState(book);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SaveBasketState(int book)
  {
   string p = g_prefix[book];
   GlobalVariableSet(p + K_BID, (double)g_bk[book].basketId);
   GlobalVariableSet(p + K_BSTART, (double)g_bk[book].basketStart);
   GlobalVariableSet(p + K_BACTIVE, g_bk[book].basketActive ? 1.0 : 0.0);
   GlobalVariablesFlush();
  }

//====================================================================
// HISTORY
//====================================================================
void InvalidateHistoryCache(int book)
  {
   g_bk[book].seenCount = 0;
   BookSeenClear(book);
   g_bk[book].lastHistoryTotal     = -1;
   g_bk[book].lastHistoryScanCount = 0;
   g_bk[book].lastHistoryScan      = 0;
   g_bk[book].sessionRealized      = 0.0;
   g_bk[book].basketRealized       = 0.0;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MarkTicketSeen(int book, int ticket)
  { if(g_bk[book].seenCount >= HISTORY_RING_MAX) return; BookSeenAdd(book, ticket); }

bool IsTicketSeen(int book, int ticket) { return(BookSeenHas(book, ticket)); }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateHistoryState(int book, bool force)
  {
   int total = OrdersHistoryTotal();
   if(!force)
     {
      if(total == g_bk[book].lastHistoryTotal &&
         TimeCurrent() - g_bk[book].lastHistoryScan < 30)
         return;
      if(g_bk[book].seenCount >= HISTORY_RING_MAX)
        {
         RebuildRealizedState(book);
         return;
        }
     }
   if(total < g_bk[book].lastHistoryTotal)
     {
      RebuildRealizedState(book);
      return;
     }

   int from = g_bk[book].lastHistoryScanCount;
   if(total - from > 200)
      from = total - 200;
   if(from < 0)
      from = 0;

   int magic = g_bk[book].magic;
   for(int i = from; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != magic)
         continue;
      if((OrderType() != OP_BUY && OrderType() != OP_SELL) || OrderCloseTime() <= 0)
         continue;
      if(IsTicketSeen(book, OrderTicket()))
         continue;
      MarkTicketSeen(book, OrderTicket());
      double net = OrderProfit() + OrderSwap() + OrderCommission();
      if(OrderCloseTime() >= g_bk[book].sessionStart)
         g_bk[book].sessionRealized += net;
      if(g_bk[book].basketActive && OrderOpenTime() >= g_bk[book].basketStart)
         g_bk[book].basketRealized += net;
     }
   g_bk[book].lastHistoryTotal     = total;
   g_bk[book].lastHistoryScanCount = total;
   g_bk[book].lastHistoryScan      = TimeCurrent();
   RecomputeSessionDD(book);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void RebuildRealizedState(int book)
  {
   g_bk[book].seenCount = 0;
   BookSeenClear(book);
   g_bk[book].sessionRealized = 0.0;
   g_bk[book].basketRealized  = 0.0;
   int total = OrdersHistoryTotal();
   int magic = g_bk[book].magic;
   for(int i = 0; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != magic)
         continue;
      if((OrderType() != OP_BUY && OrderType() != OP_SELL) || OrderCloseTime() <= 0)
         continue;
      if(IsTicketSeen(book, OrderTicket()))
         continue;
      MarkTicketSeen(book, OrderTicket());
      double net = OrderProfit() + OrderSwap() + OrderCommission();
      if(OrderCloseTime() >= g_bk[book].sessionStart)
         g_bk[book].sessionRealized += net;
      if(g_bk[book].basketActive && OrderOpenTime() >= g_bk[book].basketStart)
         g_bk[book].basketRealized += net;
     }
   g_bk[book].lastHistoryTotal     = total;
   g_bk[book].lastHistoryScanCount = total;
   g_bk[book].lastHistoryScan      = TimeCurrent();
   RecomputeSessionDD(book);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void RecomputeSessionDD(int book)
  {
   double net = g_bk[book].sessionRealized + g_bk[book].floatingPL;
   if(net > g_bk[book].sessionPeakNet)
     {
      g_bk[book].sessionPeakNet = net;
      GlobalVariableSet(g_prefix[book] + K_SPEAK, g_bk[book].sessionPeakNet);
     }
   double denom = MathMax(g_bk[book].sessionBaseBalance + g_bk[book].sessionPeakNet, 1.0);
   g_bk[book].sessionDDPct = MathMax(0.0, (g_bk[book].sessionPeakNet - net) / denom * 100.0);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void FinalizeBasket(int book)
  {
   if(!g_bk[book].basketActive)
      return;
   UpdateHistoryState(book, true);
   double realized = g_bk[book].basketRealized;
   if(InpDbLots == LOT_RECOVERY)
     {
      if(realized < 0.0)
         g_bk[book].nextRecoveryLot = NormalizeLotDown(MathMax(BaseLotsForBook(book),
                                      g_bk[book].nextRecoveryLot) * InpMultiplier);
      else
         g_bk[book].nextRecoveryLot = NormalizeLotDown(BaseLotsForBook(book));
      if(InpMaxRecoveryLot > 0.0 && g_bk[book].nextRecoveryLot > InpMaxRecoveryLot)
         g_bk[book].nextRecoveryLot = NormalizeLotDown(InpMaxRecoveryLot);
      GlobalVariableSet(g_prefix[book] + K_NEXTLOT, g_bk[book].nextRecoveryLot);
     }
   g_bk[book].basketActive    = false;
   g_bk[book].basketStart     = 0;
   g_bk[book].basketRealized  = 0.0;
   SaveBasketState(book);
   InvalidateHistoryCache(book);
   g_bk[book].closeFailStreak = 0;
   g_bk[book].closeSidePending = -1;
   LogTrade(book, "BASKET-END", 0, 0.0, 0.0, 0.0, 0.0,
            "basket #" + IntegerToString(g_bk[book].basketId) + " realized=" + DoubleToString(realized, 2));
  }

//====================================================================
// MARKET STATE / FILTERS
//====================================================================
bool UpdateMarketState(bool force)
  {
   datetime bar = iTime(Symbol(), Period(), 0);
   bool changed = false;
   if(force || bar != g_atrChartBarTime)
     {
      g_atrChartBarTime = bar;
      double atrValue = iATR(Symbol(), Period(), InpATRPeriod, 1);
      datetime atrSrc = iTime(Symbol(), Period(), 1);
      if(atrValue > Point * 0.5 && atrSrc > 0)
        { changed = (atrSrc != g_atrSourceTime); g_atr = atrValue; g_atrSourceTime = atrSrc; g_atrValid = true; }
      else
         g_atrValid = false;
     }
   if(force || bar != g_adxBarTime)
     {
      g_adxBarTime = bar;
      double adxValue = iADX(Symbol(), InpTrendTimeframe, InpADXPeriod, PRICE_CLOSE, MODE_MAIN, 1);
      if(adxValue > 0.0)
        {
         g_adx = adxValue;
         g_adxValid = true;
        }
      else
         g_adxValid = false;
     }
   return(changed);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double ATRDistance(double multiplier)
  { return(!g_atrValid || multiplier <= 0.0 ? 0.0 : multiplier * g_atr); }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool RegimeAllowsClassic()
  { if(!InpUseADXRegime || !g_adxValid) return(true); return(g_adx <  InpADXThreshold); }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool RegimeAllowsPendulum()
  { if(!InpUseADXRegime || !g_adxValid) return(true); return(g_adx >= InpADXThreshold); }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool RegimeAllowsBook(int book)
  { return(book == BOOK_PENDULUM ? RegimeAllowsPendulum() : RegimeAllowsClassic()); }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsTrendAligned(int cmd)
  {
   double ma    = iMA(Symbol(), InpTrendTimeframe, InpTrendMA_Period, 0, InpTrendMA_Method, PRICE_CLOSE, 1);
   double close = iClose(Symbol(), InpTrendTimeframe, 1);
   if(ma <= 0.0 || close <= 0.0)
      return(false);
   bool maOk = (cmd == OP_BUY) ? (close > ma) : (close < ma);
   if(!InpADXUseDI)
      return(maOk);
   double diP = iADX(Symbol(), InpTrendTimeframe, InpADXPeriod, PRICE_CLOSE, MODE_PLUSDI, 1);
   double diM = iADX(Symbol(), InpTrendTimeframe, InpADXPeriod, PRICE_CLOSE, MODE_MINUSDI, 1);
   if(diP <= 0.0 || diM <= 0.0)
      return(maOk);
   return(maOk && ((cmd == OP_BUY) ? (diP > diM) : (diM > diP)));
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
  {
   if(InpStartTrade == InpEndTrade)
      return(true);
   int hour = TimeHour(TimeCurrent());
   if(InpStartTrade < InpEndTrade)
      return(hour >= InpStartTrade && hour < InpEndTrade);
   return(hour >= InpStartTrade || hour < InpEndTrade);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsQuietHour()
  {
   if(!InpUseQuietHours)
      return(false);
   if(InpQuietStartHour == InpQuietEndHour)
      return(false);
   int hour = TimeHour(TimeCurrent());
   if(InpQuietStartHour < InpQuietEndHour)
      return(hour >= InpQuietStartHour && hour < InpQuietEndHour);
   return(hour >= InpQuietStartHour || hour < InpQuietEndHour);
  }

double CurrentSpreadPoints() { return((Ask - Bid) / Point); }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool SpreadAcceptable()
  {
   double spread = CurrentSpreadPoints();
   if(InpMaxSpreadPoints > 0.0 && spread > InpMaxSpreadPoints)
      return(false);
   if(InpUseSpreadATRCap && g_atrValid && InpMaxSpreadATR > 0.0)
     {
      double atrPoints = g_atr / Point;
      if(atrPoints > 0.0 && spread > InpMaxSpreadATR * atrPoints)
         return(false);
     }
   return(true);
  }

//====================================================================
// TRADING ENGINE
//====================================================================
void ProcessTrading(int book)
  {
   if(!g_atrValid || !IsTradeContextUsable())
      return;
   if(!InpAllowNewBaskets && !InpAllowAddons)
      return;
   if(g_bk[book].initialTrades >= InpLoop)
      return;
   if(!RegimeAllowsBook(book))
      return;
   if(book == BOOK_PENDULUM && InpBlockOnNetting && g_bk[book].nettingDetected)
      return;
   if(!IsWithinTradingHours())
      return;
   if(IsQuietHour())
      return;
   if(!SpreadAcceptable())
      return;

   int own = CountOwnOrders(book);
   if(own == 0)
     {
      if(InpAllowNewBaskets)
         OpenInitialTrade(book);
      return;
     }
   if(own >= MaxLevelForBook(book) || !InpAllowAddons)
      return;
   if(book == BOOK_PENDULUM)
      ProcessPendulumGrid(book);
   else
      ProcessClassicGrid(book);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ProcessClassicGrid(int book)
  {
   if(g_bk[book].buyCount > 0 && g_bk[book].sellCount > 0)
      return;
   double distance = ATRDistance(InpDistance);
   if(distance <= 0.0)
      return;
   if(g_bk[book].buyCount > 0 && g_bk[book].buyNewestPrice > 0.0 &&
      (g_bk[book].buyNewestPrice - Ask) >= distance)
     {
      if(!InpUseTrendFilter || !InpTrendFilterAddons || IsTrendAligned(OP_BUY))
         OpenAddonTrade(book, OP_BUY);
     }
   if(g_bk[book].sellCount > 0 && g_bk[book].sellNewestPrice > 0.0 &&
      (Bid - g_bk[book].sellNewestPrice) >= distance)
     {
      if(!InpUseTrendFilter || !InpTrendFilterAddons || IsTrendAligned(OP_SELL))
         OpenAddonTrade(book, OP_SELL);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ProcessPendulumGrid(int book)
  {
   if(!InpAllowBothDirections)
      return;
   double distance = ATRDistance(InpDistance);
   if(distance <= 0.0)
      return;
   int newType = -1;
   double newPrice = 0.0;
   if(IsNewer(g_bk[book].buyNewestTime,  g_bk[book].buyNewestTicket,
              g_bk[book].sellNewestTime, g_bk[book].sellNewestTicket))
     { newType = OP_BUY;  newPrice = g_bk[book].buyNewestPrice;  }
   else
     { newType = OP_SELL; newPrice = g_bk[book].sellNewestPrice; }
   if(newType < 0 || newPrice <= 0.0)
      return;
   if(newType == OP_BUY)
     {
      if((newPrice - Ask) >= distance)
         if(!InpUseTrendFilter || !InpTrendFilterAddons || IsTrendAligned(OP_SELL))
            OpenAddonTrade(book, OP_SELL);
     }
   else
     {
      if((Bid - newPrice) >= distance)
         if(!InpUseTrendFilter || !InpTrendFilterAddons || IsTrendAligned(OP_BUY))
            OpenAddonTrade(book, OP_BUY);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OpenInitialTrade(int book)
  {
   double close2 = iClose(Symbol(), Period(), 2);
   double close1 = iClose(Symbol(), Period(), 1);
   if(close2 <= 0.0 || close1 <= 0.0 || MathAbs(close2 - close1) < Point * 0.5)
      return;
   int cmd = (close2 > close1) ? OP_SELL : OP_BUY;
   if(InpUseTrendFilter && !IsTrendAligned(cmd))
      return;

// --- Alternating initial-direction gate (CROSS-BOOK) ---------------
// The next L0 in EITHER book must be the OPPOSITE of the last L0 in EITHER book.
   int prevDir = GetSharedLastInitDirection();
   if(prevDir != -1 && cmd == prevDir)
     {
      WarnThrottled(book, "new basket blocked: shared last L0 was " +
                    (prevDir == OP_BUY ? "BUY" : "SELL") +
                    " - next L0 in either book must be " +
                    (prevDir == OP_BUY ? "SELL" : "BUY") + ".");
      return;
     }

   StartNewBasket(book);
   double lot    = CalculateLotSize(book, 0);
   int    ticket = SafeOrderSend(book, cmd, lot, BuildOrderComment(book, 0));
   if(ticket > 0)
     {
      g_bk[book].initialTrades++;
      g_bk[book].lastInitDirection = cmd;
      GlobalVariableSet(g_prefix[book] + K_LASTDIR, (double)cmd);
      SetSharedLastInitDirection(cmd);
      MarkCacheDirty(book);
      RefreshCache(book);
      g_bk[book].previousOpenCount = CountOwnOrders(book);
      g_bk[book].protectionDirty   = true;
     }
   else
      if(CountOwnOrders(book) == 0)
        {
         g_bk[book].basketActive = false;
         g_bk[book].basketStart  = 0;
         SaveBasketState(book);
        }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OpenAddonTrade(int book, int cmd)
  {
   int level = CountOwnOrders(book);
   double lot = CalculateLotSize(book, level);
   if(InpHaltAddonsWhenCapped && level > 0)
     {
      double capLimit = PerOrderCap(book);
      double rawLot   = CalculateRawLot(book, level);
      bool   capClamped = (capLimit > 0.0 && rawLot >= capLimit - LOT_EPSILON);
      if(capClamped)
        {
         double prevLot = CalculateLotSize(book, level - 1);
         if(lot <= prevLot + LOT_EPSILON)
           {
            WarnThrottled(book, "addon halted at level " + IntegerToString(level) +
                          " - lot escalation is flat at " + DoubleToString(lot, 2) +
                          " because the per-order cap is active.");
            return;
           }
        }
     }
   int ticket = SafeOrderSend(book, cmd, lot, BuildOrderComment(book, level));
   if(ticket > 0)
     {
      MarkCacheDirty(book);
      RefreshCache(book);
      g_bk[book].previousOpenCount = CountOwnOrders(book);
      g_bk[book].protectionDirty   = true;
     }
  }

//====================================================================
// LOT SIZING
//====================================================================
bool ExposureAllows(int book, double lot, int cmd)
  {
   if(lot <= 0.0)
      return(false);
   if(InpMaxTotalLots > 0.0 && TotalAccountLots() + lot > InpMaxTotalLots + LOT_EPSILON)
      return(false);
   if(cmd != OP_BUY && cmd != OP_SELL)
      cmd = (g_bk[book].sellCount > 0) ? OP_SELL : OP_BUY;
   if(AccountFreeMarginCheck(Symbol(), cmd, lot) <= 0.0)
      return(false);
   return(true);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CalculateRawLot(int book, int orderIndex)
  {
   if(InpDbLots == LOT_MULTIPLIER)
      return(BaseLotsForBook(book) * MathPow(InpMultiplier, orderIndex));
   if(InpDbLots == LOT_RECOVERY)
     {
      double base = (g_bk[book].nextRecoveryLot > 0.0) ? g_bk[book].nextRecoveryLot : BaseLotsForBook(book);
      return(base * MathPow(InpMultiplier, orderIndex));
     }
   return(BaseLotsForBook(book));
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(int book, int orderIndex)
  {
   double lot = NormalizeLotDown(CalculateRawLot(book, orderIndex));
   double cap = PerOrderCap(book);
   if(cap > 0.0 && lot > cap)
      lot = NormalizeLotDown(cap);
   return(lot);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int EffectiveMaxLevel(int book)
  {
   int maxLv = MaxLevelForBook(book);
   if(maxLv < 1)
      return(0);
   double cap = PerOrderCap(book);
   if(cap <= 0.0)
      return(maxLv);
   double prev = 0.0;
   for(int level = 0; level < maxLv; level++)
     {
      double lot = CalculateLotSize(book, level);
      if(level > 0 && lot <= prev + LOT_EPSILON)
         return(level);
      prev = lot;
     }
   return(maxLv);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string BuildOrderComment(int book, int level)
  {
   return(g_bookComment[book] + "|B" + IntegerToString(g_bk[book].basketId) +
          "|L" + IntegerToString(level));
  }

//====================================================================
// LOGICAL EXITS
//====================================================================
bool ManageLogicalExits(int book)
  {
   if(g_bk[book].buyCount == 0 && g_bk[book].sellCount == 0)
      return(false);
   double basketTP = ATRDistance(InpTP);
   double basketSL = ATRDistance(InpBasketSL_ATR);
   if(g_bk[book].buyCount > 0)
     {
      if(InpUseBasketTP && basketTP > 0.0 && Bid >= g_bk[book].buyAvg + basketTP)
        { TriggerCloseSide(book, OP_BUY, "buy basket ATR TP"); return(true); }
      if(InpUseBasketSL && basketSL > 0.0 && Bid <= g_bk[book].buyAvg - basketSL)
        { TriggerCloseSide(book, OP_BUY, "buy basket ATR SL"); return(true); }
     }
   if(g_bk[book].sellCount > 0)
     {
      if(InpUseBasketTP && basketTP > 0.0 && Ask <= g_bk[book].sellAvg - basketTP)
        { TriggerCloseSide(book, OP_SELL, "sell basket ATR TP"); return(true); }
      if(InpUseBasketSL && basketSL > 0.0 && Ask >= g_bk[book].sellAvg + basketSL)
        { TriggerCloseSide(book, OP_SELL, "sell basket ATR SL"); return(true); }
     }

   bool   acted   = false;
   double softSL  = ATRDistance(InpSL);
   double indivTP = ATRDistance(InpIndivTP);
   double hardSL  = ATRDistance(InpHardSL_ATR);
   int    nBuys   = g_bk[book].buyCount;
   int    nSells  = g_bk[book].sellCount;

   for(int i = 0; i < nBuys; i++)
     {
      COrderData ob = BookBuy(book, i);
      if(ob.ticket == 0)
         continue;
      bool bSoft = (softSL  > 0.0 && Bid <= (ob.openPrice - softSL));
      bool bTP   = (indivTP > 0.0 && Bid >= (ob.openPrice + indivTP));
      bool bHard = (hardSL  > 0.0 && Bid <= (ob.openPrice - hardSL));
      if((bSoft || bTP || bHard) && SafeOrderClose(book, ob.ticket, ob.lots))
         acted = true;
     }
   for(int j = 0; j < nSells; j++)
     {
      COrderData os = BookSell(book, j);
      if(os.ticket == 0)
         continue;
      bool sSoft = (softSL  > 0.0 && Ask >= (os.openPrice + softSL));
      bool sTP   = (indivTP > 0.0 && Ask <= (os.openPrice - indivTP));
      bool sHard = (hardSL  > 0.0 && Ask >= (os.openPrice + hardSL));
      if((sSoft || sTP || sHard) && SafeOrderClose(book, os.ticket, os.lots))
         acted = true;
     }
   if(InpUseTrailingStop)
      ApplyTrailingStops(book);
   return(acted);
  }

//====================================================================
// TRAILING STOP
//====================================================================
void ApplyTrailingStops(int book)
  {
   if(!g_atrValid)
      return;
   double startDist = ATRDistance(InpTrailStartATR);
   double trailDist = ATRDistance(InpTrailDistanceATR);
   double stepPrice = InpTrailStepPoints * Point;
   if(startDist <= 0.0 || trailDist <= 0.0)
      return;
   RefreshRates();
   int nB = g_bk[book].buyCount;
   int nS = g_bk[book].sellCount;
   for(int i = 0; i < nB; i++)
     {
      COrderData ob = BookBuy(book, i);
      if(ob.ticket > 0)
         TrailOne(book, ob, startDist, trailDist, stepPrice);
     }
   for(int j = 0; j < nS; j++)
     {
      COrderData os = BookSell(book, j);
      if(os.ticket > 0)
         TrailOne(book, os, startDist, trailDist, stepPrice);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void TrailOne(int book, const COrderData &ord, double startDist, double trailDist, double stepPrice)
  {
   bool   isBuy  = (ord.type == OP_BUY);
   double profit = isBuy ? (Bid - ord.openPrice) : (ord.openPrice - Ask);
   if(profit < startDist)
      return;
   double newSL = isBuy ? NormalizePrice(Bid - trailDist) : NormalizePrice(Ask + trailDist);
   if(newSL <= 0.0)
      return;
   if(isBuy  && newSL <= ord.openPrice)
      return;
   if(!isBuy && newSL >= ord.openPrice)
      return;
   if(isBuy)
     { if(ord.currentSL > 0.0 && (newSL - ord.currentSL) < stepPrice) return; }
   else
      if(ord.currentSL > 0.0 && (ord.currentSL - newSL) < stepPrice)
         return;
   if(SafeOrderModify(book, ord.ticket, newSL, ord.currentTP))
      LogTradeThrottled(book, "TRAIL", ord.ticket, ord.lots, isBuy ? Bid : Ask,
                        newSL, ord.currentTP, isBuy ? "buy trail" : "sell trail");
  }

//====================================================================
// HEDGE OFFSET
//====================================================================
void ApplyHedgeOffset(int book)
  {
   if(book != BOOK_PENDULUM || !InpUseHedgeOffset)
      return;
   if(InpBlockOnNetting && g_bk[book].nettingDetected)
      return;
   if(g_bk[book].buyCount == 0 || g_bk[book].sellCount == 0)
      return;
   if(TimeCurrent() - g_bk[book].lastHedgeOffset < InpHedgeOffsetCooldown)
      return;
   if(InpHedgeOffsetMinProfit <= 0.0 || InpHedgeOffsetMaxLoss <= 0.0)
      return;

   double balance = AccountBalance();
   if(balance <= 0.0)
      return;
   double scale     = (InpHedgeOffsetSize == HEDGE_OFF_PCT) ? (balance / 100.0) : 1.0;
   double minProfit = InpHedgeOffsetMinProfit * scale;
   double maxLoss   = InpHedgeOffsetMaxLoss   * scale;

   bool buyLosing  = (g_bk[book].buyPL  <= -maxLoss);
   bool sellLosing = (g_bk[book].sellPL <= -maxLoss);
   bool buyWin     = (g_bk[book].buyPL  >=  minProfit);
   bool sellWin    = (g_bk[book].sellPL >=  minProfit);

   if(buyLosing && sellWin)
     {
      g_bk[book].lastHedgeOffset = TimeCurrent();
      LogTrade(book, "HEDGE-OFFSET", 0, 0.0, 0.0, 0.0, 0.0,
               "harvest SELL +" + DoubleToString(g_bk[book].sellPL, 2) +
               " against BUY " + DoubleToString(g_bk[book].buyPL, 2));
      TriggerCloseSide(book, OP_SELL, "hedge offset: harvest winning SELL");
      return;
     }
   if(sellLosing && buyWin)
     {
      g_bk[book].lastHedgeOffset = TimeCurrent();
      LogTrade(book, "HEDGE-OFFSET", 0, 0.0, 0.0, 0.0, 0.0,
               "harvest BUY +" + DoubleToString(g_bk[book].buyPL, 2) +
               " against SELL " + DoubleToString(g_bk[book].sellPL, 2));
      TriggerCloseSide(book, OP_BUY, "hedge offset: harvest winning BUY");
      return;
     }
  }

//====================================================================
// CLOSE TRIGGERS
//====================================================================
void TriggerCloseSide(int book, int cmd, string reason)
  {
   g_bk[book].closeSidePending = cmd;
   g_bk[book].state            = EA_CLOSE_ALL_PENDING;
   g_stateReason[book]         = reason;
   LogTrade(book, "SIDE-EXIT", 0, 0.0, 0.0, 0.0, 0.0, reason);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void TriggerCloseAll(int book, string reason)
  {
   g_bk[book].closeSidePending = -1;
   g_bk[book].state            = EA_CLOSE_ALL_PENDING;
   g_stateReason[book]         = reason;
   LogTrade(book, "BASKET-EXIT", 0, 0.0, 0.0, 0.0, 0.0, reason);
  }

//====================================================================
// BROKER PROTECTION
//====================================================================
void ReconcileBrokerProtection(int book)
  {
   if(!g_atrValid || !IsTradeContextUsable())
     { g_bk[book].nextRepairTime = TimeCurrent() + PROTECTION_REPAIR_BAD; return; }
   RefreshRates();
   bool allGood = true;
   int nB = g_bk[book].buyCount;
   int nS = g_bk[book].sellCount;
   for(int i = 0; i < nB; i++)
     {
      COrderData rb = BookBuy(book, i);
      if(rb.ticket == 0)
         continue;
      if(!ReconcileOne(book, rb))
         allGood = false;
      if(g_bk[book].state == EA_CLOSE_ALL_PENDING)
         return;
     }
   for(int j = 0; j < nS; j++)
     {
      COrderData rs = BookSell(book, j);
      if(rs.ticket == 0)
         continue;
      if(!ReconcileOne(book, rs))
         allGood = false;
      if(g_bk[book].state == EA_CLOSE_ALL_PENDING)
         return;
     }
   g_bk[book].protectionDirty = !allGood;
   g_bk[book].nextRepairTime  = TimeCurrent() + (allGood ? PROTECTION_REPAIR_OK : PROTECTION_REPAIR_BAD);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool ReconcileOne(int book, const COrderData &ord)
  {
   double sl = 0.0, tp = 0.0;
   if(InpHardSL_ATR > 0.0)
      sl = (ord.type == OP_BUY) ? (ord.openPrice - ATRDistance(InpHardSL_ATR))
           : (ord.openPrice + ATRDistance(InpHardSL_ATR));
   if(InpIndivTP > 0.0)
      tp = (ord.type == OP_BUY) ? (ord.openPrice + ATRDistance(InpIndivTP))
           : (ord.openPrice - ATRDistance(InpIndivTP));
   if(ord.currentSL > 0.0)
     {
      if(ord.type == OP_BUY  && sl > 0.0 && ord.currentSL > sl)
         sl = ord.currentSL;
      if(ord.type == OP_SELL && sl > 0.0 && ord.currentSL < sl)
         sl = ord.currentSL;
     }
   if(sl > 0.0)
     {
      if((ord.type == OP_BUY && Bid <= sl) || (ord.type == OP_SELL && Ask >= sl))
        {
         TriggerCloseAll(book, "hard SL breach on ticket " + IntegerToString(ord.ticket));
         return(false);
        }
     }
   ConformStops(ord.type, sl, tp);
   double tolerance = MathMax(InpMinModifyPoints * Point, Point * 0.5);
   if(MathAbs(sl - ord.currentSL) < tolerance && MathAbs(tp - ord.currentTP) < tolerance)
      return(true);
   return(SafeOrderModify(book, ord.ticket, sl, tp));
  }

//====================================================================
// RISK STOPS
//====================================================================
bool CheckAccountRiskStops()
  {
   if(InpMinEquity > 0.0 && AccountEquity() <= InpMinEquity)
     { TriggerRiskStopAllBooks("equity floor", InpCloseAllOnDDStop); return(true); }
   if(InpMinMarginLevel > 0.0 && AccountMargin() > 0.0 &&
      (AccountEquity() / AccountMargin() * 100.0) <= InpMinMarginLevel)
     { TriggerRiskStopAllBooks("margin level breach", true); return(true); }
   if(InpMaxDrawdownPct <= 0.0)
      return(false);
   double balance = AccountBalance();
   if(balance <= 0.0)
      return(false);
   double floating = TotalAccountFloatingPL();
   double dd = (InpDDMode == DD_EA_FLOATING)
               ? MathMax(0.0, -floating / balance * 100.0)
               : MathMax(0.0, (balance - AccountEquity()) / balance * 100.0);
   if(dd >= InpMaxDrawdownPct)
     { TriggerRiskStopAllBooks("account drawdown breach", InpCloseAllOnDDStop); return(true); }
   return(false);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CheckBookRiskStops(int book)
  {
   int open = CountOwnOrders(book);
   if(InpMaxBasketLossMoney > 0.0 && open > 0 && g_bk[book].floatingPL <= -InpMaxBasketLossMoney)
     { TriggerRiskStop(book, "basket money stop", InpCloseAllOnDDStop); return(true); }
   UpdateHistoryState(book, false);
   if(InpMaxSessionDDPct > 0.0 && g_bk[book].sessionDDPct >= InpMaxSessionDDPct)
     { TriggerRiskStop(book, "session DD breach", InpCloseAllOnDDStop); return(true); }
   return(false);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void TriggerRiskStop(int book, string reason, bool closeOrders)
  {
   g_stateReason[book] = reason;
   LogTrade(book, "RISKSTOP", 0, 0.0, 0.0, 0.0, 0.0, reason);
   if(closeOrders && CountOwnOrders(book) > 0)
     {
      g_bk[book].latchAfterClose  = true;
      g_bk[book].closeSidePending = -1;
      g_bk[book].state            = EA_CLOSE_ALL_PENDING;
     }
   else
      LatchEquityStop(book, reason);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void TriggerRiskStopAllBooks(string reason, bool closeOrders)
  {
   for(int b = 0; b < BOOK_COUNT; b++)
      if(g_bk[b].enabled)
         TriggerRiskStop(b, reason, closeOrders);
  }

//====================================================================
// CLOSE-ALL FSM
//====================================================================
void DriveCloseAllFSM(int book)
  {
   bool protectionFault = (g_bk[book].state == EA_PROTECTION_FAULT);
   bool latchAfter      = g_bk[book].latchAfterClose;
   if(CloseAllOwnOrdersPass(book))
     {
      g_bk[book].closeFailStreak = 0;
      RefreshCache(book);
      if(CountOwnOrders(book) > 0)
         return;
      if(g_bk[book].closeSidePending >= 0)
        {
         g_bk[book].closeSidePending = -1;
         LogTrade(book, "SIDE-END", 0, 0.0, 0.0, 0.0, 0.0,
                  "side close complete, basket #" + IntegerToString(g_bk[book].basketId) + " still open");
         g_bk[book].state    = g_atrValid ? EA_RUNNING : EA_WAIT_ATR;
         g_stateReason[book] = "side closed, basket live";
        }
      else
        {
         FinalizeBasket(book);
         if(latchAfter || protectionFault)
            LatchEquityStop(book, g_stateReason[book]);
         else
           { g_bk[book].state = g_atrValid ? EA_RUNNING : EA_WAIT_ATR; g_stateReason[book] = "basket closed"; }
        }
      g_bk[book].latchAfterClose = false;
     }
  }

//====================================================================
// SAFE TRADE OPERATIONS
//====================================================================
int SafeOrderSend(int book, int cmd, double lot, string comment)
  {
   if(!g_atrValid || !IsTradeContextUsable() || lot <= 0.0 || !ExposureAllows(book, lot, cmd))
      return(-1);
   int ownBefore      = CountOwnOrders(book);
   int oppositeBefore = (cmd == OP_BUY) ? g_bk[book].sellCount : g_bk[book].buyCount;

   RefreshRates();
   double entry = (cmd == OP_BUY) ? Ask : Bid;
   double sl = 0.0, tp = 0.0;
   if(InpHardSL_ATR > 0.0)
      sl = (cmd == OP_BUY) ? (entry - ATRDistance(InpHardSL_ATR)) : (entry + ATRDistance(InpHardSL_ATR));
   if(InpIndivTP > 0.0)
      tp = (cmd == OP_BUY) ? (entry + ATRDistance(InpIndivTP)) : (entry - ATRDistance(InpIndivTP));
   ConformStops(cmd, sl, tp);

   int ticket = SendMarketAttempt(book, cmd, lot, sl, tp, comment);
   if(ticket > 0)
     {
      ProbeNetting(book, cmd, ownBefore, oppositeBefore);
      LogTrade(book, "OPEN", ticket, lot, entry, sl, tp, (cmd == OP_BUY ? "buy" : "sell") + " open");
      return(ticket);
     }
   if(InpRequireBrokerSL || ticket != -2)
      return(-1);

   ticket = SendMarketAttempt(book, cmd, lot, 0.0, 0.0, comment);
   if(ticket <= 0)
      return(-1);

   if(SafeOrderModify(book, ticket, sl, tp))
     {
      ProbeNetting(book, cmd, ownBefore, oppositeBefore);
      double op1 = (OrderSelect(ticket, SELECT_BY_TICKET) ? OrderOpenPrice() : entry);
      LogTrade(book, "OPEN", ticket, lot, op1, sl, tp, "open fallback-modify");
      return(ticket);
     }

   if(OrderSelect(ticket, SELECT_BY_TICKET) && SafeOrderClose(book, ticket, OrderLots()))
     {
      double cp = (OrderType() == OP_BUY) ? Bid : Ask;
      LogTrade(book, "CLOSE-FAILSAFE", ticket, lot, cp, 0.0, 0.0, "unprotected open reverted");
      return(-1);
     }

   double fSL = sl, fTP = tp;
   ConformStops(cmd, fSL, fTP);
   if(fSL > 0.0 && SafeOrderModify(book, ticket, fSL, fTP))
     {
      double op2 = (OrderSelect(ticket, SELECT_BY_TICKET) ? OrderOpenPrice() : entry);
      LogTrade(book, "OPEN", ticket, lot, op2, fSL, fTP, "open last-resort stop");
      return(ticket);
     }

   g_bk[book].state    = EA_PROTECTION_FAULT;
   g_stateReason[book] = "unprotected order " + IntegerToString(ticket);
   Alert("HOKKY V7.0 [", BookName(book), "]: order ", ticket,
         " could not be protected - entering PROTECTION_FAULT.");
   return(-1);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ProbeNetting(int book, int cmd, int ownBefore, int oppositeBefore)
  {
   if(g_bk[book].nettingDetected)
      return;
   if(book != BOOK_PENDULUM)
      return;
   RefreshCache(book);
   int ownAfter = CountOwnOrders(book);
   if(oppositeBefore <= 0)
     {
      g_bk[book].nettingProbed = false;
      return;
     }
   if(ownAfter == ownBefore + 1)
     {
      g_bk[book].nettingProbed = true;
      return;
     }

   g_bk[book].nettingDetected = true;
   g_bk[book].nettingProbed   = true;
   g_stateReason[book]        = "netting account - pendulum adds blocked";
   if(TimeCurrent() - g_nettingAlertTime > WARN_THROTTLE_SEC)
     {
      g_nettingAlertTime = TimeCurrent();
      Alert("HOKKY V7.0 CRITICAL: account NETS positions (", ownBefore, " -> ", ownAfter,
            "). The pendulum engine CANNOT work here.");
     }
   LogTrade(book, "ACCOUNT-FAULT", 0, 0.0, 0.0, 0.0, 0.0,
            "netting detected: " + IntegerToString(ownBefore) + " -> " + IntegerToString(ownAfter));
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int SendMarketAttempt(int book, int cmd, double lot, double sl, double tp, string comment)
  {
   for(int attempt = 0; attempt < MAX_SEND_ATTEMPTS; attempt++)
     {
      if(!IsTradeContextUsable())
         return(-1);
      RefreshRates();
      double price = (cmd == OP_BUY) ? Ask : Bid;
      ResetLastError();
      int ticket = OrderSend(Symbol(), cmd, lot, price, InpSlippage,
                             NormalizePrice(sl), NormalizePrice(tp),
                             comment, g_bk[book].magic, 0,
                             (cmd == OP_BUY) ? clrBlue : clrRed);
      if(ticket > 0)
         return(ticket);
      int err = GetLastError();
      if(err == ERR_INVALID_STOPS)
         return(-2);
      if(!IsTransientTradeError(err))
         return(-1);
      if(attempt < MAX_SEND_ATTEMPTS - 1)
         Sleep(50 + attempt * 50);
     }
   return(-1);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool SafeOrderModify(int book, int ticket, double newSL, double newTP)
  {
   for(int attempt = 0; attempt < MAX_CLOSE_ATTEMPTS; attempt++)
     {
      if(!OrderSelect(ticket, SELECT_BY_TICKET) || OrderCloseTime() > 0 ||
         OrderSymbol() != Symbol() || OrderMagicNumber() != g_bk[book].magic ||
         !IsTradeContextUsable())
         return(false);
      int    cmd = OrderType();
      double sl  = newSL, tp = newTP;
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
           {
            if(newSL > 0.0)
               newSL -= pad;
            if(newTP > 0.0)
               newTP += pad;
           }
         else
           {
            if(newSL > 0.0)
               newSL += pad;
            if(newTP > 0.0)
               newTP -= pad;
           }
        }
      else
         if(!IsTransientTradeError(err))
            return(false);
      if(attempt < MAX_CLOSE_ATTEMPTS - 1)
         Sleep(50 + attempt * 50);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool SafeOrderClose(int book, int ticket, double lots)
  {
   for(int attempt = 0; attempt < MAX_CLOSE_ATTEMPTS; attempt++)
     {
      if(!OrderSelect(ticket, SELECT_BY_TICKET) || OrderCloseTime() > 0 ||
         OrderSymbol() != Symbol() || OrderMagicNumber() != g_bk[book].magic ||
         !IsTradeContextUsable())
         return(false);
      double volume = lots;
      if(volume <= 0.0 || volume > OrderLots() + LOT_EPSILON)
         volume = OrderLots();
      if(volume <= 0.0)
         return(false);
      RefreshRates();
      double price = (OrderType() == OP_BUY) ? Bid : Ask;
      ResetLastError();
      if(OrderClose(ticket, volume, price, InpExitSlippage, clrYellow))
        { LogTrade(book, "CLOSE", ticket, volume, price, 0.0, 0.0, "logical close"); return(true); }
      int err = GetLastError();
      if(!IsTransientTradeError(err))
         return(false);
      if(attempt < MAX_CLOSE_ATTEMPTS - 1)
         Sleep(50 + attempt * 50);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CloseAllOwnOrdersPass(int book)
  {
   if(!IsTradeContextUsable())
      return(false);
   RefreshRates();
   int failures = 0, closed = 0;
   int target = g_bk[book].closeSidePending;
   int magic  = g_bk[book].magic;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES) ||
         OrderSymbol() != Symbol() || OrderMagicNumber() != magic)
         continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL)
         continue;
      if(target >= 0 && type != target)
         continue;
      RefreshRates();                          // Patch 1: fresh Bid/Ask per iteration
      int    ticket = OrderTicket();
      double volume = OrderLots();
      double price  = (type == OP_BUY) ? Bid : Ask;
      ResetLastError();
      if(!OrderClose(ticket, volume, price, InpExitSlippage, clrYellow))
        {
         failures++;
         int err = GetLastError();
         if(!IsTransientTradeError(err))
            Print("HOKKY V7.0 [", BookName(book), "]: close failed. Ticket=", ticket, " error=", err);
        }
      else
        { closed++; LogTrade(book, "CLOSE", ticket, volume, price, 0.0, 0.0, "close pass"); }
     }
   if(failures > 0)
     {
      g_bk[book].closeFailStreak++;
      if(g_bk[book].closeFailStreak == InpMaxCloseFailures &&
         TimeCurrent() - g_bk[book].lastCloseFailAlert > WARN_THROTTLE_SEC)
        {
         g_bk[book].lastCloseFailAlert = TimeCurrent();
         Alert("HOKKY V7.0 [", BookName(book), "]: ", failures,
               " order close(s) failed in a row. Check the Journal now.");
         LogTrade(book, "CLOSE-FAIL", 0, 0.0, 0.0, 0.0, 0.0,
                  "streak=" + IntegerToString(g_bk[book].closeFailStreak));
        }
     }
   else
      if(closed > 0)
         g_bk[book].closeFailStreak = 0;
   RefreshCache(book);
   if(target >= 0)
     {
      int remaining = (target == OP_BUY) ? g_bk[book].buyCount : g_bk[book].sellCount;
      if(remaining == 0)
         g_bk[book].closeSidePending = -1;
      return(remaining == 0);
     }
   return(CountOwnOrders(book) == 0);
  }

//====================================================================
// UTILITY
//====================================================================
bool IsTradeContextUsable()
  {
   if(IsTesting())
      return(IsTradeAllowed());
   if(IsTradeAllowed() && !IsTradeContextBusy())
      return(true);
   for(int i = 0; i < TRADE_CTX_WAIT_STEPS; i++)
     {
      if(!IsTradeContextBusy())
         break;
      Sleep(TRADE_CTX_WAIT_MS);
     }
   return(IsTradeAllowed() && !IsTradeContextBusy());
  }

//+------------------------------------------------------------------+
//|                                                                  |
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
//|                                                                  |
//+------------------------------------------------------------------+
void ConformStops(int cmd, double &sl, double &tp)
  {
   if(cmd != OP_BUY && cmd != OP_SELL)
      return;
   double minDist = MathMax(MarketInfo(Symbol(), MODE_STOPLEVEL) * Point,
                            MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point);
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
//|                                                                  |
//+------------------------------------------------------------------+
double NormalizePrice(double price)
  { return(price <= 0.0 ? 0.0 : NormalizeDouble(price, Digits)); }

//+------------------------------------------------------------------+
//|                                                                  |
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
//|                                                                  |
//+------------------------------------------------------------------+
double NormalizeLotDown(double lot)
  {
   if(lot <= 0.0)
      return(0.0);
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0.0)
      step = 0.01;
   int    digits = LotDigits(step);
   double result = MathFloor(lot / step + 1e-9) * step;
   result = NormalizeDouble(result, digits);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   if(maxLot > 0.0 && result > maxLot)
      result = NormalizeDouble(maxLot, digits);
   if(result < MarketInfo(Symbol(), MODE_MINLOT) - LOT_EPSILON)
      return(0.0);
   return(result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
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
//|                                                                  |
//+------------------------------------------------------------------+
void WarnThrottled(int book, string text)
  {
   if(TimeCurrent() - g_bk[book].lastWarning < WARN_THROTTLE_SEC)
      return;
   g_bk[book].lastWarning = TimeCurrent();
   Print("HOKKY V7.0 WARN [", BookName(book), "]: ", text);
  }

//====================================================================
// JOURNAL
//====================================================================
void OpenJournal()
  {
   if(!InpJournalEnabled || g_journalHandle != INVALID_HANDLE)
      return;
   g_journalHandle = FileOpen(InpJournalFile, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ';');
   if(g_journalHandle == INVALID_HANDLE)
     { Print("HOKKY V7.0: journal could not be opened. Error ", GetLastError()); return; }
   FileSeek(g_journalHandle, 0, SEEK_END);
   if(FileSize(g_journalHandle) == 0)
      FileWrite(g_journalHandle, "time", "engine", "action", "ticket", "magic", "symbol",
                "lots", "price", "sl", "tp", "balance", "equity", "note");
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CloseJournal()
  {
   if(g_journalHandle == INVALID_HANDLE)
      return;
   FlushJournal(true);
   FileClose(g_journalHandle);
   g_journalHandle = INVALID_HANDLE;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void FlushJournal(bool force)
  {
   if(g_journalHandle == INVALID_HANDLE)
      return;
   if(!force && TimeCurrent() - g_lastJournalFlush < 10)
      return;
   g_lastJournalFlush = TimeCurrent();
   FileFlush(g_journalHandle);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void LogTrade(int book, string action, int ticket, double lots, double price,
              double sl, double tp, string note)
  {
   if(!InpJournalEnabled)
      return;
   OpenJournal();
   if(g_journalHandle == INVALID_HANDLE)
      return;
   FileSeek(g_journalHandle, 0, SEEK_END);
   FileWrite(g_journalHandle,
             TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
             BookName(book), action, IntegerToString(ticket),
             IntegerToString(g_bk[book].magic), Symbol(),
             DoubleToString(lots, 2), DoubleToString(price, Digits),
             DoubleToString(sl, Digits), DoubleToString(tp, Digits),
             DoubleToString(AccountBalance(), 2), DoubleToString(AccountEquity(), 2), note);
   FlushJournal(false);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void LogTradeThrottled(int book, string action, int ticket, double lots, double price,
                       double sl, double tp, string note)
  {
   if(TimeCurrent() - g_lastTrailLog < TRAIL_LOG_THROTTLE_SEC)
      return;
   g_lastTrailLog = TimeCurrent();
   LogTrade(book, action, ticket, lots, price, sl, tp, note);
  }

//====================================================================
// DASHBOARD
//====================================================================
void UpdateDashboardThrottled()
  {
   if(!InpUseDashboard || TimeCurrent() - g_lastDashboard < DASHBOARD_THROTTLE)
      return;
   g_lastDashboard = TimeCurrent();
   UpdateDashboard();
  }

//+------------------------------------------------------------------+
//|                                                                  |
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
      case EA_ACCOUNT_FAULT:
         return("ACCOUNT_FAULT");
     }
   return("?");
  }

//+------------------------------------------------------------------+
//|                                                                  |
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
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, 0);
      ObjectSetInteger(0, obj, OBJPROP_HIDDEN, 1);
     }
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, fontsize);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clrText);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
  }

void DeleteOwnObjects() { ObjectsDeleteAll(ChartID(), g_objPrefix); }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   if(!InpUseDashboard)
      return;
   int x = 12, y = 22, dy = 15, line = 0;
   string adxText       = (g_adxValid ? DoubleToString(g_adx, 1) : "n/a");
   bool   classicLive   = (g_bk[BOOK_CLASSIC].enabled  && RegimeAllowsClassic());
   bool   pendulumLive  = (g_bk[BOOK_PENDULUM].enabled && RegimeAllowsPendulum());

   SetLabel("00", x, y + dy * line++,
            "HOKKY V7.0 DUAL | " + Symbol() + " M" + IntegerToString(Period()) +
            " | ADX " + adxText + " (split " + DoubleToString(InpADXThreshold, 1) + ")",
            clrWhite, 9);

   SetLabel("01", x, y + dy * line++,
            "REGIME  CLASSIC: " + (g_bk[BOOK_CLASSIC].enabled ? (classicLive ? "ACTIVE (low ADX)" : "idle") : "off") +
            "    PENDULUM: " + (g_bk[BOOK_PENDULUM].enabled ? (pendulumLive ? "ACTIVE (high ADX)" : "idle") : "off"),
            (classicLive ? clrDodgerBlue : (pendulumLive ? clrTomato : clrSilver)), 9);

   for(int b = 0; b < BOOK_COUNT; b++)
     {
      int   base = 10 + b * 4;
      color head = (b == BOOK_PENDULUM) ? clrTomato : clrDodgerBlue;
      if(!g_bk[b].enabled)
         head = clrGray;
      SetLabel(IntegerToString(base), x, y + dy * line++,
               BookName(b) + " magic " + IntegerToString(g_bk[b].magic) +
               " | " + StateText(g_bk[b].state) + (IsEquityStopLatched(b) ? " LATCHED" : ""),
               head, 9);
      SetLabel(IntegerToString(base + 1), x, y + dy * line++,
               "  n=" + IntegerToString(CountOwnOrders(b)) +
               " B" + IntegerToString(g_bk[b].buyCount) + "/S" + IntegerToString(g_bk[b].sellCount) +
               " lots=" + DoubleToString(g_bk[b].buyLots + g_bk[b].sellLots, 2) +
               " float=" + DoubleToString(g_bk[b].floatingPL, 2) +
               " lvl " + IntegerToString(CountOwnOrders(b)) + "/" + IntegerToString(MaxLevelForBook(b)) +
               ((EffectiveMaxLevel(b) < MaxLevelForBook(b)) ? " EFF " + IntegerToString(EffectiveMaxLevel(b)) : ""),
               clrSilver, 8);
      SetLabel(IntegerToString(base + 2), x, y + dy * line++,
               "  sessDD " + DoubleToString(g_bk[b].sessionDDPct, 2) + "%/" +
               DoubleToString(InpMaxSessionDDPct, 1) + "%  basket#" + IntegerToString(g_bk[b].basketId) +
               (g_bk[b].basketActive ? " active" : " idle") +
               "  next " + DoubleToString(g_bk[b].nextRecoveryLot, 2), clrSilver, 8);
      SetLabel(IntegerToString(base + 3), x, y + dy * line++,
               "  closeFails " + IntegerToString(g_bk[b].closeFailStreak) +
               "  trail " + (InpUseTrailingStop ? "ON" : "OFF") +
               (b == BOOK_PENDULUM
                ? ("  offset " + (InpUseHedgeOffset ? "ON" : "OFF") +
                   (g_bk[b].nettingDetected ? "  NETTING!" : (g_bk[b].nettingProbed ? "  hedge OK" : "  probe...")))
                : "  fade ladder"),
               (g_bk[b].nettingDetected ? clrRed : clrSilver), 8);
     }

   double marginLevel = (AccountMargin() > 0.0) ? AccountEquity() / AccountMargin() * 100.0 : 0.0;
   SetLabel("20", x, y + dy * line++,
            "ACCOUNT  orders " + IntegerToString(TotalAccountOrders()) +
            "  lots " + DoubleToString(TotalAccountLots(), 2) + "/" + DoubleToString(InpMaxTotalLots, 2) +
            "  float " + DoubleToString(TotalAccountFloatingPL(), 2) +
            "  margin " + (marginLevel > 0.0 ? DoubleToString(marginLevel, 1) + "%" : "n/a"),
            clrSilver, 9);

   int gateDir = GetSharedLastInitDirection();   // Patch 3: show the shared gate
   SetLabel("23", x, y + dy * line++,
            "GATE: next L0 must be " +
            (gateDir == OP_BUY ? "SELL" : (gateDir == OP_SELL ? "BUY" : "either (open)")),
            clrYellow, 8);

   SetLabel("21", x, y + dy * line++,
            "Guards: " + (InpRequireBrokerSL ? "brokerSL " : "") +
            (InpMinEquity > 0 ? "eqFloor " : "") +
            (InpMaxBasketLossMoney > 0 ? "moneyStop " : "") +
            "spread " + DoubleToString(CurrentSpreadPoints(), 1) +
            "  slip in " + IntegerToString(InpSlippage) + "/out " + IntegerToString(InpExitSlippage),
            (InpMinEquity > 0 || InpMaxBasketLossMoney > 0 ? clrSilver : clrOrange), 8);

   ChartRedraw();
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
