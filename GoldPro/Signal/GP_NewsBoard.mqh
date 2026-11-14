//+------------------------------------------------------------------+
//|                                                 GP_NewsBoard.mqh |
//| GoldPro - DASHBOARD BERITA (kanan atas chart)                     |
//|                                                                  |
//| - Daftar rilis USD (kalender MT5) + jam panas New York tanpa      |
//|   berita (NYSE buka 09:30, 10:00 NY), jam WITA.                   |
//| - Baris ATAS besar = rilis berikutnya / yang sedang berlangsung.  |
//| - Kuning 15 mnt sebelum, oranye 10 mnt, merah 1 mnt sebelum rilis.|
//| - Setelah rilis: panduan per MENIT & per CANDLE (M1 #, M5 #).     |
//|                                                                  |
//| Angka dari data (research\news_phase.py, sweep_cause.py):         |
//|   323 rilis PENTING Agu 2025 - Sep 2026 (jam kalender dikoreksi), |
//|   M1 XAUUSD. Gerak candle vs menit yang sama tanpa rilis:         |
//|   menit -15..-1 1.2-1.35x (menit -10: sweep ~4x), menit 0 = M1 #1 |
//|   2.4x, menit 1 2.0x, menit 2-4 1.6-1.8x, menit 5-20 ~1.55x.      |
//|   Dorongan 2 mnt pertama median 3.2% ADR; setelah itu arah lanjut |
//|   50-54% (acak); balik lewat harga pra-rilis 20% (5 mnt),         |
//|   28% (10 mnt), 36% (20 mnt). Data 08:30 NY: sweep 26% vs 5%      |
//|   tanpa rilis; 10 mnt sebelumnya 17% vs 6%. Tick 2020-26: dorongan |
//|   terjadi 1-2 detik setelah rilis, spread pra-rilis ~$0.57, maks ~$1.|
//| INFO risiko & waktu - BUKAN sinyal arah.                          |
//+------------------------------------------------------------------+
#ifndef GP_NEWSBOARD_MQH
#define GP_NEWSBOARD_MQH

input group "=== GoldPro: Dashboard Berita ==="
// 1 Okt 2026: tampil/sembunyi kini lewat TOMBOL "Berita" di kolom tombol kiri (GDM::g_vNews, default tertutup).
input bool InpNBShow     = false;  // (tidak dipakai lagi - gunakan tombol "Berita" di chart)
input int  InpNBMinImp   = 1;      // Berita minimal: 1 = sedang + penting, 2 = penting saja
input bool InpNBHotSlots = true;   // Tambah jam panas NY tanpa berita (NYSE buka 09:30, 10:00 NY)
input bool InpNBAlert15  = true;   // Alert 15 mnt sebelum rilis PENTING
input int  InpNBFont     = 9;      // Ukuran huruf daftar

#define NB_PFX "GPN_"

struct NBRow
  {
   datetime t;          // jam server rilis (sudah dikoreksi GP_CalTime)
   int      imp;        // 2 penting, 1 sedang, 0 jam panas tanpa berita
   int      kind;       // 0 berita, 1 NYSE buka, 2 jam 10:00 NY
   int      cnt;        // jumlah rilis di menit yang sama
   string   names;
   double   medA, p90A; // dorongan 2 mnt pertama (median / 1 dari 10), satuan ADR
   double   swP, swB;   // peluang sweep menit T..T+5 / menit sama tanpa rilis (news_sweep.py, 6 Okt 2026)
   double   tuP;        // peluang candle M1 rilis "tusuk" (rentang >= 0.08 ADR, ekor >= 60%)
  };
NBRow    g_nbRows[];
datetime g_nbFetched = 0;
bool     g_nbCompact = false;
bool     g_nbFlash   = false;
string   g_nbL[];
color    g_nbC[];
int      g_nbS[];

