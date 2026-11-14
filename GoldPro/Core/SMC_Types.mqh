//+------------------------------------------------------------------+
//|                                                   SMC_Types.mqh |
//|                                                                  |
//| Fase 1 - File 1/24 : SMC Pro System                             |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   "Kamus data" tunggal untuk seluruh sistem. Semua struct & enum|
//|   yang dipakai lintas modul (Detection, Analysis, Narrative,    |
//|   Render, Signal) didefinisikan DI SINI SAJA.                   |
//|                                                                  |
//| ATURAN KETAT UNTUK FILE INI:                                    |
//|   1. TIDAK ADA logic pemrosesan apapun di sini - murni definisi |
//|      tipe data. Kalau ada fungsi hitung, itu salah tempat.      |
//|   2. Struct TIDAK BOLEH menyimpan nama object chart (string     |
//|      nama untuk ObjectCreate dsb) - itu urusan Render layer.    |
//|   3. Semua file lain di sistem ini meng-#include file ini.      |
//|      File ini sendiri tidak meng-#include file SMC lain.        |
//+------------------------------------------------------------------+
#ifndef SMC_TYPES_MQH
#define SMC_TYPES_MQH

//======================================================================
// SECTION 1: ENUM DASAR
//======================================================================

// Kekuatan sebuah swing point.
// STRONG  = belum pernah ditembus/di-sweep oleh harga setelahnya.
//           BOS/CHoCH yang valid HARUS mereferensi swing berstatus STRONG.
// WEAK    = sudah pernah ditembus sebagian - tidak valid dijadikan
//           acuan BOS/CHoCH, tapi tetap disimpan untuk histori visual.
enum ENUM_SWING_STRENGTH
  {
   SWING_STRONG,
   SWING_WEAK
  };

// Status siklus hidup sebuah zona (OB, FVG, Breaker, dsb).
// FRESH       = belum pernah disentuh harga sama sekali.
// PARTIAL     = harga sudah masuk sebagian ke zona, belum full close.
// MITIGATED   = zona sudah "terisi"/tersentuh penuh - dianggap selesai
//               tugasnya, tapi TIDAK dihapus (histori tetap disimpan).
// INVALIDATED = zona batal valid karena kondisi lain berubah
//               (misal struktur besar sudah shift, sebelum sempat
//               dimitigasi harga).
// Status siklus hidup sebuah zona (OB, FVG, Breaker, dsb).
// FRESH       = belum pernah disentuh harga sama sekali.
// PARTIAL     = harga sudah masuk sebagian ke zona, belum full close.
// MITIGATED   = zona sudah "terisi"/tersentuh penuh - dianggap selesai
//               tugasnya, tapi TIDAK dihapus (histori tetap disimpan).
// INVALIDATED = zona batal valid karena kondisi lain berubah
//               (misal struktur besar sudah shift, sebelum sempat
//               dimitigasi harga).
// TESTED, BROKEN (BARU - adopsi xxvw/SMC_ICT_Library, Fase 1):
// ditambahkan sebagai nilai TAMBAHAN, BUKAN pengganti PARTIAL/MITIGATED
// - mengganti nama enum yang sudah ada akan merusak semua pemakainya di
//   SMC_POI.mqh, Render/*, dll. Belum ada logic yang MENGHASILKAN status
//   ini di Fase 1 - disiapkan untuk dipakai di fase berikutnya.
enum ENUM_ZONE_STATUS
  {
   ZONE_FRESH,
   ZONE_PARTIAL,
   ZONE_MITIGATED,
   ZONE_INVALIDATED,
   ZONE_TESTED,   // BARU: disentuh sekali tapi belum masuk kategori PARTIAL/MITIGATED manapun
   ZONE_BROKEN    // BARU: ditembus penuh, beda dari MITIGATED (terisi) - untuk pembeda "gagal" vs "selesai wajar"
  };

// Arah bias pasar.
enum ENUM_BIAS
  {
   BIAS_BULLISH,
   BIAS_BEARISH,
   BIAS_NEUTRAL
  };

// Jenis Point of Interest. Order Block "resmi" (OB) berbeda dari
// Mitigation Block (kandidat OB yang TIDAK memecahkan struktur) dan
// Breaker Block (OB yang gagal menahan harga, berbalik fungsi).
enum ENUM_POI_TYPE
  {
   POI_ORDER_BLOCK,
   POI_FVG,
   POI_BREAKER,
   POI_MITIGATION
  };

// Kondisi market secara umum, dihasilkan oleh SMC_MarketCondition.mqh.
// TRENDING   = efficiency ratio tinggi, SMC bekerja optimal.
// RANGING    = choppy, sinyal SMC harus ditahan/dikurangi bobotnya.
// COMPRESSED = volatilitas menyempit (biasanya sebelum breakout,
//              misal di sesi Asia) - bukan trending, bukan choppy biasa.
enum ENUM_MARKET_CONDITION
  {
   CONDITION_TRENDING,
   CONDITION_RANGING,
   CONDITION_COMPRESSED
  };

