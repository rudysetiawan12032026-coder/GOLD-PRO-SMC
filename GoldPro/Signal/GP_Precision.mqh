//+------------------------------------------------------------------+
//|                                                 GP_Precision.mqh |
//| GoldPro - setup SMC "presisi" yang LOLOS validasi 1 tahun.        |
//|                                                                  |
//| Hasil Tahap 2 (22.954 POI hasil replay, retest pertama, M1,      |
//| spread asli): OB biasa & FVG RUGI di 3 periode; zona < 1 ATR     |
//| rugi; SL ketat di tepi zona = penyebab utama kerugian.            |
//| Yang lolos: BREAKER BLOCK tinggi >= 1 ATR(M5), limit di tepi      |
//| proksimal, SL di balik zona + 0.5 ATR, TP 2R:                     |
//|   +0.25R / +0.26R / +0.24R (latih / validasi / uji), parameter    |
//|   tetangga juga positif. Order berlaku 24 jam.                    |
//+------------------------------------------------------------------+
#ifndef GP_PRECISION_MQH
#define GP_PRECISION_MQH

#include "..\Core\SMC_Types.mqh"
#include "..\Core\SMC_Utils.mqh"
#include "..\Detection\SMC_POI.mqh"
#include "..\Core\GP_Notify.mqh"

// UJI MULTI-TAHUN (27 Sep 2026, aturan dikunci): 2017-2025 = -0.43R dgn biaya (-0.02R tanpa biaya),
// 0 dari 9 tahun positif. Keunggulan +0.25R hanya di tahun riset -> BELUM KOKOH.
// Setup tetap dihitung & dicatat di jurnal (forward test: apakah rezim sekarang masih mendukung),
// tetapi TIDAK digambar di chart secara default.
input group "=== GoldPro: Breaker Block (1 th saja, gagal 2017-2025) ==="
input bool   InpShowBreakerSetup = true;            // Hitung setup breaker + catat di jurnal forward test
input bool   InpDrawBreakerSetup = false;           // Gambar garis LIMIT/SL/TP di chart (default mati: belum kokoh)
input double InpBrkMinATR        = 1.0;             // Tinggi zona minimum (x ATR M5)
input double InpBrkSLBufATR      = 0.5;             // SL di balik zona + ini x ATR
input double InpBrkRR            = 2.0;             // TP (x risiko)
input int    InpBrkValidHours    = 24;              // Limit order berlaku (jam)
input color  InpBrkBuyColor      = clrDeepSkyBlue;  // Warna setup BUY
input color  InpBrkSellColor     = clrOrangeRed;    // Warna setup SELL

#define GPS_PFX "GPS_"

struct BrkTrack
  {
   long              id;
   datetime          seen;     // saat breaker pertama terlihat (= saat terdeteksi)
   bool              bull;
   double            top, bot, atr;
   bool              eligible; // lolos filter tinggi zona & harga masih di luar zona
   bool              logged;
  };

BrkTrack g_brk[];
bool     g_brkInit = false;
datetime g_brkLastBar = 0;

int GP_BrkFind(long id)
  {
   for(int i = 0; i < ArraySize(g_brk); i++)
      if(g_brk[i].id == id) return i;
   return -1;
  }

//--- status setup dengan memutar bar M5 sejak terdeteksi
//    0 menunggu, 1 aktif, 2 TP, 3 SL, 4 kedaluwarsa/batal
int GP_BrkStatus(const BrkTrack &b, double &en, double &sl, double &tp, datetime &tFill, datetime &tEnd)
  {
   int d = b.bull ? 1 : -1;
   en = b.bull ? b.top : b.bot;
   sl = b.bull ? b.bot - InpBrkSLBufATR * b.atr : b.top + InpBrkSLBufATR * b.atr;
   double risk = MathAbs(en - sl);
   tp = en + d * InpBrkRR * risk;
   tFill = 0; tEnd = 0;
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_M5, b.seen, TimeCurrent(), r);
   if(n <= 0) return 0;
   datetime expiry = b.seen + InpBrkValidHours * 3600;
   bool filled = false;
   for(int k = 0; k < n; k++)
     {
      if(r[k].time < b.seen) continue;
      double sp = r[k].spread * _Point;
      if(!filled)
        {
         if(r[k].time >= expiry) { tEnd = r[k].time; return 4; }
         bool hit = b.bull ? (r[k].low + sp <= en) : (r[k].high >= en);
         if(!hit) continue;
         filled = true; tFill = r[k].time;
         if((b.bull && r[k].low <= sl) || (!b.bull && r[k].high + sp >= sl)) { tEnd = r[k].time; return 3; }
         continue;
        }
      if(b.bull)
        {
         if(r[k].low <= sl)  { tEnd = r[k].time; return 3; }
         if(r[k].high >= tp) { tEnd = r[k].time; return 2; }
        }
      else
        {
         if(r[k].high + sp >= sl) { tEnd = r[k].time; return 3; }
         if(r[k].low + sp <= tp)  { tEnd = r[k].time; return 2; }
        }
      if(r[k].time >= tFill + 86400) { tEnd = r[k].time; return 4; }
     }
   return filled ? 1 : 0;
  }

void GP_BrkLine(string n, datetime t1, datetime t2, double p, color c, ENUM_LINE_STYLE st, int w)
  {
   ObjectCreate(0, n, OBJ_TREND, 0, t1, p, t2, p);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_STYLE, st);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
  }

void GP_BrkText(string n, datetime t, double p, string s, color c, ENUM_ANCHOR_POINT a)
  {
   ObjectCreate(0, n, OBJ_TEXT, 0, t, p);
   ObjectSetString(0, n, OBJPROP_TEXT, s);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, a);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
  }

