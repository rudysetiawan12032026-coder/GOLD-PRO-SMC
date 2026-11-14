//+------------------------------------------------------------------+
//|                                              GP_TouchTime.mqh    |
//| GoldPro (2 Okt 2026, research\pijakan_time.py, XAUUSD M1 2017-26) |
//| Peluang harga MENYENTUH sebuah level dalam T menit + perkiraan     |
//| rentang 60 menit ke depan.                                         |
//|   Model: gerak acak dengan RITME JAM. Varians per menit = ADR^2 x  |
//|   profil slot 30 mnt WITA (2017-21) x volK^2, volK = (realisasi    |
//|   120 mnt terakhir / profil)^0.5. sigma_T = 0.90 x akar(jumlah     |
//|   varians menit ke depan). P(sentuh jarak d dlm T) =               |
//|   2 x (1 - Phi(d / sigma_T)).                                      |
//|   Uji 2022-26 (tak dilihat saat memilih parameter): meleset rata2  |
//|   1.8 poin (maks 4.5), tiap tahun 1.3-2.5 poin.                    |
//|   Pijakan OB GoldPro: tersentuh -0.1..-1.2 poin dari prediksi ->   |
//|   OB BUKAN magnet & BUKAN dihindari: angka ini peluang harga        |
//|   DATANG, bukan peluang MEMANTUL (uji OB: pantulan = level acak).  |
//|   Rentang 60 mnt: median 1.44 x sigma60 (p20 0.70x, p80 1.46x),    |
//|   R2 log 42%.                                                      |
//+------------------------------------------------------------------+
#ifndef GP_TOUCHTIME_MQH
#define GP_TOUCHTIME_MQH

// Berdiri sendiri (tanpa GP_Time / SMC_Config) agar bisa dipakai indikator GoldPro DAN EA GoldPro_Panel.
// Jam server broker = UTC+2, ikut DST Amerika (UTC+3) - sama dgn default GoldPro (InpServerUTCWinter 2, ikut DST AS).
int TT_SundayOfMonth(int year, int month, int n)
  {
   MqlDateTime dt;
   ZeroMemory(dt);
   dt.year = year; dt.mon = month; dt.day = 1;
   TimeToStruct(StructToTime(dt), dt);
   return 1 + (7 - dt.day_of_week) % 7 + 7 * (n - 1);
  }
bool TT_IsUSDST(datetime utc)
  {
   MqlDateTime dt;
   TimeToStruct(utc, dt);
   MqlDateTime a, b;
   ZeroMemory(a); ZeroMemory(b);
   a.year = dt.year; a.mon = 3;  a.day = TT_SundayOfMonth(dt.year, 3, 2);  a.hour = 7;
   b.year = dt.year; b.mon = 11; b.day = TT_SundayOfMonth(dt.year, 11, 1); b.hour = 6;
   return utc >= StructToTime(a) && utc < StructToTime(b);
  }
datetime TT_ServerToUTC(datetime server) { return server - (TT_IsUSDST(server - 2 * 3600) ? 3 : 2) * 3600; }

// varians per menit (satuan ADR^2) per slot 30 menit WITA, 00:00 .. 23:30
const double TT_PROF[48] = {4.1631e-04, 3.2971e-04, 3.9535e-04, 2.8985e-04, 4.1221e-04, 3.4723e-04, 3.3078e-04, 2.6061e-04,
                            1.7907e-04, 1.9440e-04, 2.0161e-04, 1.3956e-04, 2.5364e-04, 1.7893e-04, 3.2551e-04, 1.8430e-04,
                            2.4559e-04, 1.9143e-04, 4.3842e-04, 2.5838e-04, 1.9831e-04, 1.5690e-04, 1.6649e-04, 1.0698e-04,
                            9.6711e-05, 9.9486e-05, 1.1916e-04, 2.1362e-04, 2.7027e-04, 2.5184e-04, 3.4582e-04, 2.9505e-04,
                            3.6056e-04, 2.6698e-04, 2.5132e-04, 2.3071e-04, 2.3817e-04, 2.2863e-04, 2.7390e-04, 3.3141e-04,
                            5.5335e-04, 8.7854e-04, 7.6016e-04, 1.0210e-03, 8.5678e-04, 7.8784e-04, 7.1214e-04, 5.0769e-04};
