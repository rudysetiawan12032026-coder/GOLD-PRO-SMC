//+------------------------------------------------------------------+
//|                                                 GP_ZoneWatch.mqh |
//| GoldPro - DETEKTOR ZONA OB / BREAKER / FVG SEMUA TF (tombol "Zona")|
//| 7 Okt 2026, permintaan pengguna: "detektor di chart, satu tombol   |
//| khusus mengawasi harga di sistem OB & FVG di semua TF termasuk M1, |
//| dashboard interaktif yang paling banyak bernarasi".                |
//| Versi 2 (7 Okt, dari screenshot pengguna): lebar teks diukur piksel|
//| (TextGetSize) + bungkus kata, dashboard naik ke depan bila objek   |
//| lain baru dibuat, tabel 1 baris/TF, kalimat lebih pendek, FVG hanya|
//| diceritakan TF >= M15, zona AKTIF = belum terisi 90% (sama dengan  |
//| mesin SMC; dulu dibuang setelah sentuhan pertama selesai).         |
//|                                                                  |
//| Deteksi = replika persis GoldPro sesudah audit 30 Sep (fractal 5,  |
//| BOS/CHoCH swing terbaru, OB = candle berlawanan di asal leg, FVG   |
//| 3 candle >= 0.05 ATR, Breaker = OB terisi 90% lalu close tembus),   |
//| dijalankan sendiri untuk M1/M5/M15/H1/H4.                          |
//| Angka peluang = research\smc_break.py (2017-26, stabil latih/uji): |
//|  - sentuhan pertama: lanjut tren >= 1 ATR 51-81% menurut TEBAL zona |
//|  - 1 close di luar tepi jauh: palsu 10-31% (OB) / 13-42% (FVG)     |
//|  - 2 close 15/20%; 3 close 11/15%; sumbu lewat close di dalam ->   |
//|    lanjut 48% (OB) / 59% (FVG)                                    |
//| Zona acak setebal sama memberi angka yang SAMA (geometri): peta     |
//| perilaku harga, BUKAN bukti OB memantulkan harga.                  |
//+------------------------------------------------------------------+
#ifndef GP_ZONEWATCH_MQH
#define GP_ZONEWATCH_MQH

input group "=== GoldPro: Detektor Zona OB/FVG (tombol Zona) ==="
input bool InpZWM1            = true;   // Awasi M1
input bool InpZWM5            = true;   // Awasi M5
input bool InpZWM15           = true;   // Awasi M15
input bool InpZWH1            = true;   // Awasi H1
input bool InpZWH4            = true;   // Awasi H4
input int  InpZWFvgStoryMinTF = 15;     // FVG diceritakan hanya untuk TF >= x menit (FVG kecil sangat sering)
input bool InpZWDraw          = true;   // Gambar OB/Breaker TF lain di chart (kotak putus-putus + label TF) saat dashboard tampil
input int  InpZWAlertMinTF    = 15;     // Alert sentuhan & close tembus zona untuk TF >= x menit (0 = tanpa alert)
input int  InpZWFont          = 8;      // Ukuran huruf dashboard
input int  InpZWMaxWidthPct   = 48;     // Lebar maks dashboard (% lebar chart)
input bool InpZWLeft          = true;   // Dashboard di KIRI (kanan kolom tombol, bawah label LIVE); false = kanan atas

#define ZW_PFX   "GPZ_"
#define ZW_NTF   5
#define ZW_LB    5
#define ZW_MAXEV 40

ENUM_TIMEFRAMES ZW_TF[ZW_NTF] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4};
string          ZW_TN[ZW_NTF] = {"M1", "M5", "M15", "H1", "H4"};
int             ZW_MIN[ZW_NTF] = {1, 5, 15, 60, 240};
int             ZW_BARS[ZW_NTF] = {1500, 1200, 800, 600, 400};
int             ZW_LIFE[ZW_NTF] = {600, 600, 300, 150, 100};       // umur episode sentuhan pertama (candle TF)

struct ZWZone
  {
   int      tfi, kind;        // kind 0 OB, 1 Breaker, 2 FVG
   bool     bull;             // true = zona BAWAH (support, tren naik)
   double   top, bot, atr, fill;
   datetime born, t0;         // candle lahir / candle awal gambar
   bool     choch, sweep, fvg, act;
   int      st;               // 0 belum disentuh, 1 sedang diuji, 2 bertahan (lanjut 1 ATR), 3 tembus sungguhan, 9 lewat
   int      run;              // close beruntun di luar tepi jauh (s/d candle tutup terakhir)
   bool     liveT;            // sentuhan sudah dinarasikan live (dalam candle berjalan)
   string   key;
  };
struct ZWEvent
  {
   datetime t;
   string   txt;
   color    clr;
  };
ZWZone   g_zw[];
ZWEvent  g_zwEv[];
string   g_zwKeys[];
datetime g_zwBarT[ZW_NTF];
datetime g_zwLast[ZW_NTF];
bool     g_zwInit[ZW_NTF];
bool     g_zwCompact = false, g_zwRaise = false, g_zwEvOn = false;
uint     g_zwRaiseTick = 0;
string   g_zwL[], g_zwT[];
color    g_zwC[];

//--- tabel peluang (research\smc_break.py, smc_break_mql.txt). grup 0 = OB+Breaker, 1 = FVG
double ZW_LAN[2][8] = {{0.513, 0.561, 0.594, 0.630, 0.664, 0.711, 0.744, 0.813},
                       {0.526, 0.568, 0.608, 0.646, 0.681, 0.731, 0.749, 0.847}};   // tebal 0-.25-.5-.75-1-1.5-2-3+ ATR
double ZW_PAL[2][8] = {{0.309, 0.308, 0.283, 0.269, 0.215, 0.195, 0.137, 0.100},
                       {0.419, 0.404, 0.357, 0.359, 0.272, 0.249, 0.163, 0.135}};   // [lewat <.1/.1-.3/.3-.6/>.6 ATR][badan <0.7 / >=0.7]
