//+------------------------------------------------------------------+
//|                                                SMC_Structure.mqh |
//|                                                                  |
//| Fase 2 - File 4/24 : SMC Pro System                             |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Mesin deteksi struktur pasar - fondasi paling kritis, karena  |
//|   hampir semua modul lain (POI, Zones, Scoring, Narrative)      |
//|   bergantung pada bias/BOS/CHoCH yang dihasilkan di sini.       |
//|                                                                  |
//| CATATAN PENTING:                                                 |
//|   DebugRenderStructure() (render sementara masa development)     |
//|   sudah DIHAPUS - digantikan Render/SMC_RenderStructure.mqh +    |
//|   SMC_ObjectPool.mqh yang proper (dengan lifecycle/Story Chart). |
//|                                                                  |
//| SIMPLIFIKASI YANG SENGAJA DIAMBIL (didokumentasikan supaya      |
//| jelas apa yang perlu disempurnakan setelah verifikasi visual):  |
//|   - Deteksi fractal pakai lookback tetap (InpSwingLookback untuk|
//|     external, InpInternalSwingLookback untuk internal) - belum  |
//|     ada penyesuaian otomatis berdasarkan volatilitas.           |
//|   - Deteksi IDM-swept-sebelum-BOS memakai pendekatan cukup      |
//|     sederhana (cek swing internal terakhir yang relevan) - perlu|
//|     diuji visual apakah sudah cukup akurat.                     |
//+------------------------------------------------------------------+
#ifndef SMC_STRUCTURE_MQH
#define SMC_STRUCTURE_MQH

#include "..\Core\SMC_Types.mqh"
#include "..\Core\SMC_Config.mqh"
#include "..\Core\SMC_Utils.mqh"

//======================================================================
// STATE - disimpan persisten antar-bar (bukan dihitung ulang dari nol)
//======================================================================
SwingPoint     g_extSwings[];
SwingPoint     g_intSwings[];
StructureEvent g_structureEvents[];
RangeInfo      g_currentRange; // Fase 5 - dipindah ke sini (dekat state global lain) supaya bisa dipakai SMC_Structure_Init() di bawah

long      g_nextSwingId  = 1;
long      g_nextEventId  = 1;
ENUM_BIAS g_externalBias = BIAS_NEUTRAL;
ENUM_BIAS g_internalBias = BIAS_NEUTRAL;

// State backfill (retry + status untuk dashboard)
bool g_structureBackfillDone = false;
int  g_backfillAttempts      = 0;
#define SMC_BACKFILL_MAX_RETRIES 1

//======================================================================
// INIT - dipanggil sekali dari SMC_Main.mq5 -> OnInit()
//======================================================================
void SMC_Structure_Init()
  {
   ArrayFree(g_extSwings);
   ArrayFree(g_intSwings);
   ArrayFree(g_structureEvents);
   g_nextSwingId  = 1;
   g_nextEventId  = 1;
   g_externalBias = BIAS_NEUTRAL;
   g_internalBias = BIAS_NEUTRAL;
   g_structureBackfillDone = false;
   g_backfillAttempts      = 0;
   ZeroMemory(g_currentRange); // Fase 5: g_currentRange.isValid=false, dst - mulai bersih
  }

//======================================================================
// HELPER INTERNAL: deteksi fractal swing di posisi tertentu
//======================================================================
bool DetectFractalAt(ENUM_TIMEFRAMES tf, int lookback, int p, bool &isHigh, double &outPrice)
  {
   // p harus punya `lookback` bar lebih baru (shift lebih kecil, sudah closed)
   // dan `lookback` bar lebih lama (shift lebih besar) untuk bisa dikonfirmasi.
   if(p - lookback < 1)
      return false;

   double centerHigh = iHigh(_Symbol, tf, p);
   double centerLow  = iLow(_Symbol, tf, p);

   bool isFractalHigh = true;
   bool isFractalLow  = true;

   for(int i = 1; i <= lookback; i++)
     {
      if(iHigh(_Symbol, tf, p - i) >= centerHigh || iHigh(_Symbol, tf, p + i) >= centerHigh)
         isFractalHigh = false;
      if(iLow(_Symbol, tf, p - i) <= centerLow || iLow(_Symbol, tf, p + i) <= centerLow)
         isFractalLow = false;
     }

   if(isFractalHigh)
     {
      isHigh   = true;
      outPrice = centerHigh;
      return true;
     }
   if(isFractalLow)
     {
      isHigh   = false;
      outPrice = centerLow;
      return true;
     }
   return false;
  }

