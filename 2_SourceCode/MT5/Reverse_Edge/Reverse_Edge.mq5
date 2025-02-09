//+------------------------------------------------------------------+
//|                                                     Reverse_Edge |
//|                        Copyright 2025, Your Name                 |
//|                                       https://www.example.com    |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade;

//–––––– Input Parameters ––––––
input double   RiskPercent          = 1.0;           // Risk percentage per trade
input double   RRR_Initial          = 3.0;           // Initial Risk Reward Ratio (TP = 3 x SL)
input double   RRR_Final            = 10.0;          // Final Risk Reward Ratio after partial close
input bool     ShowVisualIndicators = true;          // Show on-chart visual indicators
input string   EA_Name              = "Reverse_Edge"; // EA Name displayed on chart
input double   StopLossPips         = 20.0;          // Stop loss in pips (used to calculate lot size)

// Indicator settings for MACD, RSI, and Stochastic:
input int      FastEMA              = 12;
input int      SlowEMA              = 26;
input int      SignalSMA            = 9;
input int      RSI_Period           = 14;
input int      K_Period             = 14;
input int      D_Period             = 3;

//–––––– Global Variables ––––––
int    lastTradeDay = -1;   // Unique day identifier (YYYYMMDD) to allow only one trade per day
ulong  currentTicket = 0;   // Ticket number as an unsigned 64-bit integer
bool   partialClosed = false; // Flag to ensure one partial close per trade

// Names for chart objects
string objBalance    = "objBalance";
string objDrawdown   = "objDrawdown";
string objBrokerTime = "objBrokerTime";
string objEAName     = "objEAName";
string objPositions  = "objPositions";
string objLogStatus  = "objLogStatus";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Create visual objects if enabled
   if(ShowVisualIndicators)
      CreateChartObjects();
   PrintLog("Initialized.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Remove chart objects on deinitialization.
   if(ShowVisualIndicators)
      // Remove all label objects from subwindow 0.
      ObjectsDeleteAll(0, (int)OBJ_LABEL, 0);
   PrintLog("Deinitialized.");
}

//+------------------------------------------------------------------+
//| Create chart objects for visual indicators                       |
//+------------------------------------------------------------------+
void CreateChartObjects()
{
   // Create a series of label objects on the top left corner.
   if(!ObjectFind(0, objBalance))
   {
      ObjectCreate(0, objBalance, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objBalance, OBJPROP_CORNER, 0);
      ObjectSetInteger(0, objBalance, OBJPROP_YDISTANCE, 20);
   }
   if(!ObjectFind(0, objDrawdown))
   {
      ObjectCreate(0, objDrawdown, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objDrawdown, OBJPROP_CORNER, 0);
      ObjectSetInteger(0, objDrawdown, OBJPROP_YDISTANCE, 40);
   }
   if(!ObjectFind(0, objBrokerTime))
   {
      ObjectCreate(0, objBrokerTime, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objBrokerTime, OBJPROP_CORNER, 0);
      ObjectSetInteger(0, objBrokerTime, OBJPROP_YDISTANCE, 60);
   }
   if(!ObjectFind(0, objEAName))
   {
      ObjectCreate(0, objEAName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objEAName, OBJPROP_CORNER, 0);
      ObjectSetInteger(0, objEAName, OBJPROP_YDISTANCE, 80);
   }
   if(!ObjectFind(0, objPositions))
   {
      ObjectCreate(0, objPositions, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objPositions, OBJPROP_CORNER, 0);
      ObjectSetInteger(0, objPositions, OBJPROP_YDISTANCE, 100);
   }
   if(!ObjectFind(0, objLogStatus))
   {
      ObjectCreate(0, objLogStatus, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objLogStatus, OBJPROP_CORNER, 0);
      ObjectSetInteger(0, objLogStatus, OBJPROP_YDISTANCE, 120);
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Update on-chart objects if enabled.
   if(ShowVisualIndicators)
      UpdateChartObjects();

   // Get the current broker time and break it into components.
   datetime currentTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);

   // If it is Friday (day_of_week == 5) and hour is 21 or later, close all trades.
   if(dt.day_of_week == 5 && dt.hour >= 21)
   {
      CloseAllTrades();
      PrintLog("It is Friday 21:00 or later. Closed all trades.");
      return;
   }

   // Calculate a unique number for today's date as YYYYMMDD.
   int currentDate = dt.year * 10000 + dt.mon * 100 + dt.day;
   // Ensure only one trade per day.
   if(lastTradeDay == currentDate)
   {
      // If already traded today, manage any open trade (partial TP, etc.)
      if(PositionSelect(_Symbol))
         ManageOpenTrade();
      return;
   }

   // If no position exists, check for a new trade signal.
   if(!PositionSelect(_Symbol))
   {
      int signal = CheckTradeSignal(); // 1 for buy, -1 for sell, 0 for no signal.
      if(signal != 0)
      {
         // Determine entry price based on signal direction.
         double entryPrice = (signal == 1 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                          : SymbolInfoDouble(_Symbol, SYMBOL_BID));

         // Calculate Stop Loss and initial Take Profit levels.
         // For a Buy order: SL = entry - (StopLossPips * point),
         // TP = entry + (RRR_Initial * StopLossPips * point)
         // For a Sell order: SL = entry + (StopLossPips * point),
         // TP = entry - (RRR_Initial * StopLossPips * point)
         double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double stopLossPrice = 0.0, takeProfitPrice = 0.0;
         if(signal == 1)
         {
            stopLossPrice   = entryPrice - StopLossPips * point;
            takeProfitPrice = entryPrice + RRR_Initial * StopLossPips * point;
         }
         else // signal == -1
         {
            stopLossPrice   = entryPrice + StopLossPips * point;
            takeProfitPrice = entryPrice - RRR_Initial * StopLossPips * point;
         }

         // Calculate lot size based on risk and the stop loss distance.
         double lotSize = CalculateLotSize(StopLossPips);
         if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
         {
            PrintLog(StringFormat("Calculated lot size (%.2f) is below the minimum allowed. Trade not opened.", lotSize));
            return;
         }

         // Open the trade.
         bool orderResult = false;
         if(signal == 1)
            orderResult = trade.Buy(lotSize, NULL, entryPrice, stopLossPrice, takeProfitPrice, "Reverse_Edge Buy");
         else
            orderResult = trade.Sell(lotSize, NULL, entryPrice, stopLossPrice, takeProfitPrice, "Reverse_Edge Sell");

         if(orderResult)
         {
            lastTradeDay = currentDate;
            currentTicket = trade.ResultOrder(); // currentTicket is now of type ulong.
            partialClosed = false;
            // Use StringFormat with %I64u to print the unsigned 64-bit ticket.
            PrintLog(StringFormat("Trade opened. Ticket: %I64u, Direction: %s | Entry: %.*f | SL: %.*f | TP: %.*f",
                                   currentTicket,
                                   (signal == 1 ? "Buy" : "Sell"),
                                   _Digits, entryPrice,
                                   _Digits, stopLossPrice,
                                   _Digits, takeProfitPrice));
         }
         else
         {
            PrintLog("Trade opening failed.");
         }
      }
   }
   else
   {
      // If a position exists, check if conditions for partial close / TP update are met.
      ManageOpenTrade();
   }
}

