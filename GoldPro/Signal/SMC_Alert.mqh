//+------------------------------------------------------------------+
//|                                                     SMC_Alert.mqh |
//|                                                                  |
//| Fase 6 - File 22/24 : SMC Pro System                             |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Notifikasi lokal (sound/popup/push MT5) berdasarkan kondisi    |
//|   trigger dari Scoring & Structure. TIDAK terlibat format data   |
//|   ekspor - itu tugas SMC_SignalExport.mqh.                      |
//+------------------------------------------------------------------+
#ifndef SMC_ALERT_MQH
#define SMC_ALERT_MQH

#include "..\Core\SMC_Config.mqh"
#include "..\Detection\SMC_Structure.mqh"
#include "..\Analysis\SMC_Scoring.mqh"

//======================================================================
// STATE - dedup supaya tidak alert berkali-kali untuk event yang sama
//======================================================================
long                 g_lastAlertedEventId = -1;
ENUM_ENTRY_DECISION  g_prevDecisionForAlert = DECISION_NO_ZONE;

//======================================================================
// INIT
//======================================================================
void SMC_Alert_Init()
  {
   g_lastAlertedEventId    = -1;
   g_prevDecisionForAlert  = DECISION_NO_ZONE;
  }

//======================================================================
// HELPER: kirim alert lewat semua channel yang diaktifkan
//======================================================================
void FireAlert(string message)
  {
   PrintFormat("[SMC_Alert] %s", message);
   Alert(message);
   if(InpAlertSound)
      PlaySound("alert.wav");
   if(InpAlertPushNotify)
      SendNotification(message);
  }

//======================================================================
// FUNGSI UTAMA
//======================================================================
void SMC_Alert_Update(bool isNewBar)
  {
   if(!isNewBar)
      return;

   // --- Alert CHoCH ---
   if(InpSMCAlertCHoCH)
     {
      StructureEvent evt;
      if(GetLastStructureEvent(evt) && !evt.isBOS && evt.id != g_lastAlertedEventId)
        {
         g_lastAlertedEventId = evt.id;
         FireAlert(StringFormat("[SMC INFO, belum terbukti] %s CHoCH %s @ %.2f",
                                 _Symbol, evt.direction == BIAS_BULLISH ? "Bullish" : "Bearish", evt.price));
        }
     }

   // --- Alert Entry OK (deteksi transisi, bukan tiap bar selama status ENTRY_OK) ---
   BiasState bs = GetBiasState();
   if(InpSMCAlertEntryOK && bs.decision == DECISION_ENTRY_OK && g_prevDecisionForAlert != DECISION_ENTRY_OK)
     {
      FireAlert(StringFormat("[SMC INFO, belum terbukti] %s ENTRY OK skor %.0f%% %s %s",
                              _Symbol, bs.scoreBreakdown.scoreTotal, ::GP_TFName(),
                              bs.ltfBias == BIAS_BULLISH ? "BULL" : (bs.ltfBias == BIAS_BEARISH ? "BEAR" : "")));
     }
   g_prevDecisionForAlert = bs.decision;
  }

#endif // SMC_ALERT_MQH
