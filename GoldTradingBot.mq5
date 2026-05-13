#property copyright "gold-trading-bot"
#property version   "2.20"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

enum TrendDirection { TREND_NONE = 0, TREND_BUY = 1, TREND_SELL = -1 };

input string           InpSymbol                     = "XAUUSD";
input ENUM_TIMEFRAMES  InpTimeframe                  = PERIOD_M1;
input int              InpFastEMA                    = 9;
input int              InpSlowEMA                    = 26;
input int              InpADXPeriod                  = 14;
input double           InpADXTrendThreshold          = 25.0;
input double           InpADXConsolidationThreshold  = 18.0;
input int              InpRSIPeriod                  = 14;
input double           InpRSIBuyThreshold            = 55.0;
input double           InpRSISellThreshold           = 45.0;
input int              InpATRPeriod                  = 14;
input double           InpATRSLMultiplier            = 1.8;
input double           InpATRTPMultiplier            = 2.4;
input double           InpRiskPercent                = 0.30;
input double           InpMaxLot                     = 0.02;
input int              InpMaxTradesPerHour           = 30;
input int              InpMaxTradesPerDay            = 1000;
input int              InpMinSecondsBetweenTrades    = 4;
input bool             InpUseTrailingStop            = true;
input double           InpTrailATRMultiplier         = 1.2;
input int              InpSRLookbackBars             = 80;
input double           InpSRZoneATRMultiplier        = 0.6;
input ENUM_TIMEFRAMES  InpHTFTimeframe               = PERIOD_M5;
input int              InpMagicNumber                = 260513;

int fastHandle = INVALID_HANDLE, slowHandle = INVALID_HANDLE, rsiHandle = INVALID_HANDLE, adxHandle = INVALID_HANDLE, atrHandle = INVALID_HANDLE;
datetime lastBarTime = 0, lastTradeTime = 0;
datetime tradeTimes[];

int OnInit(){
   fastHandle=iMA(InpSymbol,InpTimeframe,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   slowHandle=iMA(InpSymbol,InpTimeframe,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   rsiHandle=iRSI(InpSymbol,InpTimeframe,InpRSIPeriod,PRICE_CLOSE);
   adxHandle=iADX(InpSymbol,InpTimeframe,InpADXPeriod);
   atrHandle=iATR(InpSymbol,InpTimeframe,InpATRPeriod);
   if(fastHandle==INVALID_HANDLE||slowHandle==INVALID_HANDLE||rsiHandle==INVALID_HANDLE||adxHandle==INVALID_HANDLE||atrHandle==INVALID_HANDLE) return INIT_FAILED;
   trade.SetExpertMagicNumber(InpMagicNumber);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){
   if(fastHandle!=INVALID_HANDLE)IndicatorRelease(fastHandle);
   if(slowHandle!=INVALID_HANDLE)IndicatorRelease(slowHandle);
   if(rsiHandle!=INVALID_HANDLE)IndicatorRelease(rsiHandle);
   if(adxHandle!=INVALID_HANDLE)IndicatorRelease(adxHandle);
   if(atrHandle!=INVALID_HANDLE)IndicatorRelease(atrHandle);
}

bool HasOpenPosition(){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i); if(t==0||!PositionSelectByTicket(t))continue; if(PositionGetString(POSITION_SYMBOL)==InpSymbol && PositionGetInteger(POSITION_MAGIC)==InpMagicNumber)return true;} return false;}
double GetATRValue(){double a[2]; if(CopyBuffer(atrHandle,0,0,2,a)<2) return 0.0; return a[0];}
void PushTradeTime(datetime t){int n=ArraySize(tradeTimes); ArrayResize(tradeTimes,n+1); tradeTimes[n]=t;}
void CleanupTradeTimes(){datetime now=TimeCurrent(); datetime f[]; ArrayResize(f,0); for(int i=0;i<ArraySize(tradeTimes);i++){if((now-tradeTimes[i])<=86400){int n=ArraySize(f); ArrayResize(f,n+1); f[n]=tradeTimes[i];}} ArrayResize(tradeTimes,ArraySize(f)); ArrayCopy(tradeTimes,f,0,0,WHOLE_ARRAY);}
bool CanOpenNewTrade(){datetime now=TimeCurrent(); if(lastTradeTime>0 && (now-lastTradeTime)<InpMinSecondsBetweenTrades) return false; int h=0,d=0; for(int i=ArraySize(tradeTimes)-1;i>=0;i--){long age=now-tradeTimes[i]; if(age<=3600)h++; if(age<=86400)d++;} return (h<InpMaxTradesPerHour && d<InpMaxTradesPerDay);}

