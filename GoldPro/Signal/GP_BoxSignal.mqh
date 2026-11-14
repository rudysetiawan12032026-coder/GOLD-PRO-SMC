//+------------------------------------------------------------------+
//| GP_BoxSignal.mqh - Sinyal KOTAK SMC (dealing range) di M5 & M1    |
//|                                                                  |
//| Arah IKUT TEMBUS (keputusan pengguna 29 Sep 2026, berdasar uji):  |
//|  harga menyentuh ujung ATAS kotak  -> BUY  (stop di garis atas)   |
//|  harga menyentuh garis BAWAH kotak -> SELL (stop di garis bawah)  |
//|  TP = SL = k x ATR14 TF sinyal. Sekali per kotak per sisi.        |
//| Kotak = replika SMC_Structure (fractal 5 kiri/kanan, high         |
//| didahulukan, terkonfirmasi 5 candle kemudian) + SMC_Zones (leg    |
//| TERBARU >= ATR14 rata2 TR, fallback high/low 10 swing terakhir),  |
//| dihitung sendiri utk M5 & M1 - tidak bergantung TF chart.         |
//| Uji research\box_scalp2.py (hasil dinilai di M1, spread asli):    |
//|  fade di ujung kotak menang 38-44% SETIAP tahun -> ikut tembus    |
//|  57-63%. Net setelah spread: negatif 2016-22, ~0 2023-24, positif |
//|  2025 (+0.10R) & 2026 (+0.14R) M5 k=1, M1 2026 +0.11R. Belum      |
//|  termasuk slippage stop order -> [HIPOTESIS], dipantau jurnal.    |
//+------------------------------------------------------------------+
#ifndef GP_BOXSIGNAL_MQH
#define GP_BOXSIGNAL_MQH

//--- 29 Sep malam: uji dengan entry realistis -> ujung kotak TIDAK memberi keunggulan (tembus ~52%, balik ~48%).
//    Keputusan pengguna: tab 3 = PETA INFO saja, tanpa arah BUY/SELL, alert sinyal mati. Nama input diganti agar
//    chart lama yang menyimpan alert = true ikut memakai default baru (mati).
input group "=== GoldPro: Kotak SMC M5 & M1 (info) ==="
input bool   InpBoxSignals = true;    // Hitung kotak SMC M5 & M1 (peta info tab 3, tanpa arah)
input double InpBoxK       = 1.0;     // (riset) jarak TP/SL uji = k x ATR14, hanya untuk jurnal
input bool   InpBoxTouchM5 = false;   // Alert info saat harga menyentuh garis kotak M5 (tanpa arah)
input bool   InpBoxTouchM1 = false;   // Alert info saat harga menyentuh garis kotak M1 (tanpa arah, ramai)
input bool   InpBoxDraw    = true;    // Gambar garis kotak M5/M1 saat tab "3 KOTAK" aktif
input bool   InpBoxAlertChg= false;   // Alert saat kotak M5 BERUBAH (~40x/hari)

#define BX_LB  5
#define BX_PFX "GPX_"
#define BX_JRN "GoldDayMap\\journal_box.csv"

struct BxBox
  {
   bool              valid;
   double            hi, lo, atr;
  };
struct BxSig
  {
   int               tf;       // 0 = M5, 1 = M1
   datetime          t;        // candle TF sinyal saat garis disentuh
   int               dir;      // +1 BUY (tembus atas), -1 SELL (tembus bawah)
   double            entry, tp, sl, atr, spr;
   int               result;   // -1 jalan, 1 kena TP, 2 kena SL
   datetime          tRes;
  };

