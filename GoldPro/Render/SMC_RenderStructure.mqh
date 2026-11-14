//+------------------------------------------------------------------+
//|                                            SMC_RenderStructure.mqh |
//|                                                                  |
//| Fase 5 - File 17/24 : SMC Pro System (REVISI - Story Chart)      |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Label BOS/CHoCH di titik break - HANYA ini. Label swing         |
//|   ("Strong Low"/"Weak High") DIHAPUS dari render default: bukan   |
//|   bagian dari cerita (pijakan -> tujuan -> POI -> konfirmasi),    |
//|   cuma noise deteksi mentah. Sesuai prinsip: kalau ragu antara    |
//|   tampilkan vs sembunyikan, pilih sembunyikan.                    |
//|                                                                  |
//|   Label BOS/CHoCH masuk kategori SMC_CAT_STRUCT_LABEL (maks 3     |
//|   ditampilkan sekaligus - lihat SMC_ObjectPool.mqh). Ini "histori"|
//|   dalam arti tidak dihapus begitu harga bergerak menjauh (beda    |
//|   dari zona POI yang hilang saat dimitigasi) - tapi tetap dibatasi|
//|   ke 3 PALING BARU untuk menjaga chart tetap "Story Chart", bukan  |
//|   pameran seluruh histori struktur.                              |
//+------------------------------------------------------------------+
#ifndef SMC_RENDERSTRUCTURE_MQH
#define SMC_RENDERSTRUCTURE_MQH

#include "..\Core\SMC_Config.mqh"
#include "..\Detection\SMC_Structure.mqh"
#include "SMC_ObjectPool.mqh"

//======================================================================
// Label BOS/CHoCH - kecil, di titik break, warna sesuai ARAH
// (hijau=bullish, merah=bearish), bukan garis panjang.
//======================================================================
void RenderStructureLabels()
  {
   int total = GetStructureEventCount();
   if(total == 0)
      return;

   // Cukup render beberapa event PALING BARU - batas keras dijaga juga
   // oleh ObjectPool (SMC_MAX_STRUCT_LABELS), ini cuma optimasi supaya
   // tidak looping seluruh histori tiap bar kalau tidak perlu.
   int startIndex = MathMax(0, total - SMC_MAX_STRUCT_LABELS);

   for(int i = startIndex; i < total; i++)
     {
      StructureEvent evt;
      if(!GetStructureEvent(i, evt))
         continue;

      string name = SMC_OBJ_PREFIX + "STRUCTLBL_" + IntegerToString(evt.id);
      // GoldPro: dulu arah turun memakai warna input CHoCH (emas) -> BOS turun tampak seperti CHoCH.
      // Sekarang warna = ARAH (hijau naik / merah turun), teks = jenis (BOS / CHoCH).
      color  col  = AdaptAccentColor(evt.direction == BIAS_BULLISH ? InpColorBOS : clrTomato);
      string label = evt.isBOS ? "BOS" : "CHoCH";

      CreateOrUpdateText(name, evt.time, evt.price, label, col, 8,
                          evt.direction == BIAS_BULLISH ? ANCHOR_LOWER : ANCHOR_UPPER,
                          SMC_CAT_STRUCT_LABEL);
     }
  }

//======================================================================
// FUNGSI UTAMA - dipanggil dari SMC_RenderAll() di SMC_Main.mq5
//======================================================================
void SMC_RenderStructure()
  {
   RenderStructureLabels();
  }

#endif // SMC_RENDERSTRUCTURE_MQH