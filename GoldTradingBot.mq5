#property copyright "gold-trading-bot"
#property version   "2.30"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

enum TrendDirection { TREND_NONE=0, TREND_BUY=1, TREND_SELL=-1 };
enum MarketRegime { REGIME_CHOPPY=0, REGIME_MODERATE=1, REGIME_STRONG=2 };

input string           InpSymbol                      = "XAUUSD";
input ENUM_TIMEFRAMES  InpTimeframe                   = PERIOD_M1;
input bool             InpUseAIConfirmation           = true;
input bool             InpStrongTrendIgnoresSR        = true;
input bool             InpConsolidationSROnly         = true;
input bool             InpDebugMode                   = true;

input int              InpFastEMA                     = 9;
input int              InpSlowEMA                     = 26;
input int              InpRSIPeriod                   = 14;
input int              InpADXPeriod                   = 14;
input int              InpATRPeriod                   = 14;

input double           InpRiskPercent                 = 0.30;
input double           InpMaxLot                      = 0.02;
input int              InpMaxOpenPositions            = 1;
input bool             InpEnableHighConfidenceScaleIn = false;
input int              InpScaleInMinConfidence        = 92;
input int              InpScaleInMaxPositions         = 2;

input double           InpATRSLMultiplier             = 1.0;
input double           InpATRTPMultiplier             = 1.2;
input bool             InpUseTrailingStop             = true;
input double           InpTrailATRMultiplier          = 1.0;
input bool             InpUseBreakEven                = true;
input double           InpBreakEvenATRMultiplier      = 0.8;

input int              InpMaxTradesPerHour            = 30;
input int              InpMaxTradesPerDay             = 1000;
input int              InpMinSecondsBetweenTrades     = 4;
input int              InpMinBarsBetweenTrades        = 1;
input double           InpMaxSpreadPoints             = 60;

input int              InpSRLookbackBars              = 220;
input int              InpSRWindow                    = 3;
input double           InpSRZoneATRMultiplier         = 0.35;
input int              InpSRMinimumTouches            = 3;
input int              InpBreakoutConfirmCandles      = 2;

input double           InpADXConsolidationThreshold   = 14.0;
input double           InpADXTrendThreshold           = 20.0;
input double           InpADXVeryStrongThreshold      = 30.0;
input int              InpMinAIConfidenceToTrade      = 60;
input int              InpMinAIConfidenceIgnoreSR     = 80;
input int              InpStrongTrendDirectionScore   = 85;
input int              InpMagicNumber                 = 260513;

int fastHandle=INVALID_HANDLE, slowHandle=INVALID_HANDLE, rsiHandle=INVALID_HANDLE, adxHandle=INVALID_HANDLE, atrHandle=INVALID_HANDLE;
int htfFastHandle=INVALID_HANDLE, htfSlowHandle=INVALID_HANDLE;
datetime lastBarTime=0, lastTradeTime=0, lastDecisionLogTime=0;
datetime tradeTimes[];
int lastTradeBarShift=9999;
string lastDecisionMessage="";

void LogOncePerDecision(string msg){
   if(!InpDebugMode) return;
   datetime nowBar=iTime(InpSymbol,InpTimeframe,0);
   if(msg!=lastDecisionMessage || nowBar!=lastDecisionLogTime){
      Print(msg);
      lastDecisionMessage=msg;
      lastDecisionLogTime=nowBar;
   }
}

