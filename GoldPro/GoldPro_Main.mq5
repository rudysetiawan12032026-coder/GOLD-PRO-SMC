//+------------------------------------------------------------------+
//|                                                 GoldPro_Main.mq5 |
//|                                                                  |
//| GoldPro System - Tahap 1 (Fondasi)                               |
//|   = modul SMC Pro System (diadopsi & diperbaiki)                 |
//|   + GoldDayMap (peta harian, straddle EQ, peluang live, jurnal)  |
//|                                                                  |
//| SMC_Pro_System asli TIDAK disentuh. Perbaikan di proyek ini:     |
//|   1. Sesi/killzone ikut jam lokal bursa & DST (GP_Time.mqh)      |
//|   2. Statistik CSV bisa dibaca ulang (SMC_Stats.mqh)             |
//|   3. Ekspor sinyal per simbol+TF, tidak saling menimpa           |
//|   4. Prefix objek/GV/file sendiri (GP_) -> bisa jalan berdampingan|
//|      dengan SMC_Main & GoldDayMap standalone.                    |
//+------------------------------------------------------------------+
#property copyright "GoldPro System"
#property version   "1.00"
#property description "GoldPro: SMC (diperbaiki) + peta harian GoldDayMap dalam satu indikator."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#include "Core\SMC_Types.mqh"
#include "Core\SMC_Config.mqh"
#include "Core\SMC_Utils.mqh"
#include "Core\GP_Time.mqh"
#include "Core\GP_TouchTime.mqh"
#include "Core\GP_Master.mqh"            // 10 Okt 2026: satu CHART UTAMA per simbol (Telegram, CSV, rapor, alert)
#include "Core\GP_Notify.mqh"

#include "Detection\SMC_Structure.mqh"
#include "Detection\SMC_Zones.mqh"
#include "Detection\SMC_POI.mqh"
#include "Detection\SMC_Liquidity.mqh"
#include "Detection\SMC_MarketCondition.mqh"
#include "Detection\SMC_SupplyDemand.mqh"

#include "Analysis\SMC_Session.mqh"
#include "Analysis\SMC_AMD.mqh"
#include "Analysis\SMC_NewsFilter.mqh"
#include "Analysis\SMC_MTF.mqh"
#include "Analysis\SMC_Scoring.mqh"
#include "Analysis\SMC_Stats.mqh"

#include "Narrative\SMC_Narrative.mqh"

#include "Render\SMC_ObjectPool.mqh"
#include "Render\SMC_RenderStructure.mqh"
#include "Render\SMC_RenderPOI.mqh"
#include "Render\SMC_RenderLiquidity.mqh"
#include "Render\SMC_RenderSupplyDemand.mqh"
#include "Render\SMC_RenderDashboard.mqh"

#include "Signal\SMC_SignalExport.mqh"
#include "Signal\SMC_Alert.mqh"

#include "Signal\GP_Precision.mqh"
#include "Map\GP_DayMap.mqh"
#include "Signal\GP_NewsBoard.mqh"
#include "Signal\GP_BoxWatch.mqh"
#include "Signal\GP_Health.mqh"          // 10 Okt 2026: cek versi indikator / EA + baris alarm kalibrasi (kiri bawah)
#include "Signal\GP_TembusBalik.mqh"     // 11 Okt 2026: tombol "Tembus Balik" - jam positif 23 & 03-07 WITA, rekap indikator, Telegram
#include "Map\GP_Wave.mqh"               // 14 Okt 2026: tombol "Gelombang" - range swing lebar + gelombang awal -> target (gelombang.py)
#include "Signal\GP_GarisTg.mqh"         // 15 Okt 2026: notif Telegram sentuh garis Gelombang (sentuh / candle tutup / konfirmasi / hasil)
#include "Render\GP_LabelFix.mqh"        // 10 Okt 2026: label SMC digeser bila menimpa label lain; 14 Okt: + tidak menimpa tombol / panel
                                         // (dimuat sesudah GP_DayMap karena memakai posisi kolom tombol GDM::BtnColR / PanelTop)
// 10 Okt 2026 (pengguna: "kita buang"): Signal\GP_BoxSignal.mqh (tab "3 KOTAK", kotak SMC lama [TIDAK TERBUKTI]) dan
// Signal\GP_ZoneWatch.mqh (tombol "Zona OB/FVG", peluang = geometri, sumber hampir semua popup) tidak dimuat lagi.
// File-nya tetap ada di folder Signal (riwayat); tombol Radar & Panah juga dihapus (lihat GP_DayMap).

