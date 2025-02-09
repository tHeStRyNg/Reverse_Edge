//+------------------------------------------------------------------+
//|                        Reverse_Edge                              |
//|                        Copyright 2025, ALGORITHMIC GmbH          |
//|                        https://www.algorithmic.one               |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade;

//–––––– Input Parameters ––––––
input double   RiskPercent         = 1.0;           // Risk percentage per trade
input double   RRR_Initial         = 3.0;           // Initial Risk Reward Ratio (TP = 3 x SL)
input double   RRR_Final           = 10.0;          // Final Risk Reward Ratio after partial close
input bool     ShowVisualIndicators= true;          // Show on-chart visual indicators
input string   EA_Name             = "Reverse_Edge"; // EA Name displayed on chart
input double   StopLossPips        = 20.0;          // Stop loss in pips (used to calculate lot size)

// Indicator settings for MACD, RSI, and Stochastic:
input int      FastEMA             = 12;
input int      SlowEMA             = 26;
input int      SignalSMA           = 9;
input int      RSI_Period          = 14;
input int      K_Period            = 14;
input int      D_Period            = 3;

//–––––– Global Variables ––––––
int    lastTradeDay = -1;   // To ensure only one trade per day
ulong  currentTicket= 0;
bool   partialClosed= false; // Flag to ensure one partial close per trade

// Names for chart objects
string objBalance   = "objBalance";
string objDrawdown  = "objDrawdown";
string objBrokerTime= "objBrokerTime";
string objEAName    = "objEAName";
string objPositions = "objPositions";
string objLogStatus = "objLogStatus";

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
   // Remove chart objects on deinitialization
   if(ShowVisualIndicators)
      ObjectsDeleteAll(0, OBJ_LABEL);
   PrintLog("Deinitialized.");
}

