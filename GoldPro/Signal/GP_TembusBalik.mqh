//+------------------------------------------------------------------+
//|                                               GP_TembusBalik.mqh |
//| GoldPro - TEMBUS BALIK DI JAM POSITIF (tombol "Tembus Balik",     |
//| 11 Okt 2026). Pengguna: "buatkan tombol baru yg merekap indikator |
//| itu, tampil di bawah chart lalu ditampilkan di dalam dashboard     |
//| sesuai jamnya, dan dikirim ke telegram".                           |
//| Riset XAUUSD M1 2017-2026 (research\peta_kotak.py, olah_positif.py,|
//| jam_positif.py, indikator_jam_positif.py, tbk_angka.py):           |
//|  - TEMBUS = candle M1 pertama close di luar dinding kotak sideway  |
//|    (mesin GP_BoxWatch). Tembusan jam 03-07 & 23 WITA lebih sering  |
//|    kembali ke tengah kotak dari acak (sebelum lanjut 0.5W: +5.4    |
//|    poin, 10/10 th; jam lain ~0).                                   |
//|  - aturan di dashboard = setelan terbaik dari 120 variasi:         |
//|    TARGET tengah kotak, BATAL 1W (lebar kotak) di luar dinding     |
//|    yang ditembus, s/d 4 jam.                                       |
//|  - PENYARING (indikator yang lolos pilih-periksa dua arah):        |
//|    LONJAKAN = volume tick M1 >= 2x rata2 60 candle ATAU            |
//|               ATR(5)/ATR(50) M1 >= 1.5                             |
//|    M5 BELUM IKUT = RSI(7) M5 < 50 utk tembus ATAS (> 50 BAWAH)     |
//|               ATAU kurva MACD(10,22,4) M5 masih melawan tembusan   |
//|    balik ke tengah sebelum batal s/d 4 jam (12.280 tembusan):      |
//|      LONJAKAN + M5 belum ikut 58.8% (acak 55.5%, 8/10 th)          |
//|      LONJAKAN saja 59.3% (56.9%) | M5 belum ikut saja 62.7% (62.2%)|
//|      tanpa keduanya 59.5% (61.9%, 1/10 th) = cenderung LANJUT       |
//|  - 10 mnt terakhir sebelum rollover (server 23:50-23:59): dilewati |
//|  - uang (lot 0.01, spread asli): 2017-25 ~impas / minus, 2026 +.   |
//| INFO + uji maju (MQL5\Files\GoldPro\tembus_balik.csv, chart utama),|
//| BUKAN sinyal. Modul ini tidak membuka order.                       |
//+------------------------------------------------------------------+
//| 12 Okt 2026 - JAM BAGUS (pengguna: "kumpulkan jam-jam bagus itu dan |
//| masukkan di dalam dashboard serta notif ke telegram"). Riset        |
//| research\colek_balik.py, tbk_rollover.py, gerak_rollover.py,        |
//| tbk_jam_bagus.py:                                                   |
//|  - broker XAUUSD tutup tiap hari server 23:55-01:00 (04:55-06:00    |
//|    WITA saat AS musim panas, 05:55-07:00 mulai 2 Nov 2026); 5 mnt   |
//|    pertama sesudah buka harga bid melompat (+$0.61 rata2, 10/10 th).|
//|  - KOREKSI angka di atas: per jam & arah, balik ke tengah s/d 4 jam |
//|    di 23 & 03-05 WITA SETARA / DI BAWAH acak.                       |
//|  - G1 JAM BAGUS: tembus BAWAH di jam pertama sesudah pasar buka     |
//|    (server 01:10-01:59; menit 00-09 dilewati, harga melompat) ->    |
//|    BELI balik ke tengah: 70% (acak 61; 2017-21 62.5 / 2022-26 76.9).|
//|    Menempel ke jam SERVER (kedua musim kuat di 2022-26). Uang lot   |
//|    0.01 (spread asli): -$0.31 / +$0.76 per posisi.                  |
//|  - G2 LEMAH: tembus ATAS 07 WITA -> JUAL balik 65% (acak 60; 63.3 / |
//|    66.2) tapi tidak stabil per musim -> dashboard saja, Telegram    |
//|    tetap pesan TBK biasa dengan keterangan LEMAH.                   |
//|  - Telegram G1: TBGJAM pengingat (server 01:10), TBG kandidat,      |
//|    TBGOK / TBGNO / TBGTO hasil (EA GoldPro_Telegram, saklar         |
//|    InpSendTbg). CSV uji maju: kolom jam_bagus G1 / G2.              |
//+------------------------------------------------------------------+
#ifndef GP_TEMBUSBALIK_MQH
#define GP_TEMBUSBALIK_MQH

input group "=== GoldPro: Tembus Balik (tombol Tembus Balik) ==="
input bool InpTBTelegram   = true;   // Kirim kandidat & hasil tembus-balik jam positif ke Telegram (lewat EA GoldPro_Telegram)
input bool InpTBStrip      = true;   // Strip rekap indikator di bawah chart saat tombol Tembus Balik aktif
input bool InpTBGoodRemind = true;   // Pengingat Telegram saat JAM BAGUS mulai (server 01:10 = 06:10 WITA; 07:10 mulai 2 Nov)

#define TB_PFX  "GPI_"
#define TB_MAX  30
#define TB_HOLD 240                                          // menit (batas waktu aturan)
#define TB_G1_P 70                                           // G1: balik ke tengah s/d 4 jam (tbk_jam_bagus.py, 534 tembusan)
#define TB_G1_A 61                                           //     acak (jarak) rata2
#define TB_G1_B 77                                           //     2022-26
#define TB_G2_P 65                                           // G2 LEMAH (1.361 tembusan)
#define TB_G2_A 60

int    TB_CAT_P[4] = {59, 59, 63, 60};                       // balik ke tengah sebelum batal s/d 4 jam (tbk_angka.py)
int    TB_CAT_G[4] = {56, 57, 62, 62};                       // acak (jarak) rata2 kategori itu
string TB_CAT_S[4] = {"L+B", "L", "B", "-"};
string TB_CAT_N[4] = {"LONJAKAN + M5 belum ikut", "LONJAKAN saja", "M5 belum ikut saja", "tanpa konfirmasi (cenderung lanjut)"};

struct TBEvent
  {
   datetime          t, rt;
   int               side, cat, res, hr;    // res 0 menunggu, 1 KENA tengah, 2 BATAL (lewat 1W), 3 HABIS 4 jam, 9 dilewati (rollover)
   int               good;                  // 0 jam positif biasa, 1 G1 JAM BAGUS, 2 G2 lemah (12 Okt)
   double            hi, lo, mid, sl, c, vol, atr, rsi7, ms, mx, px, acak;
   bool              lj, bi, ok5;
  };