int OnInit(){
   fastHandle=iMA(InpSymbol,InpTimeframe,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   slowHandle=iMA(InpSymbol,InpTimeframe,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   rsiHandle=iRSI(InpSymbol,InpTimeframe,InpRSIPeriod,PRICE_CLOSE);
   adxHandle=iADX(InpSymbol,InpTimeframe,InpADXPeriod);
   atrHandle=iATR(InpSymbol,InpTimeframe,InpATRPeriod);
   htfFastHandle=iMA(InpSymbol,PERIOD_M5,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   htfSlowHandle=iMA(InpSymbol,PERIOD_M5,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   if(fastHandle==INVALID_HANDLE||slowHandle==INVALID_HANDLE||rsiHandle==INVALID_HANDLE||adxHandle==INVALID_HANDLE||atrHandle==INVALID_HANDLE||htfFastHandle==INVALID_HANDLE||htfSlowHandle==INVALID_HANDLE) return INIT_FAILED;
   trade.SetExpertMagicNumber(InpMagicNumber);
   LogOncePerDecision("GoldTradingBot v2.30 started for "+InpSymbol+" on M1. Backtest/demo first; no profit guarantee.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){ if(fastHandle!=INVALID_HANDLE)IndicatorRelease(fastHandle); if(slowHandle!=INVALID_HANDLE)IndicatorRelease(slowHandle); if(rsiHandle!=INVALID_HANDLE)IndicatorRelease(rsiHandle); if(adxHandle!=INVALID_HANDLE)IndicatorRelease(adxHandle); if(atrHandle!=INVALID_HANDLE)IndicatorRelease(atrHandle); if(htfFastHandle!=INVALID_HANDLE)IndicatorRelease(htfFastHandle); if(htfSlowHandle!=INVALID_HANDLE)IndicatorRelease(htfSlowHandle); }

double GetATR(){ double a[2]; if(CopyBuffer(atrHandle,0,0,2,a)<2) return 0.0; return a[0]; }

bool IsSwingHigh(const double &h[],int idx,int w){ for(int k=1;k<=w;k++) if(h[idx]<=h[idx-k] || h[idx]<=h[idx+k]) return false; return true; }
bool IsSwingLow(const double &l[],int idx,int w){ for(int k=1;k<=w;k++) if(l[idx]>=l[idx-k] || l[idx]>=l[idx+k]) return false; return true; }

bool BuildSR(double &support,double &resistance,int &supStrength,int &resStrength,double &zoneWidth){
   MqlRates rates[]; int bars=MathMax(80,InpSRLookbackBars); int copied=CopyRates(InpSymbol,InpTimeframe,0,bars,rates); if(copied<40) return false;
   ArraySetAsSeries(rates,true);
   double atr=GetATR(); if(atr<=0) return false; zoneWidth=atr*InpSRZoneATRMultiplier;
   double mid=(SymbolInfoDouble(InpSymbol,SYMBOL_BID)+SymbolInfoDouble(InpSymbol,SYMBOL_ASK))*0.5;

   double zonePrice[40]; int zoneTouch[40]; int zoneReject[40]; bool zoneSup[40]; int zones=0;
   for(int i=InpSRWindow+2;i<copied-InpSRWindow-2;i++){
      bool sl=IsSwingLow((double&)rates.low,i,InpSRWindow), sh=IsSwingHigh((double&)rates.high,i,InpSRWindow);
      if(!sl && !sh) continue;
      double p=sl?rates[i].low:rates[i].high; bool isSup=sl; int f=-1;
      for(int z=0;z<zones;z++) if(zoneSup[z]==isSup && MathAbs(zonePrice[z]-p)<=zoneWidth){f=z;break;}
      if(f<0 && zones<40){f=zones; zonePrice[f]=p; zoneTouch[f]=0; zoneReject[f]=0; zoneSup[f]=isSup; zones++;}
      zoneTouch[f]++;
      double b=MathAbs(rates[i].close-rates[i].open), lw=MathMin(rates[i].open,rates[i].close)-rates[i].low, uw=rates[i].high-MathMax(rates[i].open,rates[i].close);
      if(isSup && lw>b*1.2) zoneReject[f]++; if(!isSup && uw>b*1.2) zoneReject[f]++;
   }
   support=0; resistance=0; supStrength=0; resStrength=0; double bestSup=DBL_MAX, bestRes=DBL_MAX;
   for(int z=0;z<zones;z++){
      if(zoneTouch[z]<InpSRMinimumTouches) continue;
      int st=zoneTouch[z]+zoneReject[z];
      if(zoneSup[z] && zonePrice[z]<mid){ double d=mid-zonePrice[z]; if(d<bestSup){bestSup=d; support=zonePrice[z]; supStrength=st;}}
      if(!zoneSup[z] && zonePrice[z]>mid){ double d=zonePrice[z]-mid; if(d<bestRes){bestRes=d; resistance=zonePrice[z]; resStrength=st;}}
   }
   return (support>0 || resistance>0);
}

int ClampScore(int s){ if(s<0) return 0; if(s>100) return 100; return s; }

int ComputeAIConfidence(TrendDirection &dirOut, MarketRegime &regimeOut, string &reason, double support, double resistance, double zone){
   double f[4],s[4],rsi[3],adx[3],pdi[3],mdi[3],atr[3];
   if(CopyBuffer(fastHandle,0,0,4,f)<4||CopyBuffer(slowHandle,0,0,4,s)<4||CopyBuffer(rsiHandle,0,0,3,rsi)<3||CopyBuffer(adxHandle,0,0,3,adx)<3||CopyBuffer(adxHandle,1,0,3,pdi)<3||CopyBuffer(adxHandle,2,0,3,mdi)<3||CopyBuffer(atrHandle,0,0,3,atr)<3){reason="indicator data unavailable"; return 0;}
   double mid=(SymbolInfoDouble(InpSymbol,SYMBOL_BID)+SymbolInfoDouble(InpSymbol,SYMBOL_ASK))*0.5;
   bool nearSup=(support>0 && MathAbs(mid-support)<=zone), nearRes=(resistance>0 && MathAbs(mid-resistance)<=zone);
   bool bull=iClose(InpSymbol,InpTimeframe,1)>iOpen(InpSymbol,InpTimeframe,1), bear=!bull;
   bool atrExp=atr[0]>atr[1]*1.02;
   bool emaUp=f[0]>s[0], emaDn=f[0]<s[0];
   double sep=MathAbs(f[0]-s[0])/(atr[0]+0.0000001);

   int buy=0,sell=0;
   if(emaUp) buy+=12; if(emaDn) sell+=12;
   if((f[0]-f[3])>0) buy+=10; if((f[0]-f[3])<0) sell+=10;
   if(sep>0.20){ buy+=8; sell+=8; }
   if(adx[0]>InpADXTrendThreshold){ buy+=8; sell+=8; }
   if(adx[0]>adx[1]){ buy+=6; sell+=6; }
   if(pdi[0]>mdi[0]) buy+=10; if(mdi[0]>pdi[0]) sell+=10;
   if(rsi[0]>52) buy+=8; if(rsi[0]<48) sell+=8;
   if(bull) buy+=6; if(bear) sell+=6;
   if(atrExp){ buy+=6; sell+=6; }
   long tv=iVolume(InpSymbol,InpTimeframe,1), tvp=iVolume(InpSymbol,InpTimeframe,2); if(tvp>0 && tv>tvp){ buy+=4; sell+=4; }
   if(iHigh(InpSymbol,InpTimeframe,1)>iHigh(InpSymbol,InpTimeframe,2) && iLow(InpSymbol,InpTimeframe,1)>iLow(InpSymbol,InpTimeframe,2)) buy+=8;
   if(iHigh(InpSymbol,InpTimeframe,1)<iHigh(InpSymbol,InpTimeframe,2) && iLow(InpSymbol,InpTimeframe,1)<iLow(InpSymbol,InpTimeframe,2)) sell+=8;
   if(nearSup) buy+=7; if(nearRes) sell+=7;

   bool breakRetestBuy=false, breakRetestSell=false;
   if(resistance>0){ breakRetestBuy=true; for(int i=InpBreakoutConfirmCandles+1;i>=2;i--) if(iClose(InpSymbol,InpTimeframe,i)<=resistance+zone*0.2) breakRetestBuy=false; if(!(iLow(InpSymbol,InpTimeframe,1)<=resistance+zone && iClose(InpSymbol,InpTimeframe,1)>resistance)) breakRetestBuy=false; }
   if(support>0){ breakRetestSell=true; for(int i=InpBreakoutConfirmCandles+1;i>=2;i--) if(iClose(InpSymbol,InpTimeframe,i)>=support-zone*0.2) breakRetestSell=false; if(!(iHigh(InpSymbol,InpTimeframe,1)>=support-zone && iClose(InpSymbol,InpTimeframe,1)<support)) breakRetestSell=false; }
   if(breakRetestBuy) buy+=10; if(breakRetestSell) sell+=10;

   int ai=ClampScore(MathMax(buy,sell));
   dirOut=(buy>=sell)?TREND_BUY:TREND_SELL;
   if(adx[0]>=InpADXVeryStrongThreshold && adx[0]>adx[1] && sep>0.25 && ai>=InpMinAIConfidenceIgnoreSR) regimeOut=REGIME_STRONG;
   else if(adx[0]>=InpADXConsolidationThreshold) regimeOut=REGIME_MODERATE;
   else regimeOut=REGIME_CHOPPY;

   reason="AI="+IntegerToString(ai)+" buyScore="+IntegerToString(buy)+" sellScore="+IntegerToString(sell);
   return ai;
}

int CountOpenPositions(){ int c=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t==0||!PositionSelectByTicket(t)) continue; if(PositionGetString(POSITION_SYMBOL)==InpSymbol&&PositionGetInteger(POSITION_MAGIC)==InpMagicNumber) c++; } return c; }

bool CanOpenTrade(){
   double spread=(SymbolInfoDouble(InpSymbol,SYMBOL_ASK)-SymbolInfoDouble(InpSymbol,SYMBOL_BID))/SymbolInfoDouble(InpSymbol,SYMBOL_POINT);
   if(spread>InpMaxSpreadPoints){ LogOncePerDecision("No trade: spread too high"); return false; }
   datetime now=TimeCurrent(); if(lastTradeTime>0 && (now-lastTradeTime)<InpMinSecondsBetweenTrades){ LogOncePerDecision("No trade: cooldown seconds"); return false; }
   if(lastTradeBarShift<InpMinBarsBetweenTrades){ LogOncePerDecision("No trade: cooldown bars"); return false; }
   int h=0,d=0; for(int i=ArraySize(tradeTimes)-1;i>=0;i--){ long age=now-tradeTimes[i]; if(age<=3600)h++; if(age<=86400)d++; }
   if(h>=InpMaxTradesPerHour||d>=InpMaxTradesPerDay){ LogOncePerDecision("No trade: hourly/day cap"); return false; }
   return true;
}

double CalcLots(double slPts){ if(slPts<=0) return 0; double bal=AccountInfoDouble(ACCOUNT_BALANCE), risk=bal*(InpRiskPercent/100.0), tv=SymbolInfoDouble(InpSymbol,SYMBOL_TRADE_TICK_VALUE), ts=SymbolInfoDouble(InpSymbol,SYMBOL_TRADE_TICK_SIZE), pt=SymbolInfoDouble(InpSymbol,SYMBOL_POINT); if(tv<=0||ts<=0||pt<=0) return 0; double vpp=tv*(pt/ts); double lots=risk/(slPts*vpp); double minLot=SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_MIN), maxLot=SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_MAX), step=SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_STEP); lots=MathMax(minLot,MathMin(MathMin(maxLot,InpMaxLot),lots)); lots=MathFloor(lots/step)*step; return NormalizeDouble(lots,2); }

void ManageTrailing(){ if(!InpUseTrailingStop) return; double atr=GetATR(); if(atr<=0) return; double pt=SymbolInfoDouble(InpSymbol,SYMBOL_POINT); int d=(int)SymbolInfoInteger(InpSymbol,SYMBOL_DIGITS); double trail=atr*InpTrailATRMultiplier; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t==0||!PositionSelectByTicket(t)) continue; if(PositionGetString(POSITION_SYMBOL)!=InpSymbol||PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue; long type=PositionGetInteger(POSITION_TYPE); double sl=PositionGetDouble(POSITION_SL), tp=PositionGetDouble(POSITION_TP), open=PositionGetDouble(POSITION_PRICE_OPEN); if(type==POSITION_TYPE_BUY){ double bid=SymbolInfoDouble(InpSymbol,SYMBOL_BID); if(InpUseBreakEven && bid-open>=atr*InpBreakEvenATRMultiplier && (sl<open||sl==0)) trade.PositionModify(InpSymbol,NormalizeDouble(open,d),tp); double nsl=NormalizeDouble(bid-trail,d); if(nsl>sl) trade.PositionModify(InpSymbol,nsl,tp);} else { double ask=SymbolInfoDouble(InpSymbol,SYMBOL_ASK); if(InpUseBreakEven && open-ask>=atr*InpBreakEvenATRMultiplier && (sl>open||sl==0)) trade.PositionModify(InpSymbol,NormalizeDouble(open,d),tp); double nsl=NormalizeDouble(ask+trail,d); if(sl==0||nsl<sl) trade.PositionModify(InpSymbol,nsl,tp);} }}