void GP_BrkJournal(const BrkTrack &b, double en, double sl, double tp)
  {
   string f = "GoldDayMap\\journal_breaker.csv";
   int h = FileOpen(f, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(h == INVALID_HANDLE) return;
   if(FileSize(h) == 0)
      FileWriteString(h, "server_time,id,side,entry,sl,tp,zone_top,zone_bot,atr,valid_hours\r\n");
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, StringFormat("%s,%I64d,%d,%s,%s,%s,%s,%s,%.2f,%d\r\n", TimeToString(b.seen, TIME_DATE | TIME_MINUTES), b.id,
                   b.bull ? 1 : -1, DoubleToString(en, _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits),
                   DoubleToString(b.top, _Digits), DoubleToString(b.bot, _Digits), b.atr, InpBrkValidHours));
   FileClose(h);
  }

//======================================================================
// UPDATE - sekali per bar M5 baru (terlepas dari timeframe chart)
//======================================================================
void GP_Precision_Update(bool journalOwner)
  {
   if(!InpShowBreakerSetup) return;
   datetime m5 = iTime(_Symbol, PERIOD_M5, 0);
   if(m5 == 0 || m5 == g_brkLastBar) return;
   g_brkLastBar = m5;

   //--- daftarkan breaker baru
   for(int i = 0; i < GetOBCount(); i++)
     {
      OrderBlock o;
      if(!GetOB(i, o) || o.poiType != POI_BREAKER || GP_BrkFind(o.id) >= 0) continue;
      BrkTrack b;
      b.id = o.id; b.bull = o.isBullish;
      b.top = MathMax(o.high, o.low); b.bot = MathMin(o.high, o.low);
      b.seen = g_brkInit ? m5 : o.time;              // saat backfill awal: pakai waktu zona (supaya yang lama kedaluwarsa)
      int sh = iBarShift(_Symbol, PERIOD_M5, b.seen);
      b.atr = GetATR(PERIOD_M5, 14, MathMax(sh, 1));
      double c0 = iClose(_Symbol, PERIOD_M5, MathMax(sh, 1));
      b.eligible = (b.atr > 0) && (b.top - b.bot >= InpBrkMinATR * b.atr) &&
                   (b.bull ? c0 > b.top : c0 < b.bot);
      b.logged = !g_brkInit;                         // hanya catat setup yang muncul setelah indikator aktif
      int n = ArraySize(g_brk);
      ArrayResize(g_brk, n + 1);
      g_brk[n] = b;
      if(g_brkInit && b.eligible && InpGPAlertBreaker)
        {
         double en = b.bull ? b.top : b.bot, sl = b.bull ? b.bot - InpBrkSLBufATR * b.atr : b.top + InpBrkSLBufATR * b.atr;
         double tp = en + (b.bull ? 1 : -1) * InpBrkRR * MathAbs(en - sl);
         GP_Notify("brk" + IntegerToString(b.id), StringFormat("setup BREAKER %s LIMIT %s, SL %s, TP %s (1 th saja, gagal 2017-25)",
                   b.bull ? "BUY" : "SELL", DoubleToString(en, _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits)), b.seen);
        }
     }
   g_brkInit = true;

   //--- gambar ulang
   ObjectsDeleteAll(0, GPS_PFX);
   datetime now = TimeCurrent();
   for(int i = ArraySize(g_brk) - 1; i >= 0; i--)
     {
      if(now - g_brk[i].seen > 3 * 86400)
        { ArrayRemove(g_brk, i, 1); continue; }
      if(!g_brk[i].eligible) continue;
      double en, sl, tp; datetime tF, tE;
      int st = GP_BrkStatus(g_brk[i], en, sl, tp, tF, tE);
      if(journalOwner && !g_brk[i].logged && st <= 1)
        { GP_BrkJournal(g_brk[i], en, sl, tp); g_brk[i].logged = true; }
      if(st == 4 || !InpDrawBreakerSetup) continue;
      if((st == 2 || st == 3) && now - tE > 12 * 3600) continue;   // hasil lama tidak perlu digambar
      color c = g_brk[i].bull ? InpBrkBuyColor : InpBrkSellColor;
      string id = GPS_PFX + IntegerToString(g_brk[i].id) + "_";
      datetime t1 = g_brk[i].seen, t2 = (st >= 2) ? tE : MathMax(now, g_brk[i].seen + InpBrkValidHours * 3600);
      GP_BrkLine(id + "E", t1, t2, en, c, st == 0 ? STYLE_DASH : STYLE_SOLID, 2);
      GP_BrkLine(id + "S", t1, t2, sl, clrTomato, STYLE_DOT, 1);
      GP_BrkLine(id + "T", t1, t2, tp, clrLimeGreen, STYLE_DOT, 1);
      string stx = (st == 0) ? "MENUNGGU" : (st == 1) ? "AKTIF" : (st == 2) ? "TP +2R" : "SL -1R";
      GP_BrkText(id + "L", t1, en, StringFormat(" BREAKER %s LIMIT %s | SL %s | TP %s | %s | 1 th saja, gagal 2017-25",
                 g_brk[i].bull ? "BUY" : "SELL", DoubleToString(en, _Digits), DoubleToString(sl, _Digits),
                 DoubleToString(tp, _Digits), stx), c, g_brk[i].bull ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
     }
   ChartRedraw();
  }

void GP_Precision_Deinit(bool isFinal = true)
  {
   if(isFinal)
      ObjectsDeleteAll(0, GPS_PFX);
  }

#endif // GP_PRECISION_MQH
