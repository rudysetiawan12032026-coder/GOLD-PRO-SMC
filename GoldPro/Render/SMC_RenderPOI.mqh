//+------------------------------------------------------------------+
//|                                                 SMC_RenderPOI.mqh |
//|                                                                  |
//| Fase 5 - File 18/24 : SMC Pro System (REVISI - Story Chart)      |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   (1) Zona Premium/Discount/Equilibrium/OTE - KONTEKS, SELALU     |
//|       tampil, update tiap bar, alpha rendah (~32%).               |
//|   (2) Zona POI (OB) - HANYA yang relevan dengan cerita saat ini:  |
//|       POI "pijakan" (nearest unmitigated OB searah bias) dan,     |
//|       kalau ada, POI "tujuan" (OB berlawanan dekat target         |
//|       liquidity). Maksimal 2 zona POI biasanya tampil sekaligus - |
//|       jauh di bawah batas keras ObjectPool (3).                   |
//|                                                                  |
//| PRINSIP: Render TIDAK menghitung ulang apapun - cuma memilih APA  |
//| yang relevan dari data yang SUDAH dihitung Detection layer, lalu  |
//| menggambarnya. Memilih relevansi tampilan BUKAN pelanggaran       |
//| terhadap prinsip itu (beda dari menghitung ulang deteksi).        |
//+------------------------------------------------------------------+
#ifndef SMC_RENDERPOI_MQH
#define SMC_RENDERPOI_MQH

#include "..\Core\SMC_Config.mqh"
#include "..\Analysis\SMC_Scoring.mqh"
#include "..\Detection\SMC_POI.mqh"
#include "..\Detection\SMC_Zones.mqh"
#include "..\Detection\SMC_Liquidity.mqh"
#include "..\Core\GP_TouchTime.mqh"
#include "SMC_ObjectPool.mqh"

datetime GetRenderEndTime()
  {
   return TimeCurrent() + PeriodSeconds(PERIOD_CURRENT) * 20;
  }

// ClampRenderStartTime() DIPINDAH ke SMC_ObjectPool.mqh (dipakai lintas
// file render, lihat catatan di sana).

datetime GetCappedRenderEndTime(datetime originTime)
  {
   datetime naturalEnd = GetRenderEndTime();
   datetime cappedEnd  = originTime + PeriodSeconds(PERIOD_CURRENT) * InpOBMaxWidthBars;
   return (datetime)MathMin((long)naturalEnd, (long)cappedEnd);
  }

string ZoneLabelWord(ENUM_PRICE_ZONE z)
  {
   switch(z)
     {
      case PRICEZONE_DISCOUNT:    return "Discount";
      case PRICEZONE_PREMIUM:     return "Premium";
      case PRICEZONE_EQUILIBRIUM: return "Equilibrium";
      case PRICEZONE_OTE:         return "OTE";
      default:                     return "";
     }
  }

color ZoneLabelColor(ENUM_PRICE_ZONE z)
  {
   switch(z)
     {
      case PRICEZONE_DISCOUNT: return AdaptAccentColor(clrLimeGreen);
      case PRICEZONE_PREMIUM:  return AdaptAccentColor(clrTomato);
      case PRICEZONE_OTE:      return AdaptAccentColor(clrGoldenrod);
      default:                  return GetAdaptiveMutedTextColor();
     }
  }

