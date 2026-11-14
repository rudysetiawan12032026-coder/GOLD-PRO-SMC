//+------------------------------------------------------------------+
//|                                            SMC_RenderDashboard.mqh |
//|                                                                  |
//| Fase 5 - File 20/24 : SMC Pro System (REVISI v3)                 |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Dashboard lengkap 4 blok: Bias & Struktur, Cerita Market,      |
//|   Waktu & Berita, Statistik - plus shading killzone sesi.        |
//|                                                                  |
//| CATATAN REVISI v3 (penting - baca sebelum ubah file ini):        |
//|   v1: 19 object OBJ_LABEL terpisah, posisi manual per baris -    |
//|       urutan kebalik karena asumsi arah Y salah untuk corner=1.  |
//|   v2: digabung jadi SATU object multi-baris pakai "\n" - GAGAL,  |
//|       OBJ_LABEL di MT5 tidak mendukung newline sama sekali, teks |
//|       jadi nyambung satu baris panjang.                         |
//|   v3 (ini): balik ke banyak object per baris seperti v1, TAPI    |
//|       pakai InpDashboardCorner default = 0 (kiri-atas) yang      |
//|       perilaku Y-nya paling standar & terdokumentasi jelas di    |
//|       MQL5 (Y selalu tumbuh ke BAWAH dari titik origin kiri-atas,|
//|       tidak ambigu seperti corner lain). Kalau kamu baru ganti   |
//|       dari v1/v2 ke v3 ini, LEPAS indikator dari chart lalu      |
//|       pasang ulang dari awal (bukan cuma compile ulang) supaya   |
//|       tidak kebawa nilai input lama yang tersimpan di chart.     |
//+------------------------------------------------------------------+
#ifndef SMC_RENDERDASHBOARD_MQH
#define SMC_RENDERDASHBOARD_MQH

#include "..\Core\SMC_Config.mqh"
#include "..\Detection\SMC_Structure.mqh"
#include "..\Analysis\SMC_Scoring.mqh"
#include "..\Analysis\SMC_Session.mqh"
#include "..\Analysis\SMC_AMD.mqh"
#include "..\Analysis\SMC_NewsFilter.mqh"
#include "..\Analysis\SMC_Stats.mqh"
#include "..\Detection\SMC_MarketCondition.mqh"
#include "SMC_ObjectPool.mqh"
#include "..\Narrative\SMC_Narrative.mqh"
#include "..\Detection\SMC_SupplyDemand.mqh"
#include "..\Analysis\SMC_MultiTFEntry.mqh"

//======================================================================
// HELPER: satu baris teks dashboard di posisi baris ke-`row`
// (row 0 = paling atas, bertambah ke bawah - lurus, tidak dibalik-balik)
//======================================================================
void DashboardLine(int row, string text, color clr)
  {
   string name = SMC_OBJ_PREFIX + "DASH_ROW_" + IntegerToString(row);
   int y = InpDashboardOffsetY + row * 15;
   CreateOrUpdateScreenLabel(name, InpDashboardOffsetX, y, text, clr, 9, InpDashboardCorner);
  }

string BiasDots(ENUM_BIAS b)
  {
   switch(b)
     {
      case BIAS_BULLISH: return "###";
      case BIAS_BEARISH: return "***";
      default:            return "...";
     }
  }

