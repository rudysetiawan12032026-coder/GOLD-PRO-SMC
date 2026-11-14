//+------------------------------------------------------------------+
//|                                                 SMC_Narrative.mqh |
//|                                                                  |
//| Fase 4 - File 15/24 : SMC Pro System                             |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Mengubah semua state numerik/struct jadi teks naratif yang     |
//|   mudah dibaca manusia. TIDAK ADA perhitungan baru di sini -     |
//|   murni formatting dari data yang sudah jadi.                    |
//+------------------------------------------------------------------+
#ifndef SMC_NARRATIVE_MQH
#define SMC_NARRATIVE_MQH

#include "..\Core\SMC_Types.mqh"
#include "..\Core\SMC_Config.mqh"
#include "..\Analysis\SMC_Scoring.mqh"
#include "..\Analysis\SMC_AMD.mqh"
#include "..\Analysis\SMC_NewsFilter.mqh"
#include "..\Analysis\SMC_Stats.mqh"
#include "..\Detection\SMC_POI.mqh"
#include "..\Detection\SMC_Liquidity.mqh"

//======================================================================
// HELPER: label teks untuk enum-enum umum
//======================================================================
string BiasToText(ENUM_BIAS b)
  {
   switch(b)
     {
      case BIAS_BULLISH: return "BULLISH";
      case BIAS_BEARISH: return "BEARISH";
      default:            return "NEUTRAL";
     }
  }

string DecisionToText(ENUM_ENTRY_DECISION d)
  {
   switch(d)
     {
      case DECISION_ENTRY_OK: return "ENTRY OK";
      case DECISION_WATCH:    return "WATCH";
      default:                 return "NO ZONE";
     }
  }

string AMDPhaseToText(ENUM_AMD_PHASE p)
  {
   switch(p)
     {
      case AMD_ACCUMULATION: return "Accumulation";
      case AMD_MANIPULATION: return "Manipulation";
      case AMD_DISTRIBUTION: return "Distribution";
      default:                return "-";
     }
  }

//======================================================================
// FUNGSI UTAMA
//======================================================================
void SMC_Narrative_Update(ENUM_TIMEFRAMES tf, bool isNewBar)
  {
   if(!isNewBar)
      return;

   BiasState bs  = GetBiasState();
   AMDState  amd = GetAMDState();
   double currentPrice = iClose(_Symbol, tf, 1);

   // --- Versi ringkas (dashboard, satu baris) ---
   string shortText = StringFormat("%s bias %s | %s (%.0f%%)",
                                    EnumToString(tf), BiasToText(bs.ltfBias),
                                    DecisionToText(bs.decision), bs.scoreBreakdown.scoreTotal);

   // --- Versi lengkap ---
   string fullText = StringFormat("%s bias %s. Fase market: %s.",
                                   EnumToString(tf), BiasToText(bs.ltfBias), AMDPhaseToText(amd.phase));

   if(amd.isJudasSwing)
      fullText += " Terindikasi Judas Swing di awal killzone.";

   double zonePercent;
   ENUM_PRICE_ZONE zone = GetZoneForPrice(currentPrice, zonePercent);
   if(zone != PRICEZONE_OUT_OF_RANGE)
      fullText += StringFormat(" Harga saat ini di %.0f%% dealing range.", zonePercent);

   OrderBlock ob;
   bool wantBullish = (bs.ltfBias == BIAS_BULLISH);
   if(bs.ltfBias != BIAS_NEUTRAL && GetNearestUnmitigatedOB(wantBullish, currentPrice, ob, true))
     {
      fullText += StringFormat(" POI terdekat: %s @ %.2f-%.2f%s%s.",
                                POITypeText(ob), ob.low, ob.high,
                                ob.hasFVG ? " (dengan FVG)" : "",
                                ob.isConfluent ? " [confluence HTF/MTF]" : "");
     }

   LiquidityPool target;
   if(bs.ltfBias != BIAS_NEUTRAL && GetNearestLiquidityTarget(wantBullish, currentPrice, target))
     {
      fullText += StringFormat(" Target likuiditas terdekat: %s @ %.5f.",
                                target.isBuySide ? "BSL" : "SSL", target.price);
     }

   NewsEvent nextNews;
   if(GetNextNewsEvent(nextNews))
     {
      long minutesTo = (nextNews.eventTime - TimeCurrent()) / 60;
      if(minutesTo >= 0 && minutesTo <= 180) // hanya tampilkan kalau dalam 3 jam ke depan
         fullText += StringFormat(" Berita %s (%s) dalam %d menit.", nextNews.name, nextNews.currency, (int)minutesTo);
     }
   if(IsNewsBlackout())
      fullText += " [NEWS BLACKOUT - entry ditahan]";

   PatternStats stats;
   if(InpEnableStats && GetWinRateForCurrentPattern(stats))
     {
      if(stats.totalCount >= InpStatsMinSampleSize)
         fullText += StringFormat(" Histori pola serupa: %.0f%% win rate dari %d kejadian.",
                                   stats.winRatePercent, stats.totalCount);
      else
         fullText += StringFormat(" Histori pola serupa: baru %d kejadian (belum cukup sample).", stats.totalCount);
     }

   SetNarrativeTexts(fullText, shortText);
  }

#endif // SMC_NARRATIVE_MQH
