//+------------------------------------------------------------------+
//|                                            SMC_SupplyDemand.mqh |
//|                                                                  |
//| MODUL "PAUS" - BARU, ditambahkan atas permintaan eksplisit.      |
//| Diubah, kenapa, dari mana:                                       |
//|   Deteksi pola Supply & Demand klasik (RBR/DBD/RBD/DBR) di       |
//|   PERIOD_H1 - SELALU H1, terlepas dari timeframe chart yang      |
//|   sedang dibuka (M1/M5/dst), persis seperti HTF bias (H4) yang   |
//|   sudah kita pakai sejak awal proyek. Tujuannya menangkap jejak  |
//|   "paus" (order institusi besar) yang biasanya lebih jelas di TF |
//|   lebih besar dibanding TF scalping (M1/M5).                     |
//|                                                                  |
//| BERDIRI SENDIRI - TIDAK MASUK SCORING: modul ini SENGAJA tidak   |
//| memengaruhi scoreTotal/Confluence/ENTRY_OK yang sudah ada. Ini   |
//| konsisten dengan prinsip proyek "jangan tambah faktor scoring    |
//| tanpa bukti data" (Stats yang menentukan kalibrasi, bukan        |
//| tebakan) - modul baru yang belum teruji tidak boleh mengganggu   |
//| sistem lama yang sudah jalan.                                    |
//|                                                                  |
//| BEDA DARI OrderBlock (SMC_POI.mqh): OB = 1 candle tunggal.       |
//| SDZone = LOW-HIGH gabungan SEMUA candle "base" (bisa 1-6 candle) |
//| - konsep S&D klasik, bukan konsep ICT Order Block.                |
//|                                                                  |
//| DESAIN DETEKSI: scan-ulang window bar (mirip pola DetectFVG di   |
//| SMC_POI.mqh) - BUKAN replay incremental seperti Structure. Base  |
//| H1 tidak butuh perlindungan look-ahead serumit itu karena        |
//| pola-nya murni dari candle yang SUDAH closed, dipindai ulang     |
//| tiap H1 bar baru (murah - H1 cuma ganti sekali per jam).         |
//+------------------------------------------------------------------+
#ifndef SMC_SUPPLYDEMAND_MQH
#define SMC_SUPPLYDEMAND_MQH

#include "..\Core\SMC_Types.mqh"
#include "..\Core\SMC_Config.mqh"
#include "..\Core\SMC_Utils.mqh"

//======================================================================
// STATE
//======================================================================
SDZone   g_sdZones[];
long     g_sdNextId = 1;
datetime g_sdLastScannedBarTime = 0; // dedup - jangan scan ulang kalau bar H1 belum ganti
bool     g_sdBackfilled = false;      // backfill sukses (histori TF zona sudah cukup)

//======================================================================
// INIT
//======================================================================
void SMC_SupplyDemand_Init()
  {
   ArrayFree(g_sdZones);
   g_sdNextId = 1;
   g_sdLastScannedBarTime = 0;
   g_sdBackfilled = false;
  }

//======================================================================
// HELPER: cek apakah candle di shift `s` termasuk "base" (badan kecil)
//======================================================================
bool IsBaseCandle(ENUM_TIMEFRAMES tf, int s, double avgBody)
  {
   double body = MathAbs(iClose(_Symbol, tf, s) - iOpen(_Symbol, tf, s));
   return (body <= avgBody * InpSDBaseBodyRatio);
  }

//======================================================================
// HELPER: cek apakah zona dengan baseStartTime ini SUDAH tercatat
// (dedup - scan ulang window akan menemukan base yang SAMA berkali-kali)
//======================================================================
bool IsSDZoneAlreadyRegistered(datetime baseStartTime)
  {
   for(int i = 0; i < ArraySize(g_sdZones); i++)
      if(g_sdZones[i].baseStartTime == baseStartTime)
         return true;
   return false;
  }