void OnTick(){
   if(_Symbol!=InpSymbol) return;
   ManageTrailing();
   datetime bar=iTime(InpSymbol,InpTimeframe,0); if(bar==0||bar==lastBarTime) return; lastBarTime=bar; lastTradeBarShift++;
   CleanupTradeTimes();

   if(!CanOpenTrade()) return;
   int openPos=CountOpenPositions();

   double support,resistance,zone; int supSt,resSt; if(!BuildSR(support,resistance,supSt,resSt,zone)){ LogOncePerDecision("No trade: SR not ready"); return; }

   TrendDirection dir; MarketRegime regime; string reason=""; int ai=ComputeAIConfidence(dir,regime,reason,support,resistance,zone);
   LogOncePerDecision("Regime="+IntegerToString((int)regime)+" "+reason+" SR sup="+DoubleToString(support,_Digits)+" res="+DoubleToString(resistance,_Digits));
   if(InpUseAIConfirmation && ai<InpMinAIConfidenceToTrade){ LogOncePerDecision("No trade: AI confidence too low"); return; }

   double mid=(SymbolInfoDouble(InpSymbol,SYMBOL_BID)+SymbolInfoDouble(InpSymbol,SYMBOL_ASK))*0.5;
   bool nearSup=(support>0&&MathAbs(mid-support)<=zone), nearRes=(resistance>0&&MathAbs(mid-resistance)<=zone);
   bool bullRej=iClose(InpSymbol,InpTimeframe,1)>iOpen(InpSymbol,InpTimeframe,1) && (MathMin(iOpen(InpSymbol,InpTimeframe,1),iClose(InpSymbol,InpTimeframe,1))-iLow(InpSymbol,InpTimeframe,1))>MathAbs(iClose(InpSymbol,InpTimeframe,1)-iOpen(InpSymbol,InpTimeframe,1))*1.2;
   bool bearRej=iClose(InpSymbol,InpTimeframe,1)<iOpen(InpSymbol,InpTimeframe,1) && (iHigh(InpSymbol,InpTimeframe,1)-MathMax(iOpen(InpSymbol,InpTimeframe,1),iClose(InpSymbol,InpTimeframe,1)))>MathAbs(iClose(InpSymbol,InpTimeframe,1)-iOpen(InpSymbol,InpTimeframe,1))*1.2;

   bool buy=false,sell=false;
   if(regime==REGIME_CHOPPY){
      if(InpConsolidationSROnly){ buy=nearSup&&bullRej&&!nearRes; sell=nearRes&&bearRej&&!nearSup; }
   } else if(regime==REGIME_MODERATE){
      buy=(nearSup&&bullRej&&!nearRes&&dir==TREND_BUY); sell=(nearRes&&bearRej&&!nearSup&&dir==TREND_SELL);
   } else if(regime==REGIME_STRONG){
      if(InpStrongTrendIgnoresSR && ai>=InpMinAIConfidenceIgnoreSR){ buy=(dir==TREND_BUY); sell=(dir==TREND_SELL); }
      else { buy=nearSup&&bullRej&&!nearRes; sell=nearRes&&bearRej&&!nearSup; }
   }

   if(buy&&nearRes) buy=false; if(sell&&nearSup) sell=false;
   if(!buy&&!sell){ LogOncePerDecision("No trade: setup filters not met"); return; }

   int allowed=InpMaxOpenPositions;
   if(InpEnableHighConfidenceScaleIn && regime==REGIME_STRONG && ai>=InpScaleInMinConfidence) allowed=MathMax(InpMaxOpenPositions,InpScaleInMaxPositions);
   if(openPos>=allowed){ LogOncePerDecision("No trade: max open positions reached"); return; }

   double atr=GetATR(); double pt=SymbolInfoDouble(InpSymbol,SYMBOL_POINT); int digits=(int)SymbolInfoInteger(InpSymbol,SYMBOL_DIGITS);
   double slPts=(atr*InpATRSLMultiplier)/pt, tpPts=(atr*InpATRTPMultiplier)/pt; if(slPts<=0||tpPts<=0){ LogOncePerDecision("No trade: invalid ATR stops"); return; }
   double lot=CalcLots(slPts); if(lot<=0){ LogOncePerDecision("No trade: lot calc failed"); return; }

   bool sent=false; double ask=SymbolInfoDouble(InpSymbol,SYMBOL_ASK), bid=SymbolInfoDouble(InpSymbol,SYMBOL_BID);
   if(buy){ double sl=NormalizeDouble(ask-slPts*pt,digits), tp=NormalizeDouble(ask+tpPts*pt,digits); sent=trade.Buy(lot,InpSymbol,ask,sl,tp,"GTB v2.30 BUY"); }
   if(sell){ double sl=NormalizeDouble(bid+slPts*pt,digits), tp=NormalizeDouble(bid-tpPts*pt,digits); sent=trade.Sell(lot,InpSymbol,bid,sl,tp,"GTB v2.30 SELL"); }

   if(sent){ lastTradeTime=TimeCurrent(); lastTradeBarShift=0; int n=ArraySize(tradeTimes); ArrayResize(tradeTimes,n+1); tradeTimes[n]=lastTradeTime; LogOncePerDecision("Trade opened lot="+DoubleToString(lot,2)+" AI="+IntegerToString(ai)); }
   else{ Print("Trade failed. Retcode=",trade.ResultRetcode()," Desc=",trade.ResultRetcodeDescription()," LastError=",GetLastError()); }
}
