//+------------------------------------------------------------------+
//|                                                       SMC_MTF.mqh |
//|                                                                  |
//| Fase 3 - File 12/24 : SMC Pro System                             |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Mengambil bias & zona dari HTF/MTF, lalu menandai LTF POI      |
//|   (dari SMC_POI.mqh) yang overlap dengan zona HTF/MTF sebagai    |
//|   "confluent" (nested POI).                                     |
//|                                                                  |
//| KEPUTUSAN DESAIN PENTING:                                        |
//|   File ini TIDAK menjalankan ulang mesin SMC_Structure.mqh /      |
//|   SMC_POI.mqh yang penuh (dengan strong/weak, IDM, dst) untuk    |
//|   HTF/MTF - state global tunggal di Structure.mqh cuma bisa       |
//|   melacak SATU timeframe (LTF/chart), dan menjadikannya           |
//|   multi-instance adalah refactor besar ke modul paling kritis di  |
//|   proyek ini - risikonya tidak sepadan cuma untuk bias HTF/MTF.   |
//|                                                                   |
//|   UPGRADE (dari v1): bias HTF/MTF sekarang dihitung dari REPLAY    |
//|   higher-high/lower-low sungguhan (CalculateStructuralBias) -     |
//|   bukan lagi cuma "posisi close vs 1 midpoint fractal terakhir"   |
//|   seperti v1. Zona HTF/MTF (ScanSimpleZones, untuk confluence)    |
//|   TETAP versi ringan, belum di-upgrade - itu cuma dipakai untuk   |
//|   penanda "confluent" pada LTF POI, dampaknya lebih kecil         |
//|   dibanding bias yang masuk langsung ke Structure score (30%).   |
//+------------------------------------------------------------------+
#ifndef SMC_MTF_MQH
#define SMC_MTF_MQH

#include "..\Core\SMC_Types.mqh"
#include "..\Core\SMC_Config.mqh"
#include "..\Core\SMC_Utils.mqh"
#include "..\Detection\SMC_POI.mqh"

//======================================================================
// STATE
//======================================================================
ENUM_BIAS  g_htfBias = BIAS_NEUTRAL;
ENUM_BIAS  g_mtfBias = BIAS_NEUTRAL;
OrderBlock g_htfZones[];
OrderBlock g_mtfZones[];

//======================================================================
// INIT
//======================================================================
void SMC_MTF_Init()
  {
   g_htfBias = BIAS_NEUTRAL;
   g_mtfBias = BIAS_NEUTRAL;
   ArrayFree(g_htfZones);
   ArrayFree(g_mtfZones);
  }

