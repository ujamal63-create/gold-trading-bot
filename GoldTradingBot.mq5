#property copyright "gold-trading-bot"
#property version   "4.00"
#property strict
#property description "XAUUSD Williams Fractals trend-continuation scalper for M1 charts. Backtest and demo test before live use."

#include <Trade/Trade.mqh>

CTrade trade;

enum LotSizingMode
{
   LOT_FIXED = 0,
   LOT_RISK_PERCENT = 1
};

input string          InpSymbol                     = "XAUUSD";
input ulong           InpMagicNumber                = 260531;
input int             InpDeviationPoints            = 30;
input LotSizingMode   InpLotMode                    = LOT_RISK_PERCENT;
input double          InpFixedLot                   = 0.01;
input double          InpRiskPercent                = 0.50;
input double          InpMaxLot                     = 5.00;

input int             InpM5EMA200Period             = 200;
input int             InpM1EMA50Period              = 50;
input int             InpRSIPeriod                  = 14;
input double          InpRSIBuyMin                  = 45.0;
input double          InpRSIBuyMax                  = 70.0;
input double          InpRSISellMin                 = 30.0;
input double          InpRSISellMax                 = 55.0;
input int             InpADXPeriod                  = 14;
input double          InpMinADX                     = 20.0;
input int             InpATRPeriod                  = 14;
input double          InpMinATR                     = 0.30;
input double          InpATRStopBuffer              = 0.50;
input double          InpMinSLPoints                = 100.0;
input double          InpMaxSLPoints                = 1500.0;
input double          InpMaxSpreadPoints            = 60.0;
input double          InpMinEMA200DistanceATR       = 0.25;

input int             InpMaxTradesPerDay            = 20;
input int             InpMinMinutesBetweenTrades    = 3;
input bool            InpEnablePyramiding           = false;
input double          InpDailyLossLimitPercent      = 3.0;
input double          InpDailyProfitTargetPercent   = 5.0;
input int             InpLondonStartHHMM            = 700;
input int             InpLondonEndHHMM              = 1200;
input int             InpNewYorkStartHHMM           = 1230;
input int             InpNewYorkEndHHMM             = 1700;
input bool            InpAllowAsianHighVolatility   = false;
input int             InpAsianStartHHMM             = 0;
input int             InpAsianEndHHMM               = 600;
input double          InpAsianMinATRMultiplier      = 1.75;

input bool            InpEnableM15StructureFilter   = true;
input int             InpM15StructureLookback       = 48;
input double          InpM15StructureBufferATR      = 0.75;
input bool            InpEnableNewsFilter           = false;
input string          InpNewsCurrency               = "USD";
input int             InpNewsBlockMinutes           = 5;

input double          InpFinalTakeProfitRR          = 1.50;
input bool            InpEnableTP1PartialClose      = true;
input double          InpTP1ClosePercent            = 50.0;
input bool            InpEnableBreakeven            = true;
input bool            InpEnableTrailingStop         = true;
input double          InpTrailingATRMultiplier      = 0.75;
input bool            InpCloseOnOppositeFractal     = false;

int fractalsM1Handle = INVALID_HANDLE;
int emaM5Handle      = INVALID_HANDLE;
int emaM1Handle      = INVALID_HANDLE;
int rsiM1Handle      = INVALID_HANDLE;
int atrM1Handle      = INVALID_HANDLE;
int adxM5Handle      = INVALID_HANDLE;

datetime lastBullishFractalTime = 0;
datetime lastBearishFractalTime = 0;
datetime consumedBuySignalTime  = 0;
datetime consumedSellSignalTime = 0;
datetime lastEntryTime          = 0;
datetime currentDayStart        = 0;
double   dayStartBalance        = 0.0;
double   latestBullishLow       = 0.0;
double   latestBearishHigh      = 0.0;

