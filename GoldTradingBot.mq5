#property copyright "gold-trading-bot"
#property version   "5.10"
#property strict
#property description "XAUUSD M1 stop-grid breakout Expert Advisor. Backtest and demo test before live use. Choppy markets can trigger both sides and create drawdown."

#include <Trade/Trade.mqh>

CTrade trade;

enum LotStepMode
{
   Fixed = 0,
   CustomArray = 1,
   Multiplier = 2
};

input string          InpSymbol                              = "XAUUSD";
input ulong           InpMagicNumber                         = 260531;
input double          InpBaseLot                             = 0.01;
input LotStepMode     InpLotStepMode                         = CustomArray;
input string          InpCustomLots                          = "0.01,0.03,0.05,0.07,0.10";
input double          InpMultiplier                          = 1.4;
input double          InpGridSpacingDollars                  = 2.0;
input int             InpGridLevels                          = 5;
input int             InpPendingOrderExpiryMinutes           = 0;
input bool            InpDeleteOppositePendingsAfterTrigger  = true;
input int             InpMaxSpreadPoints                     = 80;
input int             InpSlippagePoints                      = 30;
input double          InpStopLossDollars                     = 0.0;
input double          InpTakeProfitDollars                   = 0.0;
input bool            InpUseBasketTP                         = true;
input double          InpBasketProfitMoney                   = 25.0;
input bool            InpUseBasketSL                         = true;
input double          InpBasketLossMoney                     = 50.0;
input bool            InpUseBasketTrailing                   = true;
input double          InpBasketTrailStartMoney               = 15.0;
input double          InpBasketTrailDistanceMoney            = 8.0;
input bool            InpUseTrailingStop                     = true;
input double          InpTrailingStartDollars                = 3.0;
input double          InpTrailingDistanceDollars             = 2.0;
input bool            InpUseBreakEven                        = true;
input double          InpBreakEvenStartDollars               = 2.0;
input double          InpBreakEvenLockDollars                = 0.2;
input int             InpMaxOpenTrades                       = 10;
input int             InpMaxPendingOrders                    = 10;
input double          InpMaxDailyLossMoney                   = 100.0;
input double          InpMaxDailyProfitMoney                 = 100.0;
input bool            InpCloseTradesOnDailyLoss              = true;
input int             InpTradingStartHour                    = 0;
input int             InpTradingEndHour                      = 24;
input bool            InpAvoidRollover                       = true;
input int             InpRolloverStartHour                   = 23;
input int             InpRolloverEndHour                     = 1;
input int             InpFridayCloseHour                     = 20;
input bool            InpAllowNewGridAfterBasketClose        = true;

input bool            InpUseTrendFilter                      = true;
input ENUM_TIMEFRAMES InpTrendTimeframe                      = PERIOD_M5;
input int             InpTrendEMAPeriod                      = 200;
input bool            InpUseATRFilter                        = true;
input ENUM_TIMEFRAMES InpATRTimeframe                        = PERIOD_M5;
input int             InpATRPeriod                           = 14;
input double          InpMinATR                              = 0.60;
input double          InpMaxATR                              = 8.00;
input bool            InpUseADXFilter                        = true;
input ENUM_TIMEFRAMES InpADXTimeframe                        = PERIOD_M5;
input int             InpADXPeriod                           = 14;
input double          InpMinADX                              = 18.0;
input bool            InpUseChopProtection                   = true;
input int             InpMaxOppositeTriggers                 = 1;
input int             InpChopLookbackMinutes                 = 30;
input int             InpPauseAfterChopMinutes               = 60;

#define MAX_CUSTOM_LOTS 64

double   customLots[MAX_CUSTOM_LOTS];
int      customLotCount       = 0;
datetime lastBarTime          = 0;
datetime currentDayStart      = 0;
bool     basketClosedThisRun  = false;
double   basketPeakProfit     = 0.0;
bool     basketTrailingActive = false;
datetime chopPauseUntil       = 0;