//--- dorongan 2 menit pertama |close(T+1) - close(T-1)| per jenis berita (median, 1-dari-10 terbesar), satuan ADR.
//    6 Okt 2026 (research\news_calib.py): dihitung ulang dari 11.577 menit rilis/jam panas 2017-2026 (susut k=15 ke
//    cadangan jam). Uji walk-forward 2020-2026 (tabel dari data sebelum tahun uji): lewat batas 1-dari-10 10.5%
//    (ideal 10; tabel lama 13.5%), di atas median 50.6% (lama 42.6%). Diperbaiki: "Nonfarm" dulu menangkap ADP
//    (ADP 6.3% ADR, NFP asli 20.7%); "Powell" -> "Fed Chair" (jabatan Powell berakhir Mei 2026); +20 jenis berita,
//    + jam panas NY tanpa rilis. URUTAN kunci penting: yang spesifik dulu ("Nonfarm Productivity", "ADP").
//    PERINGATAN SWEEP (research\news_sweep.py, 2017-2026): sweep = tembus high/low 60 mnt lalu balik >= 0.1 ADR dlm
//    10 mnt, di menit T..T+5; pembanding = menit sama hari tanpa rilis. NFP 70% (biasa 13%), keputusan Fed 64% (2%),
//    CPI 58%, Retail 45%, notulen FOMC 38% (2%)... Jenis n < 30 disusutkan ke "biasa". KESEMPATAN: jaring limit
//    sebelum rilis (k 0.5-3 x dorongan), ikut/lawan/straddle/kejutan semua RUGI di uji -> sengaja TIDAK ditampilkan.
void NBExpect(string name, int nyMin, double &med, double &p90, double &swp, double &swb, double &tup)
  {
   string k[] = {"Nonfarm Productivity", "Unit Labor Costs", "ADP", "Nonfarm Payrolls", "Average Hourly Earnings",
                 "Unemployment Rate", "Participation Rate", "CPI", "PPI", "Real PCE", "PCE", "Personal Spending", "GDP",
                 "Employment Cost", "Retail Sales", "Retail Control", "Durable Goods", "Jobless Claims", "Philadelphia Fed",
                 "Empire State", "ISM Manufacturing", "ISM Non-Manufacturing", "ISM Services", "S&P Global", "JOLTS",
                 "Consumer Confidence", "Michigan", "Chicago", "Interest Rate Decision", "FOMC Statement",
                 "FOMC Economic Projections", "FOMC Press", "FOMC Minutes", "Fed Chair", "Beige Book", "Speech", "Testimony",
                 "Auction", "Crude Oil Stocks", "Trade Balance", "Import Price", "Export Price", "Industrial Production",
                 "Home Sales", "Housing Starts", "Building Permits", "NYSE buka", "jam 10 NY"};
   double m[] = {0.041, 0.041, 0.063, 0.207, 0.207, 0.207, 0.207, 0.136, 0.057, 0.057, 0.055, 0.055, 0.057, 0.042,
                 0.069, 0.069, 0.038, 0.049, 0.056, 0.035, 0.080, 0.064, 0.064, 0.040, 0.045, 0.038, 0.042, 0.028, 0.113,
                 0.113, 0.113, 0.042, 0.035, 0.026, 0.016, 0.017, 0.017, 0.015, 0.024, 0.042, 0.038, 0.038, 0.030, 0.035,
                 0.035, 0.035, 0.030, 0.033};
   double q[] = {0.140, 0.140, 0.194, 0.479, 0.479, 0.479, 0.479, 0.436, 0.161, 0.195, 0.150, 0.150, 0.195, 0.152,
                 0.195, 0.195, 0.102, 0.124, 0.141, 0.106, 0.177, 0.204, 0.204, 0.104, 0.145, 0.105, 0.120, 0.077, 0.287,
                 0.287, 0.287, 0.109, 0.114, 0.129, 0.066, 0.055, 0.055, 0.049, 0.065, 0.164, 0.121, 0.121, 0.081, 0.092,
                 0.092, 0.092, 0.081, 0.083};
   double sw[] = {0.14, 0.14, 0.41, 0.70, 0.70, 0.70, 0.70, 0.58, 0.29, 0.42, 0.40, 0.40, 0.42, 0.16, 0.45, 0.45, 0.15,
                  0.23, 0.32, 0.13, 0.40, 0.34, 0.34, 0.22, 0.22, 0.19, 0.25, 0.17, 0.64, 0.64, 0.64, 0.27, 0.38, 0.21,
                  0.04, 0.08, 0.08, 0.06, 0.10, 0.14, 0.17, 0.17, 0.13, 0.16, 0.16, 0.16, 0.18, 0.16};
   double sb[] = {0.13, 0.13, 0.17, 0.13, 0.13, 0.13, 0.13, 0.13, 0.13, 0.13, 0.13, 0.13, 0.13, 0.13, 0.13, 0.13, 0.12,
                  0.13, 0.13, 0.13, 0.15, 0.15, 0.15, 0.14, 0.15, 0.15, 0.15, 0.14, 0.02, 0.02, 0.02, 0.02, 0.02, 0.08,
                  0.02, 0.06, 0.06, 0.04, 0.09, 0.13, 0.12, 0.12, 0.08, 0.15, 0.15, 0.15, 0.03, 0.03};
   double tu[] = {0.024, 0.024, 0.103, 0.158, 0.158, 0.158, 0.158, 0.061, 0.118, 0.115, 0.114, 0.114, 0.115, 0.024,
                  0.163, 0.163, 0.038, 0.067, 0.128, 0.036, 0.136, 0.112, 0.112, 0.028, 0.032, 0.076, 0.046, 0.034,
                  0.115, 0.115, 0.115, 0.056, 0.064, 0.021, 0.000, 0.006, 0.006, 0.000, 0.006, 0.010, 0.019, 0.019,
                  0.009, 0.028, 0.028, 0.028, 0.011, 0.012};
   for(int i = 0; i < ArraySize(k); i++)
      if(StringFind(name, k[i]) >= 0) { med = m[i]; p90 = q[i]; swp = sw[i]; swb = sb[i]; tup = tu[i]; return; }
   if(nyMin == 510)      { med = 0.030; p90 = 0.083; swp = 0.13; swb = 0.13; tup = 0.003; }   // berita lain 08:30 NY
   else if(nyMin == 600) { med = 0.037; p90 = 0.105; swp = 0.19; swb = 0.15; tup = 0.018; }   // berita lain 10:00 NY
   else if(nyMin == 840) { med = 0.015; p90 = 0.056; swp = 0.03; swb = 0.02; tup = 0.000; }   // berita lain 14:00 NY
   else                  { med = 0.013; p90 = 0.042; swp = 0.02; swb = 0.03; tup = 0.002; }
  }

