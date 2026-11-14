#ifndef GP_DIRECTION_MATRIX_MQH
#define GP_DIRECTION_MATRIX_MQH

//+------------------------------------------------------------------+
//| GP_DirectionMatrix.mqh                                           |
//|                                                                  |
//| Layer berikutnya: memetakan fitur per TF ke satu matriks arah.   |
//|                                                                  |
//| Fokus:                                                          |
//| - M1 / M5 / M15 / H1 punya level dan karakter sendiri            |
//| - WH / WL / EQ / daily open / weekly open dipetakan per TF        |
//| - gabungan fitur menghasilkan score arah yang lebih terukur      |
//| - output dibatasi pada BUY / SELL / NEUTRAL                       |
//+------------------------------------------------------------------+

#include "GP_DirectionEvaluator.mqh"

//======================================================================
// MATRICS: feature mapping per TF
//======================================================================
struct GPDirMatrixSnapshot
  {
   datetime time;

   double    m1EqBias;
   double    m5EqBias;
   double    m15EqBias;
   double    h1EqBias;

   double    m1WeekBias;
   double    m5WeekBias;
   double    m15WeekBias;
   double    h1WeekBias;

   double    m1Trend;
   double    m5Trend;
   double    m15Trend;
   double    h1Trend;

   double    volIndex;
   double    liquidityBias;
   double    structureBias;
   double    sessionBias;

   int       sessionType;
   bool      isAsia;
   bool      isLondon;
   bool      isNewYork;
  };

//======================================================================
// BUILD MATRIX FROM FEATURES
//======================================================================
void GPDir_BuildMatrixSnapshot(const GPDirContextFeature &m1,
                              const GPDirContextFeature &m5,
                              const GPDirContextFeature &m15,
                              const GPDirContextFeature &h1,
                              GPDirMatrixSnapshot &out)
  {
   ZeroMemory(out);

   out.time = m1.time;

   out.m1EqBias = (m1.close > m1.dailyEq) ? 1.0 : ((m1.close < m1.dailyEq) ? -1.0 : 0.0);
   out.m5EqBias = (m5.close > m5.dailyEq) ? 1.0 : ((m5.close < m5.dailyEq) ? -1.0 : 0.0);
   out.m15EqBias = (m15.close > m15.dailyEq) ? 1.0 : ((m15.close < m15.dailyEq) ? -1.0 : 0.0);
   out.h1EqBias = (h1.close > h1.dailyEq) ? 1.0 : ((h1.close < h1.dailyEq) ? -1.0 : 0.0);

   out.m1WeekBias = (m1.close > m1.weeklyEq) ? 1.0 : ((m1.close < m1.weeklyEq) ? -1.0 : 0.0);
   out.m5WeekBias = (m5.close > m5.weeklyEq) ? 1.0 : ((m5.close < m5.weeklyEq) ? -1.0 : 0.0);
   out.m15WeekBias = (m15.close > m15.weeklyEq) ? 1.0 : ((m15.close < m15.weeklyEq) ? -1.0 : 0.0);
   out.h1WeekBias = (h1.close > h1.weeklyEq) ? 1.0 : ((h1.close < h1.weeklyEq) ? -1.0 : 0.0);

   out.m1Trend = m1.trendBias;
   out.m5Trend = m5.trendBias;
   out.m15Trend = m15.trendBias;
   out.h1Trend = h1.trendBias;

   out.volIndex = (m5.volatility + m15.volatility + h1.volatility) / 3.0;
   out.liquidityBias = m5.pressure + m15.pressure + h1.pressure;
   out.structureBias = (m5.bodyToRangeRatio * (m5.bullishBar ? 1.0 : -1.0)) +
                       (m15.bodyToRangeRatio * (m15.bullishBar ? 1.0 : -1.0)) +
                       (h1.bodyToRangeRatio * (h1.bullishBar ? 1.0 : -1.0));

   out.sessionType = h1.sessionType;
   out.isAsia = h1.isAsia;
   out.isLondon = h1.isLondon;
   out.isNewYork = h1.isNewYork;

   out.sessionBias = 0.0;
   if(out.isLondon) out.sessionBias += 0.25;
   if(out.isNewYork) out.sessionBias += 0.35;
   if(out.isAsia) out.sessionBias -= 0.15;
  }

//======================================================================
// MATRIX SCORE
//======================================================================
GP_DIRECTION_LABEL GPDir_MatrixDecision(const GPDirMatrixSnapshot &x, double &outConfidence)
  {
   double score = 0.0;

   score += 0.30 * x.m1EqBias;
   score += 0.35 * x.m5EqBias;
   score += 0.45 * x.m15EqBias;
   score += 0.70 * x.h1EqBias;

   score += 0.20 * x.m1WeekBias;
   score += 0.25 * x.m5WeekBias;
   score += 0.30 * x.m15WeekBias;
   score += 0.40 * x.h1WeekBias;

   score += 0.40 * x.m1Trend;
   score += 0.55 * x.m5Trend;
   score += 0.80 * x.m15Trend;
   score += 1.10 * x.h1Trend;

   score += 0.50 * x.liquidityBias;
   score += 0.60 * x.structureBias;
   score += 0.40 * x.sessionBias;

   if(x.volIndex < 0.35 || x.volIndex > 2.0)
      score *= 0.65;

   // Asia saat low conviction tetap netral.
   if(x.isAsia && MathAbs(score) < 1.2)
      {
       outConfidence = 0.35;
       return GP_DIR_NEUTRAL;
      }

   outConfidence = MathMin(1.0, MathAbs(score) / 4.5);
   if(score > 1.35) return GP_DIR_BUY;
   if(score < -1.35) return GP_DIR_SELL;
   return GP_DIR_NEUTRAL;
  }

#endif // GP_DIRECTION_MATRIX_MQH