int      trendEmaHandle       = INVALID_HANDLE;
int      atrHandle            = INVALID_HANDLE;
int      adxHandle            = INVALID_HANDLE;

// Converts the configured XAUUSD dollar distance into a broker price distance.
// XAUUSD is quoted in USD per troy ounce, so a 2.00 dollar move is a 2.00 price move.
double DollarsToPriceDistance(const double dollars)
{
   return NormalizeDouble(MathAbs(dollars), (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS));
}

// Normalizes prices to the symbol digit precision.
double NormalizePrice(const double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS));
}

// Reads the latest closed-bar value from an indicator handle buffer.
bool ReadIndicatorValue(const int handle, const int buffer, const int shift, double &value)
{
   if(handle == INVALID_HANDLE)
      return false;

   double values[];
   ArraySetAsSeries(values, true);
   if(CopyBuffer(handle, buffer, shift, 1, values) != 1)
   {
      Print("CopyBuffer failed. Handle=", handle, ", buffer=", buffer, ", error=", GetLastError());
      return false;
   }

   value = values[0];
   return (value != EMPTY_VALUE);
}

// Normalizes a requested lot to broker min/max/step constraints.
double NormalizeLot(const double lot)
{
   double minLot = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_STEP);

   if(step <= 0.0)
      step = 0.01;

   double normalized = MathMax(minLot, MathMin(maxLot, lot));
   normalized = MathFloor((normalized + 1.0e-12) / step) * step;
   int volumeDigits = 0;
   if(step < 1.0)
      volumeDigits = (int)MathCeil(-MathLog10(step));

   return NormalizeDouble(normalized, volumeDigits);
}

// Parses InpCustomLots into the customLots array used by CustomArray mode.
bool ParseCustomLots()
{
   customLotCount = 0;
   string values[];
   int count = StringSplit(InpCustomLots, ',', values);

   for(int i = 0; i < count && customLotCount < MAX_CUSTOM_LOTS; ++i)
   {
      StringTrimLeft(values[i]);
      StringTrimRight(values[i]);
      double lot = StringToDouble(values[i]);
      if(lot > 0.0)
      {
         customLots[customLotCount] = NormalizeLot(lot);
         ++customLotCount;
      }
   }

   if(InpLotStepMode == CustomArray && customLotCount == 0)
   {
      Print("No valid custom lots were parsed from InpCustomLots=", InpCustomLots);
      return false;
   }

   return true;
}

// Returns the lot size for a 1-based grid level according to the selected progression mode.
double GetLotForLevel(const int level)
{
   if(level <= 0)
      return NormalizeLot(InpBaseLot);

   if(InpLotStepMode == CustomArray)
   {
      int index = MathMin(level - 1, customLotCount - 1);
      return NormalizeLot(customLots[index]);
   }

   if(InpLotStepMode == Multiplier)
      return NormalizeLot(InpBaseLot * MathPow(InpMultiplier, level - 1));

   return NormalizeLot(InpBaseLot);
}

// Returns true when the order type is a stop pending order that belongs to this EA.
bool IsOurStopPendingOrder(const ulong ticket)
{
   if(!OrderSelect(ticket))
      return false;

   ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   return OrderGetString(ORDER_SYMBOL) == InpSymbol
          && (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagicNumber
          && (type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP);
}

// Counts open positions for the configured symbol and magic number. Pass WRONG_VALUE to count all directions.
int CountOpenPositions(const ENUM_POSITION_TYPE typeFilter = (ENUM_POSITION_TYPE)WRONG_VALUE)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != InpSymbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(typeFilter == (ENUM_POSITION_TYPE)WRONG_VALUE || type == typeFilter)
         ++count;
   }
   return count;
}

// Counts pending Buy Stop and Sell Stop orders for the configured symbol and magic number.
int CountPendingOrders(const ENUM_ORDER_TYPE typeFilter = (ENUM_ORDER_TYPE)WRONG_VALUE)
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !IsOurStopPendingOrder(ticket))
         continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(typeFilter == (ENUM_ORDER_TYPE)WRONG_VALUE || type == typeFilter)
         ++count;
   }
   return count;
}

