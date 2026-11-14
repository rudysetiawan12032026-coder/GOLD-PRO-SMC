//+------------------------------------------------------------------+
//|                                          SMC_MultiTFEntry.mqh   |
//|                                                                  |
//| MODUL BARU - permintaan eksplisit: "2 titik entry, masing-masing |
//| punya karakter sendiri, tanpa harus melawan sinyal dan arus dari |
//| TF besar sebagai acuan utama."                                   |
//|                                                                  |
//| BEDA DARI SISTEM CONFLUENCE UTAMA (SMC_Scoring.mqh): sistem       |
//| utama SENGAJA mensyaratkan keselarasan HTF/MTF/LTF (itu Structure|
//| score, 30% bobot) - filosofinya "jangan lawan tren besar". Modul  |
//| ini SEBALIKNYA - tiap timeframe (M1, M5) dinilai BERDIRI SENDIRI, |
//| pakai struktur & zona miliknya sendiri, TANPA gate keselarasan    |
//| ke TF lain. Ini BUKAN pengganti Confluence - berdampingan sebagai |
//| sudut pandang tambahan ("kalau saya trading di TF ini saja, apa   |
//| kata strukturnya sendiri").                                       |
//|                                                                  |
//| DIBANGUN DARI BLOK YANG SUDAH ADA (bukan mesin baru):              |
//|   - CalculateStructuralBias() dari SMC_MTF.mqh (bias per-TF)       |
//|   - ScanSimpleZones() dari SMC_MTF.mqh (zona OB ringan per-TF)     |
//|   - GetATR()/InpSLBufferATRMultiplier untuk SL berbasis volatilitas |
//| Tambahan baru HANYA GetNearestSwingExtreme() (untuk target TP),    |
//| konsepnya sama dengan fractal swing di CalculateStructuralBias.     |
//+------------------------------------------------------------------+
#ifndef SMC_MULTITFENTRY_MQH
#define SMC_MULTITFENTRY_MQH

#include "..\Core\SMC_Types.mqh"
#include "..\Core\SMC_Config.mqh"
#include "..\Core\SMC_Utils.mqh"
#include "SMC_MTF.mqh"

struct MultiTFEntryInfo
  {
   bool      hasEntry;
   ENUM_BIAS bias;
   double    entry;
   double    sl;
   double    tp;
   double    riskReward;
  };

//======================================================================
// GetNearestSwingExtreme() - cari swing fractal TERDEKAT yang berada
// DI DEPAN referencePrice (searah target) - dipakai sebagai TP.
// Konsep SAMA dengan koleksi fractal di CalculateStructuralBias, tapi
// tujuannya beda: cari 1 titik target terdekat, bukan replay bias.
//======================================================================
bool GetNearestSwingExtreme(ENUM_TIMEFRAMES tf, bool wantHighExtreme, double referencePrice,
                             double &outPrice, int lookbackBars = 150, int fractalLookback = 3)
  {
   bool   found    = false;
   double bestDist = DBL_MAX;
   outPrice = 0.0;

   // FIX (bug ditemukan lewat backtest - 571 order ditolak broker
   // "Invalid stops", ratusan lainnya lolos tapi TP-nya nyaris tidak
   // berarti): dulu TIDAK ADA syarat jarak minimum - fractal TERDEKAT
   // apa adanya bisa cuma beberapa SEN dari referencePrice. Sekarang
   // wajib minimal sekian x ATR TF ini sendiri - target yang terlalu
   // dekat DIABAIKAN, terus cari yang lebih jauh.
   double atr = GetATR(tf, 14, 1);
   double minDist = (atr > 0) ? atr * 1.0 : 0.0;

   for(int p = fractalLookback + 1; p < lookbackBars; p++)
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

      if(wantHighExtreme && isFractalHigh && centerHigh > referencePrice + minDist)
        {
         double dist = centerHigh - referencePrice;
         if(dist < bestDist) { bestDist = dist; outPrice = centerHigh; found = true; }
        }
      if(!wantHighExtreme && isFractalLow && centerLow < referencePrice - minDist)
        {
         double dist = referencePrice - centerLow;
         if(dist < bestDist) { bestDist = dist; outPrice = centerLow; found = true; }
        }
     }
   return found;
  }

