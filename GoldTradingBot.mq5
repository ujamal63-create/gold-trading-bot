#property copyright "gold-trading-bot"
#property version   "3.00"
#property strict
#property description "Gold Hedged Range Strategy: M15 swing levels, M5 indicator confirmation, M1 trigger execution."

#include <Trade/Trade.mqh>

CTrade trade;

enum LotSizingMode
{
   LOT_FIXED = 0,
   LOT_EQUITY_RISK = 1
};

input string          InpSymbol                   = "XAUUSD";
input ulong           InpMagicNumber              = 260513;
input bool            InpDebugMode                = true;
input bool            InpWriteCsvLog              = true;
input int             InpDeviationPoints          = 30;

input int             InpSwingWindow              = 3;
input int             InpSwingLookbackBars        = 220;
input double          InpSwingLowBufferATR        = 0.35;
input double          InpSwingHighBufferATR       = 0.50;
input double          InpMinATR                   = 1.00;

input int             InpRSIPeriod                = 14;
input double          InpRSIOversold              = 35.0;
input double          InpRSISwingHigh             = 60.0;
input int             InpStochKPeriod             = 5;
input int             InpStochDPeriod             = 3;
input int             InpStochSlowing             = 3;
input int             InpFastEMA                  = 8;
input int             InpSlowEMA                  = 21;
input int             InpATRPeriod                = 14;
input int             InpBandsPeriod              = 20;
input double          InpBandsDeviation           = 2.0;
input double          InpBandTouchBufferATR       = 0.10;
input bool            InpRequireVwapConfluence    = false;
input bool            InpRequireLowerBandTouch    = true;
input bool            InpRequireUpperBandAdd      = false;

input LotSizingMode   InpLotSizingMode            = LOT_FIXED;
input double          InpFixedLot                 = 0.01;
input double          InpRiskPercent              = 0.30;
input double          InpEmergencyStopATR         = 2.0;
input double          InpMaxLot                   = 0.10;
input int             InpMaxSimultaneousPositions = 6;
input int             InpMaxShortAddsPerCycle     = 2;
input int             InpMinSecondsBetweenEntries = 60;
input double          InpMaxSpreadPoints          = 80;
input double          InpNetCloseProfitMoney      = 0.00;
input double          InpLongQuickProfitMoney     = 0.01;
input bool            InpUseSellLimitAtSwingHigh  = false;
input int             InpPendingExpiryMinutes     = 180;

int rsiM5Handle = INVALID_HANDLE;
int stochM5Handle = INVALID_HANDLE;
int fastEmaM5Handle = INVALID_HANDLE;
int slowEmaM5Handle = INVALID_HANDLE;
int atrM15Handle = INVALID_HANDLE;
int bandsM5Handle = INVALID_HANDLE;

datetime lastM1BarTime = 0;
datetime lastM15BarTime = 0;
datetime lastEntryTime = 0;
datetime lastSwingHighAddBar = 0;
datetime lastDecisionLogBar = 0;
string lastDecisionMessage = "";

double lastSwingLow = 0.0;
double lastSwingHigh = 0.0;
datetime lastSwingLowTime = 0;
datetime lastSwingHighTime = 0;
int shortAddsThisCycle = 0;
bool cycleActive = false;

void LogDecision(const string message)
{
   if(!InpDebugMode)
      return;

   datetime bar = iTime(InpSymbol, PERIOD_M1, 0);
   if(message != lastDecisionMessage || bar != lastDecisionLogBar)
   {
      Print(message);
      lastDecisionMessage = message;
      lastDecisionLogBar = bar;
   }
}

