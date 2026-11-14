//+------------------------------------------------------------------+
//|                                                      GP_Time.mqh |
//| GoldPro - konversi waktu yang sadar DST.                          |
//|                                                                  |
//| PERBAIKAN dari SMC_Pro_System: SMC membaca jam sesi langsung dari |
//| jam server (input GMT offset tidak pernah dipakai, DST diabaikan),|
//| sehingga sesi London/NY meleset ~4 jam. Di sini semua sesi        |
//| didefinisikan dalam jam LOKAL bursa (New York / London) lalu      |
//| dikonversi otomatis:                                              |
//|   server -> UTC  : server = UTC+InpServerUTCWinter (+1 saat DST AS)|
//|   UTC -> NY (ET) : UTC-5, UTC-4 saat DST AS                        |
//|   UTC -> London  : UTC+0, UTC+1 saat DST Inggris                  |
//| Diverifikasi di broker FinexBisnisSolusi: server 10:41 saat       |
//| UTC 07:38 (25 Sep 2026, DST AS) -> UTC+3.                          |
//+------------------------------------------------------------------+
#ifndef GP_TIME_MQH
#define GP_TIME_MQH

#include "SMC_Config.mqh"

//--- hari ke-n (1..5) atau terakhir (n = -1) dari hari Minggu di bulan tertentu
int GP_SundayOfMonth(int year, int month, int n)
  {
   MqlDateTime dt;
   ZeroMemory(dt);
   dt.year = year; dt.mon = month; dt.day = 1;
   datetime first = StructToTime(dt);
   TimeToStruct(first, dt);
   int firstSunday = 1 + (7 - dt.day_of_week) % 7;
   if(n > 0)
      return firstSunday + 7 * (n - 1);
   int dim = 31;
   if(month == 4 || month == 6 || month == 9 || month == 11) dim = 30;
   if(month == 2) dim = ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) ? 29 : 28;
   int d = firstSunday;
   while(d + 7 <= dim) d += 7;
   return d;
  }

datetime GP_MakeTime(int year, int month, int day, int hour)
  {
   MqlDateTime dt;
   ZeroMemory(dt);
   dt.year = year; dt.mon = month; dt.day = day; dt.hour = hour;
   return StructToTime(dt);
  }

//--- DST Amerika: Minggu ke-2 Maret 02:00 lokal (07:00 UTC) s/d Minggu ke-1 Nov 02:00 lokal (06:00 UTC)
bool GP_IsUSDST(datetime utc)
  {
   MqlDateTime dt;
   TimeToStruct(utc, dt);
   datetime st = GP_MakeTime(dt.year, 3, GP_SundayOfMonth(dt.year, 3, 2), 7);
   datetime en = GP_MakeTime(dt.year, 11, GP_SundayOfMonth(dt.year, 11, 1), 6);
   return utc >= st && utc < en;
  }

//--- DST Inggris: Minggu terakhir Maret 01:00 UTC s/d Minggu terakhir Oktober 01:00 UTC
bool GP_IsUKDST(datetime utc)
  {
   MqlDateTime dt;
   TimeToStruct(utc, dt);
   datetime st = GP_MakeTime(dt.year, 3, GP_SundayOfMonth(dt.year, 3, -1), 1);
   datetime en = GP_MakeTime(dt.year, 10, GP_SundayOfMonth(dt.year, 10, -1), 1);
   return utc >= st && utc < en;
  }

int GP_ServerOffsetHours(datetime utcApprox)
  {
   return InpServerUTCWinter + ((InpServerFollowsUSDST && GP_IsUSDST(utcApprox)) ? 1 : 0);
  }

datetime GP_ServerToUTC(datetime server)
  {
   return server - GP_ServerOffsetHours(server - InpServerUTCWinter * 3600) * 3600;
  }

datetime GP_UTCToServer(datetime utc)
  {
   return utc + GP_ServerOffsetHours(utc) * 3600;
  }

