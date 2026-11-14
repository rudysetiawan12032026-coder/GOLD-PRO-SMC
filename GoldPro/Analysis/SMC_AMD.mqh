//+------------------------------------------------------------------+
//|                                                      SMC_AMD.mqh |
//|                                                                  |
//| Fase 3 - File 10/24 : SMC Pro System                             |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Satu-satunya tempat waktu (Session) dan likuiditas (Liquidity) |
//|   bertemu. Menentukan fase Accumulation-Manipulation-Distribution|
//|   dan flag Judas Swing. Ini yang menghapus circular dependency   |
//|   yang sempat ada antara SMC_Session.mqh dan SMC_Liquidity.mqh.  |
//+------------------------------------------------------------------+
#ifndef SMC_AMD_MQH
#define SMC_AMD_MQH

#include "..\Core\SMC_Types.mqh"
#include "..\Core\SMC_Config.mqh"
#include "SMC_Session.mqh"
#include "..\Detection\SMC_Liquidity.mqh"
#include "..\Detection\SMC_MarketCondition.mqh"

//======================================================================
// STATE
//======================================================================
AMDState g_amdState;

//======================================================================
// INIT
//======================================================================
void SMC_AMD_Init()
  {
   ZeroMemory(g_amdState);
   g_amdState.phase = AMD_NONE;
  }

//======================================================================
// HELPER: cek apakah ada liquidity pool yang di-sweep dalam window
// pembukaan sesi tertentu (indikasi Judas Swing).
//======================================================================
bool FindJudasSweepInSession(ENUM_SESSION session, datetime &outSweptTime)
  {
   if(!IsWithinSessionOpeningWindow(session, InpJudasSwingWindowMin))
      return false;

   datetime sessionStart = GetSessionStartTimeToday(session);

   for(int i = 0; i < GetLiquidityPoolCount(); i++)
     {
      LiquidityPool pool;
      if(!GetLiquidityPool(i, pool))
         continue;

      if(pool.swept && pool.sweptTime >= sessionStart)
        {
         outSweptTime = pool.sweptTime;
         return true;
        }
     }
   return false;
  }

//======================================================================
// FUNGSI UTAMA
//   REVISI (Batch 3): sekarang menerima StructureEvent & LiquidityPool
//   TERBARU sebagai parameter (bukan tahu soal Structure module lewat
//   #include - itu tetap dilarang, cuma menerima STRUCT DATA lewat
//   parameter, sesuai desain yang sudah disepakati). Ini memperbaiki
//   akar masalah lama: sebelumnya AMD_NONE/ACCUMULATION murni dari LABEL
//   SESI, tanpa peduli apakah ada breakout struktural nyata yang baru
//   saja terjadi - itu sebabnya "AMD Phase: -" muncul di luar jam
//   killzone standar (misal 22:28) padahal BOS/CHoCH aktif baru terjadi.
//======================================================================
void SMC_AMD_Update(bool isNewBar, bool hasStructEvent, StructureEvent &lastStructEvent,
                     bool hasLiqEvent, LiquidityPool &lastLiqEvent)
  {
   if(!isNewBar)
      return;

   ENUM_SESSION currentSession = GetCurrentSession();
   MarketConditionState mc     = GetMarketCondition();

   datetime sweptTime;
   bool isJudas = false;

   // Cek window pembukaan London dulu, baru NY (keduanya killzone kandidat manipulasi)
   if(FindJudasSweepInSession(SESSION_LONDON, sweptTime))
      isJudas = true;
   else if(FindJudasSweepInSession(SESSION_NEWYORK, sweptTime))
      isJudas = true;

   // BARU: liquidity sweep SEGAR (beberapa bar terakhir) di LUAR window
   // Judas standar - manipulasi tetap bisa terjadi di luar jam London/NY.
   bool hasRecentLiqSweep = false;
   if(!isJudas && hasLiqEvent)
     {
      int barsAgo = iBarShift(_Symbol, PERIOD_CURRENT, lastLiqEvent.sweptTime);
      if(barsAgo >= 0 && barsAgo <= 3)
         hasRecentLiqSweep = true;
     }

   // BARU: breakout struktural SEGAR (BOS/CHoCH beberapa bar terakhir) -
   // ini akar fix Bug #2 yang sudah lama didiagnosis (lihat sesi mentoring
   // sebelumnya): breakout nyata harus bisa mengangkat fase ke DISTRIBUTION
   // apapun label sesinya, bukan cuma bergantung sesi/killzone.
   bool hasRecentBreak = false;
   if(hasStructEvent)
     {
      int barsAgo = iBarShift(_Symbol, PERIOD_CURRENT, lastStructEvent.time);
      if(barsAgo >= 0 && barsAgo <= 3)
         hasRecentBreak = true;
     }

   if(isJudas)
     {
      g_amdState.phase          = AMD_MANIPULATION;
      g_amdState.isJudasSwing   = true;
      g_amdState.phaseStartTime = sweptTime;
     }
   else if(hasRecentLiqSweep)
     {
      g_amdState.phase          = AMD_MANIPULATION;
      g_amdState.isJudasSwing   = false;
      g_amdState.phaseStartTime = lastLiqEvent.sweptTime;
     }
   else if(hasRecentBreak)
     {
      g_amdState.phase          = AMD_DISTRIBUTION;
      g_amdState.isJudasSwing   = false;
      g_amdState.phaseStartTime = lastStructEvent.time;
     }
   else if(currentSession == SESSION_ASIA || mc.condition == CONDITION_COMPRESSED)
     {
      g_amdState.phase          = AMD_ACCUMULATION;
      g_amdState.isJudasSwing   = false;
      g_amdState.phaseStartTime = GetSessionStartTimeToday(SESSION_ASIA);
     }
   else if(IsKillzoneActive())
     {
      g_amdState.phase          = AMD_DISTRIBUTION;
      g_amdState.isJudasSwing   = false;
      g_amdState.phaseStartTime = GetSessionStartTimeToday(currentSession);
     }
   else
     {
      g_amdState.phase        = AMD_NONE;
      g_amdState.isJudasSwing = false;
     }
  }

//======================================================================
// ACCESSOR
//======================================================================
AMDState GetAMDState() { return g_amdState; }

#endif // SMC_AMD_MQH