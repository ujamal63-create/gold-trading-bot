# GoldTradingBot v4.00 — XAUUSD Fractal Continuation Scalper

## Important
This MT5 Expert Advisor is designed for **Strategy Tester backtesting and demo validation before live use**. Its filters aim to improve signal quality, but no algorithm can guarantee a win rate or profitability. Broker execution, symbol specifications, spread, slippage, data quality, session times, and market regime materially affect results.

## Strategy Overview
`GoldTradingBot.mq5` is an M1-entry XAUUSD/GOLD scalper based on confirmed Williams Fractals and multi-timeframe trend continuation:

- **M1 entries:** confirmed Williams Fractals, EMA 50, RSI 14, ATR 14, and breakout execution.
- **M5 trend confirmation:** EMA 200 and ADX 14.
- **M15 structure filter:** avoids buys close to recent resistance and sells close to recent support.
- **Execution safeguards:** spread, liquidity-session, trade-frequency, direction-exposure, daily P/L, and optional MT5 economic-calendar filters.

The EA uses only Williams Fractals starting at shift `2`. A fractal therefore has two completed bars to its right and is confirmed before it can be consumed as a signal.

## Entry Logic
### Buy
A buy requires all of the following:

1. Last closed M5 candle is above EMA 200.
2. Last closed M1 candle is above EMA 50.
3. M5 ADX is at or above the configured minimum (default `20`).
4. M1 RSI is within the buy range (default `45–70`).
5. A confirmed bullish (lower) M1 fractal exists and has not already been consumed by a buy.
6. Ask price breaks above the most recent confirmed bearish (upper) M1 fractal.
7. ATR, spread, session, frequency, daily-limit, optional news, and optional M15 resistance filters pass.
8. No EA sell is open. One EA buy is allowed unless pyramiding is enabled.

### Sell
The sell path is symmetrical: price must be below both EMAs, RSI must be within the sell range (default `30–55`), a fresh confirmed bearish fractal must exist, and bid must break below the latest confirmed bullish fractal while every safeguard passes.

## Stops, Targets, and Position Management
- Buy SL: latest confirmed bullish fractal low minus `InpATRStopBuffer × ATR`.
- Sell SL: latest confirmed bearish fractal high plus `InpATRStopBuffer × ATR`.
- Configurable minimum and maximum SL distances are expressed in symbol points.
- Final server-side TP defaults to `1.5R`.
- At `1R`, the EA optionally partially closes the configured volume percentage, moves SL to breakeven, and/or begins ATR trailing.
- Optional opposite-fractal exit can close positions after a newly confirmed opposite fractal appears.
- Position selection always checks both magic number and configured symbol.

## Session and News Notes
Session inputs use the **broker server time** visible to the EA. Defaults cover London (`07:00–12:00`) and New York (`12:30–17:00`). Asian trading is disabled by default and can be enabled only with a stronger ATR requirement.

The optional news filter uses MT5's economic calendar for high-impact events affecting `InpNewsCurrency` (default `USD`). It is disabled by default because calendar availability can differ between terminals and tester environments. If enabled and calendar lookup fails, the EA blocks new entries for safety.

## Installation and Backtesting
1. Copy `GoldTradingBot.mq5` into `MQL5/Experts`.
2. Compile it in MetaEditor.
3. Attach it to an `XAUUSD` or broker-specific gold-symbol M1 chart. If needed, change `InpSymbol` to the broker's exact symbol.
4. In Strategy Tester, select M1 and use real ticks with realistic spread and commissions.
5. Validate symbol point size, tick value, stops level, lot step, session offsets, and input thresholds against the broker's contract.
6. Run out-of-sample tests and demo-forward tests before considering live use.

## Key Inputs
- **Sizing:** `InpLotMode`, `InpFixedLot`, `InpRiskPercent`, `InpMaxLot`.
- **Indicators:** `InpM5EMA200Period`, `InpM1EMA50Period`, `InpRSIPeriod`, RSI bounds, `InpADXPeriod`, `InpMinADX`, `InpATRPeriod`, `InpMinATR`.
- **Execution:** `InpATRStopBuffer`, SL point limits, `InpMaxSpreadPoints`, `InpMaxTradesPerDay`, `InpMinMinutesBetweenTrades`, `InpEnablePyramiding`.
- **Daily limits:** `InpDailyLossLimitPercent`, `InpDailyProfitTargetPercent`.
- **Sessions:** London, New York, and optional Asian server-time ranges.
- **Accuracy filters:** M5 EMA distance, optional M15 structure filter, optional high-impact news filter.
- **Management:** final TP RR, TP1 partial close, breakeven, ATR trailing, and opposite-fractal exit.

## Chart Status
The chart comment displays M5 trend direction, latest confirmed bullish and bearish fractal levels, spread, ADX, RSI, ATR, trades today, and the EA's current daily realized-plus-floating P/L.