BxBox    g_bxBox[2];
BxSig    g_bxSig[];
datetime g_bxBar[2] = {0, 0};
double   g_bxKH[2][2], g_bxKL[2][2];   // kotak terakhir yang sudah memicu, per TF [0/1] per sisi [0 atas / 1 bawah]
bool     g_bxDraw = false;               // diset panel GoldPro: tab 3 aktif
string   g_bxLogged[];                   // sinyal yang sudah dicatat di jurnal (sesi ini)
datetime g_bxSince[2] = {0, 0};          // candle sejak kotak sekarang berlaku (berubah ~ tiap swing baru terkonfirmasi)
double   g_bxPrevHi[2] = {0, 0}, g_bxPrevLo[2] = {0, 0};   // kotak sebelumnya (untuk panel & alert perubahan)
bool     g_bxAlertOwner = false;         // hanya SATU chart per simbol yang mengirim alert kotak
double   g_bxToken = 0;

//--- kunci alert antar-chart (GoldPro di beberapa chart -> alert tidak dobel). Atomik via SetOnCondition;
//    bila chart pemilik ditutup, chart lain mengambil alih pada alert berikutnya.
bool BxAlertOwner()
  {
   if(g_bxAlertOwner || MQLInfoInteger(MQL_TESTER))
      return g_bxAlertOwner;
   string gv = "GPX_ALERT_" + _Symbol;
   if(g_bxToken == 0)
      g_bxToken = 1 + MathRand() + (double)(GetTickCount() % 100000) * 32768.0;
   if(!GlobalVariableCheck(gv))
      GlobalVariableTemp(gv);
   if(GlobalVariableSetOnCondition(gv, g_bxToken, 0.0))
      g_bxAlertOwner = true;
   return g_bxAlertOwner;
  }

ENUM_TIMEFRAMES BxTF(int i)  { return (i == 0) ? PERIOD_M5 : PERIOD_M1; }
string          BxTFN(int i) { return (i == 0) ? "M5" : "M1"; }
string          BxD(double v) { return DoubleToString(v, _Digits); }

//--- fractal di p (high didahulukan) - sama dengan DetectFractalAt
bool BxFrac(const MqlRates &r[], int p, bool high)
  {
   for(int k = 1; k <= BX_LB; k++)
     {
      if(high && (r[p - k].high >= r[p].high || r[p + k].high >= r[p].high)) return false;
      if(!high && (r[p - k].low <= r[p].low || r[p + k].low <= r[p].low))   return false;
     }
   return true;
  }

//--- ATR14 = rata2 TR candle t-13..t (sama dengan GetATR shift 1)
double BxATR(const MqlRates &r[], int t)
  {
   if(t < 14) return 0;
   double s = 0;
   for(int j = t - 13; j <= t; j++)
      s += MathMax(r[j].high - r[j].low, MathMax(MathAbs(r[j].high - r[j - 1].close), MathAbs(r[j].low - r[j - 1].close)));
   return s / 14.0;
  }

//--- kotak dari daftar swing (sama dengan SMC_Zones_Update)
bool BxRange(const int &st[], const double &sp[], int n, double a, double &hi, double &lo)
  {
   if(n < 2) return false;
   bool found = false;
   for(int ai = n - 1; ai >= MathMax(0, n - 20) && !found; ai--)
      for(int j = ai - 1; j >= 0; j--)
        {
         if(st[j] == st[ai]) continue;
         double h = (st[ai] > 0) ? sp[ai] : sp[j], l = (st[ai] > 0) ? sp[j] : sp[ai];
         if(h - l >= a) { hi = h; lo = l; found = true; }
         break;
        }
   if(!found)
     {
      bool fh = false, fl = false;
      for(int i = MathMax(0, n - 10); i < n; i++)
        {
         if(st[i] > 0) { if(!fh || sp[i] > hi) { hi = sp[i]; fh = true; } }
         else          { if(!fl || sp[i] < lo) { lo = sp[i]; fl = true; } }
        }
      found = fh && fl;
     }
   return found && hi > lo;
  }

