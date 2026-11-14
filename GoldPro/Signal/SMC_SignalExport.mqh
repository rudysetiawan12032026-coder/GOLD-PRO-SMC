//+------------------------------------------------------------------+
//|                                             SMC_SignalExport.mqh |
//|                                                                  |
//| Fase 6 - File 21/24 : SMC Pro System                             |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Mendefinisikan dan menulis kontrak data terstruktur yang akan  |
//|   dibaca EA Telegram (SMC_Telegram_EA.mq5, Fase 7). Dipisah dari |
//|   SMC_Alert.mqh supaya "apa yang diekspor" tidak campur dengan   |
//|   "kapan suara alert bunyi".                                     |
//|                                                                  |
//| FORMAT: file JSON (snapshot state terkini, DITIMPA tiap update - |
//| bukan log history, karena history sudah ditangani SMC_Stats.mqh) |
//| ditulis ke MQL5/Files/, PLUS beberapa Global Variable untuk akses|
//| cepat tanpa perlu parsing JSON kalau EA hanya butuh angka utama. |
//| Field `schemaVersion` disertakan supaya EA Telegram bisa dites   |
//| kompatibilitasnya kalau format ini berubah di kemudian hari.     |
//+------------------------------------------------------------------+
#ifndef SMC_SIGNALEXPORT_MQH
#define SMC_SIGNALEXPORT_MQH

#include "..\Core\SMC_Config.mqh"
#include "..\Analysis\SMC_Scoring.mqh"
#include "..\Analysis\SMC_AMD.mqh"
#include "..\Analysis\SMC_NewsFilter.mqh"
#include "..\Analysis\SMC_Stats.mqh"
#include "..\Detection\SMC_MarketCondition.mqh"
#include "..\Analysis\SMC_Session.mqh"
#include "..\Analysis\SMC_MultiTFEntry.mqh"

#define SMC_SIGNAL_SCHEMA_VERSION 2 // v2: tambah field multiTFEntries (M1/M5) untuk bot eksekusi Fase 1

//======================================================================
// INIT
//======================================================================
void SMC_SignalExport_Init()
  {
  }

//======================================================================
// HELPER: escape string sederhana untuk JSON (kutip & backslash)
//======================================================================
string JSONEscape(string s)
  {
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   return s;
  }

//======================================================================
// REKOMENDASI ENTRY - BARU (untuk Telegram). Murni komposisi dari
// fungsi yang SUDAH ADA (GetNearestUnmitigatedOB, GetStopLossForBuy/
// Sell, GetNearestLiquidityTarget, GetSecondNearestLiquidityTarget) -
// tidak ada deteksi baru. Entry disarankan di CE-level OB (area
// retest), bukan harga pasar sekarang - lebih konsisten dengan disiplin
// SMC klasik (masuk saat harga kembali ke POI, bukan mengejar harga).
//======================================================================
string BuildEntryRecommendationJSON(ENUM_BIAS ltfBias, double currentPrice)
  {
   if(ltfBias == BIAS_NEUTRAL)
      return "null";

   bool wantBullish = (ltfBias == BIAS_BULLISH);

   OrderBlock anchorOB;
   if(!GetNearestUnmitigatedOB(wantBullish, currentPrice, anchorOB, true))
      return "null"; // tidak ada pijakan valid - jangan rekomendasikan apapun

   double entryPrice = anchorOB.ceLevel;
   double slPrice     = wantBullish ? GetStopLossForBuy(anchorOB) : GetStopLossForSell(anchorOB);

   LiquidityPool tp1, tp2;
   bool hasTP1 = GetNearestLiquidityTarget(wantBullish, currentPrice, tp1);
   bool hasTP2 = hasTP1 && GetSecondNearestLiquidityTarget(wantBullish, currentPrice, tp1.price, tp2);

   if(!hasTP1)
      return "null"; // tidak ada target - rekomendasi tidak lengkap, jangan setengah-setengah

   double riskPoints   = MathAbs(entryPrice - slPrice);
   double rewardPoints = MathAbs(tp1.price - entryPrice);
   double rr = (riskPoints > 0) ? rewardPoints / riskPoints : 0.0;

   string tp2Json = hasTP2 ? StringFormat("%.5f", tp2.price) : "null";

   // FIX (bug ditemukan - EA tidak pernah bisa baca field ini): parser
   // sederhana di SMC_Telegram_EA.mq5 mencari format "key": "value" DENGAN
   // spasi setelah titik dua (sama seperti gaya BuildSignalJSON utama) -
   // sebelumnya field bersarang ini ditulis TANPA spasi, jadi walau
   // datanya ADA di file, EA tidak pernah berhasil mengekstraknya.
   return StringFormat(
      "{\"direction\": \"%s\", \"entry\": %.5f, \"sl\": %.5f, \"tp1\": %.5f, \"tp2\": %s, \"riskReward\": %.2f}",
      wantBullish ? "BUY" : "SELL", entryPrice, slPrice, tp1.price, tp2Json, rr);
  }

