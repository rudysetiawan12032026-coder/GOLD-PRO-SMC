//+------------------------------------------------------------------+
//|                                                SMC_ObjectPool.mqh |
//|                                                                  |
//| Fase 5 - File 16/24 : SMC Pro System (REVISI - Story Chart)      |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Satu-satunya file yang boleh langsung memanggil ObjectCreate/  |
//|   ObjectDelete untuk hal generik. Modul Render lain memanggil    |
//|   wrapper dari sini, bukan API MT5 langsung.                    |
//|                                                                  |
//| REVISI (filosofi "Story Chart" - naikkan prioritas dari Fase 5): |
//|   Setiap object sekarang punya LIFECYCLE berbasis "generasi      |
//|   render". Tiap siklus render (satu kali per bar baru), panggil  |
//|   SMC_ObjectPool_BeginCycle() dulu - ini menaikkan generasi.     |
//|   Semua CreateOrUpdate* men-"stempel" object yang disentuh       |
//|   dengan generasi SAAT INI. Di akhir siklus, RemoveIfStale()     |
//|   menghapus object manapun yang TIDAK disentuh di generasi ini - |
//|   artinya kalau sebuah render function BERHENTI menggambar       |
//|   sesuatu (karena perannya di cerita sudah selesai), object itu  |
//|   otomatis lenyap, tanpa perlu ObjectDelete manual di tiap       |
//|   tempat. Ini fondasi teknis dari prinsip "setiap elemen punya   |
//|   masa hidup".                                                  |
//|                                                                  |
//|   Kategori (dipakai untuk batas jumlah - lihat                  |
//|   EnforceCategoryLimits): SMC_CAT_LINE (maks 15),                |
//|   SMC_CAT_POI_ZONE (maks 3), SMC_CAT_STRUCT_LABEL (maks 3).      |
//|   SMC_CAT_OTHER tidak dibatasi (dashboard, shading sesi, zona    |
//|   Premium/Discount yang memang harus selalu tampil).            |
//|                                                                  |
//| ATURAN PENTING:                                                 |
//|   TIDAK ADA logic bisnis SMC di file ini - murni manajemen       |
//|   object generik, supaya bisa dipakai ulang di proyek lain juga.|
//+------------------------------------------------------------------+
#ifndef SMC_OBJECTPOOL_MQH
#define SMC_OBJECTPOOL_MQH

#include "..\Core\SMC_Config.mqh"

//======================================================================
// KATEGORI & BATAS JUMLAH (sesuai spesifikasi "Story Chart")
//======================================================================
#define SMC_CAT_LINE          0
#define SMC_CAT_POI_ZONE      1
#define SMC_CAT_STRUCT_LABEL  2
#define SMC_CAT_OTHER         3

#define SMC_MAX_LINES          15
#define SMC_MAX_POI_ZONES      3
#define SMC_MAX_STRUCT_LABELS  3

//======================================================================
// STATE - registry object dengan info kategori + generasi terakhir disentuh
//======================================================================
struct ManagedObjectInfo
  {
   string name;
   int    category;
   long   generation;
  };

ManagedObjectInfo g_managedInfo[];
long              g_renderGeneration = 0;

//======================================================================
// SIKLUS RENDER - panggil SEKALI di awal tiap siklus render (satu bar baru)
//======================================================================
void SMC_ObjectPool_BeginCycle()
  {
   g_renderGeneration++;
  }

int FindManagedIndex(string name)
  {
   for(int i = 0; i < ArraySize(g_managedInfo); i++)
      if(g_managedInfo[i].name == name)
         return i;
   return -1;
  }

// Dipanggil oleh semua CreateOrUpdate* di bawah - mendaftarkan object BARU,
// atau men-stempel generasi TERKINI pada object yang SUDAH ada (menandakan
// "masih relevan di siklus render ini, jangan dihapus").
void RegisterManagedObject(string name, int category = SMC_CAT_OTHER)
  {
   int idx = FindManagedIndex(name);
   if(idx >= 0)
     {
      g_managedInfo[idx].generation = g_renderGeneration;
      g_managedInfo[idx].category   = category;
      return;
     }
   int n = ArraySize(g_managedInfo);
   ArrayResize(g_managedInfo, n + 1);
   g_managedInfo[n].name       = name;
   g_managedInfo[n].category   = category;
   g_managedInfo[n].generation = g_renderGeneration;
  }