TBEvent  g_tbEv[];
datetime g_tbNowM1 = 0;
double   g_tbNowVol = -1, g_tbNowAtr = -1, g_tbNowRsi = -1, g_tbNowMs = 0;
bool     g_tbNowOk5 = false;
int      g_tbCsvN = 0, g_tbCsvK = 0, g_tbCsvGN = 0, g_tbCsvGK = 0;   // semua / JAM BAGUS G1
double   g_tbCsvE = 0;
string   g_tbCsvFirst = "";
datetime g_tbCsvChk = 0;
string   g_tbL[], g_tbT[];
color    g_tbC[];

//--- jam positif (jam WITA candle tembus) & rollover
bool TB_PosHour(datetime server) { int h = KB_HourWITA(server); return h == 23 || (h >= 3 && h <= 7); }
bool TB_NearRoll(datetime server)
  {
   MqlDateTime d;
   TimeToStruct(server, d);
   return d.hour == 23 && d.min >= 50;
  }

//--- JAM BAGUS (12 Okt): G1 = tembus BAWAH server 01:10-01:59 (jam pertama sesudah pasar buka), G2 lemah = tembus ATAS 07 WITA
int TB_Good(datetime server, int side)
  {
   MqlDateTime d;
   TimeToStruct(server, d);
   if(side < 0 && d.hour == 1 && d.min >= 10) return 1;
   if(side > 0 && KB_HourWITA(server) == 7) return 2;
   return 0;
  }
int TB_EvP(const TBEvent &e) { return e.good == 1 ? TB_G1_P : (e.good == 2 ? TB_G2_P : TB_CAT_P[e.cat]); }   // YAKIN yang ditampilkan
string TB_EvS(const TBEvent &e) { return e.good == 1 ? "JB" : (e.good == 2 ? "JB-lemah" : TB_CAT_S[e.cat]); }
//--- awal jendela G1 (server 01:10) yang sedang berjalan / berikutnya; Sabtu-Minggu dilewati (pasar buka Senin 01:00 server)
datetime TB_G1Start(datetime now)
  {
   MqlDateTime d;
   TimeToStruct(now, d);
   d.hour = 1; d.min = 10; d.sec = 0;
   datetime t = StructToTime(d);
   if(now >= t + 50 * 60) t += 86400;
   for(int k = 0; k < 3; k++)
     {
      MqlDateTime x;
      TimeToStruct(t, x);
      if(x.day_of_week == 6 || x.day_of_week == 0) t += 86400; else break;
     }
   return t;
  }
string TB_GoodStatus(color &c)
  {
   datetime now = TimeTradeServer(), g = TB_G1Start(now);
   if(now >= g && now < g + 50 * 60)
     {
      c = clrLime;
      return StringFormat("JAM BAGUS SEKARANG s/d %s: tunggu tembus BAWAH", GP_LocalTime(g + 49 * 60));
     }
   int m = (int)((g - now) / 60);
   c = clrGold;
   return StringFormat("jam bagus berikut %s WITA (%dj %02dm)", GP_LocalTime(g), m / 60, m % 60);
  }

//--- volume relatif & ATR5/ATR50 candle M1 r[i] (sama dengan riset: rata2 termasuk candle ini)
void TB_M1(const MqlRates &r[], int i, double &vol, double &atr)
  {
   vol = -1; atr = -1;
   if(i < 59) return;
   double sv = 0;
   for(int j = i - 59; j <= i; j++) sv += (double)r[j].tick_volume;
   vol = (double)r[i].tick_volume / MathMax(sv / 60.0, 1.0);
   double a5 = 0, a50 = 0;
   for(int j = i - 49; j <= i; j++)
     {
      double tr = MathMax(r[j].high - r[j].low, MathMax(MathAbs(r[j].high - r[j - 1].close), MathAbs(r[j].low - r[j - 1].close)));
      a50 += tr;
      if(j > i - 5) a5 += tr;
     }
   atr = (a50 > 0) ? (a5 / 5.0) / (a50 / 50.0) : -1;
  }

//--- RSI(7) & kemiringan kurva MACD(10,22,4) pada candle M5 TUTUP terakhir saat candle M1 t tutup (t = jam buka candle M1).
//    Dihitung sendiri dari close M5 (300 candle pemanasan): sama di putar ulang & live, tidak menunggu handle indikator.
bool TB_M5(datetime t, double &rsi7, double &ms)
  {
   rsi7 = -1; ms = 0;
   datetime m5 = (datetime)(((long)(t + 60) / 300) * 300 - 300);
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_M5, m5 - 300 * 299, m5, r);
   if(n < 80) return false;
   while(n > 0 && r[n - 1].time > m5) n--;
   if(n < 80) return false;
   double ap = 0, an = 0;
   for(int k = 1; k <= 7; k++)
     {
      double d = r[k].close - r[k - 1].close;
      if(d > 0) ap += d; else an -= d;
     }
   ap /= 7.0; an /= 7.0;
   for(int k = 8; k < n; k++)
     {
      double d = r[k].close - r[k - 1].close;
      ap = (ap * 6.0 + (d > 0 ? d : 0)) / 7.0;
      an = (an * 6.0 + (d < 0 ? -d : 0)) / 7.0;
     }
   rsi7 = (an <= 0) ? 100.0 : 100.0 - 100.0 / (1.0 + ap / an);
   double e10 = r[0].close, e22 = r[0].close, mPrev = 0, mNow = 0;
   for(int k = 1; k < n; k++)
     {
      e10 += (2.0 / 11.0) * (r[k].close - e10);
      e22 += (2.0 / 23.0) * (r[k].close - e22);
      mPrev = mNow; mNow = e10 - e22;
     }
   ms = mNow - mPrev;
   return true;
  }

int TB_Add(const TBEvent &e)
  {
   int n = ArraySize(g_tbEv);
   if(n >= TB_MAX)
     {
      int drop = -1;
      for(int i = 0; i < n && drop < 0; i++) if(g_tbEv[i].res != 0) drop = i;   // buang yang sudah selesai paling lama
      if(drop < 0) drop = 0;
      for(int i = drop + 1; i < n; i++) g_tbEv[i - 1] = g_tbEv[i];
      n--;
     }
   ArrayResize(g_tbEv, n + 1);
   g_tbEv[n] = e;
   return n;
  }

string TB_Side(int s) { return s > 0 ? "ATAS" : "BAWAH"; }
string TB_YaTidak(bool b) { return b ? "YA" : "tidak"; }
string TB_M5Txt(const TBEvent &e)
  {
   if(!e.ok5) return "M5 belum terbaca";
   return StringFormat("RSI7 M5 %.0f, MACD M5 %s", e.rsi7, e.ms > 0 ? "naik" : "turun");
  }