// Ukuran jendela leg (sebelum/sesudah base) - BEBERAPA candle beruntun,
// bukan 1 candle tunggal. Konstanta internal, bukan Config.mqh.
#define SMC_SD_LEG_WINDOW 3

//======================================================================
// HELPER: hitung total range + arah netto sebuah jendela candle
// beruntun (leg SEBELUM atau SESUDAH base).
//   towardPast=true  -> jendela mundur ke arah LAMA (leg SEBELUM base)
//   towardPast=false -> jendela maju ke arah BARU (leg SESUDAH base)
//======================================================================
bool GetLegStats(ENUM_TIMEFRAMES tf, int startShift, int windowSize, bool towardPast,
                  double &outSumRange, bool &outIsBullish)
  {
   int oldestShift, newestShift;
   if(towardPast)
     {
      oldestShift = startShift + windowSize - 1;
      newestShift = startShift;
     }
   else
     {
      oldestShift = startShift;
      newestShift = startShift - windowSize + 1;
      if(newestShift < 0)
         return false; // jendela keluar dari data yang ada (terlalu dekat ke bar sekarang)
     }

   outSumRange = 0.0;
   for(int s = newestShift; s <= oldestShift; s++)
      outSumRange += (iHigh(_Symbol, tf, s) - iLow(_Symbol, tf, s));

   double openAtOldest  = iOpen(_Symbol, tf, oldestShift);
   double closeAtNewest = iClose(_Symbol, tf, newestShift);
   outIsBullish = (closeAtNewest > openAtOldest); // arah NETTO seluruh jendela, bukan 1 candle

   return true;
  }