// Sesi trading aktif (murni berbasis waktu, lihat SMC_Session.mqh).
enum ENUM_SESSION
  {
   SESSION_ASIA,
   SESSION_LONDON,
   SESSION_NEWYORK,
   SESSION_OFF
  };

// Fase Accumulation-Manipulation-Distribution, dihasilkan SMC_AMD.mqh
// dari gabungan waktu (Session) + event liquidity (Liquidity).
enum ENUM_AMD_PHASE
  {
   AMD_ACCUMULATION,
   AMD_MANIPULATION,
   AMD_DISTRIBUTION,
   AMD_NONE           // belum cukup data / di luar pola AMD yang jelas
  };

// Status keputusan akhir dari confluence scoring - dipakai dashboard,
// narrative, dan signal export supaya semua modul "bicara" dengan
// istilah yang sama.
enum ENUM_ENTRY_DECISION
  {
   DECISION_ENTRY_OK,
   DECISION_WATCH,
   DECISION_NO_ZONE
  };

// Klasifikasi posisi harga di dalam dealing range aktif.
enum ENUM_PRICE_ZONE
  {
   PRICEZONE_DISCOUNT,      // < 50% dari dealing range
   PRICEZONE_EQUILIBRIUM,   // persis di sekitar 50% (toleransi kecil)
   PRICEZONE_PREMIUM,       // > 50% dari dealing range
   PRICEZONE_OTE,           // di dalam band Optimal Trade Entry (61.8%-79%)
   PRICEZONE_OUT_OF_RANGE   // harga di luar dealing range saat ini
  };

//======================================================================
// SECTION 2: STRUCT - STRUKTUR PASAR
//======================================================================

// Satu titik swing high/low di chart.
struct SwingPoint
  {
   long                 id;          // id unik, urut naik (dipakai referensi dari struct lain & render)
   datetime             time;
   double               price;
   bool                 isHigh;      // true = swing high, false = swing low
   ENUM_SWING_STRENGTH  strength;
   bool                 swept;       // sudah pernah ditembus harga setelahnya?
   bool                 isInternal;  // true = struktur internal (minor), false = struktur eksternal (major)
  };

// Satu event perubahan struktur (BOS atau CHoCH). Disimpan terpisah dari
// SwingPoint karena satu swing bisa jadi acuan event, tapi event-nya
// sendiri punya informasi tambahan (arah baru, status IDM) yang tidak
// relevan disimpan permanen di struct SwingPoint.
struct StructureEvent
  {
   long      id;
   datetime  time;
   double    price;
   bool      isBOS;         // true = BOS (kelanjutan tren), false = CHoCH (perubahan arah)
   bool      isInternal;    // event dari struktur internal (minor) atau external (major)
   ENUM_BIAS direction;     // arah bias BARU setelah event ini terjadi
   long      swingId;       // id SwingPoint yang ditembus untuk memicu event ini
   bool      idmConfirmed;  // true kalau IDM sudah di-sweep SEBELUM event ini - penanda kualitas sinyal
  };

// Rentang dealing range aktif (dasar perhitungan Premium/Discount).
struct DealingRange
  {
   bool     isValid;        // false kalau belum cukup swing untuk membentuk range
   datetime time_start, time_end;
   double   high, low;
   double   midpoint;      // level equilibrium (50%)
   double   oteTop;        // batas atas Optimal Trade Entry (~79% dari sisi origin)
   double   oteBottom;     // batas bawah Optimal Trade Entry (~61.8% dari sisi origin)
   ENUM_BIAS originDirection; // arah leg pembentuk range - menentukan sisi mana OTE dihitung
  };

//======================================================================
// SECTION 3: STRUCT - POINT OF INTEREST (POI)
//======================================================================

// Order Block, Breaker Block, dan Mitigation Block memakai struct yang
// sama (bedanya di field `poiType`) karena bentuk datanya identik -
// hanya makna & cara render-nya yang beda.
struct OrderBlock
  {
   long             id;
   datetime         time;
   double           high, low;
   bool             isBullish;
   ENUM_POI_TYPE    poiType;
   bool             hasFVG;          // apakah meninggalkan FVG saat terbentuk
   ENUM_ZONE_STATUS status;
   double           ceLevel;         // consequent encroachment (titik tengah zona)
   int              touchCount;      // berapa kali harga masuk zona ini
   ENUM_TIMEFRAMES  sourceTF;        // timeframe asal - penting untuk nested/confluence POI
   bool             isConfluent;     // true kalau overlap dengan POI dari timeframe lain
   datetime         bornTime;        // GoldPro: candle saat zona LAHIR (BOS). Mitigasi dihitung dari candle SESUDAHNYA
  };