//======================================================================
// RemoveIfStale() - hapus SEMUA object yang TIDAK disentuh di siklus
// render TERKINI. Ini yang membuat "masa hidup" elemen berlaku otomatis:
// begitu render function berhenti memanggil CreateOrUpdate untuk sebuah
// object (karena perannya di cerita sudah selesai), object itu tidak
// ter-stempel generasi baru, dan akan dibersihkan di sini.
//======================================================================
void RemoveIfStale()
  {
   for(int i = ArraySize(g_managedInfo) - 1; i >= 0; i--)
     {
      if(g_managedInfo[i].generation != g_renderGeneration)
        {
         ObjectDelete(0, g_managedInfo[i].name);
         ArrayRemove(g_managedInfo, i, 1);
        }
     }
  }

//======================================================================
// EnforceCategoryLimits() - batas jumlah keras per kategori. Kalau
// sebuah kategori punya object lebih banyak dari batasnya (karena render
// function menggambar lebih dari yang seharusnya), object PALING LAMA
// tidak disentuh (generasi terkecil) dihapus lebih dulu.
//======================================================================
void EnforceCategoryLimit(int category, int maxCount)
  {
   // Kumpulkan (index, generation) untuk kategori ini.
   int  catIdx[];
   long catGen[];
   for(int i = 0; i < ArraySize(g_managedInfo); i++)
      if(g_managedInfo[i].category == category)
        {
         int n = ArraySize(catIdx);
         ArrayResize(catIdx, n + 1);
         ArrayResize(catGen, n + 1);
         catIdx[n] = i;
         catGen[n] = g_managedInfo[i].generation;
        }

   int overCount = ArraySize(catIdx) - maxCount;
   if(overCount <= 0)
      return;

   // Pilih NAMA (bukan index) yang harus dihapus - dengan generasi
   // paling kecil (paling lama tidak disentuh) duluan. Memilih lewat
   // NAMA (bukan index mentah) penting: ArrayRemove() di bawah akan
   // menggeser index g_managedInfo, jadi index awal jadi tidak valid
   // begitu satu elemen dihapus. Nama tidak berubah oleh pergeseran itu.
   string toRemove[];
   for(int r = 0; r < overCount; r++)
     {
      int  oldestPos = -1;
      long oldestGen = LONG_MAX;
      for(int k = 0; k < ArraySize(catGen); k++)
        {
         if(catGen[k] == LONG_MAX)
            continue; // sudah dipilih di iterasi sebelumnya
         if(catGen[k] < oldestGen)
           {
            oldestGen = catGen[k];
            oldestPos = k;
           }
        }
      if(oldestPos < 0)
         break;

      int n = ArraySize(toRemove);
      ArrayResize(toRemove, n + 1);
      toRemove[n] = g_managedInfo[catIdx[oldestPos]].name;
      catGen[oldestPos] = LONG_MAX; // tandai sudah dipilih, jangan dipilih lagi
     }

   // Hapus berdasarkan NAMA - aman dari pergeseran index akibat ArrayRemove.
   for(int t = 0; t < ArraySize(toRemove); t++)
     {
      int idx = FindManagedIndex(toRemove[t]);
      if(idx >= 0)
        {
         ObjectDelete(0, g_managedInfo[idx].name);
         ArrayRemove(g_managedInfo, idx, 1);
        }
     }
  }

void EnforceCategoryLimits()
  {
   EnforceCategoryLimit(SMC_CAT_LINE, SMC_MAX_LINES);
   EnforceCategoryLimit(SMC_CAT_POI_ZONE, SMC_MAX_POI_ZONES);
   EnforceCategoryLimit(SMC_CAT_STRUCT_LABEL, SMC_MAX_STRUCT_LABELS);
  }

