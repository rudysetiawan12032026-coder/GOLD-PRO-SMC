//+------------------------------------------------------------------+
//|                                                      SMC_POI.mqh |
//|                                                                  |
//| Fase 2 - File 6/24 : SMC Pro System                             |
//|                                                                  |
//| TUGAS FILE INI:                                                 |
//|   Mendeteksi dan mengelola siklus hidup semua Point of Interest |
//|   - Order Block, FVG, Breaker Block, Mitigation Block.          |
//|                                                                  |
//| SIMPLIFIKASI YANG SENGAJA DIAMBIL (perlu diuji visual, catat di |
//| jurnal testing sebelum dianggap final):                          |
//|   - OB candidate dicari dengan scan mundur maks 20 bar dari      |
//|     structure event, mencari candle berlawanan arah terakhir     |
//|     sebelum leg impulsif. Ini heuristik umum, bukan pencarian    |
//|     yang menjamin OB "paling optimal" secara matematis.          |
//|   - Mitigation Block dideteksi dari candle displacement kuat     |
//|     yang TIDAK memicu structure event - cakupannya sengaja luas, |
//|     nanti bisa disaring lebih ketat kalau kebanyakan noise.      |
//+------------------------------------------------------------------+
#ifndef SMC_POI_MQH
#define SMC_POI_MQH

#include "..\Core\SMC_Types.mqh"
#include "..\Core\SMC_Config.mqh"
#include "..\Core\SMC_Utils.mqh"
#include "SMC_Structure.mqh"

//======================================================================
// STATE
//======================================================================
OrderBlock g_orderBlocks[];   // menampung OB, Breaker, dan Mitigation Block sekaligus (dibedakan poiType)
FVGZone    g_fvgZones[];
long       g_nextPOIId = 1;

//======================================================================
// INIT
//======================================================================
void SMC_POI_Init()
  {
   ArrayFree(g_orderBlocks);
   ArrayFree(g_fvgZones);
   g_nextPOIId = 1;
  }

//======================================================================
// HELPER: cari OB candidate dengan scan mundur dari structure event
//======================================================================
//----------------------------------------------------------------------
// GoldPro PERBAIKAN DEFINISI OB. SMC lama: candle berlawanan TERBARU dalam 20 bar sebelum BOS yang
// candle berikutnya berbadan >= 60% -> sering candle koreksi kecil di TENGAH leg, bukan asal leg.
// Definisi SMC/ICT: OB = candle berlawanan TERAKHIR di ASAL leg yang mematahkan struktur.
//   BOS bullish : asal leg = LOW terendah antara swing high yang ditembus dan candle BOS;
//                 OB = candle bearish terakhir pada/sebelum low itu (maks 5 candle); zona mencakup low tsb.
//   BOS bearish : cermin (HIGH tertinggi, candle bullish terakhir).
// Karena asal leg adalah ekstrem sampai candle BOS, zona belum tersentuh saat lahir.
//----------------------------------------------------------------------
bool FindOBCandle(ENUM_TIMEFRAMES tf, bool breakoutBullish, const StructureEvent &evt,
                   double &outHigh, double &outLow, datetime &outTime)
  {
   int shiftEvent = iBarShift(_Symbol, tf, evt.time);
   if(shiftEvent < 0)
      return false;

   SwingPoint sw;
   int shiftSwing = -1;
   if(GetExternalSwingById(evt.swingId, sw))
      shiftSwing = iBarShift(_Symbol, tf, sw.time);
   if(shiftSwing <= shiftEvent)
      shiftSwing = shiftEvent + 20;                 // swing sudah terbuang dari memori: jendela 20 bar
   shiftSwing = MathMin(shiftSwing, shiftEvent + 300);

   int origin = shiftEvent + 1;
   for(int s = shiftEvent + 1; s <= shiftSwing; s++)
     {
      if(breakoutBullish ? (iLow(_Symbol, tf, s) < iLow(_Symbol, tf, origin))
                         : (iHigh(_Symbol, tf, s) > iHigh(_Symbol, tf, origin)))
         origin = s;
     }
   for(int s = origin; s <= origin + 5; s++)
     {
      bool candleBullish = IsBullishCandle(s, tf);
      if(breakoutBullish ? candleBullish : !candleBullish)
         continue;                                   // OB bullish = candle BEARISH, OB bearish = candle BULLISH
      outHigh = iHigh(_Symbol, tf, s);
      outLow  = iLow(_Symbol, tf, s);
      outTime = iTime(_Symbol, tf, s);
      if(breakoutBullish) outLow  = MathMin(outLow,  iLow(_Symbol, tf, origin));
      else                outHigh = MathMax(outHigh, iHigh(_Symbol, tf, origin));
      return true;
     }
   return false;
  }