// SKENARIO - BARU (untuk Telegram). Sama persis logic yang sudah dipakai
// SMC_RenderDashboard.mqh (blok "Skenario") - komposisi ulang jadi JSON,
// bukan logic baru. Konsisten: apa yang muncul di dashboard = apa yang
// dikirim ke Telegram.
string BuildScenarioJSON(ENUM_BIAS ltfBias, double currentPrice)
  {
   RangeInfo activeRange;
   if(IsInRange() && GetCurrentRange(activeRange))
     {
      LiquidityPool upT, downT;
      bool hasUp   = GetSecondNearestLiquidityTarget(true, activeRange.highPrice, activeRange.highPrice, upT);
      bool hasDown = GetSecondNearestLiquidityTarget(false, activeRange.lowPrice, activeRange.lowPrice, downT);

      return StringFormat(
         "{\"inRange\": true, \"rangeHigh\": %.5f, \"rangeLow\": %.5f, \"rangeDuration\": %d, "
         "\"breakoutUpTarget\": %s, \"breakoutDownTarget\": %s}",
         activeRange.highPrice, activeRange.lowPrice, activeRange.duration,
         hasUp   ? StringFormat("%.5f", upT.price)   : "null",
         hasDown ? StringFormat("%.5f", downT.price) : "null");
     }

   if(ltfBias == BIAS_NEUTRAL)
      return "{\"inRange\": false, \"target1\": null, \"target2\": null, \"fallback\": null}";

   bool wantBullish = (ltfBias == BIAS_BULLISH);
   LiquidityPool t1, t2;
   bool hasT1 = GetNearestLiquidityTarget(wantBullish, currentPrice, t1);
   bool hasT2 = hasT1 && GetSecondNearestLiquidityTarget(wantBullish, currentPrice, t1.price, t2);

   OrderBlock anchorOB;
   bool hasAnchor = GetNearestUnmitigatedOB(wantBullish, currentPrice, anchorOB, true);

   return StringFormat(
      "{\"inRange\": false, "
      "\"target1\": %s, \"target1Pips\": %s, "
      "\"target2\": %s, "
      "\"fallback\": %s}",
      hasT1 ? StringFormat("%.5f", t1.price) : "null",
      hasT1 ? StringFormat("%.1f", PriceDistanceToPips(MathAbs(t1.price - currentPrice))) : "null",
      hasT2 ? StringFormat("%.5f", t2.price) : "null",
      hasAnchor ? StringFormat("%.5f", anchorOB.ceLevel) : "null");
  }

//======================================================================
// BUILD MULTI-TF ENTRIES JSON (BARU - fondasi bot eksekusi Fase 1)
//   Timestamp per-TF pakai waktu candle CLOSED terakhir di TF itu -
//   ini penanda "kesegaran" alami: berubah tiap kali bar baru terbentuk
//   di TF tersebut, dipakai Python untuk dedup (jangan proses sinyal
//   M1 yang SAMA berkali-kali dalam 1 candle M1 yang sama).
//======================================================================
string BuildSingleMultiTFEntryJSON(ENUM_TIMEFRAMES tf)
  {
   if(!InpEnableMultiTFEntry)
      return "null";

   MultiTFEntryInfo info;
   if(!ComputeMultiTFEntry(tf, info))
      return "null"; // TF ini belum punya arah/zona jelas - jujur null, bukan dipaksa

   return StringFormat(
      "{\"timestamp\": \"%s\", \"direction\": \"%s\", \"entry\": %.5f, \"sl\": %.5f, \"tp\": %.5f, \"riskReward\": %.2f}",
      TimeToString(iTime(_Symbol, tf, 1), TIME_DATE | TIME_MINUTES | TIME_SECONDS),
      info.bias == BIAS_BULLISH ? "BUY" : "SELL",
      info.entry, info.sl, info.tp, info.riskReward);
  }

string BuildMultiTFEntriesJSON()
  {
   return StringFormat("{\"M1\": %s, \"M5\": %s}",
                        BuildSingleMultiTFEntryJSON(InpMultiTFEntry1),
                        BuildSingleMultiTFEntryJSON(InpMultiTFEntry2));
  }