//--- hasil sinyal dinilai di M1 (seperti uji): candle M1 sentuh -> gerak melewati garis >= X setelah sentuh = TP;
//    lalu candle M1 berikutnya: TP/SL mana duluan (sama candle = SL, konservatif).
void BxOutcome(BxSig &s)
  {
   s.result = -1; s.tRes = 0;
   MqlRates m[];
   ArraySetAsSeries(m, false);
   int n = CopyRates(_Symbol, PERIOD_M1, s.t, TimeCurrent(), m);
   if(n < 1) return;
   datetime tEnd = s.t + PeriodSeconds(BxTF(s.tf));
   int k0 = -1;
   for(int k = 0; k < n && m[k].time < tEnd; k++)
      if((s.dir > 0 && m[k].high >= s.entry) || (s.dir < 0 && m[k].low <= s.entry)) { k0 = k; break; }
   if(k0 < 0) return;
   double X = MathAbs(s.tp - s.entry);
   // entry REALISTIS: bila candle M1 sudah buka di luar garis (sering pada sentuhan ulang setelah kotak berubah),
   // order terisi di harga itu, bukan di garis. Tanpa koreksi ini uji lama menggelembung (57-63% -> ~52%).
   if((s.dir > 0 && m[k0].open > s.entry) || (s.dir < 0 && m[k0].open < s.entry))
     {
      s.entry = m[k0].open;
      s.tp = s.entry + s.dir * X;
      s.sl = s.entry - s.dir * X;
     }
   if((s.dir > 0 ? m[k0].high - s.entry : s.entry - m[k0].low) >= X) { s.result = 1; s.tRes = m[k0].time; return; }
   for(int k = k0 + 1; k < n; k++)
     {
      bool tp = (s.dir > 0) ? m[k].high >= s.tp : m[k].low <= s.tp;
      bool sl = (s.dir > 0) ? m[k].low <= s.sl : m[k].high >= s.sl;
      if(sl) { s.result = 2; s.tRes = m[k].time; return; }
      if(tp) { s.result = 1; s.tRes = m[k].time; return; }
     }
  }

void BxLog(const BxSig &s, bool jOwner)
  {
   string key = BxTFN(s.tf) + TimeToString(s.t) + IntegerToString(s.dir);
   for(int i = 0; i < ArraySize(g_bxLogged); i++) if(g_bxLogged[i] == key) return;
   int n = ArraySize(g_bxLogged); ArrayResize(g_bxLogged, n + 1); g_bxLogged[n] = key;
   // alert hanya untuk sinyal yang masih di candle sinyalnya (+1 menit) -> tidak berbunyi ulang saat indikator dimuat ulang
   bool fresh = (TimeCurrent() - s.t) <= PeriodSeconds(BxTF(s.tf)) + 60;
   if(fresh && ((s.tf == 0 && InpBoxTouchM5) || (s.tf == 1 && InpBoxTouchM1)) && BxAlertOwner())
      ::GP_Notify("box" + key, StringFormat("KOTAK %s: harga menyentuh garis %s %s (info - tembus/balik ~52/48, acak)",
                  BxTFN(s.tf), s.dir > 0 ? "ATAS" : "BAWAH", BxD(s.dir > 0 ? g_bxBox[s.tf].hi : g_bxBox[s.tf].lo)), s.t);
   if(!jOwner || MQLInfoInteger(MQL_TESTER)) return;
   int h = FileOpen(BX_JRN, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(h == INVALID_HANDLE) return;
   if(FileSize(h) == 0) FileWriteString(h, "server_time,tf,dir,entry,tp,sl,atr,spread\r\n");
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, StringFormat("%s,%s,%d,%s,%s,%s,%.3f,%.3f\r\n", TimeToString(s.t, TIME_DATE | TIME_MINUTES), BxTFN(s.tf),
                                   s.dir, BxD(s.entry), BxD(s.tp), BxD(s.sl), s.atr, s.spr));
   FileClose(h);
  }