// Calculates floating basket P/L for all positions owned by this EA.
double GetBasketProfit()
{
   double profit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != InpSymbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return profit;
}

// Returns realized P/L for this EA since the broker-server day started.
double GetTodayRealizedProfit()
{
   if(!HistorySelect(currentDayStart, TimeCurrent()))
      return 0.0;

   double profit = 0.0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;

      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != InpSymbol)
         continue;
      if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber)
         continue;

      profit += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                + HistoryDealGetDouble(ticket, DEAL_SWAP)
                + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   }
   return profit;
}

// Refreshes day tracking when the broker-server date changes.
void RefreshDayState()
{
   MqlDateTime parts;
   TimeToStruct(TimeCurrent(), parts);
   parts.hour = 0;
   parts.min = 0;
   parts.sec = 0;
   datetime dayStart = StructToTime(parts);

   if(dayStart != currentDayStart)
   {
      currentDayStart = dayStart;
      basketClosedThisRun = false;
      Print("New trading day detected. Daily P/L counters reset at ", TimeToString(currentDayStart));
   }
}

// Returns true if spread is at or below the configured maximum spread.
bool IsSpreadOK()
{
   long spread = SymbolInfoInteger(InpSymbol, SYMBOL_SPREAD);
   if(spread <= InpMaxSpreadPoints)
      return true;

   Print("Spread filter blocked trading. Spread=", spread, " points, max=", InpMaxSpreadPoints);
   return false;
}

// Checks whether the current broker-server hour is inside a possibly wrapping hour window.
bool IsHourInWindow(const int hour, const int startHour, const int endHour)
{
   int start = MathMax(0, MathMin(24, startHour));
   int end   = MathMax(0, MathMin(24, endHour));

   if(start == end)
      return true;
   if(start < end)
      return (hour >= start && hour < end);
   return (hour >= start || hour < end);
}

// Returns true during the configured trading session, excluding the Friday close cutoff.
bool IsTradingTime()
{
   MqlDateTime parts;
   TimeToStruct(TimeCurrent(), parts);

   if(parts.day_of_week == 5 && InpFridayCloseHour >= 0 && parts.hour >= InpFridayCloseHour)
      return false;

   return IsHourInWindow(parts.hour, InpTradingStartHour, InpTradingEndHour);
}


// Returns true after the configured Friday cutoff hour.
bool IsFridayCloseTime()
{
   if(InpFridayCloseHour < 0)
      return false;

   MqlDateTime parts;
   TimeToStruct(TimeCurrent(), parts);
   return (parts.day_of_week == 5 && parts.hour >= InpFridayCloseHour);
}

// Returns true when new grids should be avoided for the configured rollover window.
bool IsRolloverTime()
{
   if(!InpAvoidRollover)
      return false;

   MqlDateTime parts;
   TimeToStruct(TimeCurrent(), parts);
   return IsHourInWindow(parts.hour, InpRolloverStartHour, InpRolloverEndHour);
}

// Returns true when daily realized plus floating P/L has reached a stop or profit target.
bool IsDailyLimitReached()
{
   double todayProfit = GetTodayRealizedProfit() + GetBasketProfit();

   if(InpMaxDailyLossMoney > 0.0 && todayProfit <= -MathAbs(InpMaxDailyLossMoney))
   {
      Print("Daily loss limit reached. Daily P/L=", DoubleToString(todayProfit, 2));
      return true;
   }

   if(InpMaxDailyProfitMoney > 0.0 && todayProfit >= MathAbs(InpMaxDailyProfitMoney))
   {
      Print("Daily profit target reached. Daily P/L=", DoubleToString(todayProfit, 2));
      return true;
   }

   return false;
}