//======================================================================
// ADAPTIVE THEME - baca warna background chart, sesuaikan semua warna
// garis/blok/teks supaya tetap kontras dan enak dilihat di tema
// manapun (gelap atau terang), tanpa perlu setting manual dari user.
//======================================================================
color GetChartBackgroundColor()
  {
   return (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
  }

double ColorLuminance(color clr)
  {
   int r = (int)(clr & 0xFF);
   int g = (int)((clr >> 8) & 0xFF);
   int b = (int)((clr >> 16) & 0xFF);
   return (0.299 * r + 0.587 * g + 0.114 * b);
  }

bool IsBackgroundDark()
  {
   return ColorLuminance(GetChartBackgroundColor()) < 128.0;
  }

// Blend dua warna: `weight` = proporsi warna `a` (0.0-1.0), sisanya warna `b`.
color BlendColor(color a, color b, double weight)
  {
   double w = MathMax(0.0, MathMin(1.0, weight));

   int ar = (int)(a & 0xFF),  ag = (int)((a >> 8) & 0xFF),  ab = (int)((a >> 16) & 0xFF);
   int br = (int)(b & 0xFF),  bg = (int)((b >> 8) & 0xFF),  bb = (int)((b >> 16) & 0xFF);

   int nr = (int)(ar * w + br * (1.0 - w));
   int ng = (int)(ag * w + bg * (1.0 - w));
   int nb = (int)(ab * w + bb * (1.0 - w));

   return (color)(nr | (ng << 8) | (nb << 16));
  }

// Warna teks utama (judul, label penting) - selalu kontras penuh terhadap background.
color GetAdaptiveTextColor()
  {
   return IsBackgroundDark() ? clrWhite : clrBlack;
  }

// Warna teks sekunder (header seksi, catatan kecil) - kontras tapi lebih lembut.
color GetAdaptiveMutedTextColor()
  {
   return IsBackgroundDark() ? clrSilver : C'80,80,80';
  }

// Untuk warna AKSEN (BOS/CHoCH, liquidity line, dsb) - pertahankan hue aslinya,
// tapi dorong sedikit ke arah warna kontras supaya tidak "tenggelam" di
// background yang kebetulan mirip huenya (misal hijau di atas background gelap).
color AdaptAccentColor(color accent)
  {
   return BlendColor(accent, GetAdaptiveTextColor(), 0.15);
  }

// Untuk shading zona lebar (Premium/Discount/OTE) - blend LEMBUT ke background
// asli (alpha ~30-35%) supaya terlihat sebagai "tint" halus, konteks yang
// selalu ada di latar tapi tidak mendominasi - sesuai filosofi Story Chart.
color AdaptZoneColor(color accent)
  {
   return BlendColor(accent, GetChartBackgroundColor(), 0.32);
  }

// Untuk pita POI (OB) - masih perlu cukup solid supaya label putih/hitam
// di atasnya kebaca, jadi blend-nya lebih berat ke warna asli dibanding
// zona konteks (Premium/Discount).
color AdaptBandColor(color accent)
  {
   return BlendColor(accent, GetChartBackgroundColor(), 0.55);
  }

// Panel dashboard - background gelap/terang mengikuti tema, bukan hitam pekat tetap.
color AdaptPanelBackground()
  {
   color extreme = IsBackgroundDark() ? clrBlack : clrWhite;
   return BlendColor(extreme, GetChartBackgroundColor(), 0.6);
  }

color AdaptPanelBorder()
  {
   return IsBackgroundDark() ? C'90,90,90' : C'160,160,160';
  }

//======================================================================
// RECTANGLE (dipakai untuk zona POI, Premium/Discount/OTE, killzone shading)
//======================================================================
bool CreateOrUpdateRectangle(string name, datetime t1, double p1, datetime t2, double p2,
                              color clr, bool fill = true, bool back = true, int style = STYLE_SOLID,
                              int category = SMC_CAT_OTHER)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2))
         return false;
     }
   else
     {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
     }
   RegisterManagedObject(name, category);

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, fill);
   ObjectSetInteger(0, name, OBJPROP_BACK, back);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, "\n"); // FIX: cegah tooltip default menampilkan nama objek internal
   return true;
  }