double CalculatePositionSize(double slPoints){ if(slPoints<=0.0)return 0.0; double bal=AccountInfoDouble(ACCOUNT_BALANCE), risk=bal*(InpRiskPercent/100.0); double tickValue=SymbolInfoDouble(InpSymbol,SYMBOL_TRADE_TICK_VALUE), tickSize=SymbolInfoDouble(InpSymbol,SYMBOL_TRADE_TICK_SIZE), point=SymbolInfoDouble(InpSymbol,SYMBOL_POINT); if(tickValue<=0||tickSize<=0||point<=0) return 0.0; double valuePerPointPerLot=tickValue*(point/tickSize); double lots=risk/(slPoints*valuePerPointPerLot); double minLot=SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_MIN), maxLot=SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_MAX), step=SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_STEP); lots=MathMax(minLot,MathMin(MathMin(maxLot,InpMaxLot),lots)); lots=MathFloor(lots/step)*step; return NormalizeDouble(lots,2); }

bool GetSupportResistance(double &support,double &resistance){
   int bars = MathMax(20, InpSRLookbackBars);
   int lowIdx=iLowest(InpSymbol,InpTimeframe,MODE_LOW,bars,1);
   int highIdx=iHighest(InpSymbol,InpTimeframe,MODE_HIGH,bars,1);
   if(lowIdx<0 || highIdx<0) return false;
   support=iLow(InpSymbol,InpTimeframe,lowIdx);
   resistance=iHigh(InpSymbol,InpTimeframe,highIdx);
   return (support>0 && resistance>0 && resistance>support);
}

bool IsNearLevel(double price,double level,double zone){ return MathAbs(price-level)<=zone; }

bool IsBullishRejection(){
   double o=iOpen(InpSymbol,InpTimeframe,1), c=iClose(InpSymbol,InpTimeframe,1), h=iHigh(InpSymbol,InpTimeframe,1), l=iLow(InpSymbol,InpTimeframe,1);
   double body=MathAbs(c-o), lowerWick=MathMin(o,c)-l, upperWick=h-MathMax(o,c);
   return (c>o && lowerWick>body*1.2 && lowerWick>upperWick);
}

bool IsBearishRejection(){
   double o=iOpen(InpSymbol,InpTimeframe,1), c=iClose(InpSymbol,InpTimeframe,1), h=iHigh(InpSymbol,InpTimeframe,1), l=iLow(InpSymbol,InpTimeframe,1);
   double body=MathAbs(c-o), upperWick=h-MathMax(o,c), lowerWick=MathMin(o,c)-l;
   return (c<o && upperWick>body*1.2 && upperWick>lowerWick);
}