double ZW_OTH[2][4] = {{0.150, 0.108, 0.638, 0.480},
                       {0.204, 0.148, 0.674, 0.588}};                               // palsu2, palsu3, retest1, sapu->lanjut

//--- (kotak sideway dipindah ke tombol khusus "Kotak Sideway" - Signal\GP_BoxWatch.mqh, 8 Okt 2026)

bool ZW_On(int i)
  {
   if(i == 0) return InpZWM1;
   if(i == 1) return InpZWM5;
   if(i == 2) return InpZWM15;
   if(i == 3) return InpZWH1;
   return InpZWH4;
  }
int    ZW_Grp(const ZWZone &z)  { return z.kind == 2 ? 1 : 0; }
string ZW_Kind(const ZWZone &z) { return z.kind == 2 ? "FVG" : (z.kind == 1 ? "Breaker" : "OB"); }
string ZW_Side(const ZWZone &z) { return z.bull ? "bwh" : "ats"; }
string ZW_Rng(const ZWZone &z)                                   // "4154.2-61.6" (digit depan yg sama tidak diulang)
  {
   string a = DoubleToString(z.bot, 1), b = DoubleToString(z.top, 1);
   int la = StringLen(a);
   if(la == StringLen(b) && la > 4 && StringSubstr(a, 0, la - 4) == StringSubstr(b, 0, la - 4)) b = StringSubstr(b, la - 4);
   return a + "-" + b;
  }
string ZW_Name(const ZWZone &z) { return ZW_Kind(z) + " " + ZW_Side(z) + " " + ZW_Rng(z); }
int    ZW_Pct(double p)          { return (int)MathRound(100.0 * p); }
bool   ZW_Story(const ZWZone &z) { return z.kind != 2 || ZW_MIN[z.tfi] >= InpZWFvgStoryMinTF; }

double ZW_PLanjut(const ZWZone &z)
  {
   double h = (z.atr > 0) ? (z.top - z.bot) / z.atr : 1.0;
   double e[7] = {0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0};
   int b = 0;
   while(b < 7 && h > e[b]) b++;
   return ZW_LAN[ZW_Grp(z)][b];
  }
double ZW_PPalsu1(const ZWZone &z, double beyondAtr, double bodyAtr)
  {
   int b = (beyondAtr < 0.1) ? 0 : (beyondAtr < 0.3 ? 1 : (beyondAtr < 0.6 ? 2 : 3));
   return ZW_PAL[ZW_Grp(z)][b * 2 + (bodyAtr >= 0.7 ? 1 : 0)];
  }

void ZW_Event(string key, datetime t, string txt, color c, int tfi, bool alertable)
  {
   for(int i = ArraySize(g_zwKeys) - 1; i >= 0; i--)
      if(g_zwKeys[i] == key) return;
   int nk = ArraySize(g_zwKeys);
   if(nk >= 600)                                             // buang 200 kunci tertua (geser manual)
     {
      for(int i = 200; i < nk; i++) g_zwKeys[i - 200] = g_zwKeys[i];
      nk -= 200; ArrayResize(g_zwKeys, nk);
     }
   ArrayResize(g_zwKeys, nk + 1); g_zwKeys[nk] = key;
   int n = ArraySize(g_zwEv);
   if(n >= ZW_MAXEV)                                         // buang kejadian tertua
     {
      for(int i = 1; i < n; i++) g_zwEv[i - 1] = g_zwEv[i];
      n--; ArrayResize(g_zwEv, n);
     }
   ArrayResize(g_zwEv, n + 1);
   g_zwEv[n].t = t; g_zwEv[n].txt = txt; g_zwEv[n].clr = c;
   for(int j = n; j > 0 && g_zwEv[j].t < g_zwEv[j - 1].t; j--)      // urut waktu (TF besar tutup belakangan)
     {
      ZWEvent tmp = g_zwEv[j]; g_zwEv[j] = g_zwEv[j - 1]; g_zwEv[j - 1] = tmp;
     }
   if(alertable && InpZWAlertMinTF > 0 && ZW_MIN[tfi] >= InpZWAlertMinTF)
      GP_Notify("zw" + key, "ZONA " + txt, t);
  }

