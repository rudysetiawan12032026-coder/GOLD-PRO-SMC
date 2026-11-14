//+------------------------------------------------------------------+
//|                                                   GP_GarisTg.mqh |
//| GoldPro - NOTIF TELEGRAM SENTUH ZONA GELOMBANG (15-16 Okt 2026).  |
//| Garis range swing Gelombang tiap TF (pivot swing 50, = Map\GP_Wave)|
//| PREMIUM = puncak - 0.05R (garis bawah kotak merah), EQUILIBRIUM =  |
//| 0.5R, DISCOUNT = dasar + 0.05R (garis atas kotak hijau); range >=  |
//| 2 ATR14. SENTUHAN = candle TF menyentuh garis dari sisi seberang   |
//| (close candle sebelumnya di sisi lain), maks 1 per 3 candle/garis. |
//| Hanya PINDAH ZONA (garis beda dari sentuhan sebelumnya; M1 ~23 /   |
//| hari). Chart utama saja, jalan walau tombol mati.                  |
//| 16 Okt (pengguna: "fokus ke tf m1 dan m5 ... ciri-ciri candle yg   |
//| close dan kembali / yg tembus, apakah cukup close 1 candle ditambah|
//| 2 candle selanjutnya? ini nanti yg jadi notifikasi, 2 tf ya"):     |
//| PESAN UTAMA sesudah candle sentuh + 2 candle berikut TUTUP (M1 &   |
//| M5): close tiap candle L (lewat garis, arah sentuh) / D (dalam =   |
//| kembali) -> pola 3 candle (LLL ... DDD) + peluang 1 ATR lanjut     |
//| tembus / balik dari close candle ke-3 (research\gel_candle3.py,    |
//| 2017-26: SEMUA pola 48-52%, = garis palsu; 1 / 2 / 3 candle sama   |
//| tidak menambah -> INFO, bukan sinyal). Pesan candle sentuh tutup   |
//| (1 candle), candle berjalan, konfirmasi 2 candle = input, mati.    |
//| M15 (bila dinyalakan) memakai pesan 1 candle (tabel 3 candle hanya |
//| M1 / M5). Uji maju: MQL5\Files\GoldPro\gelombang_pola.csv.         |
//| Tidak membuka order.                                               |
//+------------------------------------------------------------------+
#ifndef GP_GARISTG_MQH
#define GP_GARISTG_MQH

input group "=== GoldPro: Notif sentuh zona Gelombang (Telegram) ==="
input bool InpGTOn     = true;   // Kirim notif sentuh Premium / Equilibrium / Discount (chart utama, lewat EA GoldPro_Telegram)
input bool InpGTtfM1   = true;   // ... garis range M1 (pola 3 candle)
input bool InpGTtfM5   = true;   // ... garis range M5 (pola 3 candle)
input bool InpGTtfM15  = false;  // ... garis range M15 (pesan 1 candle)
input bool InpGTZona   = true;   // Hanya PINDAH ZONA (garis beda dari sentuhan sebelumnya); false = semua sentuhan
input bool InpGT1Candle = false; // Juga pesan saat candle SENTUH tutup (sebelum 2 candle berikut)
input bool InpGTAwal   = false;  // Juga pesan saat candle MASIH berjalan menyentuh
input bool InpGTKonf   = false;  // Juga pesan konfirmasi 2 candle
input bool InpGTLog    = true;   // Uji maju: catat SEMUA sentuhan ke MQL5\Files\GoldPro\gelombang_pola.csv

#define GT_NB   2000                                         // candle TF tutup yang dihitung (pivot swing 50)
#define GT_MAX  400
ENUM_TIMEFRAMES GT_TF[3] = {PERIOD_M1, PERIOD_M5, PERIOD_M15};
string GT_TFN[3] = {"M1", "M5", "M15"};
string GT_LN[3]  = {"PREMIUM", "EQUILIBRIUM", "DISCOUNT"};
string GT_TAG[3] = {"GZP", "GZE", "GZD"};
double GT_FR[3]  = {0.95, 0.5, 0.05};
string GT_M1N[7] = {"TEMBUS KUAT", "TEMBUS EKOR", "TEMBUS BIASA", "DOJI", "PIN BAR", "CANDLE BALIK", "COLEK BIASA"};
string GT_M1D[7] = {"close lewat garis, badan besar searah", "close lewat, ekor balik panjang", "close lewat garis", "badan sangat kecil",
                    "ekor lewat garis, close kembali", "close kembali, warna berlawanan", "menyentuh, close kembali"};
