//+------------------------------------------------------------------+
//|                                                   SMC_Utils.mqh |
//|                                                                  |
//| Fase 1 - File 3/24 : SMC Pro System                             |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Kumpulan fungsi utilitas generik yang dipakai berulang di     |
//|   banyak modul (Structure, POI, Liquidity, MarketCondition,     |
//|   Session, MTF). Menghindari duplikasi logic kecil yang sama    |
//|   ditulis ulang di banyak file.                                 |
//|                                                                  |
//| ATURAN KETAT UNTUK FILE INI:                                    |
//|   1. Semua fungsi WAJIB stateless dari sudut pandang pemanggil  |
//|      (tidak menyimpan hasil analisis SMC apapun) - kecuali      |
//|      internal cache teknis (ATR handle, last-bar-time) yang     |
//|      transparan bagi pemanggil.                                 |
//|   2. TIDAK ADA logic deteksi SMC (swing, OB, FVG, dst) di sini -|
//|      itu tugas file Detection/*.                                |
//+------------------------------------------------------------------+
#ifndef SMC_UTILS_MQH
#define SMC_UTILS_MQH

#include "SMC_Config.mqh"

//======================================================================
// SECTION 1: DETEKSI BAR BARU (multi-timeframe aware)
//   Dipakai oleh SMC_Main.mq5 (chart aktif) dan SMC_MTF.mqh (HTF/MTF)
//   supaya proses berat (deteksi ulang) hanya jalan saat benar-benar
//   ada bar baru di timeframe yang relevan, bukan tiap tick.
//======================================================================
#define SMC_MAX_TRACKED_TF 6
datetime g_lastBarTime[SMC_MAX_TRACKED_TF];
ENUM_TIMEFRAMES g_trackedTF[SMC_MAX_TRACKED_TF];
int g_trackedTFCount = 0;

int FindOrRegisterTFSlot(ENUM_TIMEFRAMES tf)
  {
   for(int i = 0; i < g_trackedTFCount; i++)
      if(g_trackedTF[i] == tf)
         return i;

   if(g_trackedTFCount >= SMC_MAX_TRACKED_TF)
     {
      Print("[SMC_Utils] ERROR: SMC_MAX_TRACKED_TF terlampaui. Tambah kapasitas array.");
      return -1;
     }

   g_trackedTF[g_trackedTFCount]   = tf;
   g_lastBarTime[g_trackedTFCount] = 0;
   g_trackedTFCount++;
   return g_trackedTFCount - 1;
  }

// Mengembalikan true HANYA pada tick pertama setelah bar baru terbentuk
// di timeframe `tf`. Aman dipanggil berulang tiap tick - efeknya sudah
// di-guard secara internal lewat cache g_lastBarTime.
bool IsNewBar(ENUM_TIMEFRAMES tf)
  {
   int slot = FindOrRegisterTFSlot(tf);
   if(slot < 0)
      return false;

   datetime currentBarTime = iTime(_Symbol, tf, 0);
   if(currentBarTime == 0)
      return false; // data belum siap (misal history belum ter-load penuh)

   if(currentBarTime != g_lastBarTime[slot])
     {
      g_lastBarTime[slot] = currentBarTime;
      return true;
     }
   return false;
  }