//+------------------------------------------------------------------+
//| Check Trade Signal based on "reversed" indicators                |
//+------------------------------------------------------------------+
int CheckTradeSignal()
{
   // --- MACD Calculation ---
   int macdHandle = iMACD(_Symbol, _Period, FastEMA, SlowEMA, SignalSMA, PRICE_CLOSE);
   if(macdHandle == INVALID_HANDLE)
   {
      PrintLog("Failed to get MACD handle.");
      return 0;
   }
   double macdMainBuffer[1], macdSignalBuffer[1];
   if(CopyBuffer(macdHandle, 0, 1, 1, macdMainBuffer) <= 0)
   {
      PrintLog("Failed to copy MACD main buffer.");
      IndicatorRelease(macdHandle);
      return 0;
   }
   if(CopyBuffer(macdHandle, 1, 1, 1, macdSignalBuffer) <= 0)
   {
      PrintLog("Failed to copy MACD signal buffer.");
      IndicatorRelease(macdHandle);
      return 0;
   }
   double macdMainVal   = macdMainBuffer[0];
   double macdSignalVal = macdSignalBuffer[0];
   IndicatorRelease(macdHandle);
   
   // Reversed logic: if MACD main is less than signal then consider bullish (1), else bearish (-1).
   int macdDir = (macdMainVal < macdSignalVal) ? 1 : -1;

   // --- RSI Calculation ---
   int rsiHandle = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);
   if(rsiHandle == INVALID_HANDLE)
   {
      PrintLog("Failed to get RSI handle.");
      return 0;
   }
   double rsiBuffer[1];
   if(CopyBuffer(rsiHandle, 0, 1, 1, rsiBuffer) <= 0)
   {
      PrintLog("Failed to copy RSI buffer.");
      IndicatorRelease(rsiHandle);
      return 0;
   }
   double rsiValue = rsiBuffer[0];
   IndicatorRelease(rsiHandle);

   // Reversed logic: if RSI > 70 then bullish, if RSI < 30 then bearish, else neutral.
   int rsiDir = 0;
   if(rsiValue > 70)
      rsiDir = 1;
   else if(rsiValue < 30)
      rsiDir = -1;

   // --- Stochastic Calculation ---
   // In MQL5, iStochastic returns a handle. Buffer 0 is %K.
   int stochHandle = iStochastic(_Symbol, _Period, K_Period, D_Period, 3, MODE_SMA, STO_LOWHIGH);
   if(stochHandle == INVALID_HANDLE)
   {
      PrintLog("Failed to get Stochastic handle.");
      return 0;
   }
   double stochBuffer[1];
   if(CopyBuffer(stochHandle, 0, 1, 1, stochBuffer) <= 0)
   {
      PrintLog("Failed to copy Stochastic buffer.");
      IndicatorRelease(stochHandle);
      return 0;
   }
   double stochK = stochBuffer[0];
   IndicatorRelease(stochHandle);

   // Reversed logic: if %K > 80 then bullish, if %K < 20 then bearish, else neutral.
   int stochDir = 0;
   if(stochK > 80)
      stochDir = 1;
   else if(stochK < 20)
      stochDir = -1;

   // Log the indicator directions.
   PrintLog(StringFormat("Indicators => MACD: %d, RSI: %d, Stochastic: %d", macdDir, rsiDir, stochDir));

   // If all indicators agree (non-zero) then return that signal; otherwise, no signal.
   if(macdDir == rsiDir && rsiDir == stochDir && macdDir != 0)
      return macdDir;
   else
      return 0;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk and stop loss pips              |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLossPips)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount     = accountBalance * (RiskPercent / 100.0);
   // For a rough approximation, assume 1 standard lot yields ~$10 per pip.
   double pipValuePerLot = 10.0;
   double point          = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   // Lot size is riskAmount divided by the monetary risk per pip.
   double lotSize = riskAmount / (stopLossPips * point * pipValuePerLot);
   lotSize = NormalizeDouble(lotSize, 2);
   return lotSize;
}

