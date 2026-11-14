//+------------------------------------------------------------------+
//|                                                    SMC_Zones.mqh |
//|                                                                  |
//| Fase 2 - File 5/24 : SMC Pro System                             |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Menghitung dealing range aktif dan pembagian                  |
//|   Premium/Discount/Equilibrium + band OTE (Optimal Trade Entry) |
//|   di dalamnya.                                                  |
//|                                                                  |
//| ATURAN PENTING:                                                 |
//|   Dealing range BUKAN sembarang rentang candle - ini dihitung   |
//|   dari swing EXTERNAL terakhir (via SMC_Structure.mqh), dan     |
//|   WAJIB di-update ulang setiap kali ada swing external baru     |
//|   atau structure event (BOS/CHoCH) baru. Range lama otomatis    |
//|   tidak relevan begitu struktur besar berubah.                  |
//+------------------------------------------------------------------+
#ifndef SMC_ZONES_MQH
#define SMC_ZONES_MQH

#include "..\Core\SMC_Types.mqh"
#include "..\Core\SMC_Config.mqh"
#include "..\Core\SMC_Utils.mqh"
#include "SMC_Structure.mqh"

//======================================================================
// STATE
//======================================================================
DealingRange g_dealingRange;

//======================================================================
// INIT
//======================================================================
void SMC_Zones_Init()
  {
   ZeroMemory(g_dealingRange);
   g_dealingRange.isValid = false;
  }

//======================================================================
// HELPER INTERNAL: hitung OTE band berdasarkan arah origin leg
//   Bullish origin (leg naik dari low ke high) -> OTE untuk BUY ada di
//   sisi bawah range (retracement 61.8%-79% dari high, setara 21%-38.2%
//   dari low).
//   Bearish origin (leg turun dari high ke low) -> OTE untuk SELL ada
//   di sisi atas range (61.8%-79% dari low).
//======================================================================
void ComputeOTEBand(ENUM_BIAS originDirection, double high, double low, double &oteBottom, double &oteTop)
  {
   double range = high - low;
   if(range <= 0)
     {
      oteBottom = 0;
      oteTop    = 0;
      return;
     }

   if(originDirection == BIAS_BULLISH)
     {
      // OTE di sisi Discount (bawah), untuk entry BUY
      oteBottom = low + range * 0.21;
      oteTop    = low + range * 0.382;
     }
   else // BIAS_BEARISH
     {
      // OTE di sisi Premium (atas), untuk entry SELL
      oteBottom = low + range * 0.618;
      oteTop    = low + range * 0.79;
     }
  }

// Ukuran window swing yang dipindai sebagai FALLBACK (kalau tidak ada
// leg terbaru yang cukup signifikan). Konstanta internal.
#define SMC_DEALING_RANGE_WINDOW 10
#define SMC_DEALING_RANGE_MAX_LOOKBACK 20