void TradeLog(const string eventName,
              const string reason,
              const double price,
              const double volume,
              const double rsi,
              const double stochK,
              const double stochD,
              const double emaFast,
              const double emaSlow,
              const double atr,
              const double vwap,
              const double bandLower,
              const double bandUpper)
{
   string line = StringFormat("%s | %s | %s | price=%.5f lot=%.2f RSI=%.2f StochK=%.2f StochD=%.2f EMA%d=%.5f EMA%d=%.5f ATR=%.5f VWAP=%.5f BB_L=%.5f BB_U=%.5f swingLow=%.5f swingHigh=%.5f",
                              TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), eventName, reason, price, volume,
                              rsi, stochK, stochD, InpFastEMA, emaFast, InpSlowEMA, emaSlow, atr, vwap, bandLower, bandUpper,
                              lastSwingLow, lastSwingHigh);
   Print(line);

   if(!InpWriteCsvLog)
      return;

   int handle = FileOpen("GoldTradingBot_HedgedRange_Log.csv", FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON|FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;

   if(FileSize(handle) == 0)
      FileWrite(handle, "timestamp", "event", "reason", "price", "lot", "rsi", "stoch_k", "stoch_d", "ema_fast", "ema_slow", "atr", "vwap", "bb_lower", "bb_upper", "swing_low", "swing_high");

   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle,
             TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), eventName, reason,
             DoubleToString(price, _Digits), DoubleToString(volume, 2), DoubleToString(rsi, 2), DoubleToString(stochK, 2), DoubleToString(stochD, 2),
             DoubleToString(emaFast, _Digits), DoubleToString(emaSlow, _Digits), DoubleToString(atr, _Digits), DoubleToString(vwap, _Digits),
             DoubleToString(bandLower, _Digits), DoubleToString(bandUpper, _Digits), DoubleToString(lastSwingLow, _Digits), DoubleToString(lastSwingHigh, _Digits));
   FileClose(handle);
}