// Checks the EMA trend filter for a specific pending order side.
bool IsTrendOK(const ENUM_ORDER_TYPE orderType)
{
   if(!InpUseTrendFilter)
      return true;

   double ema = 0.0;
   if(!ReadIndicatorValue(trendEmaHandle, 0, 1, ema))
   {
      Print("Trend filter blocked trading because EMA data is unavailable.");
      return false;
   }

   MqlTick tick;
   if(!SymbolInfoTick(InpSymbol, tick))
      return false;

   if(orderType == ORDER_TYPE_BUY_STOP)
   {
      bool ok = (tick.ask > ema);
      if(!ok)
         Print("Trend filter blocked Buy Stop grid. Ask=", tick.ask, ", EMA=", ema);
      return ok;
   }

   if(orderType == ORDER_TYPE_SELL_STOP)
   {
      bool ok = (tick.bid < ema);
      if(!ok)
         Print("Trend filter blocked Sell Stop grid. Bid=", tick.bid, ", EMA=", ema);
      return ok;
   }

   return false;
}

// Required no-argument trend helper; true means at least one grid side is aligned with EMA.
bool IsTrendOK()
{
   return IsTrendOK(ORDER_TYPE_BUY_STOP) || IsTrendOK(ORDER_TYPE_SELL_STOP);
}

// Checks ATR regime: too-low ATR suggests chop, too-high ATR suggests spike/news/slippage risk.
bool IsATROK()
{
   if(!InpUseATRFilter)
      return true;

   double atr = 0.0;
   if(!ReadIndicatorValue(atrHandle, 0, 1, atr))
   {
      Print("ATR filter blocked trading because ATR data is unavailable.");
      return false;
   }

   if(InpMinATR > 0.0 && atr < InpMinATR)
   {
      Print("ATR filter blocked trading. ATR=", DoubleToString(atr, 3), " below minimum=", DoubleToString(InpMinATR, 3));
      return false;
   }

   if(InpMaxATR > 0.0 && atr > InpMaxATR)
   {
      Print("ATR filter blocked trading. ATR=", DoubleToString(atr, 3), " above maximum=", DoubleToString(InpMaxATR, 3));
      return false;
   }

   return true;
}

// Checks ADX trend-strength filter before a new grid is opened.
bool IsADXOK()
{
   if(!InpUseADXFilter)
      return true;

   double adx = 0.0;
   if(!ReadIndicatorValue(adxHandle, 0, 1, adx))
   {
      Print("ADX filter blocked trading because ADX data is unavailable.");
      return false;
   }

   if(adx < InpMinADX)
   {
      Print("ADX filter blocked trading. ADX=", DoubleToString(adx, 2), " below minimum=", DoubleToString(InpMinADX, 2));
      return false;
   }

   return true;
}

// Detects recent two-sided stop-grid triggers and pauses new grids after whipsaw behavior.
bool IsChoppyMarket()
{
   if(!InpUseChopProtection)
      return false;

   datetime now = TimeCurrent();
   if(chopPauseUntil > now)
   {
      Print("Chop protection pause is active until ", TimeToString(chopPauseUntil));
      return true;
   }

   if(InpChopLookbackMinutes <= 0 || InpMaxOppositeTriggers <= 0)
      return false;

   datetime fromTime = now - InpChopLookbackMinutes * 60;
   if(!HistorySelect(fromTime, now))
      return false;

   int buyTriggers = 0;
   int sellTriggers = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != InpSymbol)
         continue;
      if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber)
         continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;

      ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(dealType == DEAL_TYPE_BUY)
         ++buyTriggers;
      else if(dealType == DEAL_TYPE_SELL)
         ++sellTriggers;
   }

   int oppositeTriggers = MathMin(buyTriggers, sellTriggers);
   if(oppositeTriggers >= InpMaxOppositeTriggers)
   {
      chopPauseUntil = now + InpPauseAfterChopMinutes * 60;
      Print("Chop protection detected two-sided triggers. Buys=", buyTriggers, ", sells=", sellTriggers, ", pausing new grids until ", TimeToString(chopPauseUntil));
      return true;
   }

   return false;
}

