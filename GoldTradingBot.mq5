#property copyright "gold-trading-bot"
#property version   "2.30"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

enum TrendDirection { TREND_NONE = 0, TREND_BUY = 1, TREND_SELL = -1 };

input string           InpSymbol                      = "XAUUSD";
input ENUM_TIMEFRAMES  InpTimeframe                   = PERIOD_M1;
input int              InpFastEMA                     = 9;
input int              InpSlowEMA                     = 26;
input int              InpADXPeriod                   = 14;
input double           InpADXTrendThreshold           = 18.0;
input double           InpADXChopThreshold            = 13.0;
input int              InpRSIPeriod                   = 14;
input int              InpATRPeriod                   = 14;
input double           InpATRSLMultiplier             = 1.6;
input double           InpATRTPMultiplier             = 1.35;
input double           InpRiskPercent                 = 0.30;
input double           InpMaxLot                      = 0.02;
input int              InpMaxTradesPerHour            = 30;
input int              InpMaxTradesPerDay             = 1000;
input int              InpMinSecondsBetweenTrades     = 4;
input bool             InpUseTrailingStop             = true;
input double           InpTrailATRMultiplier          = 1.05;
input int              InpBaseBarsBetweenTrades       = 2;

// Support/Resistance controls
input int              InpSRLookbackBars              = 160;
input double           InpSRZoneWidthATRMultiplier    = 0.35;
input int              InpSRMinimumTouches            = 3;
input int              InpBreakoutConfirmCandles      = 2;
input int              InpSRWindow                    = 3;
input ENUM_TIMEFRAMES  InpHTFTimeframe                = PERIOD_M5;
input int              InpMagicNumber                 = 260513;

int fastHandle=INVALID_HANDLE, slowHandle=INVALID_HANDLE, rsiHandle=INVALID_HANDLE, adxHandle=INVALID_HANDLE, atrHandle=INVALID_HANDLE;
int htfFastHandle=INVALID_HANDLE, htfSlowHandle=INVALID_HANDLE;
datetime lastBarTime=0, lastTradeTime=0;
int barsCooldown = 0;
datetime tradeTimes[];

int OnInit(){
   fastHandle=iMA(InpSymbol,InpTimeframe,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   slowHandle=iMA(InpSymbol,InpTimeframe,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   rsiHandle=iRSI(InpSymbol,InpTimeframe,InpRSIPeriod,PRICE_CLOSE);
   adxHandle=iADX(InpSymbol,InpTimeframe,InpADXPeriod);
   atrHandle=iATR(InpSymbol,InpTimeframe,InpATRPeriod);
   htfFastHandle=iMA(InpSymbol,InpHTFTimeframe,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   htfSlowHandle=iMA(InpSymbol,InpHTFTimeframe,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   if(fastHandle==INVALID_HANDLE||slowHandle==INVALID_HANDLE||rsiHandle==INVALID_HANDLE||adxHandle==INVALID_HANDLE||atrHandle==INVALID_HANDLE||htfFastHandle==INVALID_HANDLE||htfSlowHandle==INVALID_HANDLE) return INIT_FAILED;
   trade.SetExpertMagicNumber(InpMagicNumber);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){
   if(fastHandle!=INVALID_HANDLE)IndicatorRelease(fastHandle);
   if(slowHandle!=INVALID_HANDLE)IndicatorRelease(slowHandle);
   if(rsiHandle!=INVALID_HANDLE)IndicatorRelease(rsiHandle);
   if(adxHandle!=INVALID_HANDLE)IndicatorRelease(adxHandle);
   if(atrHandle!=INVALID_HANDLE)IndicatorRelease(atrHandle);
   if(htfFastHandle!=INVALID_HANDLE)IndicatorRelease(htfFastHandle);
   if(htfSlowHandle!=INVALID_HANDLE)IndicatorRelease(htfSlowHandle);
}

bool HasOpenPosition(){ for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t==0||!PositionSelectByTicket(t)) continue; if(PositionGetString(POSITION_SYMBOL)==InpSymbol && PositionGetInteger(POSITION_MAGIC)==InpMagicNumber) return true;} return false; }
double GetATRValue(){ double a[2]; if(CopyBuffer(atrHandle,0,0,2,a)<2) return 0.0; return a[0]; }
void PushTradeTime(datetime t){ int n=ArraySize(tradeTimes); ArrayResize(tradeTimes,n+1); tradeTimes[n]=t; }
void CleanupTradeTimes(){ datetime now=TimeCurrent(); datetime f[]; ArrayResize(f,0); for(int i=0;i<ArraySize(tradeTimes);i++){ if((now-tradeTimes[i])<=86400){int n=ArraySize(f); ArrayResize(f,n+1); f[n]=tradeTimes[i];}} ArrayResize(tradeTimes,ArraySize(f)); ArrayCopy(tradeTimes,f,0,0,WHOLE_ARRAY); }

bool CanOpenNewTrade(){
   datetime now=TimeCurrent();
   if(lastTradeTime>0 && (now-lastTradeTime)<InpMinSecondsBetweenTrades) return false;
   int h=0,d=0; for(int i=ArraySize(tradeTimes)-1;i>=0;i--){ long age=now-tradeTimes[i]; if(age<=3600)h++; if(age<=86400)d++; }
   if(h>=InpMaxTradesPerHour || d>=InpMaxTradesPerDay) return false;
   if(barsCooldown>0) return false;
   return true;
}

double CalculatePositionSize(double slPoints){ if(slPoints<=0.0) return 0.0; double bal=AccountInfoDouble(ACCOUNT_BALANCE), risk=bal*(InpRiskPercent/100.0); double tickValue=SymbolInfoDouble(InpSymbol,SYMBOL_TRADE_TICK_VALUE), tickSize=SymbolInfoDouble(InpSymbol,SYMBOL_TRADE_TICK_SIZE), point=SymbolInfoDouble(InpSymbol,SYMBOL_POINT); if(tickValue<=0||tickSize<=0||point<=0) return 0.0; double valuePerPointPerLot=tickValue*(point/tickSize); double lots=risk/(slPoints*valuePerPointPerLot); double minLot=SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_MIN), maxLot=SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_MAX), step=SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_STEP); lots=MathMax(minLot,MathMin(MathMin(maxLot,InpMaxLot),lots)); lots=MathFloor(lots/step)*step; return NormalizeDouble(lots,2); }