#define TT_K      0.90
#define TT_BETA   0.5
#define TT_RFAC   1.44
#define TT_MAXMIN 240      // horizon teruji maksimal (menit)

// KALIBRASI ULANG (3 Okt 2026, research\touch_calib.py): model mentah melebihkan jarak dekat ~3 poin & meremehkan jarak
// jauh (ekor gemuk). Pemetaan monoton p_mentah -> p (isotonic, latih 2017-21), 101 titik 0.00..1.00, interpolasi linear.
// Uji 2022-26: meleset rata2 1.82 -> 0.74 poin (maks 4.5 -> 1.9), logloss 0.4381 -> 0.4358, membaik 9/10 tahun.
const double TT_CAL[101] = {0.0000, 0.0296, 0.0392, 0.0498, 0.0577, 0.0641, 0.0704, 0.0866, 0.0945, 0.0958, 0.1057, 0.1210, 0.1250,
                            0.1295, 0.1410, 0.1480, 0.1564, 0.1653, 0.1740, 0.1830, 0.1871, 0.1992, 0.2085, 0.2130, 0.2269, 0.2366,
                            0.2374, 0.2471, 0.2523, 0.2697, 0.2769, 0.2841, 0.2896, 0.3105, 0.3110, 0.3201, 0.3348, 0.3383, 0.3576,
                            0.3576, 0.3742, 0.3780, 0.3815, 0.3815, 0.4022, 0.4126, 0.4314, 0.4314, 0.4446, 0.4578, 0.4588, 0.4723,
                            0.4907, 0.4930, 0.5117, 0.5242, 0.5278, 0.5358, 0.5426, 0.5506, 0.5689, 0.5744, 0.5794, 0.5999, 0.6005,
                            0.6145, 0.6308, 0.6403, 0.6459, 0.6513, 0.6711, 0.6804, 0.6939, 0.7042, 0.7146, 0.7233, 0.7376, 0.7437,
                            0.7555, 0.7733, 0.7774, 0.7904, 0.8062, 0.8133, 0.8230, 0.8299, 0.8439, 0.8565, 0.8673, 0.8787, 0.8846,
                            0.8931, 0.9099, 0.9231, 0.9305, 0.9429, 0.9515, 0.9642, 0.9853, 1.0000, 1.0000};

double TT_Cal(double p)
  {
   if(p <= 0.0) return 0.0;
   if(p >= 1.0) return 1.0;
   double x = p * 100.0;
   int i = (int)MathFloor(x);
   if(i >= 100) return TT_CAL[100];
   return TT_CAL[i] + (TT_CAL[i + 1] - TT_CAL[i]) * (x - i);
  }

double   g_ttAdr  = 0.0;   // ADR20 (rata2 range 20 candle D1 sebelum hari ini)
double   g_ttVolK = 1.0;   // koreksi volatilitas 120 mnt terakhir
datetime g_ttM1   = 0;
// diisi render SMC (garis Pijakan / Tujuan) agar panel GoldPro bisa menampilkannya
double   g_ttPijPrice = 0.0, g_ttTujPrice = 0.0;
string   g_ttPijName  = "",  g_ttTujName  = "";
//--- PDH / PDL: peluang DITEMBUS s/d tutup hari ini (diisi GDM::PdhlUpdate dari tabel live GoldPro: jarak & sisa jam, uji 2017-26
//    +-1.5 poin; dibaca label PDH/PDL). -1 = belum dihitung, 2 = sudah tertembus hari ini. g_pdCls = kekuatan hari kemarin.
double   g_pdhP = -1.0, g_pdlP = -1.0;
string   g_pdCls = "";