// GoldPro: candle "outside bar" bisa sekaligus swing HIGH dan swing LOW. DetectFractalAt() hanya
// mengembalikan high-nya -> low-nya dulu hilang. Dipakai untuk menambahkan low tsb.
bool IsFractalLowAt(ENUM_TIMEFRAMES tf, int lookback, int p, double &outPrice)
  {
   if(p - lookback < 1)
      return false;
   double centerLow = iLow(_Symbol, tf, p);
   for(int i = 1; i <= lookback; i++)
      if(iLow(_Symbol, tf, p - i) <= centerLow || iLow(_Symbol, tf, p + i) <= centerLow)
         return false;
   outPrice = centerLow;
   return true;
  }

//======================================================================
// HELPER INTERNAL: tambah swing ke array (external/internal)
//======================================================================
void AddSwing(SwingPoint &arr[], ENUM_TIMEFRAMES tf, int p, bool isHigh, double price, bool isInternal)
  {
   int n = ArraySize(arr);

   // Hindari duplikat kalau titik yang sama sudah pernah tercatat
   // (bisa terjadi kalau fungsi dipanggil lebih dari sekali untuk bar yang sama).
   if(n > 0 && arr[n - 1].time == iTime(_Symbol, tf, p) && arr[n - 1].isHigh == isHigh)
      return;

   ArrayResize(arr, n + 1);
   arr[n].id         = g_nextSwingId++;
   arr[n].time       = iTime(_Symbol, tf, p);
   arr[n].price      = NormalizePriceForSymbol(price);
   arr[n].isHigh     = isHigh;
   arr[n].strength   = SWING_STRONG;   // semua swing baru mulai sebagai STRONG
   arr[n].swept      = false;
   arr[n].isInternal = isInternal;

   int maxHist = isInternal ? InpMaxSwingHistory : InpMaxSwingHistory;
   if(ArraySize(arr) > maxHist)
      ArrayRemove(arr, 0, 1); // buang yang paling lama
  }

//======================================================================
// HELPER INTERNAL: cek apakah IDM internal sudah di-sweep sebelum
// sebuah breakout external terjadi.
//
// Logika: cari swing internal terakhir yang BERLAWANAN arah dengan
// breakout (misal breakout bullish -> cari internal LOW terakhir),
// lalu cek apakah swing internal itu sudah berstatus `swept`.
//======================================================================
bool WasIDMSweptBeforeBreak(bool breakoutBullish)
  {
   if(!InpUseInternalStructure)
      return false; // tidak bisa dikonfirmasi kalau fitur internal dimatikan

   for(int i = ArraySize(g_intSwings) - 1; i >= 0; i--)
     {
      bool wantHigh = !breakoutBullish; // breakout bullish -> cari internal LOW (isHigh=false)
      if(g_intSwings[i].isHigh == wantHigh)
         return g_intSwings[i].swept;
     }
   return false; // belum ada internal swing relevan yang terbentuk
  }

