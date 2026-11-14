#ifndef GP_DIRECTION_ENGINE_MQH
#define GP_DIRECTION_ENGINE_MQH

//+------------------------------------------------------------------+
//| GP_DirectionEngine.mqh                                            |
//|                                                                  |
//| GoldPro direction orchestration layer.                           |
//|                                                                  |
//| Tujuan utama: mengumpulkan snapshot fitur yang sudah ada di repo, |
//| lalu menilai apakah konteks gabungan hari ini memberi bias naik,   |
//| turun, atau netral untuk horizon tertentu.                        |
//|                                                                  |
//| Desain:                                                         |
//| - built on raw market data + GoldPro level references             |
//| - replay-safe: tidak membaca state masa depan                     |
//| - evaluator diseparasi dari decision layer                        |
//| - netral diprioritaskan bila evidence belum cukup                 |
//+------------------------------------------------------------------+

#include "..\Core\SMC_Utils.mqh"
#include "..\Core\SMC_Types.mqh"

//======================================================================
// DIRECTION ENUM
//======================================================================
enum GP_DIRECTION_LABEL
  {
   GP_DIR_NEUTRAL = 0,
   GP_DIR_BUY     = 1,
   GP_DIR_SELL    = -1
  };

//======================================================================
// SNAPSHOT: fitur gabungan yang diuji pada saat titik waktu tertentu
//======================================================================
struct GPDirSnapshot
  {
   datetime time;
   double   open;
   double   high;
   double   low;
   double   close;

   // ATR / ADR damping
   double   atrFast;
   double   atrSlow;
   double   adr;

   // Daily / weekly refs
   double   dOpen;
   double   dPrevClose;
   double   dEq;
   double   dHigh;
   double   dLow;
   double   dRange;

   double   wOpen;
   double   wPrevClose;
   double   wEq;
   double   wHigh;
   double   wLow;
   double   wRange;

   // posisi relatif terhadap level
   double   distToDailyEq;
   double   distToWeeklyEq;
   double   distToDayHigh;
   double   distToDayLow;
   double   distToWeekHigh;
   double   distToWeekLow;

   // karakter pasar
   double   trendBias;   // skala [-1,1], positif = bullish tendency
   double   volatility;
   double   pressure;    // ke mana tekanan cenderung bergerak

   // indikator sesi (baku untuk mesin arah)
   int      session;
   bool     isLondonSession;
   bool     isNewYorkSession;
   bool     isAsiaSession;

   // ekstra: candlestick context
   bool     bullishBar;
   bool     bearishBar;
   int      bodySize;              // 1: kecil, 2: sedang, 3: besar
   double   bodyToRangeRatio;

   // hasil waktu depan yang dipakai evaluator
   double   forwardMove;
   double   forwardMoveAbs;
   double   forwardMovePct;
  };

//======================================================================
// EVALUATION RESULT
//======================================================================
struct GPDirEvalMetric
  {
   int      total;
   int      buyCount;
   int      sellCount;
   int      neutralCount;
   int      buyWin;
   int      sellWin;
   double   buyWinRate;
   double   sellWinRate;
   double   netRate;
   double   avgMove;
   double   avgMoveBuy;
   double   avgMoveSell;
   double   maxDrawdown;
   double   score;
  };

//======================================================================
// HELPERS
//======================================================================
string GPDir_LabelText(GP_DIRECTION_LABEL v)
  {
   if(v == GP_DIR_BUY)  return "BUY";
   if(v == GP_DIR_SELL) return "SELL";
   return "NEUTRAL";
  }

// Rumus sesi dasar yang bisa dipakai tanpa dependency ke module lain.
// DateTime lokal server dipakai untuk menghindari asumsi broker yang beda.
int GPDir_ClassifySession(datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);

   // Asumsi WITA / server time sebagai input umum. Ini hanya untuk konteks,
   // bukan untuk order execution. Untuk EA live, bisa ditukar dengan utilitaire
   // Time zone yang lebih tepat bila sudah ada di repo.
   int hour = dt.hour;

   if(hour >= 0 && hour < 7) return 0;   // Asia / early session
   if(hour >= 7 && hour < 12) return 1;  // London
   if(hour >= 12 && hour < 18) return 2; // New York / overlap
   return 0;
  }

