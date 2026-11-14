//+------------------------------------------------------------------+
//|                                                    GP_Health.mqh |
//| GoldPro - CEK VERSI & KESEHATAN (10 Okt 2026, rencana pengerasan  |
//| no. 3 + baris ringkas alarm no. 4).                               |
//| Masalah: EA / indikator versi lama tetap jalan tanpa ketahuan      |
//| (10 Okt pagi: dashboard Saldo tidak muncul karena EA dimuat 09:24, |
//| sebelum compile 09:44). Sekarang tiap program menulis versinya ke  |
//| Global Variable; indikator menampilkan baris merah kecil di kiri   |
//| bawah chart bila ada yang tertinggal:                              |
//|   - indikator chart ini lebih lama dari instance GoldPro lain      |
//|     (compile baru dimuat chart lain) -> ganti TF sekali            |
//|   - EA GoldPro_Panel di chart ini versi lama -> pasang ulang       |
//|   - (chart utama) EA GoldPro_Telegram versi lama / berhenti        |
//|   - (chart utama) ALARM kalibrasi angka (mode presisi aktif)       |
//| Tidak ada baris bila semua beres (chart tetap bersih).            |
//+------------------------------------------------------------------+
#ifndef GP_HEALTH_MQH
#define GP_HEALTH_MQH

#define GP_VER_IND    2026101601     // versi indikator ini (YYYYMMDDnn) - dinaikkan bersama EA bila perilaku berubah
                                     // 2026101601 (16 Okt): notif sentuh zona M1 & M5 = pola 3 candle (sentuh + 2 candle) + peluang
                                     // 2026101507 (15 Okt malam): koreksi M1 -1.5 target Gelombang "sekarang" hanya 15 mnt sesudah BOS
                                     // 2026101506 (15 Okt malam): peluang dari harga sekarang (Premium / Discount / Equilibrium dulu =
                                     //   hitungan jarak, gel_arah.py) di kartu "i" Gelombang & pesan Telegram sentuh zona
                                     // 2026101505 (15 Okt sore): pesan Telegram rapi - Kotak "menyentuh atap / lantai" + candle tutup,
                                     //   Gelombang zona PREMIUM / EQUILIBRIUM / DISCOUNT (GZP / GZE / GZD) pindah zona, 1 pesan saat tutup
                                     // 2026101504 (15 Okt): minta EA Telegram 2026101503 (pesan ditolak tidak lagi menyumbat antrean)
                                     // 2026101503 (15 Okt): notif sentuh garis -> garis M1, hanya BOLAK-BALIK ATAS / BAWAH (~6 / hari)
                                     // 2026101502 (15 Okt): notif Telegram sentuh garis Gelombang M15 (GTS / GTC / GTK / GTT / GTB / GTH)
                                     // 2026101501 (15 Okt): status "TIDAK BERSIH" Gelombang tidak lagi label terpisah (menimpa 2.0A)
                                     // 2026101408 (14 Okt): Gelombang = BOS internal TERBARU (bersih / tidak), target "dilewati",
                                     //   pita Equilibrium Gelombang garis tepi
                                     // 2026101407 (14 Okt): angka khusus M1 (kartu SMC & Gelombang), Mode Teruji sembunyikan OB /
                                     //   BOS / CHoCH, label Gelombang maks 1 langkah geser
                                     // 2026101406 (14 Okt): satu range (SMC lama sembunyi saat Gelombang), OTE / EQ garis tepi,
                                     //   label SWEPT disembunyikan, Gelombang lama + status + label dalam chart + uji maju CSV,
                                     //   tombol ke-15 "Mode Teruji"
                                     // 2026101405 (14 Okt): kartu SMC INFO cek candle berjalan (SUDAH tembus / balik)
                                     // 2026101404 (14 Okt): tombol selalu di depan garis chart, jarak aman label SMC
                                     // 2026101401 (14 Okt): kotak "i" INFO di samping tiap tombol (tombol utama = gambar)
                                     // 2026101402 (14 Okt): label SMC tidak menimpa tombol / kotak "i" / panel (GP_LabelFix)
                                     // 2026101403 (14 Okt): tombol ke-14 "Gelombang" (Map\GP_Wave)
                                     // 2026101101 (11 Okt): tombol Tembus Balik + pesan Telegram TBK / TBKOK / TBKNO / TBKTO
                                     // 2026101102 (11 Okt malam): strip TB tidak tertutup dashboard, status MARKET TUTUP
                                     // 2026101201 (12 Okt): JAM BAGUS Tembus Balik + pesan TBGJAM / TBG / TBGOK / TBGNO / TBGTO
#define GP_NEED_PANEL 2026101002     // versi minimal EA GoldPro_Panel yang cocok (Panel tidak berubah 11-12 Okt)
#define GP_NEED_TG    2026101504     // versi minimal EA GoldPro_Telegram yang cocok (format rapi, tag TGM / GZP / GZE / GZD)
#define GPV_PFX       "GPV_I"        // baris peringatan indikator (EA Panel memakai "GPV_E")

string GPH_Cid() { return IntegerToString(ChartID()); }