//======================================================================
// HELPER: cek apakah ada FVG (arah sama) terbentuk di window waktu
// antara OB candle dan structure event - dipakai untuk set hasFVG.
//======================================================================
bool HasFVGInWindow(bool isBullish, datetime fromTime, datetime toTime)
  {
   for(int i = 0; i < ArraySize(g_fvgZones); i++)
     {
      if(g_fvgZones[i].isBullish != isBullish)
         continue;
      if(g_fvgZones[i].time >= fromTime && g_fvgZones[i].time <= toTime)
         return true;
     }
   return false;
  }

//======================================================================
// DETEKSI ORDER BLOCK - dipicu oleh structure event tertentu (biasa:
// event TERAKHIR untuk kasus live; saat backfill, dipanggil untuk
// SETIAP event historis satu per satu).
//======================================================================
void DetectOrderBlockFromEvent(ENUM_TIMEFRAMES tf, StructureEvent &evt)
  {
   bool breakoutBullish = (evt.direction == BIAS_BULLISH);
   double obHigh, obLow;
   datetime obTime;

   if(!FindOBCandle(tf, breakoutBullish, evt, obHigh, obLow, obTime))
      return; // tidak ketemu candidate valid dalam window scan

   // Cek duplikat berdasarkan waktu CANDLE OB itu sendiri (obTime), BUKAN
   // waktu structure event - karena banyak event yang berdekatan/dari leg
   // yang sama seringkali mengarah ke CANDLE OB YANG SAMA PERSIS. Cek
   // dengan waktu event lama salah total, itu sebabnya OB yang sama bisa
   // tercatat berkali-kali (bug yang baru ditemukan dari testing).
   for(int i = 0; i < ArraySize(g_orderBlocks); i++)
      if(g_orderBlocks[i].poiType == POI_ORDER_BLOCK && g_orderBlocks[i].time == obTime
         && g_orderBlocks[i].isBullish == breakoutBullish)
         return;

   bool hasFVG = HasFVGInWindow(breakoutBullish, obTime, evt.time);

   int n = ArraySize(g_orderBlocks);
   ArrayResize(g_orderBlocks, n + 1);
   g_orderBlocks[n].id         = g_nextPOIId++;
   g_orderBlocks[n].time       = obTime;
   g_orderBlocks[n].high       = NormalizePriceForSymbol(obHigh);
   g_orderBlocks[n].low        = NormalizePriceForSymbol(obLow);
   g_orderBlocks[n].isBullish  = breakoutBullish;
   g_orderBlocks[n].poiType    = POI_ORDER_BLOCK;
   g_orderBlocks[n].hasFVG     = hasFVG;
   g_orderBlocks[n].status     = ZONE_FRESH;
   g_orderBlocks[n].ceLevel    = (obHigh + obLow) / 2.0;
   g_orderBlocks[n].touchCount = 0;
   g_orderBlocks[n].sourceTF   = tf;
   g_orderBlocks[n].isConfluent = false; // diisi SMC_MTF.mqh nanti
   g_orderBlocks[n].bornTime   = evt.time;

   if(ArraySize(g_orderBlocks) > InpMaxPOIHistory * 3) // *3 karena array ini gabung OB+Breaker+Mitigation
      ArrayRemove(g_orderBlocks, 0, 1);
  }

// Wrapper untuk kasus LIVE (bar baru) - selalu pakai event TERAKHIR.
void DetectOrderBlockFromLastEvent(ENUM_TIMEFRAMES tf)
  {
   StructureEvent evt;
   if(!GetLastStructureEvent(evt))
      return;
   DetectOrderBlockFromEvent(tf, evt);
  }