string GT_M2N[7] = {"LANJUT (close lebih jauh)", "RAGU (masih di luar)", "GAGAL (close kembali)", "TEMBUS TERTUNDA", "BALIK KONFIRMASI",
                    "BALIK LEMAH", "DIAM"};
//--- % TEMBUS dulu x10 1 / 2 candle (gel_candle.pkl, garis ASLI gabungan, kedua arah) [M1, M5, M15][model]; F = garis palsu
int GT_P1[3][7] = {{487, 503, 489, 505, 506, 511, 497}, {495, 500, 489, 508, 511, 519, 504}, {499, 530, 504, 515, 531, 517, 516}};
int GT_F1[3][7] = {{481, 493, 490, 505, 511, 516, 497}, {486, 481, 499, 499, 505, 520, 485}, {486, 501, 508, 501, 505, 495, 503}};
int GT_N1[3][7] = {{131364, 8674, 40854, 25743, 25423, 19731, 89855}, {23444, 1839, 9597, 5123, 5384, 3744, 20611},
                   {6977, 598, 3177, 1717, 1678, 1129, 6648}};
int GT_P2[3][7] = {{485, 497, 507, 484, 513, 503, 502}, {494, 500, 492, 495, 504, 510, 512}, {490, 508, 504, 493, 510, 529, 504}};
int GT_F2[3][7] = {{481, 496, 504, 485, 517, 499, 497}, {499, 502, 500, 488, 502, 494, 495}, {506, 519, 506, 494, 491, 501, 520}};
int GT_N2[3][7] = {{84026, 45000, 53961, 45338, 39737, 35561, 38168}, {16475, 8161, 10447, 9651, 8400, 8687, 7849},
                   {5112, 2494, 3092, 3065, 2553, 2881, 2505}};
//--- POLA 3 CANDLE (gel_candle3.pkl): indeks = 4 x (candle 1 lewat) + 2 x (candle 2 lewat) + (candle 3 lewat); % TEMBUS 1 ATR dulu
//    dari close candle ke-3 x10 [M1, M5][PREMIUM, EQUILIBRIUM, DISCOUNT][pola]; F = garis palsu [M1, M5][pola]
string GT_P3K[8] = {"DDD", "DDL", "DLD", "DLL", "LDD", "LDL", "LLD", "LLL"};
string GT_P3N[8] = {"3 close kembali (tolak bertahan)", "2 kembali, ke-3 lewat", "kembali-lewat-kembali", "kembali lalu 2 lewat",
                    "lewat lalu 2 kembali", "lewat-kembali-lewat", "2 lewat, ke-3 kembali", "3 close lewat (tembus bertahan)"};
int GT_P3[2][3][8] = {{{512, 486, 498, 491, 513, 492, 515, 489}, {507, 487, 501, 494, 505, 495, 510, 489}, {509, 497, 506, 484, 500, 486, 508, 488}},
                      {{508, 506, 496, 504, 487, 481, 509, 488}, {509, 498, 500, 493, 487, 486, 495, 504}, {507, 506, 505, 489, 496, 540, 485, 495}}};
int GT_N3[2][3][8] = {{{30047, 6376, 4206, 10524, 13087, 4681, 7802, 35202}, {39109, 8461, 5412, 13527, 15884, 5797, 9487, 41782},
                       {24356, 5119, 3359, 8308, 10656, 3798, 6190, 28605}},
                      {{6829, 1525, 924, 2391, 2607, 994, 1550, 7175}, {8475, 1786, 1153, 2870, 3092, 1184, 1784, 7772},
                       {5197, 1100, 662, 1640, 1911, 657, 1144, 5190}}};
int GT_F3[2][8] = {{505, 483, 502, 483, 507, 485, 510, 487}, {502, 487, 496, 483, 502, 497, 517, 501}};

