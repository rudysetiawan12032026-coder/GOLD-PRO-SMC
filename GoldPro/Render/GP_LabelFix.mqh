//+------------------------------------------------------------------+
//|                                                  GP_LabelFix.mqh |
//| GoldPro - LABEL SMC TIDAK BERTUMPUK (10 Okt 2026)                 |
//| Pengguna: "SMC tetap kita pakai, kalau perlu lebih dipresisikan"; |
//| screenshot 8-9 Okt: "Pijakan" + "Bullish OB" bertumpuk, "Bullish  |
//| Breaker *" menimpa label ATAP kotak sideway, CHoCH / BOS dempet.  |
//|                                                                  |
//| Tiap label teks SMC (CreateOrUpdateText, posisi ASAL dicatat      |
//| SMC_LabelHome) dihitung kotaknya dalam piksel (ukuran teks x skala|
//| layar, anchor). Bila menimpa label teks lain di chart (peta       |
//| GoldPro, kotak sideway, PIN, label SMC yang sudah ditempatkan),   |
//| label digeser naik / turun selangkah tinggi teks (maks 4 langkah  |
//| tiap arah), dipilih yang paling dekat posisi asal. Waktu (sumbu X)|
//| tidak diubah. Dihitung ulang dari posisi asal tiap render & tiap  |
//| chart digeser / di-zoom -> geseran tidak menumpuk.                |
//| Hanya TAMPILAN: deteksi SMC (BOS/CHoCH/OB) tidak berubah.         |
//+------------------------------------------------------------------+
#ifndef GP_LABELFIX_MQH
#define GP_LABELFIX_MQH

struct LFBox { int x1; int y1; int x2; int y2; };

double LF_Scale() { long dpi = TerminalInfoInteger(TERMINAL_SCREEN_DPI); return (dpi > 96) ? dpi / 96.0 : 1.0; }

//--- kotak piksel teks objek `name` bila titik jangkarnya di (x, y)
bool LF_Box(string name, int x, int y, LFBox &b)
  {
   string txt = ObjectGetString(0, name, OBJPROP_TEXT);
   if(txt == "" || txt == " ") return false;
   string font = ObjectGetString(0, name, OBJPROP_FONT);
   if(font == "") font = "Arial";
   int fs = (int)ObjectGetInteger(0, name, OBJPROP_FONTSIZE);
   if(fs <= 0) fs = 8;
   uint w = 0, h = 0;
   TextSetFont(font, -10 * fs);
   TextGetSize(txt, w, h);
   int W = (int)MathCeil(w * LF_Scale()) + 2, H = (int)MathCeil(h * LF_Scale());
   int x1, y1;
   switch((ENUM_ANCHOR_POINT)ObjectGetInteger(0, name, OBJPROP_ANCHOR))
     {
      case ANCHOR_LEFT_UPPER:  x1 = x;         y1 = y;         break;
      case ANCHOR_LEFT:        x1 = x;         y1 = y - H / 2; break;
      case ANCHOR_LEFT_LOWER:  x1 = x;         y1 = y - H;     break;
      case ANCHOR_LOWER:       x1 = x - W / 2; y1 = y - H;     break;
      case ANCHOR_RIGHT_LOWER: x1 = x - W;     y1 = y - H;     break;
      case ANCHOR_RIGHT:       x1 = x - W;     y1 = y - H / 2; break;
      case ANCHOR_RIGHT_UPPER: x1 = x - W;     y1 = y;         break;
      case ANCHOR_UPPER:       x1 = x - W / 2; y1 = y;         break;
      default:                 x1 = x - W / 2; y1 = y - H / 2; break;   // ANCHOR_CENTER
     }
   b.x1 = x1; b.y1 = y1; b.x2 = x1 + W; b.y2 = y1 + H;
   b.x1 -= 3; b.x2 += 3; b.y1 -= 2; b.y2 += 2;                 // 14 Okt: jarak aman (screenshot: "Bearish OB" & "Tujuan BSL" bersenggolan)
   return true;
  }