bool GPDir_IsBullishCandle(const MqlRates &r)
  {
   return (r.close >= r.open);
  }

// Candlestick body size coarse bucket
int GPDir_BodyBucket(const MqlRates &r)
  {
   double range = MathMax(r.high - r.low, _Point);
   double body  = MathAbs(r.close - r.open);
   double ratio  = body / range;

   if(ratio < 0.25) return 1;
   if(ratio < 0.60) return 2;
   return 3;
  }

// Mengambil level-level dasar dari D1/W1 tanpa mengandalkan indikator state.
void GPDir_FillDailyWeeklyRefs(double &dOpen, double &dPrevClose, double &dEq, double &dHigh, double &dLow, double &dRange,
                              double &wOpen, double &wPrevClose, double &wEq, double &wHigh, double &wLow, double &wRange)
  {
   dOpen = iOpen(_Symbol, PERIOD_D1, 0);
   dPrevClose = iClose(_Symbol, PERIOD_D1, 1);
   dHigh = iHigh(_Symbol, PERIOD_D1, 0);
   dLow  = iLow(_Symbol, PERIOD_D1, 0);
   dEq   = (dOpen + dPrevClose) / 2.0;
   dRange = MathMax(dHigh - dLow, _Point);

   wOpen = iOpen(_Symbol, PERIOD_W1, 0);
   wPrevClose = iClose(_Symbol, PERIOD_W1, 1);
   wHigh = iHigh(_Symbol, PERIOD_W1, 0);
   wLow  = iLow(_Symbol, PERIOD_W1, 0);
   wEq   = (wOpen + wPrevClose) / 2.0;
   wRange = MathMax(wHigh - wLow, _Point);
  }

// Normalisasi jarak ke level dengan ATR/ADR agar layer indikator bisa dibandingkan antar TF.
double GPDir_NormalizedDistance(double price, double level, double scale)
  {
   if(scale <= 0)
      return 0.0;
   return MathAbs(price - level) / scale;
  }

//======================================================================
// SNAPSHOT CAPTURE
//======================================================================
void GPDir_CaptureSnapshot(ENUM_TIMEFRAMES tf, int shift, GPDirSnapshot &out)
  {
   MqlRates r;
   if(CopyRates(_Symbol, tf, shift, 1, r) <= 0)
      return;

   out.time     = r.time;
   out.open     = r.open;
   out.high     = r.high;
   out.low      = r.low;
   out.close    = r.close;
   out.atrFast  = GetATR(tf, 14, shift);
   out.atrSlow  = GetATR(tf, 50, shift);
   out.adr      = GetADR(PERIOD_D1, 20, shift);

   GPDir_FillDailyWeeklyRefs(out.dOpen, out.dPrevClose, out.dEq, out.dHigh, out.dLow, out.dRange,
                            out.wOpen, out.wPrevClose, out.wEq, out.wHigh, out.wLow, out.wRange);

   out.session = GPDir_ClassifySession(out.time);
   out.isLondonSession = (out.session == 1);
   out.isNewYorkSession = (out.session == 2);
   out.isAsiaSession = (out.session == 0);

   out.bullishBar = GPDir_IsBullishCandle(r);
   out.bearishBar = !out.bullishBar;
   out.bodySize   = GPDir_BodyBucket(r);
   out.bodyToRangeRatio = MathAbs(r.close - r.open) / MathMax(r.high - r.low, _Point);

   // Jarak level terhadap harga, dinormalisasi vs ATR/ADR
   double scale = MathMax(out.atrFast, out.adr * 0.5);
   out.distToDailyEq   = GPDir_NormalizedDistance(out.close, out.dEq, scale);
   out.distToWeeklyEq  = GPDir_NormalizedDistance(out.close, out.wEq, scale);
   out.distToDayHigh   = GPDir_NormalizedDistance(out.close, out.dHigh, scale);
   out.distToDayLow    = GPDir_NormalizedDistance(out.close, out.dLow, scale);
   out.distToWeekHigh  = GPDir_NormalizedDistance(out.close, out.wHigh, scale);
   out.distToWeekLow   = GPDir_NormalizedDistance(out.close, out.wLow, scale);

   // Trend bias: arah yang dominan dari struktur sederhana terhadap EQ dan open.
   double bias = 0.0;
   if(out.close > out.dEq) bias += 0.35;
   if(out.close < out.dEq) bias -= 0.35;
   if(out.close > out.wEq) bias += 0.25;
   if(out.close < out.wEq) bias -= 0.25;
   if(out.close > out.open) bias += 0.20;
   if(out.close < out.open) bias -= 0.20;
   if(out.close > out.high) bias += 0.10;
   if(out.close < out.low) bias -= 0.10;
   out.trendBias = MathMax(-1.0, MathMin(1.0, bias));

   // Volatility proxy
   out.volatility = out.atrFast / MathMax(out.adr, _Point);
   out.pressure = 0.0;
   if(out.close > out.dEq && out.close > out.wEq) out.pressure += 0.30;
   if(out.close < out.dEq && out.close < out.wEq) out.pressure -= 0.30;
   if(out.close > out.open) out.pressure += 0.10;
   if(out.close < out.open) out.pressure -= 0.10;
   out.pressure = MathMax(-1.0, MathMin(1.0, out.pressure));
  }