// Fair Value Gap / Imbalance.
struct FVGZone
  {
   long             id;
   datetime         time;
   double           top, bottom;
   bool             isBullish;
   ENUM_ZONE_STATUS status;
   double           fillPercent;     // 0-100, seberapa banyak sudah "terisi" harga
   double           ceLevel;         // titik tengah FVG
   ENUM_TIMEFRAMES  sourceTF;
   datetime         bornTime;        // GoldPro: candle ke-3 FVG (saat FVG terkonfirmasi)
  };

//======================================================================
// SECTION 4: STRUCT - LIKUIDITAS
//======================================================================

// Kumpulan likuiditas (equal highs/lows, trendline liquidity).
// CATATAN: struct ini murni harga - TIDAK ADA field terkait Judas
// Swing atau AMD di sini (itu urusan SMC_AMD.mqh, lihat AMDState).
// Klasifikasi jenis liquidity (BARU - adopsi xxvw/SMC_ICT_Library, Fase 1).
// Belum ada logic yang MENGHASILKAN nilai ini di Fase 1 - disiapkan
// untuk SMC_Liquidity.mqh Fase 2 (deteksi EQH/EQL eksplisit).
enum ENUM_LIQUIDITY_TYPE
  {
   LIQ_EQUAL_HIGHS,    // EQH - 2 touch
   LIQ_EQUAL_LOWS,     // EQL - 2 touch
   LIQ_POOL_HIGH,      // Pool - 3+ touch
   LIQ_POOL_LOW,       // Pool - 3+ touch
   LIQ_SWEEP_HIGH,     // Sweep high
   LIQ_SWEEP_LOW       // Sweep low
  };

// Kumpulan likuiditas (equal highs/lows, trendline liquidity).
// CATATAN: struct ini murni harga - TIDAK ADA field terkait Judas
// Swing atau AMD di sini (itu urusan SMC_AMD.mqh, lihat AMDState).
//
// CATATAN TRANSISI (field `type`/`isValid` BARU, Fase 1 adopsi
// xxvw/SMC_ICT_Library): semua TITIK PEMBUATAN pool yang SUDAH ADA
// (SMC_Liquidity.mqh, ClusterSwingsIntoPools) BELUM di-update untuk
// mengisi kedua field ini - keduanya akan diam-diam bernilai DEFAULT
// (type=LIQ_EQUAL_HIGHS, isValid=false) untuk SEMUA pool yang dibuat
// sampai Fase 2 selesai mewiring field ini. JANGAN baca/pakai field
// `type`/`isValid` di kode manapun sebelum Fase 2 - nilainya belum
// berarti apa-apa.
struct LiquidityPool
  {
   long                 id;
   double               price;
   datetime             firstTouch, lastTouch;
   int                  touchCount;      // >=2 mengindikasikan equal highs/lows
   bool                 swept;
   datetime             sweptTime;
   bool                 isBuySide;       // true = BSL (di atas), false = SSL (di bawah)
   ENUM_LIQUIDITY_TYPE  type;            // BARU - belum diisi kode manapun, lihat catatan transisi
   bool                 isValid;         // BARU - belum diisi kode manapun, lihat catatan transisi
  };

// Referensi level draw-on-liquidity (PDH/PDL, weekly/daily open, dsb).
// Dipisah dari LiquidityPool karena sumbernya beda (dihitung langsung
// dari data D1/W1, bukan hasil clustering swing).
struct DrawOnLiquidityRef
  {
   string   label;      // "PDH", "PDL", "PWH", "PWL", "Daily Open", dst.
   double   price;
   datetime referenceTime;
  };

//======================================================================
// SECTION 5: STRUCT - HASIL ANALISIS (Analysis layer)
//======================================================================

// Breakdown skor per komponen - disimpan terpisah dari total supaya
// bisa ditampilkan untuk debugging/dashboard ("kenapa skornya segini").
struct POIScore
  {
   double scoreStructure;
   double scoreLiquidity;
   double scoreZone;
   double scorePOIQuality;
   double scoreLTFConfirm;
   double scoreMarketCondition;
   double scoreTotal;          // hasil akhir setelah dikali bobot masing-masing

   // BARU (Fase 4, adopsi xxvw/SMC_ICT_Library): catat faktor mana yang
   // "confluence" (skor mentah komponen >= InpConfluenceFactorMinScore) -
   // dipakai IsBuyAllowed()/IsSellAllowed() sebagai gate TAMBAHAN di atas
   // scoreTotal, bukan pengganti weighted-average yang sudah ada. Tujuan:
   // cegah kasus scoreTotal lolos threshold cuma karena SATU komponen
   // dominan sementara yang lain lemah semua.
   string factorNames[];
   double factorScores[];
   int    factorCount;
  };