//======================================================================
// Gambar SATU zona OB dengan nama tetap (bukan per-ID) - dipakai untuk
// slot "pijakan" dan slot "tujuan". Nama tetap berarti dedupe otomatis:
// begitu OB yang relevan berganti, object yang SAMA cuma dipindah, tidak
// pernah ada duplikat menumpuk.
//======================================================================
void RenderPOISlot(string slotName, OrderBlock &ob)
  {
   datetime renderStart = ClampRenderStartTime(ob.time);
   // GoldPro PERBAIKAN (screenshot M1 30 Sep): ujung kanan dulu = asal OB + 100 bar, sedangkan ujung kiri
   // dipotong ke 200 bar terakhir -> OB AKTIF berumur >~300 bar tergambar sebagai garis tipis (lebar 0)
   // di titik potong, bukan zona. Zona yang masih aktif (belum termitigasi) diperpanjang sampai sekarang.
   datetime renderEnd   = (ob.status == ZONE_FRESH || ob.status == ZONE_PARTIAL) ? GetRenderEndTime()
                                                                                  : GetCappedRenderEndTime(ob.time);
   if(renderEnd <= renderStart)
      renderEnd = GetRenderEndTime();

   color baseColor;
   if(ob.poiType == POI_BREAKER)
      baseColor = InpColorBreaker;
   else if(ob.poiType == POI_MITIGATION)
      baseColor = InpColorMitigation;
   else
      baseColor = GetColorForOB(ob.isBullish, ob.status);

   // FIX (screenshot review): 0.78 terlalu pekat, terutama untuk warna
   // saturasi tinggi seperti InpColorBullishOB (DodgerBlue) - jadi blok
   // solid yang mendominasi chart begitu digabung dengan garis EQH/EQL
   // Fase 2 di sekitarnya. Turunkan ke 0.55, konsisten dengan level
   // opacity zona Premium/Discount/OTE.
   color renderColor = BlendColor(baseColor, GetChartBackgroundColor(), 0.55);

   CreateOrUpdateRectangle(SMC_OBJ_PREFIX + "POI_" + slotName, renderStart, ob.high, renderEnd, ob.low,
                            renderColor, true, true, STYLE_SOLID, SMC_CAT_POI_ZONE);

   string bandText = POITypeText(ob);
   if(ob.isConfluent)
      bandText += " *";
   // GoldPro (2 Okt 2026): peluang harga DATANG ke tepi zona terdekat (GP_TouchTime). Slot ANCHOR = Pijakan:
   // angkanya sudah di label garis Pijakan pada harga yang sama -> tidak diulang (dulu label bertumpuk).
   if(slotName != "ANCHOR")
      bandText += TT_ZoneText(ob.low, ob.high, false);

   datetime midTime = renderStart + (renderEnd - renderStart) / 2;
   CreateOrUpdateText(SMC_OBJ_PREFIX + "POILBL_" + slotName, midTime, ob.ceLevel, bandText,
                       clrWhite, 8, ANCHOR_CENTER, SMC_CAT_OTHER); // label ikut zona, tidak dihitung kuota terpisah
   TT_SetTip(SMC_OBJ_PREFIX + "POILBL_" + slotName, TT_ZoneTip(POITypeText(ob), ob.low, ob.high));

   // FIX (screenshot review - "Premium" muncul DOBEL): label zona ini
   // (POITAG) redundan dengan label zona UTAMA dari
   // RenderDealingRangeZones() - OB ini sudah SECARA VISUAL berada di
   // dalam pita zona yang sama, jadi menuliskan ulang nama zonanya di
   // sini tidak menambah informasi, cuma menduplikasi. Dihapus total,
   // bukan cuma disembunyikan (kode mati).
  }

//======================================================================
// Pilih & render POI yang relevan dengan cerita: pijakan (searah bias)
// dan, kalau ada, tujuan (OB lain dekat level liquidity target).
//======================================================================
void RenderStoryPOI()
  {
   BiasState bs = GetBiasState();
   if(bs.ltfBias == BIAS_NEUTRAL)
      return; // belum ada cerita arah - tidak ada "pijakan" untuk digambar

   double currentPrice = iClose(_Symbol, PERIOD_CURRENT, 1);
   bool   wantBullish  = (bs.ltfBias == BIAS_BULLISH);

   OrderBlock anchorOB;
   bool hasAnchor = GetNearestUnmitigatedOB(wantBullish, currentPrice, anchorOB, true);
   if(hasAnchor)
      RenderPOISlot("ANCHOR", anchorOB);

   // POI "tujuan": cari OB BERLAWANAN arah (representasi confirmation
   // zone di seberang) yang dekat dengan level liquidity target - kalau
   // ada. Kalau tidak ada yang cukup dekat, tidak digambar (lebih baik
   // sembunyikan daripada memaksa menampilkan sesuatu yang tidak relevan).
   LiquidityPool target;
   if(GetNearestLiquidityTarget(wantBullish, currentPrice, target))
     {
      OrderBlock destOB;
      if(GetNearestUnmitigatedOB(!wantBullish, target.price, destOB))
        {
         double atr = GetATR(PERIOD_CURRENT, 14, 1);
         double proximity = (atr > 0) ? atr * 1.5 : 0;
         double obMid = destOB.ceLevel;
         if(proximity > 0 && MathAbs(obMid - target.price) <= proximity)
            RenderPOISlot("TARGET", destOB);
        }
     }
  }