//--- bangun ulang zona satu TF (replay candle demi candle) + narasi kejadian di candle yang baru tutup
bool ZW_Build(int tfi)
  {
   ENUM_TIMEFRAMES tf = ZW_TF[tfi];
   MqlRates r[];
   int got = CopyRates(_Symbol, tf, 0, ZW_BARS[tfi], r);
   if(got < 80) return false;
   int n = got - 1;                                         // candle terakhir masih berjalan -> 0..n-1 sudah tutup
   double atr[], tr[]; bool isH[], isL[];
   ArrayResize(atr, n); ArrayResize(tr, n); ArrayResize(isH, n); ArrayResize(isL, n);
   for(int i = 0; i < n; i++)                                // ATR14 = rata2 true range 14 candle (sama dgn riset)
     {
      tr[i] = r[i].high - r[i].low;
      if(i > 0) tr[i] = MathMax(tr[i], MathMax(MathAbs(r[i].high - r[i - 1].close), MathAbs(r[i].low - r[i - 1].close)));
      atr[i] = 0.0;
      if(i >= 13) { double s_ = 0; for(int q = i - 13; q <= i; q++) s_ += tr[q]; atr[i] = s_ / 14.0; }
      isH[i] = false; isL[i] = false;
     }
   for(int i = ZW_LB; i < n - ZW_LB; i++)
     {
      bool h = true, l = true;
      for(int q = 1; q <= ZW_LB && (h || l); q++)
        {
         if(r[i].high <= r[i - q].high || r[i].high <= r[i + q].high) h = false;
         if(r[i].low >= r[i - q].low || r[i].low >= r[i + q].low) l = false;
        }
      isH[i] = h; isL[i] = l;
     }
   ZWZone Z[];
   int bi[];                                                // indeks candle lahir tiap zona
   int nz = 0;
   //--- OB dari BOS / CHoCH
   double hp = 0, lp = 0; int hi = -1, li = -1; bool hb = true, lb = true; int prev = 0;
   for(int ref = 2 * ZW_LB + 15; ref < n; ref++)
     {
      int c_ = ref - ZW_LB;
      if(isH[c_]) { hp = r[c_].high; hi = c_; hb = false; }
      if(isL[c_]) { lp = r[c_].low;  li = c_; lb = false; }
      int ev = 0, sw = -1;
      if(hi >= 0 && !hb && r[ref].close > hp)      { hb = true; ev = 1;  sw = hi; }
      else if(li >= 0 && !lb && r[ref].close < lp) { lb = true; ev = -1; sw = li; }
      if(ev == 0 || atr[ref] <= 0) continue;
      bool choch = (prev != 0 && ev != prev); prev = ev;
      int org = ref - 1;
      for(int q = ref - 1; q >= sw; q--)
         if(ev > 0 ? r[q].low < r[org].low : r[q].high > r[org].high) org = q;
      int k = -1;
      for(int q = org; q >= MathMax(org - 5, 0); q--)
        {
         bool bc = r[q].close > r[q].open;
         if((ev > 0 && !bc) || (ev < 0 && bc)) { k = q; break; }
        }
      if(k < 0) continue;
      bool dup = false;
      for(int q = 0; q < nz; q++)
         if(Z[q].kind == 0 && Z[q].t0 == r[k].time && Z[q].bull == (ev > 0)) { dup = true; break; }
      if(dup) continue;
      double top = (ev > 0) ? r[k].high : MathMax(r[k].high, r[org].high);
      double bot = (ev > 0) ? MathMin(r[k].low, r[org].low) : r[k].low;
      if(top <= bot) continue;
      bool sweep = false;
      for(int q = org - 1; q >= MathMax(0, org - 300); q--)
         if(ev > 0 ? isL[q] : isH[q]) { sweep = (ev > 0) ? r[org].low < r[q].low : r[org].high > r[q].high; break; }
      ArrayResize(Z, nz + 1); ArrayResize(bi, nz + 1); bi[nz] = ref;
      Z[nz].tfi = tfi; Z[nz].kind = 0; Z[nz].bull = (ev > 0); Z[nz].top = top; Z[nz].bot = bot; Z[nz].atr = atr[ref];
      Z[nz].born = r[ref].time; Z[nz].t0 = r[k].time; Z[nz].choch = choch; Z[nz].sweep = sweep; Z[nz].fvg = false;
      Z[nz].st = 0; Z[nz].run = 0; Z[nz].liveT = false; Z[nz].fill = 0; Z[nz].act = true;
      nz++;
     }
   //--- FVG (+ tandai OB yang punya FVG searah antara candle OB & candle tembus)
   int nOB = nz;
   for(int i = 16; i < n; i++)
     {
      if(atr[i] <= 0) continue;
      bool up = (r[i].low > r[i - 2].high && r[i].low - r[i - 2].high >= 0.05 * atr[i]);
      bool dn = (r[i].high < r[i - 2].low && r[i - 2].low - r[i].high >= 0.05 * atr[i]);
      if(!up && !dn) continue;
      ArrayResize(Z, nz + 1); ArrayResize(bi, nz + 1); bi[nz] = i;
      Z[nz].tfi = tfi; Z[nz].kind = 2; Z[nz].bull = up; Z[nz].atr = atr[i];
      Z[nz].top = up ? r[i].low : r[i - 2].low; Z[nz].bot = up ? r[i - 2].high : r[i].high;
      Z[nz].born = r[i].time; Z[nz].t0 = r[i - 1].time; Z[nz].choch = false; Z[nz].sweep = false; Z[nz].fvg = true;
      Z[nz].st = 0; Z[nz].run = 0; Z[nz].liveT = false; Z[nz].fill = 0; Z[nz].act = true;
      for(int q = 0; q < nOB; q++)
         if(Z[q].bull == up && r[i - 1].time >= Z[q].t0 && r[i - 1].time <= Z[q].born) Z[q].fvg = true;
      nz++;
     }
   //--- BREAKER dari OB: terisi >= 90% lalu ada CLOSE di luar sisi jauh -> fungsi terbalik
   int life = ZW_LIFE[tfi];
   for(int q = 0; q < nOB; q++)
     {
      double h = Z[q].top - Z[q].bot; int km = -1, kb = -1;
      for(int j = bi[q] + 1; j < n; j++)
        {
         if(km < 0 && (Z[q].bull ? r[j].low <= Z[q].top - 0.9 * h : r[j].high >= Z[q].bot + 0.9 * h)) km = j;
         if(km >= 0 && (Z[q].bull ? r[j].close < Z[q].bot : r[j].close > Z[q].top)) { kb = j; break; }
        }
      if(kb < 0 || atr[kb] <= 0) continue;
      ArrayResize(Z, nz + 1); ArrayResize(bi, nz + 1);
      Z[nz] = Z[q];
      Z[nz].kind = 1; Z[nz].bull = !Z[q].bull; Z[nz].born = r[kb].time; Z[nz].atr = atr[kb];
      Z[nz].st = 0; Z[nz].run = 0; Z[nz].liveT = false; Z[nz].fill = 0; Z[nz].act = true;
      bi[nz] = kb;
      nz++;
     }
   //--- status zona (terisi berapa %, sama dgn mesin SMC) + episode sentuhan pertama + narasi candle baru
   datetime lastDone = g_zwLast[tfi];
   string tn = ZW_TN[tfi];
   for(int q = 0; q < nz; q++)
     {
      Z[q].key = tn + "_" + IntegerToString(Z[q].kind) + (Z[q].bull ? "b" : "s") + IntegerToString((long)Z[q].born);
      for(int p = ArraySize(g_zw) - 1; p >= 0; p--)                       // bawa status "sudah dinarasikan live"
         if(g_zw[p].key == Z[q].key) { Z[q].liveT = g_zw[p].liveT; break; }
      int b0 = bi[q];
      bool bull = Z[q].bull; int s = bull ? 1 : -1;
      double U = Z[q].atr, hgt = Z[q].top - Z[q].bot;
      double prox = bull ? Z[q].top : Z[q].bot, dist = bull ? Z[q].bot : Z[q].top;
      double cont = prox + s * U, brk = dist - s * U;
      double fill = 0;                                                     // terisi dari sisi datang (maks), >= 90% = termitigasi
      for(int j = b0 + 1; j < n; j++)
        {
         double pen = bull ? Z[q].top - r[j].low : r[j].high - Z[q].bot;
         if(pen > 0) fill = MathMax(fill, MathMin(1.0, pen / hgt));
         if(fill >= 0.9) break;
        }
      Z[q].fill = fill; Z[q].act = (fill < 0.9);
      bool story = ZW_Story(Z[q]);
      if(Z[q].kind != 2 && r[b0].time > lastDone)
         ZW_Event(Z[q].key + "N", r[b0].time, StringFormat("%s %s BARU %s (%.1f ATR, %s%s%s): bila disentuh %s ~%d%%", tn, ZW_Kind(Z[q]) + " " + ZW_Side(Z[q]),
                  ZW_Rng(Z[q]), hgt / U, Z[q].choch ? "CHoCH" : "BOS", Z[q].fvg ? ", +FVG" : "", Z[q].sweep ? ", sapu likuiditas" : "",
                  bull ? "naik" : "turun", ZW_Pct(ZW_PLanjut(Z[q]))), clrSilver, tfi, false);
      int jt = -1, nOut = 0; bool wick = false;
      int jEnd = MathMin(n - 1, b0 + life);
      for(int j = b0 + 1; j <= jEnd; j++)
        {
         bool narrate = story && r[j].time > lastDone;
         if(Z[q].st == 0)
           {
            if(!(bull ? r[j].low <= Z[q].top : r[j].high >= Z[q].bot)) continue;
            if(bull ? r[j].open < Z[q].bot : r[j].open > Z[q].top) { Z[q].st = 9; break; }   // buka melompati zona
            Z[q].st = 1; jt = j;
            if(narrate && !Z[q].liveT)
               ZW_Event(Z[q].key + "T", r[j].time, StringFormat("%s MASUK %s: lanjut %s 1 ATR %d%% | tembus %d%%", tn, ZW_Name(Z[q]),
                        bull ? "naik" : "turun", ZW_Pct(ZW_PLanjut(Z[q])), 100 - ZW_Pct(ZW_PLanjut(Z[q]))), clrGold, tfi, true);
            Z[q].liveT = true;
           }
         bool hitBrk  = bull ? r[j].low <= brk : r[j].high >= brk;
         bool hitCont = (j > jt) && (bull ? r[j].high >= cont : r[j].low <= cont);
         bool closeOut = bull ? r[j].close < dist : r[j].close > dist;
         bool wickOut  = bull ? r[j].low < dist : r[j].high > dist;
         if(closeOut)
           {
            Z[q].run++; nOut++;
            if(narrate && Z[q].run == 1)
              {
               double by = s * (dist - r[j].close) / U, bd = MathAbs(r[j].close - r[j].open) / U;
               double pp = ZW_PPalsu1(Z[q], by, bd);
               ZW_Event(Z[q].key + "B1_" + IntegerToString((long)r[j].time), r[j].time,
                        StringFormat("%s CLOSE TEMBUS %s (lewat %.2f ATR, badan %s): tembus ~%d%% | palsu %d%% | retest tepi ~%d%%",
                                     tn, ZW_Name(Z[q]), by, bd >= 0.7 ? "besar" : "kecil", 100 - ZW_Pct(pp), ZW_Pct(pp),
                                     ZW_Pct(ZW_OTH[ZW_Grp(Z[q])][2])), clrTomato, tfi, true);
              }
            else if(narrate && (Z[q].run == 2 || Z[q].run == 3))
               ZW_Event(Z[q].key + "B" + IntegerToString(Z[q].run), r[j].time,
                        StringFormat("%s %d close beruntun di luar %s: tembus ~%d%% | palsu %d%%", tn, Z[q].run, ZW_Name(Z[q]),
                                     100 - ZW_Pct(ZW_OTH[ZW_Grp(Z[q])][Z[q].run - 2]), ZW_Pct(ZW_OTH[ZW_Grp(Z[q])][Z[q].run - 2])), clrTomato, tfi, false);
           }
         else
           {
            if(Z[q].run > 0 && narrate)
               ZW_Event(Z[q].key + "R" + IntegerToString((long)r[j].time), r[j].time,
                        StringFormat("%s close KEMBALI masuk %s (%d candle di luar, calon tembus palsu)", tn, ZW_Name(Z[q]), Z[q].run),
                        clrLimeGreen, tfi, false);
            Z[q].run = 0;
            if(wickOut && !wick && nOut == 0)
              {
               wick = true;
               if(narrate && !hitBrk)                                     // candle yg sama sudah lewat 1 ATR -> cerita TEMBUS saja
                  ZW_Event(Z[q].key + "S", r[j].time, StringFormat("%s sumbu lewat %s, close di dalam: lanjut %d%% | tembus %d%%",
                           tn, ZW_Name(Z[q]), ZW_Pct(ZW_OTH[ZW_Grp(Z[q])][3]), 100 - ZW_Pct(ZW_OTH[ZW_Grp(Z[q])][3])), clrOrange, tfi, false);
              }
           }
         if(hitBrk && (!hitCont || closeOut))
           {
            Z[q].st = 3;
            if(narrate)
               ZW_Event(Z[q].key + "X", r[j].time, StringFormat("%s %s TEMBUS SUNGGUHAN (lewat 1 ATR, %d candle%s)", tn, ZW_Name(Z[q]), j - jt,
                        closeOut ? "" : "; hanya sumbu, close di dalam"), clrRed, tfi, false);
            break;
           }
         if(hitCont)
           {
            Z[q].st = 2;
            if(narrate)
               ZW_Event(Z[q].key + "L", r[j].time, StringFormat("%s %s BERTAHAN: %s 1 ATR (%d candle%s)", tn, ZW_Name(Z[q]),
                        bull ? "naik" : "turun", j - jt, nOut > 0 ? StringFormat(", setelah %d close di luar = tembus palsu", nOut) : ""),
                        clrLimeGreen, tfi, false);
            break;
           }
        }
     }
   //--- ganti zona TF ini di daftar global: zona AKTIF (belum terisi 90%) + yang sedang diuji
   ZWZone keep[];
   int nk = 0;
   for(int p = 0; p < ArraySize(g_zw); p++)
      if(g_zw[p].tfi != tfi) { ArrayResize(keep, nk + 1); keep[nk++] = g_zw[p]; }
   ArrayResize(g_zw, 0);
   for(int p = 0; p < nk; p++) { int m = ArraySize(g_zw); ArrayResize(g_zw, m + 1); g_zw[m] = keep[p]; }
   for(int q = 0; q < nz; q++)
      if(Z[q].act || Z[q].st == 1) { int m = ArraySize(g_zw); ArrayResize(g_zw, m + 1); g_zw[m] = Z[q]; }
   g_zwLast[tfi] = r[n - 1].time;
   return true;
  }