//======================================================================
// DETEKSI FVG - dicek tiap bar baru, 3-candle gap klasik.
// Parameter `shift` defaultnya 1 (kasus live) - untuk BACKFILL, dipanggil
// berulang dengan shift menurun dari lama ke baru.
//======================================================================
void DetectFVG(ENUM_TIMEFRAMES tf, int shift = 1)
  {
   // shift+2 = candle tertua (candle 1), shift = candle terbaru (candle 3)
   double atr = GetATR(tf, 14, shift);
   double minSize = atr * InpFVGMinSizeATR;
   if(minSize <= 0)
      return;

   double highOld = iHigh(_Symbol, tf, shift + 2);
   double lowOld  = iLow(_Symbol, tf, shift + 2);
   double highNew = iHigh(_Symbol, tf, shift);
   double lowNew  = iLow(_Symbol, tf, shift);

   bool isBullish;
   double top, bottom;

   if(lowNew > highOld && (lowNew - highOld) >= minSize)
     {
      isBullish = true;
      bottom    = highOld;
      top       = lowNew;
     }
   else if(highNew < lowOld && (lowOld - highNew) >= minSize)
     {
      isBullish = false;
      bottom    = highNew;
      top       = lowOld;
     }
   else
      return; // tidak ada gap signifikan

   int n = ArraySize(g_fvgZones);

   // Hindari duplikat saat backfill memproses ulang window yang sama.
   datetime midTimeCandidate = iTime(_Symbol, tf, shift + 1);
   for(int i = 0; i < n; i++)
      if(g_fvgZones[i].time == midTimeCandidate && g_fvgZones[i].isBullish == isBullish)
         return;

   ArrayResize(g_fvgZones, n + 1);
   g_fvgZones[n].id          = g_nextPOIId++;
   g_fvgZones[n].time        = midTimeCandidate; // waktu candle impulsif (tengah)
   g_fvgZones[n].top         = NormalizePriceForSymbol(top);
   g_fvgZones[n].bottom      = NormalizePriceForSymbol(bottom);
   g_fvgZones[n].isBullish   = isBullish;
   g_fvgZones[n].status      = ZONE_FRESH;
   g_fvgZones[n].fillPercent = 0.0;
   g_fvgZones[n].ceLevel     = (top + bottom) / 2.0;
   g_fvgZones[n].sourceTF    = tf;
   g_fvgZones[n].bornTime    = iTime(_Symbol, tf, shift);

   if(ArraySize(g_fvgZones) > InpMaxPOIHistory)
      ArrayRemove(g_fvgZones, 0, 1);
  }

//======================================================================
// DETEKSI MITIGATION BLOCK - displacement candle yang TIDAK memicu
// structure event (opsional, toggle InpDetectMitigationBlk, default mati)
//======================================================================
void DetectMitigationBlock(ENUM_TIMEFRAMES tf, bool structureEventOccurred)
  {
   if(!InpDetectMitigationBlk || structureEventOccurred)
      return; // kalau event terjadi, itu domainnya OB resmi, bukan Mitigation Block

   double disp = GetBodyToRangeRatio(1, tf);
   if(disp < InpOBDisplacementMinBody)
      return;

   bool impulseBullish = IsBullishCandle(1, tf);
   bool candidateColor = IsBullishCandle(2, tf); // candle sebelum leg impulsif

   if(candidateColor == impulseBullish)
      return; // bukan pola OB-like (candle sebelum leg harus berlawanan warna)

   double mbHigh = iHigh(_Symbol, tf, 2);
   double mbLow  = iLow(_Symbol, tf, 2);
   datetime mbTime = iTime(_Symbol, tf, 2);

   // Hindari duplikat untuk waktu yang sama
   for(int i = 0; i < ArraySize(g_orderBlocks); i++)
      if(g_orderBlocks[i].poiType == POI_MITIGATION && g_orderBlocks[i].time == mbTime)
         return;

   int n = ArraySize(g_orderBlocks);
   ArrayResize(g_orderBlocks, n + 1);
   g_orderBlocks[n].id         = g_nextPOIId++;
   g_orderBlocks[n].time       = mbTime;
   g_orderBlocks[n].high       = NormalizePriceForSymbol(mbHigh);
   g_orderBlocks[n].low        = NormalizePriceForSymbol(mbLow);
   g_orderBlocks[n].isBullish  = impulseBullish;
   g_orderBlocks[n].poiType    = POI_MITIGATION;
   g_orderBlocks[n].hasFVG     = false;
   g_orderBlocks[n].status     = ZONE_FRESH;
   g_orderBlocks[n].ceLevel    = (mbHigh + mbLow) / 2.0;
   g_orderBlocks[n].touchCount = 0;
   g_orderBlocks[n].sourceTF   = tf;
   g_orderBlocks[n].isConfluent = false;
   g_orderBlocks[n].bornTime   = iTime(_Symbol, tf, 1);
   if(ArraySize(g_orderBlocks) > InpMaxPOIHistory * 3)
      ArrayRemove(g_orderBlocks, 0, 1);
  }

