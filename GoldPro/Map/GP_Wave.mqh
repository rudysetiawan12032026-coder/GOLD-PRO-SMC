//+------------------------------------------------------------------+
//|                                                      GP_Wave.mqh |
//| GoldPro - PETA GELOMBANG (tombol "Gelombang", 14 Okt 2026).       |
//| Pengguna: "kita bikin yg lebih lebar dengan perhitungan matang ... |
//| dari range kecil sebagai gelombang awal untuk melihat tujuan ke    |
//| gelombang lebih jauh. hitung secara akurat, jangan asal gambar".   |
//| Riset research\gelombang.py (XAUUSD M5 & M15 2017-26, ~50 rb       |
//| gelombang, struktur gaya LuxAlgo seperti SMC Analytics):           |
//|  - pivot SWING 50 = gelombang besar: puncak / dasar berjalan sejak |
//|    pivot swing terakhir = range LEBAR; tren swing (BOS / CHoCH)    |
//|    menentukan Strong / Weak. Premium = 5% teratas, Equilibrium =   |
//|    47.5-52.5%, Discount = 5% terbawah (definisi LuxAlgo).          |
//|  - pivot INTERNAL 5 = gelombang kecil. GELOMBANG AWAL: close       |
//|    menembus pivot internal (BOS) -> A = H1 - L0, pullback L1 (L1   |
//|    di atas L0 = bersih) = BATAL. Target T = L1 + k x A.            |
//|    Sampai T sebelum L1 tertembus (uji): 1.0A 64% | 1.272A 57% |    |
//|    1.618A 47% | 2.0A 39% | 2.618A 30% = HITUNGAN JARAK (selisih    |
//|    +-2 poin), searah / melawan swing sama, 2017-21 = 2022-26.      |
//|    Jauh gelombang dari L1: 25% < 0.94A, 50% < 1.55A, 75% < 3.1A.   |
//|  -> peluang di chart = (harga - batal) / (target - batal) dari     |
//|     harga SEKARANG (tepat menurut uji). Jejak "institusi" tidak    |
//|     terbukti (OB / Premium-Discount / Strong-Weak = acak, 14 Okt). |
//| Warna sederhana: merah = atas (Premium / high), hijau = bawah      |
//| (Discount / low), abu = tengah, emas = gelombang awal, biru =      |
//| target, oranye = batal. Garis padat = Strong, putus = Weak.        |
//| 14 Okt sore (pengguna: "apa yg kamu usulkan kita eksekusi"):       |
//|  - (diganti 14 Okt sore) BOS internal TERBARU selalu digambar;     |
//|    tidak bersih diberi tanda + label status;                       |
//|  - label di DALAM chart (ujung kanan garis, tidak terpotong) dan   |
//|    ikut digeser GP_LabelFix bila bertumpuk;                        |
//|  - UJI MAJU: tiap gelombang bersih sejak dipasang dicatat ke       |
//|    MQL5\Files\GoldPro\gelombang.csv saat selesai (batal / semua    |
//|    target kena / 2 hari) -> kartu info: KENA vs harapan per target.|
//| INFO peta, bukan sinyal; modul ini tidak membuka order.            |
//+------------------------------------------------------------------+
#ifndef GP_WAVE_MQH
#define GP_WAVE_MQH

input group "=== GoldPro: Peta Gelombang (tombol Gelombang) ==="
input int InpWVSwing    = 50;     // Panjang pivot SWING (gelombang besar / range lebar)
input int InpWVInternal = 5;      // Panjang pivot INTERNAL (gelombang awal)
input int InpWVBars     = 3000;   // Jumlah candle chart yang dihitung
input bool InpWVLog     = true;   // Uji maju: catat gelombang bersih ke MQL5\Files\GoldPro\gelombang.csv

#define WV_PFX "GPW_"
#define WV_CSV "GoldPro\\gelombang.csv"
double WV_K[5]   = {1.0, 1.272, 1.618, 2.0, 2.618};
string WV_KN[5]  = {"1.0A", "1.272A", "1.618A", "2.0A", "2.618A"};
int    WV_UJI[5] = {64, 57, 47, 39, 30};
//--- 14 Okt 2026 (research\m1_cek.py -> gelombang_m1.txt, 110 rb gelombang M1 bersih): M1 64 / 56 / 46 / 38 / 29%, NYATA konsisten
//    ~1.5 poin DI BAWAH hitungan jarak (2017-21 -1.3..-2.3, 2022-26 -0.0..-1.7, searah & melawan swing) -> di chart M1 peluang
//    live dikurangi 1.5 poin; jauh gelombang M1: 25% < 0.92A, 50% < 1.50A, 75% < 3.0A, 90% < 7.4A.
int    WV_UJI1[5] = {64, 56, 46, 38, 29};
int    WV_Uji(int k)   { return (_Period == PERIOD_M1) ? WV_UJI1[k] : WV_UJI[k]; }
double WV_Corr()       { return (_Period == PERIOD_M1) ? 0.015 : 0.0; }
struct WVPiv  { int t; int p; int kind; double px; };
struct WVWave { int tbi; int side; double w0, brk, w1, A, c0; datetime t0, th, tb, tw1; bool clean; };
//--- 14 Okt sore (screenshot: gelombang "LAMA" & sudah batal tampil terus): gelombang TIDAK BERSIH (pullback lewat awal gelombang)
//    juga tepat = hitungan jarak (gelombang.pkl M5 / M15 +-2.5 poin; gelombang_m1.pkl M1 -1.0..-2.7 = koreksi M1 sama) -> BOS
//    internal TERBARU selalu digambar; tidak bersih diberi tanda. Target yang sudah terlewati saat BOS = "dilewati" (bukan KENA).

