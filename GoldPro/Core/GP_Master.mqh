//+------------------------------------------------------------------+
//|                                                    GP_Master.mqh |
//| GoldPro - SATU CHART UTAMA per simbol (10 Okt 2026, rencana       |
//| pengerasan no. 1, pengguna: "kita tambahkan aja dulu ... 1 dan 2").|
//| Masalah: GoldPro jalan di beberapa chart sekaligus -> MT5 berat,   |
//| alert dobel, sempat macet 09:37-09:54 (pesan "30 mnt di luar"      |
//| hilang). Sekarang hanya CHART UTAMA yang menulis Telegram, CSV uji |
//| maju, rapor & alert popup; chart lain hanya menampilkan (mesin     |
//| kotak di chart lain jalan hanya bila dashboard Kotak dibuka).      |
//| Klaim atomik (token) + detak tiap timer 2 dtk; detak > 20 dtk =    |
//| chart utama dianggap mati -> chart lain mengambil alih. Ganti TF   |
//| di chart utama: instance lama melepas saat ditutup, instance baru  |
//| mengambil alih <= 2 dtk.                                           |
//| Detak GP_HB (jam PC) juga dibaca EA GoldPro_Telegram: GoldPro      |
//| berhenti > 15 mnt saat pasar buka -> pesan peringatan (no. 6).     |
//+------------------------------------------------------------------+
#ifndef GP_MASTER_MQH
#define GP_MASTER_MQH

bool   g_gpMaster = false;
double g_gpMTok   = 0;

string GPM_Key() { return "GP_MST_" + _Symbol; }
string GPM_HB()  { return "GP_MSTT_" + _Symbol; }

//--- dipanggil tiap timer (2 dtk) & sekali di OnInit
void GP_MasterTick()
  {
   if(MQLInfoInteger(MQL_TESTER)) { g_gpMaster = true; return; }
   if(g_gpMTok == 0) g_gpMTok = 1 + MathRand() + (double)(GetTickCount() % 100000) * 32768.0;
   string k = GPM_Key(), hb = GPM_HB();
   if(!GlobalVariableCheck(k)) GlobalVariableTemp(k);                    // dibuat dengan nilai 0 = belum ada chart utama
   double cur = GlobalVariableGet(k);
   bool was = g_gpMaster;
   if(cur == g_gpMTok) g_gpMaster = true;
   else
     {
      g_gpMaster = false;
      bool stale = !GlobalVariableCheck(hb) || (double)TimeLocal() - GlobalVariableGet(hb) > 20;
      if((cur == 0 || stale) && GlobalVariableSetOnCondition(k, g_gpMTok, cur)) g_gpMaster = true;
     }
   if(g_gpMaster)
     {
      GlobalVariableSet(hb, (double)TimeLocal());
      GlobalVariableSet("GP_HB", (double)TimeLocal());                   // detak hidup untuk EA GoldPro_Telegram
     }
   if(g_gpMaster != was)
      PrintFormat("[GoldPro] %s %s: %s", _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period),
                  g_gpMaster ? "CHART UTAMA (Telegram, catatan uji maju, rapor & alert dari chart ini)"
                             : "chart tampilan (chart utama ada di chart lain)");
  }

void GP_MasterRelease()
  {
   if(g_gpMaster && GlobalVariableCheck(GPM_Key()) && GlobalVariableGet(GPM_Key()) == g_gpMTok)
      GlobalVariableSet(GPM_Key(), 0);                                    // chart lain / instance TF baru boleh mengambil alih
   g_gpMaster = false;
  }

#endif // GP_MASTER_MQH