bool ReadBufferValue(const int handle, const int buffer, const int shift, double &value)
{
   double values[1];
   if(CopyBuffer(handle, buffer, shift, 1, values) != 1)
      return false;
   value = values[0];
   return (value != EMPTY_VALUE);
}

datetime DayStart(const datetime when)
{
   MqlDateTime parts;
   TimeToStruct(when, parts);
   parts.hour = 0;
   parts.min = 0;
   parts.sec = 0;
   return StructToTime(parts);
}

void RefreshDayState()
{
   datetime start = DayStart(TimeCurrent());
   if(start != currentDayStart)
   {
      currentDayStart = start;
      dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   }
}

bool IsOurPosition(const ulong ticket)
{
   return PositionSelectByTicket(ticket)
          && PositionGetString(POSITION_SYMBOL) == InpSymbol
          && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber;
}

int CountOurPositions(const ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(IsOurPosition(ticket) && (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type)
         ++count;
   }
   return count;
}

double FloatingProfit()
{
   double result = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(IsOurPosition(ticket))
         result += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return result;
}

int TradesToday()
{
   if(!HistorySelect(currentDayStart, TimeCurrent()))
      return 0;
   int count = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) == InpSymbol
         && (ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber
         && (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
         ++count;
   }
   return count;
}

double RealizedProfitToday()
{
   if(!HistorySelect(currentDayStart, TimeCurrent()))
      return 0.0;
   double result = 0.0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) == InpSymbol
         && (ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber)
         result += HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   }
   return result;
}

bool IsTimeInside(const int hhmm, const int startHHMM, const int endHHMM)
{
   if(startHHMM <= endHHMM)
      return hhmm >= startHHMM && hhmm <= endHHMM;
   return hhmm >= startHHMM || hhmm <= endHHMM;
}

bool IsTradingSession(const double atr)
{
   MqlDateTime parts;
   TimeToStruct(TimeCurrent(), parts);
   int hhmm = parts.hour * 100 + parts.min;
   if(IsTimeInside(hhmm, InpLondonStartHHMM, InpLondonEndHHMM) || IsTimeInside(hhmm, InpNewYorkStartHHMM, InpNewYorkEndHHMM))
      return true;
   return InpAllowAsianHighVolatility
          && IsTimeInside(hhmm, InpAsianStartHHMM, InpAsianEndHHMM)
          && atr >= InpMinATR * InpAsianMinATRMultiplier;
}

bool IsNearHighImpactNews()
{
   if(!InpEnableNewsFilter)
      return false;
   datetime now = TimeTradeServer();
   MqlCalendarValue values[];
   int found = CalendarValueHistory(values, now - InpNewsBlockMinutes * 60, now + InpNewsBlockMinutes * 60, NULL, InpNewsCurrency);
   if(found < 0)
   {
      Print("CalendarValueHistory failed. Error=", GetLastError(), ". News filter blocks trading for safety.");
      return true;
   }
   for(int i = 0; i < found; ++i)
   {
      MqlCalendarEvent event;
      if(CalendarEventById(values[i].event_id, event) && event.importance == CALENDAR_IMPORTANCE_HIGH)
         return true;
   }
   return false;
}

void RefreshConfirmedFractals()
{
   // Williams Fractals require two bars to the right. Scanning starts at shift 2, so only confirmed values are used.
   for(int shift = 2; shift <= 100; ++shift)
   {
      double value = 0.0;
      if(ReadBufferValue(fractalsM1Handle, 1, shift, value) && value > 0.0)
      {
         datetime time = iTime(InpSymbol, PERIOD_M1, shift);
         if(time > lastBullishFractalTime)
         {
            lastBullishFractalTime = time;
            latestBullishLow = value;
         }
         break;
      }
   }
   for(int shift = 2; shift <= 100; ++shift)
   {
      double value = 0.0;
      if(ReadBufferValue(fractalsM1Handle, 0, shift, value) && value > 0.0)
      {
         datetime time = iTime(InpSymbol, PERIOD_M1, shift);
         if(time > lastBearishFractalTime)
         {
            lastBearishFractalTime = time;
            latestBearishHigh = value;
         }
         break;
      }
   }
}