int NBNyMin(datetime server)
  {
   MqlDateTime d;
   TimeToStruct(GP_UTCToET(GP_ServerToUTC(server)), d);
   return d.hour * 60 + d.min;
  }

void NBAdd(datetime t, int imp, int kind, string name)
  {
   for(int i = 0; i < ArraySize(g_nbRows); i++)
      if(g_nbRows[i].t == t)
        {
         if(kind != 0) return;                           // jam panas bila sudah ada berita di menit itu: tidak perlu
         if(g_nbRows[i].kind != 0)                       // berita menggantikan baris jam panas
           { g_nbRows[i].kind = 0; g_nbRows[i].names = ""; g_nbRows[i].cnt = 0; g_nbRows[i].medA = 0; g_nbRows[i].p90A = 0;
             g_nbRows[i].swP = 0; g_nbRows[i].swB = 0; g_nbRows[i].tuP = 0; }
         g_nbRows[i].cnt++;
         g_nbRows[i].imp = MathMax(g_nbRows[i].imp, imp);
         if(StringFind(g_nbRows[i].names, name) < 0 && StringLen(g_nbRows[i].names) < 40)
            g_nbRows[i].names += (g_nbRows[i].names == "" ? "" : " + ") + name;
         double md, p9, sp, sb, tp;
         NBExpect(name, NBNyMin(t), md, p9, sp, sb, tp);
         if(md > g_nbRows[i].medA)                                   // jenis terkuat di menit itu (semua angka dari jenis yang sama)
           { g_nbRows[i].medA = md; g_nbRows[i].p90A = p9; g_nbRows[i].swP = sp; g_nbRows[i].swB = sb; g_nbRows[i].tuP = tp; }
         return;
        }
   int n = ArraySize(g_nbRows);
   ArrayResize(g_nbRows, n + 1);
   g_nbRows[n].t = t; g_nbRows[n].imp = imp; g_nbRows[n].kind = kind; g_nbRows[n].cnt = (kind == 0) ? 1 : 0;
   g_nbRows[n].names = name;
   g_nbRows[n].medA = 0; g_nbRows[n].p90A = 0; g_nbRows[n].swP = 0; g_nbRows[n].swB = 0; g_nbRows[n].tuP = 0;
   NBExpect(name, NBNyMin(t), g_nbRows[n].medA, g_nbRows[n].p90A, g_nbRows[n].swP, g_nbRows[n].swB, g_nbRows[n].tuP);   // jam panas NY juga (6 Okt 2026)
  }