bool IsSwingHigh(const double &h[], int idx, int w){ for(int k=1;k<=w;k++){ if(h[idx]<=h[idx-k] || h[idx]<=h[idx+k]) return false; } return true; }
bool IsSwingLow(const double &l[], int idx, int w){ for(int k=1;k<=w;k++){ if(l[idx]>=l[idx-k] || l[idx]>=l[idx+k]) return false; } return true; }

// Detect strong SR zones: cluster nearby swing points, then rank by touches + wick rejections.
bool BuildStrongSRZones(double &support, int &supportStrength, double &resistance, int &resistanceStrength, double zoneWidth){
   int bars=MathMax(60, InpSRLookbackBars), w=MathMax(1, InpSRWindow);
   MqlRates rates[]; int copied=CopyRates(InpSymbol,InpTimeframe,0,bars,rates); if(copied < (w*2+10)) return false;
   ArraySetAsSeries(rates,true);

   double mid=(SymbolInfoDouble(InpSymbol,SYMBOL_BID)+SymbolInfoDouble(InpSymbol,SYMBOL_ASK))*0.5;
   double zonePrice[24]; int zoneCount[24]; int zoneReject[24]; bool zoneIsSupport[24]; int zones=0;

   for(int i=w+2;i<copied-w-2;i++){
      bool swingLow=IsSwingLow((double&)rates.low, i, w);
      bool swingHigh=IsSwingHigh((double&)rates.high, i, w);
      if(!swingLow && !swingHigh) continue;
      bool isSup=swingLow;
      double price=isSup ? rates[i].low : rates[i].high;
      int found=-1;
      for(int z=0; z<zones; z++) if(zoneIsSupport[z]==isSup && MathAbs(zonePrice[z]-price)<=zoneWidth){ found=z; break; }
      if(found<0 && zones<24){ found=zones; zonePrice[found]=price; zoneCount[found]=0; zoneReject[found]=0; zoneIsSupport[found]=isSup; zones++; }
      if(found>=0){
         zoneCount[found]++;
         double b=MathAbs(rates[i].close-rates[i].open), lw=MathMin(rates[i].open,rates[i].close)-rates[i].low, uw=rates[i].high-MathMax(rates[i].open,rates[i].close);
         if(isSup && lw>b*1.1) zoneReject[found]++;
         if(!isSup && uw>b*1.1) zoneReject[found]++;
      }
   }

   support=0; resistance=0; supportStrength=0; resistanceStrength=0;
   double bestSupDist=DBL_MAX, bestResDist=DBL_MAX;
   for(int z=0; z<zones; z++){
      if(zoneCount[z] < InpSRMinimumTouches) continue;
      int strength=zoneCount[z]+zoneReject[z];
      if(zoneIsSupport[z] && zonePrice[z]<mid){ double d=mid-zonePrice[z]; if(d<bestSupDist || (MathAbs(d-bestSupDist)<zoneWidth && strength>supportStrength)){ bestSupDist=d; support=zonePrice[z]; supportStrength=strength; }}
      if(!zoneIsSupport[z] && zonePrice[z]>mid){ double d=zonePrice[z]-mid; if(d<bestResDist || (MathAbs(d-bestResDist)<zoneWidth && strength>resistanceStrength)){ bestResDist=d; resistance=zonePrice[z]; resistanceStrength=strength; }}
   }
   return (support>0 || resistance>0);
}

