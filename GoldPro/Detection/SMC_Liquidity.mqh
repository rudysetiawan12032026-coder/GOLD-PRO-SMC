//+------------------------------------------------------------------+
//|                                                SMC_Liquidity.mqh |
//|                                                                  |
//| Fase 2 - File 7/24 : SMC Pro System                             |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Mendeteksi kumpulan likuiditas (equal highs/lows) dan event    |
//|   sweep-nya, plus referensi draw-on-liquidity (PDH/PDL/dst).     |
//|                                                                  |
//| ATURAN PENTING (perbaikan dari desain awal):                    |
//|   File ini MURNI HARGA. Tidak ada satupun logic terkait waktu    |
//|   sesi atau klasifikasi "Judas Swing" di sini - itu tugas        |
//|   SMC_AMD.mqh yang menggabungkan hasil file ini dengan            |
//|   SMC_Session.mqh. Kalau ada kebutuhan tahu "jam berapa sekarang"|
//|   di file ini, itu tandanya logic tersebut salah tempat.        |
//+------------------------------------------------------------------+
#ifndef SMC_LIQUIDITY_MQH
#define SMC_LIQUIDITY_MQH

#include "..\Core\SMC_Types.mqh"
#include "..\Core\SMC_Config.mqh"
#include "..\Core\SMC_Utils.mqh"
#include "SMC_Structure.mqh"

//======================================================================
// STATE
//======================================================================
LiquidityPool      g_liquidityPools[];
DrawOnLiquidityRef  g_drawRefs[];
long                g_nextLiquidityId = 1;
long                g_processedSwingIds[]; // swing yang sudah dimasukkan ke clustering

bool g_liquidityBackfillDone     = false;
int  g_liquidityBackfillAttempts = 0;
#define SMC_LIQUIDITY_BACKFILL_MAX_RETRIES 1

//======================================================================
// INIT
//======================================================================
void SMC_Liquidity_Init()
  {
   ArrayFree(g_liquidityPools);
   ArrayFree(g_drawRefs);
   ArrayFree(g_processedSwingIds);
   g_nextLiquidityId = 1;
   g_liquidityBackfillDone     = false;
   g_liquidityBackfillAttempts = 0;
  }

//======================================================================
// HELPER: cek apakah swing id sudah pernah diproses
//======================================================================
bool IsSwingProcessed(long id)
  {
   for(int i = 0; i < ArraySize(g_processedSwingIds); i++)
      if(g_processedSwingIds[i] == id)
         return true;
   return false;
  }

void MarkSwingProcessed(long id)
  {
   int n = ArraySize(g_processedSwingIds);
   ArrayResize(g_processedSwingIds, n + 1);
   g_processedSwingIds[n] = id;
   if(ArraySize(g_processedSwingIds) > 200)
      ArrayRemove(g_processedSwingIds, 0, 1);
  }

