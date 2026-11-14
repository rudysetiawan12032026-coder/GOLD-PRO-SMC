//+------------------------------------------------------------------+
//|                                          SMC_MarketCondition.mqh |
//|                                                                  |
//| Fase 2 - File 8/24 : SMC Pro System                             |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Menilai apakah market sedang trending (SMC bekerja optimal),  |
//|   ranging/choppy (sinyal SMC harus ditahan), atau compressed     |
//|   (volatilitas menyempit, sering sebelum breakout).             |
//|                                                                  |
//| Berdiri sendiri - hanya bergantung pada SMC_Utils.mqh (ATR).    |
//| Tidak tahu apa-apa soal Structure/POI/Liquidity.                |
//+------------------------------------------------------------------+
#ifndef SMC_MARKETCONDITION_MQH
#define SMC_MARKETCONDITION_MQH

#include "..\Core\SMC_Types.mqh"
#include "..\Core\SMC_Config.mqh"
#include "..\Core\SMC_Utils.mqh"

//======================================================================
// STATE
//======================================================================
MarketConditionState g_marketCondition;

//======================================================================
// INIT
//======================================================================
void SMC_MarketCondition_Init()
  {
   ZeroMemory(g_marketCondition);
   g_marketCondition.condition = CONDITION_RANGING; // default konservatif sebelum data cukup
  }

//======================================================================
// HELPER: Efficiency Ratio
//   |close[akhir] - close[awal]| / total pergerakan absolut per-bar.
//   Mendekati 1.0 = trending kuat (harga bergerak efisien satu arah).
//   Mendekati 0.0 = choppy (banyak bolak-balik, net movement kecil).
//======================================================================
double CalculateEfficiencyRatio(ENUM_TIMEFRAMES tf, int period)
  {
   if(period < 2)
      return 0.0;

   double closes[];
   ArraySetAsSeries(closes, true);
   if(CopyClose(_Symbol, tf, 1, period + 1, closes) < period + 1)
      return 0.0; // data belum cukup

   double netMove = MathAbs(closes[0] - closes[period]);

   double totalMove = 0.0;
   for(int i = 0; i < period; i++)
      totalMove += MathAbs(closes[i] - closes[i + 1]);

   if(totalMove <= 0.0)
      return 0.0;

   return netMove / totalMove;
  }

//======================================================================
// HELPER: ATR Relatif
//   ATR sekarang dibanding rata-rata ATR selama InpATRRelativePeriod.
//   > 1.0 = volatilitas sedang ekspansi. < 1.0 = volatilitas menyempit.
//
// FIX: sebelumnya pakai handle iATR()+CopyBuffer() langsung - kena bug
// yang SAMA dengan yang ditemukan di SMC_Liquidity.mqh (handle belum
// tentu terisi kalau dipanggil sinkron di dalam OnInit backfill).
// Sekarang pakai GetATR() yang sudah dihitung manual (SMC_Utils.mqh),
// dipanggil berulang per titik waktu - sedikit lebih banyak komputasi,
// tapi TIDAK PERNAH bergantung pada timing buffer indikator.
//======================================================================
double CalculateATRRelative(ENUM_TIMEFRAMES tf)
  {
   double currentATR = GetATR(tf, 14, 1);
   if(currentATR <= 0.0)
      return 1.0;

   double sum = 0.0;
   int counted = 0;
   for(int i = 1; i <= InpATRRelativePeriod; i++)
     {
      double atrAtShift = GetATR(tf, 14, i);
      if(atrAtShift <= 0.0)
         continue;
      sum += atrAtShift;
      counted++;
     }

   if(counted < InpATRRelativePeriod / 2) // data terlalu sedikit untuk rata-rata yang wajar
      return 1.0;

   double avgATR = sum / counted;
   if(avgATR <= 0.0)
      return 1.0;

   return currentATR / avgATR;
  }

//======================================================================
// FUNGSI UTAMA
//======================================================================
void SMC_MarketCondition_Update(ENUM_TIMEFRAMES tf, bool isNewBar)
  {
   if(!isNewBar)
      return;

   g_marketCondition.efficiencyRatio = CalculateEfficiencyRatio(tf, InpEfficiencyRatioPeriod);
   g_marketCondition.atrRelative     = CalculateATRRelative(tf);

   // Volatilitas menyempit signifikan -> COMPRESSED, apapun efficiency ratio-nya
   // (ini kondisi klasik pra-breakout, misal sesi Asia yang sepi).
   if(g_marketCondition.atrRelative < 0.6)
     {
      g_marketCondition.condition = CONDITION_COMPRESSED;
     }
   else if(g_marketCondition.efficiencyRatio >= InpTrendingThreshold)
     {
      g_marketCondition.condition = CONDITION_TRENDING;
     }
   else if(g_marketCondition.efficiencyRatio <= InpRangingThreshold)
     {
      g_marketCondition.condition = CONDITION_RANGING;
     }
   else
     {
      // Di antara dua threshold - defaultkan ke RANGING (sikap konservatif,
      // lebih baik menahan sinyal daripada salah anggap trending).
      g_marketCondition.condition = CONDITION_RANGING;
     }
  }

//======================================================================
// ACCESSOR
//======================================================================
MarketConditionState GetMarketCondition() { return g_marketCondition; }

#endif // SMC_MARKETCONDITION_MQH