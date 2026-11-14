//+------------------------------------------------------------------+
//|                                                  SMC_Config.mqh |
//|                                                                  |
//| Fase 1 - File 2/24 : SMC Pro System                             |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Pusat konfigurasi tunggal. SEMUA input parameter, warna, dan  |
//|   ambang batas (threshold) dikumpulkan di sini - tidak ada file |
//|   lain yang boleh punya `input` sendiri atau hardcode angka     |
//|   ambang batas / warna langsung di logic-nya.                   |
//|                                                                  |
//| ATURAN KETAT UNTUK FILE INI:                                    |
//|   1. Boleh ada fungsi helper KECIL (mapping warna, validasi     |
//|      input) - tapi TIDAK BOLEH ada logic deteksi/analisis SMC   |
//|      apapun di sini.                                            |
//|   2. Semua bobot scoring HARUS dibaca dari sini oleh             |
//|      SMC_Scoring.mqh - jangan pernah hardcode bobot di file lain.|
//+------------------------------------------------------------------+
#ifndef SMC_CONFIG_MQH
#define SMC_CONFIG_MQH

#include "SMC_Types.mqh"

//======================================================================
// GROUP 1: STRUCTURE
//======================================================================
input group "=== Market Structure ==="
input int    InpSwingLookback         = 5;      // Jumlah bar kiri-kanan untuk validasi fractal swing EXTERNAL (major)
input int    InpInternalSwingLookback = 2;      // Jumlah bar kiri-kanan untuk fractal swing INTERNAL (minor/IDM) - lebih sensitif
input bool   InpUseInternalStructure  = true;    // Deteksi juga struktur internal (minor), bukan cuma external
input int    InpMaxSwingHistory       = 50;      // Maksimum swing point disimpan di memory (histori lama dibuang)
input int    InpMaxStructureEvents    = 30;      // Maksimum BOS/CHoCH event disimpan di memory

//======================================================================
// GROUP 2: ORDER BLOCK / FVG / BREAKER / MITIGATION
//======================================================================
input group "=== Point of Interest (POI) ==="
input double InpOBDisplacementMinBody = 0.6;     // Rasio body/range minimum candle konfirmasi (0.0-1.0)
input double InpFVGMinSizeATR         = 0.05;    // Ukuran minimum FVG, dalam satuan ATR (diturunkan dari 0.15 - terlalu ketat, FVG nyata jadi tidak terdeteksi)
input double InpZoneMitigatedPercent  = 90.0;    // % zona terisi sebelum dianggap MITIGATED
input bool   InpShowMitigatedZones    = false;   // Tampilkan zona yang sudah mitigated di chart?
input int    InpMaxPOIHistory         = 10;      // Maksimum OB/FVG aktif ditampilkan per jenis
input bool   InpDetectBreakerBlock    = true;    // Aktifkan deteksi Breaker Block
// GoldPro: "Mitigation Block" SMC lama = setiap candle kuat + candle sebelumnya berlawanan (bukan definisi
// SMC, sangat ramai) dan dulu TIDAK PERNAH jalan karena bug structureChanged. Nama input diganti -> default mati.
input bool   InpDetectMitigationBlk   = false;   // Deteksi "Mitigation Block" (definisi longgar, belum diuji)
input int    InpRenderMaxOBPerSide    = 3;       // Maksimum OB/Breaker DITAMPILKAN per arah (bullish/bearish) - data tetap disimpan semua, ini cuma batas visual
input int    InpRenderMaxSwingLabels  = 20;      // Maksimum label swing (Strong/Weak High/Low) ditampilkan - hanya yang paling baru
input int    InpOBMaxWidthBars        = 100;     // Lebar MAKSIMUM pita OB/Breaker/FVG dalam jumlah bar dari titik asalnya (bukan sampai "sekarang" tanpa batas) - mencegah pita lama menutupi seluruh chart
input int    InpSwingLabelMinBarGap   = 3;       // Jarak minimum (bar) antar label swing berdekatan supaya tidak numpuk jadi satu
input bool   InpFastBox               = true;    // Kotak Premium/Discount CEPAT: ujung = high/low berjalan (tanpa jeda konfirmasi 5 candle)

//======================================================================
// GROUP 3: LIQUIDITY
//======================================================================
input group "=== Liquidity ==="
input double InpEqualLevelToleranceATR = 0.1;    // Toleransi equal high/low, dalam satuan ATR
input int    InpSweepConfirmMaxBars    = 3;      // Maksimum bar setelah wick sweep untuk konfirmasi displacement balik arah

