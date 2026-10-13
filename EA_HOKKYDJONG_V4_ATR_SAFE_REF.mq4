//+------------------------------------------------------------------+
//| EA_HOKKYDJONG_V4_ATR_SAFE_REF.mq4                                |
//| Safer single-file reference derived from HOKKY V4 ATR review.     |
//| Purpose: provide a conservative, well-structured, audit-friendly  |
//| single-file MQ4 template that demonstrates best-practice patterns |
//| and explicit risk gating without modifying the original EA.      |
//+------------------------------------------------------------------+
#property strict
#property copyright "HOKKY Safe Reference"
#property version  "4.30-refactor"
#property description "Safe reference: ATR-normalized grid/recovery template with explicit risk gates"

#include <stderror.mqh>

//--- Enums and types
enum ENUM_LOT_MODE { LOT_FIXED=0, LOT_MULTIPLIER=1, LOT_RECOVERY=2 };
struct OrderRec { int ticket; int type; double lots; double price; datetime opentm; };

//--- Inputs (conservative defaults)
input string InpEA_Comment = "HOKKY_SAFE_REF";
input int    InpMagicNumber = 0;            // 0 = auto
input double InpLots = 0.01;               // base lot
input ENUM_LOT_MODE InpLotMode = LOT_MULTIPLIER;
input double InpMultiplier = 1.30;         // conservative multiplier
input int    InpMaxLevel = 8;              // max grid levels
input double InpMaxLotPerOrder = 0.5;      // per-order cap
input double InpMaxTotalLots = 2.0;        // total exposure cap
input int    InpATRPeriod = 14;
input double InpDistanceATR = 1.0;         // grid spacing in ATR
input double InpBasketTP_ATR = 0.75;
input bool   InpRequireBrokerSL = true;
input double InpHardSL_ATR = 6.0;          // hard SL in ATR units
input double InpMinEquity = 50.0;          // absolute equity floor in account currency
input double InpMaxDrawdownPct = 10.0;     // overall drawdown stop
input int    InpLeaseStaleSeconds = 15;    // simple instance lease
input double InpMaxSpreadPoints = 40.0;    // spread gate

//--- Globals
int g_magic = 0;
double g_atr = 0.0;
bool g_atrValid = false;
string g_prefix = "";
int g_ownerToken = 0;
bool g_lockOwned = false, g_leaseLost = false;

//--- Simple state
OrderRec g_orders[];
int g_levels = 0;

auto NormalizeLotDownSafe = 0.0; // placeholder to avoid warning

//+------------------------------------------------------------------+
//| Utility helpers                                                  |
//+------------------------------------------------------------------+
int PositiveHash(string s)
{
   int h = 0;
   for(int i=0;i<StringLen(s);i++) h = (h*31) + StringGetCharacter(s,i);
   return(MathAbs(h));
}

double LotEpsilon() { return(0.00001); }

double NormalizeLotDown(double lot)
{
   // attempt to normalize to broker step using MarketInfo
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minlot = MarketInfo(Symbol(), MODE_MINLOT);
   if(step <= 0.0) step = 0.01;
   double n = MathFloor(lot/step) * step;
   if(n < minlot) n = minlot;
   return(NormalizeDouble(n,2));
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   MathSrand((int)GetTickCount());
   g_ownerToken = (int)(GetTickCount()%1000000) + MathRand();

   if(!ValidateInputs())
      return(INIT_PARAMETERS_INCORRECT);

   ResolveMagic();
   BuildPrefix();
   if(!AcquireLease())
   {
      Print("HOKKY_SAFE: lease not acquired, another instance may be running");
      return(INIT_FAILED);
   }

   UpdateATR(true);

   EventSetTimer(2);
   Print("HOKKY_SAFE_REF initialized. Magic=", g_magic);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ReleaseLease();
}

//+------------------------------------------------------------------+
//| Timer: heartbeat                                                  |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(g_leaseLost) return;
   TouchLease();
}