//======================================================================
// FUNGSI UTAMA - dipanggil dari SMC_Main.mq5 tiap OnCalculate()
//   Menerima `isNewBar` langsung (BUKAN `structureChanged` lagi - fix
//   Bug #4): dealing range harus dihitung ulang TIAP bar baru, bukan
//   cuma saat ada swing/event baru. Alasan: swing TERBARU yang jadi
//   acuan range bisa TETAP SAMA sementara harga terus bergerak relatif
//   terhadapnya - kalau update ditunda sampai structureChanged, range
//   jadi basi (stale) selama berjam-jam padahal posisi harga terhadap
//   Discount/Premium sudah berubah signifikan.
//
// REDESAIN (permintaan eksplisit - prioritas PRESISI ARAH di atas
// menghindari leg mikro): sebelumnya dealing range dicari dari HIGH
// TERTINGGI & LOW TERENDAH di antara 10 swing terakhir (leg TERLEBAR,
// bisa jadi leg LAMA yang sudah tidak relevan dengan arah harga
// SEKARANG). Sekarang PRIORITASKAN leg PALING BARU yang cukup
// signifikan (>= 1x ATR) - supaya Premium/Discount/Equilibrium selalu
// mengikuti leg AKTIF, bukan leg lama yang kebetulan lebih lebar.
// Kalau leg terbaru manapun tidak ada yang cukup besar (pasar sangat
// choppy/mikro), baru fallback ke logika lama (terlebar dari window)
// sebagai jaring pengaman - mencegah regresi ke bug "Zone: 0" di M5/M1
// yang sudah pernah diperbaiki.
//======================================================================
void SMC_Zones_Update(bool isNewBar)
  {
   if(!isNewBar)
      return;

   int extCount = GetExternalSwingCount();
   if(extCount < 2)
     {
      g_dealingRange.isValid = false; // belum cukup swing untuk bentuk range
      return;
     }

   double minLegSize = GetATR(PERIOD_CURRENT, 14, 1);
   if(minLegSize <= 0.0)
      minLegSize = 0.0; // ATR gagal dihitung - jangan blokir, longgarkan syarat minimum

   //--- GoldPro KOTAK CEPAT (research\box_trend.py, M5 2017-2026): kotak lama baru muncul median 25 mnt
   //    setelah puncak/dasar (menunggu konfirmasi fractal 5 candle); saat itu harga sudah bergerak median 46%
   //    tinggi kotak dan 46% kasus sudah lewat EQ. Kotak cepat: ujung jauh = high/low BERJALAN sejak swing
   //    external terakhir, dipakai begitu leg >= 1 ATR -> muncul 0 mnt setelah ekstrem (harga baru 13%, lewat
   //    EQ 8%). Tanpa melihat masa depan: ujung hanya bergeser saat harga membuat ekstrem baru.
   if(InpFastBox && minLegSize > 0.0)
     {
      SwingPoint last;
      if(GetExternalSwing(extCount - 1, last))
        {
         int s0 = iBarShift(_Symbol, PERIOD_CURRENT, last.time);
         double run = 0.0;
         datetime runT = 0;
         for(int s = s0 - 1; s >= 1; s--)
           {
            double v = last.isHigh ? iLow(_Symbol, PERIOD_CURRENT, s) : iHigh(_Symbol, PERIOD_CURRENT, s);
            if(runT == 0 || (last.isHigh ? v < run : v > run)) { run = v; runT = iTime(_Symbol, PERIOD_CURRENT, s); }
           }
         if(runT > 0 && MathAbs(run - last.price) >= minLegSize)
           {
            g_dealingRange.isValid         = true;
            g_dealingRange.high            = MathMax(run, last.price);
            g_dealingRange.low             = MathMin(run, last.price);
            g_dealingRange.midpoint        = (g_dealingRange.high + g_dealingRange.low) / 2.0;
            g_dealingRange.originDirection = last.isHigh ? BIAS_BEARISH : BIAS_BULLISH;   // swing high -> leg turun
            g_dealingRange.time_start      = last.time;
            g_dealingRange.time_end        = runT;
            ComputeOTEBand(g_dealingRange.originDirection, g_dealingRange.high, g_dealingRange.low,
                           g_dealingRange.oteBottom, g_dealingRange.oteTop);
            return;
           }
        }
     }

   bool     found     = false;
   double   highPrice = 0.0, lowPrice = 0.0;
   datetime highTime  = 0,   lowTime  = 0;

   int maxLookback = MathMin(extCount, SMC_DEALING_RANGE_MAX_LOOKBACK);
   int oldestAnchor = extCount - maxLookback;

   // Mulai dari swing PALING BARU sebagai anchor, mundur satu-satu kalau
   // pasangannya belum cukup signifikan.
   for(int anchorIdx = extCount - 1; anchorIdx >= oldestAnchor; anchorIdx--)
     {
      SwingPoint anchor;
      if(!GetExternalSwing(anchorIdx, anchor))
         continue;

      // Cari swing BERLAWANAN tipe TERDEKAT sebelum anchor ini saja
      // (bukan cari yang terlebar) - supaya leg yang terbentuk benar-benar
      // leg TERBARU, bukan gabungan swing yang jauh terpisah.
      for(int j = anchorIdx - 1; j >= 0; j--)
        {
         SwingPoint partner;
         if(!GetExternalSwing(j, partner))
            continue;
         if(partner.isHigh == anchor.isHigh)
            continue; // tipe sama, bukan pasangan leg - lewati, cari lebih jauh

         double   h  = anchor.isHigh ? anchor.price : partner.price;
         double   l  = anchor.isHigh ? partner.price : anchor.price;
         datetime hT = anchor.isHigh ? anchor.time  : partner.time;
         datetime lT = anchor.isHigh ? partner.time : anchor.time;

         if((h - l) >= minLegSize)
           {
            highPrice = h;  lowPrice = l;
            highTime  = hT; lowTime  = lT;
            found     = true;
           }
         break; // pasangan TERDEKAT sudah ditemukan (lolos atau tidak) - jangan cari lebih jauh dari anchor ini
        }

      if(found)
         break; // leg TERBARU yang lolos sudah ditemukan - berhenti, prioritas recency
     }

   if(!found)
     {
      // FALLBACK: tidak ada leg terbaru yang cukup signifikan (pasar
      // sangat choppy) - pakai logika lama (terlebar dari window) sebagai
      // jaring pengaman, mencegah regresi ke bug "Zone: 0".
      int windowSize = MathMin(extCount, SMC_DEALING_RANGE_WINDOW);
      int startIdx   = extCount - windowSize;
      bool foundHigh = false, foundLow = false;

      for(int i = startIdx; i < extCount; i++)
        {
         SwingPoint sp;
         if(!GetExternalSwing(i, sp))
            continue;
         if(sp.isHigh)
           {
            if(!foundHigh || sp.price > highPrice) { highPrice = sp.price; highTime = sp.time; foundHigh = true; }
           }
         else
           {
            if(!foundLow || sp.price < lowPrice) { lowPrice = sp.price; lowTime = sp.time; foundLow = true; }
           }
        }
      found = foundHigh && foundLow;
     }

   if(!found)
     {
      g_dealingRange.isValid = false; // tidak ada swing berlawanan tipe ditemukan sama sekali
      return;
     }

   g_dealingRange.isValid  = true;
   g_dealingRange.high     = highPrice;
   g_dealingRange.low      = lowPrice;
   g_dealingRange.midpoint = (highPrice + lowPrice) / 2.0;

   // originDirection: mana yang terbentuk lebih DULU (waktu lebih awal)
   // menentukan arah leg - low duluan lalu high = leg naik (BULLISH),
   // high duluan lalu low = leg turun (BEARISH).
   if(lowTime < highTime)
     {
      g_dealingRange.originDirection = BIAS_BULLISH;
      g_dealingRange.time_start      = lowTime;
      g_dealingRange.time_end        = highTime;
     }
   else
     {
      g_dealingRange.originDirection = BIAS_BEARISH;
      g_dealingRange.time_start      = highTime;
      g_dealingRange.time_end        = lowTime;
     }

   ComputeOTEBand(g_dealingRange.originDirection, g_dealingRange.high, g_dealingRange.low,
                  g_dealingRange.oteBottom, g_dealingRange.oteTop);
  }