//--- putar ulang kotak & sinyal HARI INI untuk TF i (tiap candle baru TF itu). Candle terakhir = candle berjalan.
void BxReplay(int i, datetime dayStart, bool jOwner)
  {
   ENUM_TIMEFRAMES tf = BxTF(i);
   int need = (int)MathMax(300, MathMin(3000, (TimeCurrent() - dayStart) / PeriodSeconds(tf) + 400));
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int n = CopyRates(_Symbol, tf, 0, need, r);
   for(int s = ArraySize(g_bxSig) - 1; s >= 0; s--)
      if(g_bxSig[s].tf == i) ArrayRemove(g_bxSig, s, 1);
   g_bxBox[i].valid = false;
   if(n < 60) return;
   int st[]; double sp[]; int ns = 0;
   ArrayResize(st, n); ArrayResize(sp, n);
   double kh[2] = {0, 0}, kl[2] = {0, 0}, curHi = 0, curLo = 0, oldHi = 0, oldLo = 0;
   datetime since = 0;
   double lastHi = g_bxBox[i].hi, lastLo = g_bxBox[i].lo;   // kotak hasil putar-ulang sebelumnya
   for(int t = 2 * BX_LB + 20; t <= n - 2; t++)
     {
      int p = t - BX_LB;
      if(BxFrac(r, p, true))       { st[ns] = 1;  sp[ns] = r[p].high; ns++; }
      else if(BxFrac(r, p, false)) { st[ns] = -1; sp[ns] = r[p].low;  ns++; }
      double a = BxATR(r, t), hi = 0, lo = 0;
      if(a <= 0 || !BxRange(st, sp, ns, a, hi, lo)) { g_bxBox[i].valid = false; continue; }
      g_bxBox[i].valid = true; g_bxBox[i].hi = hi; g_bxBox[i].lo = lo; g_bxBox[i].atr = a;
      int b = t + 1;
      if(hi != curHi || lo != curLo)   // kotak berubah: berlaku mulai candle b
        {
         oldHi = curHi; oldLo = curLo; curHi = hi; curLo = lo; since = r[b].time;
        }
      for(int side = 0; side < 2; side++)
        {
         if(kh[side] == hi && kl[side] == lo) continue;
         if(!((side == 0) ? r[b].high >= hi : r[b].low <= lo)) continue;
         kh[side] = hi; kl[side] = lo;
         if(r[b].time < dayStart) continue;
         BxSig s;
         s.tf = i; s.t = r[b].time; s.dir = (side == 0) ? 1 : -1;
         s.entry = (side == 0) ? hi : lo; s.atr = a;
         double X = InpBoxK * a;
         s.tp = s.entry + s.dir * X; s.sl = s.entry - s.dir * X;
         s.spr = r[b].spread * _Point;
         BxOutcome(s);
         int k = ArraySize(g_bxSig); ArrayResize(g_bxSig, k + 1); g_bxSig[k] = s;
         BxLog(s, jOwner);
        }
     }
   for(int side = 0; side < 2; side++) { g_bxKH[i][side] = kh[side]; g_bxKL[i][side] = kl[side]; }
   g_bxSince[i] = since; g_bxPrevHi[i] = oldHi; g_bxPrevLo[i] = oldLo;
   //--- alert perubahan kotak M5 (opsional): hanya bila berubah di putaran ini & masih segar
   if(i == 0 && InpBoxAlertChg && g_bxBox[i].valid && lastHi > 0 && (curHi != lastHi || curLo != lastLo)
      && TimeCurrent() - since <= PeriodSeconds(tf) + 60 && BxAlertOwner())
      ::GP_Notify("boxchg" + TimeToString(since), StringFormat("KOTAK M5 berubah: ATAS %s -> %s | BAWAH %s -> %s (pindahkan order stop)",
                  BxD(lastHi), BxD(curHi), BxD(lastLo), BxD(curLo)), since);
  }