void NBFetch()
  {
   ArrayResize(g_nbRows, 0);
   datetime now = TimeTradeServer();
   MqlCalendarValue v[];
   int n = CalendarValueHistory(v, now - 3 * 3600, now + 30 * 3600, NULL, "USD");
   for(int i = 0; i < n; i++)
     {
      MqlCalendarEvent e;
      if(!CalendarEventById(v[i].event_id, e))
         continue;
      int imp = (e.importance == CALENDAR_IMPORTANCE_HIGH) ? 2 : ((e.importance == CALENDAR_IMPORTANCE_MODERATE) ? 1 : 0);
      if(imp < MathMax(1, InpNBMinImp))
         continue;
      NBAdd(GP_CalTime(v[i].time), imp, 0, e.name);
     }
   if(InpNBHotSlots)
      for(int dday = 0; dday <= 1; dday++)
        {
         datetime ref = now + dday * 86400;
         MqlDateTime ny;
         TimeToStruct(GP_UTCToET(GP_ServerToUTC(ref)), ny);
         if(ny.day_of_week < 1 || ny.day_of_week > 5)
            continue;
         NBAdd(GP_ServerAtLocalHour(ref, 9, false) + 30 * 60, 0, 1, "NYSE buka (jam panas)");
         NBAdd(GP_ServerAtLocalHour(ref, 10, false), 0, 2, "jam 10 NY (jam panas)");
        }
   for(int i = 1; i < ArraySize(g_nbRows); i++)                 // urut waktu
      for(int j = i; j > 0 && g_nbRows[j].t < g_nbRows[j - 1].t; j--)
        {
         NBRow tmp = g_nbRows[j]; g_nbRows[j] = g_nbRows[j - 1]; g_nbRows[j - 1] = tmp;
        }
   g_nbFetched = now;
  }

double NBAdr()
  {
   double s = 0; int c = 0;
   for(int i = 1; i <= 20; i++)
     {
      double h = iHigh(_Symbol, PERIOD_D1, i), l = iLow(_Symbol, PERIOD_D1, i);
      if(h > 0 && l > 0) { s += h - l; c++; }
     }
   return (c > 0) ? s / c : 0;
  }

string NBDur(long sec)
  {
   if(sec >= 3600) return StringFormat("%dj%02dm", (int)(sec / 3600), (int)((sec % 3600) / 60));
   if(sec >= 60)   return StringFormat("%d:%02d", (int)(sec / 60), (int)(sec % 60));
   return StringFormat("%d dtk", (int)sec);
  }