struct GTEv
  {
   int      ti, ln, s, m1, m2, p3, r1, r3, prevL;            // r 0 belum, 1 TEMBUS, 2 BALIK, 3 HABIS, 4 keduanya di 1 candle M1
   datetime tk, rt1, rt3, prevT;                              // tk = jam buka candle sentuh (TF); prev = sentuhan garis sebelumnya
   double   lp, c, c2, c3, atr, top, bot;
   bool     has2, has3, pindah, want, sentR, logged;
  };
GTEv     g_gtEv[];
datetime g_gtLast[3];
bool     g_gtOk[3];
double   g_gtLv[3][3], g_gtCl[3], g_gtAtr[3];
bool     g_gtLvOk[3][3];
int      g_gtAgo[3][3];                                       // candle sejak sentuhan tercatat terakhir per garis (dari candle tutup terakhir)
int      g_gtPrev[3];                                         // garis sentuhan terakhir (0 / 1 / 2), -1 belum ada
datetime g_gtPrevT[3];
datetime g_gtStart = 0, g_gtM1 = 0;

bool GT_TfOn(int ti) { return ti == 0 ? InpGTtfM1 : (ti == 1 ? InpGTtfM5 : InpGTtfM15); }
bool GT_Use3(int ti) { return ti <= 1; }                     // tabel pola 3 candle tersedia (M1 / M5)
string GT_Pc(int v) { return DoubleToString(v / 10.0, 1); }
string GT_Dir(int s) { return s > 0 ? "naik dari bawah" : "turun dari atas"; }

//--- kirim sekali per (TF, garis, candle sentuh, tahap): kunci naik di GlobalVariable (ganti TF / chart utama pindah tidak dobel)
bool GT_Once(int ti, int ln, datetime tk, int stage)
  {
   string gv = "GP_GT_" + _Symbol + "_" + GT_TFN[ti] + "_" + IntegerToString(ln);
   double key = (double)tk * 10.0 + stage;
   if(GlobalVariableCheck(gv) && GlobalVariableGet(gv) >= key) return false;
   GlobalVariableSet(gv, key);
   return true;
  }
void GT_Out(string tag, string text)
  {
   datetime t = iTime(_Symbol, PERIOD_M1, 1);                             // jam candle M1 tutup terakhir = urutan kunci KB_Out
   if(t > 0) KB_Out(t, tag, text);
  }

//--- model candle (urutan & ambang = gel_candle.py)
int GT_Model1(double o, double h, double l, double c, double lp, int s)
  {
   double rng = MathMax(h - l, 1e-9), ab = MathAbs(c - o);
   int colr = (c > o) ? s : ((c < o) ? -s : 0);
   bool beyond = s * (c - lp) > 0;
   double wk = (s > 0) ? h - MathMax(o, c) : MathMin(o, c) - l;           // ekor di sisi arah sentuh
   if(ab <= 0.1 * rng) return 3;
   if(beyond && colr > 0 && ab >= 0.6 * rng) return 0;
   if(beyond && wk >= 0.5 * rng) return 1;
   if(beyond) return 2;
   if(wk >= 0.6 * rng) return 4;
   if(colr < 0 && ab >= 0.5 * rng) return 5;
   return 6;
  }
int GT_Model2(double c, double h, double l, double c2, double lp, int s)
  {
   if(s * (c - lp) > 0)
     {
      if(s * (c2 - lp) <= 0) return 2;
      if(s * (c2 - c) > 0) return 0;
      return 1;
     }
   if(s * (c2 - lp) > 0) return 3;
   if(s * (c2 - c) < 0 && s * (c2 - (s > 0 ? l : h)) < 0) return 4;
   if(s * (c2 - c) < 0) return 5;
   return 6;
  }
int GT_Pola3(double c1, double c2, double c3, double lp, int s)
  {
   return (s * (c1 - lp) > 0 ? 4 : 0) + (s * (c2 - lp) > 0 ? 2 : 0) + (s * (c3 - lp) > 0 ? 1 : 0);
  }