//======================================================================
// UPGRADE (menggantikan CalculateSimpleBias lama): bias HTF/MTF
// sekarang dari REPLAY higher-high/lower-low sungguhan - inti logika
// BOS, versi RINGAN tanpa IDM/internal/backfill-retry (itu detail
// khusus LTF yang tidak dibutuhkan cuma untuk baca arah bias).
//
// KENAPA TIDAK PAKAI SMC_Structure.mqh LANGSUNG: modul itu pakai STATE
// GLOBAL TUNGGAL (g_extSwings dst) - cuma bisa melacak SATU timeframe
// sekaligus (LTF/chart). Menjadikannya multi-instance per-TF adalah
// refactor besar ke modul PALING KRITIS di proyek ini (sudah puluhan
// kali diperbaiki & diuji sepanjang sesi) - risikonya tidak sepadan
// cuma untuk keperluan bias HTF/MTF. Fungsi ini berdiri sendiri,
// dihitung ulang dari nol tiap dipanggil (tidak perlu state persisten
// replay-safe seperti LTF, karena tidak ada rendering/scoring detail
// yang bergantung padanya selain arah bias akhir).
//======================================================================
ENUM_BIAS CalculateStructuralBias(ENUM_TIMEFRAMES tf, int lookbackBars = 150, int fractalLookback = 3)
  {
   double   swingPrices[];
   bool     swingIsHigh[];

   // Kumpulkan SEMUA fractal swing di window, urut dari LAMA ke BARU
   // (kebalikan dari versi lama yang cuma ambil satu fractal high +
   // satu fractal low PALING BARU saja).
   for(int p = lookbackBars; p >= fractalLookback + 1; p--)
     {
      double centerHigh = iHigh(_Symbol, tf, p);
      double centerLow  = iLow(_Symbol, tf, p);
      bool isFractalHigh = true, isFractalLow = true;

      for(int i = 1; i <= fractalLookback; i++)
        {
         if(iHigh(_Symbol, tf, p - i) >= centerHigh || iHigh(_Symbol, tf, p + i) >= centerHigh)
            isFractalHigh = false;
         if(iLow(_Symbol, tf, p - i) <= centerLow || iLow(_Symbol, tf, p + i) <= centerLow)
            isFractalLow = false;
        }

      if(isFractalHigh)
        {
         int n = ArraySize(swingPrices);
         ArrayResize(swingPrices, n + 1);
         ArrayResize(swingIsHigh, n + 1);
         swingPrices[n] = centerHigh;
         swingIsHigh[n] = true;
        }
      if(isFractalLow)
        {
         int n = ArraySize(swingPrices);
         ArrayResize(swingPrices, n + 1);
         ArrayResize(swingIsHigh, n + 1);
         swingPrices[n] = centerLow;
         swingIsHigh[n] = false;
        }
     }

   if(ArraySize(swingPrices) < 2)
      return BIAS_NEUTRAL; // belum cukup swing untuk baca struktur

   // Replay: bias mengikuti apakah swing BARU (dari jenis yang sama)
   // membentuk higher-high (bullish) atau lower-low (bearish)
   // dibanding swing SEBELUMNYA dari jenis yang sama - ini inti logika
   // BOS, versi ringan.
   ENUM_BIAS bias = BIAS_NEUTRAL;
   double prevHigh = 0, prevLow = 0;
   bool   hasPrevHigh = false, hasPrevLow = false;

   for(int i = 0; i < ArraySize(swingPrices); i++)
     {
      if(swingIsHigh[i])
        {
         if(hasPrevHigh && swingPrices[i] > prevHigh)
            bias = BIAS_BULLISH; // higher high -> lanjutan/reversal ke bullish
         prevHigh    = swingPrices[i];
         hasPrevHigh = true;
        }
      else
        {
         if(hasPrevLow && swingPrices[i] < prevLow)
            bias = BIAS_BEARISH; // lower low -> lanjutan/reversal ke bearish
         prevLow    = swingPrices[i];
         hasPrevLow = true;
        }
     }

   return bias;
  }

//======================================================================
// HELPER: scan zona sederhana (candle berlawanan arah sebelum candle
// displacement) - versi ringan dari OB detection, dipakai khusus untuk
// keperluan confluence, BUKAN pengganti SMC_POI.mqh yang penuh.
//======================================================================
void ScanSimpleZones(ENUM_TIMEFRAMES tf, OrderBlock &outArr[])
  {
   ArrayFree(outArr);
   int maxScan = 40;

   for(int s = 2; s < maxScan && ArraySize(outArr) < 5; s++)
     {
      double disp = GetBodyToRangeRatio(s - 1, tf);
      if(disp < InpOBDisplacementMinBody)
         continue;

      bool impulseBullish = IsBullishCandle(s - 1, tf);
      bool candBullish    = IsBullishCandle(s, tf);
      if(candBullish == impulseBullish)
         continue; // candle kandidat harus berlawanan warna dari leg impulsif

      int n = ArraySize(outArr);
      ArrayResize(outArr, n + 1);
      outArr[n].id          = 0; // tidak dipakai untuk zona sementara ini
      outArr[n].time        = iTime(_Symbol, tf, s);
      outArr[n].high        = NormalizePriceForSymbol(iHigh(_Symbol, tf, s));
      outArr[n].low         = NormalizePriceForSymbol(iLow(_Symbol, tf, s));
      outArr[n].isBullish   = impulseBullish;
      outArr[n].poiType     = POI_ORDER_BLOCK;
      outArr[n].hasFVG      = false;
      outArr[n].status      = ZONE_FRESH;
      outArr[n].ceLevel     = (outArr[n].high + outArr[n].low) / 2.0;
      outArr[n].touchCount  = 0;
      outArr[n].sourceTF    = tf;
      outArr[n].isConfluent = false;
     }
  }