//======================================================================
// Tampilan (Tahap 3): default "bersih". Objek SMC yang tidak terbukti
// menambah keunggulan disembunyikan; semuanya bisa dinyalakan lagi.
//======================================================================
enum GPViewMode { GP_VIEW_CLEAN = 0,   // Bersih (hanya yang teruji)
                  GP_VIEW_SMC   = 1    // Lengkap SMC (semua visual SMC lama, sebagai info)
                };
input group "=== GoldPro: Tampilan chart ==="
input GPViewMode InpGPViewMode = GP_VIEW_CLEAN; // Mode tampilan (Lengkap SMC menyalakan semua visual di bawah)
input bool InpGPShowStructure   = true;    // Label struktur BOS/CHoCH
input bool InpGPShowPOI         = true;    // Kotak OB/Breaker (konteks; zona SMC > zona acak)
input bool InpGPShowPremDisc    = false;   // Kotak Premium/Discount/OTE/Equilibrium
input bool InpGPShowLiquidity   = false;   // Garis EQH/EQL/PDH/PDL, Pijakan/Tujuan, panah arah SMC
input bool InpGPShowSupplyDemand= false;   // Zona Supply/Demand "Paus" H1
input bool InpGPShowKillzones   = true;    // Garis vertikal awal killzone (jam lokal + DST)
input bool InpGPShowSMCDashboard= false;   // Dashboard SMC lama (diganti panel terpadu GoldPro)
input bool InpGPShowNarrative   = false;   // Label narasi SMC

void GP_RenderAll()
  {
   SMC_ObjectPool_BeginCycle();
   TT_Update();
   g_ttPijPrice = 0.0;   // diisi ulang oleh garis Pijakan / Tujuan bila tampil (dibaca panel GoldPro)
   g_ttTujPrice = 0.0;
   bool full = GDM::g_vSMC;   // tombol SMC / input Mode tampilan: semua visual SMC lama (kecuali dashboard lama -> panel GoldPro)
   // 14 Okt 2026: MODE TERUJI = kotak & label SMC lama (BOS / CHoCH, OB / Breaker) juga disembunyikan (tidak terbukti di uji)
   bool simple = GDM::g_vSimple && !full;
   if((InpGPShowStructure || full) && !simple) RenderStructureLabels();
   // 14 Okt 2026: tombol Gelombang menyala -> range SMC lama (Premium / OTE / EQ / Discount) disembunyikan; satu range saja
   if((InpGPShowPremDisc || full) && !GDM::g_vWave) RenderDealingRangeZones();
   if((InpGPShowPOI || full) && !simple) RenderStoryPOI();
   if(InpGPShowLiquidity || full)
     {
      RenderAnchorLine();
      RenderTargetLine();
      RenderEqualHighsLows();
      RenderDrawOnLiquidityRefs();
      RenderDirectionArrows();
     }
   if(InpGPShowSupplyDemand || full) SMC_RenderSupplyDemand();
   if(InpGPShowSMCDashboard) RenderDashboardPanel();
   if(InpGPShowKillzones || full)    RenderKillzoneShading();
   if(InpGPShowNarrative)    RenderNarrativeLabel();
   RemoveIfStale();
   EnforceCategoryLimits();
   // GoldPro (3 Okt 2026): Pijakan / Tujuan untuk EA GoldPro_Panel di chart yang sama (0 = tidak tampil)
   GlobalVariableSet("GP_PIJ_" + IntegerToString(ChartID()), g_ttPijPrice);
   GlobalVariableSet("GP_TUJ_" + IntegerToString(ChartID()), g_ttTujPrice);
   GlobalVariableSet("GP_TS_" + IntegerToString(ChartID()), (double)TimeCurrent());
   GP_FixLabels();                         // label SMC yang menimpa label lain digeser naik / turun (tampilan saja)
   GDM::RaiseButtons();                    // 14 Okt: objek SMC baru dibuat -> tombol & kotak "i" dibuat ulang agar di depan
   ChartRedraw(0);
  }