//======================================================================
// BUILD JSON SNAPSHOT
//======================================================================
string BuildSignalJSON()
  {
   BiasState bs  = GetBiasState();
   AMDState  amd = GetAMDState();
   MarketConditionState mc = GetMarketCondition();
   ENUM_SESSION session = GetCurrentSession();
   double currentPrice = iClose(_Symbol, PERIOD_CURRENT, 1);

   string nearestOBJson = "null";
   OrderBlock ob;
   bool wantBullish = (bs.ltfBias == BIAS_BULLISH);
   if(bs.ltfBias != BIAS_NEUTRAL && GetNearestUnmitigatedOB(wantBullish, currentPrice, ob, true))
     {
      nearestOBJson = StringFormat(
         "{\"high\":%.5f,\"low\":%.5f,\"isBullish\":%s,\"hasFVG\":%s,\"isConfluent\":%s}",
         ob.high, ob.low, ob.isBullish ? "true" : "false",
         ob.hasFVG ? "true" : "false", ob.isConfluent ? "true" : "false");
     }

   string newsJson = "null";
   NewsEvent nextNews;
   if(GetNextNewsEvent(nextNews))
     {
      long minTo = (nextNews.eventTime - TimeCurrent()) / 60;
      newsJson = StringFormat("{\"name\":\"%s\",\"currency\":\"%s\",\"minutesTo\":%d,\"blackout\":%s}",
                               JSONEscape(nextNews.name), nextNews.currency, (int)minTo,
                               IsNewsBlackout() ? "true" : "false");
     }

   string statsJson = "null";
   PatternStats stats;
   if(InpEnableStats && GetWinRateForCurrentPattern(stats))
     {
      statsJson = StringFormat("{\"winRate\":%.1f,\"sampleCount\":%d,\"reliable\":%s}",
                                stats.winRatePercent, stats.totalCount,
                                (stats.totalCount >= InpStatsMinSampleSize) ? "true" : "false");
     }

   string entryRecJson = BuildEntryRecommendationJSON(bs.ltfBias, currentPrice);
   string scenarioJson = BuildScenarioJSON(bs.ltfBias, currentPrice);
   string multiTFJson  = BuildMultiTFEntriesJSON();

   string json = StringFormat(
      "{\n"
      "  \"schemaVersion\": %d,\n"
      "  \"symbol\": \"%s\",\n"
      "  \"timeframe\": \"%s\",\n"
      "  \"timestamp\": \"%s\",\n"
      "  \"currentPrice\": %.5f,\n"
      "  \"htfBias\": \"%s\",\n"
      "  \"mtfBias\": \"%s\",\n"
      "  \"ltfBias\": \"%s\",\n"
      "  \"confluenceScore\": %.1f,\n"
      "  \"decision\": \"%s\",\n"
      "  \"amdPhase\": \"%s\",\n"
      "  \"isJudasSwing\": %s,\n"
      "  \"marketCondition\": \"%s\",\n"
      "  \"session\": \"%s\",\n"
      "  \"nearestOB\": %s,\n"
      "  \"scenario\": %s,\n"
      "  \"entryRecommendation\": %s,\n"
      "  \"multiTFEntries\": %s,\n"
      "  \"nextNews\": %s,\n"
      "  \"patternStats\": %s,\n"
      "  \"narrative\": \"%s\"\n"
      "}",
      SMC_SIGNAL_SCHEMA_VERSION, _Symbol, GP_TFName(), TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
      currentPrice,
      EnumToString(bs.htfBias), EnumToString(bs.mtfBias), EnumToString(bs.ltfBias),
      bs.scoreBreakdown.scoreTotal, EnumToString(bs.decision),
      EnumToString(amd.phase), amd.isJudasSwing ? "true" : "false",
      EnumToString(mc.condition), EnumToString(session),
      nearestOBJson, scenarioJson, entryRecJson, multiTFJson, newsJson, statsJson, JSONEscape(bs.narrativeText));

   return json;
  }

//======================================================================
// TULIS KE FILE JSON (snapshot - ditimpa tiap kali, bukan append)
//======================================================================
// PERBAIKAN GoldPro: nama file & key Global Variable menyertakan simbol + TF asli
// (SMC lama memakai EnumToString(PERIOD_CURRENT) = "PERIOD_CURRENT", sehingga
// beberapa chart saling menimpa satu file/variabel yang sama).
string GP_TFName()
  {
   return StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7);   // "PERIOD_M5" -> "M5"
  }

string GP_SignalFileName()
  {
   return InpSignalExportFile + "_" + _Symbol + "_" + GP_TFName() + ".json";
  }

void WriteSignalToFile()
  {
   string fname = GP_SignalFileName();
   int handle = FileOpen(fname, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("[GoldPro_SignalExport] ERROR: Gagal membuka %s untuk menulis (err=%d)",
                  fname, GetLastError());
      return;
     }
   FileWriteString(handle, BuildSignalJSON());
   FileClose(handle);
  }

//======================================================================
// TULIS GLOBAL VARIABLE (akses cepat tanpa parsing JSON)
//   Key menyertakan Symbol+Period supaya tidak collision antar-chart.
//======================================================================
void WriteSignalGlobalVariables()
  {
   BiasState bs = GetBiasState();
   string keyPrefix = SMC_GV_PREFIX + _Symbol + "_" + GP_TFName() + "_";

   GlobalVariableSet(keyPrefix + "Score", bs.scoreBreakdown.scoreTotal);
   GlobalVariableSet(keyPrefix + "Decision", (double)bs.decision);
   GlobalVariableSet(keyPrefix + "LTFBias", (double)bs.ltfBias);
   GlobalVariableSet(keyPrefix + "LastUpdate", (double)TimeCurrent());
  }

//======================================================================
// FUNGSI UTAMA
//======================================================================
void SMC_SignalExport_Update(bool isNewBar)
  {
   if(!InpEnableSignalExport || !isNewBar)
      return;

   WriteSignalToFile();
   WriteSignalGlobalVariables();
  }

#endif // SMC_SIGNALEXPORT_MQH