//--- dipanggil GP_BoxWatch tepat saat TEMBUS (candle M1 close di luar dinding, termasuk loncat dari sisi seberang)
void TB_Break(const MqlRates &r[], int i, int side, double hi, double lo)
  {
   datetime t = r[i].time;
   if(!TB_PosHour(t) || hi <= lo) return;
   TBEvent e;
   e.t = t; e.rt = 0; e.side = side; e.res = 0; e.hr = KB_HourWITA(t);
   e.hi = hi; e.lo = lo; e.mid = (hi + lo) / 2.0;
   double w = hi - lo, wall = (side > 0) ? hi : lo;
   e.sl = wall + side * w; e.c = r[i].close; e.mx = (side > 0) ? r[i].high - hi : lo - r[i].low; e.px = 0;
   TB_M1(r, i, e.vol, e.atr);
   e.ok5 = TB_M5(t, e.rsi7, e.ms);
   e.lj = (e.vol >= 2.0) || (e.atr >= 1.5);
   e.bi = e.ok5 && ((side > 0) ? (e.rsi7 < 50 || e.ms < 0) : (e.rsi7 > 50 || e.ms > 0));
   e.cat = e.lj ? (e.bi ? 0 : 1) : (e.bi ? 2 : 3);
   double dT = (side > 0) ? e.c - e.mid : e.mid - e.c, dA = (side > 0) ? e.sl - e.c : e.c - e.sl;
   e.acak = (dT > 0 && dA > 0) ? dA / (dA + dT) : -1;
   e.good = TB_Good(t, side);
   if(TB_NearRoll(t)) e.res = 9;
   TB_Add(e);
   if(e.res == 9 || !InpTBTelegram) return;
   if(e.good == 1)                                                        // JAM BAGUS (format ringkas: jam : kejadian / TARGET / YAKIN)
     {
      string g = StringFormat("%s WITA : TEMBUS BAWAH kotak %s - %s (JAM BAGUS: jam pertama sesudah pasar buka)", GP_LocalTime(t),
                              KB_Px(lo), KB_Px(hi));
      g += StringFormat("^TARGET tengah %s (BELI balik, +$%.2f) s/d %s | BATAL %s (-$%.2f)", KB_Px(e.mid), MathAbs(e.mid - e.c),
                        GP_LocalTime(t + TB_HOLD * 60), KB_Px(e.sl), MathAbs(e.c - e.sl));
      g += StringFormat("^YAKIN %d%% s/d 4 jam (acak %d%%; 2022-26 %d%%) | LONJAKAN %s, M5 belum ikut %s | INFO, bukan sinyal",
                        TB_G1_P, TB_G1_A, TB_G1_B, TB_YaTidak(e.lj), TB_YaTidak(e.bi));
      KB_Out(t, "TBG", g);
      return;
     }
   string s = StringFormat("%s TEMBUS %s (jam positif) | LONJAKAN %s (vol %.1fx, ATR5/50 %.1f) | M5 belum ikut %s (%s)", GP_LocalTime(t),
                           TB_Side(side), TB_YaTidak(e.lj), e.vol, e.atr, TB_YaTidak(e.bi), TB_M5Txt(e));
   s += StringFormat("^-> kandidat BALIK ke tengah %s ($%.2f) s/d %s, batal %s %s ($%.2f)", KB_Px(e.mid), MathAbs(e.c - e.mid),
                     GP_LocalTime(t + TB_HOLD * 60), side > 0 ? "di atas" : "di bawah", KB_Px(e.sl), MathAbs(e.sl - e.c));
   if(e.good == 2)
      s += StringFormat("^JAM BAGUS LEMAH: tembus ATAS 07 WITA balik %d%% (acak %d%%), tidak stabil per musim. INFO, bukan sinyal",
                        TB_G2_P, TB_G2_A);
   else
      s += StringFormat("^Uji 2017-26 %s: balik %d%% (acak %d%%)%s.%s INFO, bukan sinyal", TB_CAT_N[e.cat], TB_CAT_P[e.cat],
                        TB_CAT_G[e.cat], e.cat == 3 ? " - tembusan tanpa konfirmasi lebih sering LANJUT" : "",
                        (e.hr == 23 || (e.hr >= 3 && e.hr <= 5)) ? " Jam ini setara acak (uji 12 Okt)." : "");
   KB_Out(t, "TBK", s);
  }

//--- catat hasil ke CSV uji maju (chart utama saja; kunci naik di GlobalVariable -> putar ulang / beberapa chart tidak dobel)
void TB_Log(const TBEvent &x)
  {
   if(!g_gpMaster || MQLInfoInteger(MQL_TESTER)) return;
   double key = (double)x.rt * 100000.0 + (double)((x.t / 60) % 10000) * 10.0 + (x.side > 0 ? 1 : 2);
   string gv = "GP_TBJ_KEY";
   if(GlobalVariableCheck(gv) && key <= GlobalVariableGet(gv)) return;
   FolderCreate("GoldPro");
   string fn = "GoldPro\\tembus_balik.csv";
   bool isNew = !FileIsExist(fn);
   int fh = FileOpen(fn, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ, ';');
   if(fh == INVALID_HANDLE) return;
   FileSeek(fh, 0, SEEK_END);
   if(isNew)
      FileWrite(fh, "dibuat_wita", "sisi", "jam_wita", "kategori", "vol_x", "atr5_50", "rsi7_m5", "macd_m5", "lonjakan", "m5_belum_ikut",
                "close", "tengah_target", "batal_1W", "yakin_pct", "acak_pct", "hasil", "waktu_hasil_wita", "menit", "maks_lewat", "sumber",
                "jam_bagus");
   string hs = (x.res == 1) ? "KENA" : (x.res == 2 ? "BATAL" : "HABIS");
   FileWrite(fh, KB_WitaFull(x.t), TB_Side(x.side), x.hr, TB_CAT_S[x.cat], DoubleToString(x.vol, 2), DoubleToString(x.atr, 2),
             x.ok5 ? DoubleToString(x.rsi7, 1) : "", x.ok5 ? (x.ms > 0 ? "naik" : "turun") : "", x.lj ? 1 : 0, x.bi ? 1 : 0,
             DoubleToString(x.c, 2), DoubleToString(x.mid, 2), DoubleToString(x.sl, 2), TB_EvP(x),
             x.acak >= 0 ? (int)MathRound(100 * x.acak) : -1, hs, KB_WitaFull(x.rt), (int)((x.rt - x.t) / 60), DoubleToString(x.mx, 2),
             g_kbLive ? "live" : "putar-ulang", x.good == 1 ? "G1" : (x.good == 2 ? "G2" : "-"));
   FileClose(fh);
   GlobalVariableSet(gv, key);
   g_tbCsvChk = 0;                                                        // dashboard: hitung ulang ringkasan uji maju
  }

