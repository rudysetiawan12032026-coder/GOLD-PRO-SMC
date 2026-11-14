//+------------------------------------------------------------------+
//|                                                SMC_NewsFilter.mqh |
//|                                                                  |
//| Fase 3 - File 11/24 : SMC Pro System                             |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Mendeteksi kedekatan waktu dengan rilis berita ekonomi         |
//|   berdampak tinggi, sebagai gate tambahan di scoring - supaya    |
//|   sistem "terintegrasi dengan pasar global", sesuai permintaan.  |
//|                                                                  |
//| CATATAN TEKNIS PENTING:                                         |
//|   Memakai Economic Calendar API NATIVE MQL5 (CalendarValueHistory|
//|   / CalendarEventById) - BUKAN WebRequest(), jadi TIDAK kena     |
//|   masalah err=4014 yang pernah dialami di SMC Master Pro.        |
//|   Data kalender disinkronkan otomatis oleh terminal MT5 dari     |
//|   MetaQuotes - pastikan opsi kalender aktif di terminal (biasanya|
//|   default aktif). Kalau CalendarValueHistory() gagal/return      |
//|   kosong terus-menerus, cek: Tools > Options > kalender aktif,   |
//|   atau memang tidak ada event untuk currency pair ini.           |
//+------------------------------------------------------------------+
#ifndef SMC_NEWSFILTER_MQH
#define SMC_NEWSFILTER_MQH

#include "..\Core\SMC_Types.mqh"
#include "..\Core\SMC_Config.mqh"
#include "..\Core\GP_Time.mqh"

//======================================================================
// STATE
//======================================================================
NewsEvent g_upcomingNews[];
datetime  g_lastNewsRefresh = 0;

//======================================================================
// INIT
//======================================================================
void SMC_NewsFilter_Init()
  {
   ArrayFree(g_upcomingNews);
   g_lastNewsRefresh = 0;
  }

//======================================================================
// HELPER: pecah nama simbol jadi 2 kode currency (EURUSD -> EUR, USD).
// Untuk simbol non-forex standar (XAUUSD, dst) currency pertama (XAU)
// mungkin tidak selalu match kalender berita - itu wajar, kalender
// tetap jalan untuk currency kedua (USD).
//======================================================================
void GetSymbolCurrencies(string &base, string &quote)
  {
   base  = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   quote = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);

   // Fallback kalau broker tidak mengisi field di atas dengan benar
   if(base == "" || quote == "")
     {
      string s = _Symbol;
      if(StringLen(s) >= 6)
        {
         base  = StringSubstr(s, 0, 3);
         quote = StringSubstr(s, 3, 3);
        }
     }
  }

//======================================================================
// HELPER: konversi ENUM_CALENDAR_EVENT_IMPORTANCE ke int, untuk
// dibandingkan dengan InpNewsMinImportance (0=rendah,1=sedang,2=tinggi).
//======================================================================
int ImportanceToInt(ENUM_CALENDAR_EVENT_IMPORTANCE imp)
  {
   switch(imp)
     {
      case CALENDAR_IMPORTANCE_HIGH:     return 2;
      case CALENDAR_IMPORTANCE_MODERATE: return 1;
      default:                            return 0;
     }
  }

//======================================================================
// HELPER: fetch event untuk satu currency dalam rentang waktu, filter
// berdasarkan importance minimum, tambahkan ke array output.
//======================================================================
void FetchNewsForCurrency(string currency, datetime fromTime, datetime toTime)
  {
   if(currency == "")
      return;

   MqlCalendarValue values[];
   int count = CalendarValueHistory(values, fromTime, toTime, NULL, currency);
   if(count <= 0)
      return; // tidak ada event, atau kalender belum sinkron - bukan error fatal

   for(int i = 0; i < count; i++)
     {
      MqlCalendarEvent evt;
      if(!CalendarEventById(values[i].event_id, evt))
         continue;

      int importance = ImportanceToInt(evt.importance);
      if(importance < InpNewsMinImportance)
         continue;

      datetime eventTime = GP_CalTime(values[i].time);   // GoldPro: koreksi jam kalender lintas DST
      datetime now = TimeCurrent();
      long secBefore = eventTime - now;
      long secAfter  = now - eventTime;

      bool isBlackout = (secBefore >= 0 && secBefore <= InpNewsBlackoutBeforeMin * 60)
                         || (secAfter >= 0 && secAfter <= InpNewsBlackoutAfterMin * 60);

      int n = ArraySize(g_upcomingNews);
      ArrayResize(g_upcomingNews, n + 1);
      g_upcomingNews[n].name          = evt.name;
      g_upcomingNews[n].currency      = currency;
      g_upcomingNews[n].eventTime     = eventTime;
      g_upcomingNews[n].importance    = importance;
      g_upcomingNews[n].isBlackoutNow = isBlackout;
     }
  }

//======================================================================
// FUNGSI UTAMA - refresh cache tiap InpNewsCacheRefreshMin menit
// (data kalender tidak berubah tiap detik, tidak perlu query tiap bar)
//======================================================================
void SMC_NewsFilter_Update(bool isNewBar)
  {
   if(!InpEnableNewsFilter)
      return;
   if(!isNewBar)
      return;

   datetime now = TimeCurrent();
   if(g_lastNewsRefresh != 0 && (now - g_lastNewsRefresh) < InpNewsCacheRefreshMin * 60)
     {
      // Belum waktunya refresh penuh, tapi status blackout tetap perlu
      // di-update tiap panggilan karena berjalan seiring waktu berjalan.
      for(int i = 0; i < ArraySize(g_upcomingNews); i++)
        {
         long secBefore = g_upcomingNews[i].eventTime - now;
         long secAfter  = now - g_upcomingNews[i].eventTime;
         g_upcomingNews[i].isBlackoutNow =
            (secBefore >= 0 && secBefore <= InpNewsBlackoutBeforeMin * 60)
            || (secAfter >= 0 && secAfter <= InpNewsBlackoutAfterMin * 60);
        }
      return;
     }

   g_lastNewsRefresh = now;
   ArrayFree(g_upcomingNews);

   string base, quote;
   GetSymbolCurrencies(base, quote);

   datetime fromTime = now - 3600 * 6;       // termasuk beberapa jam ke belakang (untuk blackout-after)
   datetime toTime    = now + 86400 * 3;      // 3 hari ke depan cukup untuk keperluan dashboard/scoring

   FetchNewsForCurrency(base, fromTime, toTime);
   if(quote != base)
      FetchNewsForCurrency(quote, fromTime, toTime);
  }

//======================================================================
// ACCESSOR
//======================================================================
bool IsNewsBlackout()
  {
   if(!InpEnableNewsFilter)
      return false;

   for(int i = 0; i < ArraySize(g_upcomingNews); i++)
      if(g_upcomingNews[i].isBlackoutNow)
         return true;
   return false;
  }

// Event berita relevan terdekat di masa depan (untuk narrative/dashboard,
// misal "NFP dalam 42 menit") - tidak harus yang blackout, cukup terdekat.
bool GetNextNewsEvent(NewsEvent &outEvent)
  {
   bool     found   = false;
   datetime now     = TimeCurrent();
   long     bestDiff = LONG_MAX;

   for(int i = 0; i < ArraySize(g_upcomingNews); i++)
     {
      long diff = g_upcomingNews[i].eventTime - now;
      if(diff < 0)
         continue; // sudah lewat
      if(diff < bestDiff)
        {
         bestDiff = diff;
         outEvent = g_upcomingNews[i];
         found    = true;
        }
     }
   return found;
  }

#endif // SMC_NEWSFILTER_MQH