//======================================================================
// HELPER: cek overlap harga antara satu OB target dan array zona lain
//======================================================================
bool ZoneOverlapsAny(OrderBlock &target, OrderBlock &arr[])
  {
   for(int i = 0; i < ArraySize(arr); i++)
     {
      if(arr[i].isBullish != target.isBullish)
         continue;
      bool overlap = !(target.high < arr[i].low || target.low > arr[i].high);
      if(overlap)
         return true;
     }
   return false;
  }

//======================================================================
// Tandai LTF POI (dari SMC_POI.mqh) yang overlap zona HTF/MTF
//======================================================================
void MarkConfluenceOnLTFPOI()
  {
   for(int i = 0; i < GetOBCount(); i++)
     {
      OrderBlock ltfOB;
      if(!GetOB(i, ltfOB))
         continue;

      bool confluent = ZoneOverlapsAny(ltfOB, g_htfZones) || ZoneOverlapsAny(ltfOB, g_mtfZones);
      if(confluent)
         SetOBConfluent(i, true);
     }
  }

//======================================================================
// FUNGSI UTAMA
//======================================================================
// FIX (bug ditemukan lewat diagnostik - MTF selalu false, HTF benar):
// IsNewBar() itu fungsi BERSAMA dikunci per NILAI TIMEFRAME, bukan per
// PEMANGGIL. Kalau modul lain (misal SMC_SupplyDemand dengan
// InpSDTimeframe=H1) MEMANGGIL IsNewBar(PERIOD_H1) LEBIH DULU di tick
// yang sama dengan InpMTF=H1, status "true"-nya sudah "dihabiskan"
// sebelum SMC_MTF_Update sempat bertanya sendiri. Komentar LAMA di sini
// dulu mengasumsikan "aman karena tidak ada modul lain yang pakai TF
// ini" - asumsi itu SALAH (persis yang menyebabkan bug ini) begitu
// modul Paus ditambahkan dengan InpSDTimeframe default H1. Fix: TERIMA
// newHTF/newMTF sebagai PARAMETER (dihitung SEKALI di SMC_Main.mq5,
// dibagikan ke modul manapun yang butuh TF yang sama) - bukan panggil
// IsNewBar() sendiri di sini lagi.
void SMC_MTF_Update(bool newHTF, bool newMTF)
  {
   if(newHTF)
     {
      g_htfBias = CalculateStructuralBias(InpHTF);
      ScanSimpleZones(InpHTF, g_htfZones);
     }
   if(newMTF)
     {
      g_mtfBias = CalculateStructuralBias(InpMTF);
      ScanSimpleZones(InpMTF, g_mtfZones);
     }

   if(InpEnableNestedPOIConfluence && (newHTF || newMTF))
      MarkConfluenceOnLTFPOI();
  }

//======================================================================
// ACCESSOR
//======================================================================
ENUM_BIAS GetHTFBias() { return g_htfBias; }
ENUM_BIAS GetMTFBias() { return g_mtfBias; }

int GetHTFZoneCount() { return ArraySize(g_htfZones); }
bool GetHTFZone(int index, OrderBlock &outZone)
  {
   if(index < 0 || index >= ArraySize(g_htfZones))
      return false;
   outZone = g_htfZones[index];
   return true;
  }

int GetMTFZoneCount() { return ArraySize(g_mtfZones); }
bool GetMTFZone(int index, OrderBlock &outZone)
  {
   if(index < 0 || index >= ArraySize(g_mtfZones))
      return false;
   outZone = g_mtfZones[index];
   return true;
  }

#endif // SMC_MTF_MQH