//======================================================================
// GoldPro (2 Okt 2026, research\paus_test.py): pola dinilai SEKALI, tepat
// saat candle ke-3 leg keluar CLOSE (n = shift candle leg keluar terbaru).
// Rata2 body/range = 20 candle s/d candle itu (shift n..n+19) -> live dan
// backfill (ganti TF / pasang ulang) menghasilkan zona yang SAMA.
// Kode lama memindai ulang 200 bar dgn rata2 SAAT INI: 71% zona H1 muncul
// TELAT (median 40 bar), 55% sudah tersentuh sebelum muncul, 6% memakai
// candle yang belum close; 19% "base" tidak pernah ditinggalkan leg keluar.
//======================================================================
bool TrySDPattern(ENUM_TIMEFRAMES tf, int n)
  {
   double avgBody  = GetAverageCandleBody(tf, 20, n);
   double avgRange = GetAverageRange(tf, 20, n);
   if(avgBody <= 0.0 || avgRange <= 0.0)
      return false; // data belum siap

   int i = n + SMC_SD_LEG_WINDOW - 1;  // candle leg keluar TERLAMA (shift i..n, semua sudah close)

   // Cari grup base MULAI dari shift (i+1) mundur ke belakang (lebih tua)
   int baseLen = 0;
   int j = i + 1;
   while(baseLen < InpSDMaxBaseCandles && IsBaseCandle(tf, j, avgBody))
     {
      baseLen++;
      j++;
     }
   if(baseLen < InpSDMinBaseCandles)
      return false;

   int baseNewestShift = i + 1;  // candle base paling BARU
   int baseOldestShift = j - 1;  // candle base paling LAMA
   datetime baseStartTime = iTime(_Symbol, tf, baseOldestShift);
   if(IsSDZoneAlreadyRegistered(baseStartTime))
      return false;

   // Leg MASUK (before) hanya untuk klasifikasi RBR/DBD/RBD/DBR; leg KELUAR
   // (after, jendela 3 candle) wajib impulsif.
   double beforeSumRange, afterSumRange;
   bool   beforeBullish, afterBullish;
   if(!GetLegStats(tf, j, SMC_SD_LEG_WINDOW, true, beforeSumRange, beforeBullish))
      return false;
   if(!GetLegStats(tf, i, SMC_SD_LEG_WINDOW, false, afterSumRange, afterBullish))
      return false;
   if(afterSumRange < avgRange * SMC_SD_LEG_WINDOW * InpSDImpulseRangeRatio)
      return false; // leg keluar tidak cukup kuat

   // Batas zona: LOW-HIGH gabungan SEMUA candle base
   double zoneHigh = -DBL_MAX, zoneLow = DBL_MAX;
   for(int k = baseNewestShift; k <= baseOldestShift; k++)
     {
      zoneHigh = MathMax(zoneHigh, iHigh(_Symbol, tf, k));
      zoneLow  = MathMin(zoneLow,  iLow(_Symbol, tf, k));
     }

   // Leg keluar wajib CLOSE di luar zona = base benar-benar ditinggalkan
   double legClose = iClose(_Symbol, tf, n);
   if(afterBullish ? (legClose <= zoneHigh) : (legClose >= zoneLow))
      return false;

   ENUM_SD_PATTERN pattern;
   bool isDemand;
   if(beforeBullish && afterBullish)       { pattern = SD_RBR; isDemand = true;  }
   else if(!beforeBullish && !afterBullish) { pattern = SD_DBD; isDemand = false; }
   else if(beforeBullish && !afterBullish)  { pattern = SD_RBD; isDemand = false; }
   else                                     { pattern = SD_DBR; isDemand = true;  }

   int nz = ArraySize(g_sdZones);
   ArrayResize(g_sdZones, nz + 1);
   g_sdZones[nz].id              = g_sdNextId++;
   g_sdZones[nz].high            = zoneHigh;
   g_sdZones[nz].low             = zoneLow;
   g_sdZones[nz].baseStartTime   = baseStartTime;
   g_sdZones[nz].baseEndTime     = iTime(_Symbol, tf, baseNewestShift);
   g_sdZones[nz].baseCandleCount = baseLen;
   g_sdZones[nz].pattern         = pattern;
   g_sdZones[nz].isDemand        = isDemand;
   g_sdZones[nz].status          = ZONE_FRESH;
   g_sdZones[nz].sourceTF_time   = iTime(_Symbol, tf, n) + PeriodSeconds(tf); // zona LAHIR (leg keluar selesai)
   return true;
  }

//======================================================================
// SCAN - backfill: semua posisi s/d InpSDScanBars, tua -> baru (pola lebih
// tua menang dedup, sama dgn urutan live). Live: 3 posisi terakhir saja
// (cadangan bila ada bar terlewat; dedup mencegah zona ganda).
//======================================================================
void ScanSupplyDemandZones(bool backfill)
  {
   ENUM_TIMEFRAMES tf = InpSDTimeframe;
   int totalBars = iBars(_Symbol, tf);
   int maxN = totalBars - InpSDMaxBaseCandles - 2 * SMC_SD_LEG_WINDOW - 25;
   if(maxN < 1)
      return; // histori belum cukup
   if(backfill)
      g_sdBackfilled = true;
   maxN = MathMin(maxN, backfill ? InpSDScanBars : SMC_SD_LEG_WINDOW);
   for(int n = maxN; n >= 1; n--)
      TrySDPattern(tf, n);
  }