//======================================================================
// FUNGSI UTAMA DASHBOARD
//======================================================================
void RenderDashboardPanel()
  {
   if(!InpShowDashboard)
      return;

   const int totalRows = 36; // +4 Skenario, +4 Paus (H1), +4 Entry Multi-TF
   int panelHeight = totalRows * 15 + 16;
   int panelWidth  = 300;
   CreateOrUpdateScreenRectangle(SMC_OBJ_PREFIX + "DASH_BG",
                                  InpDashboardOffsetX - 8, InpDashboardOffsetY - 8,
                                  panelWidth, panelHeight,
                                  AdaptPanelBackground(), InpDashboardCorner, AdaptPanelBorder());

   int row = 0;
   BiasState bs  = GetBiasState();
   AMDState  amd = GetAMDState();
   MarketConditionState mc = GetMarketCondition();

   color textPrimary = GetAdaptiveTextColor();
   color textMuted    = GetAdaptiveMutedTextColor();

   DashboardLine(row++, "=== SMC PRO DASHBOARD ===", textPrimary);

   // --- WARNING: backfill belum/tidak berhasil - skor di bawah ini bisa
   //     jadi belum representatif (struktur baru dibangun dari live). ---
   if(!IsStructureBackfilled())
      DashboardLine(row++, "!! Backfill belum selesai - skor sementara !!", AdaptAccentColor(clrOrange));

   // --- BLOK 1: Bias & Struktur ---
   DashboardLine(row++, StringFormat("HTF (%s): %s %s", EnumToString(InpHTF),
                 EnumToString(bs.htfBias), BiasDots(bs.htfBias)), textMuted);
   DashboardLine(row++, StringFormat("MTF (%s): %s %s", EnumToString(InpMTF),
                 EnumToString(bs.mtfBias), BiasDots(bs.mtfBias)), textMuted);
   DashboardLine(row++, StringFormat("LTF: %s %s", EnumToString(bs.ltfBias), BiasDots(bs.ltfBias)), textPrimary);

   string decisionText = (bs.decision == DECISION_ENTRY_OK) ? "ENTRY OK" :
                         (bs.decision == DECISION_WATCH ? "WATCH" : "NO ZONE");
   color decisionColor = (bs.decision == DECISION_ENTRY_OK) ? AdaptAccentColor(clrLime) :
                         (bs.decision == DECISION_WATCH ? AdaptAccentColor(clrYellow) : textMuted);
   DashboardLine(row++, StringFormat("Confluence: %.0f%% [%s]", bs.scoreBreakdown.scoreTotal, decisionText), decisionColor);

   // --- BREAKDOWN SKOR (diminta untuk diagnosis Bug 3 - lihat brief) ---
   // Ditampilkan APA ADANYA, tanpa bulat-membulatkan cerita: kalau angkanya
   // aneh, ini yang harus terlihat aneh duluan, bukan disembunyikan di balik
   // satu angka total.
   POIScore sc = bs.scoreBreakdown;
   DashboardLine(row++, StringFormat("  Structure : %.0f (w=%.0f%%)", sc.scoreStructure, g_normalizedWeights[0]), textMuted);
   DashboardLine(row++, StringFormat("  Liquidity : %.0f (w=%.0f%%)", sc.scoreLiquidity, g_normalizedWeights[1]), textMuted);
   DashboardLine(row++, StringFormat("  Zone      : %.0f (w=%.0f%%)", sc.scoreZone, g_normalizedWeights[2]), textMuted);
   DashboardLine(row++, StringFormat("  POI Qual. : %.0f (w=%.0f%%)", sc.scorePOIQuality, g_normalizedWeights[3]), textMuted);
   DashboardLine(row++, StringFormat("  LTF Conf. : %.0f (w=%.0f%%)", sc.scoreLTFConfirm, g_normalizedWeights[4]), textMuted);
   DashboardLine(row++, StringFormat("  Market Cd : %.0f (w=%.0f%%)", sc.scoreMarketCondition, g_normalizedWeights[5]), textMuted);

   row++; // spasi

   // --- BLOK BARU: Skenario ---
   // Ini yang bikin dashboard "hidup" - bukan cuma "target ke A", tapi
   // "kalau tembus A lanjut ke B, kalau gagal balik ke C". Prioritas
   // pertama: kalau harga MASIH TERKURUNG di range matang (Fase 5,
   // IsInRange()), cerita bias-searah TIDAK relevan dulu - yang lebih
   // jujur adalah "belum ada arah, tunggu breakout arah mana". Kalau
   // tidak sedang di range (sudah breakout, atau belum ada range
   // matang sama sekali), baru pakai skenario target-searah-bias biasa.
   DashboardLine(row++, "-- Skenario --", textMuted);

   RangeInfo activeRange;
   bool inMatureRange = IsInRange() && GetCurrentRange(activeRange);

   if(inMatureRange)
     {
      DashboardLine(row++, StringFormat("Range aktif %s - %s (%d bar) - tunggu breakout",
                    DoubleToString(activeRange.lowPrice, _Digits),
                    DoubleToString(activeRange.highPrice, _Digits),
                    activeRange.duration), AdaptAccentColor(clrOrange));

      // FIX: cari target dari BATAS RANGE, bukan dari curPrice - dan
      // secara eksplisit LEWATI level batas range itu sendiri
      // (GetSecondNearestLiquidityTarget dengan excludePrice=batas
      // range). Kalau dicari dari curPrice, target terdekat sering
      // KEBETULAN adalah batas range itu sendiri (karena titik tertinggi
      // range biasanya memang bekas swing high yang jadi liquidity pool)
      // - hasilnya tautologi: "kalau tembus atas, target ke atas itu
      // sendiri". Sekarang target yang ditampilkan benar-benar di LUAR
      // range, bukan range-nya sendiri.
      LiquidityPool upTarget, downTarget;
      bool hasUp   = GetSecondNearestLiquidityTarget(true, activeRange.highPrice, activeRange.highPrice, upTarget);
      bool hasDown = GetSecondNearestLiquidityTarget(false, activeRange.lowPrice, activeRange.lowPrice, downTarget);

      string upText   = hasUp   ? StringFormat("BSL @ %s", DoubleToString(upTarget.price, _Digits))   : "belum ada target";
      string downText = hasDown ? StringFormat("SSL @ %s", DoubleToString(downTarget.price, _Digits)) : "belum ada target";
      DashboardLine(row++, StringFormat("Tembus atas -> %s | Tembus bawah -> %s", upText, downText), textPrimary);
     }
   else if(bs.ltfBias == BIAS_NEUTRAL)
     {
      DashboardLine(row++, "Bias netral - belum ada arah jelas.", textMuted);
      row++; // baris kosong pengganti baris ke-2 yang tidak terisi, biar layout konsisten
     }
   else
     {
      bool   wantBuySide  = (bs.ltfBias == BIAS_BULLISH);
      double curPrice     = iClose(_Symbol, PERIOD_CURRENT, 1);
      LiquidityPool target1, target2;
      bool hasTarget1 = GetNearestLiquidityTarget(wantBuySide, curPrice, target1);

      if(hasTarget1)
        {
         string sideWord = wantBuySide ? "BSL" : "SSL";
         if(GetSecondNearestLiquidityTarget(wantBuySide, curPrice, target1.price, target2))
            DashboardLine(row++, StringFormat("Jika tembus %s @ %s: lanjut ke %s @ %s",
                          sideWord, DoubleToString(target1.price, _Digits),
                          sideWord, DoubleToString(target2.price, _Digits)), textPrimary);
         else
            DashboardLine(row++, StringFormat("Jika tembus %s @ %s: belum ada target lanjutan",
                          sideWord, DoubleToString(target1.price, _Digits)), textPrimary);
        }
      else
        {
         DashboardLine(row++, "Belum ada target likuiditas searah bias.", textMuted);
        }

      OrderBlock anchorOB;
      if(GetNearestUnmitigatedOB(wantBuySide, curPrice, anchorOB))
         DashboardLine(row++, StringFormat("Jika gagal tembus: balik ke %s @ %s",
                       wantBuySide ? "Bullish OB" : "Bearish OB",
                       DoubleToString(anchorOB.ceLevel, _Digits)), textPrimary);
      else
         DashboardLine(row++, "Jika gagal tembus: belum ada pijakan jelas.", textMuted);
     }

   row++; // spasi

   // --- BLOK 2: Cerita Market ---
   DashboardLine(row++, "-- Market Story --", textMuted);
   string condText = (mc.condition == CONDITION_TRENDING) ? "TRENDING" :
                     (mc.condition == CONDITION_RANGING ? "RANGING" : "COMPRESSED");
   DashboardLine(row++, StringFormat("Condition: %s (ER=%.2f)", condText, mc.efficiencyRatio), textPrimary);

   string phaseText = (amd.phase == AMD_ACCUMULATION) ? "Accumulation" :
                      (amd.phase == AMD_MANIPULATION ? "Manipulation" :
                      (amd.phase == AMD_DISTRIBUTION ? "Distribution" : "-"));
   DashboardLine(row++, StringFormat("AMD Phase: %s%s", phaseText, amd.isJudasSwing ? " [JUDAS]" : ""),
                 amd.isJudasSwing ? AdaptAccentColor(clrOrange) : textPrimary);

   row++; // spasi

   // --- BLOK BARU: Paus (H1) - modul Supply/Demand, BERDIRI SENDIRI,
   //     TIDAK memengaruhi Confluence/ENTRY OK di atas. Murni informasi
   //     tambahan (jejak institusi di TF lebih besar).
   if(InpEnableSupplyDemand)
     {
      DashboardLine(row++, "-- Paus (H1) --", textMuted);
      double curPriceSD = iClose(_Symbol, PERIOD_CURRENT, 1);

      SDZone demandZone, supplyZone;
      bool hasDemand = GetNearestSDZone(true, curPriceSD, demandZone);
      bool hasSupply = GetNearestSDZone(false, curPriceSD, supplyZone);

      if(hasDemand)
         DashboardLine(row++, StringFormat("Demand terdekat: %s @ %s-%s (%s, %d bar)",
                       SDPatternToString(demandZone.pattern),
                       DoubleToString(demandZone.low, _Digits), DoubleToString(demandZone.high, _Digits),
                       demandZone.isDemand ? "Demand" : "Supply", demandZone.baseCandleCount),
                       AdaptAccentColor(clrMediumPurple));
      else
         DashboardLine(row++, "Demand terdekat: belum ada.", textMuted);

      if(hasSupply)
         DashboardLine(row++, StringFormat("Supply terdekat: %s @ %s-%s (%d bar)",
                       SDPatternToString(supplyZone.pattern),
                       DoubleToString(supplyZone.low, _Digits), DoubleToString(supplyZone.high, _Digits),
                       supplyZone.baseCandleCount),
                       AdaptAccentColor(clrTeal));
      else
         DashboardLine(row++, "Supply terdekat: belum ada.", textMuted);

      row++; // spasi
     }

   // --- BLOK BARU: Entry Multi-TF - permintaan eksplisit: setiap TF
   //     (M1, M5 default) dinilai BERDIRI SENDIRI, TIDAK wajib selaras
   //     HTF/MTF seperti Confluence utama. Kalau salah satu TF belum
   //     punya arah/zona jelas, baris itu bilang jujur "belum ada" -
   //     bukan dipaksakan.
   if(InpEnableMultiTFEntry)
     {
      DashboardLine(row++, "-- Entry Multi-TF (berdiri sendiri) --", textMuted);

      ENUM_TIMEFRAMES multiTFs[2] = {InpMultiTFEntry1, InpMultiTFEntry2};
      for(int m = 0; m < 2; m++)
        {
         MultiTFEntryInfo info;
         bool hasInfo = ComputeMultiTFEntry(multiTFs[m], info);
         string tfName = EnumToString(multiTFs[m]);
         StringReplace(tfName, "PERIOD_", "");

         if(hasInfo)
            DashboardLine(row++, StringFormat("%s: %s | Entry %s | SL %s | TP %s | R:R 1:%.1f",
                          tfName, info.bias == BIAS_BULLISH ? "BUY" : "SELL",
                          DoubleToString(info.entry, _Digits), DoubleToString(info.sl, _Digits),
                          DoubleToString(info.tp, _Digits), info.riskReward),
                          info.bias == BIAS_BULLISH ? AdaptAccentColor(clrLime) : AdaptAccentColor(clrRed));
         else
            DashboardLine(row++, StringFormat("%s: belum ada entry jelas (arah/zona TF ini sendiri belum matang).", tfName),
                          textMuted);
        }

      row++; // spasi
     }

   // --- BLOK 3: Waktu & Berita ---
   DashboardLine(row++, "-- Time & News --", textMuted);
   ENUM_SESSION current = GetCurrentSession();
   string sessionText = (current == SESSION_ASIA) ? "Asia" : (current == SESSION_LONDON) ? "London KZ" :
                        (current == SESSION_NEWYORK) ? "New York KZ" : "Off-session";
   DashboardLine(row++, StringFormat("Session: %s", sessionText), IsKillzoneActive() ? AdaptAccentColor(clrLime) : textMuted);

   ENUM_SESSION nextSession;
   string countdown = GetNextKillzoneCountdown(nextSession);
   DashboardLine(row++, StringFormat("Next KZ: %s in %s",
                 nextSession == SESSION_LONDON ? "London" : "New York", countdown), textPrimary);

   NewsEvent nextNews;
   if(InpEnableNewsFilter && GetNextNewsEvent(nextNews))
     {
      long minTo = (nextNews.eventTime - TimeCurrent()) / 60;
      string countdownStr = StringFormat("%02d:%02d", (int)(minTo / 60), (int)(minTo % 60));
      string newsLine = StringFormat("News: %s (%s) in %s", nextNews.name, nextNews.currency, countdownStr);
      DashboardLine(row++, newsLine, IsNewsBlackout() ? AdaptAccentColor(clrRed) : textPrimary);
     }
   else
     {
      DashboardLine(row++, "News: (tidak ada event relevan)", textMuted);
     }

   row++; // spasi

   // --- BLOK 4: Statistik ---
   DashboardLine(row++, "-- Statistics --", textMuted);
   PatternStats stats;
   if(InpEnableStats && GetWinRateForCurrentPattern(stats))
     {
      if(stats.totalCount >= InpStatsMinSampleSize)
         DashboardLine(row++, StringFormat("Pattern win-rate: %.0f%% (n=%d)", stats.winRatePercent, stats.totalCount), textPrimary);
      else
         DashboardLine(row++, StringFormat("Pattern win-rate: n=%d (min %d)", stats.totalCount, InpStatsMinSampleSize), textMuted);
     }
   else
     {
      DashboardLine(row++, "Pattern win-rate: belum ada data", textMuted);
     }
  }