//+------------------------------------------------------------------+
//| Manage an open trade: partial close at 1:3 RRR and update TP       |
//+------------------------------------------------------------------+
void ManageOpenTrade()
{
   if(!PositionSelect(_Symbol))
      return;

   // Get current position details.
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double volume     = PositionGetDouble(POSITION_VOLUME);
   // Explicitly cast to int to avoid conversion warnings.
   int posType = (int)PositionGetInteger(POSITION_TYPE);
   double currentPrice = (posType == POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                       : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Calculate profit target distances in price terms.
   double profitTargetInitial = RRR_Initial * StopLossPips * point;
   double profitTargetFinal   = RRR_Final   * StopLossPips * point;

   bool triggerPartial = false;
   if(posType == POSITION_TYPE_BUY && (currentPrice - entryPrice >= profitTargetInitial))
      triggerPartial = true;
   else if(posType == POSITION_TYPE_SELL && (entryPrice - currentPrice >= profitTargetInitial))
      triggerPartial = true;

   if(triggerPartial && !partialClosed)
   {
      // Partial close: close 50% of the volume.
      double volumeToClose = volume * 0.5;
      if(trade.PositionClosePartial(_Symbol, volumeToClose))
      {
         PrintLog(StringFormat("Executed partial close of %.2f lots.", volumeToClose));
         // Update the TP for the remaining position to the final target.
         double newTP = 0.0;
         if(posType == POSITION_TYPE_BUY)
            newTP = entryPrice + profitTargetFinal;
         else if(posType == POSITION_TYPE_SELL)
            newTP = entryPrice - profitTargetFinal;
         if(trade.PositionModify(_Symbol, PositionGetDouble(POSITION_SL), newTP))
         {
            PrintLog(StringFormat("Modified remaining position: new TP = %.*f", _Digits, newTP));
         }
         else
         {
            PrintLog("Failed to modify the remaining position.");
         }
         partialClosed = true;
      }
      else
      {
         PrintLog("Partial close failed.");
      }
   }
}

//+------------------------------------------------------------------+
//| Close all open trades (used on Friday after 21:00)               |
//+------------------------------------------------------------------+
void CloseAllTrades()
{
   if(PositionSelect(_Symbol))
   {
      if(!trade.PositionClose(_Symbol))
         PrintLog(StringFormat("Failed to close position for %s", _Symbol));
      else
         PrintLog(StringFormat("Position closed for %s", _Symbol));
   }
}

//+------------------------------------------------------------------+
//| Update chart objects with account and status information         |
//+------------------------------------------------------------------+
void UpdateChartObjects()
{
   string balanceText    = StringFormat("Balance: %.2f", AccountInfoDouble(ACCOUNT_BALANCE));
   string drawdownText   = StringFormat("Drawdown: %.2f", AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE));
   string brokerTimeText = StringFormat("Broker Time: %s", TimeToString(TimeCurrent(), TIME_SECONDS));
   string eaNameText     = "EA: " + EA_Name;
   string positionsText  = StringFormat("Open Positions: %d", PositionsTotal());
   string logText        = "Status: Running";

   ObjectSetString(0, objBalance,    OBJPROP_TEXT, balanceText);
   ObjectSetString(0, objDrawdown,   OBJPROP_TEXT, drawdownText);
   ObjectSetString(0, objBrokerTime, OBJPROP_TEXT, brokerTimeText);
   ObjectSetString(0, objEAName,     OBJPROP_TEXT, eaNameText);
   ObjectSetString(0, objPositions,  OBJPROP_TEXT, positionsText);
   ObjectSetString(0, objLogStatus,  OBJPROP_TEXT, logText);
}

//+------------------------------------------------------------------+
//| Custom logging function                                          |
//+------------------------------------------------------------------+
void PrintLog(string message)
{
   Print("[", EA_Name, "] ", message);
}