//--- tiap candle M1 yang close (dipanggil GP_BoxWatch, juga saat kotak sudah selesai): KENA / BATAL / HABIS
void TB_Bar(datetime t, double h, double l, double c)
  {
   for(int k = 0; k < ArraySize(g_tbEv); k++)
     {
      if(g_tbEv[k].res != 0 || t <= g_tbEv[k].t) continue;
      int s = g_tbEv[k].side;
      g_tbEv[k].mx = MathMax(g_tbEv[k].mx, (s > 0) ? h - g_tbEv[k].hi : g_tbEv[k].lo - l);
      bool slh = (s > 0) ? h >= g_tbEv[k].sl : l <= g_tbEv[k].sl;
      bool tph = (s > 0) ? l <= g_tbEv[k].mid : h >= g_tbEv[k].mid;
      int r = slh ? 2 : (tph ? 1 : ((t >= g_tbEv[k].t + TB_HOLD * 60) ? 3 : 0));   // candle sama -> BATAL dulu (= riset)
      if(r == 0) continue;
      g_tbEv[k].res = r; g_tbEv[k].rt = t;
      g_tbEv[k].px = (r == 1) ? g_tbEv[k].mid : (r == 2 ? g_tbEv[k].sl : c);
      TB_Log(g_tbEv[k]);
      if(!InpTBTelegram) continue;
      TBEvent x = g_tbEv[k];
      int mins = (int)((t - x.t) / 60);
      if(x.good == 1)                                                     // JAM BAGUS: tag TBG*
        {
         string g;
         if(r == 1)      g = StringFormat("KENA %s WITA: JAM BAGUS tembus BAWAH %s BALIK ke tengah %s (%d mnt, sempat lewat dinding $%.2f)",
                                          GP_LocalTime(t), GP_LocalTime(x.t), KB_Px(x.mid), mins, MathMax(0.0, x.mx));
         else if(r == 2) g = StringFormat("BATAL %s WITA: JAM BAGUS tembus BAWAH %s LANJUT turun lewat %s (1W) dalam %d mnt",
                                          GP_LocalTime(t), GP_LocalTime(x.t), KB_Px(x.sl), mins);
         else            g = StringFormat("HABIS 4 jam: JAM BAGUS tembus BAWAH %s belum ke tengah / batal (close %s)", GP_LocalTime(x.t), KB_Px(c));
         KB_Out(t, r == 1 ? "TBGOK" : (r == 2 ? "TBGNO" : "TBGTO"), g + StringFormat(" | yakin %d%% (acak %d%%)", TB_G1_P, TB_G1_A));
         continue;
        }
      string s1;
      if(r == 1)
         s1 = StringFormat("KENA %s: tembus %s %s BALIK ke tengah %s (%d mnt, sempat lewat dinding $%.2f) | %s %d%%", GP_LocalTime(t),
                           TB_Side(s), GP_LocalTime(x.t), KB_Px(x.mid), mins, MathMax(0.0, x.mx), TB_EvS(x), TB_EvP(x));
      else if(r == 2)
         s1 = StringFormat("BATAL %s: tembus %s %s LANJUT lewat %s (1W) dalam %d mnt - tidak balik | %s %d%%", GP_LocalTime(t),
                           TB_Side(s), GP_LocalTime(x.t), KB_Px(x.sl), mins, TB_EvS(x), TB_EvP(x));
      else
         s1 = StringFormat("HABIS 4 jam: tembus %s %s belum ke tengah / batal (close %s) | %s %d%%", TB_Side(s), GP_LocalTime(x.t),
                           KB_Px(c), TB_EvS(x), TB_EvP(x));
      KB_Out(t, r == 1 ? "TBKOK" : (r == 2 ? "TBKNO" : "TBKTO"), s1);
     }
  }

void TB_Reset() { ArrayResize(g_tbEv, 0); }

//--- ringkasan uji maju dari CSV (tiap 60 dtk / sesudah baris baru)
void TB_CsvStats()
  {
   if(g_tbCsvChk != 0 && TimeLocal() - g_tbCsvChk < 60) return;
   g_tbCsvChk = TimeLocal();
   g_tbCsvN = 0; g_tbCsvK = 0; g_tbCsvE = 0; g_tbCsvFirst = ""; g_tbCsvGN = 0; g_tbCsvGK = 0;
   string fn = "GoldPro\\tembus_balik.csv";
   if(!FileIsExist(fn)) return;
   int fh = FileOpen(fn, FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE) return;
   bool head = true;
   while(!FileIsEnding(fh))
     {
      string ln = FileReadString(fh);
      if(head) { head = false; continue; }
      string a[];
      if(StringSplit(ln, ';', a) < 16) continue;
      g_tbCsvN++;
      if(a[15] == "KENA") g_tbCsvK++;
      g_tbCsvE += StringToDouble(a[13]) / 100.0;
      if(g_tbCsvFirst == "") g_tbCsvFirst = StringSubstr(a[0], 8, 2) + "/" + StringSubstr(a[0], 5, 2);
      if(ArraySize(a) > 20 && a[20] == "G1") { g_tbCsvGN++; if(a[15] == "KENA") g_tbCsvGK++; }
     }
   FileClose(fh);
  }

//--- rekap indikator SEKARANG (candle M1 & M5 terakhir yang sudah tutup)
void TB_RecapNow()
  {
   datetime last = iTime(_Symbol, PERIOD_M1, 1);
   if(last == 0 || last == g_tbNowM1) return;
   MqlRates r[];
   if(CopyRates(_Symbol, PERIOD_M1, 1, 60, r) < 60) return;
   TB_M1(r, 59, g_tbNowVol, g_tbNowAtr);
   g_tbNowOk5 = TB_M5(last, g_tbNowRsi, g_tbNowMs);
   g_tbNowM1 = last;
  }