//======================================================================
// GoldPro PERBAIKAN "SMC / tombol kadang hilang" (log MT5 30 Sep: 20+ ganti TF M1/M5/M15).
// Saat ganti TF, MT5 memuat instance BARU dulu, lalu menutup instance LAMA 2-3 detik kemudian.
// Dulu OnDeinit instance lama menghapus SEMUA objek GoldPro -> tombol, panel & SMC milik instance
// baru ikut terhapus sampai candle berikutnya (5-15 mnt). Sekarang:
//   - OnDeinit hanya menghapus objek bila indikator benar-benar dilepas / chart ditutup;
//   - OnInit membersihkan sisa objek instance lama sebelum menggambar;
//   - timer memeriksa tiap 2 dtk: objek yang hilang (sebab apa pun) langsung digambar ulang,
//     plus sekali gambar ulang penuh ~6 dtk setelah mulai (instance lama pasti sudah tertutup).
//======================================================================
uint g_gpInitTick = 0;
bool g_gpSettled  = false;

void GP_CleanChartObjects()
  {
   ObjectsDeleteAll(0, SMC_OBJ_PREFIX);   // SMC (object pool)
   ObjectsDeleteAll(0, PFX);              // peta harian & panel
   ObjectsDeleteAll(0, BPFX + "B_");      // tombol (PIN "GPB_PIN_" tetap dipertahankan)
   ObjectsDeleteAll(0, BPFX + "I_");      // kotak "i" INFO di samping tombol (14 Okt 2026)
   ObjectDelete(0, BPFX + "PROBE");
   ObjectsDeleteAll(0, "GPX_");           // garis kotak tab "3 KOTAK" (modul sudah dibuang, sisa objek lama)
   ObjectsDeleteAll(0, GPS_PFX);          // setup breaker
   ObjectsDeleteAll(0, NB_PFX);           // dashboard berita
   ObjectsDeleteAll(0, "GPZ_");           // detektor zona OB/FVG (modul sudah dibuang, sisa objek lama)
   ObjectsDeleteAll(0, "GPM_RDR_");       // radar (dibuang 10 Okt, sisa objek lama)
   ObjectsDeleteAll(0, KB_PFX);           // kotak sideway
   ObjectsDeleteAll(0, GPV_PFX);          // baris cek versi / kesehatan
   ObjectsDeleteAll(0, TB_PFX);           // tembus balik (dashboard & strip bawah)
   ObjectsDeleteAll(0, WV_PFX);           // peta gelombang (14 Okt)
  }

bool GP_FinalDeinit(const int reason)
  {
   return reason == REASON_REMOVE || reason == REASON_CHARTCLOSE || reason == REASON_CLOSE ||
          reason == REASON_INITFAILED || reason == REASON_TEMPLATE;
  }

void GP_HealObjects()
  {
   bool force = (!g_gpSettled && GetTickCount() - g_gpInitTick > 6000);
   if(force)
      g_gpSettled = true;
   if(force || GDM::NeedsRepair())
      GDM::Redraw();
   if(force || SMC_PoolNeedsRepair())
      GP_RenderAll();
  }

int OnInit()
  {
   g_gpInitTick = GetTickCount();
   g_gpSettled  = false;
   GP_MasterTick();                        // chart utama? (instance TF lama yang masih memegang melepas saat ditutup)
   GP_HealthInit();
   GP_CleanChartObjects();
   if(!ValidateScoringWeights())
      Print("[GoldPro] Bobot scoring dinormalisasi otomatis - lihat pesan di atas.");

   SMC_Structure_Init();
   SMC_Structure_Backfill(PERIOD_CURRENT);
   SMC_Zones_Init();
   SMC_Zones_Update(true);
   SMC_POI_Init();
   int backfillBars = MathMin(InpVisualMaxLookbackBars * 2, iBars(_Symbol, PERIOD_CURRENT) - InpSwingLookback - 2);
   if(backfillBars > 0)
      SMC_POI_Backfill(PERIOD_CURRENT, backfillBars);
   SMC_Liquidity_Init();
   SMC_Liquidity_Backfill(PERIOD_CURRENT);
   SMC_MarketCondition_Init();
   SMC_MarketCondition_Update(PERIOD_CURRENT, true);
   SMC_SupplyDemand_Init();
   SMC_SupplyDemand_Backfill();
   SMC_AMD_Init();
   SMC_NewsFilter_Init();
   SMC_MTF_Init();
   SMC_Scoring_Init();
   SMC_Stats_Init();
   SMC_SignalExport_Init();
   SMC_Alert_Init();

   datetime u = GP_ServerToUTC(TimeCurrent());
   PrintFormat("[GoldPro] aktif %s %s | server %s = UTC %s = NY %s = London %s | sesi sekarang: %s",
               _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period),
               TimeToString(TimeCurrent(), TIME_MINUTES), TimeToString(u, TIME_MINUTES),
               TimeToString(GP_UTCToET(u), TIME_MINUTES), TimeToString(GP_UTCToLondon(u), TIME_MINUTES),
               EnumToString(GetCurrentSession()));

   GDM::Init(InpGPViewMode == GP_VIEW_SMC);   // peta harian: timer, chart shift, kunci jurnal, tombol, PIN
   GP_ExportCalendar();
   GP_ExportCalendarFull();
   return(INIT_SUCCEEDED);
  }