// Checks whether a pending order already exists at a level to avoid duplicate grid orders.
bool PendingOrderExists(const ENUM_ORDER_TYPE type, const double price)
{
   double point = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   double tolerance = MathMax(point * 0.5, 0.0000001);

   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !IsOurStopPendingOrder(ticket))
         continue;

      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != type)
         continue;

      if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - price) <= tolerance)
         return true;
   }
   return false;
}

// Deletes all pending stop orders for this EA in the requested direction.
void DeleteOppositePendingOrders(const ENUM_POSITION_TYPE triggeredDirection)
{
   ENUM_ORDER_TYPE oppositeType = (triggeredDirection == POSITION_TYPE_BUY ? ORDER_TYPE_SELL_STOP : ORDER_TYPE_BUY_STOP);

   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !IsOurStopPendingOrder(ticket))
         continue;

      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != oppositeType)
         continue;

      trade.SetExpertMagicNumber(InpMagicNumber);
      if(trade.OrderDelete(ticket))
         Print("Deleted opposite pending order #", ticket);
      else
         Print("Failed to delete opposite pending order #", ticket, ". Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
}

// Deletes every pending stop order owned by this EA.
void DeleteAllPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !IsOurStopPendingOrder(ticket))
         continue;

      trade.SetExpertMagicNumber(InpMagicNumber);
      if(trade.OrderDelete(ticket))
         Print("Deleted pending order #", ticket);
      else
         Print("Failed to delete pending order #", ticket, ". Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
}

// Closes all positions owned by this EA without touching manual or other-EA trades.
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != InpSymbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      trade.SetExpertMagicNumber(InpMagicNumber);
      trade.SetDeviationInPoints(InpSlippagePoints);
      if(trade.PositionClose(ticket, InpSlippagePoints))
         Print("Closed position #", ticket);
      else
         Print("Failed to close position #", ticket, ". Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
}