bool LF_Hit(const LFBox &a, const LFBox &b) { return a.x1 < b.x2 && b.x1 < a.x2 && a.y1 < b.y2 && b.y1 < a.y2; }
bool LF_HitAny(const LFBox &a, const LFBox &arr[])
  {
   for(int i = ArraySize(arr) - 1; i >= 0; i--) if(LF_Hit(a, arr[i])) return true;
   return false;
  }
bool LF_Movable(string name)
  {
   for(int i = ArraySize(g_lblName) - 1; i >= 0; i--) if(g_lblName[i] == name) return true;
   return false;
  }
//--- 14 Okt 2026 (screenshot pengguna: label "LIQ PDOL ... SWEPT", "EQL (2x) @ ... SWEPT", "Daily Open" di ujung kiri garis menimpa
//    tombol Target / Cad80 / SMC / Probe / +PIN): area layar milik GoldPro = TERLARANG untuk label SMC - kolom tombol + kotak "i",
//    label LIVE, kartu info, panel halaman, dashboard Kotak / Tembus Balik / Saldo / Berita. Label yang jatuh di situ digeser ke
//    KANAN area itu (waktu diubah, harga tetap; dihitung ulang dari posisi asal tiap kali -> tidak menumpuk). Hanya tampilan.
void LF_AddRect(LFBox &ng[], string obj)
  {
   if(ObjectFind(0, obj) < 0) return;
   int k = ArraySize(ng);
   ArrayResize(ng, k + 1);
   ng[k].x1 = (int)ObjectGetInteger(0, obj, OBJPROP_XDISTANCE) - 2;
   ng[k].y1 = (int)ObjectGetInteger(0, obj, OBJPROP_YDISTANCE) - 2;
   ng[k].x2 = ng[k].x1 + (int)ObjectGetInteger(0, obj, OBJPROP_XSIZE) + 4;
   ng[k].y2 = ng[k].y1 + (int)ObjectGetInteger(0, obj, OBJPROP_YSIZE) + 4;
  }
void LF_NoGo(LFBox &ng[])
  {
   ArrayResize(ng, 0);
   if(DMInpButtons)
     {
      ArrayResize(ng, 1);
      ng[0].x1 = 0; ng[0].y1 = GDM::PanelTop() - 2; ng[0].x2 = GDM::BtnColR() + 4; ng[0].y2 = GDM::BtnColB() + 2;
     }
   LF_AddRect(ng, "GPB_LIVE");
   LF_AddRect(ng, "GPM_IC_bg");
   LF_AddRect(ng, "GPM_Pbg");
   LF_AddRect(ng, "GPK_BG");
   LF_AddRect(ng, "GPI_BG");
   LF_AddRect(ng, "GPD_BG");
   LF_AddRect(ng, "GPN_BG");
  }
//--- kotak b menimpa area terlarang -> geser ke kanan (maks 4 kali, area bisa bersebelahan); kembalikan pergeseran x (piksel)
int LF_PushRight(LFBox &b, const LFBox &ng[], int cw)
  {
   int dx = 0;
   for(int it = 0; it < 4; it++)
     {
      bool moved = false;
      for(int k = ArraySize(ng) - 1; k >= 0; k--)
         if(LF_Hit(b, ng[k]))
           {
            int d = ng[k].x2 + 4 - b.x1;
            b.x1 += d; b.x2 += d; dx += d; moved = true;
           }
      if(!moved || b.x1 > cw) break;
     }
   return dx;
  }