//======================================================================
// ACCESSOR - dipakai modul lain (Scoring, Narrative, Render)
//======================================================================
bool GetDealingRange(DealingRange &outRange)
  {
   if(!g_dealingRange.isValid)
      return false;
   outRange = g_dealingRange;
   return true;
  }

// Klasifikasi posisi sebuah harga di dalam dealing range aktif.
// `outPercent` = posisi harga dalam % dari low (0%) ke high (100%).
ENUM_PRICE_ZONE GetZoneForPrice(double price, double &outPercent)
  {
   outPercent = 0.0;

   if(!g_dealingRange.isValid)
      return PRICEZONE_OUT_OF_RANGE;

   double range = g_dealingRange.high - g_dealingRange.low;
   if(range <= 0)
      return PRICEZONE_OUT_OF_RANGE;

   if(price < g_dealingRange.low || price > g_dealingRange.high)
      return PRICEZONE_OUT_OF_RANGE;

   outPercent = ((price - g_dealingRange.low) / range) * 100.0;

   // Cek OTE dulu (paling spesifik), baru fallback ke klasifikasi umum.
   double oteLow  = MathMin(g_dealingRange.oteBottom, g_dealingRange.oteTop);
   double oteHigh = MathMax(g_dealingRange.oteBottom, g_dealingRange.oteTop);
   if(price >= oteLow && price <= oteHigh)
      return PRICEZONE_OTE;

   double eqTolerance = range * 0.02; // +-2% dianggap "di sekitar equilibrium"
   if(MathAbs(price - g_dealingRange.midpoint) <= eqTolerance)
      return PRICEZONE_EQUILIBRIUM;

   return (price < g_dealingRange.midpoint) ? PRICEZONE_DISCOUNT : PRICEZONE_PREMIUM;
  }

#endif // SMC_ZONES_MQH