//======================================================================
// GoldPro (10 Okt 2026): posisi ASAL tiap label teks SMC - dipakai GP_LabelFix.mqh untuk menggeser label yang
// menimpa label lain (dihitung ulang dari posisi asal tiap render / zoom, jadi geseran tidak menumpuk).
//======================================================================
string   g_lblName[];
datetime g_lblT[];
double   g_lblP[];
void SMC_LabelHome(string name, datetime t, double p)
  {
   int n = ArraySize(g_lblName);
   for(int i = 0; i < n; i++)
      if(g_lblName[i] == name) { g_lblT[i] = t; g_lblP[i] = p; return; }
   ArrayResize(g_lblName, n + 1); ArrayResize(g_lblT, n + 1); ArrayResize(g_lblP, n + 1);
   g_lblName[n] = name; g_lblT[n] = t; g_lblP[n] = p;
  }

//======================================================================
// TEXT (dipakai untuk label BOS/CHoCH, label pijakan/tujuan, dsb)
//======================================================================
bool CreateOrUpdateText(string name, datetime t, double p, string text, color clr,
                         int fontSize = 8, ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_LOWER,
                         int category = SMC_CAT_OTHER)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, p))
         return false;
     }
   else
     {
      ObjectMove(0, name, 0, t, p);
     }
   SMC_LabelHome(name, t, p);
   RegisterManagedObject(name, category);

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, "\n"); // FIX: cegah tooltip - ini akar bug "SMC_ZONE_PREMIUM" muncul saat hover
   return true;
  }

//======================================================================
// ARROWED LINE (BARU - garis panah diagonal dari harga sekarang menuju
// target, penanda arah visual yang belum pernah dipakai indikator SMC
// lain yang kita bandingkan. OBJ_ARROWED_LINE = tipe bawaan MT5, kepala
// panah otomatis di ujung ke-2.)
//======================================================================
bool CreateOrUpdateArrowedLine(string name, datetime t1, double p1, datetime t2, double p2,
                                 color clr, int width = 2, int category = SMC_CAT_OTHER)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_ARROWED_LINE, 0, t1, p1, t2, p2))
         return false;
     }
   else
     {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
     }
   RegisterManagedObject(name, category);

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, "\n");
   return true;
  }

//======================================================================
// TREND LINE (dipakai untuk garis pijakan, garis tujuan, equilibrium)
//======================================================================
bool CreateOrUpdateTrendLine(string name, datetime t1, double p1, datetime t2, double p2,
                              color clr, int style = STYLE_SOLID, int width = 1, bool rayRight = false,
                              int category = SMC_CAT_OTHER)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2))
         return false;
     }
   else
     {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
     }
   RegisterManagedObject(name, category);

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, rayRight);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, "\n"); // FIX: cegah tooltip default
   return true;
  }

//======================================================================
// RECTANGLE BERBASIS LAYAR (panel dashboard)
//======================================================================
bool CreateOrUpdateScreenRectangle(string name, int x, int y, int width, int height,
                                    color bgColor, int corner = 1, color borderColor = clrNONE)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
         return false;
     }
   RegisterManagedObject(name, SMC_CAT_OTHER);

   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, borderColor);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1000);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, "\n"); // FIX: cegah tooltip default
   return true;
  }

//======================================================================
// LABEL berbasis koordinat layar X/Y (dashboard)
//======================================================================
bool CreateOrUpdateScreenLabel(string name, int x, int y, string text, color clr,
                                int fontSize = 9, int corner = 1, string font = "Consolas")
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
         return false;
     }
   RegisterManagedObject(name, SMC_CAT_OTHER);

   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1001);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, "\n"); // FIX: cegah tooltip default
   return true;
  }

//======================================================================
// VERTICAL LINE (batas sesi killzone)
//======================================================================
bool CreateOrUpdateVLine(string name, datetime t, color clr, int style = STYLE_DOT, int width = 1)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_VLINE, 0, t, 0))
         return false;
     }
   else
     {
      ObjectMove(0, name, 0, t, 0);
     }
   RegisterManagedObject(name, SMC_CAT_OTHER);

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, "\n"); // FIX: cegah tooltip default
   return true;
  }