void NBLine(string s, color c, int fs)
  {
   int n = ArraySize(g_nbL);
   ArrayResize(g_nbL, n + 1); ArrayResize(g_nbC, n + 1); ArrayResize(g_nbS, n + 1);
   g_nbL[n] = StringSubstr(s, 0, 62); g_nbC[n] = c; g_nbS[n] = fs;
  }

string NBShort(const NBRow &r)
  {
   string s = r.names;
   if(r.cnt > 2) s = StringSubstr(s, 0, 26) + StringFormat(" +%d", r.cnt - 1);
   return StringSubstr(s, 0, 34);
  }

//--- isi dashboard: baris besar (fokus) + panduan per menit/candle + daftar berikutnya
void NBBuild()
  {
   ArrayResize(g_nbL, 0); ArrayResize(g_nbC, 0); ArrayResize(g_nbS, 0);
   datetime now = TimeTradeServer();
   int fs = MathMax(7, InpNBFont), big = fs + 4;
   NBLine(g_nbCompact ? "BERITA [klik: lengkap]" : "BERITA USD & JAM PANAS (" + InpLocalTZName + ") [klik: ringkas]", clrSilver, fs - 1);
   int f = -1;
   for(int i = 0; i < ArraySize(g_nbRows); i++)
      if(g_nbRows[i].t + 20 * 60 > now) { f = i; break; }
   if(f < 0)
     {
      NBLine("tidak ada rilis 30 jam ke depan", clrSilver, fs);
      return;
     }
   NBRow r = g_nbRows[f];
   long dt = (long)(now - r.t);
   string tl = GP_LocalTime(r.t);
   string head = tl + " " + (r.kind == 0 ? (r.imp == 2 ? "[P] " : "[s] ") : "") + NBShort(r);
   double adr = NBAdr();
   color hc = (r.imp == 2) ? clrGold : clrWhite;
   string ph = "", g1 = "", g2 = "";
   color pc = clrSilver;
   if(r.kind == 0)
     {
      if(dt < -900)      { ph = "dalam " + NBDur(-dt); pc = clrSilver; }
      else if(dt < -600) { ph = NBDur(-dt) + " lagi | SIAP"; pc = clrGold; hc = clrGold;
                           g1 = "hindari entry baru; posisi terbuka: lebarkan SL"; }
      else if(dt < -60)  { ph = NBDur(-dt) + " lagi | PRA-RILIS"; pc = clrOrange; hc = clrOrange;
                           g1 = "10 mnt sebelum: sweep ~3x lebih sering (20:20)";
                           g2 = "spread mulai melebar (median $0.57)"; }
      else if(dt < 0)    { ph = NBDur(-dt) + " lagi | JANGAN KLIK"; pc = clrRed; hc = clrRed;
                           g1 = "dorongan terjadi 1-2 DETIK setelah rilis"; g2 = "spread melebar s/d ~$1"; }
      else if(dt < 60)   { ph = StringFormat("MENIT 1 | M1 #1 %s | M5 #1 %s-%s", tl, tl, GP_LocalTime(r.t + 240));
                           pc = g_nbFlash ? clrWhite : clrRed; hc = pc;
                           g1 = "DORONGAN UTAMA: gerak 2.4x normal"; g2 = "masuk sekarang = kejar harga + slippage"; }
      else if(dt < 120)  { ph = "MENIT 2 | M1 #2 " + GP_LocalTime(r.t + 60); pc = clrRed; hc = clrRed;
                           g1 = "masih 2x normal; arah lanjut 50:50 (acak)"; g2 = "jangan kejar dorongan"; }
      else if(dt < 300)  { ph = StringFormat("MENIT %d | M1 #%d | M5 #1 s/d %s", (int)(dt / 60) + 1, (int)(dt / 60) + 1, GP_LocalTime(r.t + 240));
                           pc = clrOrange; hc = clrOrange;
                           g1 = "1.6-1.8x normal: bolak-balik"; g2 = "20% balik lewat harga pra-rilis s/d mnt 5"; }
      else if(dt < 600)  { ph = StringFormat("MENIT %d | M5 #2 %s-%s", (int)(dt / 60) + 1, GP_LocalTime(r.t + 300), GP_LocalTime(r.t + 540));
                           pc = clrGold; hc = clrGold;
                           g1 = "~1.6x normal; 28% balik lewat harga pra-rilis s/d mnt 10"; }
      else               { ph = StringFormat("MENIT %d | M5 #%d", (int)(dt / 60) + 1, (int)(dt / 300) + 1);
                           pc = clrSilver; g1 = "mereda ke tingkat hari ini (~1.5x)"; }
     }
   else
     {
      bool nyse = (r.kind == 1);
      if(dt < -900)      { ph = "dalam " + NBDur(-dt); }
      else if(dt < 0)    { ph = NBDur(-dt) + " lagi | JAM PANAS"; pc = clrGold; hc = clrGold;
                           g1 = nyse ? "tanpa berita: sweep ~5x di menit ini" : "tanpa berita: sweep ~8x di menit ini"; }
      else if(dt < 600)  { ph = StringFormat("MENIT %d | M1 #%d | M5 #%d", (int)(dt / 60) + 1, (int)(dt / 60) + 1, (int)(dt / 300) + 1);
                           pc = clrOrange; hc = clrOrange;
                           g1 = nyse ? "10 mnt pertama NYSE: sweep ~2x, bolak-balik" : "menit 10:00-10:02 NY paling ramai"; }
      else               { ph = StringFormat("MENIT %d", (int)(dt / 60) + 1); g1 = "mereda"; }
     }
   NBLine(head, hc, big);
   NBLine(ph, pc, fs + 1);
   if(g1 != "") NBLine(g1, clrWhite, fs);
   if(g2 != "") NBLine(g2, clrWhite, fs);
   if(adr > 0 && r.medA > 0)
      NBLine(StringFormat("2 mnt pertama biasa +/-$%.1f, 1 dr 10 >= $%.0f", r.medA * adr, r.p90A * adr), clrSilver, fs);
   if(r.swP > 0 && dt < 360)                                     // peringatan sweep s/d menit T+5
      NBLine(StringFormat("SWEEP 6 mnt %.0f%% (tanpa berita %.0f%%) | tusuk %.0f%%", r.swP * 100, r.swB * 100, r.tuP * 100),
             r.swP >= 0.35 ? clrTomato : (r.swP >= 0.20 ? clrOrange : clrSilver), fs);
   if(dt >= 0 && dt < 1200)
     {
      int sh = iBarShift(_Symbol, PERIOD_M1, r.t - 60, false);
      double p0 = (sh >= 0) ? iClose(_Symbol, PERIOD_M1, sh) : 0, bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(p0 > 0)
         NBLine(StringFormat("sejak rilis %+.2f$ (%.2f ADR) dari %s", bid - p0, adr > 0 ? MathAbs(bid - p0) / adr : 0,
                             DoubleToString(p0, _Digits)), bid >= p0 ? clrLimeGreen : clrTomato, fs);
     }
   if(g_nbCompact)
      return;
   NBLine("-- berikutnya --", clrSilver, fs - 1);
   int shown = 0;
   for(int i = f + 1; i < ArraySize(g_nbRows) && shown < 7; i++, shown++)
     {
      NBRow x = g_nbRows[i];
      string tag = (x.kind != 0) ? " . " : ((x.imp == 2) ? " P " : " s ");
      string ex = (adr > 0 && x.medA > 0) ? StringFormat(" +/-$%.0f", MathMax(1, x.medA * adr)) : "";
      if(x.swP >= 0.20) ex += StringFormat(" sw%.0f%%", x.swP * 100);   // peluang sweep 6 mnt (news_sweep.py)
      long ds = (long)(x.t - now);
      color c = (x.kind != 0) ? clrSilver : ((x.imp == 2) ? clrGold : clrWhite);
      if(x.swP >= 0.35) c = clrTomato;                               // berita pemicu sweep kuat
      if(ds <= 900) c = clrOrange;
      NBLine(GP_LocalTime(x.t) + tag + NBShort(x) + ex, c, fs);
     }
  }