//+------------------------------------------------------------------+
//| Tick: main loop                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
   if(g_leaseLost) return;

   bool newBar = UpdateATR(false);
   RefreshOrders();

   // Risk gating
   if(IsAccountBelowMin())
   {
      Print("HOKKY_SAFE: account below minimum equity, halting entries");
      return;
   }

   if(!g_atrValid) return;

   // Manage exits and basket TP
   ManageExits();

   // Entries on new bar only to reduce noise
   if(Time[0] != Time[1])
      ProcessTrading();
}

//+------------------------------------------------------------------+
//| Validate inputs                                                   |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
   if(InpLots <= 0.0) { Print("Invalid InpLots"); return(false); }
   if(InpMultiplier < 1.0) { Print("Invalid multiplier"); return(false); }
   if(InpMaxLevel < 1) { Print("Invalid max level"); return(false); }
   if(InpATRPeriod < 1) { Print("Invalid ATR period"); return(false); }
   if(InpLeaseStaleSeconds < 5) { Print("Lease staleness too low"); return(false); }
   if(InpRequireBrokerSL && InpHardSL_ATR <= 0.0) { Print("Require hard SL when RequireBrokerSL is true"); return(false); }
   return(true);
}

//+------------------------------------------------------------------+
//| Magic and prefix                                                  |
//+------------------------------------------------------------------+
void ResolveMagic()
{
   if(InpMagicNumber > 0)
      g_magic = InpMagicNumber;
   else
   {
      string key = IntegerToString(AccountNumber()) + "_" + IntegerToString(PositiveHash(AccountServer())) + "_" + IntegerToString(PositiveHash(Symbol()));
      g_magic = GenerateMagicNumber(Symbol()+AccountServer()+IntegerToString(AccountNumber()));
   }
}

void BuildPrefix()
{
   g_prefix = "H4_" + IntegerToString(AccountNumber()) + "_" + IntegerToString(PositiveHash(AccountServer())) + "_" + IntegerToString(PositiveHash(Symbol())) + "_" + IntegerToString(g_magic) + "_";
}

//+------------------------------------------------------------------+
//| Simple lease (single instance)                                    |
//+------------------------------------------------------------------+
bool AcquireLease()
{
   if(!GlobalVariableCheck(g_prefix + "OWN")) GlobalVariableSet(g_prefix + "OWN", 0.0);
   if(!GlobalVariableCheck(g_prefix + "BEAT")) GlobalVariableSet(g_prefix + "BEAT", 0.0);

   double observed = GlobalVariableGet(g_prefix + "OWN");
   datetime beat = (datetime)GlobalVariableGet(g_prefix + "BEAT");
   datetime now = TimeLocal();
   if(observed != 0.0 && (now - beat) < InpLeaseStaleSeconds)
      return(false);
   if(!GlobalVariableSetOnCondition(g_prefix + "OWN", (double)g_ownerToken, observed))
      return(false);
   GlobalVariableSet(g_prefix + "BEAT", (double)now);
   GlobalVariablesFlush();
   g_lockOwned = true;
   return(true);
}

void TouchLease()
{
   if(!g_lockOwned) return;
   if((int)GlobalVariableGet(g_prefix + "OWN") != g_ownerToken)
   {
      g_lockOwned = false; g_leaseLost = true;
      Print("HOKKY_SAFE: lease lost");
      return;
   }
   GlobalVariableSet(g_prefix + "BEAT", (double)TimeLocal());
}

void ReleaseLease()
{
   if(!g_lockOwned) return;
   if((int)GlobalVariableGet(g_prefix + "OWN") == g_ownerToken)
   {
      GlobalVariableSet(g_prefix + "BEAT", 0.0);
      GlobalVariableSet(g_prefix + "OWN", 0.0);
      GlobalVariablesFlush();
   }
   g_lockOwned = false;
}

//+------------------------------------------------------------------+
//| ATR computation                                                   |
//+------------------------------------------------------------------+
bool UpdateATR(bool force)
{
   datetime bar = iTime(Symbol(), Period(), 0);
   static datetime lastBar = 0;
   if(!force && bar == lastBar) return(false);
   lastBar = bar;

   double v = iATR(Symbol(), Period(), InpATRPeriod, 1);
   datetime src = iTime(Symbol(), Period(), 1);
   if(v > Point*0.5 && src > 0)
   {
      g_atr = v; g_atrValid = true; return(true);
   }
   g_atrValid = false; return(false);
}