//--- status jam: dalam jam positif? / jam positif berikutnya (jam WITA)
string TB_HourStatus(color &c)
  {
   datetime now = TimeTradeServer();
   MqlDateTime w;
   TimeToStruct(GP_UTCToLocal(GP_ServerToUTC(now)), w);
   datetime lt = (datetime)SymbolInfoInteger(_Symbol, SYMBOL_TIME);  // tick terakhir (11 Okt: akhir pekan dulu tertulis "JAM POSITIF")
   MqlDateTime sv;
   TimeToStruct(now, sv);
   bool brk = (sv.hour == 0 && sv.day_of_week >= 1 && sv.day_of_week <= 5) ||          // 12 Okt: jeda harian broker server 23:55-01:00
              (sv.hour == 23 && sv.min >= 55 && sv.day_of_week >= 1 && sv.day_of_week <= 4);   // (Jumat 23:55 = tutup akhir pekan)
   if(brk)
     {
      c = clrSilver;
      datetime op = (sv.hour == 0) ? now - sv.min * 60 - sv.sec + 3600 : now - sv.min * 60 - sv.sec + 7200;
      return StringFormat("PASAR TUTUP (jeda harian) | buka %s WITA", GP_LocalTime(op));
     }
   if(lt > 0 && now - lt > 600) { c = clrSilver; return "MARKET TUTUP | jam positif 23 & 03-07 WITA"; }
   if(TB_NearRoll(now)) { c = clrOrange; return "10 mnt sebelum rollover: tembusan dilewati"; }
   if(w.hour == 23 || (w.hour >= 3 && w.hour <= 7))
     {
      c = clrLime;
      return StringFormat("JAM POSITIF sekarang (s/d %s WITA)", w.hour == 23 ? "23:59" : "07:59");
     }
   int k = 1;
   while(k < 24) { int h = (w.hour + k) % 24; if(h == 23 || (h >= 3 && h <= 7)) break; k++; }
   int mins = k * 60 - w.min, nh = (w.hour + k) % 24;
   c = clrSilver;
   return StringFormat("jam biasa | positif berikut %02d:00 WITA (%dj %02dm)", nh, mins / 60, mins % 60);
  }

string TB_LjTxt(double vol, double atr) { return (vol >= 2.0 || atr >= 1.5) ? "YA" : "belum"; }

//--- dashboard ringkas (feedback 8 Okt: jam : kejadian / TARGET / YAKIN %, daftar hasil)
void TB_Line(string s, color c, string tip = "")
  {
   int n = ArraySize(g_tbL);
   ArrayResize(g_tbL, n + 1); ArrayResize(g_tbC, n + 1); ArrayResize(g_tbT, n + 1);
   g_tbL[n] = StringSubstr(s, 0, KB_MAXCH); g_tbC[n] = c; g_tbT[n] = tip;
  }