//--- sentuhan LIVE (dalam candle berjalan): narasi langsung saat harga masuk zona aktif yang belum disentuh
void ZW_LiveTouch()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0) return;
   for(int q = 0; q < ArraySize(g_zw); q++)
     {
      if(g_zw[q].st != 0 || g_zw[q].liveT || !g_zw[q].act) continue;
      if(!(g_zw[q].bull ? bid <= g_zw[q].top : bid >= g_zw[q].bot)) continue;
      g_zw[q].liveT = true;
      if(!ZW_Story(g_zw[q])) continue;
      double pl = ZW_PLanjut(g_zw[q]);
      ZW_Event(g_zw[q].key + "T", TimeCurrent(), StringFormat("%s MASUK %s SEKARANG: lanjut %s 1 ATR %d%% | tembus %d%%",
               ZW_TN[g_zw[q].tfi], ZW_Name(g_zw[q]), g_zw[q].bull ? "naik" : "turun", ZW_Pct(pl), 100 - ZW_Pct(pl)), clrGold, g_zw[q].tfi, true);
     }
  }

//--- zona AKTIF terdekat satu TF, satu jenis (0 = OB/Breaker, 1 = FVG), satu sisi; -1 = tidak ada
int ZW_Nearest(int tfi, int grp, bool bull, double bid)
  {
   int best = -1; double bd = DBL_MAX;
   for(int q = 0; q < ArraySize(g_zw); q++)
     {
      if(g_zw[q].tfi != tfi || ZW_Grp(g_zw[q]) != grp || g_zw[q].bull != bull || !g_zw[q].act) continue;
      if(bull && bid < g_zw[q].bot) continue;              // harga sudah di bawah zona bawah -> bukan "di bawah harga"
      if(!bull && bid > g_zw[q].top) continue;
      double d = MathMax(0.0, bull ? bid - g_zw[q].top : g_zw[q].bot - bid);
      if(d < bd) { bd = d; best = q; }
     }
   return best;
  }