//======================================================================
// CLUSTERING: kelompokkan swing external jadi liquidity pool
// (equal highs/lows dengan toleransi berbasis ATR)
//
// FIX PENTING (mencegah look-ahead di backfill): parameter `upToTime`
// membatasi swing yang boleh diproses HANYA sampai titik waktu itu.
// Ini WAJIB untuk backfill karena SMC_Structure_Backfill() SUDAH
// mengisi SELURUH swing 400 bar SEBELUM Liquidity backfill mulai jalan
// (beda dari Structure yang array-nya tumbuh incremental sambil
// di-replay sendiri) - tanpa filter ini, clustering di titik waktu LAMA
// akan "melihat" swing dari MASA DEPAN yang sudah lebih dulu ada di
// array Structure, persis kelas bug look-ahead yang sudah pernah
// ditemukan & diperbaiki di SMC_Structure.mqh.
//======================================================================
void ClusterSwingsIntoPools(ENUM_TIMEFRAMES tf, datetime upToTime)
  {
   double atr = GetATR(tf, 14, 1);
   double tolerance = atr * InpEqualLevelToleranceATR;
   if(tolerance <= 0)
      return;

   int count = GetExternalSwingCount();
   for(int i = 0; i < count; i++)
     {
      SwingPoint sp;
      if(!GetExternalSwing(i, sp))
         continue;
      if(sp.time > upToTime)
         continue; // FILTER LOOK-AHEAD: swing ini "belum terjadi" di titik replay ini
      if(IsSwingProcessed(sp.id))
         continue;

      MarkSwingProcessed(sp.id);

      // Cari pool existing dalam toleransi & tipe (buy-side/sell-side) yang sama
      int matchIndex = -1;
      for(int p = 0; p < ArraySize(g_liquidityPools); p++)
        {
         if(g_liquidityPools[p].isBuySide != sp.isHigh)
            continue;
         if(MathAbs(g_liquidityPools[p].price - sp.price) <= tolerance)
           {
            matchIndex = p;
            break;
           }
        }

      if(matchIndex >= 0)
        {
         g_liquidityPools[matchIndex].touchCount++;
         g_liquidityPools[matchIndex].lastTouch = sp.time;
         // Rata-rata bergerak sederhana supaya level pool tetap representatif
         g_liquidityPools[matchIndex].price =
            (g_liquidityPools[matchIndex].price + sp.price) / 2.0;
        }
      else
        {
         int n = ArraySize(g_liquidityPools);
         ArrayResize(g_liquidityPools, n + 1);
         g_liquidityPools[n].id         = g_nextLiquidityId++;
         g_liquidityPools[n].price      = sp.price;
         g_liquidityPools[n].firstTouch = sp.time;
         g_liquidityPools[n].lastTouch  = sp.time;
         g_liquidityPools[n].touchCount = 1;
         g_liquidityPools[n].swept      = false;
         g_liquidityPools[n].sweptTime  = 0;
         g_liquidityPools[n].isBuySide  = sp.isHigh;
        }
     }
  }

//======================================================================
// SWEEP DETECTION: scan window bar untuk pola wick-tembus lalu closing
// kembali (klasik liquidity grab / stop hunt).
//
// FIX (replay murni): `refShift` menggantikan shift hardcode 1..N -
// window yang diperiksa sekarang RELATIF terhadap refShift (titik
// "sekarang" versi replay), bukan selalu relatif terhadap bar
// TERAKTUAL sungguhan. Untuk live, refShift=1, window jadi PERSIS
// sama seperti versi lama (shift 1..N) - tidak ada perubahan perilaku
// live sama sekali.
//======================================================================
bool CheckSweepPattern(ENUM_TIMEFRAMES tf, bool isBuySide, double level, int refShift, datetime &outSweptTime)
  {
   for(int offset = 0; offset < InpSweepConfirmMaxBars; offset++)
     {
      int s = refShift + offset;
      double h = iHigh(_Symbol, tf, s);
      double l = iLow(_Symbol, tf, s);
      double c = iClose(_Symbol, tf, s);

      if(isBuySide && h > level && c < level)
        {
         outSweptTime = iTime(_Symbol, tf, s);
         return true;
        }
      if(!isBuySide && l < level && c > level)
        {
         outSweptTime = iTime(_Symbol, tf, s);
         return true;
        }
     }
   return false;
  }

void UpdateSweepStatus(ENUM_TIMEFRAMES tf, int refShift)
  {
   for(int i = 0; i < ArraySize(g_liquidityPools); i++)
     {
      if(g_liquidityPools[i].swept)
         continue;

      datetime sweptTime;
      if(CheckSweepPattern(tf, g_liquidityPools[i].isBuySide, g_liquidityPools[i].price, refShift, sweptTime))
        {
         g_liquidityPools[i].swept     = true;
         g_liquidityPools[i].sweptTime = sweptTime;
         PrintFormat("[SMC_Liquidity] %s liquidity swept @ %.5f (%s)",
                     g_liquidityPools[i].isBuySide ? "BSL" : "SSL",
                     g_liquidityPools[i].price, TimeToString(sweptTime));
        }
     }
  }