datetime g_wvBar = 0;
bool     g_wvRange = false;
double   g_wvTop = 0, g_wvBot = 0;
datetime g_wvTopT = 0, g_wvBotT = 0;
int      g_wvTrend = 0;
bool     g_wvOk = false, g_wvInv = false, g_wvClean = true;   // Clean = pullback tidak melewati awal gelombang
int      g_wvSide = 0;
double   g_wvW0 = 0, g_wvBrk = 0, g_wvW1 = 0, g_wvA = 0, g_wvExt = 0, g_wvC0 = 0;   // W0 awal, Brk ditembus, W1 = BATAL, C0 close BOS
datetime g_wvT0 = 0, g_wvTH = 0, g_wvTB = 0, g_wvTW1 = 0, g_wvInvT = 0;
int      g_wvCsvN[5], g_wvCsvK[5];
double   g_wvCsvE[5];
int      g_wvCsvRows = 0;
datetime g_wvCsvChk = 0;

//--- pivot gaya LuxAlgo leg(): pivot di bar p = t - size bila high[p] > high tertinggi size bar sesudahnya (low sebaliknya)
void WV_Pivots(const MqlRates &r[], int n, int size, WVPiv &out[])
  {
   ArrayResize(out, 0);
   int leg = -1;
   for(int t = size; t < n; t++)
     {
      int p = t - size;
      double mh = -DBL_MAX, ml = DBL_MAX;
      for(int j = p + 1; j <= t; j++) { mh = MathMax(mh, r[j].high); ml = MathMin(ml, r[j].low); }
      int nw = (r[p].high > mh) ? 0 : ((r[p].low < ml) ? 1 : leg);
      if(nw != leg && leg != -1)
        {
         int k = ArraySize(out);
         ArrayResize(out, k + 1);
         out[k].t = t; out[k].p = p; out[k].kind = (nw == 1) ? -1 : 1; out[k].px = (nw == 1) ? r[p].low : r[p].high;
        }
      leg = nw;
     }
  }

string WV_TfName() { return StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7); }

//--- UJI MAJU: gelombang selesai? (batal dulu bila candle sama). res[k] 1 KENA / 0 tidak; kembali false bila belum selesai
bool WV_Outcome(const MqlRates &r[], int n, const WVWave &w, int &res[], string &fin, datetime &tfin)
  {
   int hz = (int)MathMax(10, 2880 * 60 / MathMax(60, PeriodSeconds(PERIOD_CURRENT)));
   ArrayResize(res, 5); ArrayInitialize(res, 0);
   int s = w.side, nk = 0, na = 0;
   for(int k = 0; k < 5; k++)                                             // target sudah terlewati saat BOS: tidak dinilai (-1)
      if(s * (w.c0 - (w.w1 + s * WV_K[k] * w.A)) >= 0) res[k] = -1; else na++;
   for(int j = w.tbi + 1; j < n && j <= w.tbi + hz; j++)
     {
      if((s > 0 && r[j].low <= w.w1) || (s < 0 && r[j].high >= w.w1)) { fin = "BATAL"; tfin = r[j].time; return true; }
      double ex = (s > 0) ? r[j].high : r[j].low;
      for(int k = 0; k < 5; k++)
         if(res[k] == 0 && s * (ex - (w.w1 + s * WV_K[k] * w.A)) >= 0) { res[k] = 1; nk++; }
      if(nk == na) { fin = "SEMUA KENA"; tfin = r[j].time; return true; }
     }
   if(n - 1 - w.tbi >= hz) { fin = "HABIS 2 HARI"; tfin = r[MathMin(n - 1, w.tbi + hz)].time; return true; }
   return false;
  }
