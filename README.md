# GoldTradingBot v3.00 (Gold Hedged Range Strategy)

## Important
This Expert Advisor is for **backtesting and demo testing first**. It is **not** a guarantee of profit. The strategy intentionally opens hedged long/short positions, so your MT5 account must support hedging; netting accounts cannot hold both directions at the same time on the same symbol.

## Strategy Overview
GoldTradingBot implements a multi-timeframe, indicator-confirmed range strategy for `XAUUSD`:

- **M15** detects confirmed swing lows and swing highs with a 3-candle left/right fractal window.
- **M5** confirms the range-low bounce with RSI, Stochastic, EMA 8/21, Bollinger Bands, daily VWAP, and ATR.
- **M1** provides the final bullish trigger candle for entry timing.
- On a confirmed range-low setup, the EA opens **one long and one short simultaneously** in equal lot sizes.
- Profitable longs are closed quickly; shorts are held until the total bot basket reaches breakeven/profit.
- At an M15 swing high, the EA closes profitable longs and can add shorts, optionally using sell-limit orders at the swing-high level.

## Install
1. Copy `GoldTradingBot.mq5` to `MQL5/Experts`.
2. Compile in MetaEditor.
3. Place one of the `.set` files in `MQL5/Profiles/Tester` (optional).
4. Attach the EA to a `XAUUSD` **M1** chart.
5. Confirm the account type is **hedging** and automated trading is enabled.

## Backtest
1. Open Strategy Tester (`Ctrl+R`).
2. Select `GoldTradingBot` + `XAUUSD` + `M1`.
3. Load `GoldTradingBot_HedgedRange.set` if desired.
4. Use high-quality real ticks and realistic spread/slippage.
5. Validate broker symbol properties, minimum lot, stop level, and whether hedging is supported.

## Entry Conditions
All enabled filters must pass before opening the hedged pair:

- Current M15 price is within `InpSwingLowBufferATR × ATR(14, M15)` of the latest confirmed M15 swing low.
- M5 RSI(14) is at or below `InpRSIOversold`.
- M5 Stochastic(5,3,3) %K crosses above %D.
- M5 EMA(8) is turning upward and is at/above EMA(21).
- The last closed M1 candle is bullish and rejects the low.
- Optional: M5 price touches the lower Bollinger Band(20,2).
- Optional: price is below daily VWAP for additional range-low confluence.

## Trade Management
- **Range-low entry:** opens one buy and one sell in equal lots.
- **Long management:** any long with at least `InpLongQuickProfitMoney` account-currency profit is closed immediately.
- **Swing-high management:** when price approaches the confirmed M15 swing high buffer and RSI is above `InpRSISwingHigh`, the EA adds shorts only; it does not open new longs at the high.
- **Basket exit:** if open bot positions have aggregate P/L greater than or equal to `InpNetCloseProfitMoney`, all bot positions are closed.
- **Emergency stops:** every market order receives an ATR-based stop (`InpEmergencyStopATR × ATR(14, M15)`).
- **Logging:** the EA writes decision details to the Experts tab and, when enabled, to `GoldTradingBot_HedgedRange_Log.csv` in the common files folder.

## Key Inputs
- `InpSwingWindow`: left/right candle count for M15 swing confirmation.
- `InpMinATR`: minimum M15 ATR required to avoid flat/dead markets.
- `InpRequireLowerBandTouch`, `InpRequireVwapConfluence`, `InpRequireUpperBandAdd`: optional confluence strictness.
- `InpLotSizingMode`, `InpFixedLot`, `InpRiskPercent`, `InpMaxLot`: fixed or equity-risk lot sizing.
- `InpMaxSimultaneousPositions`: hard cap across this EA's positions.
- `InpMaxShortAddsPerCycle`: number of shorts allowed at swing highs per range-low cycle.
- `InpUseSellLimitAtSwingHigh`: use sell-limit orders at the swing-high level instead of immediate market shorts when possible.
- `InpNetCloseProfitMoney`: basket breakeven/profit threshold in account currency.

## Broker Notes
MT5 EAs cannot use IB TWS/IB Gateway directly from MQL5 without an external bridge. This implementation uses native MT5 `CTrade` market, pending-limit, and stop-loss execution equivalents.