string ZW_StTxt(const ZWZone &z)
  {
   if(z.st == 0) return "belum disentuh";
   if(z.st == 1) return "sedang diuji";
   if(z.st == 2) return "sudah diuji, bertahan";
   return "sudah diuji";
  }

//--- sel tabel: "-4.2$ 55%" / "DALAM" / "-"; tanda * = Breaker
string ZW_Cell(int q, double bid)
  {
   if(q < 0) return "-";
   double d = g_zw[q].bull ? bid - g_zw[q].top : g_zw[q].bot - bid;
   string mk = (g_zw[q].kind == 1) ? "*" : "";
   if(d <= 0) return "DALAM" + mk;
   double p = (TT_MarketOpen() && g_ttAdr > 0) ? TT_P(d, 60) : -1;
   return StringFormat("%s%.1f$%s%s", g_zw[q].bull ? "-" : "+", d, mk, p >= 0 ? " " + TT_Pct(p) : "");
  }
string ZW_CellTip(int q, string lab)
  {
   if(q < 0) return lab + ": tidak ada";
   return StringFormat("%s: %s %s-%s (tebal %.1f ATR, terisi %d%%, %s)", lab, ZW_Kind(g_zw[q]), DoubleToString(g_zw[q].bot, 2),
                       DoubleToString(g_zw[q].top, 2), (g_zw[q].top - g_zw[q].bot) / g_zw[q].atr, ZW_Pct(g_zw[q].fill), ZW_StTxt(g_zw[q]));
  }

//--- ukur & bungkus teks dalam PIKSEL (huruf sama dgn label: Consolas). Label MT5 ikut skala layar Windows (DPI):
//    screenshot 7 Okt (skala ~125%) teks 20-25% lebih lebar dari ukuran TextGetSize -> dikali DPI/96.
double ZW_Scale() { long dpi = TerminalInfoInteger(TERMINAL_SCREEN_DPI); return (dpi > 96) ? dpi / 96.0 : 1.0; }
int ZW_W(string s)
  {
   uint w = 0, h = 0;
   TextSetFont("Consolas", -10 * MathMax(7, InpZWFont));
   TextGetSize(s, w, h);
   return (int)MathCeil(w * ZW_Scale());
  }
