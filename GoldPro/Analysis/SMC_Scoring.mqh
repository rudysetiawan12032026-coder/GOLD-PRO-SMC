//+------------------------------------------------------------------+
//|                                                   SMC_Scoring.mqh |
//|                                                                  |
//| Fase 4 - File 13/24 : SMC Pro System                             |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Mesin confluence scoring - menggabungkan semua sinyal dari     |
//|   modul deteksi jadi satu skor keputusan dan BiasState.          |
//|                                                                  |
//| ATURAN PENTING:                                                 |
//|   File ini TIDAK melakukan deteksi baru apapun - murni fungsi    |
//|   dari state yang sudah dihasilkan modul lain. Threshold & bobot |
//|   SELALU dibaca dari SMC_Config.mqh, tidak pernah hardcode di    |
//|   sini.                                                          |
//+------------------------------------------------------------------+
#ifndef SMC_SCORING_MQH
#define SMC_SCORING_MQH

#include "..\Core\SMC_Types.mqh"
#include "..\Core\SMC_Config.mqh"
#include "..\Core\SMC_Utils.mqh"
#include "..\Detection\SMC_Structure.mqh"
#include "..\Detection\SMC_POI.mqh"
#include "..\Detection\SMC_Liquidity.mqh"
#include "..\Detection\SMC_Zones.mqh"
#include "..\Detection\SMC_MarketCondition.mqh"
#include "SMC_MTF.mqh"
#include "SMC_AMD.mqh"
#include "SMC_NewsFilter.mqh"

//======================================================================
// STATE
//======================================================================
BiasState g_biasState;

//======================================================================
// INIT
//======================================================================
void SMC_Scoring_Init()
  {
   ZeroMemory(g_biasState);
   g_biasState.decision = DECISION_NO_ZONE;
  }

//======================================================================
// KOMPONEN 1: Struktur - keselarasan bias LTF/MTF/HTF
//======================================================================
double ScoreStructure(ENUM_BIAS ltf, ENUM_BIAS mtf, ENUM_BIAS htf)
  {
   if(ltf == BIAS_NEUTRAL)
      return 0.0;

   int matchCount = 0;
   if(mtf == ltf) matchCount++;
   if(htf == ltf) matchCount++;

   bool anyOpposite = (mtf != BIAS_NEUTRAL && mtf != ltf) || (htf != BIAS_NEUTRAL && htf != ltf);

   if(matchCount == 2)
      return 100.0;
   if(matchCount == 1 && !anyOpposite)
      return 75.0;
   if(matchCount == 1 && anyOpposite)
      return 50.0;
   if(anyOpposite)
      return 25.0;

   return 40.0; // LTF punya bias tapi MTF/HTF masih netral semua
  }

//======================================================================
// KOMPONEN 2: Liquidity story - IDM sudah di-sweep sebelum event?
//======================================================================
double ScoreLiquidity(ENUM_BIAS ltf)
  {
   StructureEvent evt;
   if(!GetLastStructureEvent(evt))
      return 0.0;
   if(evt.direction != ltf)
      return 0.0; // event terakhir tidak searah bias LTF saat ini

   return evt.idmConfirmed ? 100.0 : 50.0;
  }

//======================================================================
// KOMPONEN 3: Posisi harga di dealing range (Discount/Premium/OTE)
//======================================================================
double ScoreZone(ENUM_BIAS ltf, double currentPrice)
  {
   double percent;
   ENUM_PRICE_ZONE zone = GetZoneForPrice(currentPrice, percent);

   if(zone == PRICEZONE_OUT_OF_RANGE)
      return 0.0;
   if(zone == PRICEZONE_OTE)
      return 100.0;

   bool wantDiscount = (ltf == BIAS_BULLISH); // buy -> cari discount, sell -> cari premium
   if(zone == PRICEZONE_EQUILIBRIUM)
      return 50.0;
   if((zone == PRICEZONE_DISCOUNT && wantDiscount) || (zone == PRICEZONE_PREMIUM && !wantDiscount))
      return 75.0;

   return 25.0; // harga di sisi yang "salah" dari range untuk arah bias ini
  }