//======================================================================
// HELPER INTERNAL: cek sweep pada semua swing yang masih STRONG &
// belum swept, berdasarkan candle terakhir yang closed. Kalau closing
// menembus swing STRONG yang relevan, itu artinya BOS/CHoCH terjadi.
//
// Parameter `shift` defaultnya 1 (candle terakhir closed, kasus normal
// live per-bar). Untuk BACKFILL histori, fungsi ini dipanggil berulang
// dengan `shift` menurun dari lama ke baru, supaya event historis
// tercatat urut sesuai waktu aslinya - bukan cuma dari titik load.
//======================================================================
//======================================================================
// GoldPro PERBAIKAN (audit data M5 2 bulan): versi lama memeriksa SEMUA swing external yang belum
// ditembus (sampai 50 swing, termasuk yang berumur berhari-hari) -> 55% BOS/CHoCH dipicu swing yang
// BUKAN swing terbaru, 25% candle breakout menghasilkan >1 event sekaligus (maks 8), 64 candle
// sekaligus CHoCH + BOS. Definisi SMC: struktur hanya dipatahkan oleh swing high/low TERBARU.
// Sekarang: maks 1 event per candle, hanya dari swing TERBARU di sisinya; swing lama yang ikut
// terlewati ditandai tertembus TANPA event baru.
//======================================================================
void CheckExternalStructureBreak(ENUM_TIMEFRAMES tf, int shift)
  {
   double   lastClose     = iClose(_Symbol, tf, shift);
   datetime lastCloseTime = iTime(_Symbol, tf, shift);
   int n = ArraySize(g_extSwings);
   int iH = -1, iL = -1;
   for(int i = n - 1; i >= 0 && (iH < 0 || iL < 0); i--)
     {
      if(g_extSwings[i].isHigh && iH < 0)  iH = i;
      if(!g_extSwings[i].isHigh && iL < 0) iL = i;
     }
   int hit = -1;
   if(iH >= 0 && !g_extSwings[iH].swept && lastClose > g_extSwings[iH].price)      hit = iH;
   else if(iL >= 0 && !g_extSwings[iL].swept && lastClose < g_extSwings[iL].price) hit = iL;

   for(int i = 0; i < n; i++)
     {
      if(g_extSwings[i].swept)
         continue;
      if((g_extSwings[i].isHigh && lastClose > g_extSwings[i].price) || (!g_extSwings[i].isHigh && lastClose < g_extSwings[i].price))
        {
         g_extSwings[i].swept    = true;
         g_extSwings[i].strength = SWING_WEAK;
        }
     }
   if(hit < 0)
      return;

   bool      bull         = g_extSwings[hit].isHigh;
   ENUM_BIAS newDirection = bull ? BIAS_BULLISH : BIAS_BEARISH;
   bool      isBOS        = (g_externalBias == newDirection);
   bool      idmOk        = WasIDMSweptBeforeBreak(bull);

   int e = ArraySize(g_structureEvents);
   ArrayResize(g_structureEvents, e + 1);
   g_structureEvents[e].id           = g_nextEventId++;
   g_structureEvents[e].time         = lastCloseTime;
   g_structureEvents[e].price        = g_extSwings[hit].price;
   g_structureEvents[e].isBOS        = isBOS;
   g_structureEvents[e].isInternal   = false;
   g_structureEvents[e].direction    = newDirection;
   g_structureEvents[e].swingId      = g_extSwings[hit].id;
   g_structureEvents[e].idmConfirmed = idmOk;
   if(ArraySize(g_structureEvents) > InpMaxStructureEvents)
      ArrayRemove(g_structureEvents, 0, 1);
   g_externalBias = newDirection;
  }

void CheckSweepsAndStructureBreaks(ENUM_TIMEFRAMES tf, bool isInternal, int shift = 1)
  {
   if(!isInternal)
     {
      CheckExternalStructureBreak(tf, shift);   // GoldPro: jalur external yang sudah diperbaiki
      return;
     }
   // --- INTERNAL (minor): hanya untuk IDM tracking, tidak menghasilkan BOS/CHoCH ---
   double lastClose = iClose(_Symbol, tf, shift);
   for(int i = 0; i < ArraySize(g_intSwings); i++)
     {
      if(g_intSwings[i].swept || g_intSwings[i].strength != SWING_STRONG)
         continue;
      bool brokenBullish = g_intSwings[i].isHigh  && (lastClose > g_intSwings[i].price);
      bool brokenBearish = !g_intSwings[i].isHigh && (lastClose < g_intSwings[i].price);
      if(!brokenBullish && !brokenBearish)
         continue;
      g_intSwings[i].swept    = true;
      g_intSwings[i].strength = SWING_WEAK;
      g_internalBias = brokenBullish ? BIAS_BULLISH : BIAS_BEARISH;
     }
  }