bool IsBullishRejection(){ double o=iOpen(InpSymbol,InpTimeframe,1), c=iClose(InpSymbol,InpTimeframe,1), h=iHigh(InpSymbol,InpTimeframe,1), l=iLow(InpSymbol,InpTimeframe,1); double b=MathAbs(c-o), lw=MathMin(o,c)-l, uw=h-MathMax(o,c); return (c>o && lw>b*1.1 && lw>uw); }
bool IsBearishRejection(){ double o=iOpen(InpSymbol,InpTimeframe,1), c=iClose(InpSymbol,InpTimeframe,1), h=iHigh(InpSymbol,InpTimeframe,1), l=iLow(InpSymbol,InpTimeframe,1); double b=MathAbs(c-o), uw=h-MathMax(o,c), lw=MathMin(o,c)-l; return (c<o && uw>b*1.1 && uw>lw); }
TrendDirection GetHigherTimeframeBias(){ double hf[2], hs[2]; if(CopyBuffer(htfFastHandle,0,1,2,hf)<2||CopyBuffer(htfSlowHandle,0,1,2,hs)<2) return TREND_NONE; if(hf[0]>hs[0]) return TREND_BUY; if(hf[0]<hs[0]) return TREND_SELL; return TREND_NONE; }

bool IsBreakoutRetestBuy(double resistance, double zoneWidth){ if(resistance<=0) return false; for(int i=InpBreakoutConfirmCandles+1;i>=2;i--) if(iClose(InpSymbol,InpTimeframe,i)<=resistance) return false; return iLow(InpSymbol,InpTimeframe,1)<=resistance+zoneWidth && iClose(InpSymbol,InpTimeframe,1)>resistance; }
bool IsBreakdownRetestSell(double support, double zoneWidth){ if(support<=0) return false; for(int i=InpBreakoutConfirmCandles+1;i>=2;i--) if(iClose(InpSymbol,InpTimeframe,i)>=support) return false; return iHigh(InpSymbol,InpTimeframe,1)>=support-zoneWidth && iClose(InpSymbol,InpTimeframe,1)<support; }

TrendDirection GetSignal(int &trendStrength){
   trendStrength = 0;
   double f[4],s[4],rsi[2],adx[3],pdi[2],mdi[2],atrB[3];
   if(CopyBuffer(fastHandle,0,0,4,f)<4||CopyBuffer(slowHandle,0,0,4,s)<4||CopyBuffer(rsiHandle,0,0,2,rsi)<2||CopyBuffer(adxHandle,0,0,3,adx)<3||CopyBuffer(adxHandle,1,0,2,pdi)<2||CopyBuffer(adxHandle,2,0,2,mdi)<2||CopyBuffer(atrHandle,0,0,3,atrB)<3) return TREND_NONE;

   double atr=atrB[0], atrPrev=atrB[1]; if(atr<=0||atrPrev<=0) return TREND_NONE;
   double zoneWidth=atr*InpSRZoneWidthATRMultiplier;
   double mid=(SymbolInfoDouble(InpSymbol,SYMBOL_BID)+SymbolInfoDouble(InpSymbol,SYMBOL_ASK))*0.5;

   int buyScore=0, sellScore=0;
   if(f[0]>s[0]) buyScore++; else sellScore++;
   if(f[0]>f[3]) buyScore++; else sellScore++;
   if(pdi[0]>mdi[0]) buyScore++; else sellScore++;
   if(rsi[0]>51) buyScore++; if(rsi[0]<49) sellScore++;
   if(iClose(InpSymbol,InpTimeframe,1)>iOpen(InpSymbol,InpTimeframe,1)) buyScore++; else sellScore++;
   bool atrExpansion = atr > atrPrev*1.02; if(atrExpansion){ buyScore++; sellScore++; }

   bool adxTrend = (adx[0]>=InpADXTrendThreshold) || (adx[0]>=InpADXChopThreshold && adx[0]>adx[1]);
   bool choppy = (adx[0]<InpADXChopThreshold && !atrExpansion && MathAbs(f[0]-s[0])<atr*0.15);

   TrendDirection htf=GetHigherTimeframeBias();
   double support,resistance; int supStr,resStr;
   if(!BuildStrongSRZones(support,supStr,resistance,resStr,zoneWidth)) return TREND_NONE;

   bool nearSupport=(support>0&&MathAbs(mid-support)<=zoneWidth);
   bool nearResistance=(resistance>0&&MathAbs(mid-resistance)<=zoneWidth);

   bool blockBuy=nearResistance; // avoid buying into resistance
   bool blockSell=nearSupport;  // avoid selling into support

   bool buySR = nearSupport && supStr>=InpSRMinimumTouches && IsBullishRejection();
   bool sellSR = nearResistance && resStr>=InpSRMinimumTouches && IsBearishRejection();
   bool buyBO = IsBreakoutRetestBuy(resistance,zoneWidth);
   bool sellBO = IsBreakdownRetestSell(support,zoneWidth);

   if(choppy) return TREND_NONE;

   if(!blockBuy && adxTrend && (buyScore>=4) && htf!=TREND_SELL && (buySR||buyBO)){ trendStrength=buyScore; return TREND_BUY; }
   if(!blockSell && adxTrend && (sellScore>=4) && htf!=TREND_BUY && (sellSR||sellBO)){ trendStrength=sellScore; return TREND_SELL; }
   return TREND_NONE;
}