void NBLabel(string n, int x, int y, string s, color c, int fs)
  {
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_ZORDER, 20);
      ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, n, OBJPROP_TEXT, s);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, fs);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, "Dashboard berita GoldPro: klik judul untuk ringkas/lengkap");
  }

void NBDraw()
  {
   int n = ArraySize(g_nbL);
   if(n < 2) return;
   int w = 0, h = 6;
   for(int i = 0; i < n; i++)
     {
      w = (int)MathMax(w, StringLen(g_nbL[i]) * g_nbS[i] * 0.78 + 16);
      h += (int)MathRound(g_nbS[i] * 1.7);
     }
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int x0 = MathMax(4, cw - w - 8), y0 = 22;
   string bg = NB_PFX + "BG";
   if(ObjectFind(0, bg) < 0)
     {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, bg, OBJPROP_ZORDER, 19);
     }
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x0 - 4);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y0 - 4);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, w + 4);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, h + 4);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'20,22,30');
   ObjectSetInteger(0, bg, OBJPROP_COLOR, (g_nbC[1] == clrRed || g_nbC[1] == clrWhite) ? clrRed : clrDimGray);
   int y = y0;
   for(int i = 0; i < n; i++)
     {
      NBLabel(NB_PFX + "L" + IntegerToString(i), x0 + 2, y, g_nbL[i], g_nbC[i], g_nbS[i]);
      y += (int)MathRound(g_nbS[i] * 1.7);
     }
   for(int i = n; ObjectFind(0, NB_PFX + "L" + IntegerToString(i)) >= 0; i++)   // baris lebih yang tidak terpakai
      ObjectDelete(0, NB_PFX + "L" + IntegerToString(i));
  }