void WV_Log(const MqlRates &r[], int n, const WVWave &wv[])
  {
   if(!InpWVLog || MQLInfoInteger(MQL_TESTER)) return;
   string gk = "GP_WVJ_" + _Symbol + "_" + WV_TfName();
   if(!GlobalVariableCheck(gk + "_T0")) GlobalVariableSet(gk + "_T0", (double)TimeCurrent());   // hanya gelombang SESUDAH dipasang
   datetime t0 = (datetime)GlobalVariableGet(gk + "_T0");
   double last = GlobalVariableCheck(gk) ? GlobalVariableGet(gk) : 0;
   for(int i = 0; i < ArraySize(wv); i++)
     {
      if(wv[i].tb < t0 || (double)wv[i].tb <= last) continue;
      int res[];
      string fin;
      datetime tf;
      if(!WV_Outcome(r, n, wv[i], res, fin, tf)) break;                  // urut waktu: tunggu yang lebih tua selesai dulu
      FolderCreate("GoldPro");
      bool isNew = !FileIsExist(WV_CSV);
      int fh = FileOpen(WV_CSV, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ, ';');
      if(fh == INVALID_HANDLE) return;
      FileSeek(fh, 0, SEEK_END);
      if(isNew)
         FileWrite(fh, "bos_wita", "tf", "sisi", "A", "batal", "close_bos", "k1_0", "p1_0", "k1_272", "p1_272", "k1_618", "p1_618",
                   "k2_0", "p2_0", "k2_618", "p2_618", "selesai", "waktu_selesai_wita", "bersih");
      double p[5];
      for(int k = 0; k < 5; k++)
        {
         double T = wv[i].w1 + wv[i].side * WV_K[k] * wv[i].A;
         p[k] = (res[k] < 0) ? -0.01 : MathMax(0.0, MathMin(1.0, wv[i].side * (wv[i].c0 - wv[i].w1) / (wv[i].side * (T - wv[i].w1)) - WV_Corr()));
        }
      FileWrite(fh, KB_WitaFull(wv[i].tb), WV_TfName(), wv[i].side > 0 ? "NAIK" : "TURUN", DoubleToString(wv[i].A, 2),
                DoubleToString(wv[i].w1, 2), DoubleToString(wv[i].c0, 2), res[0], (int)MathRound(p[0] * 100), res[1],
                (int)MathRound(p[1] * 100), res[2], (int)MathRound(p[2] * 100), res[3], (int)MathRound(p[3] * 100), res[4],
                (int)MathRound(p[4] * 100), fin, KB_WitaFull(tf), wv[i].clean ? 1 : 0);
      FileClose(fh);
      GlobalVariableSet(gk, (double)wv[i].tb);
      last = (double)wv[i].tb;
      g_wvCsvChk = 0;
     }
  }
void WV_CsvStats()
  {
   if(g_wvCsvChk != 0 && TimeLocal() - g_wvCsvChk < 60) return;
   g_wvCsvChk = TimeLocal();
   ArrayInitialize(g_wvCsvN, 0); ArrayInitialize(g_wvCsvK, 0); ArrayInitialize(g_wvCsvE, 0); g_wvCsvRows = 0;
   if(!FileIsExist(WV_CSV)) return;
   int fh = FileOpen(WV_CSV, FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE) return;
   bool head = true;
   string tfn = WV_TfName();
   while(!FileIsEnding(fh))
     {
      string ln = FileReadString(fh);
      if(head) { head = false; continue; }
      string a[];
      if(StringSplit(ln, ';', a) < 17 || a[1] != tfn) continue;
      g_wvCsvRows++;
      for(int k = 0; k < 5; k++)
        {
         int rk = (int)StringToInteger(a[6 + 2 * k]);
         if(rk < 0) continue;                                             // target sudah terlewati saat BOS: tidak dinilai
         g_wvCsvN[k]++;
         g_wvCsvK[k] += rk;
         g_wvCsvE[k] += StringToDouble(a[7 + 2 * k]) / 100.0;
        }
     }
   FileClose(fh);
  }