bool PassesM15StructureFilter(const bool isBuy, const double price, const double atr)
{
   if(!InpEnableM15StructureFilter)
      return true;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(InpSymbol, PERIOD_M15, 1, InpM15StructureLookback, rates);
   if(copied < 5)
      return false;
   double support = rates[0].low;
   double resistance = rates[0].high;
   for(int i = 1; i < copied; ++i)
   {
      support = MathMin(support, rates[i].low);
      resistance = MathMax(resistance, rates[i].high);
   }
   double buffer = atr * InpM15StructureBufferATR;
   return isBuy ? (resistance - price > buffer) : (price - support > buffer);
}

double NormalizeVolume(double volume)
{
   double minimum = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MIN);
   double maximum = MathMin(SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MAX), InpMaxLot);
   double step = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      return 0.0;
   volume = MathFloor(volume / step) * step;
   volume = MathMax(minimum, MathMin(maximum, volume));
   return NormalizeDouble(volume, 2);
}

double CalculateVolume(const double entry, const double stop)
{
   if(InpLotMode == LOT_FIXED)
      return NormalizeVolume(InpFixedLot);
   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   double tickSize = SymbolInfoDouble(InpSymbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(InpSymbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0.0)
      tickValue = SymbolInfoDouble(InpSymbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0 || MathAbs(entry - stop) <= 0.0)
      return 0.0;
   return NormalizeVolume(riskMoney / (MathAbs(entry - stop) / tickSize * tickValue));
}

bool DailyLimitsAllowTrading()
{
   double profit = RealizedProfitToday() + FloatingProfit();
   if(dayStartBalance <= 0.0)
      return false;
   return profit > -dayStartBalance * InpDailyLossLimitPercent / 100.0
          && profit < dayStartBalance * InpDailyProfitTargetPercent / 100.0;
}

bool ModifyPosition(const ulong ticket, const double sl, const double tp)
{
   if(trade.PositionModify(ticket, sl, tp))
      return true;
   Print("PositionModify failed ticket=", ticket, " retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   return false;
}

void ManageOpenPositions(const double atr)
{
   RefreshConfirmedFractals();
   MqlTick tick;
   if(!SymbolInfoTick(InpSymbol, tick))
      return;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket))
         continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double price = type == POSITION_TYPE_BUY ? tick.bid : tick.ask;
      double initialRisk = InpFinalTakeProfitRR > 0.0 ? MathAbs(tp - open) / InpFinalTakeProfitRR : MathAbs(open - sl);
      if(initialRisk <= 0.0)
         continue;
      double move = type == POSITION_TYPE_BUY ? price - open : open - price;
      string tp1Key = "GFS_TP1_" + IntegerToString((long)ticket);
      if(InpEnableTP1PartialClose && move >= initialRisk && !GlobalVariableCheck(tp1Key))
      {
         double closeVolume = NormalizeVolume(PositionGetDouble(POSITION_VOLUME) * InpTP1ClosePercent / 100.0);
         double minVolume = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MIN);
         if(closeVolume >= minVolume && PositionGetDouble(POSITION_VOLUME) - closeVolume >= minVolume)
         {
            if(!trade.PositionClosePartial(ticket, closeVolume))
               Print("TP1 partial close failed ticket=", ticket, " retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
         }
         GlobalVariableSet(tp1Key, 1.0);
      }
      if(move >= initialRisk)
      {
         double nextSL = sl;
         if(InpEnableBreakeven)
            nextSL = type == POSITION_TYPE_BUY ? MathMax(nextSL, open) : (sl == 0.0 ? open : MathMin(nextSL, open));
         if(InpEnableTrailingStop)
         {
            double trail = type == POSITION_TYPE_BUY ? price - atr * InpTrailingATRMultiplier : price + atr * InpTrailingATRMultiplier;
            nextSL = type == POSITION_TYPE_BUY ? MathMax(nextSL, trail) : MathMin(nextSL, trail);
         }
         if(MathAbs(nextSL - sl) >= SymbolInfoDouble(InpSymbol, SYMBOL_POINT))
            ModifyPosition(ticket, nextSL, tp);
      }
      bool opposite = (type == POSITION_TYPE_BUY && lastBearishFractalTime > (datetime)PositionGetInteger(POSITION_TIME))
                      || (type == POSITION_TYPE_SELL && lastBullishFractalTime > (datetime)PositionGetInteger(POSITION_TIME));
      if(InpCloseOnOppositeFractal && opposite && !trade.PositionClose(ticket))
         Print("Opposite-fractal close failed ticket=", ticket, " retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
}

bool OpenTrade(const bool isBuy, const double atr)
{
   MqlTick tick;
   if(!SymbolInfoTick(InpSymbol, tick))
      return false;
   double point = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   double entry = isBuy ? tick.ask : tick.bid;
   double rawSL = isBuy ? latestBullishLow - atr * InpATRStopBuffer : latestBearishHigh + atr * InpATRStopBuffer;
   double stopPoints = MathAbs(entry - rawSL) / point;
   if(stopPoints > InpMaxSLPoints)
      return false;
   stopPoints = MathMax(stopPoints, InpMinSLPoints);
   double sl = isBuy ? entry - stopPoints * point : entry + stopPoints * point;
   double tp = isBuy ? entry + stopPoints * point * InpFinalTakeProfitRR : entry - stopPoints * point * InpFinalTakeProfitRR;
   double volume = CalculateVolume(entry, sl);
   if(volume <= 0.0)
      return false;
   bool sent = isBuy ? trade.Buy(volume, InpSymbol, 0.0, sl, tp, "Fractal continuation buy")
                     : trade.Sell(volume, InpSymbol, 0.0, sl, tp, "Fractal continuation sell");
   if(!sent)
   {
      Print("Order failed: ", isBuy ? "BUY" : "SELL", " retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription(), " error=", GetLastError());
      return false;
   }
   lastEntryTime = TimeCurrent();
   Print(isBuy ? "BUY opened" : "SELL opened", " lot=", volume, " entry=", entry, " sl=", sl, " tp=", tp);
   return true;
}

void UpdateChartComment(const double spread, const double adx, const double rsi, const double atr, const double m5Close, const double emaM5)
{
   string trend = m5Close > emaM5 ? "BULLISH" : (m5Close < emaM5 ? "BEARISH" : "NEUTRAL");
   Comment("XAUUSD Fractal Continuation Scalper\n",
           "Trend M5: ", trend, "\n",
           "Last bullish fractal low: ", DoubleToString(latestBullishLow, _Digits), "\n",
           "Last bearish fractal high: ", DoubleToString(latestBearishHigh, _Digits), "\n",
           "Spread: ", DoubleToString(spread, 1), " points\n",
           "ADX M5: ", DoubleToString(adx, 2), "\n",
           "RSI M1: ", DoubleToString(rsi, 2), "\n",
           "ATR M1: ", DoubleToString(atr, _Digits), "\n",
           "Trades today: ", TradesToday(), "/", InpMaxTradesPerDay, "\n",
           "Daily P/L: ", DoubleToString(RealizedProfitToday() + FloatingProfit(), 2));
}

int OnInit()
{
   if(!SymbolSelect(InpSymbol, true))
      return INIT_FAILED;
   fractalsM1Handle = iFractals(InpSymbol, PERIOD_M1);
   emaM5Handle = iMA(InpSymbol, PERIOD_M5, InpM5EMA200Period, 0, MODE_EMA, PRICE_CLOSE);
   emaM1Handle = iMA(InpSymbol, PERIOD_M1, InpM1EMA50Period, 0, MODE_EMA, PRICE_CLOSE);
   rsiM1Handle = iRSI(InpSymbol, PERIOD_M1, InpRSIPeriod, PRICE_CLOSE);
   atrM1Handle = iATR(InpSymbol, PERIOD_M1, InpATRPeriod);
   adxM5Handle = iADX(InpSymbol, PERIOD_M5, InpADXPeriod);
   if(fractalsM1Handle == INVALID_HANDLE || emaM5Handle == INVALID_HANDLE || emaM1Handle == INVALID_HANDLE
      || rsiM1Handle == INVALID_HANDLE || atrM1Handle == INVALID_HANDLE || adxM5Handle == INVALID_HANDLE)
   {
      Print("Indicator handle initialization failed. Error=", GetLastError());
      return INIT_FAILED;
   }
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(InpSymbol);
   RefreshDayState();
   RefreshConfirmedFractals();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(fractalsM1Handle);
   IndicatorRelease(emaM5Handle);
   IndicatorRelease(emaM1Handle);
   IndicatorRelease(rsiM1Handle);
   IndicatorRelease(atrM1Handle);
   IndicatorRelease(adxM5Handle);
   Comment("");
}

void OnTick()
{
   RefreshDayState();
   RefreshConfirmedFractals();
   double emaM5, emaM1, rsi, atr, adx;
   if(!ReadBufferValue(emaM5Handle, 0, 1, emaM5) || !ReadBufferValue(emaM1Handle, 0, 1, emaM1)
      || !ReadBufferValue(rsiM1Handle, 0, 1, rsi) || !ReadBufferValue(atrM1Handle, 0, 1, atr)
      || !ReadBufferValue(adxM5Handle, 0, 1, adx))
      return;
   ManageOpenPositions(atr);
   MqlTick tick;
   if(!SymbolInfoTick(InpSymbol, tick))
      return;
   double point = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   double spread = (tick.ask - tick.bid) / point;
   double m5Close = iClose(InpSymbol, PERIOD_M5, 1);
   double m1Close = iClose(InpSymbol, PERIOD_M1, 1);
   UpdateChartComment(spread, adx, rsi, atr, m5Close, emaM5);
   if(spread > InpMaxSpreadPoints || atr < InpMinATR || adx < InpMinADX || !IsTradingSession(atr)
      || !DailyLimitsAllowTrading() || TradesToday() >= InpMaxTradesPerDay || IsNearHighImpactNews())
      return;
   if(lastEntryTime > 0 && TimeCurrent() - lastEntryTime < InpMinMinutesBetweenTrades * 60)
      return;
   if(MathAbs(m5Close - emaM5) < atr * InpMinEMA200DistanceATR || latestBullishLow <= 0.0 || latestBearishHigh <= 0.0)
      return;
   bool canBuy = m5Close > emaM5 && m1Close > emaM1 && rsi >= InpRSIBuyMin && rsi <= InpRSIBuyMax
                 && tick.ask > latestBearishHigh && lastBullishFractalTime > consumedBuySignalTime
                 && CountOurPositions(POSITION_TYPE_SELL) == 0
                 && (InpEnablePyramiding || CountOurPositions(POSITION_TYPE_BUY) == 0)
                 && PassesM15StructureFilter(true, tick.ask, atr);
   bool canSell = m5Close < emaM5 && m1Close < emaM1 && rsi >= InpRSISellMin && rsi <= InpRSISellMax
                  && tick.bid < latestBullishLow && lastBearishFractalTime > consumedSellSignalTime
                  && CountOurPositions(POSITION_TYPE_BUY) == 0
                  && (InpEnablePyramiding || CountOurPositions(POSITION_TYPE_SELL) == 0)
                  && PassesM15StructureFilter(false, tick.bid, atr);
   if(canBuy && OpenTrade(true, atr))
      consumedBuySignalTime = lastBullishFractalTime;
   else if(canSell && OpenTrade(false, atr))
      consumedSellSignalTime = lastBearishFractalTime;
}