void OnTimer()
  {
   GP_MasterTick();      // detak chart utama (+ GP_HB untuk penjaga hidup EA Telegram)
   GDM::Timer();
   NB_Update();          // dashboard berita (hitung mundur, fase per menit/candle)
   KB_Update();          // kotak sideway: dinding, colek, tembus & bertahan (chart utama selalu, chart lain bila dashboard dibuka)
   GP_HealthTick();      // baris merah kiri bawah bila ada versi lama / EA Telegram berhenti / alarm kalibrasi
   TB_Update();          // tembus balik: dashboard per jam & strip rekap indikator di bawah chart (bila tombol aktif)
   WV_Update();          // peta gelombang: hitung ulang tiap candle chart baru, label peluang tiap 2 dtk (bila tombol aktif)
   GT_Update();          // notif Telegram sentuh garis Gelombang M15 (chart utama, jalan walau tombol mati)
   GP_HealObjects();
   GP_FixLabels();       // label lain (peta, garis kotak sideway) ikut bergerak -> cek tumpukan label SMC tiap 2 dtk
   ChartRedraw(0);
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   GDM::ChartEvent(id, lparam, dparam, sparam);
   NB_ChartEvent(id, sparam);
   KB_ChartEvent(id, sparam);
   TB_ChartEvent(id, sparam);
   WV_ChartEvent(id, sparam);
   static uint lastFix = 0;               // chart digeser / di-zoom -> posisi piksel label berubah
   if(id == CHARTEVENT_CHART_CHANGE && GetTickCount() - lastFix >= 150)
     {
      lastFix = GetTickCount();
      GP_FixLabels();
      ChartRedraw(0);
     }
   if(GDM::g_smcDirty)   // tombol SMC ditekan -> gambar ulang visual SMC sekarang
     {
      GDM::g_smcDirty = false;
      GP_RenderAll();
     }
  }

//======================================================================
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   if(rates_total < InpSwingLookback + 30)
      return(0);

   ENUM_TIMEFRAMES tf = PERIOD_CURRENT;
   bool isNewBar = IsNewBar(tf);

   bool structureChanged = SMC_Structure_Update(tf, isNewBar);
   SMC_Zones_Update(isNewBar);
   SMC_POI_Update(tf, isNewBar, structureChanged);
   SMC_Liquidity_Update(tf, isNewBar);
   SMC_MarketCondition_Update(tf, isNewBar);

   bool newHTFFlag = IsNewBar(InpHTF);
   bool newMTFFlag = IsNewBar(InpMTF);
   bool newSDFlag  = (InpSDTimeframe == InpMTF) ? newMTFFlag :
                     (InpSDTimeframe == InpHTF) ? newHTFFlag : IsNewBar(InpSDTimeframe);
   SMC_SupplyDemand_Update(isNewBar, newSDFlag);

   StructureEvent lastStructEvt;
   bool hasStructEvt = GetLastStructureEvent(lastStructEvt);
   LiquidityPool lastLiqEvt;
   bool hasLiqEvt = GetLastLiquidityEvent(lastLiqEvt);

   SMC_AMD_Update(isNewBar, hasStructEvt, lastStructEvt, hasLiqEvt, lastLiqEvt);
   SMC_NewsFilter_Update(isNewBar);
   SMC_MTF_Update(newHTFFlag, newMTFFlag);
   SMC_Scoring_Update(tf, isNewBar);
   SMC_Stats_Update(tf, isNewBar);
   SMC_Narrative_Update(tf, isNewBar);

   // GoldPro (2 Okt 2026): peluang waktu Pijakan/Tujuan/zona berubah tiap menit -> label & panel ikut diperbarui
   bool newMin = TT_Update();
   if(isNewBar || newMin)
      GP_RenderAll();

   SMC_SignalExport_Update(isNewBar);
   SMC_Alert_Update(isNewBar);

   GP_ContextAlerts();
   // setup breaker (+ jurnal). GoldPro: jurnal breaker HANYA dari chart M5 (TF riset) - dulu pemilik jurnal
   // bisa chart M1/M15 -> breaker dari TF lain tercatat (anomali "breaker jauh dari harga").
   GP_Precision_Update(GDM::g_jOwner && _Period == PERIOD_M5);
   GDM::Calculate();   // peta harian + panel terpadu (menghitung ulang sekali per bar M5 baru)
   if(newMin)
      GDM::RefreshPanel();                               // menit baru -> panel (RUTE HARGA ikut bergerak)
   static uint lastPdhl = 0;                             // peluang PDH/PDL ditembus s/d tutup: tiap 5 dtk / menit baru
   if(newMin || GetTickCount() - lastPdhl >= 5000)
     {
      lastPdhl = GetTickCount();
      GDM::PdhlUpdate();                                 // (label PDH/PDL & panel)
     }
   return(rates_total);
  }