bool WV_Compute()
  {
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_CURRENT, 1, InpWVBars, r);          // candle yang sudah tutup, terlama dulu
   if(n < InpWVSwing * 3) return false;
   WVPiv ps[], pi[];
   WV_Pivots(r, n, InpWVSwing, ps);
   WV_Pivots(r, n, InpWVInternal, pi);
   //--- range swing (puncak / dasar berjalan) & tren swing
   double tp = -1, bt = -1, sH = 0, sL = 0;
   datetime tpT = 0, btT = 0;
   bool sHb = true, sLb = true;
   int trend = 0, q = 0, nps = ArraySize(ps);
   for(int t = 0; t < n; t++)
     {
      while(q < nps && ps[q].t == t)
        {
         if(ps[q].kind > 0) { tp = ps[q].px; tpT = r[ps[q].p].time; sH = ps[q].px; sHb = false; }
         else               { bt = ps[q].px; btT = r[ps[q].p].time; sL = ps[q].px; sLb = false; }
         q++;
        }
      if(tp < 0 || r[t].high > tp) { tp = r[t].high; tpT = r[t].time; }
      if(bt < 0 || r[t].low < bt)  { bt = r[t].low;  btT = r[t].time; }
      double cp = (t > 0) ? r[t - 1].close : r[t].close;
      if(!sHb && r[t].close > sH && cp <= sH) { sHb = true; trend = 1; }
      if(!sLb && r[t].close < sL && cp >= sL) { sLb = true; trend = -1; }
     }
   g_wvRange = (tp > bt && bt > 0);
   g_wvTop = tp; g_wvBot = bt; g_wvTopT = tpT; g_wvBotT = btT; g_wvTrend = trend;
   //--- semua BOS internal -> daftar gelombang (bersih / tidak bersih); yang TERBARU digambar
   WVWave wv[];
   double hPx = 0, lPx = 0;
   int hP = -1, lP = -1, q2 = 0, npi = ArraySize(pi);
   bool hB = true, lB = true;
   for(int t = 0; t < n; t++)
     {
      while(q2 < npi && pi[q2].t == t)
        {
         if(pi[q2].kind > 0) { hPx = pi[q2].px; hP = pi[q2].p; hB = false; }
         else                { lPx = pi[q2].px; lP = pi[q2].p; lB = false; }
         q2++;
        }
      double cp = (t > 0) ? r[t - 1].close : r[t].close;
      for(int sd = 1; sd >= -1; sd -= 2)
        {
         double lv = (sd > 0) ? hPx : lPx;
         int lp = (sd > 0) ? hP : lP;
         bool br = (sd > 0) ? (!hB && r[t].close > hPx && cp <= hPx) : (!lB && r[t].close < lPx && cp >= lPx);
         if(!br) continue;
         if(sd > 0) hB = true; else lB = true;
         int k0 = -1;
         for(int k = q2 - 1; k >= 0; k--) if(pi[k].kind == -sd && pi[k].p < lp) { k0 = k; break; }
         if(k0 < 0) continue;
         double w1 = (sd > 0) ? DBL_MAX : -DBL_MAX;
         int w1p = lp;
         for(int j = lp; j <= t; j++)
           {
            double x = (sd > 0) ? r[j].low : r[j].high;
            if((sd > 0 && x < w1) || (sd < 0 && x > w1)) { w1 = x; w1p = j; }
           }
         double A = sd * (lv - pi[k0].px);
         if(A > 0 && sd * (r[t].close - w1) > 0)
           {
            int m = ArraySize(wv);
            ArrayResize(wv, m + 1);
            wv[m].tbi = t; wv[m].side = sd; wv[m].w0 = pi[k0].px; wv[m].brk = lv; wv[m].w1 = w1; wv[m].A = A; wv[m].c0 = r[t].close;
            wv[m].t0 = r[pi[k0].p].time; wv[m].th = r[lp].time; wv[m].tb = r[t].time; wv[m].tw1 = r[w1p].time;
            wv[m].clean = (sd * (w1 - pi[k0].px) > 0);
           }
        }
     }
   int m = ArraySize(wv);
   g_wvOk = (m > 0);
   g_wvInv = false; g_wvInvT = 0;
   if(g_wvOk)
     {
      WVWave w = wv[m - 1];
      g_wvSide = w.side; g_wvW0 = w.w0; g_wvBrk = w.brk; g_wvW1 = w.w1; g_wvA = w.A; g_wvC0 = w.c0; g_wvClean = w.clean;
      g_wvT0 = w.t0; g_wvTH = w.th; g_wvTB = w.tb; g_wvTW1 = w.tw1; g_wvExt = w.c0;
      for(int j = w.tbi + 1; j < n; j++)                                  // status sesudah BOS (candle tutup): batal dulu bila candle sama
        {
         int s = w.side;
         if((s > 0 && r[j].low <= w.w1) || (s < 0 && r[j].high >= w.w1)) { g_wvInv = true; g_wvInvT = r[j].time; break; }
         g_wvExt = (s > 0) ? MathMax(g_wvExt, r[j].high) : MathMin(g_wvExt, r[j].low);
        }
     }
   WV_Log(r, n, wv);
   return true;
  }

//--- objek
void WV_Rect(string n, datetime t1, double p1, datetime t2, double p2, color c, string tip, bool fill = true)
  {
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, n, OBJPROP_BACK, true);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, n, OBJPROP_FILL, fill);
   ObjectMove(0, n, 0, t1, p1); ObjectMove(0, n, 1, t2, p2);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, tip);
  }
void WV_Line(string n, datetime t1, double p1, datetime t2, double p2, color c, int w, ENUM_LINE_STYLE st, string tip)
  {
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_BACK, false);
     }
   ObjectMove(0, n, 0, t1, p1); ObjectMove(0, n, 1, t2, p2);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, n, OBJPROP_STYLE, st);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, tip);
  }
