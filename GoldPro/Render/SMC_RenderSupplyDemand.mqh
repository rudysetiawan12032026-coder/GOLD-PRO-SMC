//+------------------------------------------------------------------+
//|                                      SMC_RenderSupplyDemand.mqh |
//|                                                                  |
//| MODUL "PAUS" - BARU. Render zona Supply/Demand dari                |
//| SMC_SupplyDemand.mqh. SENGAJA beda warna & style dari OB biasa      |
//| (SMC_RenderPOI.mqh) - supaya user tidak salah kira ini order block |
//| ICT biasa. Cuma render 2 zona TERDEKAT (1 Demand + 1 Supply,        |
//| nama slot TETAP) - konsisten dengan prinsip "cerita ringkas"        |
//| yang sudah dipegang di seluruh render lain, walau di sesi ini        |
//| user bilang jumlah garis tidak prioritas - tetap dibatasi supaya     |
//| tidak menumpuk banyak zona H1 lebar sekaligus di chart LTF.          |
//+------------------------------------------------------------------+
#ifndef SMC_RENDERSUPPLYDEMAND_MQH
#define SMC_RENDERSUPPLYDEMAND_MQH

#include "..\Core\SMC_Config.mqh"
#include "..\Detection\SMC_SupplyDemand.mqh"
#include "SMC_ObjectPool.mqh"

//======================================================================
// RENDER SATU SISI (Demand atau Supply) - slot nama TETAP, lifecycle
// otomatis lewat ObjectPool (sama pola dengan seluruh render lain).
//======================================================================
void RenderSDZoneSide(bool wantDemand)
  {
   double currentPrice = iClose(_Symbol, PERIOD_CURRENT, 1);

   string boxName = SMC_OBJ_PREFIX + (wantDemand ? "SD_DEMAND" : "SD_SUPPLY");
   string lblName = SMC_OBJ_PREFIX + (wantDemand ? "SD_DEMAND_LBL" : "SD_SUPPLY_LBL");

   SDZone zone;
   if(!GetNearestSDZone(wantDemand, currentPrice, zone))
      return; // tidak ada zona valid sisi ini - slot dibiarkan kosong (ObjectPool bersihkan otomatis)

   datetime renderStart = ClampRenderStartTime(zone.baseStartTime);
   datetime renderEnd   = GetDefaultRenderEndTime();

   // Warna SENGAJA beda dari OB (yang pakai biru/merah DodgerBlue/Crimson) -
   // ungu untuk Demand, teal untuk Supply. Opacity 0.35 - lebih redup dari
   // OB (0.55) karena ini zona H1 yang lebih lebar, jangan sampai
   // mendominasi chart LTF.
   color baseColor = wantDemand ? clrMediumPurple : clrTeal;
   color renderColor = BlendColor(baseColor, GetChartBackgroundColor(), 0.35);

   CreateOrUpdateRectangle(boxName, renderStart, zone.high, renderEnd, zone.low,
                            renderColor, true, true, STYLE_SOLID, SMC_CAT_OTHER);

   string labelText = StringFormat("%s Paus (%s, %d bar %s)",
                                    wantDemand ? "Demand" : "Supply",
                                    SDPatternToString(zone.pattern), zone.baseCandleCount,
                                    StringSubstr(EnumToString(InpSDTimeframe), 7));
   datetime midTime = renderStart + (renderEnd - renderStart) / 2;
   double   midPrice = (zone.high + zone.low) / 2.0;
   CreateOrUpdateText(lblName, midTime, midPrice, labelText,
                       AdaptAccentColor(baseColor), 7, ANCHOR_CENTER, SMC_CAT_OTHER);
  }

//======================================================================
// FUNGSI UTAMA
//======================================================================
void SMC_RenderSupplyDemand()
  {
   if(!InpEnableSupplyDemand)
      return;

   RenderSDZoneSide(true);  // Demand terdekat
   RenderSDZoneSide(false); // Supply terdekat
  }

#endif // SMC_RENDERSUPPLYDEMAND_MQH