TrendDirection GetHigherTimeframeBias(){
   double htfFast=iMA(InpSymbol,InpHTFTimeframe,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double htfSlow=iMA(InpSymbol,InpHTFTimeframe,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   if(htfFast==0 || htfSlow==0) return TREND_NONE;
   if(htfFast>htfSlow) return TREND_BUY;
   if(htfFast<htfSlow) return TREND_SELL;
   return TREND_NONE;
}

TrendDirection GetSignal(){
   double f[2],s[2],r[2],adx[2],pdi[2],mdi[2];
   if(CopyBuffer(fastHandle,0,0,2,f)<2||CopyBuffer(slowHandle,0,0,2,s)<2||CopyBuffer(rsiHandle,0,0,2,r)<2||CopyBuffer(adxHandle,0,0,2,adx)<2||CopyBuffer(adxHandle,1,0,2,pdi)<2||CopyBuffer(adxHandle,2,0,2,mdi)<2) return TREND_NONE;
   if(adx[0]<=InpADXConsolidationThreshold) return TREND_NONE;

   TrendDirection htfBias=GetHigherTimeframeBias();
   double support,resistance; if(!GetSupportResistance(support,resistance)) return TREND_NONE;

   double atr=GetATRValue(); if(atr<=0) return TREND_NONE;
   double zone=atr*InpSRZoneATRMultiplier;
   double close1=iClose(InpSymbol,InpTimeframe,1);

   bool trendBuy=(adx[0]>=InpADXTrendThreshold && f[0]>s[0] && pdi[0]>mdi[0] && r[0]>=InpRSIBuyThreshold && htfBias!=TREND_SELL);
   bool trendSell=(adx[0]>=InpADXTrendThreshold && f[0]<s[0] && mdi[0]>pdi[0] && r[0]<=InpRSISellThreshold && htfBias!=TREND_BUY);

   bool srBuy = IsNearLevel(close1,support,zone) && IsBullishRejection() && htfBias!=TREND_SELL;
   bool srSell = IsNearLevel(close1,resistance,zone) && IsBearishRejection() && htfBias!=TREND_BUY;

   if(trendBuy || srBuy) return TREND_BUY;
   if(trendSell || srSell) return TREND_SELL;
   return TREND_NONE;
}

bool PlaceOrder(TrendDirection sig,double vol,double slPts,double tpPts){double point=SymbolInfoDouble(InpSymbol,SYMBOL_POINT); int digits=(int)SymbolInfoInteger(InpSymbol,SYMBOL_DIGITS); double ask=SymbolInfoDouble(InpSymbol,SYMBOL_ASK), bid=SymbolInfoDouble(InpSymbol,SYMBOL_BID); if(sig==TREND_BUY) return trade.Buy(vol,InpSymbol,ask,NormalizeDouble(ask-slPts*point,digits),NormalizeDouble(ask+tpPts*point,digits),"XAU M1 TA Buy"); if(sig==TREND_SELL) return trade.Sell(vol,InpSymbol,bid,NormalizeDouble(bid+slPts*point,digits),NormalizeDouble(bid-tpPts*point,digits),"XAU M1 TA Sell"); return false; }

void ManageTrailingStop(){ if(!InpUseTrailingStop)return; double atr=GetATRValue(); if(atr<=0.0)return; double point=SymbolInfoDouble(InpSymbol,SYMBOL_POINT); int digits=(int)SymbolInfoInteger(InpSymbol,SYMBOL_DIGITS); double trailPts=(atr*InpTrailATRMultiplier)/point; for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i); if(t==0||!PositionSelectByTicket(t))continue; if(PositionGetString(POSITION_SYMBOL)!=InpSymbol||PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)continue; long type=PositionGetInteger(POSITION_TYPE); double tp=PositionGetDouble(POSITION_TP), sl=PositionGetDouble(POSITION_SL); if(type==POSITION_TYPE_BUY){double bid=SymbolInfoDouble(InpSymbol,SYMBOL_BID); double nsl=NormalizeDouble(bid-trailPts*point,digits); if(sl==0.0||nsl>sl) trade.PositionModify(InpSymbol,nsl,tp);} else if(type==POSITION_TYPE_SELL){double ask=SymbolInfoDouble(InpSymbol,SYMBOL_ASK); double nsl=NormalizeDouble(ask+trailPts*point,digits); if(sl==0.0||nsl<sl) trade.PositionModify(InpSymbol,nsl,tp);} }}

void OnTick(){ if(_Symbol!=InpSymbol) return; ManageTrailingStop(); datetime bar=iTime(InpSymbol,InpTimeframe,0); if(bar==0||bar==lastBarTime) return; lastBarTime=bar; if(HasOpenPosition()) return; CleanupTradeTimes(); if(!CanOpenNewTrade()) return; double atr=GetATRValue(); if(atr<=0.0) return; TrendDirection sig=GetSignal(); if(sig==TREND_NONE) return; double point=SymbolInfoDouble(InpSymbol,SYMBOL_POINT); double slPts=(atr*InpATRSLMultiplier)/point, tpPts=(atr*InpATRTPMultiplier)/point; double vol=CalculatePositionSize(slPts); if(vol<=0.0)return; if(PlaceOrder(sig,vol,slPts,tpPts)){lastTradeTime=TimeCurrent(); PushTradeTime(lastTradeTime);} }