//======================================================================
// GROUP 4: MARKET CONDITION
//======================================================================
input group "=== Market Condition ==="
input int    InpEfficiencyRatioPeriod  = 20;     // Periode bar untuk hitung efficiency ratio (trending vs choppy)
input double InpTrendingThreshold      = 0.35;   // Efficiency ratio di atas ini dianggap TRENDING (diturunkan dari 0.5 - kalibrasi empiris XAUUSD, lihat diagnostik ER)
input double InpRangingThreshold       = 0.20;   // Di bawah ini dianggap RANGING; di antaranya = default RANGING konservatif (diturunkan dari 0.25)
input int    InpATRRelativePeriod      = 100;    // Periode rata-rata ATR historis untuk hitung ATR relatif

//======================================================================
// GROUP 5: SESSION / KILLZONE (waktu murni - lihat SMC_Session.mqh)
//======================================================================
// GoldPro: jam sesi dalam jam LOKAL bursa, dikonversi otomatis (DST AS & Inggris) - lihat GP_Time.mqh.
// SMC lama memakai jam server mentah -> sesi meleset ~4 jam & tidak ikut DST.
input group "=== Session & Killzone (jam LOKAL bursa, otomatis ikut DST) ==="
input int    InpLocalUTCOffset         = 8;      // Zona waktu Anda (UTC+): WIB 7, WITA 8, WIT 9
input string InpLocalTZName            = "WITA"; // Nama zona waktu yang ditampilkan di panel & alert
input int    InpServerUTCWinter        = 2;      // Jam server broker = UTC + ini saat musim dingin
input bool   InpServerFollowsUSDST     = true;   // Server broker ikut DST Amerika (+1 jam, Mar-Nov)
input int    InpAsiaStartET            = 20;     // Asia mulai (jam New York) = 07:00/08:00 WIB
input int    InpAsiaEndET              = 24;     // Asia selesai (jam New York, 24 = tengah malam)
input int    InpLondonStartLDN         = 7;      // London killzone mulai (jam London) = 13:00/14:00 WIB
input int    InpLondonEndLDN           = 10;     // London killzone selesai (jam London)
input int    InpNewYorkStartET         = 7;      // New York killzone mulai (jam New York) = 18:00/19:00 WIB
input int    InpNewYorkEndET           = 10;     // New York killzone selesai (rilis data 08:30 ET di dalamnya)
input int    InpJudasSwingWindowMin    = 30;     // Menit pertama tiap killzone yang dianggap window manipulasi

//======================================================================
// GROUP 6: NEWS FILTER (Economic Calendar API native)
//======================================================================
input group "=== News Filter ==="
input bool   InpEnableNewsFilter       = true;
input int    InpNewsMinImportance      = 2;      // 0=rendah,1=sedang,2=tinggi (mapping ke CALENDAR_IMPORTANCE_*)
input int    InpNewsBlackoutBeforeMin  = 30;      // Menit sebelum rilis - entry ditahan
input int    InpNewsBlackoutAfterMin   = 15;      // Menit sesudah rilis - entry masih ditahan
input int    InpNewsCacheRefreshMin    = 60;      // Refresh cache kalender tiap N menit (bukan tiap tick)

//======================================================================
// GROUP 7: MULTI-TIMEFRAME
//======================================================================
input group "=== Multi-Timeframe ==="
input ENUM_TIMEFRAMES InpHTF = PERIOD_H4;
input ENUM_TIMEFRAMES InpMTF = PERIOD_H1;
input ENUM_TIMEFRAMES InpLTF = PERIOD_M15;
input bool   InpEnableNestedPOIConfluence = true; // Deteksi overlap POI antar-timeframe

//======================================================================
// GROUP 8: CONFLUENCE SCORING
//   Catatan: total 6 bobot ini idealnya = 100. Divalidasi otomatis di
//   OnInit lewat ValidateScoringWeights() (lihat bagian bawah file).
//======================================================================
// GoldPro Tahap 2 (validasi 1 th, 3 periode): Structure & LTF Confirm menurunkan hasil secara
// konsisten, Liquidity hampir konstan (50), Zone positif konsisten, POI Quality positif 2/3.
// Bobot SMC lama: 30/20/15/15/15/5.
input group "=== Confluence Scoring (bobot berbasis bukti GoldPro) ==="
input double InpWeightStructure        = 0.0;
input double InpWeightLiquidity        = 0.0;
input double InpWeightZone             = 50.0;
input double InpWeightPOIQuality       = 50.0;
input double InpWeightLTFConfirm       = 0.0;
input double InpWeightMarketCondition  = 0.0;
input bool   InpEvidenceDecision       = true;   // ENTRY OK = Zone>=70 & POI Quality>=80 (kandidat teruji); false = aturan SMC lama
input bool   InpLegacyGates            = false;  // Gerbang lama AMD/range/jumlah faktor (tidak terbukti) - gerbang berita tetap aktif
input double InpEntryThreshold         = 80.0;   // Dinaikkan dari 70 - uji apakah sinyal LEBIH KETAT naikkan win-rate tanpa korbankan PF (beda pendekatan dari TP-shrink yang terbukti jalan buntu)
input double InpWatchThreshold         = 45.0;   // Skor minimum untuk status WATCH (di bawah ini = NO_ZONE)
input int    InpMinConfluence          = 3;      // BARU (Fase 4): minimum komponen "confluence" untuk IsBuyAllowed/IsSellAllowed
input double InpConfluenceFactorMinScore = 50.0; // BARU (Fase 4): skor mentah komponen (0-100) dianggap "confluence" kalau >= ini
input int    InpMinRangeBars           = 20;     // BARU (Fase 5): HH/LL diam minimal ini banyak bar -> dianggap range matang
input double InpSLBufferATRMultiplier  = 1.0;    // Dinaikkan dari 0.3 - backtest ronde 2 masih 31% trade mati <=10 detik, buffer perlu lebih lebar