void TB_BuildLines()
  {
   ArrayResize(g_tbL, 0); ArrayResize(g_tbC, 0); ArrayResize(g_tbT, 0);
   string tip = "TEMBUS BALIK: tembusan kotak sideway (candle M1 pertama close di luar dinding) di jam 23 & 03-07 WITA\n"
                "lebih sering KEMBALI ke tengah kotak dari acak (uji XAUUSD 2017-26, 10/10 th). Aturan: TARGET tengah kotak,\n"
                "BATAL 1W (lebar kotak) di luar dinding, s/d 4 jam. Penyaring: LONJAKAN (volume M1 >= 2x rata2 60 candle atau\n"
                "ATR5/ATR50 M1 >= 1.5) & M5 BELUM IKUT (RSI7 M5 < 50 utk tembus atas / > 50 bawah, atau kurva MACD 10,22,4 M5\n"
                "masih melawan). Balik s/d 4 jam: L+B 59% (acak 56), L 59 (57), B 63 (62), tanpa 60 (62 = cenderung lanjut).\n"
                "Per jam: 23 58% (acak 61) | 03 59 (62) | 04 59 (62) | 05 57 (62) | 06 66 (60) | 07 64 (60).\n"
                "Uang lot 0.01 (spread asli): 2017-25 ~impas / minus, 2026 +. INFO + uji maju, bukan sinyal; tidak membuka order.";
   string tipG = "JAM BAGUS (uji 12 Okt, XAUUSD 2017-26, per jam & arah, aturan sama: TARGET tengah, BATAL 1W, s/d 4 jam):\n"
                 "* G1 = tembus BAWAH di jam pertama sesudah pasar buka (server 01:10-01:59 = 06:10-06:59 WITA saat AS musim panas,\n"
                 "  07:10-07:59 mulai 2 Nov) -> BELI balik ke tengah: 70% (acak 61; 2017-21 62.5% / 2022-26 76.9%), kuat di kedua musim.\n"
                 "  Uang lot 0.01 spread asli: 2017-21 -$0.31 / 2022-26 +$0.76 per posisi. Menit 00-09 sesudah buka dilewati (harga melompat).\n"
                 "~ G2 LEMAH = tembus ATAS 07 WITA -> JUAL balik 65% (acak 60), tidak stabil per musim (Telegram pesan biasa).\n"
                 "Jam 23 & 03-05 WITA: balik setara / di bawah acak. Pasar broker tutup tiap hari server 23:55-01:00.\n"
                 "Telegram: pengingat jam bagus mulai + kandidat + hasil (bintang). INFO + uji maju, bukan sinyal.";
   TB_Line("TEMBUS BALIK - jam bagus * + jam positif", clrWhite, tip);
   color hc;
   string hs = TB_HourStatus(hc);
   TB_Line(hs, hc, tip);
   datetime g1 = TB_G1Start(TimeTradeServer());
   TB_Line(StringFormat("* JAM BAGUS %s-%s tembus BAWAH->BELI %d%% (acak %d)", GP_LocalTime(g1), GP_LocalTime(g1 + 49 * 60), TB_G1_P,
                        TB_G1_A), clrGold, tipG);
   color gc;
   string gs = TB_GoodStatus(gc);
   TB_Line("  " + gs, gc, tipG);
   TB_Line(StringFormat("~ lemah 07:00-07:59 tembus ATAS->JUAL %d%% (acak %d)", TB_G2_P, TB_G2_A), clrSilver, tipG);
   TB_Line("  jam 23 & 03-05: setara acak", clrDimGray, tipG);
   if(g_kbSt != 0 && g_kbHi > g_kbLo)
      TB_Line(StringFormat("Kotak %s ($%.2f) | tengah %s", KB_Rng(), g_kbHi - g_kbLo, KB_Px((g_kbHi + g_kbLo) / 2)), clrAqua,
              "Kotak sideway yang diawasi (tombol Kotak Sideway). Batal = 1 lebar kotak di luar dinding yang ditembus.");
   else
      TB_Line("Kotak: belum ada (menunggu kotak sideway)", clrDimGray);
   //--- rekap indikator sekarang
   string tipI = "Rekap indikator candle M1 & M5 terakhir yang sudah tutup. LONJAKAN = volume tick M1 >= 2x rata2 60 candle\n"
                 "atau ATR(5)/ATR(50) M1 >= 1.5. M5 BELUM IKUT = RSI(7) M5 belum searah tembusan atau kurva MACD(10,22,4) M5\n"
                 "masih melawan. Dinilai saat candle TEMBUS tutup.";
   if(g_tbNowVol >= 0)
      TB_Line(StringFormat("LONJAKAN %s: vol %.1fx | ATR5/50 %.2f", TB_LjTxt(g_tbNowVol, g_tbNowAtr), g_tbNowVol, g_tbNowAtr),
              (g_tbNowVol >= 2.0 || g_tbNowAtr >= 1.5) ? clrLime : clrSilver, tipI);
   if(g_tbNowOk5)
     {
      bool upB = (g_tbNowRsi < 50 || g_tbNowMs < 0), dnB = (g_tbNowRsi > 50 || g_tbNowMs > 0);
      TB_Line(StringFormat("RSI7 M5 %.0f | MACD M5 %s", g_tbNowRsi, g_tbNowMs > 0 ? "naik" : "turun"), clrSilver, tipI);
      TB_Line(StringFormat("M5 belum ikut: tembus ATAS %s | BAWAH %s", TB_YaTidak(upB), TB_YaTidak(dnB)), clrSilver, tipI);
     }
   //--- kejadian per jam (terbaru di atas)
   TB_Line("-- tembusan jam positif (WITA) --", clrDimGray);
   int n = ArraySize(g_tbEv), shown = 0, lastHr = -1;
   if(n == 0) TB_Line("(belum ada sejak dipasang / 10 jam terakhir)", clrDimGray);
   for(int i = n - 1; i >= 0 && shown < 6; i--, shown++)
     {
      TBEvent e = g_tbEv[i];
      if(e.hr != lastHr) { TB_Line(StringFormat("- jam %02d -", e.hr), clrDimGray); lastHr = e.hr; }
      string tp = StringFormat("Tembus %s %s close %s | vol %.1fx ATR5/50 %.2f | %s\nTARGET tengah %s s/d %s | BATAL %s (1W)\n"
                               "Kategori %s: balik %d%% (acak kategori %d%%, acak tembusan ini %d%%)", TB_Side(e.side),
                               GP_LocalTime(e.t), KB_Px(e.c), e.vol, e.atr, TB_M5Txt(e), KB_Px(e.mid), GP_LocalTime(e.t + TB_HOLD * 60),
                               KB_Px(e.sl), TB_CAT_N[e.cat], TB_CAT_P[e.cat], TB_CAT_G[e.cat], e.acak >= 0 ? (int)MathRound(100 * e.acak) : 0);
      if(e.res == 9)
        {
         TB_Line(StringFormat("%s %s dekat rollover - dilewati", GP_LocalTime(e.t), TB_Side(e.side)), clrDimGray, tp);
         continue;
        }
      if(e.good > 0)
         tp += StringFormat("\n%s: balik %d%% (acak %d%%)", e.good == 1 ? "JAM BAGUS G1" : "JAM BAGUS G2 LEMAH", TB_EvP(e),
                            e.good == 1 ? TB_G1_A : TB_G2_A);
      TB_Line(StringFormat("%s%s %s %s %d%% -> %s s/d %s", e.good == 1 ? "*" : (e.good == 2 ? "~" : ""), GP_LocalTime(e.t),
                           TB_Side(e.side), e.good == 1 ? "JB" : TB_CAT_S[e.cat], TB_EvP(e), KB_Px(e.mid), GP_LocalTime(e.t + TB_HOLD * 60)),
              e.good == 1 ? clrLime : (e.cat == 3 ? clrSilver : clrGold), tp);
      string rs;
      color rc;
      if(e.res == 0)      { rs = StringFormat("   menunggu | lewat dinding maks $%.2f", MathMax(0.0, e.mx)); rc = clrYellow; }
      else if(e.res == 1) { rs = StringFormat("   KENA %s (%d mnt)", GP_LocalTime(e.rt), (int)((e.rt - e.t) / 60)); rc = clrLime; }
      else if(e.res == 2) { rs = StringFormat("   BATAL %s: lanjut lewat %s", GP_LocalTime(e.rt), KB_Px(e.sl)); rc = clrTomato; }
      else                { rs = StringFormat("   HABIS 4 jam (close %s)", KB_Px(e.px)); rc = clrSilver; }
      TB_Line(rs, rc, tp);
     }
   TB_CsvStats();
   if(g_tbCsvN > 0)
      TB_Line(StringFormat("uji maju sejak %s: KENA %d/%d (harapan %.1f)", g_tbCsvFirst, g_tbCsvK, g_tbCsvN, g_tbCsvE), clrSilver,
              "Dari MQL5\\Files\\GoldPro\\tembus_balik.csv (chart utama). Harapan = jumlah YAKIN% kategori tiap kejadian.");
   if(g_tbCsvGN > 0)
      TB_Line(StringFormat("uji maju JAM BAGUS: KENA %d/%d (harapan %.1f)", g_tbCsvGK, g_tbCsvGN, g_tbCsvGN * TB_G1_P / 100.0), clrGold, tipG);
   TB_Line("uji 17-26: L+B 59% (acak 56) | tanpa 60% (acak 62)", clrDimGray, tip);
   TB_Line("batal = 1W di luar dinding | INFO, bukan sinyal", clrDimGray, tip);
  }

void TB_Label(string n, int corner, int anchor, int x, int y, string s, color c, int fs, string tip)
  {
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_ZORDER, 22);
      ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
     }
   ObjectSetInteger(0, n, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, n, OBJPROP_TEXT, s == "" ? " " : s);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, fs);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, tip == "" ? "Tembus Balik GoldPro (jam positif 23 & 03-07 WITA)" : tip);
  }

//--- posisi: kiri, di kanan kolom tombol; di kanan dashboard Kotak / panel trading bila terbuka
void TB_Place(int &x0, int &y0)
  {
   x0 = (DMInpButtons ? GDM::BtnColR() : 0) + 8;
   y0 = GDM::PanelTop() + (DMInpButtons ? BTN_H + 12 : 8);
   if(GDM::g_vPanel) x0 = MathMax(x0, GDM::g_panR + 10);
   string cid = IntegerToString(ChartID());
   if(GDM::g_vTrade && GlobalVariableCheck("GP_EAPW_" + cid) && GlobalVariableGet("GP_EAPH_" + cid) > 0)
      x0 = MathMax(x0, GDM::BtnColR() + 6 + (int)GlobalVariableGet("GP_EAPW_" + cid) + 10);
   if(ObjectFind(0, KB_PFX + "BG") >= 0)
      x0 = MathMax(x0, (int)ObjectGetInteger(0, KB_PFX + "BG", OBJPROP_XDISTANCE) + (int)ObjectGetInteger(0, KB_PFX + "BG", OBJPROP_XSIZE) + 8);
  }

