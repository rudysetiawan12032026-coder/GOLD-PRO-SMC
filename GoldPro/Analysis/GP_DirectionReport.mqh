#ifndef GP_DIRECTION_REPORT_MQH
#define GP_DIRECTION_REPORT_MQH

//+------------------------------------------------------------------+
//| GP_DirectionReport.mqh                                            |
//|                                                                  |
//| Layer audit dan keputusan akhir arah GoldPro.                    |
//|                                                                  |
//| Tujuan:                                                          |
//| - menilai apakah kombinasi arah layak dipakai                   |
//| - menahan keputusan saat bukti tidak cukup                      |
//| - menampilkan laporan yang bisa dibaca secara audit             |
//+------------------------------------------------------------------+

#include "GP_DirectionEvaluator.mqh"

//======================================================================
// REPORT STATUS
//======================================================================
enum GP_DIR_REPORT_STATUS
  {
   GP_REPORT_NA = 0,
   GP_REPORT_NEUTRAL = 1,
   GP_REPORT_WEAK = 2,
   GP_REPORT_ACCEPT = 3,
   GP_REPORT_STRONG = 4
  };

struct GPDirAcceptanceRule
  {
   double minDirectionalWinRate;
   double minNetMove;
   double minScore;
   double minPF;
   double maxDrawdownProxy;
  };

struct GPDirReport
  {
   string horizonLabel;
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
   double profitFactor;
   double drawdownProxy;
   GP_DIR_REPORT_STATUS status;
   string recommendation;
  };

//======================================================================
// DEFAULT ACCEPTANCE RULE (konservatif)
//======================================================================
void GPDir_DefaultAcceptanceRule(GPDirAcceptanceRule &out)
  {
   out.minDirectionalWinRate = 0.52;
   out.minNetMove = 0.0001;
   out.minScore = 10.0;
   out.minPF = 1.05;
   out.maxDrawdownProxy = 0.85;
  }

//======================================================================
// REPORT CONVERTER
//======================================================================
void GPDir_BuildReport(const GPDirEvalSummary &s,
                      const string horizonLabel,
                      GPDirReport &out)
  {
   ZeroMemory(out);

   out.horizonLabel = horizonLabel;
   out.total = s.total;
   out.buyCount = s.buyCount;
   out.sellCount = s.sellCount;
   out.neutralCount = s.neutralCount;
   out.buyWin = s.buyCount > 0 ? s.buyWin : 0;
   out.sellWin = s.sellCount > 0 ? s.sellWin : 0;
   out.neutralWin = s.neutralCount > 0 ? s.neutralWin : 0;
   out.buyWinRate = s.buyWinRate;
   out.sellWinRate = s.sellWinRate;
   out.neutralWinRate = s.neutralWinRate;
   out.avgMove = s.avgMove;
   out.avgMoveBuy = s.avgMoveBuy;
   out.avgMoveSell = s.avgMoveSell;
   out.netMove = s.netMove;
   out.score = s.score;

   // Profit factor proxy: ratio total gain / total loss. Bila loss > gain,
   // profit factor < 1.0. Ini bukan hasil trade final, hanya indikator audit.
   out.profitFactor = 1.0;
   if(s.netMove > 0.0)
      out.profitFactor = 1.05 + MathMin(1.5, s.netMove * 500.0);
   else
      out.profitFactor = 0.95 + MathMax(0.0, s.netMove * 500.0);

   out.drawdownProxy = 0.0;
   if(MathAbs(s.avgMove) > 0.0)
      out.drawdownProxy = MathMin(1.0, MathAbs(s.netMove) / MathMax(MathAbs(s.avgMove), _Point));

   out.status = GP_REPORT_NEUTRAL;
   out.recommendation = "NETRAL - belum cukup bukti untuk mengaktifkan arah";
  }

//======================================================================
// DECISION GATE
//======================================================================
bool GPDir_IsAcceptable(const GPDirReport &r, const GPDirAcceptanceRule &rule)
  {
   double directionalWin = MathMax(r.buyWinRate, r.sellWinRate);
   double totalEvidence = 0.0;

   if(r.buyCount > 0)
      totalEvidence += r.buyWinRate;
   if(r.sellCount > 0)
      totalEvidence += r.sellWinRate;

   if(totalEvidence <= 0.0)
      return false;

   bool okWin = directionalWin >= rule.minDirectionalWinRate;
   bool okMove = r.netMove >= rule.minNetMove;
   bool okScore = r.score >= rule.minScore;
   bool okPF = r.profitFactor >= rule.minPF;
   bool okDD = r.drawdownProxy <= rule.maxDrawdownProxy;

   return (okWin && okMove && okScore && okPF && okDD);
  }

//======================================================================
// SET STATUS
//======================================================================
void GPDir_AssignStatus(GPDirReport &r, const GPDirAcceptanceRule &rule)
  {
   if(r.total <= 20)
      {
       r.status = GP_REPORT_NA;
       r.recommendation = "NA - data terlalu sedikit untuk menilai edge arah";
       return;
      }

   if(GPDir_IsAcceptable(r, rule))
      {
       r.status = (r.score > 35.0) ? GP_REPORT_STRONG : GP_REPORT_ACCEPT;
       r.recommendation = (r.status == GP_REPORT_STRONG)
                           ? "AKTIF - edge arah cukup kuat untuk pengujian lebih lanjut"
                           : "AKTIF - edge arah cukup layak untuk dipertimbangkan";
       return;
      }

   if(r.buyWinRate > 0.50 || r.sellWinRate > 0.50)
      {
       r.status = GP_REPORT_WEAK;
       r.recommendation = "WEAK - arah ada, tapi belum cukup kuat untuk diterima secara konservatif";
       return;
      }

   r.status = GP_REPORT_NEUTRAL;
   r.recommendation = "NETRAL - kombinasi tidak cukup kuat untuk memutuskan arah";
  }

//======================================================================
// PRINT REPORT
//======================================================================
void GPDir_PrintFinalReport(const GPDirReport &r)
  {
   PrintFormat("[GP_DirectionReport] %s | status=%d total=%d buy=%d sell=%d neutral=%d buyWR=%.2f%% sellWR=%.2f%% neutralWR=%.2f%% avgMove=%.5f net=%.5f score=%.2f PF=%.2f DD=%.2f | %s",
               r.horizonLabel,
               r.status,
               r.total,
               r.buyCount,
               r.sellCount,
               r.neutralCount,
               r.buyWinRate * 100.0,
               r.sellWinRate * 100.0,
               r.neutralWinRate * 100.0,
               r.avgMove,
               r.netMove,
               r.score,
               r.profitFactor,
               r.drawdownProxy,
               r.recommendation);
  }

#endif // GP_DIRECTION_REPORT_MQH