input group "=== Supply & Demand 'Paus' (H1, berdiri sendiri dari Confluence) ==="
input bool             InpEnableSupplyDemand   = true;         // Aktifkan modul Paus
input ENUM_TIMEFRAMES  InpSDTimeframe          = PERIOD_H1;    // TF deteksi base - SELALU ini, terlepas dari chart aktif
input int              InpSDMinBaseCandles     = 1;            // Minimal candle base yang valid
input int              InpSDMaxBaseCandles     = 6;            // Maksimal candle base - lebih dari ini dianggap range, bukan base institusi
input double           InpSDBaseBodyRatio      = 0.40;         // Badan candle base < ini x rata-rata badan
input double           InpSDImpulseRangeRatio  = 1.5;          // Range leg sebelum/sesudah base >= ini x rata-rata range, baru dianggap impulsif
input int              InpSDScanBars           = 200;          // Berapa bar H1 ke belakang yang dipindai tiap kali

input group "=== Entry Multi-TF (berdiri sendiri per-TF, tidak wajib selaras HTF/MTF) ==="
input bool             InpEnableMultiTFEntry = true;        // Aktifkan panel Entry Multi-TF di dashboard
input ENUM_TIMEFRAMES  InpMultiTFEntry1      = PERIOD_M1;   // TF pertama yang dievaluasi berdiri sendiri
input ENUM_TIMEFRAMES  InpMultiTFEntry2      = PERIOD_M5;   // TF kedua yang dievaluasi berdiri sendiri

//======================================================================
// GROUP 9: STATISTIK (SMC_Stats.mqh)
//======================================================================
input group "=== Statistics ==="
input bool   InpEnableStats            = true;
input int    InpStatsMinSampleSize     = 20;     // Jumlah sample minimum sebelum win-rate ditampilkan sebagai valid
input int    InpStatsMaxTrackBars      = 100;    // Maksimum bar dipantau forward sebelum setup dianggap timeout/gagal
input string InpStatsFileName          = "GoldPro_Stats.csv";  // Disimpan di MQL5/Files/ (format CSV koma - diperbaiki)

//======================================================================
// GROUP 10: VISUAL - WARNA & TAMPILAN
//======================================================================
input group "=== Visual: Warna ==="
input color  InpColorBullishOB    = clrDodgerBlue;
input color  InpColorBearishOB    = clrCrimson;
input color  InpColorFVGBullish   = C'170,210,255';
input color  InpColorFVGBearish   = C'255,190,190';
input color  InpColorBreaker      = clrOrange;
input color  InpColorMitigation   = clrGray;
input color  InpColorSwingStrong  = clrWhite;
input color  InpColorSwingWeak    = clrSilver;
input color  InpColorBOS          = clrLimeGreen;
input color  InpColorCHoCH        = clrGold;
input color  InpColorLiquidity    = clrDarkGray;
input color  InpColorPremiumZone  = C'255,220,220';
input color  InpColorDiscountZone = C'220,255,220';
input color  InpColorOTEZone      = C'255,250,200';
input color  InpColorKillzoneAsia    = C'230,230,255';
input color  InpColorKillzoneLondon  = C'230,255,230';
input color  InpColorKillzoneNewYork = C'255,235,220';