void TB_Render()
  {
   TB_BuildLines();
   int n = ArraySize(g_tbL);
   if(n < 1) return;
   int lh = KB_LineH(), fs = MathMax(7, InpKBFont), w = 0, x0, y0;
   for(int i = 0; i < n; i++) w = MathMax(w, KB_W(g_tbL[i]));
   w += 12;
   TB_Place(x0, y0);
   int chh = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0), maxn = (chh - 2 - y0 - 8) / lh;
   if(n > maxn && maxn >= 3)                                              // chart pendek: buang baris kejadian lama, penutup tetap
     {
      g_tbL[maxn - 1] = g_tbL[n - 1]; g_tbC[maxn - 1] = g_tbC[n - 1]; g_tbT[maxn - 1] = g_tbT[n - 1];
      n = maxn;
     }
   string bg = TB_PFX + "BG";
   if(ObjectFind(0, bg) < 0)
     {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, bg, OBJPROP_ZORDER, 21);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'26,20,36');
      ObjectSetString(0, bg, OBJPROP_TOOLTIP, "Tembus Balik GoldPro (jam positif 23 & 03-07 WITA)");
     }
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x0 - 4);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y0 - 4);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, w + 2);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, n * lh + 8);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, C'150,90,200');
   for(int i = 0; i < n; i++)
      TB_Label(TB_PFX + "L" + IntegerToString(i), CORNER_LEFT_UPPER, ANCHOR_LEFT_UPPER, x0 + 2, y0 + i * lh, g_tbL[i], g_tbC[i], fs, g_tbT[i]);
   for(int i = n; ObjectFind(0, TB_PFX + "L" + IntegerToString(i)) >= 0; i++)
      ObjectDelete(0, TB_PFX + "L" + IntegerToString(i));
  }

//--- STRIP REKAP di bawah chart (kiri bawah, di atas baris cek kesehatan GPV_)
void TB_Strip()
  {
   if(!InpTBStrip) { if(ObjectFind(0, TB_PFX + "S0") >= 0) ObjectsDeleteAll(0, TB_PFX + "S"); return; }
   int nv = 0;
   while(ObjectFind(0, GPV_PFX + IntegerToString(nv)) >= 0) nv++;
   int x = (DMInpButtons ? GDM::BtnColR() : 0) + 8, y = 8 + nv * 17;
   color hc;
   string hs = TB_HourStatus(hc);
   string s2 = (g_tbNowVol >= 0) ? StringFormat("LONJAKAN %s: vol %.1fx ATR5/50 %.2f", TB_LjTxt(g_tbNowVol, g_tbNowAtr), g_tbNowVol, g_tbNowAtr)
                                 : "LONJAKAN: menunggu data M1";
   string s3 = g_tbNowOk5 ? StringFormat("M5 belum ikut: ATAS %s | BAWAH %s (RSI7 %.0f, MACD %s)",
                                         TB_YaTidak(g_tbNowRsi < 50 || g_tbNowMs < 0), TB_YaTidak(g_tbNowRsi > 50 || g_tbNowMs > 0),
                                         g_tbNowRsi, g_tbNowMs > 0 ? "naik" : "turun")
                          : "M5: menunggu data";
   string tip = "Rekap indikator Tembus Balik (candle M1 & M5 terakhir yang tutup). Klik tombol Tembus Balik = tampil / sembunyi.";
   color gc;
   string s4 = "* " + TB_GoodStatus(gc) + StringFormat(" (%d%%)", TB_G1_P);       // 12 Okt: jam bagus
   //--- 11 Okt (screenshot: chart utama pendek karena jendela RSI -> baris strip tertutup dashboard Kotak): area strip yang
   //    bertumpuk dengan dashboard Kotak / Tembus Balik -> strip digeser ke kanan dashboard itu
   int sw = MathMax(MathMax(KB_W("TB | " + hs), KB_W("TB | " + s4)), MathMax(KB_W("TB | " + s2), KB_W("TB | " + s3))) + 6;
   int chh = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0), top = chh - (y + 45 + KB_LineH() + 2), bot = chh - y;
   string bgs[2] = {KB_PFX + "BG", TB_PFX + "BG"};
   for(int pass = 0; pass < 2; pass++)
      for(int k = 0; k < 2; k++)
        {
         if(ObjectFind(0, bgs[k]) < 0) continue;
         int bx = (int)ObjectGetInteger(0, bgs[k], OBJPROP_XDISTANCE), by = (int)ObjectGetInteger(0, bgs[k], OBJPROP_YDISTANCE);
         int bw = (int)ObjectGetInteger(0, bgs[k], OBJPROP_XSIZE), bh = (int)ObjectGetInteger(0, bgs[k], OBJPROP_YSIZE);
         if(by < bot && by + bh > top && bx < x + sw && bx + bw > x) x = bx + bw + 8;
        }
   TB_Label(TB_PFX + "S2", CORNER_LEFT_LOWER, ANCHOR_LEFT_LOWER, x, y, "TB | " + s3, clrSilver, 8, tip);
   TB_Label(TB_PFX + "S1", CORNER_LEFT_LOWER, ANCHOR_LEFT_LOWER, x, y + 15, "TB | " + s2,
            (g_tbNowVol >= 2.0 || g_tbNowAtr >= 1.5) ? clrLime : clrSilver, 8, tip);
   TB_Label(TB_PFX + "S0", CORNER_LEFT_LOWER, ANCHOR_LEFT_LOWER, x, y + 30, "TB | " + hs, hc, 8, tip);
   TB_Label(TB_PFX + "S3", CORNER_LEFT_LOWER, ANCHOR_LEFT_LOWER, x, y + 45, "TB | " + s4, gc, 8,
            "JAM BAGUS: tembus BAWAH di jam pertama sesudah pasar buka -> balik ke tengah 70% (acak 61), uji 2017-26. INFO, bukan sinyal.");
  }

//--- 12 Okt: pengingat Telegram saat JAM BAGUS mulai (chart utama, sekali per hari server, pasar buka; jalan walau tombol mati)
void TB_GoodTick()
  {
   if(!InpTBTelegram || !InpTBGoodRemind || !g_gpMaster) return;
   datetime now = TimeTradeServer(), g = TB_G1Start(now);
   if(now < g || now >= g + 10 * 60) return;                             // 01:10-01:19 server
   datetime lt = (datetime)SymbolInfoInteger(_Symbol, SYMBOL_TIME);
   if(lt <= 0 || now - lt > 600) return;
   double day = (double)(g / 86400);
   if(GlobalVariableCheck("GP_TBG_DAY") && GlobalVariableGet("GP_TBG_DAY") >= day) return;
   datetime t = iTime(_Symbol, PERIOD_M1, 1);
   if(t <= 0) return;
   string bx = (g_kbSt != 0 && g_kbHi > g_kbLo)
               ? StringFormat("kotak sekarang %s ($%.2f), tengah %s", KB_Rng(), g_kbHi - g_kbLo, KB_Px((g_kbHi + g_kbLo) / 2))
               : "belum ada kotak sideway - tunggu kotak terbentuk";
   string s = StringFormat("JAM BAGUS %s-%s WITA : tunggu TEMBUS BAWAH kotak^TARGET tengah kotak (BELI balik) s/d 4 jam | BATAL 1W di "
                           "bawah dinding^YAKIN %d%% (acak %d%%; 2022-26 %d%%) | %s | INFO, bukan sinyal", GP_LocalTime(g),
                           GP_LocalTime(g + 49 * 60), TB_G1_P, TB_G1_A, TB_G1_B, bx);
   KB_Out(t, "TBGJAM", s);
   GlobalVariableSet("GP_TBG_DAY", day);
  }