int GT_Find(int ti, int ln, datetime tk)
  {
   for(int i = 0; i < ArraySize(g_gtEv); i++)
      if(g_gtEv[i].ti == ti && g_gtEv[i].ln == ln && g_gtEv[i].tk == tk) return i;
   return -1;
  }
int GT_Add(const GTEv &e)
  {
   int n = ArraySize(g_gtEv);
   if(n >= GT_MAX)
     {
      int drop = 0;
      for(int i = 0; i < n; i++) if(g_gtEv[i].logged) { drop = i; break; }
      for(int i = drop + 1; i < n; i++) g_gtEv[i - 1] = g_gtEv[i];
      n--;
     }
   ArrayResize(g_gtEv, n + 1);
   g_gtEv[n] = e;
   return n;
  }

string GT_Zone(const GTEv &e) { return StringFormat("%s %s", GT_LN[e.ln], KB_Px(e.lp)); }
string GT_Prev(const GTEv &e)
  {
   return GT_Dir(e.s) + (e.prevL >= 0 ? StringFormat(" | sebelumnya %s %s", GT_LN[e.prevL], GP_LocalTime(e.prevT)) : "");
  }
//--- 15 Okt malam (research\gel_arah.py: sampai garis PREMIUM / DISCOUNT / EQUILIBRIUM dulu = hitungan jarak): baris peluang dari harga
//    px. EQUILIBRIUM -> Premium dulu vs Discount dulu; PREMIUM / DISCOUNT -> kembali ke Equilibrium dulu vs ujung range dulu.
string GT_Range(const GTEv &e, double px)
  {
   double R = e.top - e.bot;
   if(R <= 0) return "";
   double Pl = e.top - 0.05 * R, Dl = e.bot + 0.05 * R, Eq = e.bot + 0.5 * R;
   if(e.ln == 1)
     {
      double p = MathMax(0.0, MathMin(1.0, (px - Dl) / (Pl - Dl)));
      return StringFormat("^dari sini (jarak): PREMIUM dulu %d%% | DISCOUNT dulu %d%%", (int)MathRound(100 * p), 100 - (int)MathRound(100 * p));
     }
   double ext = (e.ln == 0) ? e.top : e.bot, dX = MathAbs(ext - px), dE = MathAbs(px - Eq);
   if((e.ln == 0 && px >= ext) || (e.ln == 2 && px <= ext)) return StringFormat("^close sudah lewat %s range", e.ln == 0 ? "puncak" : "dasar");
   int pE = (int)MathRound(100 * dX / MathMax(dX + dE, 1e-9));
   return StringFormat("^dari sini (jarak): EQUILIBRIUM %s dulu %d%% | %s %s dulu %d%%", KB_Px(Eq), pE, e.ln == 0 ? "puncak" : "dasar",
                       KB_Px(ext), 100 - pE);
  }
string GT_RangeLine(const GTEv &e)
  {
   return StringFormat("^range %s %s - %s ($%.2f) | 1 ATR $%.2f", GT_TFN[e.ti], KB_Px(e.bot), KB_Px(e.top), e.top - e.bot, e.atr);
  }
//--- pesan 1 candle (candle sentuh tutup) - opsional di M1 / M5, utama di M15
void GT_Stage2(const GTEv &e)
  {
   int ti = e.ti, m = e.m1, p = GT_P1[ti][m];
   string s = StringFormat("menyentuh %s | candle %s %s tutup", GT_Zone(e), GT_TFN[ti], GP_LocalTime(e.tk));
   s += "^" + GT_Prev(e);
   s += StringFormat("^candle: %s - %s", GT_M1N[m], GT_M1D[m]);
   s += StringFormat("^lanjut tembus ke %s: %s%% | balik ke %s: %s%%", KB_Px(e.c + e.s * e.atr), GT_Pc(p), KB_Px(e.c - e.s * e.atr),
                     GT_Pc(1000 - p));
   s += GT_Range(e, e.c) + GT_RangeLine(e);
   GT_Out(GT_TAG[e.ln], s);
  }