int TT_Slot(datetime server)
  {
   MqlDateTime s;
   TimeToStruct(TT_ServerToUTC(server) + 8 * 3600, s);   // profil dibuat dalam jam WITA (UTC+8)
   return s.hour * 2 + (s.min >= 30 ? 1 : 0);
  }

double TT_Phi(double x)   // distribusi normal kumulatif (Abramowitz-Stegun 26.2.17, galat < 1e-7)
  {
   double t = 1.0 / (1.0 + 0.2316419 * MathAbs(x));
   double d = 0.3989422804014327 * MathExp(-x * x / 2.0);
   double p = d * t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
   return (x >= 0) ? 1.0 - p : p;
  }

bool TT_MarketOpen()
  {
   datetime b = iTime(_Symbol, PERIOD_M1, 0);
   return (b > 0 && TimeTradeServer() - b < 15 * 60);
  }

// hitung ulang ADR & volK saat candle M1 baru; true = ada menit baru
bool TT_Update()
  {
   datetime m1 = iTime(_Symbol, PERIOD_M1, 0);
   if(m1 == 0 || (m1 == g_ttM1 && g_ttAdr > 0))
      return false;
   double sum = 0.0;
   int cnt = 0;
   for(int i = 1; i <= 20; i++)
     {
      double h = iHigh(_Symbol, PERIOD_D1, i), l = iLow(_Symbol, PERIOD_D1, i);
      if(h > 0.0 && l > 0.0) { sum += h - l; cnt++; }
     }
   if(cnt < 10)
      return false;
   g_ttAdr = sum / cnt;
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_M1, 1, 121, r);   // terlama -> terbaru
   double real = 0.0, prof = 0.0;
   int used = 0;
   for(int i = 1; i < n; i++)
     {
      if(r[i].time - r[i - 1].time != 60)
         continue;   // lompatan sesi / akhir pekan
      double x = (r[i].close - r[i - 1].close) / g_ttAdr;
      real += x * x;
      prof += TT_PROF[TT_Slot(r[i].time)];
      used++;
     }
   double rv = (prof > 0.0 && used >= 60) ? MathSqrt(real / prof) : 1.0;
   g_ttVolK = MathPow(MathMax(0.2, MathMin(5.0, rv)), TT_BETA);
   g_ttM1 = m1;
   return true;
  }

// simpangan (satuan ADR) gerak harga dalam `minutes` menit ke depan
double TT_Sigma(int minutes)
  {
   if(g_ttAdr <= 0.0 || minutes <= 0)
      return 0.0;
   datetime t0 = iTime(_Symbol, PERIOD_M1, 0);
   double v = 0.0;
   for(int i = 0; i < minutes; i++)
      v += TT_PROF[TT_Slot(t0 + i * 60)];
   return TT_K * MathSqrt(v) * g_ttVolK;
  }

// peluang harga menyentuh level berjarak `dist` ($) dalam `minutes` menit; -1 = tidak tersedia
double TT_P(double dist, int minutes)
  {
   double s = TT_Sigma(minutes);
   if(s <= 0.0)
      return -1.0;
   return TT_Cal(MathMax(0.0, MathMin(1.0, 2.0 * (1.0 - TT_Phi(MathAbs(dist) / g_ttAdr / s)))));
  }

// menit sampai peluang tersentuh mencapai 50%; -1 bila lebih dari 4 jam (di luar horizon teruji)
int TT_Min50(double dist)
  {
   if(g_ttAdr <= 0.0)
      return -1;
   datetime t0 = iTime(_Symbol, PERIOD_M1, 0);
   double d = MathAbs(dist) / g_ttAdr, v = 0.0;
   for(int i = 0; i < TT_MAXMIN; i++)
     {
      v += TT_PROF[TT_Slot(t0 + i * 60)];
      double s = TT_K * MathSqrt(v) * g_ttVolK;
      if(s > 0.0 && TT_Cal(2.0 * (1.0 - TT_Phi(d / s))) >= 0.5)
         return i + 1;
     }
   return -1;
  }