//======================================================================
// DRAW-ON-LIQUIDITY REFERENCE (PDH/PDL/PWH/PWL/Daily-Weekly Open)
//   Tidak perlu versi replay - ini selalu merujuk ke D1/W1 TERKINI,
//   bukan sesuatu yang butuh "diketahui di titik waktu tertentu".
//======================================================================
void UpdateDrawOnLiquidityRefs()
  {
   ArrayFree(g_drawRefs);

   double pdh = iHigh(_Symbol, PERIOD_D1, 1);
   double pdl = iLow(_Symbol, PERIOD_D1, 1);
   double pwh = iHigh(_Symbol, PERIOD_W1, 1);
   double pwl = iLow(_Symbol, PERIOD_W1, 1);
   double dOpen = iOpen(_Symbol, PERIOD_D1, 0);
   double wOpen = iOpen(_Symbol, PERIOD_W1, 0);

   datetime dTime = iTime(_Symbol, PERIOD_D1, 1);
   datetime wTime = iTime(_Symbol, PERIOD_W1, 1);
   datetime dTime0 = iTime(_Symbol, PERIOD_D1, 0);
   datetime wTime0 = iTime(_Symbol, PERIOD_W1, 0);

   string   labels[6] = {"PDH", "PDL", "PWH", "PWL", "Daily Open", "Weekly Open"};
   double   prices[6] = {pdh, pdl, pwh, pwl, dOpen, wOpen};
   datetime times[6]  = {dTime, dTime, wTime, wTime, dTime0, wTime0};

   ArrayResize(g_drawRefs, 6);
   for(int i = 0; i < 6; i++)
     {
      g_drawRefs[i].label         = labels[i];
      g_drawRefs[i].price         = NormalizePriceForSymbol(prices[i]);
      g_drawRefs[i].referenceTime = times[i];
     }
  }

//======================================================================
// DetectEqualHighsLows() - Fase 2 (adopsi xxvw/SMC_ICT_Library).
//
// CATATAN DESAIN (beda dari instruksi asli, dengan alasan): ini BUKAN
// clustering baru yang terpisah - itu akan menduplikasi
// ClusterSwingsIntoPools yang sudah ada dan sudah replay-correct untuk
// SELURUH swing (bukan cuma 10 terakhir). Fungsi ini murni KLASIFIKASI
// - mengisi field `type`/`isValid` (ditambahkan Fase 1, sengaja
// dibiarkan kosong sampai sekarang) pada `g_liquidityPools` yang SUDAH
// terbentuk, berdasarkan touchCount yang sudah dihitung clustering.
//   touchCount == 1 -> isValid=false (baru satu swing, belum "equal" apapun)
//   touchCount == 2 -> LIQ_EQUAL_HIGHS/LOWS, isValid=true
//   touchCount >= 3 -> LIQ_POOL_HIGH/LOW, isValid=true
// Dipanggil tiap langkah replay (live & backfill) - murah (O(n) atas
// pool yang sudah ada, bukan O(n^2) atas swing).
//======================================================================
void DetectEqualHighsLows(ENUM_TIMEFRAMES tf)
  {
   for(int i = 0; i < ArraySize(g_liquidityPools); i++)
     {
      int tc = g_liquidityPools[i].touchCount;
      bool isHighSide = g_liquidityPools[i].isBuySide; // isBuySide true = sisi HIGH (BSL)

      if(tc < 2)
        {
         g_liquidityPools[i].isValid = false;
        }
      else if(tc == 2)
        {
         g_liquidityPools[i].type    = isHighSide ? LIQ_EQUAL_HIGHS : LIQ_EQUAL_LOWS;
         g_liquidityPools[i].isValid = true;
        }
      else // tc >= 3
        {
         g_liquidityPools[i].type    = isHighSide ? LIQ_POOL_HIGH : LIQ_POOL_LOW;
         g_liquidityPools[i].isValid = true;
        }
     }
  }

//======================================================================
// SATU LANGKAH REPLAY - dipakai LIVE (refShift=1) MAUPUN BACKFILL
// (refShift bervariasi dari lama ke baru). Satu jalur kode, sama
// persis dengan pola yang sudah terbukti benar di SMC_Structure.mqh.
//======================================================================
void ProcessLiquidityStep(ENUM_TIMEFRAMES tf, int refShift)
  {
   datetime refTime = iTime(_Symbol, tf, refShift);
   if(refTime == 0)
      return;

   ClusterSwingsIntoPools(tf, refTime);
   UpdateSweepStatus(tf, refShift);
   DetectEqualHighsLows(tf);
  }