//--- tiap tick: candle baru -> putar ulang; selain itu cek sentuhan candle berjalan (alert secepatnya).
//    true = ada perubahan (panel perlu diperbarui).
bool BX_Update(datetime dayStart, bool jOwner)
  {
   if(!InpBoxSignals || dayStart <= 0) return false;
   bool ch = false;
   for(int i = 0; i < 2; i++)
     {
      datetime tb = iTime(_Symbol, BxTF(i), 0);
      if(tb == 0) continue;
      if(tb != g_bxBar[i]) { BxReplay(i, dayStart, jOwner); g_bxBar[i] = tb; ch = true; continue; }
      if(!g_bxBox[i].valid) continue;
      double hi = g_bxBox[i].hi, lo = g_bxBox[i].lo;
      for(int side = 0; side < 2; side++)
        {
         if(g_bxKH[i][side] == hi && g_bxKL[i][side] == lo) continue;
         if(!((side == 0) ? iHigh(_Symbol, BxTF(i), 0) >= hi : iLow(_Symbol, BxTF(i), 0) <= lo)) continue;
         g_bxKH[i][side] = hi; g_bxKL[i][side] = lo;
         BxSig s;
         s.tf = i; s.t = tb; s.dir = (side == 0) ? 1 : -1;
         s.entry = (side == 0) ? hi : lo; s.atr = g_bxBox[i].atr;
         double X = InpBoxK * s.atr;
         s.tp = s.entry + s.dir * X; s.sl = s.entry - s.dir * X;
         s.spr = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
         BxOutcome(s);
         int k = ArraySize(g_bxSig); ArrayResize(g_bxSig, k + 1); g_bxSig[k] = s;
         BxLog(s, jOwner);
         ch = true;
        }
     }
   //--- hasil sinyal yang masih berjalan: cek tiap candle M1 baru (lewat putar ulang M1 / di sini)
   static datetime lastM1 = 0;
   datetime m1t = iTime(_Symbol, PERIOD_M1, 0);
   if(m1t != lastM1)
     {
      lastM1 = m1t;
      for(int s = 0; s < ArraySize(g_bxSig); s++)
         if(g_bxSig[s].result < 0) { BxOutcome(g_bxSig[s]); if(g_bxSig[s].result > 0) ch = true; }
     }
   BxDrawAll();
   return ch;
  }

//--- garis kotak M5 (tebal) & M1 (titik-titik) di sisi kanan chart, hanya saat tab 3 aktif
void BxLine(string n, double p, color c, ENUM_LINE_STYLE st, int w, string txt)
  {
   datetime t1 = iTime(_Symbol, _Period, 40), t2 = iTime(_Symbol, _Period, 0) + 12 * PeriodSeconds(_Period);
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_TREND, 0, t1, p, t2, p);
   ObjectMove(0, n, 0, t1, p); ObjectMove(0, n, 1, t2, p);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_STYLE, st);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, txt);
   string l = n + "T";
   if(ObjectFind(0, l) < 0) ObjectCreate(0, l, OBJ_TEXT, 0, t2, p);
   ObjectMove(0, l, 0, t2, p);
   ObjectSetString(0, l, OBJPROP_TEXT, txt + "  ");
   ObjectSetInteger(0, l, OBJPROP_COLOR, c);
   ObjectSetInteger(0, l, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, l, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
   ObjectSetInteger(0, l, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, l, OBJPROP_HIDDEN, true);
  }

void BxDrawAll()
  {
   if(!InpBoxSignals || !InpBoxDraw || !g_bxDraw)
     {
      if(ObjectsTotal(0, 0, -1) > 0) ObjectsDeleteAll(0, BX_PFX);
      return;
     }
   for(int i = 0; i < 2; i++)
     {
      string p = BX_PFX + BxTFN(i);
      if(!g_bxBox[i].valid) { ObjectsDeleteAll(0, p); continue; }
      ENUM_LINE_STYLE st = (i == 0) ? STYLE_SOLID : STYLE_DOT;
      BxLine(p + "u", g_bxBox[i].hi, clrSilver, st, (i == 0) ? 2 : 1, "kotak " + BxTFN(i) + " atas " + BxD(g_bxBox[i].hi));
      BxLine(p + "d", g_bxBox[i].lo, clrSilver, st, (i == 0) ? 2 : 1, "kotak " + BxTFN(i) + " bawah " + BxD(g_bxBox[i].lo));
     }
  }

string BxRes(const BxSig &s)
  {
   if(s.result == 1) return "TP " + ::GP_LocalTime(s.tRes);
   if(s.result == 2) return "SL " + ::GP_LocalTime(s.tRes);
   return "jalan";
  }