//======================================================================
// SECTION 2: ATR CACHE
//   Menghindari CreateHandle/CopyBuffer berulang untuk kombinasi
//   timeframe+period yang sama dari banyak modul berbeda.
//======================================================================
// FIX (bug ditemukan lewat log: "0 liquidity pool" + kemungkinan besar
// menjelaskan "0 FVG" yang berulang sejak awal proyek): GetATR() dulu
// bergantung pada handle iATR() + CopyBuffer() - MT5 punya quirk yang
// sudah dikenal luas: indikator yang BARU dibuat via iATR() belum tentu
// punya buffer terisi kalau langsung di-CopyBuffer dalam SATU siklus
// OnInit() yang sama (biasanya baru terisi di tick berikutnya). Karena
// SELURUH backfill (Structure, POI, Liquidity) berjalan sinkron di
// dalam OnInit() tanpa jeda tick, GetATR() bisa return 0 untuk SEMUA
// pemanggilan selama backfill - membuat guard "if(tolerance<=0)" atau
// "if(minSize<=0)" di modul lain (SMC_Liquidity.mqh, SMC_POI.mqh)
// selalu gagal diam-diam.
//
// FIX: hitung True Range MANUAL langsung dari iHigh/iLow/iClose - tidak
// butuh handle indikator apapun, sinkron, tidak ada "pemanasan" buffer.
// Handle-based GetOrCreateATRHandle() DIHAPUS total (bukan cuma
// dibiarkan tidak terpakai) - sesuai prinsip proyek "jangan biarkan
// kode mati tertinggal".
//======================================================================
// FIX PERMANEN (audit menyeluruh, temuan besar sesi ini): return value
// SEKARANG membedakan dua kondisi yang dulu SAMA-SAMA jadi 0.0 (ambigu):
//   -1.0  = GAGAL menghitung (data tidak tersedia di rentang shift ini) -
//           caller WAJIB treat ini sebagai "tidak valid", BUKAN "nol".
//    0.0  = secara teoritis nilai valid tapi degenerate (praktis nyaris
//           mustahil terjadi di data pasar sungguhan, tapi tetap
//           mungkin secara matematis kalau seluruh price flat).
// Ini menutup kelas bug "silent fail" yang sudah bikin salah diagnosa
// berbulan-bulan (ATR=0.0 dari kegagalan data VS ATR=0.0 dari
// perhitungan valid tidak bisa dibedakan caller sebelumnya).
double GetATR(ENUM_TIMEFRAMES tf, int period, int shift = 1)
  {
   if(period <= 0)
      return -1.0;

   double sumTR = 0.0;
   int counted = 0;

   for(int i = 0; i < period; i++)
     {
      int idx = shift + i;
      double high      = iHigh(_Symbol, tf, idx);
      double low       = iLow(_Symbol, tf, idx);
      double prevClose = iClose(_Symbol, tf, idx + 1);

      if(high == 0.0 && low == 0.0)
         continue; // data tidak tersedia di shift ini

      double tr = high - low;
      if(prevClose > 0.0)
        {
         tr = MathMax(tr, MathAbs(high - prevClose));
         tr = MathMax(tr, MathAbs(low - prevClose));
        }

      sumTR += tr;
      counted++;
     }

   if(counted == 0)
     {
      PrintFormat("[SMC_Utils] WARNING: GetATR() gagal - tidak ada bar valid untuk %s tf=%s period=%d shift=%d. "
                  "Kalau ini terjadi berulang, cek ketersediaan histori simbol/TF ini.",
                  _Symbol, EnumToString(tf), period, shift);
      return -1.0; // GAGAL - tidak ada satupun bar valid di rentang ini
     }

   return sumTR / counted;
  }

//======================================================================
// SECTION 3: ANALISIS CANDLE DASAR
//======================================================================