int AdaptiveBarsCooldown(int trendStrength){
   // stronger trend => smaller cooldown (more trades), weaker trend => larger cooldown (fewer trades)
   if(trendStrength>=6) return 0;
   if(trendStrength>=5) return MathMax(0, InpBaseBarsBetweenTrades-1);
   return InpBaseBarsBetweenTrades+1;
}

bool PlaceOrder(TrendDirection sig,double vol,double slPts,double tpPts){ double point=SymbolInfoDouble(InpSymbol,SYMBOL_POINT); int digits=(int)SymbolInfoInteger(InpSymbol,SYMBOL_DIGITS); double ask=SymbolInfoDouble(InpSymbol,SYMBOL_ASK), bid=SymbolInfoDouble(InpSymbol,SYMBOL_BID); if(sig==TREND_BUY) return trade.Buy(vol,InpSymbol,ask,NormalizeDouble(ask-slPts*point,digits),NormalizeDouble(ask+tpPts*point,digits),"XAU M1 Adaptive Buy"); if(sig==TREND_SELL) return trade.Sell(vol,InpSymbol,bid,NormalizeDouble(bid+slPts*point,digits),NormalizeDouble(bid-tpPts*point,digits),"XAU M1 Adaptive Sell"); return false; }
void ManageTrailingStop(){ if(!InpUseTrailingStop) return; double atr=GetATRValue(); if(atr<=0.0) return; double point=SymbolInfoDouble(InpSymbol,SYMBOL_POINT); int digits=(int)SymbolInfoInteger(InpSymbol,SYMBOL_DIGITS); double trailPts=(atr*InpTrailATRMultiplier)/point; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t==0||!PositionSelectByTicket(t)) continue; if(PositionGetString(POSITION_SYMBOL)!=InpSymbol||PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue; long type=PositionGetInteger(POSITION_TYPE); double tp=PositionGetDouble(POSITION_TP), sl=PositionGetDouble(POSITION_SL); if(type==POSITION_TYPE_BUY){ double bid=SymbolInfoDouble(InpSymbol,SYMBOL_BID); double nsl=NormalizeDouble(bid-trailPts*point,digits); if(sl==0.0||nsl>sl) trade.PositionModify(InpSymbol,nsl,tp);} else if(type==POSITION_TYPE_SELL){ double ask=SymbolInfoDouble(InpSymbol,SYMBOL_ASK); double nsl=NormalizeDouble(ask+trailPts*point,digits); if(sl==0.0||nsl<sl) trade.PositionModify(InpSymbol,nsl,tp);} }}

void OnTick(){
   if(_Symbol!=InpSymbol) return;
   ManageTrailingStop();
   datetime bar=iTime(InpSymbol,InpTimeframe,0); if(bar==0||bar==lastBarTime) return; lastBarTime=bar;

   if(barsCooldown>0) barsCooldown--;
   if(HasOpenPosition()) return;

   CleanupTradeTimes();
   if(!CanOpenNewTrade()) return;

   double atr=GetATRValue(); if(atr<=0.0) return;
   int trendStrength=0;
   TrendDirection sig=GetSignal(trendStrength);
   if(sig==TREND_NONE) return;

   double point=SymbolInfoDouble(InpSymbol,SYMBOL_POINT);
   double slPts=(atr*InpATRSLMultiplier)/point, tpPts=(atr*InpATRTPMultiplier)/point;
   double vol=CalculatePositionSize(slPts); if(vol<=0.0) return;

   if(PlaceOrder(sig,vol,slPts,tpPts)){
      lastTradeTime=TimeCurrent();
      PushTradeTime(lastTradeTime);
      barsCooldown = AdaptiveBarsCooldown(trendStrength);
   }
}