//--- isi tab "3 KOTAK" = PETA INFO (tanpa arah; uji entry realistis: ujung kotak tembus ~52% / balik ~48%)
void BX_Lines(string &tx[], color &cl[], double riskPct, double balance)
  {
   ArrayResize(tx, 0); ArrayResize(cl, 0);
   int n = 0;
#define BXL(s, c) { ArrayResize(tx, n + 1); ArrayResize(cl, n + 1); tx[n] = (s); cl[n] = (c); n++; }
   BXL("== KOTAK SMC M5 & M1 [INFO] ==", clrGold);
   BXL("Ujung kotak: tembus ~52% / balik ~48%", clrSilver);
   BXL("= acak, bukan sinyal arah (uji 2016-26)", clrSilver);
   if(!InpBoxSignals) { BXL("Kotak: MATI (input)", clrSilver); return; }
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   for(int i = 0; i < 2; i++)
     {
      BxBox b = g_bxBox[i];
      if(!b.valid) { BXL("-- " + BxTFN(i) + ": kotak belum terbentuk --", clrSilver); continue; }
      double mid = (b.hi + b.lo) / 2, pos = (b.hi > b.lo) ? (bid - b.lo) / (b.hi - b.lo) * 100 : 0;
      BXL(StringFormat("-- %s | tinggi $%.2f | ATR $%.2f --", BxTFN(i), b.hi - b.lo, b.atr), clrLimeGreen);
      if(g_bxSince[i] > 0)
        {
         int age = (int)((TimeCurrent() - g_bxSince[i]) / 60);
         BXL(StringFormat("sejak %s (%d mnt, khas %s)", ::GP_LocalTime(g_bxSince[i]), age, i == 0 ? "35 mnt" : "7 mnt"),
             age <= ((i == 0) ? 5 : 1) ? clrGold : clrSilver);
        }
      // GoldPro (3 Okt 2026): + peluang harga DATANG dlm 1 jam (Core\GP_TouchTime, terkalibrasi, uji 2022-26 +-0.7 poin)
      bool tto = ::TT_MarketOpen() && ::g_ttAdr > 0;
      BXL(StringFormat("Atas  %s (%+.1f)%s", BxD(b.hi), b.hi - bid, (tto && b.hi > bid) ? "  1j " + ::TT_Pct(::TT_P(b.hi - bid, 60)) : ""), clrWhite);
      BXL(StringFormat("EQ    %s (%+.1f)%s", BxD(mid), mid - bid, tto ? "  1j " + ::TT_Pct(::TT_P(mid - bid, 60)) : ""), clrGold);
      BXL(StringFormat("Bawah %s (%+.1f)%s", BxD(b.lo), b.lo - bid, (tto && b.lo < bid) ? "  1j " + ::TT_Pct(::TT_P(b.lo - bid, 60)) : ""), clrWhite);
      BXL(StringFormat("Harga di %.0f%% kotak (%s)", pos,
                       pos > 100 ? "di atas kotak" : (pos < 0 ? "di bawah kotak" : (pos >= 50 ? "Premium" : "Discount"))), clrSilver);
      int up = 0, dn = 0;
      for(int s = 0; s < ArraySize(g_bxSig); s++)
         if(g_bxSig[s].tf == i) { if(g_bxSig[s].dir > 0) up++; else dn++; }
      BXL(StringFormat("Disentuh hari ini: atas %d | bawah %d", up, dn), clrSilver);
     }
#undef BXL
  }

void BX_Deinit(bool isFinal = true)
  {
   if(isFinal)
      ObjectsDeleteAll(0, BX_PFX);   // ganti TF: garis dibiarkan untuk instance baru (lihat GoldPro_Main OnDeinit)
   if(g_bxAlertOwner)
      GlobalVariableDel("GPX_ALERT_" + _Symbol);   // chart lain boleh mengambil alih alert
   g_bxAlertOwner = false;
  }

#endif // GP_BOXSIGNAL_MQH