//--- (opsional) konfirmasi 2 candle
void GT_Stage3(const GTEv &e)
  {
   int ti = e.ti, m = e.m2, p = GT_P2[ti][m];
   string s = StringFormat("konfirmasi %s | candle %s %s tutup", GT_Zone(e), GT_TFN[ti], GP_LocalTime(e.tk + PeriodSeconds(GT_TF[ti])));
   s += StringFormat("^candle berikut: %s (sentuh: %s)", GT_M2N[m], GT_M1N[e.m1]);
   s += StringFormat("^lanjut tembus ke %s: %s%% | balik ke %s: %s%%", KB_Px(e.c2 + e.s * e.atr), GT_Pc(p), KB_Px(e.c2 - e.s * e.atr),
                     GT_Pc(1000 - p));
   GT_Out("GTK", s);
  }
//--- PESAN UTAMA M1 / M5: candle sentuh + 2 candle berikut TUTUP -> pola 3 candle
string GT_LD(double c, const GTEv &e) { return StringFormat("%s %s", e.s * (c - e.lp) > 0 ? "L" : "D", KB_Px(c)); }
void GT_Stage4(const GTEv &e)
  {
   int ti = e.ti, q = e.p3, p = GT_P3[ti][e.ln][q], psec = PeriodSeconds(GT_TF[ti]);
   string s = StringFormat("%s | 3 candle %s %s-%s tutup", GT_Zone(e), GT_TFN[ti], GP_LocalTime(e.tk), GP_LocalTime(e.tk + 2 * psec));
   s += "^" + GT_Prev(e);
   s += StringFormat("^close: %s > %s > %s = %s %s", GT_LD(e.c, e), GT_LD(e.c2, e), GT_LD(e.c3, e), GT_P3K[q], GT_P3N[q]);
   s += StringFormat("^lanjut tembus ke %s: %s%% | balik ke %s: %s%%", KB_Px(e.c3 + e.s * e.atr), GT_Pc(p), KB_Px(e.c3 - e.s * e.atr),
                     GT_Pc(1000 - p));
   s += StringFormat("^uji 2017-26 n %d | garis palsu %s%% (L = close lewat garis, D = kembali)", GT_N3[ti][e.ln][q], GT_Pc(GT_F3[ti][q]));
   s += GT_Range(e, e.c3) + GT_RangeLine(e);
   GT_Out(GT_TAG[e.ln], s);
  }