//======================================================================
// BACKFILL - dipanggil dari SMC_Main.mq5 -> OnInit(), SETELAH
// SMC_Structure_Backfill() selesai (butuh g_extSwings sudah terisi).
//
// Guard eksplisit (pola sama dengan SMC_Structure_Backfill): abort
// kalau dipanggil tanpa array kosong, mencegah duplikasi.
//======================================================================
void SMC_Liquidity_Backfill(ENUM_TIMEFRAMES tf)
  {
   if(ArraySize(g_liquidityPools) > 0)
     {
      Print("[SMC_Liquidity] WARNING: Backfill dipanggil tanpa Init() sebelumnya - abort untuk mencegah duplikasi.");
      return;
     }

   int available = iBars(_Symbol, tf);
   int scanBars  = MathMin(InpVisualMaxLookbackBars * 2, available - 2);
   if(scanBars <= 1)
     {
      Print("[SMC_Liquidity] Backfill dilewati: histori belum cukup.");
      return;
     }

   PrintFormat("[SMC_Liquidity] Backfill dimulai: replay %d bar historis di %s...", scanBars, EnumToString(tf));

   for(int refShift = scanBars; refShift >= 1; refShift--)
      ProcessLiquidityStep(tf, refShift);

   g_liquidityBackfillDone = true;
   PrintFormat("[SMC_Liquidity] Backfill selesai: %d liquidity pool ditemukan.", ArraySize(g_liquidityPools));
  }

//======================================================================
// FUNGSI UTAMA (LIVE)
//======================================================================
void SMC_Liquidity_Update(ENUM_TIMEFRAMES tf, bool isNewBar)
  {
   if(!isNewBar)
      return;

   // RETRY OTOMATIS 1x (pola sama dengan SMC_Structure.mqh): kalau
   // backfill awal di OnInit gagal/di-skip, coba lagi di bar live
   // pertama. Cukup 1x karena percobaan kedua dst pasti kena guard
   // (array sudah terisi dari live) - sudah dibuktikan di diskusi
   // Structure sebelumnya, sama persis berlaku di sini.
   if(!g_liquidityBackfillDone && g_liquidityBackfillAttempts < SMC_LIQUIDITY_BACKFILL_MAX_RETRIES)
     {
      g_liquidityBackfillAttempts++;
      SMC_Liquidity_Backfill(tf);
      if(g_liquidityBackfillDone)
        {
         UpdateDrawOnLiquidityRefs();
         return;
        }
     }

   ProcessLiquidityStep(tf, 1);
   UpdateDrawOnLiquidityRefs();
  }

//======================================================================
// ACCESSOR
//======================================================================
int GetLiquidityPoolCount() { return ArraySize(g_liquidityPools); }
bool GetLiquidityPool(int index, LiquidityPool &outPool)
  {
   if(index < 0 || index >= ArraySize(g_liquidityPools))
      return false;
   outPool = g_liquidityPools[index];
   return true;
  }

