//+------------------------------------------------------------------+
//|                                                     SMC_Stats.mqh |
//|                                                                  |
//| Fase 4 - File 14/24 : SMC Pro System                             |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Melacak setiap setup yang lolos threshold (ENTRY_OK), memantau |
//|   hasilnya secara forward, dan menyimpan histori win-rate per    |
//|   "jenis pola" - persisten antar-restart lewat file CSV.         |
//|                                                                  |
//| SIMPLIFIKASI YANG SENGAJA DIAMBIL:                               |
//|   Target & stop dihitung dari ATR (R:R tetap ~1.5), BUKAN dari   |
//|   liquidity target/stop struktural yang sesungguhnya - supaya    |
//|   modul ini mandiri/tidak menambah dependency baru. Setelah      |
//|   berjalan beberapa waktu, evaluasi apakah definisi win/loss ini |
//|   perlu diperhalus memakai level structural yang sebenarnya.     |
//+------------------------------------------------------------------+
#ifndef SMC_STATS_MQH
#define SMC_STATS_MQH

#include "..\Core\SMC_Types.mqh"
#include "..\Core\SMC_Config.mqh"
#include "..\Core\SMC_Utils.mqh"
#include "SMC_Scoring.mqh"
#include "SMC_AMD.mqh"
#include "..\Detection\SMC_MarketCondition.mqh"

//======================================================================
// STATE
//======================================================================
SetupRecord   g_pendingSetups[];
PatternStats  g_patternStats[];
long          g_nextSetupId = 1;
datetime      g_lastSetupEntryTime = 0; // cegah duplikat setup di bar yang sama

//======================================================================
// HELPER: cari/tambah PatternStats untuk sebuah key
//======================================================================
int FindOrCreatePatternStats(string key)
  {
   for(int i = 0; i < ArraySize(g_patternStats); i++)
      if(g_patternStats[i].patternKey == key)
         return i;

   int n = ArraySize(g_patternStats);
   ArrayResize(g_patternStats, n + 1);
   g_patternStats[n].patternKey     = key;
   g_patternStats[n].totalCount     = 0;
   g_patternStats[n].winCount       = 0;
   g_patternStats[n].winRatePercent = 0.0;
   return n;
  }

void RegisterOutcome(string key, bool isWin)
  {
   int idx = FindOrCreatePatternStats(key);
   g_patternStats[idx].totalCount++;
   if(isWin)
      g_patternStats[idx].winCount++;
   g_patternStats[idx].winRatePercent =
      (double)g_patternStats[idx].winCount / g_patternStats[idx].totalCount * 100.0;
  }

//======================================================================
// PERSISTENSI: tulis satu baris hasil ke file CSV
//======================================================================
void AppendResultToFile(SetupRecord &rec)
  {
   int handle = FileOpen(InpStatsFileName, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("[SMC_Stats] ERROR: Gagal membuka file %s untuk menulis (err=%d)",
                  InpStatsFileName, GetLastError());
      return;
     }

   // PERBAIKAN GoldPro: FileWrite() pada file FILE_TXT menulis kolom TANPA pemisah,
   // padahal LoadStatsFromFile() memecah dengan koma -> semua histori gagal dibaca
   // setiap restart (itu sebabnya patternStats SMC selalu null). Tulis koma eksplisit.
   FileSeek(handle, 0, SEEK_END);
   FileWriteString(handle, StringFormat("%s,%s,%s,%s\r\n", rec.patternKey, rec.isWin ? "1" : "0",
                   DoubleToString(rec.confluenceScore, 2), TimeToString(rec.resolvedTime)));
   FileClose(handle);
  }