//--- 14 Okt 2026: tombol "Tembus Balik" = GAMBAR di chart: panah di candle tembus (ke arah balik yang diharapkan), garis TARGET tengah
//    kotak (hijau titik) & BATAL 1W (merah titik) dari candle tembus s/d hasil / sekarang, label hasil. Hijau terang = JAM BAGUS.
//    Kejadian 24 jam terakhir (yang dilewati dekat rollover tidak digambar). Prefix GPI_M.
void TB_MarkLine(string n, datetime t1, datetime t2, double p, color c, string tip)
  {
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_TREND, 0, t1, p, t2, p);
      ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, n, OBJPROP_BACK, false);
     }
   ObjectMove(0, n, 0, t1, p); ObjectMove(0, n, 1, t2, p);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, tip);
  }
void TB_MarkText(string n, datetime t, double p, string s, color c, ENUM_ANCHOR_POINT a, string tip)
  {
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_TEXT, 0, t, p);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetString(0, n, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 7);
     }
   ObjectMove(0, n, 0, t, p);
   ObjectSetString(0, n, OBJPROP_TEXT, s);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, a);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, tip);
  }
void TB_Marks()
  {
   datetime now = TimeCurrent();
   string keep = "|";
   for(int i = 0; i < ArraySize(g_tbEv); i++)
     {
      TBEvent e = g_tbEv[i];
      if(e.res == 9 || now - e.t > 24 * 3600) continue;
      string id = TB_PFX + "M" + IntegerToString((long)e.t) + (e.side > 0 ? "A" : "B");
      keep += id + "|";
      color c = (e.good == 1) ? clrLime : ((e.good == 2) ? clrGold : C'190,120,255');
      datetime t2 = (e.res != 0) ? e.rt : now + PeriodSeconds(PERIOD_CURRENT) * 3;
      string tip = StringFormat("Tembus Balik %s: tembus %s %s WITA, yakin balik %d%%%s | TARGET tengah %s, BATAL %s",
                                e.good == 1 ? "JAM BAGUS" : (e.good == 2 ? "jam bagus LEMAH" : "jam positif"), TB_Side(e.side),
                                GP_LocalTime(e.t), TB_EvP(e), e.good == 1 ? StringFormat(" (acak %d%%)", TB_G1_A) : "", KB_Px(e.mid), KB_Px(e.sl));
      string ar = id + "a";                                                // panah ke arah balik yang diharapkan
      if(ObjectFind(0, ar) < 0)
        {
         ObjectCreate(0, ar, OBJ_ARROW, 0, e.t, e.c);
         ObjectSetInteger(0, ar, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, ar, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, ar, OBJPROP_WIDTH, 2);
        }
      ObjectMove(0, ar, 0, e.t, e.c);
      ObjectSetInteger(0, ar, OBJPROP_ARROWCODE, e.side > 0 ? 234 : 233);
      ObjectSetInteger(0, ar, OBJPROP_ANCHOR, e.side > 0 ? ANCHOR_BOTTOM : ANCHOR_TOP);
      ObjectSetInteger(0, ar, OBJPROP_COLOR, c);
      ObjectSetString(0, ar, OBJPROP_TOOLTIP, tip);
      TB_MarkLine(id + "t", e.t, t2, e.mid, clrLimeGreen, "TARGET tengah kotak " + KB_Px(e.mid) + " - " + tip);
      TB_MarkLine(id + "b", e.t, t2, e.sl, clrTomato, "BATAL 1W " + KB_Px(e.sl) + " - " + tip);
      string rs = (e.res == 1) ? "KENA" : ((e.res == 2) ? "BATAL" : ((e.res == 3) ? "HABIS" : "menunggu"));
      color rc = (e.res == 1) ? clrLime : ((e.res == 2) ? clrTomato : clrSilver);
      TB_MarkText(id + "r", t2, e.mid, StringFormat("%s%s %d%%", e.good == 1 ? "* " : "", rs, TB_EvP(e)), rc, ANCHOR_LEFT, tip);
     }
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)                  // tanda kejadian yang sudah lewat 24 jam / hilang dari daftar
     {
      string nm = ObjectName(0, i, 0, -1);
      if(StringFind(nm, TB_PFX + "M") != 0) continue;
      string base = StringSubstr(nm, 0, StringLen(nm) - 1);
      if(StringFind(keep, "|" + base + "|") < 0) ObjectDelete(0, nm);
     }
  }

void TB_Update()
  {
   if(MQLInfoInteger(MQL_TESTER)) return;
   TB_GoodTick();
   if(!GDM::g_vTbk && !GDM::g_iTbk)
     {
      ObjectsDeleteAll(0, TB_PFX);
      return;
     }
   TB_RecapNow();
   if(GDM::g_iTbk) { TB_Render(); TB_Strip(); }                          // 14 Okt: kotak "i" = dashboard + strip
   else if(ObjectFind(0, TB_PFX + "BG") >= 0 || ObjectFind(0, TB_PFX + "S0") >= 0)
     { ObjectDelete(0, TB_PFX + "BG"); ObjectsDeleteAll(0, TB_PFX + "L"); ObjectsDeleteAll(0, TB_PFX + "S"); }
   if(GDM::g_vTbk) TB_Marks();                                            // tombol utama = gambar di chart
   else ObjectsDeleteAll(0, TB_PFX + "M");
  }

void TB_ChartEvent(const int id, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK && (sparam == "GPB_B_tbk" || sparam == "GPB_I_tbk")) { TB_Update(); ChartRedraw(); return; }
   if(id == CHARTEVENT_CHART_CHANGE && (GDM::g_vTbk || GDM::g_iTbk)) TB_Update();
  }

void TB_Deinit(bool isFinal)
  {
   if(isFinal) ObjectsDeleteAll(0, TB_PFX);
  }

#endif // GP_TEMBUSBALIK_MQH