//+------------------------------------------------------------------+
//| Create chart objects for visual indicators                       |
//+------------------------------------------------------------------+
void CreateChartObjects()
{
   // Create a series of label objects on the top left corner
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
   // Update on-chart objects if enabled
   if(ShowVisualIndicators)
      UpdateChartObjects();

   // Check if it is Friday 21:00 or later (broker time) and close all positions
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   if(dt.day_of_week == 5 && dt.hour >= 21)
   {
      CloseAllTrades();
      PrintLog("It is Friday 21:00 or later. Closed all trades.");
      return;
   }

   // Ensure only one trade is taken per day
   int currentDay = TimeDay(now);
   if(lastTradeDay == currentDay)
   {
      // If already traded today, manage any open trade (partial TP, etc.)
      if(PositionSelect(_Symbol))
         ManageOpenTrade();
      return;
   }

   // If no position exists, check for a new trade signal
   if(!PositionSelect(_Symbol))
   {
      int signal = CheckTradeSignal(); // 1 for buy, -1 for sell, 0 for no signal
      if(signal != 0)
      {
         // Determine entry price based on signal direction
         double entryPrice = (signal == 1 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                          : SymbolInfoDouble(_Symbol, SYMBOL_BID));

         // Calculate Stop Loss and initial Take Profit levels.
         // For a Buy order: SL = entry - (StopLossPips * point), TP = entry + (RRR_Initial * StopLossPips * point)
         // For a Sell order:  SL = entry + (StopLossPips * point), TP = entry - (RRR_Initial * StopLossPips * point)
         double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double stopLossPrice = 0.0, takeProfitPrice = 0.0;
         if(signal == 1)
         {
            stopLossPrice  = entryPrice - StopLossPips * point;
            takeProfitPrice= entryPrice + RRR_Initial * StopLossPips * point;
         }
         else // signal == -1
         {
            stopLossPrice  = entryPrice + StopLossPips * point;
            takeProfitPrice= entryPrice - RRR_Initial * StopLossPips * point;
         }

         // Calculate lot size based on risk and the stop loss distance (StopLossPips)
         double lotSize = CalculateLotSize(StopLossPips);
         if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
         {
            PrintLog("Calculated lot size (" + DoubleToString(lotSize,2) + ") is below the minimum allowed. Trade not opened.");
            return;
         }

         // Open the trade
         bool orderResult = false;
         if(signal == 1)
            orderResult = trade.Buy(lotSize, NULL, entryPrice, stopLossPrice, takeProfitPrice, "Reverse_Edge Buy");
         else
            orderResult = trade.Sell(lotSize, NULL, entryPrice, stopLossPrice, takeProfitPrice, "Reverse_Edge Sell");

         if(orderResult)
         {
            lastTradeDay = currentDay;
            currentTicket = trade.ResultOrder();
            partialClosed = false;
            PrintLog("Trade opened. Ticket: " + IntegerToString(currentTicket) +
                     " Direction: " + (signal==1?"Buy":"Sell") +
                     " | Entry: " + DoubleToString(entryPrice,_Digits) +
                     " | SL: " + DoubleToString(stopLossPrice,_Digits) +
                     " | TP: " + DoubleToString(takeProfitPrice,_Digits));
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
   double macdMain, macdSignal;
   // Get the previous bar's MACD values (index=1)
   if(ArraySize(iMACD(_Symbol, _Period, FastEMA, SlowEMA, SignalSMA, PRICE_CLOSE, MODE_MAIN))<2 ||
      ArraySize(iMACD(_Symbol, _Period, FastEMA, SlowEMA, SignalSMA, PRICE_CLOSE, MODE_SIGNAL))<2)
   {
      PrintLog("Not enough MACD data.");
      return 0;
   }
   macdMain   = iMACD(_Symbol, _Period, FastEMA, SlowEMA, SignalSMA, PRICE_CLOSE, MODE_MAIN, 1);
   macdSignal = iMACD(_Symbol, _Period, FastEMA, SlowEMA, SignalSMA, PRICE_CLOSE, MODE_SIGNAL, 1);
   // Reversed logic: if MACD main is less than signal then consider that bullish (1), else bearish (-1)
   int macdDir = (macdMain < macdSignal) ? 1 : -1;

   // --- RSI Calculation ---
   double rsiValue = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE, 1);
   // Reversed: if RSI > 70 then bullish, if RSI < 30 then bearish, else neutral (0)
   int rsiDir = 0;
   if(rsiValue > 70)
      rsiDir = 1;
   else if(rsiValue < 30)
      rsiDir = -1;

   // --- Stochastic Calculation ---
   double stochK, stochD;
   if(ArraySize(iStochastic(_Symbol, _Period, K_Period, D_Period, 3, MODE_SMA, STO_LOWHIGH, MODE_MAIN))<2)
   {
      PrintLog("Not enough Stochastic data.");
      return 0;
   }
   stochK = iStochastic(_Symbol, _Period, K_Period, D_Period, 3, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
   // Reversed: if %K > 80 then bullish, if %K < 20 then bearish, else neutral (0)
   int stochDir = 0;
   if(stochK > 80)
      stochDir = 1;
   else if(stochK < 20)
      stochDir = -1;

   // Log the indicator directions
   PrintLog("Indicators => MACD: " + IntegerToString(macdDir) +
            ", RSI: " + IntegerToString(rsiDir) +
            ", Stochastic: " + IntegerToString(stochDir));

   // If all indicators agree (non-zero) then return that signal; otherwise no trade signal.
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
   double riskAmount = accountBalance * (RiskPercent / 100.0);
   // For a rough approximation, assume that for many Forex pairs 1 standard lot yields ~$10 per pip.
   // Adjust this as needed for your broker/instrument.
   double pipValuePerLot = 10.0;
   // The price difference per pip is SYMBOL_POINT.
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   // Calculate lot size so that riskAmount = lotSize * (stopLossPips * (point * pipValuePerLot))
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

   // Get current position details
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double volume     = PositionGetDouble(POSITION_VOLUME);
   int    posType    = PositionGetInteger(POSITION_TYPE);
   double currentPrice = (posType==POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                     : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Calculate the profit target distances in price terms:
   double profitTargetInitial = RRR_Initial * StopLossPips * point;
   double profitTargetFinal   = RRR_Final   * StopLossPips * point;

   bool triggerPartial = false;
   if(posType == POSITION_TYPE_BUY && (currentPrice - entryPrice >= profitTargetInitial))
      triggerPartial = true;
   else if(posType == POSITION_TYPE_SELL && (entryPrice - currentPrice >= profitTargetInitial))
      triggerPartial = true;

   if(triggerPartial && !partialClosed)
   {
      // Partial close: close 50% of the volume
      double volumeToClose = volume * 0.5;
      if(trade.PositionClosePartial(_Symbol, volumeToClose))
      {
         PrintLog("Executed partial close of " + DoubleToString(volumeToClose,2) + " lots.");
         // Update the TP for the remaining position to the final target
         double newTP = 0.0;
         if(posType == POSITION_TYPE_BUY)
            newTP = entryPrice + profitTargetFinal;
         else if(posType == POSITION_TYPE_SELL)
            newTP = entryPrice - profitTargetFinal;
         if(trade.PositionModify(_Symbol, PositionGetDouble(POSITION_SL), newTP))
         {
            PrintLog("Modified remaining position: new TP = " + DoubleToString(newTP, _Digits));
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
         PrintLog("Failed to close position for " + _Symbol);
      else
         PrintLog("Position closed for " + _Symbol);
   }
}

//+------------------------------------------------------------------+
//| Update chart objects with account and status information         |
//+------------------------------------------------------------------+
void UpdateChartObjects()
{
   string balanceText    = "Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2);
   string drawdownText   = "Drawdown: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE), 2);
   string brokerTimeText = "Broker Time: " + TimeToString(TimeCurrent(), TIME_SECONDS);
   string eaNameText     = "EA: " + EA_Name;
   string positionsText  = "Open Positions: " + IntegerToString(PositionsTotal());
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
