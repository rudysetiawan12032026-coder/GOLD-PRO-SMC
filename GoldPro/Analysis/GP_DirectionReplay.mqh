#ifndef GP_DIRECTION_REPLAY_MQH
#define GP_DIRECTION_REPLAY_MQH

//+------------------------------------------------------------------+
//| GP_DirectionReplay.mqh                                            |
//|                                                                  |
//| Historis replay evaluator untuk engine arah GoldPro.             |
//|                                                                  |
//| Fokus:                                                           |
//| - replay bar-per-bar pada timeframe tertentu                     |
//| - label BUY/SELL/NEUTRAL dari GP_DirectionEngine                 |
//| - bandingkan dengan forward move yang nyata                     |
//| - skala hasil untuk train/test / walk-forward                    |
//| - sangat penting untuk menghindari false confidence              |
//+------------------------------------------------------------------+

#include "GP_DirectionEngine.mqh"

//======================================================================
// REPLAY RESULT METRIC
//======================================================================
struct GPDirReplayStats
  {
   int    total;
   int    buyCount;
   int    sellCount;
   int    neutralCount;
   int    buyWin;
   int    sellWin;
   int    neutralWin;
   double buyWinRate;
   double sellWinRate;
   double neutralWinRate;
   double avgMove;
   double avgMoveBuy;
   double avgMoveSell;
   double netMove;
   double score;
  };

//======================================================================
// INITIALIZE
//======================================================================
void GPDir_ResetReplayStats(GPDirReplayStats &out)
  {
   ZeroMemory(out);
  }

//======================================================================
// REPLAY: hitung label arah vs forward move nyata di horizon tertentu
//======================================================================
void GPDir_ComputeReplayStats(ENUM_TIMEFRAMES tf, int startShift, int sampleCount,
                             int horizonBars, double threshold, GPDirReplayStats &out)
  {
   GPDir_ResetReplayStats(out);

   for(int i = 0; i < sampleCount; i++)
      {
       int shift = startShift + i;
       if(shift + horizonBars >= iBars(_Symbol, tf))
          break;

       GPDirSnapshot s;
       GPDir_CaptureSnapshot(tf, shift, s);
       if(s.time == 0)
          continue;

       GP_DIRECTION_LABEL dir = GPDir_ScoreDirection(s);
       double move = GPDir_ForwardMove(tf, shift, horizonBars);
       bool isWin = GPDir_OutcomeIsWin(dir, move, threshold);

       out.total++;
       switch(dir)
         {
          case GP_DIR_BUY:
             out.buyCount++;
             out.avgMoveBuy += move;
             if(isWin)
                {
                 out.buyWin++;
                 out.neutralWin++;
                }
             break;

          case GP_DIR_SELL:
             out.sellCount++;
             out.avgMoveSell += move;
             if(isWin)
                {
                 out.sellWin++;
                 out.neutralWin++;
                }
             break;

          default:
             out.neutralCount++;
             if(isWin)
                out.neutralWin++;
             break;
         }

       out.avgMove += move;
       out.netMove += move;
      }

   if(out.total > 0)
      {
       out.avgMove /= (double)out.total;
       out.netMove /= (double)out.total;
      }

   if(out.buyCount > 0)
      {
       out.buyWinRate = (double)out.buyWin / (double)out.buyCount;
       out.avgMoveBuy /= (double)out.buyCount;
      }

   if(out.sellCount > 0)
      {
       out.sellWinRate = (double)out.sellWin / (double)out.sellCount;
       out.avgMoveSell /= (double)out.sellCount;
      }

   if(out.neutralCount > 0)
      out.neutralWinRate = (double)out.neutralWin / (double)out.neutralCount;

   // Kombinasi skor kasar: tidak dipakai untuk trade, hanya untuk debug evaluasi.
   double winComposite = 0.0;
   if(out.buyCount > 0) winComposite += out.buyWinRate * 0.5;
   if(out.sellCount > 0) winComposite += out.sellWinRate * 0.5;
   if(out.neutralCount > 0) winComposite += out.neutralWinRate * 0.2;

   out.score = (winComposite * 100.0) + (out.netMove * 1000.0);
  }

//======================================================================
// PRINT REPORT
//======================================================================
void GPDir_PrintReplayStats(const GPDirReplayStats &s, const string label)
  {
   PrintFormat("[GP_DirectionReplay] %s | total=%d buy=%d sell=%d neutral=%d buyWR=%.2f%% sellWR=%.2f%% neutralWR=%.2f%% avgMove=%.5f netMove=%.5f score=%.2f",
               label,
               s.total,
               s.buyCount,
               s.sellCount,
               s.neutralCount,
               s.buyWinRate * 100.0,
               s.sellWinRate * 100.0,
               s.neutralWinRate * 100.0,
               s.avgMove,
               s.netMove,
               s.score);
  }

//======================================================================
// WALK-FORWARD SIMPLE: train/test split yang jelas dan aman dari look-ahead
//======================================================================
void GPDir_RunWalkForward(ENUM_TIMEFRAMES tf, int trainSamples, int testSamples,
                         int horizonBars, double threshold,
                         GPDirReplayStats &trainOut, GPDirReplayStats &testOut)
  {
   int bars = iBars(_Symbol, tf);
   if(bars <= trainSamples + testSamples + horizonBars)
      {
       Print("[GP_DirectionReplay] Data tidak cukup untuk walk-forward.");
       GPDir_ResetReplayStats(trainOut);
       GPDir_ResetReplayStats(testOut);
       return;
      }

   int trainStart = 0;
   int testStart  = trainSamples;

   GPDir_ComputeReplayStats(tf, trainStart, trainSamples, horizonBars, threshold, trainOut);
   GPDir_ComputeReplayStats(tf, testStart, testSamples, horizonBars, threshold, testOut);
  }

//======================================================================
// PENGUJIAN NAIK/TURUN DENGAN KETENTUAN KELUAR
//======================================================================
bool GPDir_IsDecisionUseful(const GPDirReplayStats &s)
  {
   if(s.total <= 20)
      return false;

   double buyRelevant = (s.buyCount > 0) ? s.buyWinRate : 0.0;
   double sellRelevant = (s.sellCount > 0) ? s.sellWinRate : 0.0;

   if(MathMax(buyRelevant, sellRelevant) < 0.52)
      return false;

   return true;
  }

#endif // GP_DIRECTION_REPLAY_MQH