//--- hitung ulang range & sentuhan tiap candle TF baru tutup
bool GT_Compute(int ti)
  {
   ENUM_TIMEFRAMES tf = GT_TF[ti];
   datetime tb = iTime(_Symbol, tf, 1);
   if(tb == 0) return false;
   if(tb == g_gtLast[ti]) return g_gtOk[ti];
   MqlRates r[];
   int n = CopyRates(_Symbol, tf, 1, GT_NB, r);                          // candle tutup, terlama dulu
   if(n < 400 || r[n - 1].time != tb) return false;                       // data belum lengkap: coba lagi nanti
   WVPiv ps[];
   WV_Pivots(r, n, 50, ps);
   double top[], bot[], atr[], tr[];
   ArrayResize(top, n); ArrayResize(bot, n); ArrayResize(atr, n); ArrayResize(tr, n);
   double tp = -1, bt = -1, sum = 0;
   int q = 0, nps = ArraySize(ps);
   for(int t = 0; t < n; t++)
     {
      while(q < nps && ps[q].t == t) { if(ps[q].kind > 0) tp = ps[q].px; else bt = ps[q].px; q++; }
      if(tp < 0 || r[t].high > tp) tp = r[t].high;
      if(bt < 0 || r[t].low < bt) bt = r[t].low;
      top[t] = tp; bot[t] = bt;
      double pc = (t > 0) ? r[t - 1].close : r[t].close;
      tr[t] = MathMax(r[t].high - r[t].low, MathMax(MathAbs(r[t].high - pc), MathAbs(r[t].low - pc)));
      sum += tr[t];
      if(t >= 14) sum -= tr[t - 14];
      atr[t] = (t >= 13) ? sum / 14.0 : 0;
     }
   int lastK[3] = {-100, -100, -100}, prv = -1;
   datetime prvT = 0;
   datetime old = TimeCurrent() - 86400;
   for(int k = 300; k < n; k++)
      for(int L = 0; L < 3; L++)
        {
         double R0 = top[k - 1] - bot[k - 1];
         if(!(R0 > 0) || atr[k - 1] <= 0 || R0 < 2 * atr[k - 1]) continue;
         double lp = bot[k - 1] + GT_FR[L] * R0;
         int s = 0;
         if(r[k - 1].close < lp && r[k].high >= lp) s = 1;
         else if(r[k - 1].close > lp && r[k].low <= lp) s = -1;
         if(s == 0 || k - lastK[L] < 3) continue;
         lastK[L] = k;
         bool pindah = (prv >= 0 && prv != L);                            // garis beda dari sentuhan sebelumnya
         int pL = prv;
         datetime pT = prvT;
         prv = L; prvT = r[k].time;
         if(r[k].time < old) continue;
         int i = GT_Find(ti, L, r[k].time);
         if(i < 0)
           {
            GTEv e;
            e.ti = ti; e.ln = L; e.s = s; e.tk = r[k].time; e.lp = lp; e.c = r[k].close; e.atr = atr[k]; e.top = top[k - 1]; e.bot = bot[k - 1];
            e.m1 = GT_Model1(r[k].open, r[k].high, r[k].low, r[k].close, lp, s);
            e.m2 = -1; e.p3 = -1; e.c2 = 0; e.c3 = 0; e.has2 = false; e.has3 = false; e.r1 = 0; e.r3 = 0; e.rt1 = 0; e.rt3 = 0;
            e.sentR = false; e.logged = false;
            e.pindah = pindah; e.prevL = pL; e.prevT = pT; e.want = !InpGTZona || pindah;
            i = GT_Add(e);
           }
         if(!g_gtEv[i].has2 && k + 1 < n)
           {
            g_gtEv[i].c2 = r[k + 1].close; g_gtEv[i].has2 = true;
            g_gtEv[i].m2 = GT_Model2(r[k].close, r[k].high, r[k].low, r[k + 1].close, lp, s);
           }
         if(!g_gtEv[i].has3 && k + 2 < n)
           {
            g_gtEv[i].c3 = r[k + 2].close; g_gtEv[i].has3 = true;
            g_gtEv[i].p3 = GT_Pola3(r[k].close, r[k + 1].close, r[k + 2].close, lp, s);
           }
         //--- pesan hanya untuk sentuhan terbaru yang dikirim (pindah zona / semua)
         if(!g_gtEv[i].want) continue;
         bool use3 = GT_Use3(ti);
         if((!use3 || InpGT1Candle) && k >= n - 2 && GT_Once(ti, L, r[k].time, 2)) GT_Stage2(g_gtEv[i]);
         if(InpGTKonf && k == n - 2 && GT_Once(ti, L, r[k].time, 3)) GT_Stage3(g_gtEv[i]);
         if(use3 && k == n - 3 && GT_Once(ti, L, r[k].time, 4)) GT_Stage4(g_gtEv[i]);
        }
   //--- garis untuk candle berjalan (dari candle tutup terakhir) & jarak dari sentuhan terakhir per garis
   double R1 = top[n - 1] - bot[n - 1];
   for(int L = 0; L < 3; L++)
     {
      g_gtLvOk[ti][L] = (R1 > 0 && atr[n - 1] > 0 && R1 >= 2 * atr[n - 1]);
      g_gtLv[ti][L] = bot[n - 1] + GT_FR[L] * R1;
      g_gtAgo[ti][L] = (n - 1) - lastK[L];
     }
   g_gtPrev[ti] = prv; g_gtPrevT[ti] = prvT;
   g_gtCl[ti] = r[n - 1].close; g_gtAtr[ti] = atr[n - 1];
   g_gtLast[ti] = tb; g_gtOk[ti] = true;
   return true;
  }

