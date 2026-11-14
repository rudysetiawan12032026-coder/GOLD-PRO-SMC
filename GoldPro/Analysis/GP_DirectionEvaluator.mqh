#ifndef GP_DIRECTION_EVALUATOR_MQH
#define GP_DIRECTION_EVALUATOR_MQH

//+------------------------------------------------------------------+
//| GP_DirectionEvaluator.mqh                                         |
//|                                                                  |
//| Evaluator gabungan untuk level + sesi + TF + kondisi pasar.       |
//|                                                                  |
//| Tujuan: menilai apakah kombinasi fitur GoldPro memang memberi     |
//| arah yang bermanfaat, atau sebaiknya tidak dipakai.              |
//+------------------------------------------------------------------+

#include "GP_DirectionContext.mqh"
#include "GP_DirectionHorizon.mqh"

struct GPDirEvalSummary
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
// ORCHESTRATOR: gabungkan konteks level + TF + sesi + momentum
//======================================================================
GP_DIRECTION_LABEL GPDir_CombinedDecision(const GPDirContextFeature &m1,
                                        const GPDirContextFeature &m5,
                                        const GPDirContextFeature &m15,
                                        const GPDirContextFeature &h1,
                                        double &outConfidence)
  {
   double score = 0.0;

   score += (m1.close > m1.dailyEq ? 0.55 : -0.55);
   score += (m5.close > m5.dailyEq ? 0.45 : -0.45);
   score += (m15.close > m15.dailyEq ? 0.35 : -0.35);
   score += (h1.close > h1.dailyEq ? 0.85 : -0.85);

   score += (h1.close > h1.weeklyEq ? 0.45 : -0.45);
   score += (m1.trendBias * 0.7);
   score += (m5.trendBias * 0.9);
   score += (h1.pressure * 1.1);

   // Volatilitas terlalu tinggi/terlalu rendah => menurunkan confidence.
   if(m5.volatility < 0.35 || m5.volatility > 2.0)
      score *= 0.65;

   // Sesi Asia tetap konservatif.
   if(h1.isAsia && MathAbs(score) < 1.0)
      {
       outConfidence = 0.35;
       return GP_DIR_NEUTRAL;
      }

   outConfidence = MathMin(1.0, MathAbs(score) / 3.2);
   if(score > 1.2) return GP_DIR_BUY;
   if(score < -1.2) return GP_DIR_SELL;
   return GP_DIR_NEUTRAL;
  }

//======================================================================
// REPLAY EVALUATOR
//======================================================================
void GPDir_RunReplayEvaluator(ENUM_TIMEFRAMES tf, int startShift, int sampleCount,
                             int horizonBars, double threshold, GPDirEvalSummary &out)
  {
   ZeroMemory(out);

   for(int i = 0; i < sampleCount; i++)
      {
       int s = startShift + i;
       if(s + horizonBars >= iBars(_Symbol, tf))
          break;

       GPDirContextFeature m1, m5, m15, h1;
       GPDir_BuildContextFeature(PERIOD_M1, s, m1);
       GPDir_BuildContextFeature(PERIOD_M5, s, m5);
       GPDir_BuildContextFeature(PERIOD_M15, s, m15);
       GPDir_BuildContextFeature(PERIOD_H1, s, h1);

       double conf = 0.0;
       GP_DIRECTION_LABEL d = GPDir_CombinedDecision(m1, m5, m15, h1, conf);
       double move = GPDir_HorizonMove(tf, s, horizonBars);
       bool win = GPDir_OutcomeIsWin(d, move, threshold);

       out.total++;
       if(d == GP_DIR_BUY)
         {
          out.buyCount++;
          out.avgMoveBuy += move;
          if(win) out.buyWin++;
         }
       else if(d == GP_DIR_SELL)
         {
          out.sellCount++;
          out.avgMoveSell += move;
          if(win) out.sellWin++;
         }
       else
         {
          out.neutralCount++;
          if(win) out.neutralWin++;
         }

       out.avgMove += move;
       out.netMove += move;
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

   if(out.total > 0)
      out.avgMove = out.avgMove / (double)out.total;

   out.score = (out.buyWinRate * 0.5 + out.sellWinRate * 0.5) * 100.0;
   out.score += (out.netMove * 1000.0);
  }

void GPDir_PrintEvalSummary(const GPDirEvalSummary &s, const string name)
  {
   PrintFormat("[GP_DirectionEvaluator] %s | total=%d buy=%d sell=%d neutral=%d buyWR=%.2f%% sellWR=%.2f%% neutralWR=%.2f%% avgMove=%.5f netMove=%.5f score=%.2f",
               name,
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

#endif // GP_DIRECTION_EVALUATOR_MQH