void GP_HealthInit()
  {
   if(MQLInfoInteger(MQL_TESTER)) return;
   GlobalVariableSet("GP_VERI_" + GPH_Cid(), GP_VER_IND);
   if(!GlobalVariableCheck("GP_VER_IND_MAX") || GlobalVariableGet("GP_VER_IND_MAX") < GP_VER_IND)
      GlobalVariableSet("GP_VER_IND_MAX", GP_VER_IND);
  }

string g_gphW[], g_gphT[];
color  g_gphC[];
void GPH_Add(string s, color c, string tip)
  {
   int n = ArraySize(g_gphW);
   ArrayResize(g_gphW, n + 1); ArrayResize(g_gphC, n + 1); ArrayResize(g_gphT, n + 1);
   g_gphW[n] = StringSubstr(s, 0, 62); g_gphC[n] = c; g_gphT[n] = tip;
  }

//--- tiap timer (2 dtk)
void GP_HealthTick()
  {
   if(MQLInfoInteger(MQL_TESTER)) return;
   string cid = GPH_Cid();
   GlobalVariableSet("GP_VERI_" + cid, GP_VER_IND);
   ArrayResize(g_gphW, 0); ArrayResize(g_gphC, 0); ArrayResize(g_gphT, 0);
   double now = (double)TimeLocal();
   if(GlobalVariableCheck("GP_VER_IND_MAX") && GlobalVariableGet("GP_VER_IND_MAX") > GP_VER_IND)
      GPH_Add("GoldPro chart ini VERSI LAMA: ganti TF sekali (M1>M5>M1)", clrTomato,
              StringFormat("Chart lain sudah memuat GoldPro versi %.0f, chart ini masih %d.\nCompile baru hanya dimuat saat TF diganti / "
                           "indikator dipasang ulang.", GlobalVariableGet("GP_VER_IND_MAX"), GP_VER_IND));
   if(GlobalVariableCheck("GP_VERPT_" + cid) && now - GlobalVariableGet("GP_VERPT_" + cid) < 15 &&
      (!GlobalVariableCheck("GP_VERP_" + cid) || GlobalVariableGet("GP_VERP_" + cid) < GP_NEED_PANEL))
      GPH_Add("EA GoldPro_Panel VERSI LAMA: lepas & pasang ulang EA", clrTomato,
              "EA di chart ini dimuat sebelum compile terbaru -> fitur baru belum aktif. Lepas EA lalu pasang lagi\n"
              "(Navigator > Expert Advisors > GoldPro > GoldPro_Panel).");
   if(g_gpMaster)
     {
      if(GlobalVariableCheck("GP_VERTT"))
        {
         double tt = GlobalVariableGet("GP_VERTT");
         if(now - tt < 60 && GlobalVariableCheck("GP_VERT") && GlobalVariableGet("GP_VERT") < GP_NEED_TG)
            GPH_Add("EA GoldPro_Telegram VERSI LAMA: pasang ulang EA", clrTomato,
                    "EA Telegram dimuat sebelum compile terbaru (penjaga hidup & ikon baru belum aktif). Lepas & pasang lagi.");
         else if(now - tt > 300 && InpKBTelegram)
            GPH_Add("EA Telegram berhenti sejak " + TimeToString((datetime)tt, TIME_MINUTES) + " - pesan tertahan", clrOrange,
                    "EA GoldPro_Telegram tidak memberi tanda hidup > 5 mnt (dilepas? chart ditutup? AutoTrading mati?).\n"
                    "Kejadian tetap ditulis ke kotak_telegram.txt dan TIDAK dikirim ulang saat EA dipasang lagi.");
        }
      string al = KB_AlSummary();
      if(al != "")
         GPH_Add("ALARM angka 7 hari: " + al, clrOrange,
                 "Angka ini meleset dari kenyataan uji maju 7 hari terakhir melebihi kebetulan -> di dashboard Kotak diganti\n"
                 "[DICEK] (mode presisi). Tampil lagi otomatis bila kembali wajar. Rincian: dashboard Kotak & rapor harian.");
     }
   //--- gambar: kiri bawah, di kanan kolom tombol (tidak menimpa panel di kiri atas)
   int x = GDM::BtnColR() + 8, n = ArraySize(g_gphW);
   for(int i = 0; i < n; i++)
     {
      string nm = GPV_PFX + IntegerToString(i);
      if(ObjectFind(0, nm) < 0)
        {
         ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_LOWER);
         ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, nm, OBJPROP_ZORDER, 30);
         ObjectSetString(0, nm, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 9);
        }
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 8 + (n - 1 - i) * 17);
      ObjectSetString(0, nm, OBJPROP_TEXT, g_gphW[i]);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, g_gphC[i]);
      ObjectSetString(0, nm, OBJPROP_TOOLTIP, g_gphT[i]);
     }
   for(int i = n; ObjectFind(0, GPV_PFX + IntegerToString(i)) >= 0; i++)
      ObjectDelete(0, GPV_PFX + IntegerToString(i));
  }

void GP_HealthDeinit(bool isFinal)
  {
   if(!isFinal) return;
   ObjectsDeleteAll(0, GPV_PFX);
   GlobalVariableDel("GP_VERI_" + GPH_Cid());
  }

#endif // GP_HEALTH_MQH