//======================================================================
// Alert konteks: AM Fix, ENTRY OK kandidat, blackout berita
//======================================================================
void GP_ContextAlerts()
  {
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   if(InpGPAlertAMFix && dt.day_of_week >= 1 && dt.day_of_week <= 5)
     {
      datetime fx = GP_AMFixStart(now);
      if(now >= fx - 300 && now < fx)
        {
         GP_Notify("amfix" + TimeToString(fx, TIME_DATE), StringFormat("AM Fix: SELL %s-%s %s (10:20-10:29 London) - 1 th saja, 2017-25 menang 29%%",
                   GP_LocalTime(fx), GP_LocalTime(fx + 540), InpLocalTZName), fx - 300);
        }
     }
   //--- jendela RAWAN SWEEP (08:00-11:30 New York) - terbukti kokoh 2017-2026
   if(InpGPAlertSweep && dt.day_of_week >= 1 && dt.day_of_week <= 5)
     {
      datetime s0 = GP_SweepStart(now);
      if(now >= s0 - 600 && now < s0)
         GP_Notify("sweep" + TimeToString(s0, TIME_DATE), StringFormat("RAWAN SWEEP %s-%s %s mulai 10 menit lagi: hindari entry baru & SL ketat",
                   GP_LocalTime(s0), GP_LocalTime(s0 + 210 * 60), InpLocalTZName), s0 - 600);
     }
   BiasState bs = GetBiasState();
   if(InpGPAlertEntryOK && bs.decision == DECISION_ENTRY_OK)
      GP_Notify("eok" + TimeToString(iTime(_Symbol, PERIOD_CURRENT, 0)), StringFormat("ENTRY OK kandidat %s (Zone %.0f, POI %.0f) - belum terbukti",
                BiasTxtMain(bs.ltfBias), bs.scoreBreakdown.scoreZone, bs.scoreBreakdown.scorePOIQuality), now);
   if(InpGPAlertNews)
      for(int i = 0; i < ArraySize(g_upcomingNews); i++)
         if(g_upcomingNews[i].isBlackoutNow)   // satu alert per event berita
            GP_Notify("news" + g_upcomingNews[i].name + TimeToString(g_upcomingNews[i].eventTime),
                      StringFormat("BLACKOUT berita: %s (%s) - tahan entry baru", g_upcomingNews[i].name,
                                   GP_LocalTime(g_upcomingNews[i].eventTime) + " " + InpLocalTZName), now);
  }

string BiasTxtMain(ENUM_BIAS b) { return b == BIAS_BULLISH ? "BUY" : (b == BIAS_BEARISH ? "SELL" : "-"); }