//--- label: posisi ASAL dicatat (SMC_LabelHome) -> GP_LabelFix menggeser bila bertumpuk / menimpa tombol & panel
void WV_Text(string n, datetime t, double p, string s, color c, ENUM_ANCHOR_POINT a, string tip)
  {
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_TEXT, 0, t, p);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetString(0, n, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
     }
   ObjectMove(0, n, 0, t, p);
   ObjectSetString(0, n, OBJPROP_TEXT, s);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, a);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, tip);
   SMC_LabelHome(n, t, p);
  }
string WV_Px(double p) { return DoubleToString(p, _Digits); }
//--- peluang sampai target sebelum batal dari harga sekarang (uji 2017-26: = hitungan jarak, selisih +-2 poin)
//    15 Okt malam (research\gel_target_cek.py, 4.1 jt cuplikan M1 tiap 5 mnt selama gelombang hidup): koreksi M1 -1.5 poin (dari uji
//    SAAT BOS) hanya tepat di 15 mnt pertama (umur <= 15 mnt: nyata - angka +0.6 dengan koreksi / -0.9 tanpa); sesudahnya jarak murni
//    lebih tepat (dengan koreksi angka 1.3 poin terlalu rendah: 15-60 mnt +0.9, > 4 jam +2.6) -> koreksi s/d 15 mnt sesudah BOS saja.
double WV_P(double cur, double tgt)
  {
   double d1 = g_wvSide * (cur - g_wvW1), d2 = g_wvSide * (tgt - g_wvW1);
   if(d2 <= 0) return -1;
   double corr = (TimeCurrent() - g_wvTB <= 16 * 60) ? WV_Corr() : 0.0;
   return MathMax(0.0, MathMin(1.0, d1 / d2 - corr));
  }
//--- ujung kanan gambar: 6 candle ke depan, tapi tidak melewati tepi kanan area chart (label tidak terpotong)
datetime WV_RightT()
  {
   datetime now = TimeCurrent();
   int ps = PeriodSeconds(PERIOD_CURRENT);
   datetime tR = now + ps * 6;
   int sub;
   datetime te;
   double pe;
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   if(cw > 100 && ChartXYToTimePrice(0, cw - 12, 20, sub, te, pe) && te > now && te < tR) tR = te;
   return (tR > now + ps) ? tR : now + ps;
  }