//======================================================================
// STATUS - MITIGATED bila ada bar CLOSE yang menyentuh zona SETELAH zona
// lahir (sourceTF_time). Dicek dari histori (bukan cuma 1 candle terakhir)
// -> setelah ganti TF / pasang ulang status tetap benar. Kode lama: 78% zona
// yang tampil sesudah ganti TF sebenarnya sudah tersentuh, 41% di sisi salah
// harga (demand di atas harga). Bar dari TF chart (atau TF zona bila chart
// lebih besar). Sentuhan pertama = MITIGATED (tidak memodelkan kedalaman).
//======================================================================
bool SDTouchedSince(const SDZone &z)
  {
   ENUM_TIMEFRAMES ctf = (PeriodSeconds(PERIOD_CURRENT) <= PeriodSeconds(InpSDTimeframe)) ? PERIOD_CURRENT : InpSDTimeframe;
   int sh = iBarShift(_Symbol, ctf, z.sourceTF_time, false);
   if(sh < 0)
      return false;
   if(iTime(_Symbol, ctf, sh) < z.sourceTF_time)
      sh--;               // bar itu masih bagian leg keluar
   if(sh < 1)
      return false;       // belum ada bar CLOSE sejak zona lahir
   if(z.isDemand)
     {
      int k = iLowest(_Symbol, ctf, MODE_LOW, sh, 1);
      return (k >= 0 && iLow(_Symbol, ctf, k) <= z.high);
     }
   int k = iHighest(_Symbol, ctf, MODE_HIGH, sh, 1);
   return (k >= 0 && iHigh(_Symbol, ctf, k) >= z.low);
  }

void UpdateSDZoneStatus()
  {
   for(int i = 0; i < ArraySize(g_sdZones); i++)
     {
      if(g_sdZones[i].status == ZONE_MITIGATED || g_sdZones[i].status == ZONE_INVALIDATED)
         continue; // sudah selesai ceritanya - tidak perlu dicek lagi
      if(SDTouchedSince(g_sdZones[i]))
         g_sdZones[i].status = ZONE_MITIGATED;
     }
  }

//======================================================================
// FUNGSI UTAMA - backfill sekali di OnInit (diulang otomatis bila histori
// TF zona belum siap saat itu), live tiap bar baru di InpSDTimeframe.
// Status dicek tiap bar baru TF chart.
//======================================================================
void SMC_SupplyDemand_Update(bool isNewBarChart, bool isNewBarSD)
  {
   if(!InpEnableSupplyDemand)
      return;

   if(!g_sdBackfilled)
      ScanSupplyDemandZones(true);
   else if(isNewBarSD)
      ScanSupplyDemandZones(false);

   if(isNewBarChart || isNewBarSD)
      UpdateSDZoneStatus();
  }

void SMC_SupplyDemand_Backfill()
  {
   if(!InpEnableSupplyDemand)
      return;
   ScanSupplyDemandZones(true);
   UpdateSDZoneStatus();
  }

//======================================================================
// ACCESSOR
//======================================================================
int GetSDZoneCount() { return ArraySize(g_sdZones); }

bool GetSDZone(int index, SDZone &outZone)
  {
   if(index < 0 || index >= ArraySize(g_sdZones))
      return false;
   outZone = g_sdZones[index];
   return true;
  }

// Zona Supply/Demand FRESH terdekat dari harga, searah kebutuhan
// (Demand/Supply) - dipakai render & dashboard "Paus".
bool GetNearestSDZone(bool wantDemand, double referencePrice, SDZone &outZone)
  {
   bool   found    = false;
   double bestDist = DBL_MAX;

   for(int i = 0; i < ArraySize(g_sdZones); i++)
     {
      if(g_sdZones[i].isDemand != wantDemand)
         continue;
      if(g_sdZones[i].status == ZONE_MITIGATED || g_sdZones[i].status == ZONE_INVALIDATED)
         continue;

      double mid  = (g_sdZones[i].high + g_sdZones[i].low) / 2.0;
      double dist = MathAbs(referencePrice - mid);
      if(dist < bestDist)
        {
         bestDist = dist;
         outZone  = g_sdZones[i];
         found    = true;
        }
     }
   return found;
  }

string SDPatternToString(ENUM_SD_PATTERN p)
  {
   switch(p)
     {
      case SD_RBR: return "RBR";
      case SD_DBD: return "DBD";
      case SD_RBD: return "RBD";
      case SD_DBR: return "DBR";
     }
   return "?";
  }

#endif // SMC_SUPPLYDEMAND_MQH