//--- (opsional, default mati) candle TF berjalan menyentuh garis
void GT_Touch(int ti)
  {
   ENUM_TIMEFRAMES tf = GT_TF[ti];
   datetime t0 = iTime(_Symbol, tf, 0);
   if(t0 <= g_gtLast[ti]) return;
   double h0 = iHigh(_Symbol, tf, 0), l0 = iLow(_Symbol, tf, 0);
   if(h0 <= 0 || l0 <= 0) return;
   for(int L = 0; L < 3; L++)
     {
      bool pindah = (g_gtPrev[ti] >= 0 && g_gtPrev[ti] != L);
      if(InpGTZona && !pindah) continue;
      if(!g_gtLvOk[ti][L] || g_gtAgo[ti][L] + 1 < 3) continue;
      double lp = g_gtLv[ti][L];
      int s = 0;
      if(g_gtCl[ti] < lp && h0 >= lp) s = 1;
      else if(g_gtCl[ti] > lp && l0 <= lp) s = -1;
      if(s == 0 || !GT_Once(ti, L, t0, 1)) continue;
      string str = StringFormat("sedang menyentuh %s %s | candle %s %s belum tutup", GT_LN[L], KB_Px(lp), GT_TFN[ti], GP_LocalTime(t0));
      str += StringFormat("^%s | pola & peluang dikirim sesudah candle tutup", GT_Dir(s));
      GT_Out("GTS", str);
     }
  }

//--- hasil: 1 ATR ke arah TEMBUS / BALIK dulu (candle M1, sama dengan riset; berhenti sebelum jeda harian 23:55 server / 24 jam)
int GT_Race(datetime from, double base, double d, int s, datetime &rt)
  {
   rt = 0;
   datetime to = iTime(_Symbol, PERIOD_M1, 1);
   if(to < from) return 0;
   MqlRates m[];
   int n = CopyRates(_Symbol, PERIOD_M1, from, to, m);
   if(n <= 0) return 0;
   double up = base + d, dn = base - d;
   for(int j = 0; j < n; j++)
     {
      MqlDateTime x;
      TimeToStruct(m[j].time, x);
      if((x.hour == 23 && x.min >= 55) || (j > 0 && m[j].time - m[j - 1].time > 3600) || j >= 1440)
        { rt = (j > 0) ? m[j - 1].time : m[j].time; return 3; }
      bool a = m[j].high >= up, b = m[j].low <= dn;
      if(a && b) { rt = m[j].time; return 4; }
      if(a) { rt = m[j].time; return s > 0 ? 1 : 2; }
      if(b) { rt = m[j].time; return s > 0 ? 2 : 1; }
     }
   return 0;
  }
string GT_RTxt(int r)
  {
   if(r == 1) return "TEMBUS";
   if(r == 2) return "BALIK";
   if(r == 3) return "HABIS (jeda harian / 24 jam)";
   if(r == 4) return "keduanya dalam 1 candle M1 (tidak dinilai)";
   return "belum";
  }

void GT_Log(const GTEv &e)
  {
   if(!InpGTLog || MQLInfoInteger(MQL_TESTER)) return;
   FolderCreate("GoldPro");
   string fn = "GoldPro\\gelombang_pola.csv";
   bool isNew = !FileIsExist(fn);
   int fh = FileOpen(fn, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ, ';');
   if(fh == INVALID_HANDLE) return;
   FileSeek(fh, 0, SEEK_END);
   if(isNew)
      FileWrite(fh, "sentuh_wita", "tf", "zona", "arah", "pindah", "dikirim", "harga_garis", "atr", "model_tutup", "tembus_pct1", "hasil_1",
                "waktu_hasil_1", "pola3", "tembus_pct3", "palsu_pct3", "hasil_3", "waktu_hasil_3");
   bool u3 = GT_Use3(e.ti) && e.p3 >= 0;
   FileWrite(fh, KB_WitaFull(e.tk), GT_TFN[e.ti], GT_LN[e.ln], e.s > 0 ? "naik" : "turun", e.pindah ? 1 : 0, e.want ? 1 : 0,
             DoubleToString(e.lp, _Digits), DoubleToString(e.atr, 2), GT_M1N[e.m1], GT_Pc(GT_P1[e.ti][e.m1]), GT_RTxt(e.r1),
             e.rt1 > 0 ? KB_WitaFull(e.rt1) : "", e.p3 >= 0 ? GT_P3K[e.p3] : "", u3 ? GT_Pc(GT_P3[e.ti][e.ln][e.p3]) : "",
             u3 ? GT_Pc(GT_F3[e.ti][e.p3]) : "", GT_RTxt(e.r3), e.rt3 > 0 ? KB_WitaFull(e.rt3) : "");
   FileClose(fh);
  }