//======================================================================
// DECISION ENGINE (gabungan level + momentum + konteks)
//======================================================================
GP_DIRECTION_LABEL GPDir_ScoreDirection(const GPDirSnapshot &s)
  {
   double score = 0.0;

   // 1) Daily / weekly equilibrium bias
   if(s.close > s.dEq) score += 0.7;
   else if(s.close < s.dEq) score -= 0.7;

   if(s.close > s.wEq) score += 0.5;
   else if(s.close < s.wEq) score -= 0.5;

   // 2) Level extreme bias (high/low weekly/day)
   if(s.close > s.dHigh * 0.996) score += 0.2;
   if(s.close < s.dLow * 1.004)  score -= 0.2;
   if(s.close > s.wHigh * 0.995) score += 0.3;
   if(s.close < s.wLow * 1.005) score -= 0.3;

   // 3) Momentum / bar direction plus pressure
   if(s.bullishBar) score += 0.35;
   if(s.bearishBar) score -= 0.35;

   if(s.bodyToRangeRatio > 0.45) score += 0.15 * (s.bullishBar ? 1.0 : -1.0);

   // 4) Trend bias / pressure
   score += s.trendBias * 0.9;
   score += s.pressure * 0.8;

   // 5) Volatility gate: terlalu volatile / terlalu flat = netral
   if(s.volatility < 0.35 || s.volatility > 2.0)
      {
       score *= 0.7;
      }

   // 6) Session guard: Asia often low conviction unless accompanied by level alignment.
   if(s.isAsiaSession && MathAbs(score) < 0.75)
      return GP_DIR_NEUTRAL;

   if(score > 0.75) return GP_DIR_BUY;
   if(score < -0.75) return GP_DIR_SELL;
   return GP_DIR_NEUTRAL;
  }

//======================================================================
// FORWARD MOVE / LABEL VALIDATION
//======================================================================
// Horizon bar: 1 = candle ini, 5 = 5 candle ke depan.
double GPDir_ForwardMove(ENUM_TIMEFRAMES tf, int startShift, int horizonBars)
  {
   double startClose = iClose(_Symbol, tf, startShift);
   double endClose   = iClose(_Symbol, tf, startShift + horizonBars);
   return (endClose - startClose);
  }

bool GPDir_OutcomeIsWin(GP_DIRECTION_LABEL label, double forwardMove, double threshold)
  {
   if(label == GP_DIR_BUY)
      return forwardMove >= threshold;
   if(label == GP_DIR_SELL)
      return forwardMove <= -threshold;
   return MathAbs(forwardMove) < threshold;
  }