void NBAlerts()
  {
   if(!InpNBAlert15)
      return;
   datetime now = TimeTradeServer();
   double adr = NBAdr();
   for(int i = 0; i < ArraySize(g_nbRows); i++)
     {
      // PENTING, atau "sedang" yang terbukti pemicu sweep (mis. notulen FOMC 38% vs 2%) - 6 Okt 2026
      if(g_nbRows[i].kind != 0 || (g_nbRows[i].imp < 2 && g_nbRows[i].swP < 0.30))
         continue;
      long dt = (long)(g_nbRows[i].t - now);
      if(dt > 840 && dt <= 900)
         GP_Notify("nb15" + TimeToString(g_nbRows[i].t),
                   StringFormat("BERITA 15 mnt lagi: %s %s %s - sweep %.0f%% (biasa %.0f%%), dorongan +/-$%.0f: hindari entry baru, lebarkan SL",
                                GP_LocalTime(g_nbRows[i].t), InpLocalTZName, NBShort(g_nbRows[i]), g_nbRows[i].swP * 100,
                                g_nbRows[i].swB * 100, g_nbRows[i].medA * adr), g_nbRows[i].t - 900);
     }
  }

//--- 14 Okt 2026: tombol "Berita" = GAMBAR - garis vertikal di jam rilis (2 jam lalu s/d 24 jam ke depan): merah = penting,
//    oranye = sedang, abu = jam panas NY tanpa berita; teks garis = jam WITA + nama. Dashboard = kotak "i" (g_iNews). Prefix GPN_V.
datetime g_nbVDrawn = 0;
void NBVLines()
  {
   datetime now = TimeTradeServer();
   if(g_nbVDrawn == g_nbFetched && ObjectFind(0, NB_PFX + "V0") >= 0 && now - g_nbVDrawn < 600) return;
   ObjectsDeleteAll(0, NB_PFX + "V");
   int k = 0;
   for(int i = 0; i < ArraySize(g_nbRows); i++)
     {
      NBRow x = g_nbRows[i];
      if(x.t < now - 2 * 3600 || x.t > now + 24 * 3600) continue;
      string n = NB_PFX + "V" + IntegerToString(k++);
      ObjectCreate(0, n, OBJ_VLINE, 0, x.t, 0);
      color c = (x.kind != 0) ? clrDimGray : ((x.imp >= 2) ? clrRed : clrOrange);
      ObjectSetInteger(0, n, OBJPROP_COLOR, c);
      ObjectSetInteger(0, n, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, n, OBJPROP_BACK, true);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      string nm = (x.kind != 0) ? x.names : StringSubstr(x.names, 0, 30);
      ObjectSetString(0, n, OBJPROP_TEXT, GP_LocalTime(x.t) + " " + nm);
      ObjectSetString(0, n, OBJPROP_TOOLTIP, StringFormat("%s %s %s | sweep %.0f%% (biasa %.0f%%) | dorongan 2 mnt median %.0f%% ADR",
                                                          GP_LocalTime(x.t), InpLocalTZName, x.names, x.swP * 100, x.swB * 100, x.medA * 100));
     }
   g_nbVDrawn = g_nbFetched;
  }