// True kalau candle di index `shift` (pada timeframe chart aktif secara
// default, atau timeframe manapun kalau di-pass) closing lebih tinggi
// dari open (bullish).
bool IsBullishCandle(int shift, ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
  {
   double o = iOpen(_Symbol, tf, shift);
   double c = iClose(_Symbol, tf, shift);
   return (c > o);
  }

// Rasio body terhadap range candle (0.0 - 1.0). Dipakai untuk validasi
// displacement (OB confirmation, BOS/CHoCH impulsif).
// Return 0.0 kalau range = 0 (candle doji ekstrem/data tidak valid).
double GetBodyToRangeRatio(int shift, ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
  {
   double o = iOpen(_Symbol, tf, shift);
   double c = iClose(_Symbol, tf, shift);
   double h = iHigh(_Symbol, tf, shift);
   double l = iLow(_Symbol, tf, shift);

   double range = h - l;
   if(range <= 0.0)
      return 0.0;

   return MathAbs(c - o) / range;
  }

//======================================================================
// SECTION 4: NORMALISASI HARGA / PIP
//   Penting untuk multi-pair (JPY pair beda digit dari mayor pair lain).
//======================================================================

// Mengembalikan ukuran 1 "pip" (bukan 1 point) untuk simbol aktif.
// Broker 5-digit: 1 pip = 10 point. Broker JPY 3-digit: 1 pip = 10 point juga
// (karena JPY quote 2 digit asli -> 3 digit broker). Deteksi otomatis
// dari jumlah digit simbol, bukan hardcode per currency.
double GetPipSize(string symbol = "")
  {
   if(symbol == "")
      symbol = _Symbol;

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

   // Broker dengan digit ganjil (3 atau 5) berarti ada 1 digit fraksional
   // tambahan dibanding pip tradisional -> pip = 10 x point.
   if(digits == 3 || digits == 5)
      return point * 10.0;

   return point;
  }

// Konversi jarak harga (misal untuk SL) ke satuan pip, untuk keperluan
// logging/narrative supaya angka yang ditampilkan mudah dibaca trader.
double PriceDistanceToPips(double priceDistance, string symbol = "")
  {
   double pip = GetPipSize(symbol);
   if(pip <= 0.0)
      return 0.0;
   return priceDistance / pip;
  }

// GoldPro: teks jarak untuk label. XAUUSD 2 digit -> GetPipSize() = $0.01, jadi "321 pips" dulu
// berarti $3.21 (trader emas umumnya membaca 1 pip = $0.10 -> terbaca 10x lebih jauh).
// Untuk logam ditulis dalam dolar, simbol lain tetap pips.
string DistanceText(double priceDistance)
  {
   if(StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "XAG") >= 0 || StringFind(_Symbol, "GOLD") >= 0)
      return StringFormat("$%.2f", priceDistance);
   return StringFormat("%.0f pips", PriceDistanceToPips(priceDistance));
  }

// Bulatkan harga ke jumlah digit yang benar untuk simbol - wajib dipakai
// sebelum menampilkan/menyimpan level harga apapun (OB, FVG, dsb) supaya
// tidak ada floating point noise (misal 1.234500000001).
double NormalizePriceForSymbol(double price, string symbol = "")
  {
   if(symbol == "")
      symbol = _Symbol;
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
  }

//======================================================================
// SECTION 5: WAKTU
//======================================================================

// Ekstrak jam (0-23) dari sebuah datetime, berbasis waktu server/broker
// (datetime MT5 secara default sudah dalam waktu server). Dipakai
// SMC_Session.mqh untuk klasifikasi killzone.
int GetBrokerHour(datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.hour;
  }

int GetBrokerMinute(datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.min;
  }

//======================================================================
// SECTION 6: ANALISIS CANDLE LANJUTAN (BARU - adopsi
// xxvw/SMC_ICT_Library, Fase 1). Disiapkan untuk validasi displacement
// yang lebih presisi di fase berikutnya - belum dipakai modul manapun.
//======================================================================

// Rata-rata body candle (|close-open|) selama `period` bar, dari `shift`.
double GetAverageCandleBody(ENUM_TIMEFRAMES tf, int period, int shift = 1)
  {
   if(period <= 0)
      return 0.0;

   double sum = 0.0;
   int counted = 0;
   for(int i = 0; i < period; i++)
     {
      double o = iOpen(_Symbol, tf, shift + i);
      double c = iClose(_Symbol, tf, shift + i);
      if(o == 0.0 && c == 0.0)
         continue; // data tidak tersedia di shift ini
      sum += MathAbs(c - o);
      counted++;
     }
   return (counted > 0) ? sum / counted : 0.0;
  }

// Rata-rata range candle (High-Low) selama `period` bar, dari `shift`.
double GetAverageRange(ENUM_TIMEFRAMES tf, int period, int shift = 1)
  {
   if(period <= 0)
      return 0.0;

   double sum = 0.0;
   int counted = 0;
   for(int i = 0; i < period; i++)
     {
      double h = iHigh(_Symbol, tf, shift + i);
      double l = iLow(_Symbol, tf, shift + i);
      if(h == 0.0 && l == 0.0)
         continue;
      sum += (h - l);
      counted++;
     }
   return (counted > 0) ? sum / counted : 0.0;
  }

// Upper wick: High - max(Open, Close)
double GetUpperWick(ENUM_TIMEFRAMES tf, int shift)
  {
   double h = iHigh(_Symbol, tf, shift);
   double o = iOpen(_Symbol, tf, shift);
   double c = iClose(_Symbol, tf, shift);
   return h - MathMax(o, c);
  }

// Lower wick: min(Open, Close) - Low
double GetLowerWick(ENUM_TIMEFRAMES tf, int shift)
  {
   double l = iLow(_Symbol, tf, shift);
   double o = iOpen(_Symbol, tf, shift);
   double c = iClose(_Symbol, tf, shift);
   return MathMin(o, c) - l;
  }

#endif // SMC_UTILS_MQH