void WV_Draw()
  {
   datetime tR = WV_RightT();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string uji = (_Period == PERIOD_M1) ? " (uji 2017-26 XAUUSD M1: tepat = hitungan jarak - 1.5 poin; INFO, bukan sinyal)"
                                       : " (uji 2017-26 XAUUSD M5/M15: tepat, = hitungan jarak; INFO, bukan sinyal)";
   //--- RANGE SWING LEBAR
   if(g_wvRange)
     {
      double R = g_wvTop - g_wvBot;
      datetime t1 = (g_wvTopT < g_wvBotT) ? g_wvTopT : g_wvBotT;
      WV_Rect(WV_PFX + "RP", t1, g_wvTop, tR, g_wvTop - 0.05 * R, C'90,35,35', "PREMIUM: 5% teratas range swing (mahal)" + uji);
      // 14 Okt sore (screenshot: pita Equilibrium tampil BIRU TUA = abu ditumpuk pita coklat peta harian, dicampur MT5): garis tepi saja
      WV_Rect(WV_PFX + "RE", t1, g_wvBot + 0.525 * R, tR, g_wvBot + 0.475 * R, C'150,150,150', "EQUILIBRIUM: tengah range swing 47.5-52.5%" + uji, false);
      WV_Rect(WV_PFX + "RD", t1, g_wvBot + 0.05 * R, tR, g_wvBot, C'30,85,40', "DISCOUNT: 5% terbawah range swing (murah)" + uji);
      string th = (g_wvTrend < 0) ? "Strong High" : "Weak High", tl = (g_wvTrend > 0) ? "Strong Low" : "Weak Low";
      WV_Line(WV_PFX + "LH", g_wvTopT, g_wvTop, tR, g_wvTop, clrTomato, 1, (g_wvTrend < 0) ? STYLE_SOLID : STYLE_DASH,
              th + " = puncak range swing; Weak = searah tren swing (biasanya dituju), Strong = dijaga" + uji);
      WV_Line(WV_PFX + "LL", g_wvBotT, g_wvBot, tR, g_wvBot, clrLimeGreen, 1, (g_wvTrend > 0) ? STYLE_SOLID : STYLE_DASH,
              tl + " = dasar range swing" + uji);
      double pos = (bid > 0) ? (bid - g_wvBot) / R : -1;
      string ztxt = (pos >= 0.95) ? "PREMIUM" : ((pos <= 0.05) ? "DISCOUNT" : ((pos >= 0.475 && pos <= 0.525) ? "EQUILIBRIUM" :
                    (pos > 0.5 ? "atas tengah" : "bawah tengah")));
      WV_Text(WV_PFX + "XH", tR, g_wvTop, StringFormat("%s %s | Premium", th, WV_Px(g_wvTop)), clrTomato, ANCHOR_RIGHT_UPPER, th + uji);
      WV_Text(WV_PFX + "XE", tR, g_wvBot + 0.5 * R, StringFormat("Equilibrium %s | harga %d%% range (%s)", WV_Px(g_wvBot + 0.5 * R),
              (int)MathRound(pos * 100), ztxt), clrSilver, ANCHOR_RIGHT_LOWER, "Posisi harga di range swing" + uji);
      WV_Text(WV_PFX + "XL", tR, g_wvBot, StringFormat("%s %s | Discount", tl, WV_Px(g_wvBot)), clrLimeGreen, ANCHOR_RIGHT_LOWER, tl + uji);
     }
   else if(ObjectFind(0, WV_PFX + "RP") >= 0) { ObjectsDeleteAll(0, WV_PFX + "R"); ObjectsDeleteAll(0, WV_PFX + "L"); ObjectsDeleteAll(0, WV_PFX + "X"); }
   //--- status gelombang awal (di bawah label Equilibrium)
   //--- 15 Okt (screenshot: status "TIDAK BERSIH" menimpa label target 2.0A): tanda tidak bersih cukup di label "A $x (tdk bersih)"
   string stt = !g_wvOk ? "gelombang awal: menunggu BOS internal" : "";
   if(stt != "" && g_wvRange)
      WV_Text(WV_PFX + "XS", tR, g_wvBot + 0.475 * (g_wvTop - g_wvBot), stt, clrDarkGray, ANCHOR_RIGHT_UPPER,
              "Gelombang awal = range kecil (pivot internal) yang baru ditembus. TIDAK BERSIH = pullback melewati awal gelombang "
              "(batal lebih jauh, target dekat sering sudah terlewati); peluangnya tetap tepat = hitungan jarak (uji 2017-26).");
   else if(ObjectFind(0, WV_PFX + "XS") >= 0) ObjectDelete(0, WV_PFX + "XS");
   //--- GELOMBANG AWAL -> TARGET
   if(!g_wvOk)
     {
      if(ObjectFind(0, WV_PFX + "WA") >= 0) { ObjectsDeleteAll(0, WV_PFX + "W"); ObjectsDeleteAll(0, WV_PFX + "T"); ObjectsDeleteAll(0, WV_PFX + "B"); }
      return;
     }
   int s = g_wvSide;
   bool inv = g_wvInv;
   double ext = g_wvExt;
   if(!inv)                                                               // candle berjalan
     {
      double h0 = iHigh(_Symbol, PERIOD_CURRENT, 0), l0 = iLow(_Symbol, PERIOD_CURRENT, 0);
      if((s > 0 && l0 > 0 && l0 <= g_wvW1) || (s < 0 && h0 >= g_wvW1)) inv = true;
      else ext = (s > 0) ? MathMax(ext, h0) : MathMin(ext, l0);
     }
   color cg = clrGold, cb = clrDeepSkyBlue;
   string lama = g_wvClean ? "" : " (tdk bersih)";
   string gw = StringFormat("Gelombang awal %s%s A = $%.2f (%s -> %s)", s > 0 ? "NAIK" : "TURUN", lama, g_wvA, WV_Px(g_wvW0), WV_Px(g_wvBrk));
   WV_Line(WV_PFX + "WA", g_wvT0, g_wvW0, g_wvTH, g_wvBrk, cg, 2, STYLE_SOLID, gw + uji);
   WV_Line(WV_PFX + "WB", g_wvTH, g_wvBrk, g_wvTW1, g_wvW1, cg, 1, STYLE_DOT, "pullback gelombang awal -> BATAL di " + WV_Px(g_wvW1));
   WV_Text(WV_PFX + "WT", g_wvTH, g_wvBrk, StringFormat("A $%.2f%s", g_wvA, lama), cg, s > 0 ? ANCHOR_LOWER : ANCHOR_UPPER, gw + uji);
   WV_Line(WV_PFX + "BL", g_wvTW1, g_wvW1, tR, g_wvW1, clrOrange, 1, STYLE_DASH,
           "BATAL: pullback gelombang awal tertembus = gelombang selesai" + uji);
   WV_Text(WV_PFX + "BX", tR, g_wvW1, "BATAL " + WV_Px(g_wvW1) + (inv ? " - TERTEMBUS" : ""), clrOrange,
           s > 0 ? ANCHOR_RIGHT_UPPER : ANCHOR_RIGHT_LOWER, "BATAL gelombang awal" + uji);
   for(int k = 0; k < 5; k++)
     {
      double T = g_wvW1 + s * WV_K[k] * g_wvA;
      bool passed = (s * (g_wvC0 - T) >= 0);                              // sudah terlewati saat BOS (gelombang tidak bersih)
      bool hit = !passed && (s * (ext - T) >= 0);
      double p = WV_P(bid, T);
      string st = passed ? "dilewati" : (hit ? "KENA" : (inv ? "batal" : (p >= 0 ? StringFormat("%d%%", (int)MathRound(p * 100)) : "-")));
      color c = passed ? C'90,90,90' : (hit ? clrLime : (inv ? clrDimGray : cb));
      string tip = StringFormat("Target %s = batal + %.3f x A = %s | peluang sampai sebelum BATAL dari harga sekarang %s; rata2 uji saat BOS %d%%%s",
                                WV_KN[k], WV_K[k], WV_Px(T), st, WV_Uji(k), uji);
      WV_Line(WV_PFX + "TL" + IntegerToString(k), g_wvTB, T, tR, T, c, 1, STYLE_DOT, tip);
      WV_Text(WV_PFX + "TX" + IntegerToString(k), tR, T, StringFormat("%s %s | %s", WV_KN[k], WV_Px(T), st), c,
              s > 0 ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER, tip);
     }
  }