//======================================================================
// FUNGSI UTAMA - dipanggil dari SMC_Main.mq5 tiap OnCalculate()
//
// PENTING (perbaikan arsitektur): fungsi ini TIDAK memanggil IsNewBar()
// sendiri. Status bar baru harus dihitung SEKALI oleh orchestrator
// (SMC_Main.mq5) lalu di-pass ke SEMUA modul (Structure, Zones, POI,
// dst) lewat parameter `isNewBar`. Alasannya: IsNewBar() di SMC_Utils
// punya cache global per-timeframe yang "sekali konsumsi" - kalau tiap
// modul memanggilnya sendiri-sendiri untuk timeframe yang sama, hanya
// modul PERTAMA yang dapat `true`, sisanya selalu `false`.
//
// REVISI (fix look-ahead bias): live dan backfill sekarang memanggil
// SATU fungsi step yang sama (ProcessStructureStep), beda cuma nilai
// `refShift`. Live selalu refShift=1 (bar yang baru saja closed).
// Backfill me-replay refShift dari besar (lama) ke kecil (baru).
// Ini menjamin live dan backfill TIDAK PERNAH bisa berbeda hasil,
// karena secara harfiah cuma ada satu jalur kode untuk dijalankan.
//======================================================================

// Satu "langkah" pemrosesan struktur pada posisi waktu tertentu (refShift
// bar dari sekarang). Dipakai oleh live (refShift selalu 1) MAUPUN
// backfill (refShift bervariasi, dari lama ke baru). TIDAK ADA logic
// lain di luar fungsi ini yang menentukan kapan swing/event terbentuk -
// satu sumber kebenaran untuk kedua jalur.
//======================================================================
// DetectRange() - Fase 5 (adopsi xxvw/SMC_ICT_Library). State TERPISAH
// dari swing/structure event - tidak mengubah g_extSwings/g_intSwings
// sama sekali, murni menambah "konteks range" di atasnya. Dipanggil
// dari ProcessStructureStep, jadi otomatis replay-correct (live &
// backfill satu jalur, refShift yang sama).
//======================================================================
void DetectRange(ENUM_TIMEFRAMES tf, int refShift)
  {
   int lookback = InpMinRangeBars;
   if(lookback < 2)
      return;

   // Kalau range aktif SUDAH tercatat & belum ditembus, cek dulu apakah
   // bar INI (refShift) menembusnya - baru kalau tidak, cari kandidat baru.
   if(g_currentRange.isValid && !g_currentRange.isBroken)
     {
      double closeNow = iClose(_Symbol, tf, refShift);
      if(closeNow > g_currentRange.highPrice)
        {
         g_currentRange.isBroken       = true;
         g_currentRange.isBullishBreak = true;
         g_currentRange.breakTime      = iTime(_Symbol, tf, refShift);
         return; // range ini selesai ceritanya di step ini - jangan cari range baru di step yang sama
        }
      if(closeNow < g_currentRange.lowPrice)
        {
         g_currentRange.isBroken       = true;
         g_currentRange.isBullishBreak = false;
         g_currentRange.breakTime      = iTime(_Symbol, tf, refShift);
         return;
        }
      return; // range masih aktif & belum ditembus - tidak perlu dihitung ulang tiap bar
     }

   // Cari kandidat range dari window InpMinRangeBars bar terakhir dari refShift
   double windowHigh  = iHigh(_Symbol, tf, refShift);
   double windowLow   = iLow(_Symbol, tf, refShift);
   int    highBarsAgo = 0;
   int    lowBarsAgo  = 0;

   for(int i = 1; i < lookback; i++)
     {
      int s = refShift + i;
      double h = iHigh(_Symbol, tf, s);
      double l = iLow(_Symbol, tf, s);
      if(h >= windowHigh) { windowHigh = h; highBarsAgo = i; }
      if(l <= windowLow)  { windowLow  = l; lowBarsAgo  = i; }
     }

   // Range dianggap MATANG kalau extreme high & low sudah "diam" minimal
   // separuh window - kalau extreme-nya baru 1-2 bar terakhir, itu masih
   // breakout aktif, BUKAN konsolidasi yang layak disebut range.
   bool isMature = (highBarsAgo >= lookback / 2) && (lowBarsAgo >= lookback / 2);

   g_currentRange.highPrice      = windowHigh;
   g_currentRange.lowPrice       = windowLow;
   g_currentRange.startTime      = iTime(_Symbol, tf, refShift + lookback - 1);
   g_currentRange.startBar       = lookback - 1;
   g_currentRange.duration       = lookback;
   g_currentRange.isBroken       = false;
   g_currentRange.isBullishBreak = false;
   g_currentRange.breakTime      = 0;
   g_currentRange.isValid        = isMature;
  }