double ATRDistance(double factor)
{
   if(!g_atrValid || factor <= 0.0) return(0.0);
   return(factor * g_atr);
}

//+------------------------------------------------------------------+
//| Order cache refresh                                                |
//+------------------------------------------------------------------+
void RefreshOrders()
{
   ArrayResize(g_orders,0);
   for(int i=0;i<OrdersTotal();i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != g_magic) continue;
      if(OrderSymbol() != Symbol()) continue;
      OrderRec r; r.ticket = OrderTicket(); r.type = OrderType(); r.lots = OrderLots(); r.price = OrderOpenPrice(); r.opentm = OrderOpenTime();
      int n = ArraySize(g_orders); ArrayResize(g_orders, n+1); g_orders[n] = r;
   }
}

//+------------------------------------------------------------------+
//| Risk gates                                                         |
//+------------------------------------------------------------------+
bool IsAccountBelowMin()
{
   if(InpMinEquity > 0.0 && AccountEquity() < InpMinEquity) return(true);
   double usedLots = 0.0; for(int i=0;i<ArraySize(g_orders);i++) usedLots += g_orders[i].lots;
   if(InpMaxTotalLots > 0.0 && usedLots >= InpMaxTotalLots - LotEpsilon()) return(true);
   // drawdown check (session not tracked here - simple equity drawdown)
   double ddPct = 0.0; // placeholder - extend with persistent session tracking
   if(InpMaxDrawdownPct > 0.0 && ddPct >= InpMaxDrawdownPct) return(true);
   return(false);
}

//+------------------------------------------------------------------+
//| Trading engine: entries                                             |
//+------------------------------------------------------------------+
void ProcessTrading()
{
   if(!IsTradeContextUsable()) return;
   if(CurrentSpreadPoints() > InpMaxSpreadPoints) return;

   int openCount = ArraySize(g_orders);
   if(openCount == 0)
   {
      if(!InpRequireBrokerSL || (InpRequireBrokerSL && InpHardSL_ATR>0.0))
         OpenInitialTrade();
      return;
   }

   if(openCount >= InpMaxLevel) return;

   // Example simple addon: if price moved by ATR distance from newest, add
   double newestPrice = g_orders[ArraySize(g_orders)-1].price;
   int side = g_orders[ArraySize(g_orders)-1].type;
   double distance = ATRDistance(InpDistanceATR);
   if(side == OP_BUY)
   {
      if((newestPrice - Ask) >= distance)
         OpenAddon(OP_BUY);
   }
   else if(side == OP_SELL)
   {
      if((Bid - newestPrice) >= distance)
         OpenAddon(OP_SELL);
   }
}

void OpenInitialTrade()
{
   double close2 = iClose(Symbol(), Period(), 2);
   double close1 = iClose(Symbol(), Period(), 1);
   if(close1 <= 0 || close2 <= 0) return;
   int cmd = (close2 > close1) ? OP_SELL : OP_BUY;
   double lot = CalculateLotSize(0);
   if(!ExposureAllows(lot, cmd)) return;
   int ticket = SafeOrderSend(cmd, lot, "INIT");
   if(ticket>0) { RefreshOrders(); }
}

void OpenAddon(int cmd)
{
   int level = ArraySize(g_orders);
   double lot = CalculateLotSize(level);
   if(!ExposureAllows(lot, cmd)) return;
   int ticket = SafeOrderSend(cmd, lot, "ADD");
   if(ticket>0) { RefreshOrders(); }
}

//+------------------------------------------------------------------+
//| Lot sizing                                                         |
//+------------------------------------------------------------------+
double CalculateRawLot(int idx)
{
   if(InpLotMode == LOT_MULTIPLIER) return(InpLots * MathPow(InpMultiplier, idx));
   if(InpLotMode == LOT_RECOVERY) return(InpLots * MathPow(InpMultiplier, idx));
   return(InpLots);
}

double CalculateLotSize(int idx)
{
   double lot = CalculateRawLot(idx);
   lot = NormalizeLotDown(lot);
   if(InpMaxLotPerOrder > 0.0 && lot > InpMaxLotPerOrder) lot = NormalizeLotDown(InpMaxLotPerOrder);
   return(lot);
}