//======================================================================
// FUNGSI UTAMA - hitung entry/SL/TP untuk SATU timeframe, BERDIRI
// SENDIRI (tidak cek bias HTF/MTF/LTF sama sekali - sesuai permintaan).
//======================================================================
bool ComputeMultiTFEntry(ENUM_TIMEFRAMES tf, MultiTFEntryInfo &outInfo)
  {
   outInfo.hasEntry = false;
   outInfo.bias     = CalculateStructuralBias(tf);
   if(outInfo.bias == BIAS_NEUTRAL)
      return false; // TF ini sendiri belum punya arah jelas - jangan paksa entry

   bool wantBullish = (outInfo.bias == BIAS_BULLISH);

   OrderBlock zones[];
   ScanSimpleZones(tf, zones);

   double currentPrice = iClose(_Symbol, tf, 1);
   int    bestIdx  = -1;
   double bestDist = DBL_MAX;
   for(int i = 0; i < ArraySize(zones); i++)
     {
      if(zones[i].isBullish != wantBullish)
         continue;

      // FIX KONSEPTUAL (ditemukan dari pertanyaan user - sinyal BUY
      // muncul dengan Entry di ATAS harga, "bersebrangan" dengan candle
      // yang sedang berjalan): sebelumnya zona TERDEKAT dipilih TANPA
      // peduli posisinya di ATAS/BAWAH harga sekarang. Padahal secara
      // konsep, BUY yang benar itu MENUNGGU harga TURUN dulu ke suatu
      // level (pullback), baru naik lagi - bukan menuntut harga NAIK
      // duluan ke level yang sudah dilewati. Sekarang zona HANYA
      // dianggap kandidat kalau POSISINYA MASUK AKAL sebagai target
      // pullback: seluruh zona harus di BAWAH harga sekarang untuk BUY
      // (nunggu turun), atau di ATAS harga sekarang untuk SELL (nunggu
      // naik). Zona yang "ketinggalan" di sisi berlawanan (butuh
      // breakout, bukan pullback) SEKARANG DIABAIKAN di sini - bukan
      // lagi ditolak belakangan di Python.
      if(wantBullish && zones[i].high >= currentPrice)
         continue; // zona ini di atas/tumpang tindih harga - bukan target pullback yang valid untuk BUY
      if(!wantBullish && zones[i].low <= currentPrice)
         continue; // zona ini di bawah/tumpang tindih harga - bukan target pullback yang valid untuk SELL

      double mid  = (zones[i].high + zones[i].low) / 2.0;
      double dist = MathAbs(currentPrice - mid);
      if(dist < bestDist)
        {
         bestDist = dist;
         bestIdx  = i;
        }
     }
   if(bestIdx < 0)
      return false; // tidak ada zona pullback yang masuk akal searah bias TF ini - jangan paksa

   double entry = (zones[bestIdx].high + zones[bestIdx].low) / 2.0;

   // FIX (bug sama dengan SMC_POI.mqh - ditemukan lewat backtest):
   // buffer pip tetap menghasilkan jarak SL sekitar 5 sen untuk XAUUSD -
   // jauh di bawah noise normal. Ganti ke kelipatan ATR DARI TF INI
   // SENDIRI (bukan PERIOD_CURRENT chart) - supaya M1 dapat buffer
   // sesuai skala M1, M5 sesuai skala M5, bukan tercampur skala TF chart
   // yang sedang dibuka.
   double atr    = GetATR(tf, 14, 1);
   double buffer = (atr > 0) ? InpSLBufferATRMultiplier * atr : 0.0;
   double sl     = wantBullish ? zones[bestIdx].low  - buffer
                                : zones[bestIdx].high + buffer;

   double tp;
   if(!GetNearestSwingExtreme(tf, wantBullish, entry, tp))
      return false; // tidak ada target swing jelas - rekomendasi tidak lengkap, jangan setengah-setengah

   outInfo.hasEntry   = true;
   outInfo.entry      = entry;
   outInfo.sl         = sl;
   outInfo.tp         = tp;
   double riskPoints   = MathAbs(entry - sl);
   double rewardPoints = MathAbs(tp - entry);
   outInfo.riskReward  = (riskPoints > 0.0) ? rewardPoints / riskPoints : 0.0;

   return true;
  }

#endif // SMC_MULTITFENTRY_MQH