void GP_FixLabels()
  {
   int n = ArraySize(g_lblName);
   if(n == 0) return;
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS), ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   //--- penghalang: semua label teks lain di jendela utama (posisi saat ini)
   LFBox obs[];
   int tot = ObjectsTotal(0, 0, OBJ_TEXT);
   for(int i = 0; i < tot; i++)
     {
      string nm = ObjectName(0, i, 0, OBJ_TEXT);
      if(LF_Movable(nm)) continue;
      int x, y;
      if(!ChartTimePriceToXY(0, 0, (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 0), ObjectGetDouble(0, nm, OBJPROP_PRICE, 0), x, y)) continue;
      if(x < -400 || x > cw + 400 || y < -50 || y > ch + 50) continue;
      LFBox b;
      if(!LF_Box(nm, x, y, b)) continue;
      int k = ArraySize(obs);
      ArrayResize(obs, k + 1);
      obs[k] = b;
     }
   //--- label SMC: label zona (POILBL) dulu, lalu yang lain; yang sudah tidak ada dibuang dari daftar
   int w = 0;
   for(int i = 0; i < n; i++)
      if(ObjectFind(0, g_lblName[i]) >= 0)
        {
         if(w != i) { g_lblName[w] = g_lblName[i]; g_lblT[w] = g_lblT[i]; g_lblP[w] = g_lblP[i]; }
         w++;
        }
   ArrayResize(g_lblName, w); ArrayResize(g_lblT, w); ArrayResize(g_lblP, w);
   LFBox ng[];
   LF_NoGo(ng);                                                // 14 Okt: tombol, kotak "i", panel & dashboard GoldPro
   for(int pass = 0; pass < 2; pass++)
      for(int i = 0; i < w; i++)
        {
         bool poi = (StringFind(g_lblName[i], "POILBL") >= 0);
         if((pass == 0) != poi) continue;
         string nm = g_lblName[i];
         int x, y;
         if(!ChartTimePriceToXY(0, 0, g_lblT[i], g_lblP[i], x, y) || x < -1500 || x > cw || y < 0 || y > ch)
           { ObjectMove(0, nm, 0, g_lblT[i], g_lblP[i]); continue; }
         LFBox b;
         if(!LF_Box(nm, x, y, b)) { ObjectMove(0, nm, 0, g_lblT[i], g_lblP[i]); continue; }
         if(b.x2 < 0) { ObjectMove(0, nm, 0, g_lblT[i], g_lblP[i]); continue; }   // seluruhnya di luar kiri layar
         //--- area terlarang -> geser ke kanan (waktu baru dari piksel x baru)
         datetime tx = g_lblT[i];
         int dx = LF_PushRight(b, ng, cw);
         if(dx != 0)
           {
            int bw = 1 << (int)ChartGetInteger(0, CHART_SCALE);    // waktu dibulatkan ke candle -> tambah 1 lebar candle
            dx += bw; b.x1 += bw; b.x2 += bw;
            int sub;
            datetime tt;
            double pp;
            if(ChartXYToTimePrice(0, x + dx, y, sub, tt, pp) && sub == 0) { tx = tt; x += dx; }
            else { b.x1 -= dx; b.x2 -= dx; }
           }
         int step = (b.y2 - b.y1) + 2, best = 0;
         bool found = !LF_HitAny(b, obs);
         //--- 14 Okt (screenshot: label target 1.272A / 1.618A Peta Gelombang terdorong ~85 px, di bawah Strong Low): label yang
         //    menunjuk HARGA garisnya (Peta Gelombang GPW_) maks 1 langkah; bila tetap bertumpuk, biarkan di garisnya
         int maxK = (StringFind(nm, "GPW_") == 0) ? 1 : 4;
         for(int k = 1; k <= maxK && !found; k++)
            for(int sg = -1; sg <= 1 && !found; sg += 2)       // naik dulu, lalu turun
              {
               LFBox c = b;
               c.y1 += sg * k * step; c.y2 += sg * k * step;
               if(c.y1 < 0 || c.y2 > ch) continue;
               if(!LF_HitAny(c, obs) && !LF_HitAny(c, ng)) { found = true; best = sg * k * step; }
              }
         double p = g_lblP[i];
         if(best != 0)
           {
            int sub;
            datetime tt;
            double pp;
            if(ChartXYToTimePrice(0, x, y + best, sub, tt, pp) && sub == 0) p = pp;
            else best = 0;
           }
         ObjectMove(0, nm, 0, tx, p);
         b.y1 += best; b.y2 += best;
         int k2 = ArraySize(obs);
         ArrayResize(obs, k2 + 1);
         obs[k2] = b;                                          // label yang sudah ditempatkan jadi penghalang berikutnya
        }
  }

#endif // GP_LABELFIX_MQH