bool GetCurrentRange(RangeInfo &outRange)
  {
   if(!g_currentRange.isValid)
      return false;
   outRange = g_currentRange;
   return true;
  }

bool IsInRange()
  {
   return g_currentRange.isValid && !g_currentRange.isBroken;
  }

void ProcessStructureStep(ENUM_TIMEFRAMES tf, int refShift)
  {
   bool   isHigh;
   double price;

   DetectRange(tf, refShift);

   // --- Deteksi swing EXTERNAL (major) pada posisi refShift+lookback ---
   int pExt = refShift + InpSwingLookback;
   double lowP;
   if(DetectFractalAt(tf, InpSwingLookback, pExt, isHigh, price))
     {
      AddSwing(g_extSwings, tf, pExt, isHigh, price, false);
      if(isHigh && IsFractalLowAt(tf, InpSwingLookback, pExt, lowP))   // GoldPro: outside bar
         AddSwing(g_extSwings, tf, pExt, false, lowP, false);
     }

   // --- Deteksi swing INTERNAL (minor / kandidat IDM) ---
   if(InpUseInternalStructure)
     {
      int pInt = refShift + InpInternalSwingLookback;
      if(DetectFractalAt(tf, InpInternalSwingLookback, pInt, isHigh, price))
        {
         AddSwing(g_intSwings, tf, pInt, isHigh, price, true);
         if(isHigh && IsFractalLowAt(tf, InpInternalSwingLookback, pInt, lowP))
            AddSwing(g_intSwings, tf, pInt, false, lowP, true);
        }
     }

   // --- Cek sweep & structure break TEPAT di titik waktu refShift ini -
   //     bukan di seluruh array tanpa peduli waktu (itu penyebab bug
   //     look-ahead sebelumnya). Karena AddSwing di atas hanya menambah
   //     swing sampai SEJAUH refShift ini, array g_extSwings/g_intSwings
   //     pada titik ini SECARA OTOMATIS hanya berisi swing yang memang
   //     sudah "diketahui" sampai bar ini - tidak ada kontaminasi dari
   //     swing yang baru terbentuk di bar-bar setelahnya. ---
   //
   // URUTAN: internal DULU, baru external (dibalik dari versi sebelumnya).
   // Alasan: WasIDMSweptBeforeBreak() (dipanggil dari cek external) harus
   // membaca status `swept` swing internal TERKINI di refShift ini juga -
   // kalau external dicek duluan, sweep internal yang terjadi TEPAT di
   // bar yang sama belum sempat tercatat, membuat IDM salah dibaca
   // "belum di-sweep" padahal seharusnya sudah. Urutan ini AMAN (tidak
   // menciptakan look-ahead baru) karena isBOS/isCHoCH cuma bergantung
   // pada g_externalBias (diubah HANYA di cabang external, baris di
   // bawah), dan g_internalBias (diubah di cabang internal) TERBUKTI
   // tidak dibaca oleh cabang external maupun modul manapun di seluruh
   // proyek ini (diverifikasi via grep).
   if(InpUseInternalStructure)
      CheckSweepsAndStructureBreaks(tf, true, refShift);
   CheckSweepsAndStructureBreaks(tf, false, refShift);
  }