// Range konsolidasi (Fase 5, adopsi xxvw/SMC_ICT_Library).
// HH/LL yang tidak diperbaharui > InpMinRangeBars dianggap range matang.
struct RangeInfo
  {
   double   highPrice, lowPrice;
   datetime startTime, breakTime;
   int      startBar, duration;
   bool     isBroken;
   bool     isBullishBreak;
   bool     isValid;
  };

// Pola Supply & Demand klasik (BARU - modul "Paus", berdiri sendiri dari
// scoring scalping yang sudah ada).
enum ENUM_SD_PATTERN
  {
   SD_RBR,   // Rally-Base-Rally  -> Demand
   SD_DBD,   // Drop-Base-Drop    -> Supply
   SD_RBD,   // Rally-Base-Drop   -> Supply (gagal lanjut)
   SD_DBR    // Drop-Base-Rally   -> Demand (gagal lanjut)
  };

// Zona Supply/Demand - beda konsep dari OrderBlock (SMC_POI.mqh): batas
// zona dari LOW-HIGH seluruh candle "base" (bisa beberapa candle),
// bukan satu candle order block tunggal. Dipakai modul "Paus" (H1),
// TIDAK dipakai scoring/Confluence yang sudah ada.
struct SDZone
  {
   long             id;
   double           high, low;      // batas zona = low-high seluruh candle base
   datetime         baseStartTime;  // waktu candle base PALING LAMA
   datetime         baseEndTime;    // waktu candle base PALING BARU
   int              baseCandleCount;
   ENUM_SD_PATTERN  pattern;
   bool             isDemand;       // true = Demand (RBR/DBR), false = Supply (DBD/RBD)
   ENUM_ZONE_STATUS status;
   datetime         sourceTF_time;  // GoldPro: waktu zona LAHIR (candle leg keluar ke-3 close); status dicek sejak ini
  };

// State bias gabungan dari semua timeframe + hasil scoring akhir.
struct BiasState
  {
   ENUM_BIAS            htfBias;
   ENUM_BIAS            mtfBias;
   ENUM_BIAS            ltfBias;
   POIScore             scoreBreakdown;
   ENUM_ENTRY_DECISION  decision;
   string               narrativeText;      // versi lengkap, untuk alert/log
   string               narrativeShort;     // versi ringkas, untuk dashboard
  };

// Kondisi market saat ini (hasil SMC_MarketCondition.mqh).
struct MarketConditionState
  {
   ENUM_MARKET_CONDITION condition;
   double                efficiencyRatio;   // 0.0 - 1.0
   double                atrRelative;       // ATR sekarang / rata-rata ATR historis
  };

// Fase AMD saat ini (hasil SMC_AMD.mqh).
struct AMDState
  {
   ENUM_AMD_PHASE phase;
   bool           isJudasSwing;
   datetime       phaseStartTime;
  };

// Satu event berita ekonomi relevan (hasil SMC_NewsFilter.mqh, dibaca
// dari Economic Calendar API native MT5 - lihat catatan di file itu).
struct NewsEvent
  {
   string   name;
   string   currency;
   datetime eventTime;
   int      importance;     // dipetakan dari CALENDAR_IMPORTANCE_* MT5
   bool     isBlackoutNow;  // true kalau waktu sekarang ada di window blackout event ini
  };

//======================================================================
// SECTION 6: STRUCT - STATISTIK (SMC_Stats.mqh)
//======================================================================

// Satu catatan setup yang pernah lolos threshold, dilacak forward
// untuk menentukan apakah akhirnya "berhasil" atau "gagal".
struct SetupRecord
  {
   long             id;
   datetime         entryTime;
   string           patternKey;      // kombinasi kondisi ringkas, misal "OB_H1_Discount_LondonKZ"
   ENUM_BIAS        biasDirection;
   double           confluenceScore;
   double           entryPrice;
   double           stopPrice;
   double           targetPrice;
   ENUM_AMD_PHASE   amdPhaseAtEntry;
   ENUM_MARKET_CONDITION marketConditionAtEntry;
   bool             isResolved;      // sudah ada hasil akhir (menang/kalah) atau masih dipantau
   bool             isWin;           // valid dibaca hanya kalau isResolved == true
   datetime         resolvedTime;
  };

// Ringkasan statistik teragregasi untuk satu pattern key - inilah yang
// dibaca dashboard & narrative ("68% win rate dari 47 kejadian").
struct PatternStats
  {
   string patternKey;
   int    totalCount;
   int    winCount;
   double winRatePercent;
  };

#endif // SMC_TYPES_MQH