input group "=== Visual: Panel & Toggle ==="
input bool   InpShowDashboard      = true;
input int    InpDashboardCorner    = 0;      // 0=kiri atas,1=kanan atas,2=kiri bawah,3=kanan bawah (0 direkomendasikan - perilaku Y paling standar/terdokumentasi)
input int    InpDashboardOffsetX   = 15;
input int    InpDashboardOffsetY   = 20;
input bool   InpShowKillzoneShading = true;
input bool   InpShowNarrativeLabel  = true;
input int    InpVisualMaxLookbackBars = 200; // Batas MAKSIMAL rentang visual ke kiri untuk rectangle zona/OB/FVG (bukan pembatas data, murni supaya chart tidak tertutup blok warna saat di-zoom-out)

//======================================================================
// GROUP 11: SIGNAL EXPORT & ALERT
//======================================================================
input group "=== Signal Export & Alert ==="
input bool   InpEnableSignalExport = true;
input string InpSignalExportFile   = "GoldPro_Signal";  // Prefix file di MQL5/Files/ -> GoldPro_Signal_<SIMBOL>_<TF>.json
// Alert modul SMC lama: CHoCH & ENTRY OK TIDAK terbukti menebak arah (uji Tahap 2 & 2017-25) -> default mati.
// Nama input sengaja diganti agar chart lama yang menyimpan nilai "true" ikut memakai default baru.
input bool   InpSMCAlertCHoCH      = false;   // Alert CHoCH SMC (INFO, belum terbukti)
input bool   InpSMCAlertEntryOK    = false;   // Alert ENTRY OK SMC (INFO, belum terbukti)
input bool   InpAlertSound         = true;
input bool   InpAlertPushNotify    = false;   // Push ke MT5 mobile - butuh setup MetaQuotes ID

//======================================================================
// KONSTANTA INTERNAL (bukan input - tetap, tidak untuk diubah user)
//======================================================================
#define SMC_OBJ_PREFIX        "GP_"         // GoldPro: beda dari SMC asli ("SMC_") supaya bisa jalan berdampingan
#define SMC_GV_PREFIX         "GP_GV_"      // Prefix Global Variable GoldPro

//======================================================================
// FUNGSI HELPER: MAPPING WARNA
// (helper kecil murni lookup - bukan logic analisis)
//======================================================================
color GetColorForOB(bool isBullish, ENUM_ZONE_STATUS status)
  {
   color base = isBullish ? InpColorBullishOB : InpColorBearishOB;
   if(status == ZONE_MITIGATED || status == ZONE_INVALIDATED)
      return InpColorMitigation;
   return base;
  }

color GetColorForFVG(bool isBullish)
  {
   return isBullish ? InpColorFVGBullish : InpColorFVGBearish;
  }

color GetColorForSwing(ENUM_SWING_STRENGTH strength)
  {
   return (strength == SWING_STRONG) ? InpColorSwingStrong : InpColorSwingWeak;
  }

color GetColorForKillzone(ENUM_SESSION session)
  {
   switch(session)
     {
      case SESSION_ASIA:    return InpColorKillzoneAsia;
      case SESSION_LONDON:  return InpColorKillzoneLondon;
      case SESSION_NEWYORK: return InpColorKillzoneNewYork;
      default:              return clrNONE;
     }
  }

//======================================================================
// FUNGSI HELPER: VALIDASI INPUT
// Dipanggil sekali dari SMC_Main.mq5 -> OnInit(). Kalau total bobot
// scoring tidak 100, dinormalisasi otomatis secara proporsional supaya
// sistem tetap jalan konsisten walau user salah isi input.
//======================================================================
double g_normalizedWeights[6]; // [Structure, Liquidity, Zone, POIQuality, LTFConfirm, MarketCondition]

bool ValidateScoringWeights()
  {
   double total = InpWeightStructure + InpWeightLiquidity + InpWeightZone
                  + InpWeightPOIQuality + InpWeightLTFConfirm + InpWeightMarketCondition;

   if(total <= 0)
     {
      Print("[SMC_Config] ERROR: Total bobot scoring <= 0, tidak bisa dinormalisasi. Cek input.");
      return false;
     }

   if(MathAbs(total - 100.0) > 0.01)
     {
      PrintFormat("[SMC_Config] WARNING: Total bobot scoring = %.2f (bukan 100). "
                  "Dinormalisasi otomatis secara proporsional.", total);
     }

   g_normalizedWeights[0] = (InpWeightStructure       / total) * 100.0;
   g_normalizedWeights[1] = (InpWeightLiquidity        / total) * 100.0;
   g_normalizedWeights[2] = (InpWeightZone             / total) * 100.0;
   g_normalizedWeights[3] = (InpWeightPOIQuality       / total) * 100.0;
   g_normalizedWeights[4] = (InpWeightLTFConfirm       / total) * 100.0;
   g_normalizedWeights[5] = (InpWeightMarketCondition  / total) * 100.0;

   return true;
  }

#endif // SMC_CONFIG_MQH