//--- dipanggil timer (tiap 2 dtk)
void NB_Update()
  {
   if((!GDM::g_vNews && !GDM::g_iNews) || MQLInfoInteger(MQL_TESTER))
     {
      if(ObjectFind(0, NB_PFX + "BG") >= 0 || ObjectFind(0, NB_PFX + "V0") >= 0)
         ObjectsDeleteAll(0, NB_PFX);              // tombol & kotak "i" Berita mati -> garis & dashboard disembunyikan
      return;
     }
   datetime now = TimeTradeServer();
   if(g_nbFetched == 0 || now - g_nbFetched > 600)
      NBFetch();
   if(GDM::g_iNews)                                // 14 Okt: dashboard = kotak "i"
     {
      g_nbFlash = !g_nbFlash;
      NBBuild();
      NBDraw();
     }
   else if(ObjectFind(0, NB_PFX + "BG") >= 0) { ObjectDelete(0, NB_PFX + "BG"); ObjectsDeleteAll(0, NB_PFX + "L"); }
   if(GDM::g_vNews) NBVLines();                    // tombol utama = garis jam berita
   else if(ObjectFind(0, NB_PFX + "V0") >= 0) ObjectsDeleteAll(0, NB_PFX + "V");
   NBAlerts();
  }

void NB_ChartEvent(const int id, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK && ((sparam == "GPB_B_news" && GDM::g_vNews) || (sparam == "GPB_I_news" && GDM::g_iNews)))
     {
      g_nbVDrawn = 0;
      NB_Update();                                 // baru dinyalakan -> tampil langsung
      ChartRedraw();
      return;
     }
   if(!GDM::g_iNews)
      return;
   if(id == CHARTEVENT_OBJECT_CLICK && (sparam == NB_PFX + "L0" || sparam == NB_PFX + "BG"))
     {
      g_nbCompact = !g_nbCompact;
      NBBuild();
      NBDraw();
      ChartRedraw();
     }
   else if(id == CHARTEVENT_CHART_CHANGE)
      NBDraw();                                   // lebar chart berubah -> posisi kanan ikut
  }

void NB_Deinit(bool isFinal = true)
  {
   if(isFinal)
      ObjectsDeleteAll(0, NB_PFX);
  }

#endif // GP_NEWSBOARD_MQH
