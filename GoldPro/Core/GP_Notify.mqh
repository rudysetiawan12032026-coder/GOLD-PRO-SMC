//+------------------------------------------------------------------+
//|                                                    GP_Notify.mqh |
//| GoldPro - alert popup / suara / push ke HP (MetaQuotes ID).      |
//| Setiap alert punya kunci unik -> tidak pernah terkirim dua kali. |
//+------------------------------------------------------------------+
#ifndef GP_NOTIFY_MQH
#define GP_NOTIFY_MQH
#include "GP_Master.mqh"                // 10 Okt 2026: alert hanya dari CHART UTAMA (kecuali PIN = garis milik chart itu)

input group "=== GoldPro: Alert ==="
input bool InpGPAlertPopup = true;    // Popup alert di MT5
input bool InpGPAlertSound = true;    // Bunyi
input bool InpGPAlertPush  = false;   // Push ke HP (isi MetaQuotes ID di Tools > Options > Notifications)
// Straddle, breaker & AM Fix gagal di uji 2017-2025 -> alert default MATI (bisa dinyalakan utk forward test)
input bool InpGPAlertStraddle = false;// Straddle: siap pasang, terisi, hasil (1 th saja)
input bool InpGPAlertBreaker  = false;// Setup breaker baru (1 th saja)
input bool InpGPAlertAMFix    = false;// AM Fix SELL 5 menit sebelum jendela (1 th saja)
input bool InpGPAlertAsia     = false;// Breakout Asia terpicu, hanya saat rezim vol tinggi (hipotesis)
input bool InpGPAlertSweep    = true; // 10 menit sebelum jendela RAWAN SWEEP 08:00-11:30 New York (terbukti kokoh)
input bool InpGPAlertEntryOK  = false;// ENTRY OK kandidat (belum terbukti -> default mati)
input bool InpGPAlertNews     = true; // Blackout berita dimulai
input bool InpGPAlertPin      = true; // Harga menyentuh PIN (garis yang Anda pasang sendiri)

string g_gpSent[];

bool GP_AlreadySent(string key)
  {
   for(int i = ArraySize(g_gpSent) - 1; i >= 0; i--)
      if(g_gpSent[i] == key) return true;
   int n = ArraySize(g_gpSent);
   if(n > 500) { ArrayRemove(g_gpSent, 0, 250); n = ArraySize(g_gpSent); }
   ArrayResize(g_gpSent, n + 1);
   g_gpSent[n] = key;
   return false;
  }

//--- kirim sekali per `key`, hanya untuk kejadian yang masih segar (<= 15 menit),
//    supaya memasang ulang indikator di tengah hari tidak memicu alert lama.
void GP_Notify(string key, string msg, datetime eventTime)
  {
   if(MQLInfoInteger(MQL_TESTER)) return;
   if(TimeCurrent() - eventTime > 15 * 60) { GP_AlreadySent(key); return; }
   if(!g_gpMaster && StringFind(key, "pin") != 0) { GP_AlreadySent(key); return; }   // chart tampilan: tidak dobel
   if(GP_AlreadySent(key)) return;
   string m = "GoldPro " + _Symbol + ": " + msg;
   if(InpGPAlertPopup) Alert(m);
   else Print(m);
   if(InpGPAlertSound && !InpGPAlertPopup) PlaySound("alert.wav");
   if(InpGPAlertPush && TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED))
      SendNotification(StringSubstr(m, 0, 255));
  }

#endif // GP_NOTIFY_MQH