//======================================================================
// KOMPONEN 4: Kualitas POI terdekat searah bias
//======================================================================
double ScorePOIQuality(ENUM_BIAS ltf, double currentPrice)
  {
   if(ltf == BIAS_NEUTRAL)
      return 0.0;

   OrderBlock ob;
   bool wantBullish = (ltf == BIAS_BULLISH);
   if(!GetNearestUnmitigatedOB(wantBullish, currentPrice, ob))
      return 0.0;

   double score = 40.0;
   if(ob.hasFVG)
      score += 20.0;
   if(ob.isConfluent)
      score += 20.0;
   if(ob.status == ZONE_FRESH)
      score += 20.0;

   return MathMin(score, 100.0);
  }

//======================================================================
// KOMPONEN 5: Konfirmasi LTF - seberapa baru structure event terjadi
//======================================================================
double ScoreLTFConfirm(ENUM_TIMEFRAMES tf, ENUM_BIAS ltf)
  {
   StructureEvent evt;
   if(!GetLastStructureEvent(evt))
      return 0.0;
   if(evt.direction != ltf)
      return 0.0;

   int barsAgo = iBarShift(_Symbol, tf, evt.time);
   if(barsAgo < 0)
      return 0.0;

   if(barsAgo <= 3)  return 100.0;
   if(barsAgo <= 6)  return 70.0;
   if(barsAgo <= 10) return 40.0;
   return 20.0; // event masih ada tapi sudah cukup lama, sinyal melemah
  }

//======================================================================
// KOMPONEN 6: Kondisi market
//======================================================================
double ScoreMarketCondition()
  {
   MarketConditionState mc = GetMarketCondition();
   switch(mc.condition)
     {
      case CONDITION_TRENDING:   return 100.0;
      case CONDITION_COMPRESSED: return 60.0;
      default:                   return 40.0; // RANGING - dinaikkan dari 20 (kalibrasi: choppy butuh konfirmasi lebih, bukan otomatis setup buruk)
     }
  }

//======================================================================
// AddFactor() - Fase 4. Catat SATU komponen skor ke daftar faktor kalau
// nilainya >= InpConfluenceFactorMinScore (default 50). Dipakai untuk
// dashboard/debugging DAN sebagai basis IsBuyAllowed()/IsSellAllowed().
//======================================================================
void AddFactor(POIScore &score, string name, double value)
  {
   if(value < InpConfluenceFactorMinScore)
      return; // bukan faktor confluence - jangan dicatat

   int n = ArraySize(score.factorNames);
   ArrayResize(score.factorNames, n + 1);
   ArrayResize(score.factorScores, n + 1);
   score.factorNames[n]  = name;
   score.factorScores[n] = value;
   score.factorCount      = n + 1;
  }