int OnInit()
{
   if(!SymbolSelect(InpSymbol, true))
   {
      Print("Failed to select symbol ", InpSymbol);
      return INIT_FAILED;
   }

   rsiM5Handle = iRSI(InpSymbol, PERIOD_M5, InpRSIPeriod, PRICE_CLOSE);
   stochM5Handle = iStochastic(InpSymbol, PERIOD_M5, InpStochKPeriod, InpStochDPeriod, InpStochSlowing, MODE_SMA, STO_LOWHIGH);
   fastEmaM5Handle = iMA(InpSymbol, PERIOD_M5, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowEmaM5Handle = iMA(InpSymbol, PERIOD_M5, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   atrM15Handle = iATR(InpSymbol, PERIOD_M15, InpATRPeriod);
   bandsM5Handle = iBands(InpSymbol, PERIOD_M5, InpBandsPeriod, 0, InpBandsDeviation, PRICE_CLOSE);

   if(rsiM5Handle == INVALID_HANDLE || stochM5Handle == INVALID_HANDLE || fastEmaM5Handle == INVALID_HANDLE ||
      slowEmaM5Handle == INVALID_HANDLE || atrM15Handle == INVALID_HANDLE || bandsM5Handle == INVALID_HANDLE)
   {
      Print("Failed to create one or more indicator handles. LastError=", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   RecalculateM15Swings(true);
   Print("GoldTradingBot v3.00 Hedged Range Strategy started for ", InpSymbol, ". Demo/backtest first; no profit guarantee.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(rsiM5Handle != INVALID_HANDLE) IndicatorRelease(rsiM5Handle);
   if(stochM5Handle != INVALID_HANDLE) IndicatorRelease(stochM5Handle);
   if(fastEmaM5Handle != INVALID_HANDLE) IndicatorRelease(fastEmaM5Handle);
   if(slowEmaM5Handle != INVALID_HANDLE) IndicatorRelease(slowEmaM5Handle);
   if(atrM15Handle != INVALID_HANDLE) IndicatorRelease(atrM15Handle);
   if(bandsM5Handle != INVALID_HANDLE) IndicatorRelease(bandsM5Handle);
}

bool CopySeriesValue(const int handle, const int buffer, const int start, const int count, double &values[])
{
   ArraySetAsSeries(values, true);
   return CopyBuffer(handle, buffer, start, count, values) >= count;
}

bool GetIndicatorSnapshot(double &rsi,
                          double &stochK0,
                          double &stochD0,
                          double &stochK1,
                          double &stochD1,
                          double &emaFast0,
                          double &emaFast1,
                          double &emaSlow0,
                          double &emaSlow1,
                          double &atr,
                          double &bandUpper,
                          double &bandLower)
{
   double rsiValues[], stochKValues[], stochDValues[], emaFastValues[], emaSlowValues[], atrValues[], bandUpperValues[], bandLowerValues[];

   if(!CopySeriesValue(rsiM5Handle, 0, 0, 3, rsiValues)) return false;
   if(!CopySeriesValue(stochM5Handle, 0, 0, 3, stochKValues)) return false;
   if(!CopySeriesValue(stochM5Handle, 1, 0, 3, stochDValues)) return false;
   if(!CopySeriesValue(fastEmaM5Handle, 0, 0, 4, emaFastValues)) return false;
   if(!CopySeriesValue(slowEmaM5Handle, 0, 0, 4, emaSlowValues)) return false;
   if(!CopySeriesValue(atrM15Handle, 0, 0, 3, atrValues)) return false;
   if(!CopySeriesValue(bandsM5Handle, 1, 0, 3, bandUpperValues)) return false;
   if(!CopySeriesValue(bandsM5Handle, 2, 0, 3, bandLowerValues)) return false;

   rsi = rsiValues[1];
   stochK0 = stochKValues[1];
   stochD0 = stochDValues[1];
   stochK1 = stochKValues[2];
   stochD1 = stochDValues[2];
   emaFast0 = emaFastValues[1];
   emaFast1 = emaFastValues[2];
   emaSlow0 = emaSlowValues[1];
   emaSlow1 = emaSlowValues[2];
   atr = atrValues[1];
   bandUpper = bandUpperValues[1];
   bandLower = bandLowerValues[1];
   return true;
}

bool IsSwingHigh(const MqlRates &rates[], const int index, const int window)
{
   for(int shift = 1; shift <= window; shift++)
   {
      if(rates[index].high <= rates[index - shift].high || rates[index].high <= rates[index + shift].high)
         return false;
   }
   return true;
}

bool IsSwingLow(const MqlRates &rates[], const int index, const int window)
{
   for(int shift = 1; shift <= window; shift++)
   {
      if(rates[index].low >= rates[index - shift].low || rates[index].low >= rates[index + shift].low)
         return false;
   }
   return true;
}

bool RecalculateM15Swings(const bool force)
{
   datetime m15Bar = iTime(InpSymbol, PERIOD_M15, 0);
   if(m15Bar == 0)
      return false;
   if(!force && m15Bar == lastM15BarTime)
      return true;

   lastM15BarTime = m15Bar;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int barsNeeded = MathMax(InpSwingLookbackBars, InpSwingWindow * 2 + 20);
   int copied = CopyRates(InpSymbol, PERIOD_M15, 0, barsNeeded, rates);
   if(copied < InpSwingWindow * 2 + 10)
      return false;

   bool foundLow = false;
   bool foundHigh = false;
   for(int i = InpSwingWindow + 1; i < copied - InpSwingWindow; i++)
   {
      if(!foundLow && IsSwingLow(rates, i, InpSwingWindow))
      {
         lastSwingLow = rates[i].low;
         lastSwingLowTime = rates[i].time;
         foundLow = true;
      }

      if(!foundHigh && IsSwingHigh(rates, i, InpSwingWindow))
      {
         lastSwingHigh = rates[i].high;
         lastSwingHighTime = rates[i].time;
         foundHigh = true;
      }

      if(foundLow && foundHigh)
         break;
   }

   if(foundLow || foundHigh)
      LogDecision(StringFormat("M15 swings recalculated: low=%.5f high=%.5f", lastSwingLow, lastSwingHigh));

   return foundLow && foundHigh;
}

int CountBotPositions(const long positionType = -1)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSymbol || (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      if(positionType >= 0 && PositionGetInteger(POSITION_TYPE) != positionType)
         continue;
      count++;
   }
   return count;
}

double BotPositionProfit(const long positionType = -1)
{
   double profit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSymbol || (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      if(positionType >= 0 && PositionGetInteger(POSITION_TYPE) != positionType)
         continue;
      profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return profit;
}

bool ClosePositionByTicket(const ulong ticket, const string reason)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   double volume = PositionGetDouble(POSITION_VOLUME);
   double price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(InpSymbol, SYMBOL_BID) : SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
   bool ok = trade.PositionClose(ticket);
   if(ok)
      TradeLog("CLOSE", reason, price, volume, 0, 0, 0, 0, 0, 0, 0, 0, 0);
   else
      Print("Position close failed. ticket=", ticket, " retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   return ok;
}

void CloseProfitableLongs()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSymbol || (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY)
         continue;

      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(profit >= InpLongQuickProfitMoney)
         ClosePositionByTicket(ticket, "long reached quick profit target");
   }
}

void CloseAllBotPositions(const string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSymbol || (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      ClosePositionByTicket(ticket, reason);
   }
}

void ManageNetExit()
{
   int shorts = CountBotPositions(POSITION_TYPE_SELL);
   if(shorts <= 0)
      return;

   double netProfit = BotPositionProfit(-1);
   if(netProfit >= InpNetCloseProfitMoney)
   {
      CloseAllBotPositions("net basket breakeven/profit reached");
      cycleActive = false;
      shortAddsThisCycle = 0;
   }
}

bool IsSpreadOk()
{
   double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   double point = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   if(point <= 0.0)
      return false;

   double spreadPoints = (ask - bid) / point;
   if(spreadPoints > InpMaxSpreadPoints)
   {
      LogDecision(StringFormat("No trade: spread %.1f points exceeds max %.1f", spreadPoints, InpMaxSpreadPoints));
      return false;
   }
   return true;
}

double NormalizeVolume(const double volume)
{
   double minLot = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;

   double clipped = MathMax(minLot, MathMin(MathMin(maxLot, InpMaxLot), volume));
   double normalized = MathFloor(clipped / step) * step;
   if(normalized < minLot)
      normalized = minLot;
   return NormalizeDouble(normalized, 2);
}

double CalculateLot(const double atr)
{
   if(InpLotSizingMode == LOT_FIXED)
      return NormalizeVolume(InpFixedLot);

   double stopDistance = atr * InpEmergencyStopATR;
   double tickValue = SymbolInfoDouble(InpSymbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(InpSymbol, SYMBOL_TRADE_TICK_SIZE);
   if(stopDistance <= 0.0 || tickValue <= 0.0 || tickSize <= 0.0)
      return 0.0;

   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPercent / 100.0);
   double lossPerLot = (stopDistance / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
      return 0.0;

   return NormalizeVolume(riskMoney / lossPerLot);
}

double DailyVWAP()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   datetime dayStart = iTime(InpSymbol, PERIOD_D1, 0);
   if(dayStart == 0)
      return 0.0;

   int copied = CopyRates(InpSymbol, PERIOD_M5, dayStart, TimeCurrent(), rates);
   if(copied <= 0)
      return 0.0;

   double pv = 0.0;
   double volume = 0.0;
   for(int i = 0; i < copied; i++)
   {
      double typical = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
      double vol = (double)rates[i].tick_volume;
      pv += typical * vol;
      volume += vol;
   }

   if(volume <= 0.0)
      return 0.0;
   return pv / volume;
}

bool M1BullishTrigger()
{
   double open = iOpen(InpSymbol, PERIOD_M1, 1);
   double close = iClose(InpSymbol, PERIOD_M1, 1);
   double low = iLow(InpSymbol, PERIOD_M1, 1);
   if(open == 0.0 || close == 0.0 || low == 0.0)
      return false;

   double body = MathAbs(close - open);
   double lowerWick = MathMin(open, close) - low;
   return close > open && lowerWick >= body * 0.50;
}

bool OpenMarketPair(const double lot,
                    const double atr,
                    const double rsi,
                    const double stochK,
                    const double stochD,
                    const double emaFast,
                    const double emaSlow,
                    const double vwap,
                    const double bandLower,
                    const double bandUpper)
{
   int digits = (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS);
   double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   double buyStop = NormalizeDouble(ask - atr * InpEmergencyStopATR, digits);
   double sellStop = NormalizeDouble(bid + atr * InpEmergencyStopATR, digits);

   bool buyOk = trade.Buy(lot, InpSymbol, 0.0, buyStop, 0.0, "HedgedRange long leg");
   if(!buyOk)
   {
      Print("Buy leg failed. retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      return false;
   }
   TradeLog("OPEN_BUY", "confirmed M15 low + M5 indicators + M1 bullish trigger", ask, lot, rsi, stochK, stochD, emaFast, emaSlow, atr, vwap, bandLower, bandUpper);

   bool sellOk = trade.Sell(lot, InpSymbol, 0.0, sellStop, 0.0, "HedgedRange short hedge");
   if(!sellOk)
   {
      Print("Sell hedge failed; closing buy leg. retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      CloseAllBotPositions("hedge leg failed");
      return false;
   }
   TradeLog("OPEN_SELL", "simultaneous hedge at range low", bid, lot, rsi, stochK, stochD, emaFast, emaSlow, atr, vwap, bandLower, bandUpper);

   lastEntryTime = TimeCurrent();
   cycleActive = true;
   shortAddsThisCycle = 0;
   return true;
}

bool OpenSwingHighShort(const double lot,
                        const double atr,
                        const double rsi,
                        const double stochK,
                        const double stochD,
                        const double emaFast,
                        const double emaSlow,
                        const double vwap,
                        const double bandLower,
                        const double bandUpper,
                        const string reason)
{
   int digits = (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS);
   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   double stop = NormalizeDouble(bid + atr * InpEmergencyStopATR, digits);

   bool ok = false;
   if(InpUseSellLimitAtSwingHigh && lastSwingHigh > bid)
   {
      datetime expiry = TimeCurrent() + InpPendingExpiryMinutes * 60;
      ok = trade.SellLimit(lot, NormalizeDouble(lastSwingHigh, digits), InpSymbol, stop, 0.0, ORDER_TIME_SPECIFIED, expiry, "HedgedRange swing-high limit short");
   }
   else
   {
      ok = trade.Sell(lot, InpSymbol, 0.0, stop, 0.0, "HedgedRange swing-high short");
   }

   if(ok)
   {
      TradeLog("ADD_SELL", reason, bid, lot, rsi, stochK, stochD, emaFast, emaSlow, atr, vwap, bandLower, bandUpper);
      shortAddsThisCycle++;
      lastSwingHighAddBar = iTime(InpSymbol, PERIOD_M15, 0);
   }
   else
   {
      Print("Swing-high short failed. retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
   return ok;
}

void EvaluateRangeLowEntry()
{
   if(!IsSpreadOk())
      return;
   if((TimeCurrent() - lastEntryTime) < InpMinSecondsBetweenEntries)
      return;
   if(CountBotPositions(-1) > 0)
      return;
   if(CountBotPositions(-1) + 2 > InpMaxSimultaneousPositions)
      return;
   if(lastSwingLow <= 0.0)
      return;

   double rsi, stochK0, stochD0, stochK1, stochD1, emaFast0, emaFast1, emaSlow0, emaSlow1, atr, bandUpper, bandLower;
   if(!GetIndicatorSnapshot(rsi, stochK0, stochD0, stochK1, stochD1, emaFast0, emaFast1, emaSlow0, emaSlow1, atr, bandUpper, bandLower))
   {
      LogDecision("No trade: indicator data not ready");
      return;
   }

   if(atr < InpMinATR)
   {
      LogDecision(StringFormat("No trade: M15 ATR %.5f below minimum %.5f", atr, InpMinATR));
      return;
   }

   double vwap = DailyVWAP();
   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
   double mid = (bid + ask) * 0.5;
   double swingLowBuffer = atr * InpSwingLowBufferATR;
   bool nearSwingLow = MathAbs(mid - lastSwingLow) <= swingLowBuffer;
   bool rsiOk = rsi <= InpRSIOversold;
   bool stochCrossUp = stochK1 <= stochD1 && stochK0 > stochD0;
   bool emaTurningUp = emaFast0 > emaFast1 && emaFast0 >= emaSlow0;
   bool bullishM1 = M1BullishTrigger();
   bool lowerBandTouch = !InpRequireLowerBandTouch || iLow(InpSymbol, PERIOD_M5, 1) <= bandLower + atr * InpBandTouchBufferATR;
   bool vwapOk = !InpRequireVwapConfluence || (vwap > 0.0 && mid < vwap);

   if(!(nearSwingLow && rsiOk && stochCrossUp && emaTurningUp && bullishM1 && lowerBandTouch && vwapOk))
   {
      LogDecision(StringFormat("No trade: low setup not met nearLow=%s RSI=%.2f stochCross=%s emaUp=%s M1Bull=%s lowerBB=%s vwap=%s",
                               nearSwingLow ? "Y" : "N", rsi, stochCrossUp ? "Y" : "N", emaTurningUp ? "Y" : "N",
                               bullishM1 ? "Y" : "N", lowerBandTouch ? "Y" : "N", vwapOk ? "Y" : "N"));
      return;
   }

   double lot = CalculateLot(atr);
   if(lot <= 0.0)
   {
      LogDecision("No trade: lot calculation failed");
      return;
   }

   OpenMarketPair(lot, atr, rsi, stochK0, stochD0, emaFast0, emaSlow0, vwap, bandLower, bandUpper);
}

void EvaluateSwingHighAdd()
{
   if(!cycleActive)
      return;
   if(!IsSpreadOk())
      return;
   if(shortAddsThisCycle >= InpMaxShortAddsPerCycle)
      return;
   if(CountBotPositions(-1) >= InpMaxSimultaneousPositions)
      return;
   if(lastSwingHigh <= 0.0)
      return;

   double rsi, stochK0, stochD0, stochK1, stochD1, emaFast0, emaFast1, emaSlow0, emaSlow1, atr, bandUpper, bandLower;
   if(!GetIndicatorSnapshot(rsi, stochK0, stochD0, stochK1, stochD1, emaFast0, emaFast1, emaSlow0, emaSlow1, atr, bandUpper, bandLower))
      return;

   if(atr < InpMinATR)
      return;

   double vwap = DailyVWAP();
   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
   double mid = (bid + ask) * 0.5;
   bool nearSwingHigh = MathAbs(mid - lastSwingHigh) <= atr * InpSwingHighBufferATR;
   bool rsiApproach = rsi >= InpRSISwingHigh;
   bool vwapConfluence = vwap > 0.0 && mid >= vwap;
   bool upperBandConfluence = iHigh(InpSymbol, PERIOD_M5, 1) >= bandUpper - atr * InpBandTouchBufferATR;
   bool confluenceOk = !InpRequireUpperBandAdd || (vwapConfluence && upperBandConfluence);
   datetime currentM15 = iTime(InpSymbol, PERIOD_M15, 0);

   if(!(nearSwingHigh && rsiApproach && confluenceOk) || currentM15 == lastSwingHighAddBar)
      return;

   CloseProfitableLongs();
   double lot = CalculateLot(atr);
   if(lot <= 0.0)
      return;

   string reason = StringFormat("M15 swing high add; RSI %.2f; VWAP=%s upperBB=%s", rsi, vwapConfluence ? "Y" : "N", upperBandConfluence ? "Y" : "N");
   OpenSwingHighShort(lot, atr, rsi, stochK0, stochD0, emaFast0, emaSlow0, vwap, bandLower, bandUpper, reason);
}

void OnTick()
{
   if(_Symbol != InpSymbol)
      return;

   RecalculateM15Swings(false);
   CloseProfitableLongs();
   ManageNetExit();

   datetime m1Bar = iTime(InpSymbol, PERIOD_M1, 0);
   if(m1Bar == 0 || m1Bar == lastM1BarTime)
      return;
   lastM1BarTime = m1Bar;

   EvaluateSwingHighAdd();
   EvaluateRangeLowEntry();
}