//======================================================================
// Zona Premium/Discount/Equilibrium/OTE - KONTEKS, selalu tampil.
//======================================================================
void RenderDealingRangeZones()
  {
   DealingRange dr;
   if(!GetDealingRange(dr))
      return;

   datetime endTime   = GetRenderEndTime();
   datetime startTime = ClampRenderStartTime(dr.time_start);

   CreateOrUpdateRectangle(SMC_OBJ_PREFIX + "ZONE_DISCOUNT", startTime, dr.low, endTime, dr.midpoint,
                            AdaptZoneColor(InpColorDiscountZone), true, true, STYLE_SOLID, SMC_CAT_OTHER);
   CreateOrUpdateRectangle(SMC_OBJ_PREFIX + "ZONE_PREMIUM", startTime, dr.midpoint, endTime, dr.high,
                            AdaptZoneColor(InpColorPremiumZone), true, true, STYLE_SOLID, SMC_CAT_OTHER);

   double oteLow  = MathMin(dr.oteBottom, dr.oteTop);
   double oteHigh = MathMax(dr.oteBottom, dr.oteTop);
   // GoldPro 14 Okt 2026 (pengguna: "warnanya yg membuat saya bingung"): kotak berisi warna yang TUMPANG TINDIH dicampur MT5
   // (Premium merah muda + OTE kuning = hijau gelap, Discount + OTE = biru tua) -> warna tanpa arti. OTE & Equilibrium kini GARIS
   // TEPI saja (tanpa isi): tiap warna punya satu arti (merah muda = Premium, hijau = Discount, garis emas titik = OTE, abu = EQ).
   CreateOrUpdateRectangle(SMC_OBJ_PREFIX + "ZONE_OTE", startTime, oteHigh, endTime, oteLow,
                            AdaptAccentColor(clrGoldenrod), false, true, STYLE_DOT, SMC_CAT_OTHER);

   double eqBandHalfHeight = (dr.high - dr.low) * 0.015;
   CreateOrUpdateRectangle(SMC_OBJ_PREFIX + "ZONE_EQ", startTime, dr.midpoint + eqBandHalfHeight,
                            endTime, dr.midpoint - eqBandHalfHeight,
                            BlendColor(clrGray, GetChartBackgroundColor(), 0.8), false, true, STYLE_SOLID, SMC_CAT_OTHER);

   double discountLabelPrice = (dr.low + dr.midpoint) / 2.0;
   double premiumLabelPrice  = (dr.midpoint + dr.high) / 2.0;
   double oteLabelPrice      = (oteLow + oteHigh) / 2.0;

   // FIX (perjelas tujuan candle #4): label dipindah ke TENGAH kotak,
   // TAPI dibatasi ke bagian "proyeksi kosong" (antara sekarang dan
   // endTime) - BUKAN tengah keseluruhan kotak (yang mencakup histori
   // candle penuh). Kalau dipusatkan ke seluruh rentang, teks akan
   // menimpa candle - bertentangan dengan prinsip "jangan menutupi
   // candle" yang sudah disepakati sejak awal proyek ini.
   datetime midTime = (datetime)(TimeCurrent() + (endTime - TimeCurrent()) / 2);

   // GoldPro (2 Okt 2026): peluang harga DATANG (GP_TouchTime). Tepi terdekat Premium/Discount dari luar = garis
   // Equilibrium -> angkanya cukup di label Equilibrium (dulu dobel); Premium/Discount hanya "(harga di sini)".
   double bidZ = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string discTxt = (bidZ >= dr.low && bidZ <= dr.midpoint) ? " (harga di sini)" : "";
   string premTxt = (bidZ >= dr.midpoint && bidZ <= dr.high) ? " (harga di sini)" : "";
   // Kotak kecil di layar (< 15% tinggi chart, screenshot 2 Okt: 4 label berdesakan dlm ~$8) -> SATU label di Equilibrium
   double vis = ChartGetDouble(0, CHART_PRICE_MAX) - ChartGetDouble(0, CHART_PRICE_MIN);
   if(vis > 0.0 && (dr.high - dr.low) < 0.15 * vis)
     {
      string where = (premTxt != "") ? "di Premium" : ((discTxt != "") ? "di Discount" : (bidZ > dr.high ? "di atas kotak" : "di bawah kotak"));
      CreateOrUpdateText(SMC_OBJ_PREFIX + "ZONE_LBL_EQ", midTime, dr.midpoint,
                          "EQ" + TT_ZoneText(dr.midpoint, dr.midpoint, false) + " (harga " + where + ")",
                          GetAdaptiveMutedTextColor(), 8, ANCHOR_CENTER, SMC_CAT_OTHER);
      TT_SetTip(SMC_OBJ_PREFIX + "ZONE_LBL_EQ", TT_ZoneTip("Equilibrium", dr.midpoint, dr.midpoint) +
                StringFormat("\nPremium %s-%s | Discount %s-%s | OTE %s-%s", DoubleToString(dr.midpoint, _Digits),
                             DoubleToString(dr.high, _Digits), DoubleToString(dr.low, _Digits), DoubleToString(dr.midpoint, _Digits),
                             DoubleToString(oteLow, _Digits), DoubleToString(oteHigh, _Digits)));
      return;
     }
   CreateOrUpdateText(SMC_OBJ_PREFIX + "ZONE_LBL_DISC", midTime, discountLabelPrice, "Discount" + discTxt,
                       AdaptAccentColor(clrGreen), 8, ANCHOR_CENTER, SMC_CAT_OTHER);
   CreateOrUpdateText(SMC_OBJ_PREFIX + "ZONE_LBL_PREM", midTime, premiumLabelPrice, "Premium" + premTxt,
                       AdaptAccentColor(clrRed), 8, ANCHOR_CENTER, SMC_CAT_OTHER);
   CreateOrUpdateText(SMC_OBJ_PREFIX + "ZONE_LBL_OTE", midTime, oteLabelPrice, "OTE" + TT_ZoneText(oteLow, oteHigh, false),
                       AdaptAccentColor(clrGoldenrod), 8, ANCHOR_CENTER, SMC_CAT_OTHER);
   CreateOrUpdateText(SMC_OBJ_PREFIX + "ZONE_LBL_EQ", midTime, dr.midpoint, "Equilibrium" + TT_ZoneText(dr.midpoint, dr.midpoint, true),
                       GetAdaptiveMutedTextColor(), 8, ANCHOR_CENTER, SMC_CAT_OTHER);
   TT_SetTip(SMC_OBJ_PREFIX + "ZONE_LBL_DISC", TT_ZoneTip("Discount", dr.low, dr.midpoint));
   TT_SetTip(SMC_OBJ_PREFIX + "ZONE_LBL_PREM", TT_ZoneTip("Premium", dr.midpoint, dr.high));
   TT_SetTip(SMC_OBJ_PREFIX + "ZONE_LBL_OTE", TT_ZoneTip("OTE", oteLow, oteHigh));
   TT_SetTip(SMC_OBJ_PREFIX + "ZONE_LBL_EQ", TT_ZoneTip("Equilibrium", dr.midpoint, dr.midpoint));
  }

//======================================================================
// FUNGSI UTAMA
//======================================================================
void SMC_RenderPOI()
  {
   RenderDealingRangeZones();
   RenderStoryPOI();
  }

#endif // SMC_RENDERPOI_MQH