//======================================================================
// UPDATE SIKLUS HIDUP - dijalankan tiap bar baru untuk semua OB/FVG aktif
//======================================================================
//----------------------------------------------------------------------
// GoldPro PERBAIKAN: (1) dulu hanya candle shift 1 yang dicek, juga saat BACKFILL -> setelah indikator
// dipasang ulang / ganti TF / compile, 68% OB yang tampil "belum termitigasi" sebenarnya sudah
// termitigasi dan "Pijakan" menunjuk zona yang sudah ditembus habis 67% waktu (audit M5 30 hari).
// Sekarang dihitung per candle (`shift`) dan backfill me-replay candle demi candle.
// (2) Candle BOS sendiri tidak lagi dihitung sebagai mitigasi (hanya candle SESUDAH bornTime).
// (3) Breaker / zona non-OB yang sudah termitigasi lalu DITUTUP tembus -> INVALIDATED (dulu abadi).
//----------------------------------------------------------------------
void UpdateZoneLifecycle(ENUM_TIMEFRAMES tf, int shift = 1)
  {
   datetime barTime  = iTime(_Symbol, tf, shift);
   double   barHigh  = iHigh(_Symbol, tf, shift);
   double   barLow   = iLow(_Symbol, tf, shift);
   double   barClose = iClose(_Symbol, tf, shift);

   // --- Order Block / Breaker / Mitigation ---
   for(int i = 0; i < ArraySize(g_orderBlocks); i++)
     {
      if(g_orderBlocks[i].status == ZONE_INVALIDATED)
         continue;
      if(barTime <= g_orderBlocks[i].bornTime)
         continue;

      double top    = g_orderBlocks[i].high;
      double bottom = g_orderBlocks[i].low;
      double height = top - bottom;
      if(height <= 0)
         continue;

      bool touchedThisBar = (barLow <= top && barHigh >= bottom);
      if(touchedThisBar)
         g_orderBlocks[i].touchCount++;

      // Penetrasi diukur dari sisi harga datang. OB bullish (support) di-
      // dekati dari atas (harga turun ke zona) -> penetrasi dari top ke bawah.
      // OB bearish (resistance) didekati dari bawah -> penetrasi dari bottom ke atas.
      double penetration = 0.0;
      if(g_orderBlocks[i].isBullish)
        {
         if(barLow < top)
            penetration = MathMin(top - barLow, height);
        }
      else
        {
         if(barHigh > bottom)
            penetration = MathMin(barHigh - bottom, height);
        }

      double fillPct = (penetration / height) * 100.0;

      if(fillPct >= InpZoneMitigatedPercent && g_orderBlocks[i].status != ZONE_MITIGATED)
        {
         g_orderBlocks[i].status = ZONE_MITIGATED;
        }
      else if(fillPct > 0 && g_orderBlocks[i].status == ZONE_FRESH)
        {
         g_orderBlocks[i].status = ZONE_PARTIAL;
        }

      // --- Breaker Block conversion ---
      // OB yang sudah MITIGATED, lalu ditembus PENUH (body close) ke arah
      // berlawanan -> berubah fungsi jadi Breaker.
      if(g_orderBlocks[i].status == ZONE_MITIGATED)
        {
         bool brokenThrough = g_orderBlocks[i].isBullish ? (barClose < bottom) : (barClose > top);
         if(brokenThrough)
           {
            if(InpDetectBreakerBlock && g_orderBlocks[i].poiType == POI_ORDER_BLOCK)
              {
               g_orderBlocks[i].poiType    = POI_BREAKER;
               g_orderBlocks[i].isBullish  = !g_orderBlocks[i].isBullish; // fungsi terbalik
               g_orderBlocks[i].status     = ZONE_FRESH;
               g_orderBlocks[i].touchCount = 0;
               g_orderBlocks[i].bornTime   = barTime;                     // breaker lahir di candle ini
              }
            else
               g_orderBlocks[i].status = ZONE_INVALIDATED;                // breaker/zona lain gagal -> tidak berlaku
           }
        }
     }

   // --- FVG ---
   for(int i = 0; i < ArraySize(g_fvgZones); i++)
     {
      if(g_fvgZones[i].status == ZONE_INVALIDATED)
         continue;
      if(barTime <= g_fvgZones[i].bornTime)
         continue;

      double top    = g_fvgZones[i].top;
      double bottom = g_fvgZones[i].bottom;
      double height = top - bottom;
      if(height <= 0)
         continue;

      double penetration = 0.0;
      if(g_fvgZones[i].isBullish)
        {
         if(barLow < top)
            penetration = MathMin(top - barLow, height);
        }
      else
        {
         if(barHigh > bottom)
            penetration = MathMin(barHigh - bottom, height);
        }

      double fillPct = (penetration / height) * 100.0;
      if(fillPct > g_fvgZones[i].fillPercent)
         g_fvgZones[i].fillPercent = fillPct;

      if(g_fvgZones[i].fillPercent >= InpZoneMitigatedPercent)
         g_fvgZones[i].status = ZONE_MITIGATED;
      else if(g_fvgZones[i].fillPercent > 0)
         g_fvgZones[i].status = ZONE_PARTIAL;
     }
  }