//======================================================================
// FADE: opacity blend ke WARNA BACKGROUND ASLI chart.
//======================================================================
color FadeColor(color clr, double opacityPercent)
  {
   double w = MathMax(0.0, MathMin(1.0, opacityPercent / 100.0));
   return BlendColor(clr, GetChartBackgroundColor(), w);
  }

//======================================================================
// ClearAll() - hapus SEMUA object yang dikelola pool ini. Dipanggil dari
// SMC_Main.mq5 -> OnDeinit().
//
// CATATAN (temuan dari testing): registry (g_managedInfo) cuma tahu
// object yang didaftarkan di SESI YANG SEDANG BERJALAN. Kalau versi
// kode sebelumnya sempat berganti tanpa lepas-pasang bersih (atau
// sempat reload paksa), object dari sesi LAMA bisa jadi "yatim" -
// tidak pernah masuk registry baru, jadi tidak pernah ikut dihapus
// lewat cara normal. Sapuan berbasis PREFIX di bawah ini jaring
// pengaman kedua: hapus APAPUN yang diawali SMC_OBJ_PREFIX, terlepas
// apakah tercatat di registry atau tidak.
//======================================================================
void ClearAll()
  {
   for(int i = ArraySize(g_managedInfo) - 1; i >= 0; i--)
      ObjectDelete(0, g_managedInfo[i].name);
   ArrayFree(g_managedInfo);

   ObjectsDeleteAll(0, SMC_OBJ_PREFIX); // jaring pengaman - tangkap object yatim dari sesi lama

   ChartRedraw(0);
  }

void DeleteAllManagedObjects()
  {
   ClearAll();
  }

//======================================================================
// GoldPro: PEMERIKSA KESEHATAN objek SMC (dipanggil timer tiap 2 dtk).
// true bila ada objek terdaftar yang HILANG dari chart (dihapus instance lama saat ganti TF, program
// lain, atau pengguna) -> pemanggil menggambar ulang. Objek "GP_" yatim yang tidak dikenal registry
// (sisa instance TF sebelumnya) langsung dihapus.
//======================================================================
bool SMC_PoolNeedsRepair()
  {
   bool bad = false;
   for(int i = 0; i < ArraySize(g_managedInfo) && !bad; i++)
      if(ObjectFind(0, g_managedInfo[i].name) < 0)
         bad = true;
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
     {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, SMC_OBJ_PREFIX) == 0 && FindManagedIndex(nm) < 0)
        {
         ObjectDelete(0, nm);
         bad = true;
        }
     }
   return bad;
  }

// ClampRenderStartTime() - DIPINDAH dari SMC_RenderPOI.mqh ke sini
// (screenshot review: label EQH/EQL di SMC_RenderLiquidity.mqh perlu
// fungsi yang sama, dan render file sebaiknya tidak saling include -
// SMC_ObjectPool.mqh sudah jadi infrastruktur render bersama yang
// di-include KEDUA file). Membatasi titik mula render supaya tidak
// terlalu jauh ke belakang - mengurangi kemungkinan elemen jatuh di
// area yang tertutup panel dashboard (yang menempati bagian kiri layar).
datetime ClampRenderStartTime(datetime originalStart)
  {
   datetime minAllowed = iTime(_Symbol, PERIOD_CURRENT, InpVisualMaxLookbackBars);
   if(minAllowed == 0)
      return originalStart;
   return (datetime)MathMax((long)originalStart, (long)minAllowed);
  }

// GetDefaultRenderEndTime() - utilitas render bersama BARU (modul
// "Paus"). Nama SENGAJA beda dari GetRenderEndTime()/GetLiqRenderEndTime()
// yang sudah ada LOKAL di SMC_RenderPOI.mqh/SMC_RenderLiquidity.mqh -
// keduanya logic-nya identik tapi didefinisikan lokal di file
// masing-masing (duplikasi lama, bukan yang saya buat sekarang, tidak
// disentuh supaya tidak memperluas scope perubahan). Fungsi ini untuk
// file BARU yang tidak mau include render file lain.
datetime GetDefaultRenderEndTime()
  {
   return TimeCurrent() + PeriodSeconds(PERIOD_CURRENT) * 20;
  }

#endif // SMC_OBJECTPOOL_MQH