int ZW_MaxW()
  {
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   return (int)MathMax(260, MathMin(620, cw * MathMax(25, MathMin(80, InpZWMaxWidthPct)) / 100.0));
  }
//--- OBJ_LABEL MT5 hanya menampilkan 63 karakter (sisanya dibuang; screenshot 7 Okt "close di dalam: l") -> maks 62/baris
#define ZW_MAXCH 62
void ZW_Line(string s, color c, string tip = "")
  {
   int n = ArraySize(g_zwL);
   ArrayResize(g_zwL, n + 1); ArrayResize(g_zwC, n + 1); ArrayResize(g_zwT, n + 1);
   g_zwL[n] = StringSubstr(s, 0, ZW_MAXCH); g_zwC[n] = c; g_zwT[n] = tip;
  }
void ZW_Wrap(string s, color c, string tip = "")
  {
   int mw = ZW_MaxW() - 12;
   if(ZW_W(s) <= mw && StringLen(s) <= ZW_MAXCH) { ZW_Line(s, c, tip); return; }
   string w[];
   int nw = StringSplit(s, ' ', w);
   string cur = "";
   for(int i = 0; i < nw; i++)
     {
      string nx = (cur == "") ? w[i] : cur + " " + w[i];
      if(cur != "" && (ZW_W(nx) > mw || StringLen(nx) > ZW_MAXCH))
        {
         ZW_Line(cur, c, tip);
         cur = "   " + w[i];
        }
      else cur = nx;
     }
   if(cur != "") ZW_Line(cur, c, tip);
  }

void ZW_BuildLines()
  {
   ArrayResize(g_zwL, 0); ArrayResize(g_zwC, 0); ArrayResize(g_zwT, 0);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string tfs = "";
   for(int i = 0; i < ZW_NTF; i++) if(ZW_On(i)) tfs += " " + ZW_TN[i];
   ZW_Line("ZONA OB/FVG" + tfs + (g_zwCompact ? "  [klik: lengkap]" : "  [klik: ringkas]"), clrSilver);
   //--- SEKARANG: harga di dalam zona mana / terdekat
   string inside = "";
   int nIn = 0;
   for(int i = ZW_NTF - 1; i >= 0; i--)
      for(int q = 0; q < ArraySize(g_zw); q++)
        {
         if(g_zw[q].tfi != i || !g_zw[q].act || bid < g_zw[q].bot || bid > g_zw[q].top) continue;
         if(nIn < 3)
            inside += (nIn > 0 ? ", " : "") + ZW_Kind(g_zw[q]) + " " + ZW_Side(g_zw[q]) + " " + ZW_TN[i] +
                      StringFormat(" (%s %d%%)", g_zw[q].bull ? "naik" : "turun", ZW_Pct(ZW_PLanjut(g_zw[q])));
         nIn++;
        }
   if(nIn > 0)
      ZW_Wrap("DI DALAM: " + inside + (nIn > 3 ? StringFormat(" +%d lagi", nIn - 3) : ""), clrGold,
              "Harga sekarang di dalam zona ini. Angka = peluang lanjut tren 1 ATR bila ini sentuhan pertama (menurut tebal zona).");
   else
     {
      int bq = -1, aq = -1; double bd = DBL_MAX, ad = DBL_MAX;
      for(int q = 0; q < ArraySize(g_zw); q++)
        {
         if(!g_zw[q].act) continue;
         if(g_zw[q].bull && bid > g_zw[q].top && bid - g_zw[q].top < bd) { bd = bid - g_zw[q].top; bq = q; }
         if(!g_zw[q].bull && bid < g_zw[q].bot && g_zw[q].bot - bid < ad) { ad = g_zw[q].bot - bid; aq = q; }
        }
      string sb = (bq >= 0) ? ZW_Kind(g_zw[bq]) + " " + ZW_TN[g_zw[bq].tfi] + " " + ZW_Cell(bq, bid) : "-";
      string sa = (aq >= 0) ? ZW_Kind(g_zw[aq]) + " " + ZW_TN[g_zw[aq].tfi] + " " + ZW_Cell(aq, bid) : "-";
      ZW_Wrap("DI LUAR zona | terdekat bwh " + sb + " | ats " + sa, clrWhite,
              ZW_CellTip(bq, "Terdekat di bawah") + "\n" + ZW_CellTip(aq, "Terdekat di atas"));
     }
   if(!g_zwCompact)
     {
      ZW_Line("TF  OB bwh | ats      FVG bwh | ats", clrDimGray,
              "Tiap sel: jarak harga ke tepi zona ($) + peluang harga DATANG dalam 1 jam (model waktu GoldPro).\n"
              "DALAM = harga di dalam zona. * = Breaker. Arahkan mouse ke baris TF untuk rentang harga, tebal, % terisi & status.");
      for(int i = 0; i < ZW_NTF; i++)
        {
         if(!ZW_On(i)) continue;
         int ob = ZW_Nearest(i, 0, true, bid), oa = ZW_Nearest(i, 0, false, bid);
         int fb = ZW_Nearest(i, 1, true, bid), fa = ZW_Nearest(i, 1, false, bid);
         string tn = ZW_TN[i];
         while(StringLen(tn) < 3) tn += " ";
         ZW_Line(tn + " " + ZW_Cell(ob, bid) + " | " + ZW_Cell(oa, bid) + "   FVG " + ZW_Cell(fb, bid) + " | " + ZW_Cell(fa, bid), clrWhite,
                 ZW_TN[i] + "\n" + ZW_CellTip(ob, "OB bawah") + "\n" + ZW_CellTip(oa, "OB atas") + "\n" + ZW_CellTip(fb, "FVG bawah") + "\n" +
                 ZW_CellTip(fa, "FVG atas"));
        }
     }
   ZW_Line("-- cerita (" + InpLocalTZName + ") --", clrDimGray);
   int ne = ArraySize(g_zwEv), show = g_zwCompact ? 3 : 6;
   if(ne == 0) ZW_Line("(belum ada kejadian sejak dipasang)", clrDimGray);
   for(int i = ne - 1; i >= 0 && i >= ne - show; i--)
      ZW_Wrap(GP_LocalTime(g_zwEv[i].t) + " " + g_zwEv[i].txt, g_zwEv[i].clr);
   ZW_Line("INFO perilaku harga (zona acak = angka sama), bukan sinyal", clrDimGray,
           "Peluang dari uji 2017-26 (research\\smc_break.py), stabil 2017-21 & 2022-26.\n"
           "Sentuhan pertama: lanjut tren 1 ATR 51-81% menurut tebal zona. 1 close di luar tepi jauh: biasanya tembus sungguhan\n"
           "(OB 69-90%, makin jauh close lewat & makin besar badan makin pasti). Sumbu lewat tapi close di dalam: lanjut 48% (OB).\n"
           "Zona acak setebal sama memberi angka yang sama -> ini peta perilaku, bukan bukti OB memantulkan harga.");
  }

