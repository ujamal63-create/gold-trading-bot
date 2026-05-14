# GoldTradingBot v2.30 (Advanced AI-Style M1 Scalper)

## Important
This EA is for **backtesting and demo testing first**. It is **not** a guarantee of profit.

## Install
1. Copy `GoldTradingBot.mq5` to `MQL5/Experts`.
2. Compile in MetaEditor.
3. Place `GoldTradingBot_Advanced_AI_M1.set` in `MQL5/Profiles/Tester` (optional).
4. Attach EA to `XAUUSD` chart on `M1`.

## Backtest
1. Open Strategy Tester (`Ctrl+R`).
2. Select `GoldTradingBot` + `XAUUSD` + `M1`.
3. Load `GoldTradingBot_Advanced_AI_M1.set` in Inputs.
4. Use high-quality ticks and realistic spread/slippage.

## Strategy Overview
- Market regimes: **Choppy**, **Moderate trend**, **Very strong trend**.
- AI-style confidence score (0–100) with weighted factors:
  - EMA alignment/slope/separation
  - ADX strength + rising/falling
  - DI direction
  - RSI
  - Candle momentum/body-wick profile
  - ATR expansion
  - Tick-volume confirmation
  - Market structure (HH/HL or LH/LL)
  - SR distance and breakout/retest behavior
- SR zones from clustered swing highs/lows with touch/rejection strength ranking.
- In consolidation: SR-only trading (buy support / sell resistance).
- In very strong trend: optional SR bypass when confidence is very high.

## Key Inputs
- `InpRiskPercent`, `InpMaxLot`: position risk and lot cap.
- `InpATRSLMultiplier`, `InpATRTPMultiplier`: dynamic SL/TP tuning.
- `InpUseTrailingStop`, `InpUseBreakEven`: exit management.
- `InpMaxSpreadPoints`: spread filter.
- `InpMaxOpenPositions`: cap simultaneous positions.
- `InpEnableHighConfidenceScaleIn`: strict optional scale-in.
- `InpSRLookbackBars`, `InpSRZoneATRMultiplier`, `InpSRMinimumTouches`: SR quality controls.
- `InpDebugMode`: decision and reason logging in Experts tab.
