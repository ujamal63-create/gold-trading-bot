# GoldTradingBot v5.00 — XAUUSD M1 Stop-Grid Breakout EA

## Important
This MT5 Expert Advisor is designed for **Strategy Tester backtesting and demo validation before live use**. It is a breakout-grid strategy for XAUUSD M1 and can lose quickly in adverse conditions. The main strategy risk is that choppy markets can trigger both sides of the grid and cause significant drawdown.

## Strategy Overview
`GoldTradingBot.mq5` places a symmetrical stop grid around the current XAUUSD price:

- **Buy Stop orders** are placed above the current Ask.
- **Sell Stop orders** are placed below the current Bid.
- Grid levels use configurable dollar spacing, where `2.00` means a `2.00` XAUUSD price move.
- Lot size can be fixed, pulled from a custom array, or multiplied by tier.
- If one side is triggered, the EA can delete the opposite pending stop orders.
- Basket profit, basket loss, breakeven, trailing stop, daily P/L, spread, session, rollover, Friday close, and max order/trade safeguards are included.

Example with price `2350.00`, spacing `2.00`, four levels, and custom lots `0.01,0.04,0.07,0.10`:

| Level | Buy Stop | Sell Stop | Lot |
| --- | ---: | ---: | ---: |
| 1 | 2352.00 | 2348.00 | 0.01 |
| 2 | 2354.00 | 2346.00 | 0.04 |
| 3 | 2356.00 | 2344.00 | 0.07 |
| 4 | 2358.00 | 2342.00 | 0.10 |

## Core Logic
1. On each new M1 candle and every timer event, the EA checks whether it has any active positions or pending stop orders for the configured symbol and magic number.
2. If no EA grid is active and filters pass, it places a fresh Buy Stop / Sell Stop grid.
3. All position and order management is filtered by `InpMagicNumber` and `InpSymbol`, so manual trades and other EAs are ignored.
4. If basket TP, basket SL, or daily limits are reached, the EA closes its positions and deletes its pending orders.
5. If breakeven or trailing stop is enabled, profitable positions are protected with server-side stop-loss updates.

## Key Inputs
- **Symbol/magic:** `InpSymbol`, `InpMagicNumber`.
- **Grid:** `InpGridSpacingDollars`, `InpGridLevels`, `InpPendingOrderExpiryMinutes`.
- **Lots:** `InpBaseLot`, `InpLotStepMode`, `InpCustomLots`, `InpMultiplier`.
- **Per-order exits:** `InpStopLossDollars`, `InpTakeProfitDollars`.
- **Basket exits:** `InpUseBasketTP`, `InpBasketProfitMoney`, `InpUseBasketSL`, `InpBasketLossMoney`.
- **Protection:** `InpUseTrailingStop`, `InpTrailingStartDollars`, `InpTrailingDistanceDollars`, `InpUseBreakEven`, `InpBreakEvenStartDollars`, `InpBreakEvenLockDollars`.
- **Safety:** `InpMaxSpreadPoints`, `InpSlippagePoints`, `InpMaxOpenTrades`, `InpMaxPendingOrders`, `InpMaxDailyLossMoney`, `InpMaxDailyProfitMoney`.
- **Time filters:** `InpTradingStartHour`, `InpTradingEndHour`, `InpAvoidRollover`, `InpRolloverStartHour`, `InpRolloverEndHour`, `InpFridayCloseHour`.

## Suggested XAUUSD M1 Starting Settings
These are starting points only. Optimize and validate with your broker's spread, commissions, stop levels, tick value, and execution quality:

- `InpGridSpacingDollars = 2.0` to `3.0`.
- `InpGridLevels = 3` to `5`.
- `InpLotStepMode = CustomArray`.
- `InpCustomLots = "0.01,0.04,0.07,0.10"` for small-account demo testing, adjusted downward if risk is too high.
- `InpDeleteOppositePendingsAfterTrigger = true` to reduce two-sided whipsaw exposure.
- `InpMaxSpreadPoints = 50` to `100`, depending on the broker's XAUUSD point size.
- `InpUseBasketTP = true` with a modest target such as `15` to `50` account-currency units.
- `InpUseBasketSL = true`; set the limit to an amount you are willing to lose in one basket.
- Keep `InpAvoidRollover = true`, and avoid low-liquidity rollover periods.

## Installation and Backtesting
1. Copy `GoldTradingBot.mq5` into `MQL5/Experts`.
2. Compile it in MetaEditor.
3. Attach it to an `XAUUSD` or broker-specific gold-symbol M1 chart. If needed, change `InpSymbol` to the broker's exact symbol.
4. In Strategy Tester, use M1 with real ticks, realistic spread, swaps, commissions, and slippage.
5. Confirm broker stop-level, freeze-level, volume-step, min-lot, max-lot, and trading-hour constraints before live use.
6. Run out-of-sample tests and demo-forward tests before considering any live deployment.