void ZW_Label(string n, int x, int y, string s, color c, int fs, string tip)
  {
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_ZORDER, 21);
      ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, n, OBJPROP_TEXT, s == "" ? " " : s);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, fs);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, tip == "" ? "Detektor zona OB/FVG GoldPro - klik judul = ringkas / lengkap" : tip);
  }

void ZW_Draw()
  {
   int n = ArraySize(g_zwL);
   if(n < 1) return;
   int fs = MathMax(7, InpZWFont);
   uint tw = 0, th = 0;
   TextSetFont("Consolas", -10 * fs);
   TextGetSize("Ag", tw, th);
   int lh = (int)MathCeil(th * ZW_Scale()) + 3, w = 0;
   for(int i = 0; i < n; i++) w = MathMax(w, ZW_W(g_zwL[i]));
   w += 12;
   int h = n * lh + 8;
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int x0, y0;
   if(InpZWLeft)                                                          // KIRI (7 Okt: jangan tutupi ujung chart yg berjalan)
     {
      x0 = (DMInpButtons ? GDM::BtnColR() : 0) + 8;
      y0 = GDM::PanelTop() + (DMInpButtons ? BTN_H + 12 : 8);             // di bawah label LIVE
      if(GDM::g_vPanel) x0 = MathMax(x0, GDM::g_panR + 10);              // panel halaman terbuka -> di kanannya
      string cid = IntegerToString(ChartID());
      if(GDM::g_vTrade && GlobalVariableCheck("GP_EAPW_" + cid) && GlobalVariableGet("GP_EAPH_" + cid) > 0)
         x0 = MathMax(x0, GDM::BtnColR() + 6 + (int)GlobalVariableGet("GP_EAPW_" + cid) + 10);   // panel Trade EA terbuka
     }
   else
     {
      y0 = 22;
      if(GDM::g_vNews && ObjectFind(0, "GPN_BG") >= 0)                    // di bawah dashboard Berita
         y0 = (int)ObjectGetInteger(0, "GPN_BG", OBJPROP_YDISTANCE) + (int)ObjectGetInteger(0, "GPN_BG", OBJPROP_YSIZE) + 8;
      x0 = MathMax(4, cw - w - 6);
     }
   string bg = ZW_PFX + "BG";
   if(ObjectFind(0, bg) < 0)
     {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, bg, OBJPROP_ZORDER, 20);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'16,22,28');
      ObjectSetString(0, bg, OBJPROP_TOOLTIP, "Detektor zona OB/FVG GoldPro - klik = ringkas / lengkap");
     }
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x0 - 4);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y0 - 4);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, w + 2);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, C'0,120,120');
   for(int i = 0; i < n; i++)
      ZW_Label(ZW_PFX + "L" + IntegerToString(i), x0 + 2, y0 + i * lh, g_zwL[i], g_zwC[i], fs, g_zwT[i]);
   for(int i = n; ObjectFind(0, ZW_PFX + "L" + IntegerToString(i)) >= 0; i++)
      ObjectDelete(0, ZW_PFX + "L" + IntegerToString(i));
  }

