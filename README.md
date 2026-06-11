# GoldTradingBot v5.10 — XAUUSD M1/M5 Stop-Grid Breakout EA

## Important
This MT5 Expert Advisor is designed for **Strategy Tester backtesting and demo validation before live use**. It is a breakout stop-grid strategy for XAUUSD M1/M5 and can lose quickly in adverse conditions. The main strategy risk is that choppy markets and news spikes can trigger multiple stop-grid levels quickly, sometimes on both sides, causing drawdown and slippage.

## Improved EA Logic
`GoldTradingBot.mq5` places a filtered stop grid around the current XAUUSD price:

- **Buy Stop orders** are placed above the current Ask when the optional EMA trend filter allows buys.
- **Sell Stop orders** are placed below the current Bid when the optional EMA trend filter allows sells.
- Grid levels use configurable fixed price spacing, where `2.00` means a `2.00` XAUUSD price move.
- Lot size can be fixed, pulled from a conservative custom array, or multiplied by tier.
- ATR and ADX filters avoid opening grids in very quiet chop, excessive spike volatility, or weak directional conditions.
- If one side is triggered, the EA can delete the opposite pending stop orders.
- Basket TP, basket SL, basket trailing profit, breakeven, per-position trailing, daily limits, spread limits, rollover avoidance, Friday close handling, and choppy-market pauses are included.
- All order and position management is filtered by `InpSymbol` and `InpMagicNumber`, so manual trades and other EA trades are ignored.

Example with price `2350.00`, spacing `2.00`, four levels, and custom lots `0.01,0.03,0.05,0.07`:

| Level | Buy Stop | Sell Stop | Lot |
| --- | ---: | ---: | ---: |
| 1 | 2352.00 | 2348.00 | 0.01 |
| 2 | 2354.00 | 2346.00 | 0.03 |
| 3 | 2356.00 | 2344.00 | 0.05 |
| 4 | 2358.00 | 2342.00 | 0.07 |

## Key Inputs
- **Symbol/magic:** `InpSymbol`, `InpMagicNumber`.
- **Grid:** `InpGridSpacingDollars`, `InpGridLevels`, `InpPendingOrderExpiryMinutes`.
- **Lots:** `InpBaseLot`, `InpLotStepMode`, `InpCustomLots`, `InpMultiplier`.
- **Per-order exits:** `InpStopLossDollars`, `InpTakeProfitDollars`.
- **Basket exits:** `InpUseBasketTP`, `InpBasketProfitMoney`, `InpUseBasketSL`, `InpBasketLossMoney`.
- **Basket trailing:** `InpUseBasketTrailing`, `InpBasketTrailStartMoney`, `InpBasketTrailDistanceMoney`.
- **Position protection:** `InpUseTrailingStop`, `InpTrailingStartDollars`, `InpTrailingDistanceDollars`, `InpUseBreakEven`, `InpBreakEvenStartDollars`, `InpBreakEvenLockDollars`.
- **Trend filter:** `InpUseTrendFilter`, `InpTrendTimeframe`, `InpTrendEMAPeriod`.
- **ATR filter:** `InpUseATRFilter`, `InpATRTimeframe`, `InpATRPeriod`, `InpMinATR`, `InpMaxATR`.
- **ADX filter:** `InpUseADXFilter`, `InpADXTimeframe`, `InpADXPeriod`, `InpMinADX`.
- **Chop protection:** `InpUseChopProtection`, `InpMaxOppositeTriggers`, `InpChopLookbackMinutes`, `InpPauseAfterChopMinutes`.
- **Safety:** `InpMaxSpreadPoints`, `InpSlippagePoints`, `InpMaxOpenTrades`, `InpMaxPendingOrders`, `InpMaxDailyLossMoney`, `InpMaxDailyProfitMoney`, `InpCloseTradesOnDailyLoss`.
- **Time filters:** `InpTradingStartHour`, `InpTradingEndHour`, `InpAvoidRollover`, `InpRolloverStartHour`, `InpRolloverEndHour`, `InpFridayCloseHour`.

## Recommended Default Style
Use a conservative configuration first:

- Conservative custom lot progression, such as `0.01,0.03,0.05,0.07,0.10`.
- `InpDeleteOppositePendingsAfterTrigger = true`.
- `InpUseTrendFilter = true` with EMA 200 on M5 or M15.
- `InpUseATRFilter = true` to avoid low-volatility chop and high-volatility news spikes.
- `InpUseADXFilter = true` to require directional strength.
- `InpUseBasketTP = true`, `InpUseBasketSL = true`, and `InpUseBasketTrailing = true`.
- `InpAvoidRollover = true` and avoid Friday late trading.

## Suggested XAUUSD M1 Starting Settings
These are starting points only. Optimize and validate with your broker's spread, commissions, stop levels, tick value, and execution quality:

- `InpGridSpacingDollars = 2.0` or `2.5`.
- `InpGridLevels = 4` to `5`.
- `InpCustomLots = "0.01,0.03,0.05,0.07,0.10"`.
- `InpMaxOpenTrades = 5` to `6`.
- `InpMaxPendingOrders = 8` to `10`.
- `InpBasketProfitMoney = 20` to `40` per $10,000 test balance.
- `InpBasketLossMoney = 50` to `80` per $10,000 test balance.
- `InpBasketTrailStartMoney = 15` to `25`.
- `InpBasketTrailDistanceMoney = 6` to `12`.
- `InpTrendTimeframe = PERIOD_M5`, `InpTrendEMAPeriod = 200`.
- `InpATRTimeframe = PERIOD_M5`, `InpMinATR = 0.60`, `InpMaxATR = 8.00`.
- `InpADXTimeframe = PERIOD_M5`, `InpMinADX = 18` to `25`.
- Trade liquid sessions only if your broker's rollover/spread behavior is poor.

## Suggested XAUUSD M5 Starting Settings
For M5, use slightly wider spacing and fewer levels to reduce whipsaw exposure:

- `InpGridSpacingDollars = 2.5` to `4.0`.
- `InpGridLevels = 3` to `5`.
- `InpCustomLots = "0.01,0.02,0.04,0.06,0.08"` or `"0.01,0.03,0.05,0.07,0.10"`.
- `InpBasketProfitMoney = 25` to `60` per $10,000 test balance.
- `InpBasketLossMoney = 60` to `120` per $10,000 test balance.
- `InpTrendTimeframe = PERIOD_M15` where possible.
- `InpATRTimeframe = PERIOD_M15`, with optimized `InpMinATR` and `InpMaxATR` based on broker data.
- `InpADXTimeframe = PERIOD_M15`, `InpMinADX = 18` to `28`.

## Optimization Plan
Optimize for quality, not just net profit. Rank parameter sets by:

1. Profit Factor.
2. Max equity drawdown.
3. Recovery Factor.
4. Expected Payoff.
5. Smoothness of equity curve.
6. Number of trades.

Optimize these inputs first:

- Grid spacing: `1.5`, `2.0`, `2.5`, `3.0`, `4.0`.
- Grid levels: `3` to `7`.
- Conservative custom lot arrays.
- Basket TP and basket SL.
- Basket trailing start and distance.
- Per-position trailing start and distance.
- ATR minimum and maximum.
- ADX minimum.
- Trading hours.
- Rollover avoidance window.

Avoid any setting that has:

- Profit Factor below `1.30`.
- Equity drawdown above `10%`.
- Very low trade count.
- One or two lucky profit spikes.
- Huge lot exposure.
- High sensitivity to spread or slippage.

## Backtesting Properly
1. Copy `GoldTradingBot.mq5` into `MQL5/Experts` and compile in MetaEditor.
2. Attach or test it on the broker's exact gold symbol, for example `XAUUSD`, `GOLD`, or `XAUUSDm`, and update `InpSymbol` accordingly.
3. In Strategy Tester, use **Every tick based on real ticks** with 100% history quality where possible.
4. Include realistic commission, swap, and execution assumptions.
5. Test with realistic spread or variable real-tick spread, then repeat with intentionally worse spread to check sensitivity.
6. Use realistic slippage assumptions through `InpSlippagePoints`; then stress-test higher values.
7. Run in-sample and out-of-sample tests, then demo-forward test before considering live use.
8. Do not accept settings that only improve net profit by increasing exposure or relying on rare lucky spikes.
