#property strict

#include "GP_ResearchHarness.mqh"

//+------------------------------------------------------------------+
//| GP_ResearchRunner.mq5                                            |
//|                                                                  |
//| Standalone runner untuk research arah GoldPro.                   |
//|                                                                  |
//| File ini TIDAK mengubah sistem utama. Hanya menjalankan riset     |
//| replay di bar yang tersedia untuk mengecek kombinasi fitur.       |
//+------------------------------------------------------------------+

int OnInit()
  {
   Print("[GP_ResearchRunner] siap. Memulai evaluasi multi-TF dengan kombinasi GoldPro.");
   return(INIT_SUCCEEDED);
  }

int OnStart()
  {
   ENUM_TIMEFRAMES tf = PERIOD_M15;
   int bars = iBars(_Symbol, tf);
   if(bars < 500)
      {
       Print("[GP_ResearchRunner] data tidak cukup untuk evaluasi.");
       return(0);
      }

   int startShift = 200;
   int sampleCount = MathMin(500, bars - startShift - 60);
   int horizonBars = 12;
   double threshold = 8.0 * _Point;

   GPResearchResult result;
   GPResearchReplayWindow(tf, startShift, sampleCount, horizonBars, threshold, result);
   GPResearchPrintReport(result, "M15 / 12-bar candidate");

   Print("[GP_ResearchRunner] evaluasi selesai. Hasil ini adalah bahan riset, bukan sinyal trading.");
   return(0);
  }