//======================================================================
// SHADING KILLZONE (garis vertikal awal sesi hari ini)
//======================================================================
void RenderKillzoneShading()
  {
   if(!InpShowKillzoneShading)
      return;

   datetime asiaStart   = GetSessionStartTimeToday(SESSION_ASIA);
   datetime londonStart = GetSessionStartTimeToday(SESSION_LONDON);
   datetime nyStart      = GetSessionStartTimeToday(SESSION_NEWYORK);

   CreateOrUpdateVLine(SMC_OBJ_PREFIX + "KZ_ASIA",   asiaStart,   AdaptAccentColor(GetColorForKillzone(SESSION_ASIA)));
   CreateOrUpdateVLine(SMC_OBJ_PREFIX + "KZ_LONDON", londonStart, AdaptAccentColor(GetColorForKillzone(SESSION_LONDON)));
   CreateOrUpdateVLine(SMC_OBJ_PREFIX + "KZ_NY",     nyStart,     AdaptAccentColor(GetColorForKillzone(SESSION_NEWYORK)));
  }

//======================================================================
// NARRATIVE LABEL (satu baris TEPAT DI BAWAH panel dashboard)
//======================================================================
void RenderNarrativeLabel()
  {
   if(!InpShowNarrativeLabel)
      return;

   BiasState bs = GetBiasState();
   string name = SMC_OBJ_PREFIX + "NARRATIVE";
   const int totalRows = 35;
   int y = InpDashboardOffsetY + totalRows * 15 + 10; // tepat di bawah panel background
   CreateOrUpdateScreenRectangle(SMC_OBJ_PREFIX + "NARR_BG", InpDashboardOffsetX - 8, y - 4,
                                  300, 18, AdaptPanelBackground(), InpDashboardCorner, AdaptPanelBorder());
   CreateOrUpdateScreenLabel(name, InpDashboardOffsetX, y, bs.narrativeShort, GetAdaptiveMutedTextColor(), 8, InpDashboardCorner);
  }

//======================================================================
// FUNGSI UTAMA
//======================================================================
void SMC_RenderDashboard()
  {
   RenderDashboardPanel();
   RenderKillzoneShading();
   RenderNarrativeLabel();
  }

#endif // SMC_RENDERDASHBOARD_MQH