bool SMC_Structure_Update(ENUM_TIMEFRAMES tf, bool isNewBar)
  {
   if(!isNewBar)
      return false;

   // RETRY OTOMATIS: kalau backfill awal di OnInit gagal/di-skip (histori
   // TF ini belum termuat penuh saat itu), coba lagi di sini, di bar-bar
   // live pertama - sampai berhasil ATAU sampai SMC_BACKFILL_MAX_RETRIES
   // kali percobaan (mencegah percobaan tak berujung kalau memang histori
   // TF ini permanen kurang, misal symbol baru listing).
   if(!g_structureBackfillDone && g_backfillAttempts < SMC_BACKFILL_MAX_RETRIES)
     {
      g_backfillAttempts++;
      PrintFormat("[SMC_Structure] Retry backfill #%d/%d...", g_backfillAttempts, SMC_BACKFILL_MAX_RETRIES);
      SMC_Structure_Backfill(tf);

      // Backfill (kalau berhasil) sudah memproses SAMPAI refShift=1, yaitu
      // bar yang sama dengan bar live saat ini - jadi TIDAK perlu panggil
      // ProcessStructureStep(tf,1) lagi di bawah untuk bar yang sama ini.
      if(g_structureBackfillDone)
         return true;

      // Kalau masih gagal (histori masih kurang), tetap lanjut proses bar
      // live ini seperti biasa di bawah - supaya tidak kehilangan progres
      // sambil menunggu histori termuat penuh.
     }

   // GoldPro PERBAIKAN: dulu selalu `return true` di setiap bar baru -> modul POI mengira ada BOS/CHoCH
   // tiap candle (pencarian OB diulang terus, deteksi Mitigation Block tidak pernah jalan).
   long before = g_nextEventId;
   ProcessStructureStep(tf, 1); // live selalu refShift=1 (bar yang baru closed)
   return (g_nextEventId != before);
  }

//======================================================================
// ACCESSOR STATUS BACKFILL - dipakai Dashboard untuk menampilkan
// peringatan kalau backfill belum/tidak berhasil, supaya user tidak
// salah baca skor kosong sebagai sinyal pasar.
//======================================================================
bool IsStructureBackfilled() { return g_structureBackfillDone; }

//======================================================================
// ACCESSOR - dipakai modul lain (POI, Zones, Scoring, Narrative)
//======================================================================
ENUM_BIAS GetExternalBias() { return g_externalBias; }
ENUM_BIAS GetInternalBias() { return g_internalBias; }

bool GetLastStructureEvent(StructureEvent &outEvent)
  {
   int n = ArraySize(g_structureEvents);
   if(n == 0)
      return false;
   outEvent = g_structureEvents[n - 1];
   return true;
  }

int GetExternalSwingCount() { return ArraySize(g_extSwings); }
bool GetExternalSwing(int index, SwingPoint &outSwing)
  {
   if(index < 0 || index >= ArraySize(g_extSwings))
      return false;
   outSwing = g_extSwings[index];
   return true;
  }

bool GetExternalSwingById(long id, SwingPoint &outSwing)
  {
   for(int i = 0; i < ArraySize(g_extSwings); i++)
      if(g_extSwings[i].id == id)
        {
         outSwing = g_extSwings[i];
         return true;
        }
   return false;
  }

int GetStructureEventCount() { return ArraySize(g_structureEvents); }
bool GetStructureEvent(int index, StructureEvent &outEvent)
  {
   if(index < 0 || index >= ArraySize(g_structureEvents))
      return false;
   outEvent = g_structureEvents[index];
   return true;
  }