datetime GP_UTCToET(datetime utc)     { return utc - (GP_IsUSDST(utc) ? 4 : 5) * 3600; }
datetime GP_UTCToLondon(datetime utc) { return utc + (GP_IsUKDST(utc) ? 1 : 0) * 3600; }
datetime GP_UTCToWIB(datetime utc)    { return utc + 7 * 3600; }
datetime GP_UTCToLocal(datetime utc)  { return utc + InpLocalUTCOffset * 3600; }   // jam pengguna (default WITA)
string   GP_LocalTime(datetime server){ return TimeToString(GP_UTCToLocal(GP_ServerToUTC(server)), TIME_MINUTES); }

datetime GP_ETToUTC(datetime et)
  {
   datetime u = et + 4 * 3600;
   if(!GP_IsUSDST(u)) u = et + 5 * 3600;
   return u;
  }

datetime GP_LondonToUTC(datetime ldn)
  {
   datetime u = ldn - 3600;
   if(!GP_IsUKDST(u)) u = ldn;
   return u;
  }

//--- jam lokal (0-23) di New York / London untuk waktu server
int GP_HourET(datetime server)
  {
   MqlDateTime dt;
   TimeToStruct(GP_UTCToET(GP_ServerToUTC(server)), dt);
   return dt.hour;
  }

int GP_HourLondon(datetime server)
  {
   MqlDateTime dt;
   TimeToStruct(GP_UTCToLondon(GP_ServerToUTC(server)), dt);
   return dt.hour;
  }

//--- waktu server untuk jam lokal `hour` pada TANGGAL LOKAL yang sama dengan `server`
datetime GP_ServerAtLocalHour(datetime server, int hour, bool london)
  {
   datetime u = GP_ServerToUTC(server);
   datetime loc = london ? GP_UTCToLondon(u) : GP_UTCToET(u);
   MqlDateTime dt;
   TimeToStruct(loc, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime locStart = StructToTime(dt) + hour * 3600;
   datetime u2 = london ? GP_LondonToUTC(locStart) : GP_ETToUTC(locStart);
   return GP_UTCToServer(u2);
  }

//--- jendela AM Fix SELL: 10:20-10:29 jam London (lelang LBMA 10:30). Riset M1 1 tahun:
//    SELL buka 10:20, tutup 10:29 -> menang ~72% (latih/validasi/uji 71/69/81%).
datetime GP_AMFixStart(datetime server)
  {
   // pakai TENGAH HARI server sebagai acuan tanggal: jam 00:00-02:00 server, tanggal London masih
   // hari sebelumnya (London = server - 2 jam) -> dulu panel menulis "selesai" di awal hari.
   datetime noon = server - (server % 86400) + 12 * 3600;
   return GP_ServerAtLocalHour(noon, 10, true) + 20 * 60;
  }

//--- jendela RAWAN SWEEP: 08:00-11:30 jam New York (rilis data AS 08:30, bursa saham 09:30, data 10:00).
//    Uji M1 2017-2026: sweep (tembus high/low 60 mnt lalu balik >= 0.1 ADR dalam 10 mnt) 3-4x lebih sering
//    dari rata-rata; 6 slot 30-menit teratas semuanya di jendela ini; pola per tahun korelasi 0.91-0.99.
//--- Kalender MT5 (CalendarValueHistory) memberi jam SEMUA tanggal dengan offset server SAAT INI -
//    terbukti di ekspor: Jobless Claims Des-Feb (08:30 NY) tercatat 09:30 NY karena diekspor saat UTC+3.
//    Koreksi ke offset server yang berlaku PADA TANGGAL rilis itu (penting sekitar pergantian DST).
datetime GP_CalTime(datetime tApi)
  {
   int cur = GP_ServerOffsetHours(GP_ServerToUTC(TimeTradeServer()));
   return GP_UTCToServer(tApi - cur * 3600);
  }

datetime GP_SweepStart(datetime server) { return GP_ServerAtLocalHour(server, 8, false); }
datetime GP_SweepEnd(datetime server)   { return GP_SweepStart(server) + 210 * 60; }

#endif // GP_TIME_MQH