bool ExposureAllows(double lot, int cmd)
{
   if(lot <= 0.0) return(false);
   double usedLots = 0.0; for(int i=0;i<ArraySize(g_orders);i++) usedLots += g_orders[i].lots;
   if(InpMaxTotalLots > 0.0 && usedLots + lot > InpMaxTotalLots + LotEpsilon()) return(false);
   if(AccountFreeMarginCheck(Symbol(), cmd, lot) <= 0.0) return(false);
   return(true);
}

//+------------------------------------------------------------------+
//| Safe order send / enforce broker SL                                |
//+------------------------------------------------------------------+
int SafeOrderSend(int cmd, double lots, string comment)
{
   double price = (cmd==OP_BUY) ? Ask : Bid;
   double sl = 0.0, tp = 0.0;
   if(InpRequireBrokerSL && InpHardSL_ATR>0.0)
   {
      double slDist = ATRDistance(InpHardSL_ATR);
      if(cmd==OP_BUY) sl = price - slDist; else sl = price + slDist;
   }

   int ticket = OrderSend(Symbol(), cmd, lots, price, 3, sl, tp, InpEA_Comment + "_" + IntegerToString(g_magic), g_magic, 0, clrNONE);
   if(ticket < 0)
   {
      int err = GetLastError();
      Print("SafeOrderSend failed: ", err, " (", ErrorDescription(err), ")");
      ResetLastError();
      return(-1);
   }
   // verify SL was accepted by broker when required
   if(InpRequireBrokerSL && sl != 0.0)
   {
      // small retry: reselect and check
      if(!OrderSelect(ticket, SELECT_BY_TICKET)) return(ticket);
      if(OrderStopLoss() == 0.0)
      {
         Print("Warning: broker did not set SL for ticket ", ticket);
         // try to set it now
         bool ok = OrderModify(ticket, OrderOpenPrice(), sl, OrderTakeProfit(), 0, clrNONE);
         if(!ok) Print("Failed to modify SL for ticket ", ticket, " err=", GetLastError());
      }
   }
   return(ticket);
}

//+------------------------------------------------------------------+
//| Logical exits / basket TP                                           |
//+------------------------------------------------------------------+
void ManageExits()
{
   // simple basket TP: if total unrealized profit exceeds ATR-scaled threshold, close all
   double unreal = 0.0;
   for(int i=0;i<ArraySize(g_orders);i++)
   {
      if(!OrderSelect(g_orders[i].ticket, SELECT_BY_TICKET)) continue;
      unreal += OrderProfit() + OrderSwap() + OrderCommission();
   }
   double target = ATRDistance(InpBasketTP_ATR);
   // convert ATR distance to profit target is non-trivial; this is a placeholder conservative action
   if(unreal >= 0.0 && unreal >= target * MarketInfo(Symbol(), MODE_TICKVALUE))
   {
      Print("Basket TP hit, closing all orders");
      CloseAllOwnOrders();
   }
}

void CloseAllOwnOrders()
{
   for(int i=ArraySize(g_orders)-1;i>=0;i--)
   {
      int t = g_orders[i].ticket;
      if(!OrderSelect(t, SELECT_BY_TICKET)) continue;
      int type = OrderType();
      bool ok = OrderClose(t, OrderLots(), (type==OP_BUY)?Bid:Ask, 3, clrNONE);
      if(!ok) Print("Close failed for ", t, " err=", GetLastError());
   }
   ArrayResize(g_orders,0);
}

//+------------------------------------------------------------------+
//| Helpers                                                           |
//+------------------------------------------------------------------+
string ErrorDescription(int code)
{
   // minimal mapping - extend as needed
   switch(code)
   {
      case ERR_NO_ERROR: return("No error");
      case ERR_TRADE_CONTEXT_BUSY: return("Trade context busy");
      case ERR_INVALID_TICKET: return("Invalid ticket");
      default: return("Err=" + IntegerToString(code));
   }
}

//+------------------------------------------------------------------+
//| Current spread in points                                           |
//+------------------------------------------------------------------+
double CurrentSpreadPoints()
{
   double sp = (Ask - Bid) / Point;
   return(sp);
}

//+------------------------------------------------------------------+