//--- kotak putus-putus OB/Breaker AKTIF terdekat tiap sisi (TF selain TF chart) + label TF; dipindah, tidak dibuat ulang
void ZW_DrawZones()
  {
   if(!InpZWDraw) { ObjectsDeleteAll(0, ZW_PFX + "Z"); return; }
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   datetime t2 = TimeCurrent() + PeriodSeconds(PERIOD_CURRENT) * 8;
   for(int i = 0; i < ZW_NTF; i++)
      for(int sd = 0; sd < 2; sd++)
        {
         string n = ZW_PFX + "Z" + IntegerToString(i) + (sd == 0 ? "b" : "s"), tl = n + "T";
         int q = (ZW_On(i) && ZW_TF[i] != (ENUM_TIMEFRAMES)_Period) ? ZW_Nearest(i, 0, sd == 0, bid) : -1;   // TF chart: mesin SMC
         if(q < 0) { ObjectDelete(0, n); ObjectDelete(0, tl); continue; }
         color c = g_zw[q].bull ? C'40,170,110' : C'210,80,80';
         if(ObjectFind(0, n) < 0)
           {
            ObjectCreate(0, n, OBJ_RECTANGLE, 0, g_zw[q].t0, g_zw[q].top, t2, g_zw[q].bot);
            ObjectSetInteger(0, n, OBJPROP_STYLE, STYLE_DOT);
            ObjectSetInteger(0, n, OBJPROP_FILL, false);
            ObjectSetInteger(0, n, OBJPROP_BACK, true);
            ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
           }
         ObjectMove(0, n, 0, g_zw[q].t0, g_zw[q].top);
         ObjectMove(0, n, 1, t2, g_zw[q].bot);
         ObjectSetInteger(0, n, OBJPROP_COLOR, c);
         ObjectSetString(0, n, OBJPROP_TOOLTIP, ZW_TN[i] + " " + ZW_CellTip(q, ZW_Kind(g_zw[q]) + " " + (g_zw[q].bull ? "bawah" : "atas")) +
                         StringFormat("\nbila disentuh pertama: lanjut %s 1 ATR ~%d%% (= zona acak setebal sama)", g_zw[q].bull ? "naik" : "turun",
                                      ZW_Pct(ZW_PLanjut(g_zw[q]))));
         if(ObjectFind(0, tl) < 0)
           {
            ObjectCreate(0, tl, OBJ_TEXT, 0, t2, g_zw[q].bull ? g_zw[q].top : g_zw[q].bot);
            ObjectSetInteger(0, tl, OBJPROP_FONTSIZE, 7);
            ObjectSetInteger(0, tl, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, tl, OBJPROP_HIDDEN, true);
           }
         ObjectMove(0, tl, 0, t2, g_zw[q].bull ? g_zw[q].top : g_zw[q].bot);
         ObjectSetString(0, tl, OBJPROP_TEXT, (g_zw[q].kind == 1 ? "BRK " : "OB ") + ZW_TN[i]);
         ObjectSetInteger(0, tl, OBJPROP_COLOR, c);
         ObjectSetInteger(0, tl, OBJPROP_ANCHOR, g_zw[q].bull ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
        }
  }

//--- dipanggil timer (tiap 2 dtk): bangun ulang TF yang punya candle baru, sentuhan live, gambar bila tombol aktif
void ZW_Update()
  {
   if(MQLInfoInteger(MQL_TESTER)) return;
   if(!g_zwEvOn)                                       // tahu saat objek lain dibuat -> dashboard naik ke depan
     {
      ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);
      g_zwEvOn = true;
     }
   for(int i = 0; i < ZW_NTF; i++)
     {
      if(!ZW_On(i)) continue;
      datetime t0 = iTime(_Symbol, ZW_TF[i], 0);
      if(t0 == 0 || t0 == g_zwBarT[i]) continue;
      bool first_ = !g_zwInit[i];
      if(first_) { g_zwLast[i] = TimeCurrent() - MathMax(3 * 3600, 6 * PeriodSeconds(ZW_TF[i])); }   // pertama: cerita 3 jam terakhir
      if(ZW_Build(i))
        {
         g_zwBarT[i] = t0; g_zwInit[i] = true;
         if(first_)                                                   // catatan sekali per TF (cek dari log)
           {
            int nOB = 0, nF = 0, nT = 0;
            for(int q = 0; q < ArraySize(g_zw); q++)
               if(g_zw[q].tfi == i && g_zw[q].act) { if(g_zw[q].kind == 2) nF++; else nOB++; if(g_zw[q].st == 1) nT++; }
            PrintFormat("[GoldPro ZoneWatch] %s: zona aktif OB/Breaker %d, FVG %d (sedang diuji %d) | kejadian tercatat %d",
                        ZW_TN[i], nOB, nF, nT, ArraySize(g_zwEv));
           }
        }
     }
   ZW_LiveTouch();
   if(!GDM::g_vZone)
     {
      if(ObjectFind(0, ZW_PFX + "BG") >= 0) ObjectsDeleteAll(0, ZW_PFX);
      return;
     }
   if(g_zwRaise && GetTickCount() - g_zwRaiseTick > 20000)   // objek lain baru dibuat -> buat ulang agar di depan (maks 1x/20 dtk)
     {
      g_zwRaise = false;
      g_zwRaiseTick = GetTickCount();
      ObjectDelete(0, ZW_PFX + "BG");
      ObjectsDeleteAll(0, ZW_PFX + "L");
     }
   ZW_BuildLines();
   ZW_Draw();
   ZW_DrawZones();
  }

void ZW_ChartEvent(const int id, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CREATE)
     {
      // dikecualikan: milik sendiri (GPZ_), panel EA (GPT_, EA juga naik ke depan -> jangan saling dorong), tombol/probe/PIN
      // (GPB_, probe dibuat ulang tiap gerak mouse), dashboard Berita (GPN_, di tempat lain)
      if(StringFind(sparam, ZW_PFX) != 0 && StringFind(sparam, "GPT_") != 0 && StringFind(sparam, "GPB_") != 0 &&
         StringFind(sparam, "GPN_") != 0 && StringFind(sparam, "GPK_") != 0) g_zwRaise = true;   // GPK_ = dashboard Kotak Sideway
      return;
     }
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == "GPB_B_zone" && GDM::g_vZone)
     {
      ZW_Update();
      ChartRedraw();
      return;
     }
   if(!GDM::g_vZone) return;
   if(id == CHARTEVENT_OBJECT_CLICK && (sparam == ZW_PFX + "L0" || sparam == ZW_PFX + "BG"))
     {
      g_zwCompact = !g_zwCompact;
      ObjectDelete(0, ZW_PFX + "BG");
      ObjectsDeleteAll(0, ZW_PFX + "L");
      ZW_BuildLines(); ZW_Draw();
      ChartRedraw();
     }
   else if(id == CHARTEVENT_CHART_CHANGE)
     {
      ZW_BuildLines(); ZW_Draw();
     }
  }

void ZW_Deinit(bool isFinal)
  {
   if(isFinal) ObjectsDeleteAll(0, ZW_PFX);
  }

#endif // GP_ZONEWATCH_MQH