// Target likuiditas terdekat yang BELUM di-sweep, searah kebutuhan (buy-side/sell-side).
//
// FIX (bug ditemukan dari screenshot - target BSL kedua lebih RENDAH
// dari target pertama, tidak masuk akal untuk skenario "lanjut ke
// atas"): sebelumnya cuma filter `swept==false`. Masalahnya,
// CheckSweepPattern() butuh pola SPESIFIK ("wick tembus lalu close
// balik") untuk menandai level sebagai swept - kalau harga menembus
// level itu secara BERSIH (rally kuat tanpa pernah close balik ke
// bawahnya lagi), level itu TETAP tercatat "belum di-sweep" SELAMANYA,
// walau harga sudah jauh melewatinya. Akibatnya level BASI itu tetap
// muncul sebagai "target" walau sebenarnya sudah di BELAKANG harga.
// Fix: tambah filter ARAH - target BSL harus BENAR-BENAR di ATAS
// referencePrice, target SSL harus di BAWAH - "belum di-sweep" saja
// tidak cukup, harus juga "masih di depan".
bool GetNearestLiquidityTarget(bool wantBuySide, double referencePrice, LiquidityPool &outPool)
  {
   bool   found    = false;
   double bestDist = DBL_MAX;

   for(int i = 0; i < ArraySize(g_liquidityPools); i++)
     {
      if(g_liquidityPools[i].isBuySide != wantBuySide)
         continue;
      if(g_liquidityPools[i].swept)
         continue;
      if(wantBuySide  && g_liquidityPools[i].price <= referencePrice)
         continue; // BSL tapi sudah di BAWAH/sama harga sekarang - basi, sudah dilewati
      if(!wantBuySide && g_liquidityPools[i].price >= referencePrice)
         continue; // SSL tapi sudah di ATAS/sama harga sekarang - basi, sudah dilewati

      double dist = MathAbs(g_liquidityPools[i].price - referencePrice);
      if(dist < bestDist)
        {
         bestDist = dist;
         outPool  = g_liquidityPools[i];
         found    = true;
        }
     }
   return found;
  }

// Liquidity pool yang PALING BARU di-sweep, dari SELURUH histori pool -
// TIDAK dibatasi window sesi apapun (beda dari Judas Swing check di
// SMC_AMD.mqh yang cuma menengok window London/NY). Dipakai SMC_AMD.mqh
// untuk mendeteksi manipulasi/sweep segar yang terjadi DI LUAR window
// Judas standar (misal saat off-session, tapi ada sweep signifikan).
bool GetLastLiquidityEvent(LiquidityPool &outPool)
  {
   bool     found    = false;
   datetime bestTime = 0;

   for(int i = 0; i < ArraySize(g_liquidityPools); i++)
     {
      if(!g_liquidityPools[i].swept)
         continue;
      if(g_liquidityPools[i].sweptTime > bestTime)
        {
         bestTime = g_liquidityPools[i].sweptTime;
         outPool  = g_liquidityPools[i];
         found    = true;
        }
     }
   return found;
  }

bool IsLiquidityBackfilled() { return g_liquidityBackfillDone; }

// GetNearestEqualHigh/Low - Fase 2. Cari pool VALID (touchCount>=2,
// sudah terklasifikasi EQUAL/POOL) terdekat dari harga, di sisi yang
// diminta. Beda dari GetNearestLiquidityTarget: fungsi itu untuk
// "target arah tertentu" (dipakai garis Tujuan), ini untuk "EQH/EQL
// apapun arahnya" (dipakai render label EQH/EQL/POOL).
bool GetNearestEqualHigh(double price, LiquidityPool &outPool)
  {
   bool   found    = false;
   double bestDist = DBL_MAX;
   for(int i = 0; i < ArraySize(g_liquidityPools); i++)
     {
      if(!g_liquidityPools[i].isValid || !g_liquidityPools[i].isBuySide)
         continue;
      double dist = MathAbs(g_liquidityPools[i].price - price);
      if(dist < bestDist)
        {
         bestDist = dist;
         outPool  = g_liquidityPools[i];
         found    = true;
        }
     }
   return found;
  }

bool GetNearestEqualLow(double price, LiquidityPool &outPool)
  {
   bool   found    = false;
   double bestDist = DBL_MAX;
   for(int i = 0; i < ArraySize(g_liquidityPools); i++)
     {
      if(!g_liquidityPools[i].isValid || g_liquidityPools[i].isBuySide)
         continue;
      double dist = MathAbs(g_liquidityPools[i].price - price);
      if(dist < bestDist)
        {
         bestDist = dist;
         outPool  = g_liquidityPools[i];
         found    = true;
        }
     }
   return found;
  }