//======================================================================
// FUNGSI UTAMA
//======================================================================
void SMC_Scoring_Update(ENUM_TIMEFRAMES tf, bool isNewBar)
  {
   if(!isNewBar)
      return;

   ENUM_BIAS ltf = GetExternalBias();
   ENUM_BIAS mtf = GetMTFBias();
   ENUM_BIAS htf = GetHTFBias();
   double currentPrice = iClose(_Symbol, tf, 1);

   POIScore s;
   ArrayFree(s.factorNames);
   ArrayFree(s.factorScores);
   s.factorCount = 0;

   s.scoreStructure       = ScoreStructure(ltf, mtf, htf);
   s.scoreLiquidity       = ScoreLiquidity(ltf);
   s.scoreZone            = ScoreZone(ltf, currentPrice);
   s.scorePOIQuality      = ScorePOIQuality(ltf, currentPrice);
   s.scoreLTFConfirm      = ScoreLTFConfirm(tf, ltf);
   s.scoreMarketCondition = ScoreMarketCondition();

   // Catat faktor SETELAH semua komponen dihitung (urutan tidak
   // memengaruhi scoreTotal - AddFactor cuma mencatat, tidak menghitung).
   AddFactor(s, "Structure", s.scoreStructure);
   AddFactor(s, "Liquidity", s.scoreLiquidity);
   AddFactor(s, "Zone", s.scoreZone);
   AddFactor(s, "POI Quality", s.scorePOIQuality);
   AddFactor(s, "LTF Confirm", s.scoreLTFConfirm);
   AddFactor(s, "Market Condition", s.scoreMarketCondition);

   s.scoreTotal = (s.scoreStructure       * g_normalizedWeights[0]
                 + s.scoreLiquidity       * g_normalizedWeights[1]
                 + s.scoreZone            * g_normalizedWeights[2]
                 + s.scorePOIQuality      * g_normalizedWeights[3]
                 + s.scoreLTFConfirm      * g_normalizedWeights[4]
                 + s.scoreMarketCondition * g_normalizedWeights[5]) / 100.0;

   ENUM_ENTRY_DECISION decision;
   if(InpEvidenceDecision)
     {
      // GoldPro: aturan dari validasi 1 tahun (rekomendasi entry dgn Zone>=70 & POI>=80:
      // +0.04/+0.61/+0.21R di latih/validasi/uji). Skor total SMC lama tidak prediktif.
      if(s.scoreZone >= 70 && s.scorePOIQuality >= 80)
         decision = DECISION_ENTRY_OK;
      else if(s.scoreZone >= 50 || s.scorePOIQuality >= 80)
         decision = DECISION_WATCH;
      else
         decision = DECISION_NO_ZONE;
     }
   else
     {
      if(s.scoreTotal >= InpEntryThreshold)
         decision = DECISION_ENTRY_OK;
      else if(s.scoreTotal >= InpWatchThreshold)
         decision = DECISION_WATCH;
      else
         decision = DECISION_NO_ZONE;
     }

   // --- Gate: news blackout menahan entry (tetap aktif sebagai pengaman) ---
   if(decision == DECISION_ENTRY_OK && IsNewsBlackout())
      decision = DECISION_WATCH;

   // --- Gerbang lama SMC (AMD Accumulation) - tidak terbukti, default nonaktif ---
   AMDState amd = GetAMDState();
   if(InpLegacyGates && decision == DECISION_ENTRY_OK && amd.phase == AMD_ACCUMULATION)
      decision = DECISION_WATCH;

   // --- Gate tambahan (screenshot review - kontradiksi ditemukan):
   //     ENTRY OK muncul BERSAMAAN dengan Skenario "Range aktif - tunggu
   //     breakout" - dua instruksi yang saling bertentangan buat orang
   //     yang baca dashboard/Telegram. Kalau harga masih terkurung di
   //     range matang (IsInRange(), Fase 5), sistem SENDIRI belum tahu
   //     arahnya - jadi ENTRY OK jelas prematur, apapun skor confluence-nya.
   if(InpLegacyGates && decision == DECISION_ENTRY_OK && IsInRange())
      decision = DECISION_WATCH;

   // --- Gate tambahan (Fase 4): confluence factorCount minimum ---
   // scoreTotal bisa lolos threshold cuma dari 1-2 komponen dominan -
   // ini mencegah entry kalau confluence-nya sebenarnya tipis.
   if(InpLegacyGates && decision == DECISION_ENTRY_OK && s.factorCount < InpMinConfluence)
      decision = DECISION_WATCH;

   g_biasState.htfBias        = htf;
   g_biasState.mtfBias        = mtf;
   g_biasState.ltfBias        = ltf;
   g_biasState.scoreBreakdown = s;
   g_biasState.decision       = decision;
   // narrativeText & narrativeShort SENGAJA tidak diisi di sini - itu
   // tugas SMC_Narrative.mqh lewat SetNarrativeTexts() di bawah.
  }

//======================================================================
// ACCESSOR
//======================================================================
BiasState GetBiasState() { return g_biasState; }

// IsBuyAllowed()/IsSellAllowed() - Fase 4. Gate eksplisit terpisah per
// arah, dipakai SIGNAL EXPORT / EA companion nanti (BUKAN dipakai
// ulang oleh SMC_Scoring_Update sendiri - decision di atas SUDAH final
// lewat jalur yang sama; ini accessor TAMBAHAN untuk konsumen eksternal
// yang butuh jawaban ya/tidak per arah secara eksplisit).
bool IsBuyAllowed()
  {
   return g_biasState.ltfBias == BIAS_BULLISH
       && g_biasState.decision == DECISION_ENTRY_OK;
  }

bool IsSellAllowed()
  {
   return g_biasState.ltfBias == BIAS_BEARISH
       && g_biasState.decision == DECISION_ENTRY_OK;
  }

// Dipanggil HANYA oleh SMC_Narrative.mqh untuk mengisi field naratif
// pada state yang sama - menjaga agar Scoring tetap "otak angka" dan
// Narrative tetap "penerjemah teks", tanpa duplikasi state terpisah.
void SetNarrativeTexts(string fullText, string shortText)
  {
   g_biasState.narrativeText  = fullText;
   g_biasState.narrativeShort = shortText;
  }

#endif // SMC_SCORING_MQH