//--- hasil 1 ATR dari close candle sentuh (r1) & dari close candle ke-3 (r3 = peluang pesan utama M1 / M5)
void GT_Results()
  {
   for(int i = 0; i < ArraySize(g_gtEv); i++)
     {
      if(!g_gtEv[i].has3 || g_gtEv[i].logged) continue;
      int psec = PeriodSeconds(GT_TF[g_gtEv[i].ti]);
      datetime rt;
      if(g_gtEv[i].r1 == 0)
        {
         g_gtEv[i].r1 = GT_Race(g_gtEv[i].tk + psec, g_gtEv[i].c, g_gtEv[i].atr, g_gtEv[i].s, rt);
         g_gtEv[i].rt1 = rt;
        }
      if(g_gtEv[i].r3 == 0)
        {
         g_gtEv[i].r3 = GT_Race(g_gtEv[i].tk + 3 * psec, g_gtEv[i].c3, g_gtEv[i].atr, g_gtEv[i].s, rt);
         g_gtEv[i].rt3 = rt;
        }
      GTEv e = g_gtEv[i];
      bool u3 = GT_Use3(e.ti);
      int rr = u3 ? e.r3 : e.r1;
      datetime rtt = u3 ? e.rt3 : e.rt1;
      bool quiet = (rr != 0 && rtt + 60 <= g_gtStart);                    // sudah selesai sebelum modul ini jalan (dimuat ulang)
      if(rr != 0 && !e.sentR)
        {
         g_gtEv[i].sentR = true;
         if(!quiet && e.want)
           {
            string tag = (rr == 1) ? "GTT" : ((rr == 2) ? "GTB" : "GTH");
            double base = u3 ? e.c3 : e.c;
            string s = StringFormat("hasil %s %s: %s", GT_TFN[e.ti], GT_Zone(e), GT_RTxt(rr));
            if(rr <= 2) s += StringFormat(" ke %s (%d mnt)", KB_Px(base + (rr == 1 ? e.s : -e.s) * e.atr),
                                          (int)((rtt + 60 - (e.tk + (u3 ? 3 : 1) * psec)) / 60));
            s += u3 ? StringFormat("^sentuh %s %s, pola %s (peluang tembus %s%%)", GP_LocalTime(e.tk), GT_Dir(e.s), GT_P3K[e.p3],
                                   GT_Pc(GT_P3[e.ti][e.ln][e.p3]))
                    : StringFormat("^sentuh %s %s, candle %s (peluang tembus %s%%)", GP_LocalTime(e.tk), GT_Dir(e.s), GT_M1N[e.m1],
                                   GT_Pc(GT_P1[e.ti][e.m1]));
            GT_Out(tag, s);
           }
        }
      if(e.r1 != 0 && e.r3 != 0)
        {
         g_gtEv[i].logged = true;
         if(!quiet) GT_Log(g_gtEv[i]);
        }
     }
   //--- buang kejadian selesai > 2 hari
   datetime old = TimeCurrent() - 2 * 86400;
   for(int i = ArraySize(g_gtEv) - 1; i >= 0; i--)
      if(g_gtEv[i].logged && g_gtEv[i].tk < old) ArrayRemove(g_gtEv, i, 1);
  }

void GT_Update()
  {
   if(!InpGTOn || !g_gpMaster || MQLInfoInteger(MQL_TESTER)) return;
   if(g_gtStart == 0) { g_gtStart = TimeCurrent(); ArrayInitialize(g_gtPrev, -1); }
   for(int ti = 0; ti < 3; ti++)
     {
      if(!GT_TfOn(ti)) continue;
      if(GT_Compute(ti) && InpGTAwal) GT_Touch(ti);
     }
   datetime m1 = iTime(_Symbol, PERIOD_M1, 1);
   if(m1 > 0 && m1 != g_gtM1) { g_gtM1 = m1; GT_Results(); }
  }

#endif // GP_GARISTG_MQH
