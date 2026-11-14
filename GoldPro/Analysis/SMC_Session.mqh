//+------------------------------------------------------------------+
//|                                                  SMC_Session.mqh |
//|                                                                  |
//| GoldPro (diadopsi dari SMC Pro System, Fase 3 - File 9/24)        |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Klasifikasi sesi trading & killzone - MURNI berbasis waktu.   |
//|                                                                  |
//| PERBAIKAN GoldPro: sesi didefinisikan dalam jam LOKAL bursa       |
//| (Asia & New York = jam New York, London = jam London) dan         |
//| dikonversi dari jam server lewat GP_Time.mqh (ikut DST AS &       |
//| Inggris). Versi SMC lama memakai jam server mentah, sehingga      |
//| "London" dan "NY" meleset ~4 jam dan tidak ikut DST.              |
//|                                                                  |
//| ATURAN: file ini TIDAK tahu apa-apa soal liquidity/sweep/Judas.  |
//+------------------------------------------------------------------+
#ifndef SMC_SESSION_MQH
#define SMC_SESSION_MQH

#include "..\Core\SMC_Types.mqh"
#include "..\Core\SMC_Config.mqh"
#include "..\Core\SMC_Utils.mqh"
#include "..\Core\GP_Time.mqh"

bool GP_InHourWindow(int hour, int startH, int endH)
  {
   if(startH <= endH)
      return hour >= startH && hour < endH;
   return hour >= startH || hour < endH;   // melewati tengah malam
  }

//======================================================================
// KLASIFIKASI SESI SAAT INI
//======================================================================
ENUM_SESSION GetCurrentSession()
  {
   datetime now = TimeCurrent();
   int hET = GP_HourET(now), hLDN = GP_HourLondon(now);

   if(GP_InHourWindow(hET, InpAsiaStartET, InpAsiaEndET))   // End 24 = sampai tengah malam
      return SESSION_ASIA;
   if(GP_InHourWindow(hLDN, InpLondonStartLDN, InpLondonEndLDN))
      return SESSION_LONDON;
   if(GP_InHourWindow(hET, InpNewYorkStartET, InpNewYorkEndET))
      return SESSION_NEWYORK;

   return SESSION_OFF;
  }

// Killzone = London & New York (fase manipulasi/distribusi utama).
bool IsKillzoneActive()
  {
   ENUM_SESSION s = GetCurrentSession();
   return (s == SESSION_LONDON || s == SESSION_NEWYORK);
  }

//======================================================================
// WAKTU MULAI SESI HARI INI (dalam jam SERVER) - dipakai SMC_AMD.mqh
// dan garis killzone di dashboard. "Hari ini" = tanggal lokal bursa.
//======================================================================
datetime GetSessionStartTimeToday(ENUM_SESSION session)
  {
   datetime now = TimeCurrent();
   switch(session)
     {
      case SESSION_ASIA:    return GP_ServerAtLocalHour(now, InpAsiaStartET, false);
      case SESSION_LONDON:  return GP_ServerAtLocalHour(now, InpLondonStartLDN, true);
      case SESSION_NEWYORK: return GP_ServerAtLocalHour(now, InpNewYorkStartET, false);
      default:              return 0;
     }
  }

// True kalau waktu sekarang berada dalam N menit pertama sejak sesi dimulai.
bool IsWithinSessionOpeningWindow(ENUM_SESSION session, int windowMinutes)
  {
   datetime start = GetSessionStartTimeToday(session);
   if(start == 0)
      return false;

   long elapsedMin = (TimeCurrent() - start) / 60;
   return (elapsedMin >= 0 && elapsedMin <= windowMinutes);
  }

//======================================================================
// COUNTDOWN KE KILLZONE BERIKUTNYA (untuk dashboard)
//======================================================================
string GetNextKillzoneCountdown(ENUM_SESSION &outNextSession)
  {
   datetime now = TimeCurrent();
   datetime londonStart = GetSessionStartTimeToday(SESSION_LONDON);
   datetime nyStart     = GetSessionStartTimeToday(SESSION_NEWYORK);

   // Kalau sudah lewat, hitung ulang untuk tanggal lokal berikutnya
   if(londonStart <= now) londonStart = GP_ServerAtLocalHour(now + 86400, InpLondonStartLDN, true);
   if(nyStart <= now)     nyStart     = GP_ServerAtLocalHour(now + 86400, InpNewYorkStartET, false);

   datetime nextTime;
   if(londonStart < nyStart) { nextTime = londonStart; outNextSession = SESSION_LONDON; }
   else                      { nextTime = nyStart;     outNextSession = SESSION_NEWYORK; }

   long diffSec = nextTime - now;
   int  h = (int)(diffSec / 3600);
   int  m = (int)((diffSec % 3600) / 60);
   int  s = (int)(diffSec % 60);

   return StringFormat("%02d:%02d:%02d", h, m, s);
  }

#endif // SMC_SESSION_MQH
