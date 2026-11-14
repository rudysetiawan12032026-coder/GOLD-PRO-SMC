//+------------------------------------------------------------------+
//|                                            SMC_RenderLiquidity.mqh |
//|                                                                  |
//| Fase 5 - File 19/24 : SMC Pro System (REVISI TOTAL - Story Chart)|
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   - "Pijakan"/"Tujuan": 2 garis nama TETAP (Fase Story Chart      |
//|     awal) - level POI dasar bias & liquidity target terdekat.    |
//|   - EQH/EQL/POOL (Fase 2, adopsi xxvw/SMC_ICT_Library): sampai    |
//|     5 slot TETAP per sisi (high/low), diisi pool VALID terdekat   |
//|     dari harga. Total garis liquidity maksimal 12 (2+5+5),        |
//|     masih di bawah batas keras SMC_MAX_LINES=15 di ObjectPool.    |
//|   Semua nama object TETAP (per slot, bukan per-ID) -> lifecycle   |
//|   otomatis: slot yang tidak terisi siklus ini otomatis hilang     |
//|   lewat RemoveIfStale(), tidak pernah menumpuk.                   |
//+------------------------------------------------------------------+
#ifndef SMC_RENDERLIQUIDITY_MQH
#define SMC_RENDERLIQUIDITY_MQH

#include "..\Core\SMC_Config.mqh"
#include "..\Analysis\SMC_Scoring.mqh"
#include "..\Detection\SMC_POI.mqh"
#include "..\Detection\SMC_Liquidity.mqh"
#include "..\Core\GP_TouchTime.mqh"
#include "SMC_ObjectPool.mqh"

// FIX #2 (screenshot zoom-out MASIH kacau meski sudah dipisah +10/+20
// bar tetap): offset bar TETAP ikut mengecil ke piksel begitu di-zoom
// out - makin banyak bar termampatkan ke lebar layar yang sama, jarak
// 10-20 bar jadi nyaris nol piksel lagi. Fix yang benar: offset
// PROPORSIONAL terhadap CHART_WIDTH_IN_BARS (jumlah bar yang SEDANG
// terlihat di layar) - supaya jarak pisah tetap sekitar sekian % lebar
// layar, di ZOOM LEVEL BERAPAPUN, bukan sekian bar tetap.
int GetProportionalOffsetBars(double fractionOfVisibleWidth, int minBars)
  {
   long visibleBars = ChartGetInteger(0, CHART_WIDTH_IN_BARS);
   if(visibleBars <= 0)
      visibleBars = 100; // fallback wajar kalau API belum siap
   return (int)MathMax(minBars, visibleBars * fractionOfVisibleWidth);
  }

datetime GetLiqRenderEndTime()
  {
   int offsetBars = GetProportionalOffsetBars(0.10, 10); // 10% lebar layar, minimal 10 bar
   return TimeCurrent() + PeriodSeconds(PERIOD_CURRENT) * offsetBars;
  }

//======================================================================
// Garis Pijakan - level POI (OB) yang jadi dasar bias saat ini.
//======================================================================
void RenderAnchorLine()
  {
   BiasState bs = GetBiasState();
   if(bs.ltfBias == BIAS_NEUTRAL)
      return; // tidak ada bias = tidak ada "pijakan" untuk diceritakan

   double currentPrice = iClose(_Symbol, PERIOD_CURRENT, 1);
   bool   wantBullish  = (bs.ltfBias == BIAS_BULLISH);

   OrderBlock anchorOB;
   if(!GetNearestUnmitigatedOB(wantBullish, currentPrice, anchorOB, true))
      return; // tidak ada POI valid di sisi yang benar - jangan gambar garis kosong

   datetime endTime = GetLiqRenderEndTime();
   color col = AdaptAccentColor(wantBullish ? clrDodgerBlue : clrCrimson);

   // GoldPro: jenis zona sebenarnya (OB / Breaker) + status (segar / sudah disentuh)
   string labelText = StringFormat("Pijakan %s%s %s", POITypeText(anchorOB),
                                    anchorOB.status == ZONE_PARTIAL ? " (tersentuh)" : "",
                                    DoubleToString(anchorOB.ceLevel, _Digits));
   // GoldPro (2 Okt 2026): peluang harga DATANG ke Pijakan dalam 1 / 2 jam (GP_TouchTime, uji 2022-26 +-1.8 poin)
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string tt = TT_Short(anchorOB.ceLevel - bid);
   if(tt != "")
      labelText += " | " + tt;
   g_ttPijPrice = anchorOB.ceLevel;
   g_ttPijName  = POITypeText(anchorOB);

   CreateOrUpdateTrendLine(SMC_OBJ_PREFIX + "LINE_ANCHOR", anchorOB.time, anchorOB.ceLevel,
                            endTime, anchorOB.ceLevel, col, STYLE_DASH, 1, false, SMC_CAT_LINE);
   CreateOrUpdateText(SMC_OBJ_PREFIX + "LBL_ANCHOR", endTime, anchorOB.ceLevel, labelText,
                       col, 7, ANCHOR_RIGHT, SMC_CAT_OTHER);
   string tip = TT_Tip("Pijakan " + g_ttPijName, anchorOB.ceLevel, bid);
   TT_SetTip(SMC_OBJ_PREFIX + "LBL_ANCHOR", tip);
   TT_SetTip(SMC_OBJ_PREFIX + "LINE_ANCHOR", tip);
  }

//======================================================================
// Garis Tujuan - liquidity terdekat yang belum di-sweep, searah bias.
//======================================================================
void RenderTargetLine()
  {
   BiasState bs = GetBiasState();
   if(bs.ltfBias == BIAS_NEUTRAL)
      return;

   double currentPrice = iClose(_Symbol, PERIOD_CURRENT, 1);
   bool   wantBuySide  = (bs.ltfBias == BIAS_BULLISH); // bullish -> target di atas (BSL)

   LiquidityPool target;
   if(!GetNearestLiquidityTarget(wantBuySide, currentPrice, target))
      return; // tidak ada target valid (semua sudah di-sweep, atau belum ada pool) - jangan gambar

   datetime endTime = GetLiqRenderEndTime();
   color col = AdaptAccentColor(clrGoldenrod);

   // FIX (perjelas tujuan candle #1): tambah harga + jarak dalam pips,
   // bukan cuma "Tujuan (BSL)" tanpa angka - ini yang bikin chart
   // "bercerita" (seberapa jauh, bukan cuma "ke arah mana").
   // GoldPro: jarak dalam $ untuk emas (dulu "pips" dengan 1 pip = $0.01 -> terbaca 10x lebih jauh);
   // "swing" bila target hanya 1 swing high/low (95% kasus), bukan equal high/low.
   string labelText = StringFormat("Tujuan %s%s %s (%s)",
                                    wantBuySide ? "BSL" : "SSL", target.touchCount >= 2 ? "" : " swing",
                                    DoubleToString(target.price, _Digits),
                                    DistanceText(MathAbs(target.price - currentPrice)));

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string tt = TT_Short(target.price - bid);
   if(tt != "")
      labelText += " | " + tt;
   g_ttTujPrice = target.price;
   g_ttTujName  = wantBuySide ? "BSL" : "SSL";

   CreateOrUpdateTrendLine(SMC_OBJ_PREFIX + "LINE_TARGET", target.firstTouch, target.price,
                            endTime, target.price, col, STYLE_DASHDOT, 1, false, SMC_CAT_LINE);
   CreateOrUpdateText(SMC_OBJ_PREFIX + "LBL_TARGET", endTime, target.price, labelText,
                       col, 7, ANCHOR_RIGHT, SMC_CAT_OTHER);
   string tip = TT_Tip("Tujuan " + g_ttTujName, target.price, bid);
   TT_SetTip(SMC_OBJ_PREFIX + "LBL_TARGET", tip);
   TT_SetTip(SMC_OBJ_PREFIX + "LINE_TARGET", tip);
  }

//======================================================================
// EQH/EQL/POOL - Fase 2. 5 slot TETAP per sisi (high/low), diisi ulang
// tiap render cycle dengan pool VALID terdekat dari harga saat ini.
// Nama slot TETAP (bukan per-ID) -> lifecycle otomatis lewat ObjectPool:
// kalau di suatu saat cuma ada 2 pool valid di sisi itu, slot 3-5
// otomatis tidak disentuh -> dihapus RemoveIfStale(), bukan menumpuk.
//======================================================================
// FIX (screenshot review #2 - masih numpuk dengan label zona): turunkan
// lagi dari 3 ke 2 per sisi (4 total). Prioritas kejelasan cerita di atas
// jumlah data yang ditampilkan - lebih sedikit tapi jelas > banyak tapi
// numpuk.
#define SMC_EQ_MAX_SLOTS_PER_SIDE 2

// FIX (perjelas tujuan candle #3): tambah harga eksplisit di label, dan
// pool yang SUDAH di-sweep dipudarkan (alpha visual via warna redup,
// MQL5 objek chart tidak punya alpha channel asli - didekati dengan abu
// keruh alih-alih kuning terang yang dulu terlalu mencolok).
string LiquidityLabelText(LiquidityPool &pool)
  {
   string base = (pool.type == LIQ_POOL_HIGH || pool.type == LIQ_POOL_LOW)
                 ? "LIQ POOL" : (pool.isBuySide ? "EQH" : "EQL");
   string text = StringFormat("%s (%dx) @ %s", base, pool.touchCount, DoubleToString(pool.price, _Digits));
   if(pool.swept)
      text += " SWEPT";
   return text;
  }

void RenderEqualHighsLowsSide(bool wantBuySide)
  {
   double currentPrice = iClose(_Symbol, PERIOD_CURRENT, 1);
   datetime endTime = GetLiqRenderEndTime();

   LiquidityPool pools[];
   int count = GetNearestValidPools(currentPrice, wantBuySide, SMC_EQ_MAX_SLOTS_PER_SIDE, pools);

   string sidePrefix = wantBuySide ? "EQ_HIGH_" : "EQ_LOW_";
   color  baseColor  = wantBuySide ? clrMagenta : clrCyan;

   for(int slot = 0; slot < SMC_EQ_MAX_SLOTS_PER_SIDE; slot++)
     {
      string lineName = SMC_OBJ_PREFIX + sidePrefix + IntegerToString(slot);
      string lblName  = SMC_OBJ_PREFIX + sidePrefix + "LBL_" + IntegerToString(slot);

      if(slot >= count)
        {
         // Slot ini tidak terisi siklus ini - hapus object lama kalau ada
         // (tidak disentuh = ObjectPool akan hapus otomatis di RemoveIfStale,
         // tapi dihapus eksplisit di sini juga aman & lebih cepat kelihatan).
         continue;
        }

      LiquidityPool p = pools[slot];
      bool  isSwept = p.swept;
      // FIX: SWEPT dipudarkan - warna abu keruh, bukan kuning terang
      // yang dulu terlalu mendominasi dibanding EQH/EQL yang masih aktif.
      color col   = isSwept ? AdaptAccentColor(clrDarkGray) : AdaptAccentColor(baseColor);
      int   style = isSwept ? STYLE_DOT : STYLE_SOLID;

      // FIX (screenshot review - label EQH/EQL terpotong "WEPT" karena
      // firstTouch jatuh di area yang tertutup panel dashboard): pakai
      // ClampRenderStartTime (sama seperti OB/Breaker) supaya titik
      // mula garis & label tidak terlalu jauh ke belakang.
      datetime lineStart = ClampRenderStartTime(p.firstTouch);

      CreateOrUpdateTrendLine(lineName, lineStart, p.price, endTime, p.price,
                               col, style, 1, false, SMC_CAT_LINE);

      // FIX #3 (persentase kecil TETAP kalah lawan lebar teks - dua
      // label masih bertabrakan walau "terpisah" secara persentase,
      // karena jaraknya dalam piksel absolut lebih kecil dari lebar
      // kotak teks itu sendiri). Solusi mendasar: label TIDAK LAGI
      // dipaksa berkumpul di satu jalur sempit dekat masa depan -
      // sekarang ditaruh di TITIK KEMUNCULAN pool itu sendiri
      // (lineStart, sudah di-clamp di atas), yang SECARA ALAMI beda-beda
      // untuk tiap pool (dibentuk di jam/hari berbeda) - jadi otomatis
      // tersebar horizontal tanpa perlu jalur buatan. Anchor LEFT (bukan
      // RIGHT)
      // karena sekarang teks ada di SEBELAH KIRI garis (dekat titik
      // mula), tumbuh ke kanan menjauhi histori candle di kirinya.
      // GoldPro 14 Okt 2026 (screenshot pengguna: deretan "EQH / EQL / LIQ POOL ... SWEPT" di kiri chart): pool yang SUDAH
      // tersapu = sejarah, bukan level aktif -> garis titik abu tetap, LABEL tidak digambar (dihapus RemoveIfStale).
      if(!isSwept)
         CreateOrUpdateText(lblName, lineStart, p.price, LiquidityLabelText(p),
                             col, 7, wantBuySide ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER, SMC_CAT_OTHER);
     }
  }

void RenderEqualHighsLows()
  {
   RenderEqualHighsLowsSide(true);  // EQH / POOL HIGH
   RenderEqualHighsLowsSide(false); // EQL / POOL LOW
  }

//======================================================================
// PDH/PDL/PWH/PWL/Daily-Weekly Open - BARU. Datanya SUDAH dihitung sejak
// awal proyek (UpdateDrawOnLiquidityRefs() di SMC_Liquidity.mqh) tapi
// belum pernah digambar di chart manapun - gap yang ditemukan lewat
// perbandingan dengan indikator SMC lain (PDH/PDL adalah level acuan
// likuiditas klasik, dipakai kompetitor). Warna dibedakan per jenis
// biar gampang dibedakan sekilas: PDH/PDL oranye terang, PWH/PWL oranye
// gelap, Daily/Weekly Open abu putus-putus (referensi netral).
//======================================================================
void RenderDrawOnLiquidityRefs()
  {
   datetime endTime = GetLiqRenderEndTime();
   int count = GetDrawOnLiquidityRefCount();

   for(int i = 0; i < count; i++)
     {
      DrawOnLiquidityRef ref;
      if(!GetDrawOnLiquidityRef(i, ref))
         continue;

      string lineName = SMC_OBJ_PREFIX + "DOL_" + IntegerToString(i);
      string lblName  = SMC_OBJ_PREFIX + "DOL_LBL_" + IntegerToString(i);
      datetime lineStart = ClampRenderStartTime(ref.referenceTime);

      color col;
      int   style;
      if(ref.label == "PDH" || ref.label == "PDL")
        {
         col   = AdaptAccentColor(clrOrange);
         style = STYLE_DASH;
        }
      else if(ref.label == "PWH" || ref.label == "PWL")
        {
         col   = AdaptAccentColor(clrDarkOrange);
         style = STYLE_DASHDOT;
        }
      else // Daily Open / Weekly Open
        {
         col   = AdaptAccentColor(clrGray);
         style = STYLE_DOT;
        }

      CreateOrUpdateTrendLine(lineName, lineStart, ref.price, endTime, ref.price,
                               col, style, 1, false, SMC_CAT_LINE);
      // GoldPro (3 Okt 2026): PDH/PDL + peluang harga DATANG (GP_TouchTime terkalibrasi) & sifat terukur: garis kemarin
      // cenderung DITEMBUS (research\line_graph.py / tembus_garis.py / route_table.py, M1 2017-26).
      string lbl = ref.label;
      if(ref.label == "PDH" || ref.label == "PDL")
        {
         bool   isH = (ref.label == "PDH");
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         bool   beyond = isH ? (bid > ref.price) : (bid < ref.price);
         if(beyond)
            lbl += isH ? " (harga di atas)" : " (harga di bawah)";
         else
           {
            string tt = TT_Short(ref.price - bid);
            if(tt != "") lbl += " | " + tt;
           }
         //--- 5 Okt 2026: peluang DITEMBUS s/d tutup hari ini (tabel live GoldPro: jarak & sisa jam; GDM::PdhlUpdate)
         double pb = isH ? g_pdhP : g_pdlP;
         if(pb >= 1.5)     lbl += " | TERTEMBUS hari ini";
         else if(pb >= 0)  lbl += " | tembus s/d tutup " + TT_Pct(pb);
         else              lbl += " | cenderung tembus";
        }
      CreateOrUpdateText(lblName, lineStart, ref.price, lbl,
                          col, 7, ANCHOR_LEFT_LOWER, SMC_CAT_OTHER);
      if(ref.label == "PDH" || ref.label == "PDL")
        {
         bool isH = (ref.label == "PDH");
         string tip = TT_Tip(ref.label + (isH ? " (high kemarin)" : " (low kemarin)"), ref.price, SymbolInfoDouble(_Symbol, SYMBOL_BID)) +
                      StringFormat("\n\nSifat terukur %s (XAUUSD M1 2017-26):\n"
                                   "- setelah disentuh dari %s, harga sampai garis GoldPro berikutnya di %s SEBELUM balik\n"
                                   "  ke garis asal %s (menurut jarak %s), %s tahun searah -> cenderung DITEMBUS.\n"
                                   "- memantul dari %s = rute terburuk (menang 46%% padahal jarak memperkirakan 55%%).\n"
                                   "- candle M5 close tembus / balik TIDAK menambah info (lanjut = sesuai jarak dari close).",
                                   ref.label, isH ? "bawah" : "atas", isH ? "atas" : "bawah",
                                   isH ? "45.8%" : "46.3%", isH ? "41.6%" : "43.2%", isH ? "9/10" : "8/10", ref.label);
         double pb = isH ? g_pdhP : g_pdlP;
         tip += StringFormat("\n\nPeluang %s DITEMBUS s/d tutup hari ini: %s\n"
                             "(tabel live GoldPro: jarak harga ke garis & sisa jam, uji 2017-26 meleset +-1.5 poin;\n"
                             " versi awal hari, jarak close kemarin: galat Brier 0.175 vs 0.250 tanpa jarak).",
                             ref.label, pb >= 1.5 ? "SUDAH tertembus" : (pb >= 0 ? TT_Pct(pb) : "- (market tutup)"));
         if(g_pdCls != "")
            tip += "\nKemarin: " + g_pdCls + ".\nTemuan GA (5 Okt 2026): setelah hari NAIK KUAT, PDH lebih sering ditembus; tapi pada\n"
                   "jarak yang sama kekuatan kemarin hanya menggeser +-1..6 poin & tidak memperbaiki uji 2022-26 -> info saja.";
         TT_SetTip(lblName, tip);
         TT_SetTip(lineName, tip);
        }
     }
  }

//======================================================================
// PANAH ARAH GANDA - REDESAIN (permintaan eksplisit: dua tahap prediksi
// yang saling terhubung, bukan satu panah tunggal).
//
//   Tahap 1 (skala PENDEK, kuning tipis): prediksi RETEST - harga
//   kemungkinan balik dulu ke Pijakan (OB terdekat yang belum
//   ter-mitigasi) sebelum lanjut. Konsep SMC klasik: breakout jarang
//   lurus, biasanya "napas" balik ke POI dulu.
//
//   Tahap 2 (skala LEBAR, hijau/merah tebal): prediksi LANJUTAN - DARI
//   titik retest itu (atau dari harga sekarang kalau tidak ada Pijakan
//   valid), menuju Tujuan (likuiditas jauh).
//
// Kedua titik (Pijakan, Tujuan) BUKAN angka baru - sudah dipakai blok
// Skenario & garis Pijakan/Tujuan yang sudah ada. Yang baru cuma cara
// MENGHUBUNGKANNYA jadi satu alur dua tahap.
//======================================================================
void RenderDirectionArrows()
  {
   // FIX (screenshot review - panah kontradiksi dengan Skenario): kalau
   // harga masih terkurung di range matang, arah BELUM ditentukan (itu
   // sebabnya Skenario bilang "tunggu breakout", bukan condong ke satu
   // arah). Panah TIDAK BOLEH menggambar arah percaya diri di kondisi
   // ini - konsisten dengan blok Skenario (IsInRange() dicek LEBIH DULU).
   if(IsInRange())
      return;

   BiasState bs = GetBiasState();
   if(bs.ltfBias == BIAS_NEUTRAL)
      return; // tidak ada arah - jangan gambar panah kosong

   double currentPrice = iClose(_Symbol, PERIOD_CURRENT, 1);
   bool   wantBullish  = (bs.ltfBias == BIAS_BULLISH);
   datetime nowTime     = iTime(_Symbol, PERIOD_CURRENT, 1);

   // --- TAHAP 1: retest ke Pijakan (skala pendek) ---
   OrderBlock anchorOB;
   bool hasAnchor = GetNearestUnmitigatedOB(wantBullish, currentPrice, anchorOB, true);
   datetime retestEndTime = nowTime + PeriodSeconds(PERIOD_CURRENT) * 4; // lebih dekat - skala pendek

   if(hasAnchor)
     {
      color retestColor = AdaptAccentColor(clrYellow);
      CreateOrUpdateArrowedLine(SMC_OBJ_PREFIX + "DIR_ARROW_SHORT", nowTime, currentPrice,
                                 retestEndTime, anchorOB.ceLevel, retestColor, 1, SMC_CAT_LINE);
      // GoldPro (2 Okt 2026): label diganti peluang TERUKUR - mana yang disentuh duluan, Pijakan atau Tujuan
      // (gerak acak: P = jarak ke Tujuan / jumlah kedua jarak; arah "duluan" GoldDayMap = geometri, uji akurat),
      // plus peluang Pijakan tersentuh dlm 1 jam. Pantulan dari Pijakan sendiri TIDAK terbukti.
      // Hanya "duluan xx%" (angka 1 jam sudah ada di garis Pijakan); tanpa Tujuan / market tutup -> tanpa label
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      LiquidityPool tgt;
      if(TT_MarketOpen() && GetNearestLiquidityTarget(wantBullish, currentPrice, tgt))
        {
         double dp = MathAbs(bid - anchorOB.ceLevel), dt = MathAbs(tgt.price - bid);
         if(dp + dt > 0)
           {
            // di TENGAH panah kuning (dulu di ujung = harga Pijakan -> bertumpuk dgn label garis Pijakan & kotaknya)
            datetime lblTime  = nowTime + (retestEndTime - nowTime) / 2;
            double   lblPrice = (currentPrice + anchorOB.ceLevel) / 2.0;
            CreateOrUpdateText(SMC_OBJ_PREFIX + "DIR_LBL_SHORT", lblTime, lblPrice, "duluan " + TT_Pct(dt / (dp + dt)),
                                retestColor, 7, ANCHOR_LEFT, SMC_CAT_OTHER);
            TT_SetTip(SMC_OBJ_PREFIX + "DIR_LBL_SHORT", StringFormat("Peluang Pijakan %s disentuh SEBELUM Tujuan %s: %s\n"
                      "(jarak relatif: Pijakan $%.2f, Tujuan $%.2f; gerak acak - akurat, bukan ramalan arah)",
                      DoubleToString(anchorOB.ceLevel, _Digits), DoubleToString(tgt.price, _Digits), TT_Pct(dt / (dp + dt)), dp, dt));
           }
        }
     }
   // Kalau tidak ada Pijakan valid, slot DIR_ARROW_SHORT/DIR_LBL_SHORT
   // tidak disentuh siklus ini - ObjectPool otomatis membersihkannya
   // (RemoveIfStale), tidak perlu penghapusan eksplisit di sini.

   // --- TAHAP 2: lanjutan ke Tujuan (skala lebar) - mulai dari titik
   //     retest kalau ada, atau langsung dari harga sekarang kalau tidak ---
   LiquidityPool target;
   if(!GetNearestLiquidityTarget(wantBullish, currentPrice, target))
      return; // tidak ada target valid - jangan gambar panah tanpa tujuan jelas

   datetime wideStartTime  = hasAnchor ? retestEndTime : nowTime;
   double   wideStartPrice = hasAnchor ? anchorOB.ceLevel : currentPrice;
   datetime wideEndTime    = wideStartTime + PeriodSeconds(PERIOD_CURRENT) * 10;

   color wideColor = AdaptAccentColor(wantBullish ? clrLime : clrRed);
   CreateOrUpdateArrowedLine(SMC_OBJ_PREFIX + "DIR_ARROW_WIDE", wideStartTime, wideStartPrice,
                              wideEndTime, target.price, wideColor, 2, SMC_CAT_LINE);
  }

//======================================================================
// FUNGSI UTAMA
//======================================================================
void SMC_RenderLiquidity()
  {
   RenderAnchorLine();
   RenderTargetLine();
   RenderEqualHighsLows();
   RenderDrawOnLiquidityRefs();
   RenderDirectionArrows();
  }

#endif // SMC_RENDERLIQUIDITY_MQH