// Builds a new symmetrical Buy Stop / Sell Stop grid above Ask and below Bid.
void PlaceGrid()
{
   if(!IsSpreadOK() || !IsTradingTime() || IsRolloverTime() || IsDailyLimitReached() || !IsATROK() || !IsADXOK() || IsChoppyMarket())
      return;

   int openCount = CountOpenPositions();
   int pendingCount = CountPendingOrders();

   if(openCount > 0 || pendingCount > 0)
      return;

   if(InpMaxPendingOrders <= 0 || InpGridLevels <= 0)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(InpSymbol, tick))
   {
      Print("SymbolInfoTick failed for ", InpSymbol, ". Error=", GetLastError());
      return;
   }

   double spacing = DollarsToPriceDistance(InpGridSpacingDollars);
   if(spacing <= 0.0)
   {
      Print("Grid spacing must be greater than zero.");
      return;
   }

   long stopsLevelPoints = SymbolInfoInteger(InpSymbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStopDistance = stopsLevelPoints * SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   if(spacing < minStopDistance)
      Print("Configured spacing is below broker stops level. Spacing=", spacing, ", minimum=", minStopDistance);

   datetime expiration = 0;
   ENUM_ORDER_TYPE_TIME typeTime = ORDER_TIME_GTC;
   if(InpPendingOrderExpiryMinutes > 0)
   {
      typeTime = ORDER_TIME_SPECIFIED;
      expiration = TimeCurrent() + InpPendingOrderExpiryMinutes * 60;
   }

   bool allowBuyGrid = IsTrendOK(ORDER_TYPE_BUY_STOP);
   bool allowSellGrid = IsTrendOK(ORDER_TYPE_SELL_STOP);
   if(!allowBuyGrid && !allowSellGrid)
   {
      Print("Trend filter blocked both grid sides. No grid placed.");
      return;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);

   int ordersPlaced = 0;
   for(int level = 1; level <= InpGridLevels; ++level)
   {
      if(CountPendingOrders() >= InpMaxPendingOrders)
      {
         Print("Max pending order limit reached while placing grid. Limit=", InpMaxPendingOrders);
         break;
      }

      double lot = GetLotForLevel(level);
      double buyPrice = NormalizePrice(tick.ask + spacing * level);
      double sellPrice = NormalizePrice(tick.bid - spacing * level);
      double buySL = 0.0, buyTP = 0.0, sellSL = 0.0, sellTP = 0.0;

      if(InpStopLossDollars > 0.0)
      {
         double slDistance = DollarsToPriceDistance(InpStopLossDollars);
         buySL = NormalizePrice(buyPrice - slDistance);
         sellSL = NormalizePrice(sellPrice + slDistance);
      }
      if(InpTakeProfitDollars > 0.0)
      {
         double tpDistance = DollarsToPriceDistance(InpTakeProfitDollars);
         buyTP = NormalizePrice(buyPrice + tpDistance);
         sellTP = NormalizePrice(sellPrice - tpDistance);
      }

      if(allowBuyGrid && CountPendingOrders() < InpMaxPendingOrders && !PendingOrderExists(ORDER_TYPE_BUY_STOP, buyPrice))
      {
         if(trade.BuyStop(lot, buyPrice, InpSymbol, buySL, buyTP, typeTime, expiration, "StopGrid Buy L" + IntegerToString(level)))
         {
            ++ordersPlaced;
            Print("Placed Buy Stop L", level, " at ", DoubleToString(buyPrice, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS)), " lot ", DoubleToString(lot, 2));
         }
         else
            Print("Failed to place Buy Stop L", level, ". Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      }

      if(CountPendingOrders() >= InpMaxPendingOrders)
      {
         Print("Max pending order limit reached after buy side placement. Limit=", InpMaxPendingOrders);
         break;
      }

      if(allowSellGrid && !PendingOrderExists(ORDER_TYPE_SELL_STOP, sellPrice))
      {
         if(trade.SellStop(lot, sellPrice, InpSymbol, sellSL, sellTP, typeTime, expiration, "StopGrid Sell L" + IntegerToString(level)))
         {
            ++ordersPlaced;
            Print("Placed Sell Stop L", level, " at ", DoubleToString(sellPrice, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS)), " lot ", DoubleToString(lot, 2));
         }
         else
            Print("Failed to place Sell Stop L", level, ". Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      }
   }

   Print("Grid placement complete. Orders placed=", ordersPlaced);
}

// Moves profitable positions to breakeven plus a configurable lock distance.
void ManageBreakEven()
{
   if(!InpUseBreakEven)
      return;

   double startDistance = DollarsToPriceDistance(InpBreakEvenStartDollars);
   double lockDistance  = DollarsToPriceDistance(InpBreakEvenLockDollars);
   if(startDistance <= 0.0)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(InpSymbol, tick))
      return;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSymbol || (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double newSL = 0.0;

      if(type == POSITION_TYPE_BUY && tick.bid - openPrice >= startDistance)
      {
         newSL = NormalizePrice(openPrice + lockDistance);
         if(sl == 0.0 || newSL > sl)
         {
            if(trade.PositionModify(ticket, newSL, tp))
               Print("Moved buy position #", ticket, " to breakeven SL=", newSL);
            else
               Print("Failed breakeven modify for buy position #", ticket, ". Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
         }
      }
      else if(type == POSITION_TYPE_SELL && openPrice - tick.ask >= startDistance)
      {
         newSL = NormalizePrice(openPrice - lockDistance);
         if(sl == 0.0 || newSL < sl)
         {
            if(trade.PositionModify(ticket, newSL, tp))
               Print("Moved sell position #", ticket, " to breakeven SL=", newSL);
            else
               Print("Failed breakeven modify for sell position #", ticket, ". Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
         }
      }
   }
}

// Applies a price-distance trailing stop after positions move into profit by InpTrailingStartDollars.
void ManageTrailingStop()
{
   if(!InpUseTrailingStop)
      return;

   double startDistance = DollarsToPriceDistance(InpTrailingStartDollars);
   double trailDistance = DollarsToPriceDistance(InpTrailingDistanceDollars);
   if(startDistance <= 0.0 || trailDistance <= 0.0)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(InpSymbol, tick))
      return;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSymbol || (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double newSL = 0.0;

      if(type == POSITION_TYPE_BUY && tick.bid - openPrice >= startDistance)
      {
         newSL = NormalizePrice(tick.bid - trailDistance);
         if(newSL > openPrice && (sl == 0.0 || newSL > sl))
         {
            if(trade.PositionModify(ticket, newSL, tp))
               Print("Trailed buy position #", ticket, " to SL=", newSL);
            else
               Print("Failed trailing modify for buy position #", ticket, ". Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
         }
      }
      else if(type == POSITION_TYPE_SELL && openPrice - tick.ask >= startDistance)
      {
         newSL = NormalizePrice(tick.ask + trailDistance);
         if(newSL < openPrice && (sl == 0.0 || newSL < sl))
         {
            if(trade.PositionModify(ticket, newSL, tp))
               Print("Trailed sell position #", ticket, " to SL=", newSL);
            else
               Print("Failed trailing modify for sell position #", ticket, ". Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
         }
      }
   }
}

// Trails total basket profit after the basket reaches a configurable money threshold.
void ManageBasketTrailing()
{
   if(!InpUseBasketTrailing)
   {
      basketTrailingActive = false;
      basketPeakProfit = 0.0;
      return;
   }

   if(CountOpenPositions() == 0)
   {
      basketTrailingActive = false;
      basketPeakProfit = 0.0;
      return;
   }

   double basketProfit = GetBasketProfit();
   if(!basketTrailingActive)
   {
      if(InpBasketTrailStartMoney > 0.0 && basketProfit >= InpBasketTrailStartMoney)
      {
         basketTrailingActive = true;
         basketPeakProfit = basketProfit;
         Print("Basket trailing activated. Basket P/L=", DoubleToString(basketProfit, 2));
      }
      return;
   }

   if(basketProfit > basketPeakProfit)
      basketPeakProfit = basketProfit;

   if(InpBasketTrailDistanceMoney > 0.0 && basketProfit <= basketPeakProfit - InpBasketTrailDistanceMoney)
   {
      Print("Basket trailing stop hit. Basket P/L=", DoubleToString(basketProfit, 2), ", peak=", DoubleToString(basketPeakProfit, 2));
      CloseAllPositions();
      DeleteAllPendingOrders();
      basketClosedThisRun = true;
      basketTrailingActive = false;
      basketPeakProfit = 0.0;
   }
}

// Enforces basket-level TP/SL and daily limits, then performs position management.
void ManageOpenRisk()
{
   double basketProfit = GetBasketProfit();

   if(IsFridayCloseTime() && (CountOpenPositions() > 0 || CountPendingOrders() > 0))
   {
      Print("Friday close hour reached. Closing EA positions and deleting pending orders.");
      CloseAllPositions();
      DeleteAllPendingOrders();
      return;
   }

   if(InpUseBasketTP && InpBasketProfitMoney > 0.0 && basketProfit >= MathAbs(InpBasketProfitMoney))
   {
      Print("Basket profit target reached. Basket P/L=", DoubleToString(basketProfit, 2));
      CloseAllPositions();
      DeleteAllPendingOrders();
      basketClosedThisRun = true;
      return;
   }

   if(InpUseBasketSL && InpBasketLossMoney > 0.0 && basketProfit <= -MathAbs(InpBasketLossMoney))
   {
      Print("Basket loss limit reached. Basket P/L=", DoubleToString(basketProfit, 2));
      CloseAllPositions();
      DeleteAllPendingOrders();
      basketClosedThisRun = true;
      return;
   }

   ManageBasketTrailing();
   if(CountOpenPositions() == 0 && CountPendingOrders() == 0 && basketClosedThisRun)
      return;

   if(IsDailyLimitReached())
   {
      double dailyProfit = GetTodayRealizedProfit() + GetBasketProfit();
      DeleteAllPendingOrders();
      if(dailyProfit >= MathAbs(InpMaxDailyProfitMoney) || (dailyProfit <= -MathAbs(InpMaxDailyLossMoney) && InpCloseTradesOnDailyLoss))
         CloseAllPositions();
      return;
   }

   if(InpMaxOpenTrades > 0 && CountOpenPositions() >= InpMaxOpenTrades && CountPendingOrders() > 0)
   {
      Print("Max open trade limit reached. Deleting remaining pending orders. Limit=", InpMaxOpenTrades);
      DeleteAllPendingOrders();
   }

   if(InpDeleteOppositePendingsAfterTrigger)
   {
      if(CountOpenPositions(POSITION_TYPE_BUY) > 0)
         DeleteOppositePendingOrders(POSITION_TYPE_BUY);
      if(CountOpenPositions(POSITION_TYPE_SELL) > 0)
         DeleteOppositePendingOrders(POSITION_TYPE_SELL);
   }

   ManageBreakEven();
   ManageTrailingStop();
}

// Returns true when a new M1 bar has formed.
bool IsNewBar()
{
   datetime barTime = iTime(InpSymbol, PERIOD_M1, 0);
   if(barTime == 0)
      return false;

   if(barTime != lastBarTime)
   {
      lastBarTime = barTime;
      return true;
   }
   return false;
}

// Shared processing called by ticks, new bars, and the timer.
void ProcessEA(const bool allowGridCheck)
{
   RefreshDayState();
   ManageOpenRisk();

   if(!allowGridCheck)
      return;

   if(basketClosedThisRun && !InpAllowNewGridAfterBasketClose)
      return;

   if(CountOpenPositions() >= InpMaxOpenTrades)
      return;

   if(CountOpenPositions() == 0 && CountPendingOrders() == 0)
      PlaceGrid();
}

int OnInit()
{
   if(!SymbolSelect(InpSymbol, true))
   {
      Print("Failed to select symbol ", InpSymbol, ". Error=", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);

   RefreshDayState();
   if(!ParseCustomLots())
      return INIT_FAILED;

   if(InpUseTrendFilter)
   {
      trendEmaHandle = iMA(InpSymbol, InpTrendTimeframe, InpTrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(trendEmaHandle == INVALID_HANDLE)
      {
         Print("Failed to create trend EMA handle. Error=", GetLastError());
         return INIT_FAILED;
      }
   }

   if(InpUseATRFilter)
   {
      atrHandle = iATR(InpSymbol, InpATRTimeframe, InpATRPeriod);
      if(atrHandle == INVALID_HANDLE)
      {
         Print("Failed to create ATR handle. Error=", GetLastError());
         return INIT_FAILED;
      }
   }

   if(InpUseADXFilter)
   {
      adxHandle = iADX(InpSymbol, InpADXTimeframe, InpADXPeriod);
      if(adxHandle == INVALID_HANDLE)
      {
         Print("Failed to create ADX handle. Error=", GetLastError());
         return INIT_FAILED;
      }
   }

   lastBarTime = iTime(InpSymbol, PERIOD_M1, 0);
   EventSetTimer(10);

   Print("Stop-grid breakout EA initialized for ", InpSymbol, ". Magic=", InpMagicNumber);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();

   if(trendEmaHandle != INVALID_HANDLE)
      IndicatorRelease(trendEmaHandle);
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
   if(adxHandle != INVALID_HANDLE)
      IndicatorRelease(adxHandle);

   Print("Stop-grid breakout EA deinitialized. Reason=", reason);
}

void OnTick()
{
   ProcessEA(IsNewBar());
}

void OnTimer()
{
   ProcessEA(true);
}