//======================================================================
// EVALUATOR: sampel per bar history, label dibanding forward move
//======================================================================
void GPDir_EvaluateWindow(ENUM_TIMEFRAMES tf, int startShift, int samples,
                          int horizonBars, double threshold,
                          GPDirEvalMetric &out)
  {
   ZeroMemory(out);
   out.total = 0;

   for(int i = 0; i < samples; i++)
      {
       int shift = startShift + i;
       if(shift + horizonBars >= iBars(_Symbol, tf))
          break;

       GPDirSnapshot s;
       GPDir_CaptureSnapshot(tf, shift, s);
       if(s.time == 0)
          continue;

       GP_DIRECTION_LABEL dir = GPDir_ScoreDirection(s);
       s.forwardMove = GPDir_ForwardMove(tf, shift, horizonBars);
       s.forwardMoveAbs = MathAbs(s.forwardMove);
       s.forwardMovePct = s.forwardMove / MathMax(MathAbs(s.close), _Point);

       out.total++;
       if(dir == GP_DIR_BUY)
         {
          out.buyCount++;
          if(GPDir_OutcomeIsWin(dir, s.forwardMove, threshold))
             out.buyWin++;
          out.avgMoveBuy += s.forwardMove;
         }
       else if(dir == GP_DIR_SELL)
         {
          out.sellCount++;
          if(GPDir_OutcomeIsWin(dir, s.forwardMove, threshold))
             out.sellWin++;
          out.avgMoveSell += s.forwardMove;
         }
       else
         {
          out.neutralCount++;
         }

       out.avgMove += s.forwardMove;
      }

   if(out.buyCount > 0)
      out.buyWinRate = (double)out.buyWin / (double)out.buyCount;
   if(out.sellCount > 0)
      out.sellWinRate = (double)out.sellWin / (double)out.sellCount;

   if(out.total > 0)
      out.netRate = out.avgMove / (double)out.total;

   if(out.buyCount > 0)
      out.avgMoveBuy /= (double)out.buyCount;
   if(out.sellCount > 0)
      out.avgMoveSell /= (double)out.sellCount;

   out.score = (out.buyWinRate * 0.5 + out.sellWinRate * 0.5) * 100.0;
   out.score += (out.netRate > 0 ? 5.0 : -5.0);
  }

//======================================================================
// REPORTING
//======================================================================
void GPDir_PrintEvalReport(const GPDirEvalMetric &m, const string label)
  {
   PrintFormat("[GP_DirectionEngine] %s | total=%d buy=%d sell=%d neutral=%d buyWR=%.2f sellWR=%.2f avgMove=%.5f | score=%.2f",
               label,
               m.total,
               m.buyCount,
               m.sellCount,
               m.neutralCount,
               m.buyWinRate * 100.0,
               m.sellWinRate * 100.0,
               m.netRate,
               m.score);
  }

//======================================================================
// SINTAKS BENTUKAN: semua fitur dirangkum menjadi 1 keputusan
// yang bisa dipakai oleh EA / dashboard / alert.
//======================================================================
GP_DIRECTION_LABEL GPDir_GetCurrentDecision(ENUM_TIMEFRAMES tf, bool &outStrongBias, double &outScore)
  {
   GPDirSnapshot s;
   GPDir_CaptureSnapshot(tf, 1, s);
   GP_DIRECTION_LABEL decision = GPDir_ScoreDirection(s);
   outStrongBias = (MathAbs(s.trendBias) > 0.6 || MathAbs(s.pressure) > 0.7);
   outScore = s.trendBias + s.pressure;
   return decision;
  }

#endif // GP_DIRECTION_ENGINE_MQH

//+------------------------------------------------------------------+
//| Catatan penggunaan:                                               |
//|                                                                  |
//| 1) File ini disebut sebagai engine arah ORCHESTRATOR, bukan       |
//|    “indikator arah final”.                                        |
//|                                                                  |
//| 2) Untuk evaluasi yang valid, gunakan fungsi GPDir_EvaluateWindow |
//|    pada data replay dengan split train/test.                      |
//|                                                                  |
//| 3) Bila score tidak cukup kuat, keluarkan NEUTRAL.                |
//|    Ini mencegah false confidence yang sering merusak sistem.       |
//+------------------------------------------------------------------+