//======================================================================
// CalcSwingStrength() - BARU (adopsi xxvw/SMC_ICT_Library, Fase 1).
//   Mengukur "berapa bar ekstra" di luar lookback minimum yang tetap
//   membuat bar `barIndex` (shift ke chart aktif) sebagai ekstrem
//   (high/low tertinggi/terendah) - swing yang bertahan lebih banyak
//   bar ekstra dianggap lebih kuat/lebih signifikan. FUNGSI MANDIRI,
//   tidak menyentuh state g_extSwings/g_intSwings manapun - aman
//   dipanggil kapan saja tanpa efek samping ke detection state.
//   Belum dipakai modul manapun - disiapkan untuk fase scoring lanjutan.
//======================================================================
int CalcSwingStrength(ENUM_TIMEFRAMES tf, int barIndex, bool isHigh)
  {
   double extremePrice = isHigh ? iHigh(_Symbol, tf, barIndex) : iLow(_Symbol, tf, barIndex);
   int strength = 0;
   int maxCheck = 30; // batas wajar, jangan scan tak terbatas

   for(int extra = 1; extra <= maxCheck; extra++)
     {
      double leftVal  = isHigh ? iHigh(_Symbol, tf, barIndex + extra) : iLow(_Symbol, tf, barIndex + extra);
      double rightVal = isHigh ? iHigh(_Symbol, tf, barIndex - extra) : iLow(_Symbol, tf, barIndex - extra);

      bool leftOk  = isHigh ? (leftVal < extremePrice)  : (leftVal > extremePrice);
      bool rightOk = isHigh ? (rightVal < extremePrice) : (rightVal > extremePrice);

      if(!leftOk || !rightOk)
         break; // sudah tidak lagi jadi ekstrem di jarak ini - berhenti

      strength = extra;
     }
   return strength;
  }

//======================================================================
// BACKFILL - dipanggil SEKALI dari SMC_Main.mq5 -> OnInit(), setelah
// SMC_Structure_Init(). Memindai histori yang SUDAH ADA di chart supaya
// swing & structure event langsung terisi begitu indikator dipasang -
// bukan menunggu bar baru terbentuk satu-satu ke depan.
//
// REVISI (fix look-ahead bias, lihat diskusi arsitektur): backfill
// sekarang REPLAY MURNI - memanggil ProcessStructureStep() yang SAMA
// persis dengan jalur live, satu per satu dari bar PALING LAMA ke
// PALING BARU. Ini menjamin backfill dan live TIDAK PERNAH bisa
// menghasilkan struktur yang berbeda, karena cuma ada SATU jalur kode.
//
// Guard eksplisit: fungsi ini WAJIB dipanggil dengan array kosong
// (segera setelah SMC_Structure_Init()). Kalau tidak, dia abort -
// ini menutup kelas bug "backfill dipanggil dua kali tanpa reset"
// secara desain, bukan cuma mengandalkan disiplin caller.
//======================================================================
void SMC_Structure_Backfill(ENUM_TIMEFRAMES tf)
  {
   if(ArraySize(g_structureEvents) > 0 || ArraySize(g_extSwings) > 0)
     {
      Print("[SMC_Structure] WARNING: Backfill dipanggil tanpa Init() sebelumnya - abort untuk mencegah duplikasi.");
      return;
     }

   int available = iBars(_Symbol, tf);
   int scanBars  = MathMin(InpVisualMaxLookbackBars * 2, available - InpSwingLookback - 2);
   if(scanBars <= InpSwingLookback + 1)
     {
      Print("[SMC_Structure] Backfill dilewati: histori belum cukup.");
      return;
     }

   PrintFormat("[SMC_Structure] Backfill dimulai: memindai %d bar historis di %s (replay murni)...", scanBars, EnumToString(tf));

   // Replay murni: SATU loop, dari bar PALING LAMA (refShift=scanBars) ke
   // PALING BARU (refShift=1), memanggil fungsi step yang SAMA dengan live.
   // Tidak ada lagi "kumpulkan semua swing dulu, baru cek breakout" -
   // itu penyebab bug look-ahead sebelumnya (swing dari bar depan bocor
   // ke pengecekan bar lama). Sekarang di tiap refShift, hanya swing yang
   // SUDAH terbentuk sampai bar itu yang ada di array - persis seperti
   // kalau kita menonton live dari awal, candle demi candle.
   for(int refShift = scanBars; refShift >= 1; refShift--)
      ProcessStructureStep(tf, refShift);

   g_structureBackfillDone = true;

   PrintFormat("[SMC_Structure] Backfill selesai: %d swing eksternal, %d structure event ditemukan.",
               ArraySize(g_extSwings), ArraySize(g_structureEvents));
  }

#endif // SMC_STRUCTURE_MQH