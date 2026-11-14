#ifndef GP_RESEARCH_DATASET_MQH
#define GP_RESEARCH_DATASET_MQH

//+------------------------------------------------------------------+
//| GP_ResearchDataset.mqh                                            |
//|                                                                  |
//| Standalone dataset untuk menyimpan snapshot fitur GoldPro.        |
//|                                                                  |
//| Tujuan:                                                          |
//| - menyimpan hasil riset secara terpisah dari sistem utama         |
//| - memudahkan backtest / analisis pola arah                        |
//| - meletakkan fitur per bar ke file CSV / memori                  |
//+------------------------------------------------------------------+

struct GPResearchRow
  {
   datetime time;
   string   symbol;
   string   tfName;
   double   open;
   double   high;
   double   low;
   double   close;
   double   dailyOpen;
   double   dailyEq;
   double   dailyHigh;
   double   dailyLow;
   double   weeklyOpen;
   double   weeklyEq;
   double   weeklyHigh;
   double   weeklyLow;
   double   trendBias;
   double   pressure;
   double   volatility;
   int      sessionType;
   double   distToDailyEq;
   double   distToWeeklyEq;
   double   distToDailyHigh;
   double   distToDailyLow;
   double   distToWeeklyHigh;
   double   distToWeeklyLow;
   int      directionLabel;
   double   forwardMove;
   double   confidence;
  };

//======================================================================
// EXPORT DATASET KE CSV (terpisah dari chart main)
//======================================================================
bool GPResearchWriteCsv(const string fileName, const GPResearchRow &row)
  {
   int handle = FileOpen(fileName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON, ',');
   if(handle == INVALID_HANDLE)
      return false;

   bool exists = FileIsExist(fileName, FILE_COMMON);
   if(!exists)
      {
       FileWrite(handle,
                 "time,symbol,tfName,open,high,low,close,dailyOpen,dailyEq,dailyHigh,dailyLow,weeklyOpen,weeklyEq,weeklyHigh,weeklyLow,trendBias,pressure,volatility,sessionType,distToDailyEq,distToWeeklyEq,distToDailyHigh,distToDailyLow,distToWeeklyHigh,distToWeeklyLow,directionLabel,forwardMove,confidence");
      }

   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle,
             IntegerToString((int)row.time),
             row.symbol,
             row.tfName,
             DoubleToString(row.open, 8),
             DoubleToString(row.high, 8),
             DoubleToString(row.low, 8),
             DoubleToString(row.close, 8),
             DoubleToString(row.dailyOpen, 8),
             DoubleToString(row.dailyEq, 8),
             DoubleToString(row.dailyHigh, 8),
             DoubleToString(row.dailyLow, 8),
             DoubleToString(row.weeklyOpen, 8),
             DoubleToString(row.weeklyEq, 8),
             DoubleToString(row.weeklyHigh, 8),
             DoubleToString(row.weeklyLow, 8),
             DoubleToString(row.trendBias, 8),
             DoubleToString(row.pressure, 8),
             DoubleToString(row.volatility, 8),
             IntegerToString(row.sessionType),
             DoubleToString(row.distToDailyEq, 8),
             DoubleToString(row.distToWeeklyEq, 8),
             DoubleToString(row.distToDailyHigh, 8),
             DoubleToString(row.distToDailyLow, 8),
             DoubleToString(row.distToWeeklyHigh, 8),
             DoubleToString(row.distToWeeklyLow, 8),
             IntegerToString(row.directionLabel),
             DoubleToString(row.forwardMove, 8),
             DoubleToString(row.confidence, 8));

   FileClose(handle);
   return true;
  }

#endif // GP_RESEARCH_DATASET_MQH