// Ambil sampai N pool VALID terdekat dari `price`, di sisi tertentu,
// diurutkan dari terdekat - dipakai SMC_RenderLiquidity.mqh untuk
// "5 EQH/EQL terdekat". Fungsi query murni, tidak mengubah state.
int GetNearestValidPools(double price, bool wantBuySide, int maxCount, LiquidityPool &outPools[])
  {
   int    idxs[];
   double dists[];
   for(int i = 0; i < ArraySize(g_liquidityPools); i++)
     {
      if(!g_liquidityPools[i].isValid || g_liquidityPools[i].isBuySide != wantBuySide)
         continue;
      int n = ArraySize(idxs);
      ArrayResize(idxs, n + 1);
      ArrayResize(dists, n + 1);
      idxs[n]  = i;
      dists[n] = MathAbs(g_liquidityPools[i].price - price);
     }

   // Selection sort sederhana - jumlah pool valid biasanya kecil (puluhan), aman.
   int total = ArraySize(idxs);
   int take  = MathMin(maxCount, total);
   ArrayResize(outPools, take);
   for(int k = 0; k < take; k++)
     {
      int    bestPos = -1;
      double bestVal = DBL_MAX;
      for(int j = 0; j < total; j++)
        {
         if(dists[j] < 0)
            continue; // sudah diambil
         if(dists[j] < bestVal)
           {
            bestVal = dists[j];
            bestPos = j;
           }
        }
      if(bestPos < 0)
         break;
      outPools[k] = g_liquidityPools[idxs[bestPos]];
      dists[bestPos] = -1;
     }
   return take;
  }

// HasRecentSweep() - Fase 2. Fungsi QUERY murni di atas data sweep
// yang SUDAH ADA (dihasilkan UpdateSweepStatus/CheckSweepPattern yang
// sudah replay-correct sejak Batch 4) - bukan mesin deteksi baru.
bool HasRecentSweep(int withinBars = 20)
  {
   datetime cutoff = iTime(_Symbol, PERIOD_CURRENT, withinBars);
   if(cutoff == 0)
      return false;

   for(int i = 0; i < ArraySize(g_liquidityPools); i++)
      if(g_liquidityPools[i].swept && g_liquidityPools[i].sweptTime >= cutoff)
         return true;
   return false;
  }

// GetSecondNearestLiquidityTarget() - dipakai skenario "kalau tembus
// target pertama, lanjut ke mana". Sama seperti GetNearestLiquidityTarget
// tapi MENGABAIKAN satu harga tertentu (target pertama yang sudah
// ditemukan) supaya hasilnya benar-benar "target BERIKUTNYA", bukan
// yang sama lagi.
bool GetSecondNearestLiquidityTarget(bool wantBuySide, double referencePrice,
                                      double excludePrice, LiquidityPool &outPool)
  {
   bool   found    = false;
   double bestDist = DBL_MAX;

   for(int i = 0; i < ArraySize(g_liquidityPools); i++)
     {
      if(g_liquidityPools[i].isBuySide != wantBuySide)
         continue;
      if(g_liquidityPools[i].swept)
         continue;
      if(MathAbs(g_liquidityPools[i].price - excludePrice) < _Point) // ini target pertama, lewati
         continue;
      // FIX (bug sama dengan GetNearestLiquidityTarget): filter ARAH,
      // bukan cuma status swept - cegah level basi yang sudah dilewati
      // harga (tanpa sempat "di-sweep" secara teknis) muncul sebagai
      // target lanjutan.
      if(wantBuySide  && g_liquidityPools[i].price <= referencePrice)
         continue;
      if(!wantBuySide && g_liquidityPools[i].price >= referencePrice)
         continue;

      double dist = MathAbs(g_liquidityPools[i].price - referencePrice);
      if(dist < bestDist)
        {
         bestDist = dist;
         outPool  = g_liquidityPools[i];
         found    = true;
        }
     }
   return found;
  }

int GetDrawOnLiquidityRefCount() { return ArraySize(g_drawRefs); }
bool GetDrawOnLiquidityRef(int index, DrawOnLiquidityRef &outRef)
  {
   if(index < 0 || index >= ArraySize(g_drawRefs))
      return false;
   outRef = g_drawRefs[index];
   return true;
  }

#endif // SMC_LIQUIDITY_MQH