// rentang (high-low) 60 menit ke depan dalam $: median, p20, p80
bool TT_Range60(double &med, double &p20, double &p80)
  {
   double s = TT_Sigma(60);
   if(s <= 0.0)
      return false;
   med = TT_RFAC * s * g_ttAdr;
   p20 = med * 0.70;
   p80 = med * 1.46;
   return true;
  }

string TT_Pct(double p)
  {
   if(p < 0.0)    return "-";
   if(p < 0.005)  return "<1%";
   if(p > 0.995)  return ">99%";
   return StringFormat("%d%%", (int)MathRound(p * 100.0));
  }

string TT_MinTxt(int mins)
  {
   if(mins < 0)  return "> 4 jam";
   if(mins < 60) return StringFormat("~%d mnt", mins);
   return StringFormat("~%dj%02dm", mins / 60, mins % 60);
  }

// teks pendek untuk label di chart: "1j 61% 2j 75%"
string TT_Short(double dist)
  {
   if(!TT_MarketOpen() || g_ttAdr <= 0.0)
      return "";
   return StringFormat("1j %s 2j %s", TT_Pct(TT_P(dist, 60)), TT_Pct(TT_P(dist, 120)));
  }

// tooltip lengkap untuk level `price` bernama `name`
string TT_Tip(string name, double price, double bid)
  {
   if(!TT_MarketOpen() || g_ttAdr <= 0.0)
      return name + "\n(market tutup - peluang waktu tidak dihitung)";
   double dist = MathAbs(price - bid);
   return StringFormat("%s %s  (%s$%.2f dari harga)\nPeluang harga DATANG ke sini dalam:\n"
                       "15 mnt %s | 30 mnt %s | 1 jam %s | 2 jam %s | 4 jam %s\n"
                       "Peluang 50%% tercapai dalam %s\n"
                       "Model ritme jam + volatilitas 2 jam terakhir, terkalibrasi (uji 2022-26: meleset rata2 0.7 poin).\n"
                       "Ini peluang DATANG, bukan peluang MEMANTUL: uji 2017-26 OB/zona SMC\n"
                       "tidak memantulkan harga lebih sering dari level biasa.",
                       name, DoubleToString(price, _Digits), (price >= bid) ? "+" : "-", dist,
                       TT_Pct(TT_P(dist, 15)), TT_Pct(TT_P(dist, 30)), TT_Pct(TT_P(dist, 60)),
                       TT_Pct(TT_P(dist, 120)), TT_Pct(TT_P(dist, 240)), TT_MinTxt(TT_Min50(dist)));
  }

// jarak harga sekarang ke zona [lo, hi] ($); 0 = harga di dalam zona; edge = tepi terdekat
double TT_ZoneDist(double lo, double hi, double bid, double &edge)
  {
   if(lo > hi) { double t = lo; lo = hi; hi = t; }
   if(bid > hi) { edge = hi; return bid - hi; }
   if(bid < lo) { edge = lo; return lo - bid; }
   edge = bid;
   return 0.0;
  }

// akhiran label zona: " | 1j 45% 2j 62%" (full) / " | 1j 45%" atau " (harga di sini)"
string TT_ZoneText(double lo, double hi, bool full = true)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), edge;
   double d = TT_ZoneDist(lo, hi, bid, edge);
   if(d <= 0.0 && hi > lo)
      return " (harga di sini)";
   if(!TT_MarketOpen() || g_ttAdr <= 0.0)
      return "";
   return full ? " | " + TT_Short(d) : " | 1j " + TT_Pct(TT_P(d, 60));
  }

string TT_ZoneTip(string name, double lo, double hi)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), edge;
   double d = TT_ZoneDist(lo, hi, bid, edge);
   if(d <= 0.0 && hi > lo)
      return name + "\nHarga sedang DI DALAM zona ini.";
   return TT_Tip(name + " (tepi terdekat)", edge, bid);
  }

void TT_SetTip(string obj, string tip)
  {
   if(ObjectFind(0, obj) >= 0)
      ObjectSetString(0, obj, OBJPROP_TOOLTIP, tip);
  }

#endif // GP_TOUCHTIME_MQH