//======================================================================
// FUNGSI UTAMA
//======================================================================
void SMC_POI_Update(ENUM_TIMEFRAMES tf, bool isNewBar, bool structureEventOccurred)
  {
   if(!isNewBar)
      return;

   DetectFVG(tf, 1);

   if(structureEventOccurred)
      DetectOrderBlockFromLastEvent(tf);
   else
      DetectMitigationBlock(tf, structureEventOccurred);

   UpdateZoneLifecycle(tf, 1);
  }

//======================================================================
// BACKFILL - dipanggil SEKALI dari OnInit(), SETELAH SMC_Structure_Backfill().
// GoldPro PERBAIKAN: REPLAY candle demi candle (lama -> baru), sama persis dengan jalur live:
// di tiap candle -> deteksi FVG, OB dari BOS/CHoCH yang terjadi di candle itu, lalu siklus hidup
// semua zona dengan candle itu. Dulu: semua zona dibuat dulu, siklus hidup dicek SEKALI dengan
// candle terakhir saja -> zona yang sudah dilewati harga tampil "segar".
//======================================================================
void SMC_POI_Backfill(ENUM_TIMEFRAMES tf, int scanBars)
  {
   int eventCount = GetStructureEventCount();
   for(int shift = scanBars; shift >= 1; shift--)
     {
      DetectFVG(tf, shift);
      datetime bt = iTime(_Symbol, tf, shift);
      for(int i = 0; i < eventCount; i++)
        {
         StructureEvent evt;
         if(GetStructureEvent(i, evt) && evt.time == bt)
            DetectOrderBlockFromEvent(tf, evt);
        }
      UpdateZoneLifecycle(tf, shift);
     }
   PrintFormat("[SMC_POI] Backfill (replay) selesai: %d OB/Breaker, %d FVG.", GetOBCount(), GetFVGCount());
  }

//======================================================================
// ACCESSOR
//======================================================================
int GetOBCount() { return ArraySize(g_orderBlocks); }
bool GetOB(int index, OrderBlock &outOB)
  {
   if(index < 0 || index >= ArraySize(g_orderBlocks))
      return false;
   outOB = g_orderBlocks[index];
   return true;
  }

int GetFVGCount() { return ArraySize(g_fvgZones); }
bool GetFVG(int index, FVGZone &outFVG)
  {
   if(index < 0 || index >= ArraySize(g_fvgZones))
      return false;
   outFVG = g_fvgZones[index];
   return true;
  }