void WV_Update()
  {
   if(MQLInfoInteger(MQL_TESTER)) return;
   if(!GDM::g_vWave)
     {
      if(ObjectFind(0, WV_PFX + "RP") >= 0 || ObjectFind(0, WV_PFX + "WA") >= 0 || ObjectFind(0, WV_PFX + "XS") >= 0)
         ObjectsDeleteAll(0, WV_PFX);
      return;
     }
   datetime b = iTime(_Symbol, PERIOD_CURRENT, 1);
   if(b != 0 && b != g_wvBar && WV_Compute()) g_wvBar = b;
   WV_Draw();
  }

void WV_ChartEvent(const int id, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == "GPB_B_wave" && GDM::g_vWave) { g_wvBar = 0; WV_Update(); ChartRedraw(); }
  }

void WV_Deinit(bool isFinal)
  {
   if(isFinal) ObjectsDeleteAll(0, WV_PFX);
  }

//--- isi kartu info kotak "i" di samping tombol Gelombang (dipanggil GP_DayMap)
void WV_InfoLines(string &L[], color &K[])
  {
   color W = clrWhite, G = clrSilver;
   GDM::AddLine(L, K, "PETA GELOMBANG  (gambar = tombol Gelombang)", clrGold);
   if(!GDM::g_vWave) GDM::AddLine(L, K, "tombol Gelombang mati -> klik untuk menggambar", G);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(g_wvRange && g_wvTop > g_wvBot)
     {
      double R = g_wvTop - g_wvBot;
      GDM::AddLine(L, K, StringFormat("Range swing %s - %s ($%.2f)", WV_Px(g_wvBot), WV_Px(g_wvTop), R), W);
      GDM::AddLine(L, K, StringFormat("tren swing %s | harga %d%% range", g_wvTrend > 0 ? "NAIK" : (g_wvTrend < 0 ? "TURUN" : "-"),
                                      (int)MathRound((bid - g_wvBot) / R * 100)), W);
      GDM::AddLine(L, K, StringFormat("atas = %s | bawah = %s", g_wvTrend < 0 ? "Strong High" : "Weak High",
                                      g_wvTrend > 0 ? "Strong Low" : "Weak Low"), G);
      //--- 15 Okt malam (research\gel_arah.py, 624 rb sampel M1 2017-26): garis PREMIUM sebelum DISCOUNT nyata 51.9% = jarak 52.0%,
      //    ke EQUILIBRIUM dulu 50.0 = 50.1%; indikator klasik & kombinasinya (EMA / MACD / RSI M1-H1, momentum, tren) <= +-1.6 poin
      double Pl = g_wvTop - 0.05 * R, Dl = g_wvBot + 0.05 * R, Eq = g_wvBot + 0.5 * R;
      GDM::AddLine(L, K, "-- PELUANG DARI HARGA SEKARANG (uji = jarak) --", clrLimeGreen);
      if(bid > Dl && bid < Pl)
        {
         int pP = (int)MathRound(100 * (bid - Dl) / (Pl - Dl));
         int pE = (int)MathRound(100 * ((bid < Eq) ? (bid - Dl) / (Eq - Dl) : (Pl - bid) / (Pl - Eq)));
         GDM::AddLine(L, K, StringFormat("PREMIUM %s dulu %d%% | DISCOUNT %s dulu %d%%", WV_Px(Pl), pP, WV_Px(Dl), 100 - pP), W);
         GDM::AddLine(L, K, StringFormat("EQUILIBRIUM %s dulu %d%% (sebelum %s)", WV_Px(Eq), pE, bid < Eq ? "Discount" : "Premium"), W);
         GDM::AddLine(L, K, "indikator / kombinasi menambah <= 1-2 poin", G);
        }
      else
         GDM::AddLine(L, K, bid >= Pl ? "harga di zona PREMIUM (di atas garis)" : "harga di zona DISCOUNT (di bawah garis)", G);
     }
   else
      GDM::AddLine(L, K, "range swing belum terbentuk (data kurang)", G);
   GDM::AddLine(L, K, StringFormat("-- GELOMBANG AWAL (BOS internal %s terbaru) --", WV_TfName()), clrLimeGreen);
   if(g_wvOk)
     {
      int s = g_wvSide;
      if(!g_wvClean) GDM::AddLine(L, K, "TIDAK BERSIH: pullback lewat awal gelombang", G);
      GDM::AddLine(L, K, StringFormat("%s %s | A $%.2f | batal %s%s", s > 0 ? "NAIK tembus" : "TURUN tembus", WV_Px(g_wvBrk), g_wvA,
                                      WV_Px(g_wvW1), g_wvInv ? " TERTEMBUS" : ""), g_wvInv ? clrDimGray : W);
      for(int k = 0; k < 5; k++)
        {
         double T = g_wvW1 + s * WV_K[k] * g_wvA, p = WV_P(bid, T);
         bool passed = (s * (g_wvC0 - T) >= 0), hit = !passed && (s * (g_wvExt - T) >= 0);
         GDM::AddLine(L, K, StringFormat("%-7s %s  sekarang %s | uji %d%%", WV_KN[k], WV_Px(T),
                                         passed ? "dilewati" : (hit ? "KENA" : (g_wvInv ? "batal" :
                                         StringFormat("%3d%%", (int)MathRound(MathMax(p, 0.0) * 100)))), WV_Uji(k)),
                      passed ? clrDimGray : (hit ? clrLime : clrDeepSkyBlue));
        }
     }
   else
      GDM::AddLine(L, K, "belum ada BOS internal di data chart", G);
   bool m1 = (_Period == PERIOD_M1);
   GDM::AddLine(L, K, m1 ? "-- UJI 2017-26 M1 (110 rb gelombang) --" : "-- UJI 2017-26 M5/M15 (~50 rb gelombang) --", clrLimeGreen);
   GDM::AddLine(L, K, StringFormat("sampai sebelum batal: 1.0A %d | 1.272A %d |", WV_Uji(0), WV_Uji(1)), W);
   GDM::AddLine(L, K, StringFormat("  1.618A %d | 2.0A %d | 2.618A %d (%%)", WV_Uji(2), WV_Uji(3), WV_Uji(4)), W);
   GDM::AddLine(L, K, m1 ? "gelombang berhenti: 25% < 0.92A | 50% < 1.50A" : "gelombang berhenti: 25% < 0.94A | 50% < 1.55A", W);
   GDM::AddLine(L, K, m1 ? "  | 75% < 3.0A | 90% < 7.4A (dari batal)" : "  | 75% < 3.1A | 90% < 6-7A (dari batal)", W);
   GDM::AddLine(L, K, m1 ? "M1 sekarang: tepat +-1 poin (4.1 jt cuplikan)" : "searah / melawan swing SAMA; 17-21 = 22-26", G);
   //--- uji maju akun ini
   WV_CsvStats();
   GDM::AddLine(L, K, StringFormat("-- UJI MAJU %s (gelombang.csv) --", WV_TfName()), clrLimeGreen);
   if(g_wvCsvRows == 0)
      GDM::AddLine(L, K, "belum ada gelombang selesai sejak dipasang", G);
   else
     {
      GDM::AddLine(L, K, StringFormat("%d gelombang | KENA / harapan:", g_wvCsvRows), W);
      GDM::AddLine(L, K, StringFormat("1.0A %d/%.1f | 1.272A %d/%.1f | 1.618A %d/%.1f", g_wvCsvK[0], g_wvCsvE[0], g_wvCsvK[1],
                                      g_wvCsvE[1], g_wvCsvK[2], g_wvCsvE[2]), W);
      GDM::AddLine(L, K, StringFormat("2.0A %d/%.1f | 2.618A %d/%.1f", g_wvCsvK[3], g_wvCsvE[3], g_wvCsvK[4], g_wvCsvE[4]), W);
     }
   GDM::AddLine(L, K, "= hitungan jarak (+-2): angka tepat, jejak", G);
   GDM::AddLine(L, K, "  institusi tidak terbukti. INFO peta.", G);
  }

#endif // GP_WAVE_MQH