//======================================================================
// PERSISTENSI: baca ulang file saat init, bangun ulang agregat statistik
//======================================================================
void LoadStatsFromFile()
  {
   if(!FileIsExist(InpStatsFileName))
      return;

   int handle = FileOpen(InpStatsFileName, FILE_READ | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;

   while(!FileIsEnding(handle))
     {
      string line = FileReadString(handle);
      if(StringLen(line) == 0)
         continue;

      string parts[];
      int cnt = StringSplit(line, ',', parts);
      if(cnt < 2)
         continue;

      string key   = parts[0];
      bool   isWin = (parts[1] == "1");
      RegisterOutcome(key, isWin);
     }
   FileClose(handle);

   PrintFormat("[SMC_Stats] Histori dimuat: %d pola unik dari %s", ArraySize(g_patternStats), InpStatsFileName);
  }

//======================================================================
// INIT
//======================================================================
void SMC_Stats_Init()
  {
   ArrayFree(g_pendingSetups);
   ArrayFree(g_patternStats);
   g_nextSetupId = 1;
   g_lastSetupEntryTime = 0;

   if(InpEnableStats)
      LoadStatsFromFile();
  }

//======================================================================
// HELPER: bangun pattern key dari konteks saat ini
//======================================================================
string BuildPatternKey(ENUM_BIAS bias, ENUM_AMD_PHASE amdPhase, ENUM_MARKET_CONDITION mc)
  {
   return StringFormat("%s_%s_%s", EnumToString(bias), EnumToString(amdPhase), EnumToString(mc));
  }

//======================================================================
// CATAT SETUP BARU (dipanggil saat scoring menghasilkan ENTRY_OK)
//======================================================================
void RegisterNewSetup(ENUM_TIMEFRAMES tf, BiasState &bs)
  {
   datetime entryTime = iTime(_Symbol, tf, 1);
   if(entryTime == g_lastSetupEntryTime)
      return; // sudah dicatat untuk bar ini

   g_lastSetupEntryTime = entryTime;

   double entryPrice = iClose(_Symbol, tf, 1);
   double atr = GetATR(tf, 14, 1);
   if(atr <= 0)
      return;

   double stopDist   = atr * 1.0;
   double targetDist = atr * 1.5; // R:R 1.5, konsisten dengan konvensi risk default sistem

   AMDState amd = GetAMDState();
   MarketConditionState mc = GetMarketCondition();

   int n = ArraySize(g_pendingSetups);
   ArrayResize(g_pendingSetups, n + 1);
   g_pendingSetups[n].id              = g_nextSetupId++;
   g_pendingSetups[n].entryTime       = entryTime;
   g_pendingSetups[n].patternKey      = BuildPatternKey(bs.ltfBias, amd.phase, mc.condition);
   g_pendingSetups[n].biasDirection   = bs.ltfBias;
   g_pendingSetups[n].confluenceScore = bs.scoreBreakdown.scoreTotal;
   g_pendingSetups[n].entryPrice      = entryPrice;
   g_pendingSetups[n].amdPhaseAtEntry = amd.phase;
   g_pendingSetups[n].marketConditionAtEntry = mc.condition;
   g_pendingSetups[n].isResolved      = false;

   if(bs.ltfBias == BIAS_BULLISH)
     {
      g_pendingSetups[n].stopPrice   = entryPrice - stopDist;
      g_pendingSetups[n].targetPrice = entryPrice + targetDist;
     }
   else
     {
      g_pendingSetups[n].stopPrice   = entryPrice + stopDist;
      g_pendingSetups[n].targetPrice = entryPrice - targetDist;
     }
  }

//======================================================================
// EVALUASI SETUP YANG SEDANG DIPANTAU
//======================================================================
void EvaluatePendingSetups(ENUM_TIMEFRAMES tf)
  {
   double barHigh = iHigh(_Symbol, tf, 1);
   double barLow  = iLow(_Symbol, tf, 1);
   datetime barTime = iTime(_Symbol, tf, 1);

   for(int i = ArraySize(g_pendingSetups) - 1; i >= 0; i--)
     {
      if(g_pendingSetups[i].isResolved)
         continue;

      bool isBullish = (g_pendingSetups[i].biasDirection == BIAS_BULLISH);
      bool hitTarget = isBullish ? (barHigh >= g_pendingSetups[i].targetPrice)
                                  : (barLow <= g_pendingSetups[i].targetPrice);
      bool hitStop   = isBullish ? (barLow <= g_pendingSetups[i].stopPrice)
                                  : (barHigh >= g_pendingSetups[i].stopPrice);

      int barsElapsed = iBarShift(_Symbol, tf, g_pendingSetups[i].entryTime) - iBarShift(_Symbol, tf, barTime);

      bool resolved = false;
      bool isWin    = false;

      if(hitTarget)
        {
         resolved = true;
         isWin    = true;
        }
      else if(hitStop)
        {
         resolved = true;
         isWin    = false;
        }
      else if(barsElapsed >= InpStatsMaxTrackBars)
        {
         resolved = true;
         isWin    = false; // timeout dianggap gagal (sikap konservatif)
        }

      if(resolved)
        {
         g_pendingSetups[i].isResolved   = true;
         g_pendingSetups[i].isWin        = isWin;
         g_pendingSetups[i].resolvedTime = barTime;

         RegisterOutcome(g_pendingSetups[i].patternKey, isWin);
         AppendResultToFile(g_pendingSetups[i]);

         ArrayRemove(g_pendingSetups, i, 1); // sudah dicatat ke agregat, tidak perlu disimpan individual
        }
     }
  }

//======================================================================
// FUNGSI UTAMA
//======================================================================
void SMC_Stats_Update(ENUM_TIMEFRAMES tf, bool isNewBar)
  {
   if(!InpEnableStats || !isNewBar)
      return;

   BiasState bs = GetBiasState();
   if(bs.decision == DECISION_ENTRY_OK)
      RegisterNewSetup(tf, bs);

   EvaluatePendingSetups(tf);
  }

//======================================================================
// ACCESSOR
//======================================================================
bool GetWinRateForPattern(string patternKey, PatternStats &outStats)
  {
   for(int i = 0; i < ArraySize(g_patternStats); i++)
      if(g_patternStats[i].patternKey == patternKey)
        {
         outStats = g_patternStats[i];
         return true;
        }
   return false;
  }

// Versi untuk dashboard: hitung key dari kondisi SAAT INI, ambil statistiknya.
bool GetWinRateForCurrentPattern(PatternStats &outStats)
  {
   BiasState bs = GetBiasState();
   AMDState amd = GetAMDState();
   MarketConditionState mc = GetMarketCondition();

   string key = BuildPatternKey(bs.ltfBias, amd.phase, mc.condition);
   return GetWinRateForPattern(key, outStats);
  }

#endif // SMC_STATS_MQH