// Cari OB/Breaker belum-termitigasi terdekat dari harga saat ini, searah bias.
// GoldPro: `correctSide` = zona bullish (support) harus di BAWAH/menyentuh harga, bearish di ATAS -
// dipakai untuk "Pijakan"/retest (6% Pijakan dulu berada di sisi yang salah).
bool GetNearestUnmitigatedOB(bool wantBullish, double referencePrice, OrderBlock &outOB, bool correctSide = false)
  {
   bool  found     = false;
   double bestDist = DBL_MAX;

   for(int i = 0; i < ArraySize(g_orderBlocks); i++)
     {
      if(g_orderBlocks[i].isBullish != wantBullish)
         continue;
      if(g_orderBlocks[i].status == ZONE_MITIGATED || g_orderBlocks[i].status == ZONE_INVALIDATED)
         continue;
      if(correctSide && (wantBullish ? g_orderBlocks[i].low > referencePrice : g_orderBlocks[i].high < referencePrice))
         continue;

      double mid  = g_orderBlocks[i].ceLevel;
      double dist = MathAbs(referencePrice - mid);
      if(dist < bestDist)
        {
         bestDist = dist;
         outOB    = g_orderBlocks[i];
         found    = true;
        }
     }
   return found;
  }

// GoldPro: nama jenis zona yang SEBENARNYA (dulu label Pijakan selalu "OB" walau zonanya Breaker).
string POITypeText(const OrderBlock &ob)
  {
   string side = ob.isBullish ? "Bullish " : "Bearish ";
   if(ob.poiType == POI_BREAKER)    return side + "Breaker";
   if(ob.poiType == POI_MITIGATION) return "Mitigation Block";
   return side + "OB";
  }

// Setter khusus dipakai SMC_MTF.mqh untuk menandai LTF OB yang overlap
// dengan zona HTF/MTF (nested/confluence POI).
bool SetOBConfluent(int index, bool value)
  {
   if(index < 0 || index >= ArraySize(g_orderBlocks))
      return false;
   g_orderBlocks[index].isConfluent = value;
   return true;
  }

// CalcOBScore() - Fase 5 (adopsi xxvw/SMC_ICT_Library). Skor kualitas
// SATU OrderBlock berdiri sendiri - beda dari ScorePOIQuality() di
// SMC_Scoring.mqh yang menilai OB TERDEKAT dari harga sebagai bagian
// confluence score keseluruhan. Fungsi ini untuk MEMBANDINGKAN
// beberapa OB satu sama lain (dashboard/debugging/EA companion nanti),
// bukan menggantikan ScorePOIQuality().
double CalcOBScore(const OrderBlock &ob)
  {
   double score = 0.0;

   // Kesegaran (status)
   if(ob.status == ZONE_FRESH)        score += 30.0;
   else if(ob.status == ZONE_PARTIAL) score += 15.0;
   else if(ob.status == ZONE_TESTED)  score += 10.0;
   // MITIGATED/BROKEN/INVALIDATED -> 0 dari komponen ini

   // FVG pendukung & confluence lintas-TF
   if(ob.hasFVG)      score += 20.0;
   if(ob.isConfluent) score += 20.0;

   // BARU (permintaan eksplisit - "entry presisi", bedah karakter
   // candle OB itu sendiri): badan KECIL dibanding rentang candle =
   // penolakan kuat (institusi "diserap" di situ, harga ditolak
   // balik) - bukan cuma candle biasa yang kebetulan searah. Pakai
   // ulang GetBodyToRangeRatio() yang sudah ada (sebelumnya cuma
   // dipakai untuk candle KONFIRMASI, sekarang juga untuk OB itu sendiri).
   int obShift = iBarShift(_Symbol, ob.sourceTF, ob.time);
   if(obShift >= 0)
     {
      double bodyRatio  = GetBodyToRangeRatio(obShift, ob.sourceTF);
      double rejection  = 1.0 - bodyRatio; // 0=badan penuh (tanpa wick), 1=badan nyaris nol (wick dominan)
      score += rejection * 20.0;
     }

   // Usia - OB yang lebih baru lebih relevan (pakai sourceTF milik OB
   // itu sendiri, bukan asumsi PERIOD_CURRENT).
   int barsAgo = iBarShift(_Symbol, ob.sourceTF, ob.time);
   if(barsAgo >= 0)
     {
      if(barsAgo <= 10)      score += 20.0;
      else if(barsAgo <= 30) score += 10.0;
     }

   return MathMin(score, 100.0);
  }