//======================================================================
// Ekspor riwayat kalender ekonomi (USD, sedang+tinggi, 400 hari) ke
// Common\Files\GoldPro_Calendar.csv - bahan backtest filter berita
// (kalender MT5 tidak tersedia di Strategy Tester). Sekali per hari.
//======================================================================
void GP_ExportCalendar()
  {
   string f = "GoldPro_Calendar.csv";
   if(FileIsExist(f, FILE_COMMON) && TimeCurrent() - (datetime)FileGetInteger(f, FILE_MODIFY_DATE, true) < 86400) return;
   MqlCalendarValue v[];
   datetime to = TimeCurrent() + 7 * 86400, from = TimeCurrent() - 400 * 86400;
   int n = CalendarValueHistory(v, from, to, NULL, "USD");
   if(n <= 0) { Print("[GoldPro] kalender belum tersedia (", GetLastError(), ")"); return; }
   int h = FileOpen(f, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE) return;
   FileWriteString(h, "server_time,importance,event\r\n");
   int w = 0;
   for(int i = 0; i < n; i++)
     {
      MqlCalendarEvent e;
      if(!CalendarEventById(v[i].event_id, e) || e.importance < CALENDAR_IMPORTANCE_MODERATE) continue;
      string nm = e.name;
      StringReplace(nm, ",", " ");
      FileWriteString(h, StringFormat("%s,%d,%s\r\n", TimeToString(v[i].time, TIME_DATE | TIME_MINUTES),
                      e.importance == CALENDAR_IMPORTANCE_HIGH ? 2 : 1, nm));
      w++;
     }
   FileClose(h);
   PrintFormat("[GoldPro] kalender diekspor: %d event -> Common\\Files\\%s", w, f);
  }

//--- Kalender LENGKAP (2016-sekarang) dengan actual / forecast / previous / impact untuk riset "kejutan data".
//    Sama dengan Scripts\GoldPro\GP_CalendarExport, tapi otomatis saat GoldPro dimuat (maks 1x per 7 hari).
//    Jam = jam server dengan offset SAAT EKSPOR (lihat GP_CalTime; riset mengoreksi musim lain).
string GP_Num(bool has, double v) { return has ? DoubleToString(v, 6) : ""; }
void GP_ExportCalendarFull()
  {
   string f = "GoldPro_CalendarFull.csv";
   if(FileIsExist(f, FILE_COMMON) && TimeCurrent() - (datetime)FileGetInteger(f, FILE_MODIFY_DATE, true) < 7 * 86400) return;
   MqlCalendarValue v[];
   int n = CalendarValueHistory(v, D'2016.12.01', TimeTradeServer() + 14 * 86400, NULL, "USD");
   if(n <= 0) { Print("[GoldPro] kalender lengkap belum tersedia (", GetLastError(), ")"); return; }
   int h = FileOpen(f, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE) { Print("[GoldPro] gagal menulis ", f, " (", GetLastError(), ")"); return; }
   FileWriteString(h, "server_time,importance,event_id,event,actual,forecast,previous,revised,impact\r\n");
   int w = 0;
   for(int i = 0; i < n; i++)
     {
      MqlCalendarEvent e;
      if(!CalendarEventById(v[i].event_id, e) || e.importance < CALENDAR_IMPORTANCE_MODERATE) continue;
      string nm = e.name;
      StringReplace(nm, ",", " ");
      FileWriteString(h, StringFormat("%s,%d,%I64u,%s,%s,%s,%s,%s,%d\r\n", TimeToString(v[i].time, TIME_DATE | TIME_MINUTES),
                      e.importance == CALENDAR_IMPORTANCE_HIGH ? 2 : 1, e.id, nm,
                      GP_Num(v[i].HasActualValue(), v[i].GetActualValue()), GP_Num(v[i].HasForecastValue(), v[i].GetForecastValue()),
                      GP_Num(v[i].HasPreviousValue(), v[i].GetPreviousValue()), GP_Num(v[i].HasRevisedValue(), v[i].GetRevisedValue()),
                      (int)v[i].impact_type));
      w++;
     }
   FileClose(h);
   PrintFormat("[GoldPro] kalender LENGKAP diekspor: %d event -> Common\\Files\\%s", w, f);
  }

//======================================================================
void OnDeinit(const int reason)
  {
   bool isFinal = GP_FinalDeinit(reason);   // ganti TF / compile / ubah input: objek dibiarkan untuk instance baru
   GP_MasterRelease();                      // instance baru / chart lain mengambil alih chart utama <= 2 dtk
   GP_HealthDeinit(isFinal);
   GDM::Deinit(reason, isFinal);
   GP_Precision_Deinit(isFinal);
   NB_Deinit(isFinal);
   KB_Deinit(isFinal);
   TB_Deinit(isFinal);
   WV_Deinit(isFinal);
   if(isFinal)
      DeleteAllManagedObjects();
  }