// GetBestQualityOB() - BARU (permintaan eksplisit - "entry presisi,
// jangan asal comot"): GetNearestUnmitigatedOB() di atas cuma pilih OB
// TERDEKAT secara jarak - mengabaikan CalcOBScore() yang sudah ada
// tapi TIDAK PERNAH dipakai untuk seleksi entry (cuma nganggur untuk
// dashboard/debugging). Fungsi ini pilih OB dengan SKOR TERTINGGI di
// antara kandidat dalam jangkauan wajar (maxDistanceATR x ATR dari
// harga) - bukan cuma yang paling dekat secara geometris.
// GetNearestQualifiedOB() - REVISI dari GetBestQualityOB (v5 terbukti
// lebih buruk: PF 1.53->1.40, kemungkinan karena memilih OB "bagus di
// atas kertas" tapi terlalu jauh dari aksi harga saat ini). Pendekatan
// lebih konservatif: TETAP OB TERDEKAT seperti semula, TAPI cuma
// kandidat yang lolos skor kualitas MINIMUM - membuang yang jelas
// lemah, tanpa mengorbankan relevansi jarak seperti v5.
bool GetNearestQualifiedOB(bool wantBullish, double referencePrice, OrderBlock &outOB, double minScore = 40.0)
  {
   bool   found    = false;
   double bestDist = DBL_MAX;

   for(int i = 0; i < ArraySize(g_orderBlocks); i++)
     {
      if(g_orderBlocks[i].isBullish != wantBullish)
         continue;
      if(g_orderBlocks[i].status == ZONE_MITIGATED || g_orderBlocks[i].status == ZONE_INVALIDATED)
         continue;
      if(CalcOBScore(g_orderBlocks[i]) < minScore)
         continue; // buang yang jelas lemah - baru di antara sisanya, pilih TERDEKAT

      double dist = MathAbs(referencePrice - g_orderBlocks[i].ceLevel);
      if(dist < bestDist)
        {
         bestDist = dist;
         outOB    = g_orderBlocks[i];
         found    = true;
        }
     }
   return found;
  }

bool GetBestQualityOB(bool wantBullish, double referencePrice, OrderBlock &outOB, double maxDistanceATR = 3.0)
  {
   double atr     = GetATR(PERIOD_CURRENT, 14, 1);
   double maxDist = (atr > 0) ? atr * maxDistanceATR : DBL_MAX;

   bool   found     = false;
   double bestScore = -1.0;

   for(int i = 0; i < ArraySize(g_orderBlocks); i++)
     {
      if(g_orderBlocks[i].isBullish != wantBullish)
         continue;
      if(g_orderBlocks[i].status == ZONE_MITIGATED || g_orderBlocks[i].status == ZONE_INVALIDATED)
         continue;

      double dist = MathAbs(referencePrice - g_orderBlocks[i].ceLevel);
      if(dist > maxDist)
         continue; // terlalu jauh dari harga sekarang - bukan kandidat realistis untuk entry

      double score = CalcOBScore(g_orderBlocks[i]);
      if(score > bestScore)
        {
         bestScore = score;
         outOB     = g_orderBlocks[i];
         found     = true;
        }
     }
   return found;
  }

// GetStopLossForBuy/Sell() - Fase 5. SL di luar OB + buffer - murni
// fungsi hitung, TIDAK menempatkan order apapun (dipakai Signal
// Export/EA companion/backtest).
//   FIX (bug ditemukan lewat backtest 3 bulan - 41% trade mati dalam
//   <=10 detik, 99% di antaranya langsung rugi): buffer dulu pakai
//   "pip tetap" (InpSLBufferPips x GetPipSize()) - untuk XAUUSD (2
//   digit desimal di broker ini), itu menghasilkan buffer cuma 5 SEN
//   (5.0 x 0.01) - jauh di bawah spread/noise normal gold yang bisa
//   berdolar-dolar. Diganti jadi kelipatan ATR - otomatis menyesuaikan
//   ke volatilitas instrumen APAPUN, bukan angka statis yang salah unit
//   untuk gold.
double GetStopLossForBuy(const OrderBlock &ob)
  {
   double atr = GetATR(PERIOD_CURRENT, 14, 1);
   double buffer = (atr > 0) ? InpSLBufferATRMultiplier * atr : 0.0;
   return ob.low - buffer;
  }

double GetStopLossForSell(const OrderBlock &ob)
  {
   double atr = GetATR(PERIOD_CURRENT, 14, 1);
   double buffer = (atr > 0) ? InpSLBufferATRMultiplier * atr : 0.0;
   return ob.high + buffer;
  }

#endif // SMC_POI_MQH