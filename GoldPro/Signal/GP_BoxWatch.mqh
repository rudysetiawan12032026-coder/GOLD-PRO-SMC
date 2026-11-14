//+------------------------------------------------------------------+
//|                                                  GP_BoxWatch.mqh |
//| GoldPro - KOTAK SIDEWAY (tombol "Kotak Sideway", 8 Okt 2026)      |
//| Permintaan pengguna: tombol khusus mengawasi kotak konsolidasi,   |
//| narasi jelas & mudah dipahami: dinding mana yang akan ditembus,    |
//| candle colek berekor, inside bar, berapa lama bertahan di luar.    |
//|                                                                  |
//| Kotak = DEFINISI RISET (sama persis): rentang 60 candle M1 <=      |
//| ambang P20 per slot 30 mnt jam NY (CS_P20_60, x ADR), dan 60 mnt   |
//| sebelumnya tidak ada kotak. ATAP/LANTAI = high/low 60 mnt itu,     |
//| DIBEKUKAN saat kotak lahir (dinding sebelum dicolek). Bisa beda    |
//| dari kotak abu "sideway x mnt" peta (yang ikut bergerak).          |
//| Angka dari riset 2017-2026, stabil latih 2017-21 & uji 2022-26:    |
//|  consol_edge.py : posisi harga di kotak -> keluar atap/lantai     |
//|  consol_poke.py : colek -> dinding SAMA tembus M1 85% / M5 77%,   |
//|                   dikocok median 4 / 8 mnt; + inside bar 83 / 72%, |
//|                   tanpa inside bar 78 / 60%                        |
//|  consol_hours.py: dorongan tembus median ~0.26 lebar kotak, 74%    |
//|                   close balik ke dalam <= 15 mnt; per jam WITA     |
//|  consol_lines.py: bertahan di luar median 3 mnt, > 15 mnt 25%,     |
//|                   > 60 mnt 13%                                     |
//|  consol_78.py   : BOS/CHoCH M5 searah tembusan 78% (~4 mnt), tapi  |
//|                   TIDAK menguatkan tembusan (lanjut 44% = wajar)   |
//|  consol_frozen.py (screenshot 8 Okt: kotak tembus lalu kembali ->  |
//|                   dashboard "tidak ada kotak"): dinding BEKU tetap |
//|                   berlaku s/d 240 mnt - tabel posisi sesudah 1 / 2+ |
//|                   tembusan gagal selisih 1-2 poin; tembusan ke-2/3 |
//|                   bertahan sama; colek sesudah tembusan M1 85% /   |
//|                   M5 74%. -> kotak HIDUP s/d 240 mnt walau pernah  |
//|                   ditembus, selesai bila 60 mnt di luar; sesudah    |
//|                   selesai & 60 mnt masih sempit -> DIPERBARUI.      |
//| INFO perilaku harga - arah tembus tetap ~50:50 dari tren mana pun.|
//+------------------------------------------------------------------+
#ifndef GP_BOXWATCH_MQH
#define GP_BOXWATCH_MQH
//--- 11 Okt 2026: tombol "Tembus Balik" (Signal\GP_TembusBalik.mqh, dimuat sesudah file ini) memakai kejadian TEMBUS mesin ini
void TB_Break(const MqlRates &r[], int i, int side, double hi, double lo);
void TB_Bar(datetime t, double h, double l, double c);
void TB_Reset();

input group "=== GoldPro: Kotak Sideway (tombol Kotak Sideway) ==="
input bool InpKBDrawLines = true;    // Gambar garis ATAP & LANTAI kotak yang diawasi
input int  InpKBFont      = 8;       // Ukuran huruf dashboard
input bool InpKBTelegram  = true;    // Tulis kejadian live untuk EA Telegram (Experts\GoldPro\GoldPro_Telegram)

#define KB_PFX   "GPK_"
#define KB_MAXEV 30
#define KB_MAXCH 62                  // OBJ_LABEL MT5 hanya menampilkan 63 karakter

//--- tabel riset
double KB_CEX[10]  = {0.125, 0.206, 0.288, 0.371, 0.459, 0.531, 0.616, 0.702, 0.785, 0.879};   // keluar ATAS per desil posisi
int    KB_CMED[10] = {4, 10, 15, 18, 20, 20, 18, 15, 10, 4};                                  // menit sampai keluar (median)
int    KB_CP75[10] = {15, 25, 32, 36, 37, 38, 35, 33, 26, 14};                                // 3 dari 4 keluar dalam (mnt)
int    KB_QUIET[24] = {9, 17, 26, 34, 47, 52, 58, 62, 41, 17, 25, 43, 61, 50, 21, 14, 13, 21, 27, 23, 11, 3, 1, 3};   // % waktu sepi / jam WITA
double KB_OVW[24]   = {0.21, 0.22, 0.21, 0.21, 0.23, 0.22, 0.27, 0.25, 0.29, 0.32, 0.21, 0.22, 0.26, 0.35, 0.29, 0.29,
                       0.28, 0.24, 0.27, 0.26, 0.29, 0.29, 0.23, 0.21};                                         // dorongan tembus (x lebar)

//--- kind: 0 biasa, 1 tembus-sebentar-kembali (gabungan), 2 tembus (menunggu), 3 colek (gabungan)
struct KBEvent { datetime t; string txt; color c; int kind; int side; int tf; int cnt; int nb0; int nb1; int mins; double mx; datetime t1;
                 int c1; int c5; };                                        // c1/c5 = jumlah colek M1/M5 dalam cerita colek gabungan
KBEvent  g_kbEv[];
int      g_kbSt = 0;                       // 0 tidak ada kotak, 1 kotak hidup & harga di dalam, 2 kotak hidup & harga di luar (tembus)
double   g_kbHi = 0, g_kbLo = 0;
datetime g_kbT0 = 0, g_kbStart = 0;        // awal 60 mnt kotak / candle saat kotak lahir
datetime g_kbLastBar = 0, g_kbLastCons = 0;
int      g_kbNBrk = 0;                     // jumlah tembusan kotak ini (yang gagal + yang sedang berjalan)
bool     g_kbFresh = false;                // kotak = episode riset (60 mnt sebelumnya tanpa kotak); false = diperbarui
int      g_kbPkSide[2] = {0, 0};           // colek terakhir M1 [0] / M5 [1] yang menunggu cek inside bar (1 atap, -1 lantai)
double   g_kbPkH[2], g_kbPkL[2];
int      g_kbLastPkSide = 0, g_kbLastPkTF = 0, g_kbLastPkIB = -1;   // IB: -1 belum ada candle berikut, 1 inside, 0 tidak
datetime g_kbLastPkT = 0;
double   g_kbLastPkWick = 0;
int      g_kbBrkSide = 0, g_kbBrkHr = 0;
datetime g_kbBrkT = 0, g_kbBackT = 0;
double   g_kbMaxOut = 0;
bool     g_kbBack = false, g_kbHold15 = false, g_kbStory = false, g_kbRaise = false, g_kbLive = false;   // g_kbStory: klik judul = cerita
uint     g_kbRaiseTick = 0;
string   g_kbL[], g_kbT[];
color    g_kbC[];
//--- ALARM KALIBRASI (rencana pengerasan no. 4-5): [0 pecah5, 1 kembali5, 2 sungguhan60, 3 colek, 4 mepet, 5 kembali, 6 lanjut garis]
int      g_kbAl[7]  = {0, 0, 0, 0, 0, 0, 0};          // 1 = angka itu meleset di uji maju 7 hari terakhir -> disembunyikan
int      g_kbAlN[7] = {0, 0, 0, 0, 0, 0, 0};
double   g_kbAlE[7], g_kbAlY[7], g_kbAlZ[7];
bool     g_kbAlRun = false;                           // sudah dihitung sekali (dari CSV)
string KB_AlNote(int a) { return (a >= 0 && a < 7 && g_kbAl[a] == 1) ? " [angka sedang dicek: meleset 7 hari terakhir]" : ""; }

string KB_Px(double p) { return DoubleToString(p, _Digits); }   // 2 desimal (8 Okt: atap 4130.45 tampil "4130.4", close 4129.04 vs pemicu 4129.18)
string KB_Rng() { return KB_Px(g_kbLo) + " - " + KB_Px(g_kbHi); }
int    KB_Pct(double p) { return (int)MathRound(100.0 * p); }
int    KB_HourWITA(datetime server)
  {
   MqlDateTime d;
   TimeToStruct(GP_UTCToLocal(GP_ServerToUTC(server)), d);
   return d.hour;
  }
string KB_Wall(int side) { return side > 0 ? "ATAP" : "LANTAI"; }
string KB_wall(int side) { return side > 0 ? "atap" : "lantai"; }
//--- peluang dinding yang SAMA ditembus sesudah colek: kotak baru belum pernah ditembus = consol_poke.py (+ inside bar);
//    sesudah tembusan gagal / kotak diperbarui = consol_frozen.py bagian 3 (inside bar tidak diuji di sana)
bool KB_PokeFirst() { return g_kbFresh && g_kbNBrk == 0; }
int KB_PokeSame(int tf, int ib)
  {
   if(!KB_PokeFirst()) return (tf == 1) ? 85 : 74;
   if(tf == 1) return (ib == 1) ? 83 : (ib == 0 ? 78 : 85);
   return (ib == 1) ? 72 : (ib == 0 ? 60 : 77);
  }

int KB_Event(datetime t, string txt, color c, int kind = 0, int side = 0)
  {
   int n = ArraySize(g_kbEv);
   if(n >= KB_MAXEV) { for(int i = 1; i < n; i++) g_kbEv[i - 1] = g_kbEv[i]; n--; ArrayResize(g_kbEv, n); }
   ArrayResize(g_kbEv, n + 1);
   g_kbEv[n].t = t; g_kbEv[n].txt = txt; g_kbEv[n].c = c; g_kbEv[n].kind = kind; g_kbEv[n].side = side;
   g_kbEv[n].tf = 0; g_kbEv[n].cnt = 1; g_kbEv[n].nb0 = 0; g_kbEv[n].nb1 = 0; g_kbEv[n].mins = 0; g_kbEv[n].mx = 0; g_kbEv[n].t1 = t;
   g_kbEv[n].c1 = 0; g_kbEv[n].c5 = 0;
   return n;
  }
//--- tembusan yang cepat kembali (<= 5 mnt): gabung dengan cerita TEMBUS-nya, dan dengan gabungan sebelumnya di sisi sama (<= 15 mnt)
//    -> cerita tidak dibanjiri "tembus 1 mnt lalu kembali" (screenshot 8 Okt: 7 tembusan 1 mnt di satu kotak)
string KB_QuickTxt(const KBEvent &e)
  {
   if(e.cnt == 1)
      return StringFormat("TEMBUS %s%s sebentar: %d mnt di luar (lewat $%.2f) lalu KEMBALI - gagal, kotak masih berlaku.",
                          e.side > 0 ? "ATAS" : "BAWAH", e.nb0 > 1 ? StringFormat(" ke-%d", e.nb0) : "", e.mins, e.mx);
   return StringFormat("TEMBUS %s sebentar %dx (ke-%d s/d ke-%d, terakhir %s): tiap kali close kembali ke dalam <= %d mnt, lewat maks "
                       "$%.2f. Kotak masih berlaku.", e.side > 0 ? "ATAS" : "BAWAH", e.cnt, e.nb0, e.nb1, GP_LocalTime(e.t1), e.mins, e.mx);
  }
bool KB_QuickBack(datetime t, int mins)
  {
   int n = ArraySize(g_kbEv) - 1;
   if(mins > 5 || n < 0 || g_kbEv[n].kind != 2 || g_kbEv[n].t != g_kbBrkT) return false;
   if(n >= 1 && g_kbEv[n - 1].kind == 1 && g_kbEv[n - 1].side == g_kbBrkSide && g_kbBrkT - g_kbEv[n - 1].t1 <= 15 * 60)
     {
      ArrayResize(g_kbEv, n);                                             // buang cerita TEMBUS, tambahkan ke gabungan
      n--;
      g_kbEv[n].cnt++; g_kbEv[n].nb1 = g_kbNBrk; g_kbEv[n].mins = MathMax(g_kbEv[n].mins, MathMax(1, mins));
      g_kbEv[n].mx = MathMax(g_kbEv[n].mx, g_kbMaxOut); g_kbEv[n].t1 = g_kbBrkT;
     }
   else
     {
      g_kbEv[n].kind = 1; g_kbEv[n].side = g_kbBrkSide; g_kbEv[n].cnt = 1; g_kbEv[n].nb0 = g_kbNBrk; g_kbEv[n].nb1 = g_kbNBrk;
      g_kbEv[n].mins = MathMax(1, mins); g_kbEv[n].mx = g_kbMaxOut; g_kbEv[n].t1 = g_kbBrkT;
     }
   g_kbEv[n].txt = KB_QuickTxt(g_kbEv[n]); g_kbEv[n].c = clrYellow;
   return true;
  }

//--- TARGET (8 Okt 2026, pengguna: "18:55 mencolek atas -> TARGET tembus dalam 4-5 menit + confidence; setelah lewat dicek
//    tercapai atau tidak; tiap target masuk daftar; sesudah di luar kotak bot terus mengontrol: kembali atau berlanjut; garis-garis
//    GoldPro terdeteksi"). research\consol_target.py, aliran target PERSIS aturan ini (target colek/mepet berjarak >= 5 mnt),
//    XAUUSD M1 2017-26 (angka 85% consol_poke = AKHIRNYA, bukan dalam 5 mnt):
//      COLEK M1 -> dinding sama ditembus (close M1 di luar) s/d 5 candle 58.6% (latih 58.2 / uji 58.9, tiap th 57-60), 15 mnt
//                  73.7%, akhirnya 84.7%
//      MEPET (close >= 90% / <= 10% kotak, bukan colek) 52.1% (51.0 / 53.5), 15 mnt 70.1%, akhirnya 87.6%
//      sesudah TEMBUS: close kembali di dalam kotak s/d 5 candle 59.0% (58.6 / 59.3), 15 mnt 74.6%
//      LANJUT ke garis GoldPro berikutnya (tangga EQ/T0/T1.., di luar ekstrem candle tembus) sebelum close kembali ke dalam,
//                  per jarak x ADR: < 0.01 57% | < 0.02 42 | < 0.04 32 | < 0.06 23 | < 0.10 17 | < 0.15 13 | < 0.25 8 | lebih 4
//    Batas waktu = 5 candle M1 sesudah candle pemicu ("s/d hh:mm" = jam buka candle terakhir yang masih dihitung).
//    Hasil dicatat ke MQL5\Files\GoldPro\kotak_target.csv (uji maju live).
#define KB_TGW   5
#define KB_MAXTG 40
struct KBTarget { datetime t; int ty; int side; int conf; double lo; double hi; double lvl; string ln; string lns; int res; datetime rt;
                  string why; };       // ty 1 colek, 2 mepet, 3 kembali, 4 lanjut | res 0 menunggu, 1 KENA, 2 TIDAK / GAGAL
KBTarget g_kbTg[];
datetime g_kbTgLast = 0;
double   KB_LJ_D[7] = {0.01, 0.02, 0.04, 0.06, 0.10, 0.15, 0.25};
int      KB_LJ_P[8] = {57, 42, 32, 23, 17, 13, 8, 4};
int KB_LanjutP(double dA) { int k = 0; while(k < 7 && dA >= KB_LJ_D[k]) k++; return KB_LJ_P[k]; }

//--- KE TELEGRAM (8 Okt 2026, pengguna: "buat EA telegram yang memuat informasi ini, lengkap dengan simbolnya"): kejadian LIVE
//    ditulis ke MQL5\Files\GoldPro\kotak_telegram.txt, 1 baris = "SIMBOL|TAG|teks" ('^' = baris baru, "->" = panah); EA
//    Experts\GoldPro\GoldPro_Telegram.mq5 membaca, memberi simbol & mengirim (EA tidak pernah trading). Putar ulang tidak
//    ditulis; GoldPro di beberapa chart -> tiap kejadian sekali (kunci jam candle x 1000 + urutan, naik, di GV GP_KBTG_KEY).
//--- PERGANTIAN KOTAK DIBERI TAHU LEBIH DULU (9 Okt 2026, pengguna: "saat akan ada pergantian kotak ke kotak baru, ada keterangan di
//    dashboard dan telegram?"). Kotak selesai: umur 240 mnt (harga di dalam) / 60 mnt terus di luar / diganti kotak baru (60 mnt
//    sempit lagi sesudah >= 60 mnt tidak sempit). research\consol_hold60.py: peluang tembusan jadi TEMBUS SUNGGUHAN per menit di
//    luar (0 / 1-4 / 5-9 / 10-14 / 15-29 / 30-44 / 45-59) x jarak close dari dinding (< 0.1 / 0.1-0.25 / 0.25-0.5 / 0.5-1 / >= 1
//    lebar), 1.18 jt menit 2017-26, latih = uji +-2 (kecuali sel candle tembus >= 1 lebar n 358: 56 vs 42).
int      KB_H60[35] = {9, 16, 24, 33, 50, 11, 20, 29, 43, 60, 13, 24, 36, 49, 68, 14, 26, 40, 55, 74, 15, 31, 48, 66, 84, 21, 42, 62, 80, 94,
                       41, 67, 85, 95, 99};
double   g_kbR60 = -1, g_kbThrUsd = 0;     // rentang 60 mnt terakhir & batas sideway slot itu ($), candle terakhir
bool     g_kbSoonEnd = false, g_kbSoon30 = false, g_kbSoon45 = false, g_kbSoonNew = false, g_kbConsNow = false;
//--- kotak baru bisa muncul (mengganti kotak ini): 60 mnt terakhir belum sempit, sudah >= 60 mnt tidak sempit, rentang <= 115% batas
bool KB_NewNear(datetime t) { return !g_kbConsNow && t - g_kbLastCons >= 3600 && g_kbR60 > 0 && g_kbR60 <= 1.15 * g_kbThrUsd; }
string KB_After()
  {
   if(g_kbR60 < 0) return "kotak baru menunggu 60 mnt data utuh";
   return g_kbConsNow ? StringFormat("kotak baru langsung (60 mnt terakhir $%.1f <= batas $%.1f)", g_kbR60, g_kbThrUsd)
                      : StringFormat("belum ada kotak baru (60 mnt terakhir $%.1f > batas $%.1f)", g_kbR60, g_kbThrUsd);
  }
int KB_MOB(int mo) { return (mo < 1) ? 0 : ((mo < 5) ? 1 : ((mo < 10) ? 2 : ((mo < 15) ? 3 : ((mo < 30) ? 4 : ((mo < 45) ? 5 : 6))))); }
//--- KOREKSI JAM "v2" (10 Okt 2026, pengguna: "kita tambahkan aja dulu waktu yg konsisten itu"). research\consol_day2.py: tabel di
//    atas sama untuk semua jam, padahal meleset 4-10 poin searah di 2017-21 DAN 2022-26 pada 11 jam WITA (08 & 20-21 terlalu
//    tinggi, 00-03 / 10-12 / 23 terlalu rendah). consol_h60hr.py: p = sigmoid(A * logit(tabel) + B + HR[jam server]); jam server
//    = jam New York + 7 (= jam candle MT5, ikut DST). Uji 1.04 jt menit: logloss -1.21% (latih 17-21 -> nilai 22-26) & -1.64%
//    (dibalik), membaik 5/5 tahun di KEDUA arah; jam WITA & sisa-ke-tutup tidak lebih baik. Kotak ke-n / EQ / jumlah kotak kemarin
//    DITOLAK (logloss +0.06 / +0.17%). Dicatat di CSV dengan alasan "... v2" (evaluate_kotak.py memisahkan versi 1 / 2).
double KB_H60A = 1.0358, KB_H60B = 0.0435;
double KB_H60HR[24] = {0.0000, 0.0783, -0.3612, -0.5242, -0.0147, 0.3866, 0.3968, 0.1046, -0.2721, -0.3237, -0.1144, 0.1091, 0.1813,
                       -0.0397, -0.4203, -0.5260, -0.5020, 0.1449, 0.4648, 0.4542, 0.2559, 0.2832, 0.3183, -0.0330};   // [jam server]
int KB_H60P(int mo, double d, datetime t)
  {
   int db = (d < 0.1) ? 0 : ((d < 0.25) ? 1 : ((d < 0.5) ? 2 : ((d < 1) ? 3 : 4)));
   double p0 = MathMax(0.005, MathMin(0.995, KB_H60[KB_MOB(mo) * 5 + db] / 100.0));
   MqlDateTime s;
   TimeToStruct(t, s);
   double z = KB_H60A * MathLog(p0 / (1.0 - p0)) + KB_H60B + KB_H60HR[s.hour];
   return (int)MathMax(1, MathMin(99, MathRound(100.0 / (1.0 + MathExp(-z)))));
  }
//--- PETA KEMBALI / TIDAK KEMBALI (9 Okt 2026, pengguna: "petakan waktu / ujung terjauh, mana yang akan kembali dan mana yang tidak"
//    -> "pasang"). research\consol_map.py: 951 rb menit di luar 2017-26, latih = uji (selisih umumnya <= 3 poin). % close KEMBALI di
//    dalam kotak sebelum 60 mnt di luar, per menit di luar (0 / 1-4 / 5-9 / 10-14 / 15-29 / 30-44 / 45-59) x UJUNG TERJAUH di luar
//    s/d candle itu (< 0.25 / 0.25-0.5 / 0.5-1 / 1-2 / >= 2 lebar kotak; -1 = sampel < 150) + median menit sampai kembali (bagi yang
//    kembali). Angka baris dashboard = 100 - KB_H60 (menit x jarak close sekarang) - sama tepat (logloss uji 0.4763 vs peta 0.4770,
//    gabungan 0.4741) -> peta = penjelas di tooltip. Posisi close vs ujung (balik > separuh / 20-50% / di ujung): kembali menit 5-9
//    82 / 65 / 52%, 15-29 67 / 37 / 22%, 30-44 48 / 16 / 7%.
int KB_MAPK[35] = {90, 81, 74, 59, -1, 86, 78, 68, 54, 34, 81, 74, 63, 48, 27, 75, 70, 58, 43, 23, 73, 61, 50, 34, 15, 48, 45, 35, 21, 8,
                   -1, 23, 14, 7, 3};
int KB_MAPM[35] = {2, 5, 7, 11, -1, 4, 6, 10, 14, 21, 5, 8, 12, 16, 22, 6, 9, 12, 17, 21, 6, 9, 12, 14, 18, 10, 8, 9, 10, 12, -1, 5, 5, 5, 5};
int KB_MXB(double x) { return (x < 0.25) ? 0 : ((x < 0.5) ? 1 : ((x < 1) ? 2 : ((x < 2) ? 3 : 4))); }
string KB_MapTip(int cell)
  {
   string ml[7] = {"0 (tembus)", "1-4", "5-9", "10-14", "15-29", "30-44", "45-59"};
   string s = "Peluang close KEMBALI di dalam kotak sebelum 60 mnt di luar (= 100 - peluang tembus sungguhan). (~x mnt) = median\n"
              "waktu sampai kembali bagi yang kembali. Ujung = lewat dinding terjauh s/d candle terakhir (x lebar kotak); di ujung /\n"
              "balik = close dibanding ujung itu. PETA % KEMBALI (uji 2017-26, 951 rb menit, latih = uji), ujung terjauh\n"
              "< 0.25 / 0.25-0.5 / 0.5-1 / 1-2 / >= 2 lebar ([ ] = sekarang):";
   for(int r = 0; r < 7; r++)
     {
      s += "\n  menit " + ml[r] + ":";
      for(int c = 0; c < 5; c++)
        {
         int v = KB_MAPK[r * 5 + c];
         string t = (v < 0) ? "-" : IntegerToString(v);
         s += (c > 0 ? " /" : "") + (r * 5 + c == cell ? " [" + t + "]" : " " + t);
        }
     }
   return s + "\nSudah balik > separuh dari ujung ke dinding: kembali menit 5-9 82%, 15-29 67%, 30-44 48%; masih di ujung 52 / 22 / 7%.";
  }
//--- DINDING KOTAK LAMA TERSENTUH LAGI (9 Okt 2026, consol_map.py B, pengguna: "setelah kotak berakhir, harga jauh di atas, lalu
//    terbentuk kotak selanjutnya - melanjutkan atau sebaliknya?"): sesudah TEMBUS SUNGGUHAN, kotak berikutnya (lahir <= 8 jam): arah
//    lanjut / balik = KOIN (tembusan pertama searah 51.7% vs harapan posisi 51.5%, tembus sungguhan searah 49.9%, gerak 4 jam ~0), tapi
//    harga MENYENTUH lagi dinding lama yang ditembus dalam 4 jam 57%, menurut jarak tengah kotak baru dari dinding itu (x ADR): di
//    belakang dinding 99%, < 0.1 73%, 0.1-0.25 44%, 0.25-0.5 16%, >= 0.5 2% (latih / uji selisih <= 4 poin, 7.9 rb kotak 2017-26).
datetime g_kbRealT = 0, g_kbOldT0 = 0, g_kbOldHit = 0;
double   g_kbRealW = 0, g_kbOldW = 0;
int      g_kbRealS = 0, g_kbOldS = 0, g_kbOldP = -1;
int KB_OldP(double trav) { return (trav < 0) ? 99 : ((trav < 0.1) ? 73 : ((trav < 0.25) ? 44 : ((trav < 0.5) ? 16 : 2))); }
datetime g_kbOutT = 0, g_kbAlertPB = 0, g_kbAlertPK = 0, g_kbTgMadeT = 0;
int      g_kbOutSeq = 0, g_kbBoxN = 0, g_kbBoxK = 0;
double   g_kbBoxE = 0;
//--- SUSULAN (10 Okt 2026, rencana pengerasan no. 2): dulu kejadian saat putar ulang (ganti TF / chart utama pindah / MT5 macet
//    lalu indikator dimuat ulang) TIDAK dikirim -> 9 Okt 09:37-09:54 pesan "30 mnt di luar" hilang. Sekarang kejadian putar ulang
//    <= KB_CATCHUP mnt terakhir yang BELUM pernah dikirim (kunci GP_KBTG_KEY naik) dikirim dengan tanda SUSULAN; kejadian live yang
//    terlambat > 3 mnt (MT5 sempat macet) juga diberi tanda. Rapor tidak disusulkan (punya jadwal sendiri). Hanya CHART UTAMA menulis.
#define KB_CATCHUP 30
void KB_Out(datetime t, string tag, string text)
  {
   if(t != g_kbOutT) { g_kbOutT = t; g_kbOutSeq = 0; }
   else g_kbOutSeq++;
   if(!InpKBTelegram || !g_gpMaster || MQLInfoInteger(MQL_TESTER)) return;
   int late = (int)((TimeCurrent() - (t + 60)) / 60);                     // menit sejak candle t close
   if(!g_kbLive && (late > KB_CATCHUP || tag == "RAPOR")) return;
   double key = (double)t * 1000.0 + g_kbOutSeq;
   if(GlobalVariableCheck("GP_KBTG_KEY") && key <= GlobalVariableGet("GP_KBTG_KEY")) return;
   if(late > 3 && tag != "RAPOR" && tag != "ALARM")
      text = StringFormat("SUSULAN (kejadian %s, terlambat %d mnt): ", GP_LocalTime(t), late) + text;
   FolderCreate("GoldPro");
   string fn = "GoldPro\\kotak_telegram.txt";
   int fh = FileOpen(fn, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE) return;
   if(FileSize(fh) > 1000000)                                             // > 1 MB: mulai baru (EA membaca ulang dari awal)
     {
      FileClose(fh); FileDelete(fn);
      fh = FileOpen(fn, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
      if(fh == INVALID_HANDLE) return;
     }
   FileSeek(fh, 0, SEEK_END);
   FileWriteString(fh, _Symbol + "|" + tag + "|" + text + "\r\n");
   FileClose(fh);
   GlobalVariableSet("GP_KBTG_KEY", key);
  }
void KB_OutEnd(datetime t, string why)
  {
   KB_Out(t, "END", StringFormat("KOTAK SELESAI %s (lahir %s)^%s^peluang kotak ini KENA %d/%d (harapan %.1f)", KB_Rng(),
                                 GP_LocalTime(g_kbStart), why, g_kbBoxK, g_kbBoxN, g_kbBoxE));
  }

void KB_TgAdd(datetime t, int ty, int side, int conf, double lvl = 0, string ln = "", string lns = "")
  {
   int n = ArraySize(g_kbTg);
   if(n >= KB_MAXTG)
     {
      int drop = -1;
      for(int i = 0; i < n && drop < 0; i++) if(g_kbTg[i].res != 0) drop = i;   // buang target selesai yang paling lama
      if(drop < 0) drop = 0;
      for(int i = drop + 1; i < n; i++) g_kbTg[i - 1] = g_kbTg[i];
      n--;
     }
   ArrayResize(g_kbTg, n + 1);
   g_kbTg[n].t = t; g_kbTg[n].ty = ty; g_kbTg[n].side = side; g_kbTg[n].conf = conf; g_kbTg[n].lo = g_kbLo; g_kbTg[n].hi = g_kbHi;
   g_kbTg[n].lvl = lvl; g_kbTg[n].ln = ln; g_kbTg[n].lns = lns; g_kbTg[n].res = 0; g_kbTg[n].rt = 0; g_kbTg[n].why = "";
  }

string KB_WitaFull(datetime server) { return TimeToString(GP_UTCToLocal(GP_ServerToUTC(server)), TIME_DATE | TIME_MINUTES); }
string KB_TgTrig(const KBTarget &x)
  {
   if(x.ty == 1) return "colek " + KB_Wall(x.side);
   if(x.ty == 2) return "mepet " + KB_Wall(x.side);
   return x.side > 0 ? "tembus ATAS" : "tembus BAWAH";
  }
string KB_TgGoal(const KBTarget &x, bool lst)
  {
   if(x.ty <= 2) return StringFormat("tembus %s s/d %s", x.side > 0 ? "ATAS" : "BAWAH", GP_LocalTime(x.t + KB_TGW * 60));
   if(x.ty == 3) return (lst ? "kembali s/d " : "kembali ke kotak s/d ") + GP_LocalTime(x.t + KB_TGW * 60);
   return (lst ? "garis " + x.lns : x.ln) + " " + KB_Px(x.lvl);
  }
string KB_TgRes(const KBTarget &x)
  {
   if(x.res == 0) return "menunggu";
   if(x.res == 1) return "KENA " + GP_LocalTime(x.rt);
   return (x.ty == 4) ? "GAGAL" : "TIDAK";
  }

//--- catat target selesai ke CSV (sekali saja: kunci naik disimpan di GlobalVariable, aman untuk putar ulang & beberapa chart)
void KB_TgLog(const KBTarget &x)
  {
   if(!g_gpMaster) return;                                               // hanya CHART UTAMA menulis CSV
   double key = (double)x.rt * 100000.0 + (double)((x.t / 60) % 10000) * 10.0 + x.ty;
   string gv = "GP_KBJ_KEY";
   if(GlobalVariableCheck(gv) && key <= GlobalVariableGet(gv)) return;
   FolderCreate("GoldPro");
   string fn = "GoldPro\\kotak_target.csv";
   bool isNew = !FileIsExist(fn);
   int fh = FileOpen(fn, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ, ';');
   if(fh == INVALID_HANDLE) return;
   FileSeek(fh, 0, SEEK_END);
   if(isNew)
      FileWrite(fh, "dibuat_wita", "pemicu", "target", "yakin_pct", "hasil", "waktu_hasil_wita", "kotak_bawah", "kotak_atas", "sumber");
   FileWrite(fh, KB_WitaFull(x.t), KB_TgTrig(x), KB_TgGoal(x, false), x.conf, x.res == 1 ? "KENA" : (x.ty == 4 ? "GAGAL" : "TIDAK"),
             KB_WitaFull(x.rt), DoubleToString(x.lo, 2), DoubleToString(x.hi, 2), g_kbLive ? "live" : "putar-ulang");
   FileClose(fh);
   GlobalVariableSet(gv, key);
  }

//--- periksa target yang menunggu dengan candle M1 yang baru close (t = jam buka candle). Dinding = kotak saat target dibuat.
void KB_TgResolve(datetime t, double h, double l, double c)
  {
   for(int i = 0; i < ArraySize(g_kbTg); i++)
     {
      if(g_kbTg[i].res != 0 || t <= g_kbTg[i].t) continue;
      bool up = c > g_kbTg[i].hi, dn = c < g_kbTg[i].lo;
      bool same = (g_kbTg[i].side > 0) ? up : dn, oth = (g_kbTg[i].side > 0) ? dn : up;
      bool end = (t >= g_kbTg[i].t + KB_TGW * 60);
      int r = 0;
      if(g_kbTg[i].ty <= 2)      r = same ? 1 : ((oth || end) ? 2 : 0);
      else if(g_kbTg[i].ty == 3) r = (!up && !dn) ? 1 : ((oth || end) ? 2 : 0);
      else
        {
         bool reach = (g_kbTg[i].side > 0) ? h >= g_kbTg[i].lvl : l <= g_kbTg[i].lvl;
         r = !same ? 2 : (reach ? 1 : ((t - g_kbTg[i].t >= 240 * 60) ? 2 : 0));   // candle kembali ke kotak dihitung GAGAL dulu (= riset)
        }
      if(r == 0) continue;
      g_kbTg[i].res = r; g_kbTg[i].rt = t;
      if(g_kbTg[i].t >= g_kbStart) { g_kbBoxN++; if(r == 1) g_kbBoxK++; g_kbBoxE += g_kbTg[i].conf / 100.0; }
      KB_TgLog(g_kbTg[i]);
      //--- Telegram: hasil target
      KBTarget x = g_kbTg[i];
      string s;
      if(x.ty <= 2)
         s = (r == 1) ? StringFormat("KENA %s: %s %s -> tembus %s (yakin %d%%)", GP_LocalTime(t), KB_TgTrig(x), GP_LocalTime(x.t),
                                     x.side > 0 ? "ATAS" : "BAWAH", x.conf)
                      : StringFormat("TIDAK: %s %s -> tembus %s s/d %s (yakin %d%%)", KB_TgTrig(x), GP_LocalTime(x.t),
                                     x.side > 0 ? "ATAS" : "BAWAH", GP_LocalTime(x.t + KB_TGW * 60), x.conf);
      else if(x.ty == 3)
         s = (r == 1) ? StringFormat("KENA %s: kembali ke kotak sesudah %s %s (yakin %d%%)", GP_LocalTime(t), KB_TgTrig(x), GP_LocalTime(x.t), x.conf)
                      : StringFormat("TIDAK: tidak kembali ke kotak s/d %s sesudah %s %s (yakin %d%%)", GP_LocalTime(x.t + KB_TGW * 60),
                                     KB_TgTrig(x), GP_LocalTime(x.t), x.conf);
      else
         s = (r == 1) ? StringFormat("KENA %s: lanjut ke %s %s (yakin %d%%)", GP_LocalTime(t), x.ln, KB_Px(x.lvl), x.conf)
                      : StringFormat("GAGAL: %s %s tidak tercapai (yakin %d%%)", x.ln, KB_Px(x.lvl), x.conf);
      KB_Out(t, r == 1 ? "KENA" : (x.ty == 4 ? "GAGAL" : "TIDAK"), s);
     }
  }

//--- pemicu target colek / mepet pada candle yang close DI DALAM kotak (jarak >= 5 mnt dari target sebelumnya)
void KB_TgTrigger(datetime t, double h, double l, double c)
  {
   if(t - g_kbTgLast < KB_TGW * 60 || g_kbHi <= g_kbLo) return;
   int ty = 0, side = 0;
   if(h > g_kbHi || l < g_kbLo)
     {
      ty = 1;
      side = (h > g_kbHi && l < g_kbLo) ? (((h - g_kbHi) >= (g_kbLo - l)) ? 1 : -1) : ((h > g_kbHi) ? 1 : -1);
     }
   else
     {
      double p = (c - g_kbLo) / (g_kbHi - g_kbLo);
      if(p >= 0.9) { ty = 2; side = 1; }
      else if(p <= 0.1) { ty = 2; side = -1; }
     }
   if(ty == 0) return;
   KB_TgAdd(t, ty, side, ty == 1 ? 59 : 52);
   g_kbTgLast = t; g_kbTgMadeT = t;
   KBTarget x = g_kbTg[ArraySize(g_kbTg) - 1];
   //--- 15 Okt 2026 (pengguna: "notifikasinya sangat berantakan ... ketika menyentuh, informasikan candle yg sudah tutup"): judul
   //    singkat + candle yang sudah tutup + peluang; colek = TGT "menyentuh", mepet = TGM "mendekati" (saklar EA terpisah)
   double wall = (side > 0) ? g_kbHi : g_kbLo;
   string s;
   if(ty == 1)
      s = StringFormat("menyentuh %s %s | candle %s tutup", KB_Wall(side), KB_Px(wall), GP_LocalTime(t)) +
          StringFormat("^%s %s (lewat $%.2f), close %s kembali di dalam", side > 0 ? "high" : "low", KB_Px(side > 0 ? h : l),
                       side > 0 ? h - g_kbHi : g_kbLo - l, KB_Px(c));
   else
      s = StringFormat("mendekati %s %s | candle %s tutup", KB_Wall(side), KB_Px(wall), GP_LocalTime(t)) +
          StringFormat("^close %s = %d%% kotak ($%.2f dari %s)", KB_Px(c), KB_Pct((c - g_kbLo) / (g_kbHi - g_kbLo)), MathAbs(wall - c),
                       KB_wall(side));
   s += StringFormat("^peluang tembus %s s/d %s: %d%% (15 mnt %d%%)", KB_Wall(side), GP_LocalTime(x.t + KB_TGW * 60), x.conf,
                     ty == 1 ? 74 : 70) + KB_AlNote(ty == 1 ? 3 : 4);
   s += StringFormat("^kotak %s ($%.2f)", KB_Rng(), g_kbHi - g_kbLo);
   KB_Out(t, ty == 1 ? "TGT" : "TGM", s);
  }

//--- sesudah TEMBUS: target KEMBALI + target LANJUT ke garis GoldPro berikutnya di luar ekstrem candle tembus (tangga hari ini)
void KB_TgBreak(datetime t, int side, double ext, int confBack)
  {
   KB_TgAdd(t, 3, side, confBack);                                       // yakin = model "kembali 5 mnt" di candle tembus (dulu rata2 59%)
   if(GDM::g_nd <= 0) return;
   GDM::DayInfo d = GDM::g_days[GDM::g_nd - 1];
   if(t < d.t0 || d.adr <= 0) return;                                   // candle hari kemarin (putar ulang) -> tangga lain, lewati
   GDM::LiveInfo li;
   GDM::GetLive(d, li);
   double lv[];
   string nm[], sh[];
   int nl = GDM::RtLadder(d, li, lv, nm, sh), k = -1;
   if(side > 0) { for(int i = 0; i < nl && k < 0; i++) if(lv[i] > ext) k = i; }
   else         { for(int i = nl - 1; i >= 0 && k < 0; i--) if(lv[i] < ext) k = i; }
   if(k < 0) return;
   KB_TgAdd(t, 4, side, KB_LanjutP(MathAbs(lv[k] - ext) / d.adr), lv[k], nm[k], sh[k]);
  }
//--- Telegram: pesan TEMBUS (dipanggil sesudah KB_TgBreak) - target kembali & lanjut dari candle yang sama
void KB_OutBreak(datetime t, double c, bool jump)
  {
   string s = StringFormat("TEMBUS %s %s%s | candle %s tutup", KB_Wall(g_kbBrkSide), KB_Px(g_kbBrkSide > 0 ? g_kbHi : g_kbLo),
                           jump ? " (loncat dari sisi seberang)" : (g_kbNBrk > 1 ? StringFormat(" ke-%d", g_kbNBrk) : ""), GP_LocalTime(t));
   s += StringFormat("^close %s ($%.2f %s %s)", KB_Px(c), MathAbs(g_kbBrkSide > 0 ? c - g_kbHi : g_kbLo - c),
                     g_kbBrkSide > 0 ? "di atas" : "di bawah", KB_wall(g_kbBrkSide));
   string sk = "", sl = "";
   for(int i = ArraySize(g_kbTg) - 1; i >= 0 && g_kbTg[i].t == t; i--)
     {
      if(g_kbTg[i].ty == 3) sk = StringFormat("^Kembali ke kotak s/d %s: yakin %d%%", GP_LocalTime(t + KB_TGW * 60), g_kbTg[i].conf);
      if(g_kbTg[i].ty == 4) sl = StringFormat("^Lanjut ke %s %s: yakin %d%%", g_kbTg[i].ln, KB_Px(g_kbTg[i].lvl), g_kbTg[i].conf);
     }
   KB_Out(t, g_kbBrkSide > 0 ? "UP" : "DN", s + sk + sl);
  }

//--- PECAH DALAM 5 MENIT (8 Okt 2026 malam, pengguna: "itu perlu untuk meningkatkan kualitas"). research\consol_why.py (pemicu
//    waktu: berita x2.1, data NY 08:30 x2.6, buka London/NY x1.5, jam aktif/sepi) -> consol_when.py / consol_when2.py: regresi
//    logistik tiap menit candle close di dalam kotak (1.07 jt sampel 2017-26), hasil = candle M1 close di luar kotak dalam 5
//    candle berikut. Fitur: desil posisi, colek per desil, berita USD HIGH / data NY 08:30 (dibedakan harga di tengah kotak
//    desil 2-7 vs dekat dinding), buka London 08:00, buka NY 09:30 ET, jam WITA, umur kotak, pernah ditembus, + LEBAR kotak
//    relatif ambang (consol_when3.py: < 0.55x pecah 5 mnt 41.6%, 0.55-0.75 35.6, 0.75-0.9 28.6, 0.9-1 25.2; logloss 0.4700 -> 0.4695).
//    Uji satu-tahun-ditahan: logloss 0.4720 vs posisi saja 0.4929; + tabel koreksi (dari tahun lain) bila TANPA berita/08:30,
//    model langsung bila ADA (di atas 70% dikecilkan separuh): semua kelompok prediksi selisih <= 1 poin; berita 54.4 vs nyata
//    53.8, data 08:30 61.8 vs 61.1, berita dekat dinding 66.4 vs 65.9, colek 58.6 vs 60.5, jam 20-21 WITA 38.4 vs 38.7.
double KB_W_POS[10] = {1.1932, 0.3047, -0.4268, -1.0021, -1.2899, -1.3355, -1.0145, -0.4791, 0.2698, 1.1857};
double KB_W_PK[10]  = {0.3988, 0.4690, 0.7902, 1.4887, 1.5550, 1.6840, 1.5678, 0.8687, 0.5253, 0.4180};
double KB_W_HR[24]  = {-0.6635, -0.6983, -0.6769, -0.6160, -0.6705, -0.7239, -0.6586, -0.3584, 0.2429, 0.4251, -0.2834, -0.6249, -0.6047, 0.0883, 0.3446, 0.2356, 0.0000, -0.2868, -0.3264, -0.1142, 0.3117, 0.4580, 0.1701, -0.3348};
double KB_W_AGE[4]  = {0.0000, -0.1025, -0.1526, -0.1735};
double KB_W_WID[4]  = {0.0000, -0.5140, -0.7856, -0.9350};
double KB_W_NEWS_MID = 1.1225, KB_W_NEWS_TEPI = 0.4310, KB_W_NY830_MID = 1.0340, KB_W_NY830_TEPI = 0.2583;
double KB_W_LON = 0.4653, KB_W_NY930 = 0.2867, KB_W_BRK = 0.3041;
#define KB_NCAL 20
double KB_CAL_X[KB_NCAL] = {0.0525, 0.0632, 0.0746, 0.0832, 0.0960, 0.1100, 0.1242, 0.1354, 0.1503, 0.1708, 0.1939, 0.2258, 0.2523, 0.2918, 0.3495, 0.4261, 0.4812, 0.5481, 0.6313, 0.7444};
double KB_CAL_Y[KB_NCAL] = {0.0338, 0.0414, 0.0573, 0.0592, 0.0836, 0.1090, 0.1204, 0.1322, 0.1680, 0.1957, 0.2257, 0.2363, 0.2617, 0.3123, 0.3647, 0.4397, 0.4868, 0.5851, 0.6136, 0.6699};
//--- KEMBALI KE KOTAK DALAM 5 MENIT, tiap candle close DI LUAR kotak (8 Okt 2026 malam, pengguna: "setelah harga keluar kotak dan akan
//    kembali lagi ke dalam kotak, itu juga perlu"). research\consol_back.py: 1.18 jt menit di luar 2017-26 (s/d 59 mnt sesudah
//    tembus), hasil = candle M1 close di dalam kotak dalam 5 candle (rata2 18.3%). Regresi logistik: sel menit di luar x jarak
//    close dari dinding (x lebar kotak) + close dibanding ekstrem (sedang balik?) + colek dinding dari luar + berita USD HIGH /
//    data NY 08:30 dlm 5 candle + jam WITA + tembusan ke-n + lebar kotak + sisi. Uji satu-tahun-ditahan + tabel koreksi: logloss
//    0.3203 (rata2 0.4762); tiap kelompok prediksi selisih <= 0.7 poin; colek dari luar 57.4 vs nyata 59.3, berita 25.4 vs 27.1,
//    jarak < 0.1 lebar 60.7 vs 62.5, 15-59 mnt di luar 7.2 vs 7.3; per tahun 16.8-19.5 vs 17.3-19.5.
//    Tabel sederhana (kembali 5 mnt): candle tembus & < 0.1 lebar 67%, >= 1 lebar 11%; 30-59 mnt di luar: 56% / 0%.
double KB_B_C[40]  = {1.8566, 1.2364, 0.5581, 0.0456, -0.2991, 1.7176, 1.2286, 0.5630, -0.1875, -0.4034, 1.5919, 1.0847, 0.3847, -0.5647, -0.6861, 1.4777, 0.8922, 0.1521, -0.6992, -1.5721, 1.3821, 0.6254, -0.1690, -1.1236, -2.6121, 1.3336, 0.4160, -0.4664, -1.5285, -3.0286, 1.2879, 0.2641, -0.7406, -1.8409, -3.4065, 1.2486, 0.1224, -0.9631, -2.1923, -4.0023};   // [menit*5 + jarak]
double KB_B_R[3]   = {0.8173, 0.2686, 0.0000};
double KB_B_HR[24] = {-0.4191, -0.4624, -0.4345, -0.3389, -0.3776, -0.3969, -0.2360, -0.1332, 0.0769, 0.1853, -0.2020, -0.3560, -0.3009, 0.0051, 0.1431, 0.1320, 0.0000, -0.2281, -0.1937, -0.0441, 0.2811, 0.3633, 0.1223, -0.2113};
double KB_B_NB[4]  = {0.0000, 0.0000, 0.0079, 0.0295};
double KB_B_W[4]   = {0.0000, -1.5065, -1.7812, -1.8332};
double KB_B_PKB = 0.3851, KB_B_NEWS = 0.6771, KB_B_NY830 = 0.1277, KB_B_DN = 0.0345;
#define KB_NCALB 20
double KB_CALB_X[KB_NCALB] = {0.0026, 0.0036, 0.0047, 0.0070, 0.0126, 0.0192, 0.0267, 0.0369, 0.0505, 0.0674, 0.0910, 0.1195, 0.1564, 0.2048, 0.2610, 0.3279, 0.4145, 0.5155, 0.6103, 0.7361};
double KB_CALB_Y[KB_NCALB] = {0.0011, 0.0018, 0.0038, 0.0084, 0.0111, 0.0113, 0.0204, 0.0353, 0.0502, 0.0608, 0.0850, 0.1212, 0.1675, 0.2102, 0.2655, 0.3472, 0.4281, 0.5335, 0.6201, 0.6808};
//--- MASUK LAGI: BENAR-BENAR MASUK ATAU KELUAR-MASUK? (8 Okt malam, pengguna: "saat menyentuh dinding kotak setelah dari luar, seberapa
//    yakin harga akan benar-benar masuk?"). research\consol_retest.py, 2017-26, latih = uji:
//    COLEK DARI LUAR (140 rb): close masuk dlm 5 mnt 59% / 15 mnt 75%, tapi MASUK & BERTAHAN 10 mnt hanya 15.8%; per jarak close
//      dari dinding (< 5% / 5-10 / 10-25 / 25-50 / >= 50% lebar): masuk 5 mnt 71/61/49/35/22%, masuk & bertahan 20/17/12/6/3%.
//    SEMUA MASUK LAGI (72 rb): bertahan 10 mnt 26.2%, 30 mnt 9.5%, ke tengah kotak dulu 28.3%; bila keluar lagi lewat dinding
//      yang SAMA 93%. Per dalamnya close masuk (< 5% / 5-10 / 10-25 / 25-50 / >= 50% lebar): bertahan 10 mnt 20/28/34/34/22%,
//      ke tengah dulu 17/26/40/69/100%, keluar lagi sisi sama 98/96/89/70/40%. Lama di luar & colek ke-n hampir tidak berpengaruh.
int      KB_PKO_IN[5] = {20, 17, 12, 6, 3};
int      KB_RE_STAY[5] = {20, 28, 34, 34, 22}, KB_RE_MID[5] = {17, 26, 40, 69, 100}, KB_RE_SAME[5] = {98, 96, 89, 70, 40};
int KB_Bin5(double x) { return (x < 0.05) ? 0 : ((x < 0.1) ? 1 : ((x < 0.25) ? 2 : ((x < 0.5) ? 3 : 4))); }
bool     g_kbPKpkb = false;                // candle terakhir di luar = colek dinding dari luar
double   g_kbPKd = 0;                      // jarak close dari dinding (x lebar) candle terakhir di luar
double   g_kbBackDepth = 0;                // dalamnya close saat masuk lagi (x lebar dari dinding yang ditembus)
int      g_kbBackSide = 0;
double   g_kbPK = -1;                      // peluang kembali ke kotak dlm 5 mnt (candle terakhir yang close di luar)
string   g_kbPKWhy = "";
datetime g_kbPKT = 0;
datetime g_kbNewsT[];                      // rilis berita USD HIGH (jam server, dikoreksi GP_CalTime)
string   g_kbNewsN[];
datetime g_kbNewsLoad = 0;
double   g_kbWrel = 1;                     // lebar kotak saat lahir / ambang konsolidasi slot itu (consol_when3: makin sempit makin cepat pecah)
double   g_kbPB = -1;                      // peluang pecah 5 mnt dari candle terakhir yang tutup di dalam kotak
string   g_kbPBWhy = "";
datetime g_kbPBT = 0;
//--- prediksi yang menunggu hasil (dicatat ke kotak_prediksi.csv saat selesai). mo = umur kotak (pecah) / menit di luar (kembali,
//    sungguhan); side & tb = sisi & candle tembus (sungguhan); live = dibuat saat live (bukan putar ulang)
struct KBPend { datetime t; double p; double lo; double hi; double c; int mo; int side; datetime tb; string why; bool live; double lvl; };
KBPend   g_kbPend[];
KBPend   g_kbPendK[];                      // prediksi "kembali 5 mnt" yang menunggu hasil
KBPend   g_kbPendH[];                      // prediksi "tembus sungguhan" (menit 0 / 15 / 30 / 45 di luar) yang menunggu hasil
KBPend   g_kbPendO[];                      // prediksi "dinding kotak lama tersentuh lagi 4 jam" (lvl = dinding lama) yang menunggu hasil
int      g_kbH60Lg = 0;                    // menit tembusan ini yang sudah dicatat (bit 0 = menit 0, 1 = 15, 2 = 30, 3 = 45)

void KB_NewsLoad(datetime from, datetime to)
  {
   MqlCalendarValue v[];
   int n = CalendarValueHistory(v, from, to, NULL, "USD");
   if(n < 0) return;
   ArrayResize(g_kbNewsT, 0); ArrayResize(g_kbNewsN, 0);
   for(int i = 0; i < n; i++)
     {
      MqlCalendarEvent e;
      if(!CalendarEventById(v[i].event_id, e) || e.importance != CALENDAR_IMPORTANCE_HIGH) continue;
      int k = ArraySize(g_kbNewsT);
      ArrayResize(g_kbNewsT, k + 1); ArrayResize(g_kbNewsN, k + 1);
      g_kbNewsT[k] = GP_CalTime(v[i].time); g_kbNewsN[k] = e.name;
     }
   g_kbNewsLoad = TimeCurrent();
  }
int KB_NewsIn(datetime t0, datetime t1)
  {
   for(int i = 0; i < ArraySize(g_kbNewsT); i++) if(g_kbNewsT[i] >= t0 && g_kbNewsT[i] <= t1) return i;
   return -1;
  }
double KB_Interp(double x)
  {
   if(x <= KB_CAL_X[0]) return KB_CAL_Y[0];
   for(int i = 1; i < KB_NCAL; i++)
      if(x <= KB_CAL_X[i]) return KB_CAL_Y[i - 1] + (KB_CAL_Y[i] - KB_CAL_Y[i - 1]) * (x - KB_CAL_X[i - 1]) / (KB_CAL_X[i] - KB_CAL_X[i - 1]);
   return KB_CAL_Y[KB_NCAL - 1];
  }

//--- peluang candle M1 close di luar kotak dalam 5 candle sesudah candle t (close c, high h, low l, tutup di dalam kotak)
double KB_PBreak(datetime t, double h, double l, double c, string &why)
  {
   why = "";
   double wd = g_kbHi - g_kbLo;
   if(wd <= 0) return -1;
   int pd = (int)MathMin(9, MathMax(0, MathFloor((c - g_kbLo) / wd * 10)));
   bool poke = (h > g_kbHi || l < g_kbLo), mid = (pd >= 2 && pd <= 7);
   int ni = KB_NewsIn(t + 60, t + 5 * 60);
   bool ny830 = false, ny930 = false, lon = false;
   for(int m = 1; m <= 5; m++)
     {
      datetime u = GP_ServerToUTC(t + m * 60);
      MqlDateTime e, d;
      TimeToStruct(GP_UTCToET(u), e); TimeToStruct(GP_UTCToLondon(u), d);
      int em = e.hour * 60 + e.min;
      if(em == 510) ny830 = true;
      if(em == 570) ny930 = true;
      if(d.hour * 60 + d.min == 480) lon = true;
     }
   int hr = KB_HourWITA(t), age = (int)((t - g_kbStart) / 60);
   int ab = (age < 15) ? 0 : ((age < 60) ? 1 : ((age < 120) ? 2 : 3));
   int wb = (g_kbWrel < 0.55) ? 0 : ((g_kbWrel < 0.75) ? 1 : ((g_kbWrel < 0.9) ? 2 : 3));
   double z = KB_W_POS[pd] + (poke ? KB_W_PK[pd] : 0) + KB_W_HR[hr] + KB_W_AGE[ab] + KB_W_WID[wb] + (g_kbNBrk > 0 ? KB_W_BRK : 0)
              + (ni >= 0 ? (mid ? KB_W_NEWS_MID : KB_W_NEWS_TEPI) : 0) + (ny830 ? (mid ? KB_W_NY830_MID : KB_W_NY830_TEPI) : 0)
              + (lon ? KB_W_LON : 0) + (ny930 ? KB_W_NY930 : 0);
   double p = 1.0 / (1.0 + MathExp(-z));
   if(ni >= 0 || ny830) p = (p > 0.7) ? 0.7 + 0.5 * (p - 0.7) : p;
   else p = KB_Interp(p);
   //--- alasan utama (maks 2)
   if(ni >= 0) why = "berita " + GP_LocalTime(g_kbNewsT[ni]);
   else if(ny830) why = "data NY 08:30";
   if(lon) why += (why == "" ? "" : ", ") + "buka London";
   if(ny930) why += (why == "" ? "" : ", ") + "buka NY";
   if(poke && StringFind(why, ",") < 0) why += (why == "" ? "" : ", ") + "colek";
   if(why == "" && KB_W_HR[hr] >= 0.2) why = "jam aktif";
   if(why == "" && KB_W_HR[hr] <= -0.5) why = "jam sepi";
   return p;
  }
//--- UJI MAJU SEMUA PREDIKSI (9 Okt 2026, usulan perbaikan no. 1, disetujui pengguna): tiap prediksi "pecah 5 mnt" (tiap candle di
//    dalam kotak), "kembali 5 mnt" (tiap candle di luar) & "tembus sungguhan" (menit 0 / 15 / 30 / 45 di luar) dicatat bersama
//    hasilnya ke MQL5\Files\GoldPro\kotak_prediksi.csv -> dashboard, rapor harian & Files\GoldPro\evaluate_kotak.py membandingkan
//    angka yang ditampilkan dengan kenyataan. Sekali saja per prediksi: kunci = jam candle prediksi (naik; prediksi selesai urut
//    dibuat) di GV GP_KBP_KEY0/1/2 - aman untuk putar ulang & beberapa chart.
string KB_PJ[4] = {"pecah5", "kembali5", "sungguhan60", "dinding4j"};
void KB_PredLog(int kind, const KBPend &x, bool yes, datetime rt)
  {
   if(MQLInfoInteger(MQL_TESTER) || !g_gpMaster) return;                // hanya CHART UTAMA menulis CSV
   string gv = "GP_KBP_KEY" + IntegerToString(kind);
   if(GlobalVariableCheck(gv) && (double)x.t <= GlobalVariableGet(gv)) return;
   FolderCreate("GoldPro");
   string fn = "GoldPro\\kotak_prediksi.csv";
   bool isNew = !FileIsExist(fn);
   int fh = FileOpen(fn, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ, ';');
   if(fh == INVALID_HANDLE) return;
   FileSeek(fh, 0, SEEK_END);
   if(isNew)
      FileWrite(fh, "waktu_wita", "jenis", "peluang_pct", "hasil", "waktu_hasil_wita", "menit", "harga", "kotak_bawah", "kotak_atas",
                "alasan", "sumber");
   FileWrite(fh, KB_WitaFull(x.t), KB_PJ[kind], DoubleToString(100 * x.p, 1), yes ? "YA" : "TIDAK", KB_WitaFull(rt), x.mo,
             DoubleToString(x.c, 2), DoubleToString(x.lo, 2), DoubleToString(x.hi, 2), x.why, x.live ? "live" : "putar-ulang");
   FileClose(fh);
   GlobalVariableSet(gv, (double)x.t);
  }
void KB_PendAdd(KBPend &a[], datetime t, double p, double c, int mo, string why, int side = 0, datetime tb = 0, double lvl = 0)
  {
   int n = ArraySize(a);
   if(n >= 50) return;
   ArrayResize(a, n + 1);
   a[n].t = t; a[n].p = p; a[n].lo = g_kbLo; a[n].hi = g_kbHi; a[n].c = c; a[n].mo = mo; a[n].side = side; a[n].tb = tb;
   a[n].why = why; a[n].live = g_kbLive; a[n].lvl = lvl;
  }
//--- cek hasil prediksi pecah 5 mnt (close di luar dinding saat prediksi dalam 5 candle), urut dibuat
void KB_PBResolve(datetime t, double c)
  {
   int n = ArraySize(g_kbPend), w = 0;
   for(int i = 0; i < n; i++)
     {
      bool out = (c > g_kbPend[i].hi || c < g_kbPend[i].lo);
      if(t <= g_kbPend[i].t || (!out && t < g_kbPend[i].t + 5 * 60)) { if(w != i) g_kbPend[w] = g_kbPend[i]; w++; continue; }
      KB_PredLog(0, g_kbPend[i], out, t);
     }
   ArrayResize(g_kbPend, w);
  }
void KB_PBUpdate(datetime t, double h, double l, double c)
  {
   g_kbPB = KB_PBreak(t, h, l, c, g_kbPBWhy); g_kbPBT = t;
   if(g_kbPB < 0) return;
   //--- Telegram: pecah 5 mnt >= 50% (bukan candle lahir / candle yang sudah membuat target; jeda 15 mnt)
   if(g_kbPB >= 0.5 && t > g_kbStart && g_kbTgMadeT != t && t - g_kbAlertPB >= 15 * 60)
     {
      g_kbAlertPB = t;
      KB_Out(t, "PECAH", StringFormat("Pecah 5 mnt %d%%%s | harga %s = %d%% kotak %s", KB_Pct(g_kbPB), g_kbPBWhy == "" ? "" : " | " + g_kbPBWhy,
                                      KB_Px(c), KB_Pct((c - g_kbLo) / MathMax(g_kbHi - g_kbLo, _Point)), KB_Rng()) + KB_AlNote(0));
     }
   KB_PendAdd(g_kbPend, t, g_kbPB, c, (int)((t - g_kbStart) / 60), g_kbPBWhy);
  }

//--- KEMBALI 5 MNT: candle t close DI LUAR kotak (sisi g_kbBrkSide). Dihitung tiap candle M1 di luar, mulai candle tembus.
double KB_InterpB(double x)
  {
   if(x <= KB_CALB_X[0]) return KB_CALB_Y[0];
   for(int i = 1; i < KB_NCALB; i++)
      if(x <= KB_CALB_X[i]) return KB_CALB_Y[i - 1] + (KB_CALB_Y[i] - KB_CALB_Y[i - 1]) * (x - KB_CALB_X[i - 1]) / (KB_CALB_X[i] - KB_CALB_X[i - 1]);
   return KB_CALB_Y[KB_NCALB - 1];
  }
double KB_PKBack(datetime t, double h, double l, double c, string &why)
  {
   why = "";
   double wd = g_kbHi - g_kbLo;
   if(wd <= 0 || g_kbBrkSide == 0) return -1;
   int s = g_kbBrkSide, mo = (int)((t - g_kbBrkT) / 60);
   if(mo < 0 || mo >= 60) return -1;
   int mob = (mo < 1) ? 0 : ((mo < 2) ? 1 : ((mo < 3) ? 2 : ((mo < 5) ? 3 : ((mo < 10) ? 4 : ((mo < 15) ? 5 : ((mo < 30) ? 6 : 7))))));
   double d = ((s > 0) ? c - g_kbHi : g_kbLo - c) / wd;
   if(d <= 0) return -1;
   int db = (d < 0.1) ? 0 : ((d < 0.25) ? 1 : ((d < 0.5) ? 2 : ((d < 1) ? 3 : 4)));
   double rat = d / MathMax(g_kbMaxOut / wd, 1e-9);
   int rb = (rat < 0.5) ? 0 : ((rat < 0.8) ? 1 : 2);
   bool pkb = (s > 0) ? (l <= g_kbHi) : (h >= g_kbLo);                     // sumbu masuk lagi ke kotak, close tetap di luar
   g_kbPKpkb = pkb; g_kbPKd = d;
   int ni = KB_NewsIn(t + 60, t + 5 * 60);
   bool ny830 = false;
   for(int m = 1; m <= 5; m++)
     {
      MqlDateTime e;
      TimeToStruct(GP_UTCToET(GP_ServerToUTC(t + m * 60)), e);
      if(e.hour * 60 + e.min == 510) ny830 = true;
     }
   int hr = KB_HourWITA(t), nb = MathMin(g_kbNBrk, 3);
   int wb = (g_kbWrel < 0.55) ? 0 : ((g_kbWrel < 0.75) ? 1 : ((g_kbWrel < 0.9) ? 2 : 3));
   double z = KB_B_C[mob * 5 + db] + KB_B_R[rb] + (pkb ? KB_B_PKB : 0) + (ni >= 0 ? KB_B_NEWS : 0) + (ny830 ? KB_B_NY830 : 0)
              + KB_B_HR[hr] + KB_B_NB[nb] + KB_B_W[wb] + (s < 0 ? KB_B_DN : 0);
   double p = KB_InterpB(1.0 / (1.0 + MathExp(-z)));
   //--- alasan utama (maks 2)
   if(pkb) why = "colek " + KB_wall(s) + " dari luar";
   else if(db == 0) why = "dekat " + KB_wall(s);
   else if(db >= 3) why = "jauh dari " + KB_wall(s);
   if(rb == 0 && StringFind(why, "colek") < 0) why += (why == "" ? "" : ", ") + "sudah balik separuh";
   if(ni >= 0 && StringFind(why, ",") < 0) why += (why == "" ? "" : ", ") + "berita " + GP_LocalTime(g_kbNewsT[ni]);
   if(mob >= 6 && StringFind(why, ",") < 0) why += (why == "" ? "" : ", ") + "lama di luar";
   return p;
  }
void KB_PKResolve(datetime t, double c)
  {
   int n = ArraySize(g_kbPendK), w = 0;
   for(int i = 0; i < n; i++)
     {
      bool in = (c <= g_kbPendK[i].hi && c >= g_kbPendK[i].lo);
      if(t <= g_kbPendK[i].t || (!in && t < g_kbPendK[i].t + 5 * 60)) { if(w != i) g_kbPendK[w] = g_kbPendK[i]; w++; continue; }
      KB_PredLog(1, g_kbPendK[i], in, t);
     }
   ArrayResize(g_kbPendK, w);
  }
//--- TEMBUS SUNGGUHAN: YA = 60 mnt terus close di luar dinding yang sama sejak candle tembus (= mesin kotak); TIDAK = close kembali
//    ke dalam / loncat ke sisi seberang. Dinding = saat prediksi (tetap dicek walau kotak diganti kotak baru).
void KB_H60Resolve(datetime t, double c)
  {
   int n = ArraySize(g_kbPendH), w = 0;
   for(int i = 0; i < n; i++)
     {
      bool same = (g_kbPendH[i].side > 0) ? c > g_kbPendH[i].hi : c < g_kbPendH[i].lo;
      bool yes = same && t - g_kbPendH[i].tb >= 3600;
      if(t <= g_kbPendH[i].t || (same && !yes)) { if(w != i) g_kbPendH[w] = g_kbPendH[i]; w++; continue; }
      KB_PredLog(2, g_kbPendH[i], yes, t);
     }
   ArrayResize(g_kbPendH, w);
  }
//--- DINDING LAMA: YA = high / low menyentuh dinding kotak lama dalam 4 jam sesudah kotak baru lahir (= consol_map.py), TIDAK = lewat 4 jam
void KB_OldResolve(datetime t, double h, double l)
  {
   int n = ArraySize(g_kbPendO), w = 0;
   for(int i = 0; i < n; i++)
     {
      bool in4 = t > g_kbPendO[i].t && t - g_kbPendO[i].t < 240 * 60;
      bool hit = in4 && ((g_kbPendO[i].side > 0) ? l <= g_kbPendO[i].lvl : h >= g_kbPendO[i].lvl);
      if(!hit && (t <= g_kbPendO[i].t || in4)) { if(w != i) g_kbPendO[w] = g_kbPendO[i]; w++; continue; }
      if(hit && g_kbPendO[i].t == g_kbOldT0) g_kbOldHit = t;
      KB_PredLog(3, g_kbPendO[i], hit, t);
     }
   ArrayResize(g_kbPendO, w);
  }
void KB_PKUpdate(datetime t, double h, double l, double c)
  {
   g_kbPK = KB_PKBack(t, h, l, c, g_kbPKWhy); g_kbPKT = t;
   if(g_kbPK < 0) return;
   //--- Telegram: kembali 5 mnt >= 50% sesudah candle tembus (candle tembus sudah dikirim dgn pesan TEMBUS; jeda 10 mnt)
   if(g_kbPK >= 0.5 && t > g_kbBrkT && t - g_kbAlertPK >= 10 * 60)
     {
      g_kbAlertPK = t;
      KB_Out(t, "BACKP", StringFormat("Kembali ke kotak 5 mnt %d%%%s | harga %s ($%.2f dari %s)", KB_Pct(g_kbPK),
                                      g_kbPKWhy == "" ? "" : " | " + g_kbPKWhy, KB_Px(c), g_kbPKd * (g_kbHi - g_kbLo), KB_wall(g_kbBrkSide))
                         + (g_kbPKpkb ? StringFormat("^Colek dari luar: masuk & bertahan 10 mnt %d%%", KB_PKO_IN[KB_Bin5(g_kbPKd)]) : "")
                         + KB_AlNote(1));
     }
   KB_PendAdd(g_kbPendK, t, g_kbPK, c, (int)((t - g_kbBrkT) / 60), g_kbPKWhy, g_kbBrkSide, g_kbBrkT);
  }
//--- peluang TEMBUS SUNGGUHAN yang tampil di dashboard (KB_H60P) dicatat di menit 0 / 15 / 30 / 45 di luar (sekali tiap menit itu)
void KB_H60Add(datetime t, double c, int mins)
  {
   if(g_kbPK < 0 || mins >= 60) return;
   int m = (mins >= 45) ? 3 : ((mins >= 30) ? 2 : ((mins >= 15) ? 1 : 0));
   if(((g_kbH60Lg >> m) & 1) != 0) return;
   g_kbH60Lg |= (1 << (m + 1)) - 1;                                       // menit yang terlewat (celah data) tidak dicatat belakangan
   KB_PendAdd(g_kbPendH, t, KB_H60P(mins, g_kbPKd, t) / 100.0, c, mins, StringFormat("jarak %.2f lebar v2", g_kbPKd), g_kbBrkSide, g_kbBrkT);
  }

//--- teks cerita colek (mx = ekor colek terakhir, nb0 = 1 bila candle berikut inside bar)
string KB_PokeTxt(const KBEvent &e)
  {
   if(e.c1 + e.c5 == 1)
     {
      string tn = (e.tf == 1) ? "M1" : "M5";
      return StringFormat("COLEK %s (candle %s lewat %s lalu close balik ke dalam, ekor %d%%%s). Biasanya dikocok ~%d mnt, lalu %s "
                          "ditembus juga (~%d%%).", KB_Wall(e.side), tn, KB_wall(e.side), KB_Pct(e.mx),
                          e.nb0 == 1 ? ", lalu inside bar" : "", (e.tf == 1) ? 4 : 8, KB_wall(e.side),
                          KB_PokeSame(e.tf, e.nb0 == 1 ? 1 : -1));
     }
   string cn = (e.c1 > 0 && e.c5 > 0) ? StringFormat("M1 %dx, M5 %dx", e.c1, e.c5)
               : (e.c1 > 0 ? StringFormat("M1 %dx", e.c1) : StringFormat("M5 %dx", e.c5));
   string pc = (e.c1 > 0 && e.c5 > 0) ? StringFormat("M1 ~%d%% / M5 ~%d%%", KB_PokeSame(1, -1), KB_PokeSame(5, -1))
               : StringFormat("~%d%%", KB_PokeSame(e.c1 > 0 ? 1 : 5, -1));
   return StringFormat("COLEK %s berulang (%s, terakhir %s, ekor %d%%): %s ditolak berkali-kali, tapi biasanya tetap ditembus (%s).",
                       KB_Wall(e.side), cn, GP_LocalTime(e.t1), KB_Pct(e.mx), KB_wall(e.side), pc);
  }

//--- COLEK: candle yang lewat dinding tapi CLOSE kembali di dalam kotak (q = 0 M1, 1 M5)
void KB_Poke(int q, datetime t, double o, double h, double l, double c)
  {
   //--- candle berikut sesudah colek sebelumnya: inside bar? (tidak lewat high/low candle colek)
   int tf = (q == 0) ? 1 : 5;
   if(g_kbPkSide[q] != 0)
     {
      bool ib = (h <= g_kbPkH[q] && l >= g_kbPkL[q]);
      if(g_kbLastPkTF == tf && g_kbLastPkSide == g_kbPkSide[q]) g_kbLastPkIB = ib ? 1 : 0;
      int s = g_kbPkSide[q], n = ArraySize(g_kbEv) - 1;
      if(ib && n >= 0 && g_kbEv[n].kind == 3 && g_kbEv[n].side == s)
        {
         if(g_kbEv[n].c1 + g_kbEv[n].c5 == 1 && g_kbEv[n].tf == tf)        // inside bar masuk ke cerita colek-nya
           { g_kbEv[n].nb0 = 1; g_kbEv[n].txt = KB_PokeTxt(g_kbEv[n]); }
        }                                                                    // (colek berulang: cukup di baris colek dashboard)
      else if(ib)
         KB_Event(t, StringFormat("INSIDE BAR %s sesudah colek %s (candle berikut tidak lewat high/low candle colek): "
                                  "%s tetap ditembus ~%d%%.", q == 0 ? "M1" : "M5", KB_wall(s), KB_wall(s), KB_PokeSame(tf, 1)), clrSilver);
      g_kbPkSide[q] = 0;
     }
   bool top = (h > g_kbHi), bot = (l < g_kbLo);
   if(top && bot) { top = (h - g_kbHi) >= (g_kbLo - l); bot = !top; }
   if(!top && !bot) return;
   int side = top ? 1 : -1;
   double rg = MathMax(h - l, _Point);
   double wick = top ? (h - MathMax(o, c)) / rg : (MathMin(o, c) - l) / rg;
   g_kbPkSide[q] = side; g_kbPkH[q] = h; g_kbPkL[q] = l;
   g_kbLastPkSide = side; g_kbLastPkTF = tf; g_kbLastPkT = t; g_kbLastPkWick = wick; g_kbLastPkIB = -1;
   //--- colek beruntun di dinding yang sama, M1 & M5 (<= 15 mnt, tanpa cerita lain di antaranya) -> satu cerita dengan hitungan.
   //    Waktu cerita M5 = candle M1 penutupnya (urutan cerita tetap); waktu candle M5 sendiri ada di baris colek dashboard.
   datetime te = (q == 0) ? t : t + 240;
   int n = ArraySize(g_kbEv) - 1;
   if(!(n >= 0 && g_kbEv[n].kind == 3 && g_kbEv[n].side == side && te - g_kbEv[n].t1 <= 15 * 60))
      n = KB_Event(te, "", top ? clrDeepSkyBlue : clrOrange, 3, side);
   if(q == 0) g_kbEv[n].c1++; else g_kbEv[n].c5++;
   g_kbEv[n].tf = tf; g_kbEv[n].t1 = te; g_kbEv[n].mx = wick; g_kbEv[n].nb0 = 0;
   g_kbEv[n].txt = KB_PokeTxt(g_kbEv[n]);
  }

//--- PEMBERITAHUAN PERGANTIAN KOTAK (Telegram "SOON"; dashboard membaca keadaan yang sama)
void KB_SoonNew(datetime t)                                                  // kotak baru hampir terbentuk (bisa mengganti kotak ini)
  {
   if(g_kbSoonNew || !KB_NewNear(t)) return;
   g_kbSoonNew = true;
   KB_Out(t, "SOON", StringFormat("Kotak baru bisa segera muncul (mengganti kotak %s): rentang 60 mnt terakhir $%.1f, kotak baru bila "
                                  "<= $%.1f", GP_LocalTime(g_kbStart), g_kbR60, g_kbThrUsd));
  }
void KB_SoonIn(datetime t)                                                   // harga di dalam: 10 mnt sebelum umur 4 jam
  {
   int age = (int)((t - g_kbStart) / 60);
   if(!g_kbSoonEnd && age >= 230 && age < 240)
     {
      g_kbSoonEnd = true;
      KB_Out(t, "SOON", StringFormat("Kotak %s (%s) selesai %s (%d mnt lagi, umur 4 jam) bila harga tetap di dalam | sesudahnya: %s",
                                     GP_LocalTime(g_kbStart), KB_Rng(), GP_LocalTime(g_kbStart + 240 * 60), 240 - age, KB_After()));
     }
   KB_SoonNew(t);
  }
void KB_SoonOut(datetime t, int mins)                                        // harga di luar: menit 30 & 45 -> hitung mundur tembus sungguhan
  {
   KB_SoonNew(t);
   if(g_kbPK < 0) return;
   if((mins >= 30 && !g_kbSoon30) || (mins >= 45 && !g_kbSoon45))
     {
      if(mins >= 45) g_kbSoon45 = true;
      g_kbSoon30 = true;
      KB_Out(t, "SOON", StringFormat("%d mnt di luar %s: TEMBUS SUNGGUHAN %s bila bertahan (%d mnt lagi) | peluang %d%% | harga $%.2f dari %s",
                                     mins, KB_wall(g_kbBrkSide), GP_LocalTime(g_kbBrkT + 3600), 60 - mins, KB_H60P(mins, g_kbPKd, t),
                                     g_kbPKd * (g_kbHi - g_kbLo), KB_wall(g_kbBrkSide)) + KB_AlNote(2));
     }
  }

//--- satu candle M1 yang sudah close (r[i]) -> mesin keadaan. Dipanggil berurutan dari lama ke baru.
void KB_Bar(const MqlRates &r[], int i, double adr, bool warm)
  {
   datetime t = r[i].time;
   //--- 1) kotak baru? (definisi riset: 60 candle M1 tanpa celah, rentang <= P20 slot NY, 60 mnt sebelumnya tanpa kotak)
   bool cons = false;
   double h60 = 0, l60 = 0, wrel = 1;
   if(i >= 59 && r[i].time - r[i - 59].time == 59 * 60 && adr > 0)
     {
      h60 = r[i].high; l60 = r[i].low;
      for(int j = i - 59; j < i; j++) { h60 = MathMax(h60, r[j].high); l60 = MathMin(l60, r[j].low); }
      MqlDateTime et;
      TimeToStruct(GP_UTCToET(GP_ServerToUTC(t)), et);
      double thr = GDM::CS_P20_60[(et.hour * 60 + et.min) / 30];
      cons = ((h60 - l60) / adr <= thr);
      wrel = (h60 - l60) / adr / thr;
      g_kbR60 = h60 - l60; g_kbThrUsd = thr * adr;
     }
   else g_kbR60 = -1;
   bool fresh = cons && t - g_kbLastCons > 3600;
   if(cons) g_kbLastCons = t;
   g_kbConsNow = cons;
   if(warm) return;                                                      // pemanasan putar ulang: hanya catat kotak terakhir
   KB_TgResolve(t, r[i].high, r[i].low, r[i].close);                     // target yang menunggu: KENA / TIDAK dengan candle ini
   KB_PBResolve(t, r[i].close);                                          // prediksi "pecah 5 mnt" yang menunggu hasil
   KB_PKResolve(t, r[i].close);                                          // prediksi "kembali 5 mnt" yang menunggu hasil
   KB_H60Resolve(t, r[i].close);                                         // prediksi "tembus sungguhan" yang menunggu hasil
   KB_OldResolve(t, r[i].high, r[i].low);                                // prediksi "dinding kotak lama tersentuh lagi 4 jam"
   TB_Bar(t, r[i].high, r[i].low, r[i].close);                           // Tembus Balik: KENA tengah / BATAL 1W / HABIS 4 jam
   //--- kotak BARU (episode riset) atau DIPERBARUI (tidak ada kotak hidup, tapi 60 mnt terakhir masih sempit = sampel consol_edge)
   if(fresh || (g_kbSt == 0 && cons))
     {
      if(g_kbSt != 0) KB_OutEnd(t, "diganti kotak sideway baru");
      g_kbSt = 1; g_kbHi = h60; g_kbLo = l60; g_kbT0 = r[i - 59].time; g_kbStart = t; g_kbFresh = fresh; g_kbNBrk = 0; g_kbWrel = wrel;
      g_kbPkSide[0] = 0; g_kbPkSide[1] = 0; g_kbLastPkSide = 0; g_kbBrkT = 0; g_kbBack = false; g_kbTgLast = 0;
      g_kbBoxN = 0; g_kbBoxK = 0; g_kbBoxE = 0;
      g_kbSoonEnd = false; g_kbSoonNew = false; g_kbSoon30 = false; g_kbSoon45 = false;
      if(fresh)
         KB_Event(t, StringFormat("KOTAK SIDEWAY BARU %s (lebar $%.1f): 60 mnt terakhir harga sempit. Arah keluar nanti ditentukan "
                                  "posisi harga, bukan tren.", KB_Rng(), h60 - l60), clrAqua);
      else
         KB_Event(t, StringFormat("KOTAK DIPERBARUI %s (lebar $%.1f): harga masih sideway, dinding = high/low 60 mnt terakhir.",
                                  KB_Rng(), h60 - l60), clrAqua);
      KB_PBUpdate(t, r[i].high, r[i].low, r[i].close);
      //--- kotak pertama sesudah TEMBUS SUNGGUHAN (<= 8 jam): peluang dinding lama tersentuh lagi dalam 4 jam
      g_kbOldP = -1; g_kbOldHit = 0;
      if(g_kbRealT > 0 && t - g_kbRealT <= 480 * 60)
        {
         g_kbOldW = g_kbRealW; g_kbOldS = g_kbRealS; g_kbOldT0 = t;
         g_kbOldP = KB_OldP(((h60 + l60) / 2 - g_kbRealW) * g_kbRealS / adr);
         KB_PendAdd(g_kbPendO, t, g_kbOldP / 100.0, r[i].close, 0, StringFormat("dinding lama %s (%s)", KB_Px(g_kbOldW), KB_wall(g_kbOldS)),
                    g_kbOldS, g_kbRealT, g_kbOldW);
        }
      g_kbRealT = 0;
      double p0 = MathMax(0.0, MathMin(1.0, (r[i].close - g_kbLo) / (g_kbHi - g_kbLo)));
      int pu0 = KB_Pct(KB_CEX[(int)MathMin(9, MathFloor(p0 * 10))]);
      KB_Out(t, "BOX", StringFormat("KOTAK %s %s ($%.1f)^harga %d%% kotak | keluar %s dulu %d%% | pecah 5 mnt %d%%",
                                    fresh ? "BARU" : "DIPERBARUI", KB_Rng(), h60 - l60, KB_Pct(p0), pu0 >= 50 ? "ATAP" : "LANTAI",
                                    pu0 >= 50 ? pu0 : 100 - pu0, KB_Pct(MathMax(g_kbPB, 0.0)))
                       + (g_kbOldP >= 0 ? StringFormat("^Dinding lama %s (%s kotak sebelumnya) tersentuh lagi s/d %s: %d%%",
                                                       KB_Px(g_kbOldW), KB_wall(g_kbOldS), GP_LocalTime(t + 240 * 60), g_kbOldP) : ""));
      return;
     }
   if(g_kbSt == 0) return;
   double o = r[i].open, h = r[i].high, l = r[i].low, c = r[i].close;
   bool inside = (c <= g_kbHi && c >= g_kbLo);
   //--- 2) harga di dalam kotak: tembus / colek / umur kotak habis
   if(g_kbSt == 1)
     {
      if(!inside)                                                           // TEMBUS = candle M1 close di luar dinding
        {
         g_kbSt = 2; g_kbNBrk++; g_kbBrkSide = (c > g_kbHi) ? 1 : -1; g_kbBrkT = t; g_kbBack = false; g_kbHold15 = false;
         g_kbSoon30 = false; g_kbSoon45 = false; g_kbH60Lg = 0;
         g_kbBrkHr = KB_HourWITA(t);
         g_kbMaxOut = (g_kbBrkSide > 0) ? h - g_kbHi : g_kbLo - l;
         g_kbPkSide[0] = 0; g_kbPkSide[1] = 0;
         KB_Event(t, StringFormat("TEMBUS %s%s! Candle M1 close %s di luar %s. Biasanya dorongan ~$%.1f lewat dinding, lalu 3 dari 4 "
                                  "close balik ke dalam dalam 15 mnt.", g_kbBrkSide > 0 ? "ATAS" : "BAWAH",
                                  g_kbNBrk > 1 ? StringFormat(" (ke-%d)", g_kbNBrk) : "", KB_Px(c), KB_wall(g_kbBrkSide),
                                  KB_OVW[g_kbBrkHr] * (g_kbHi - g_kbLo)), g_kbBrkSide > 0 ? clrLime : clrTomato, 2, g_kbBrkSide);
         KB_PKUpdate(t, h, l, c);                                          // menit 0 = candle tembus
         KB_H60Add(t, c, 0);
         KB_TgBreak(t, g_kbBrkSide, g_kbBrkSide > 0 ? h : l, g_kbPK >= 0 ? KB_Pct(g_kbPK) : 59);
         KB_OutBreak(t, c, false);
         TB_Break(r, i, g_kbBrkSide, g_kbHi, g_kbLo);                      // Tembus Balik (jam positif saja)
         return;
        }
      KB_Poke(0, t, o, h, l, c);
      //--- candle M5 (dari 5 candle M1, sama dengan riset) yang tutup di candle ini, seluruhnya sesudah kotak lahir & di dalam kotak
      MqlDateTime d;
      TimeToStruct(t, d);
      if(d.min % 5 == 4 && i >= 4 && t - r[i - 4].time == 240 && r[i - 4].time > g_kbStart && r[i - 4].time > g_kbBrkT)
        {
         double h5 = r[i - 4].high, l5 = r[i - 4].low;
         bool in5 = true;
         for(int j = i - 4; j <= i; j++)
           {
            h5 = MathMax(h5, r[j].high); l5 = MathMin(l5, r[j].low);
            if(r[j].close > g_kbHi || r[j].close < g_kbLo) in5 = false;
           }
         if(in5) KB_Poke(1, r[i - 4].time, r[i - 4].open, h5, l5, c);
        }
      KB_TgTrigger(t, h, l, c);
      KB_PBUpdate(t, h, l, c);
      KB_SoonIn(t);
      if(t - g_kbStart >= 240 * 60)
        {
         KB_Event(t, StringFormat("Kotak %s sudah 4 jam%s - pengawasan selesai.", KB_Rng(),
                                  g_kbNBrk > 0 ? StringFormat(" (ditembus %d kali, semua kembali)", g_kbNBrk) : " tanpa tembus"), clrDimGray);
         KB_OutEnd(t, g_kbNBrk > 0 ? StringFormat("umur 4 jam (ditembus %d kali, semua kembali)", g_kbNBrk) : "umur 4 jam tanpa tembus");
         g_kbSt = 0;
        }
      return;
     }
   //--- 3) harga di luar kotak: berapa lama bertahan, seberapa jauh; kembali = kotak tetap hidup
   int mins = (int)((t - g_kbBrkT) / 60);
   if(inside)
     {
      g_kbSt = 1; g_kbBack = true; g_kbBackT = t; g_kbBackSide = g_kbBrkSide;
      g_kbBackDepth = ((g_kbBrkSide > 0) ? g_kbHi - c : c - g_kbLo) / MathMax(g_kbHi - g_kbLo, _Point);
      int b5 = KB_Bin5(g_kbBackDepth);
      KB_Out(t, "BACK", StringFormat("MASUK LAGI ke kotak | candle %s tutup %s^di luar %s %d mnt, maks lewat $%.2f^bertahan di dalam 10 mnt "
                                     "%d%% | sampai tengah %d%%", GP_LocalTime(t), KB_Px(c), KB_wall(g_kbBrkSide), mins, g_kbMaxOut,
                                     KB_RE_STAY[b5], KB_RE_MID[b5]));
      if(!KB_QuickBack(t, mins))
         KB_Event(t, StringFormat("KEMBALI ke dalam kotak: bertahan di luar %d mnt, sempat lewat dinding $%.2f. Tembusan GAGAL - kotak "
                                  "masih berlaku.", mins, g_kbMaxOut), clrYellow);
      KB_TgTrigger(t, h, l, c);                                            // candle kembali = candle di dalam (riset ikut menghitungnya)
      KB_PBUpdate(t, h, l, c);
      KB_SoonIn(t);
      if(t - g_kbStart >= 240 * 60)
        {
         KB_Event(t, StringFormat("Kotak %s sudah 4 jam (ditembus %d kali, semua kembali) - pengawasan selesai.", KB_Rng(), g_kbNBrk),
                  clrDimGray);
         KB_OutEnd(t, StringFormat("umur 4 jam (ditembus %d kali, semua kembali)", g_kbNBrk));
         g_kbSt = 0;
        }
      return;
     }
   if((c > g_kbHi && g_kbBrkSide < 0) || (c < g_kbLo && g_kbBrkSide > 0))   // loncat ke sisi seberang tanpa close di dalam
     {
      g_kbBrkSide = -g_kbBrkSide; g_kbNBrk++; g_kbBrkT = t; g_kbHold15 = false; g_kbBrkHr = KB_HourWITA(t);
      g_kbSoon30 = false; g_kbSoon45 = false; g_kbH60Lg = 0;
      g_kbMaxOut = 0; mins = 0;
      KB_Event(t, StringFormat("TEMBUS %s (ke-%d) langsung dari sisi seberang - candle M1 close %s.", g_kbBrkSide > 0 ? "ATAS" : "BAWAH",
                               g_kbNBrk, KB_Px(c)), g_kbBrkSide > 0 ? clrLime : clrTomato, 2, g_kbBrkSide);
      g_kbMaxOut = (g_kbBrkSide > 0) ? h - g_kbHi : g_kbLo - l;
      string wj;
      double pj = KB_PKBack(t, h, l, c, wj);                               // yakin awal target kembali (candle tembus)
      KB_TgBreak(t, g_kbBrkSide, g_kbBrkSide > 0 ? h : l, pj >= 0 ? KB_Pct(pj) : 59);
      KB_OutBreak(t, c, true);
      TB_Break(r, i, g_kbBrkSide, g_kbHi, g_kbLo);                         // Tembus Balik (jam positif saja)
     }
   g_kbMaxOut = MathMax(g_kbMaxOut, (g_kbBrkSide > 0) ? h - g_kbHi : g_kbLo - l);
   KB_PKUpdate(t, h, l, c);                                                // tiap menit di luar: peluang kembali 5 mnt
   KB_H60Add(t, c, mins);                                                  // menit 0 (loncat) / 15 / 30 / 45: peluang tembus sungguhan
   KB_SoonOut(t, mins);
   if(mins >= 15 && !g_kbHold15)
     {
      g_kbHold15 = true;
      KB_Event(t, StringFormat("BERTAHAN 15 mnt di luar %s - termasuk tembusan kuat (hanya ~1 dari 4). Lewat dinding maks $%.2f.",
                               KB_wall(g_kbBrkSide), g_kbMaxOut), clrLime);
      KB_Out(t, "HOLD", StringFormat("BERTAHAN 15 mnt di luar %s^maks lewat $%.2f | hanya ~1 dari 4 tembusan bertahan; separuhnya sampai 1 jam",
                                     KB_wall(g_kbBrkSide), g_kbMaxOut));
     }
   if(mins >= 60)
     {
      KB_OutEnd(t, StringFormat("TEMBUS SUNGGUHAN %s (60 mnt di luar %s, maks lewat $%.2f)", g_kbBrkSide > 0 ? "ATAS" : "BAWAH",
                                KB_wall(g_kbBrkSide), g_kbMaxOut));
      KB_Event(t, StringFormat("TEMBUS SUNGGUHAN: 60 mnt di luar %s (hanya ~13%% tembusan), lewat maks $%.2f. Kotak %s selesai.",
                               KB_wall(g_kbBrkSide), g_kbMaxOut, KB_Rng()), g_kbBrkSide > 0 ? clrLime : clrTomato);
      g_kbRealT = t; g_kbRealW = (g_kbBrkSide > 0) ? g_kbHi : g_kbLo; g_kbRealS = g_kbBrkSide;   // untuk kotak berikutnya
      g_kbSt = 0;
     }
  }

//--- jalankan mesin untuk candle M1 baru. Pertama kali: putar ulang ~10 jam agar dashboard langsung terisi.
void KB_Machine()
  {
   double adr = GDM::g_pAdr;
   if(adr <= 0) return;
   datetime last = iTime(_Symbol, PERIOD_M1, 1);
   if(last == 0 || last == g_kbLastBar) return;
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_M1, 1, 600, r);                     // candle M1 yang sudah close, lama -> baru
   if(n < 120) return;
   bool replay = (g_kbLastBar == 0);
   g_kbLive = !replay;                                                   // dicatat di CSV: "live" / "putar-ulang"
   if(replay) KB_NewsLoad(r[0].time, TimeCurrent() + 86400);            // berita USD HIGH untuk putar ulang & ke depan
   else if(TimeCurrent() - g_kbNewsLoad > 600) KB_NewsLoad(TimeCurrent() - 12 * 3600, TimeCurrent() + 86400);
   for(int i = (replay ? 59 : 0); i < n; i++)
     {
      if(r[i].time <= g_kbLastBar) continue;
      KB_Bar(r, i, adr, replay && i < 120);                               // 60 candle pertama putar ulang = pemanasan
     }
   g_kbLastBar = r[n - 1].time;
   g_kbLive = true;
  }

//--- HITUNGAN KUMULATIF DARI CSV (9 Okt 2026, usulan no. 3: "DAFTAR sejak ..." dulu hilang tiap ganti TF / muat ulang) & RAPOR
//    HARIAN TELEGRAM (usulan no. 2, sekaligus tanda sistem hidup). kotak_target.csv & kotak_prediksi.csv dibaca bertahap (hanya
//    baris baru, tiap 5 dtk); tiap baris dihitung ke: total, total live, dan hari dagang (jam server 00:00 = ~05:00 WITA) dari
//    WAKTU HASIL -> rapor hari kemarin lengkap saat dikirim. Kotak lahir = prediksi pecah menit 0; tembusan = prediksi sungguhan
//    menit 0 (YA = tembus sungguhan).
#define KB_ND  8                              // hari dagang yang disimpan (cincin) untuk rapor
#define KB_NSC 10                             // lingkup: 0 total, 1 total live, 2..9 hari (slot cincin)
int      g_kbSTN[KB_NSC * 5], g_kbSTK[KB_NSC * 5];   // target selesai / KENA [lingkup][jenis: 0 semua, 1 colek, 2 mepet, 3 kembali, 4 lanjut]
double   g_kbSTE[KB_NSC * 5];                        // harapan (jumlah yakin)
double   g_kbSTV[KB_NSC * 5];                        // jumlah p(1-p) = ragam wajar (alarm kalibrasi)
int      g_kbSPN[KB_NSC * 12], g_kbSPY[KB_NSC * 12]; // prediksi [lingkup][0 pecah5 / 1 kembali5 / 2 sungguhan60][0 semua / 1 < 20% / 2 20-50% / 3 >= 50%]
double   g_kbSPS[KB_NSC * 12], g_kbSPV[KB_NSC * 12];
int      g_kbSBox[KB_NSC], g_kbSBrk[KB_NSC], g_kbSReal[KB_NSC];
datetime g_kbSDay[KB_ND];
datetime g_kbSFirst[2] = {0, 0};              // baris pertama tiap file (jam server)
long     g_kbFPos[2] = {0, 0};
uint     g_kbSTick = 0;
datetime g_kbRapChk = 0;

void KB_SReset()
  {
   ArrayInitialize(g_kbSTN, 0); ArrayInitialize(g_kbSTK, 0); ArrayInitialize(g_kbSTE, 0); ArrayInitialize(g_kbSTV, 0);
   ArrayInitialize(g_kbSPN, 0); ArrayInitialize(g_kbSPY, 0); ArrayInitialize(g_kbSPS, 0); ArrayInitialize(g_kbSPV, 0);
   ArrayInitialize(g_kbSBox, 0); ArrayInitialize(g_kbSBrk, 0); ArrayInitialize(g_kbSReal, 0);
   ArrayInitialize(g_kbSDay, 0);
   g_kbSFirst[0] = 0; g_kbSFirst[1] = 0; g_kbFPos[0] = 0; g_kbFPos[1] = 0;
  }
//--- hari dagang -> lingkup (2..); hari lebih baru menimpa slot cincinnya; -1 bila lebih lama dari cincin
int KB_SSlot(datetime day, bool make)
  {
   int s = (int)((day / 86400) % KB_ND), sc = 2 + s;
   if(g_kbSDay[s] == day) return sc;
   if(!make || g_kbSDay[s] > day) return -1;
   g_kbSDay[s] = day;
   for(int j = 0; j < 5; j++) { g_kbSTN[sc * 5 + j] = 0; g_kbSTK[sc * 5 + j] = 0; g_kbSTE[sc * 5 + j] = 0; g_kbSTV[sc * 5 + j] = 0; }
   for(int j = 0; j < 12; j++) { g_kbSPN[sc * 12 + j] = 0; g_kbSPY[sc * 12 + j] = 0; g_kbSPS[sc * 12 + j] = 0; g_kbSPV[sc * 12 + j] = 0; }
   g_kbSBox[sc] = 0; g_kbSBrk[sc] = 0; g_kbSReal[sc] = 0;
   return sc;
  }
datetime KB_Day(datetime server) { return server - server % 86400; }
//--- "2026.10.09 06:08" (WITA) -> jam server; 0 bila bukan waktu (baris judul / rusak)
datetime KB_WitaToServer(string s)
  {
   if(StringLen(s) != 16 || StringGetCharacter(s, 4) != '.') return 0;
   datetime l = StringToTime(s);
   return (l <= 0) ? 0 : GP_UTCToServer(l - InpLocalUTCOffset * 3600);
  }
void KB_SRow(int f, string &a[], int k)
  {
   datetime t0 = KB_WitaToServer(a[0]), rt = KB_WitaToServer(a[f == 0 ? 5 : 4]);
   if(t0 == 0 || rt == 0) return;
   if(g_kbSFirst[f] == 0 || t0 < g_kbSFirst[f]) g_kbSFirst[f] = t0;
   int sc[3];
   sc[0] = 0; sc[1] = (a[k - 1] == "live") ? 1 : -1; sc[2] = KB_SSlot(KB_Day(rt), true);
   if(f == 0)
     {
      int ty = (StringFind(a[1], "colek") == 0) ? 1 : ((StringFind(a[1], "mepet") == 0) ? 2 : ((StringFind(a[2], "kembali") == 0) ? 3 : 4));
      bool kn = (a[4] == "KENA");
      double p = StringToDouble(a[3]) / 100.0;
      for(int z = 0; z < 3; z++)
        {
         if(sc[z] < 0) continue;
         g_kbSTN[sc[z] * 5]++; g_kbSTN[sc[z] * 5 + ty]++; g_kbSTE[sc[z] * 5] += p; g_kbSTE[sc[z] * 5 + ty] += p;
         g_kbSTV[sc[z] * 5] += p * (1 - p); g_kbSTV[sc[z] * 5 + ty] += p * (1 - p);
         if(kn) { g_kbSTK[sc[z] * 5]++; g_kbSTK[sc[z] * 5 + ty]++; }
        }
      return;
     }
   int kd = (a[1] == "pecah5") ? 0 : ((a[1] == "kembali5") ? 1 : ((a[1] == "sungguhan60") ? 2 : -1));
   if(kd < 0) return;
   double p = StringToDouble(a[2]) / 100.0;
   bool ya = (a[3] == "YA");
   int b = (p < 0.2) ? 1 : ((p < 0.5) ? 2 : 3), mo = (int)StringToInteger(a[5]);
   for(int z = 0; z < 3; z++)
     {
      if(sc[z] < 0) continue;
      int q = (sc[z] * 3 + kd) * 4;
      g_kbSPN[q]++; g_kbSPN[q + b]++; g_kbSPS[q] += p; g_kbSPS[q + b] += p;
      g_kbSPV[q] += p * (1 - p); g_kbSPV[q + b] += p * (1 - p);
      if(ya) { g_kbSPY[q]++; g_kbSPY[q + b]++; }
      if(kd == 0 && mo == 0) g_kbSBox[sc[z]]++;
      if(kd == 2 && mo == 0) { g_kbSBrk[sc[z]]++; if(ya) g_kbSReal[sc[z]]++; }
     }
  }
//--- baca baris baru file f (0 kotak_target.csv, 1 kotak_prediksi.csv); file mengecil (dihapus / diganti) -> hitung ulang semua
void KB_SRead(int f)
  {
   string fn = (f == 0) ? "GoldPro\\kotak_target.csv" : "GoldPro\\kotak_prediksi.csv";
   if(!FileIsExist(fn)) return;
   long sz = FileGetInteger(fn, FILE_SIZE);
   if(sz <= 0 || sz == g_kbFPos[f]) return;
   if(sz < g_kbFPos[f]) { KB_SReset(); KB_SRead(1 - f); }
   int fh = FileOpen(fn, FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE) return;
   FileSeek(fh, g_kbFPos[f], SEEK_SET);
   int need = (f == 0) ? 9 : 11;
   while(!FileIsEnding(fh))
     {
      string ln = FileReadString(fh), a[];
      bool end = FileIsEnding(fh);
      int k = StringSplit(ln, ';', a);
      if(k < need && end) break;                                         // baris terakhir belum utuh -> baca lagi nanti
      if(k >= need) KB_SRow(f, a, k);
      g_kbFPos[f] = (long)FileTell(fh);
     }
   FileClose(fh);
  }
void KB_SUpdate()
  {
   if(g_kbSTick != 0 && GetTickCount() - g_kbSTick < 5000) return;
   g_kbSTick = GetTickCount();
   KB_SRead(0); KB_SRead(1);
  }
int KB_SToday() { return KB_SSlot(KB_Day(TimeTradeServer()), false); }

string KB_DayTxt(datetime server)
  {
   string mn[12] = {"Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"};
   MqlDateTime d;
   TimeToStruct(GP_UTCToLocal(GP_ServerToUTC(server)), d);
   return IntegerToString(d.day) + " " + mn[d.mon - 1];
  }
//--- "rata2 x% -> nyata y%" prediksi jenis kd lingkup sc (kelompok b: 0 semua, 1 < 20%, 2 20-50%, 3 >= 50%)
string KB_SCal(int sc, int kd, int b, string fmt)
  {
   int q = (sc * 3 + kd) * 4 + b;
   if(g_kbSPN[q] == 0) return "";
   return StringFormat(fmt, g_kbSPN[q], 100 * g_kbSPS[q] / g_kbSPN[q], 100.0 * g_kbSPY[q] / g_kbSPN[q]);
  }
//--- tooltip dashboard: uji maju prediksi jenis kd sejak dicatat
string KB_SCalTip(int kd)
  {
   if(g_kbSPN[kd * 4] == 0) return "\nUji maju: dicatat ke MQL5\\Files\\GoldPro\\kotak_prediksi.csv (belum ada yang selesai).";
   string s = StringFormat("\nUji maju sejak %s %s (tetap walau ganti TF):", KB_DayTxt(g_kbSFirst[1]), GP_LocalTime(g_kbSFirst[1]));
   s += KB_SCal(0, kd, 0, "\n  semua: %d prediksi, rata2 %.1f%% -> nyata %.1f%%");
   string bl[4] = {"", "< 20%%", "20-50%%", ">= 50%%"};                    // (dipakai di dalam format: %% = %)
   for(int b = 1; b < 4; b++) s += KB_SCal(0, kd, b, "\n  " + bl[b] + ": %d, rata2 %.0f%% -> nyata %.0f%%");
   return s;
  }
string KB_STgTxt(int sc, int ty, bool lbl)
  {
   int q = sc * 5 + ty;
   return StringFormat(lbl ? "KENA %d dari %d (harapan %.1f)" : "%d/%d (harapan %.1f)", g_kbSTK[q], g_kbSTN[q], g_kbSTE[q]);
  }

//--- ALARM KALIBRASI + MODE PRESISI (10 Okt 2026, rencana pengerasan no. 4 & 5, pengguna: "tidak usah kita tampilkan jika kurang
//    presisi"). Angka peluang berasal dari uji 2017-26; bila pasar berubah, angka bisa mulai meleset tanpa ketahuan. Tiap menit bot
//    membandingkan angkanya sendiri dengan hasil nyata uji maju 7 hari kalender terakhir (~5 hari dagang, kotak_prediksi.csv &
//    kotak_target.csv, semua chart sama): z = (nyata - harapan) / akar(jumlah p(1-p) x DEFF). DEFF = prediksi beruntun saling
//    tumpang (pecah / kembali 5 mnt tiap menit = 5, sungguhan dicatat 4x per tembusan = 4, target berjarak >= 5 mnt = 1.5) supaya
//    alarm tidak berbunyi karena kebetulan. ALARM bila n cukup (prediksi >= 300, target >= 40), |z| >= 3 DAN selisih >= 5 poin;
//    padam bila |z| < 2 atau selisih < 3 poin. Selama ALARM: angka itu di dashboard diganti "[DICEK] angka x% -> nyata y%", pesan
//    Telegram yang memuat angka itu diberi tanda, & chart utama mengirim pesan ALARM / pulih sekali tiap perubahan.
string KB_AlName[7] = {"Pecah 5 mnt", "Kembali 5 mnt", "Tembus sungguhan", "Target colek", "Target mepet", "Target kembali", "Target lanjut garis"};
double KB_DEFF[7]   = {5, 5, 4, 1.5, 1.5, 1.5, 1.5};
datetime g_kbAlChk = 0;
void KB_CalCheck()
  {
   datetime now = TimeTradeServer();
   if(g_kbAlRun && now - g_kbAlChk < 60) return;
   g_kbAlChk = now; g_kbAlRun = true;
   datetime d0 = KB_Day(now);
   double n[7], y[7], e[7], v[7];
   ArrayInitialize(n, 0); ArrayInitialize(y, 0); ArrayInitialize(e, 0); ArrayInitialize(v, 0);
   for(int s = 0; s < KB_ND; s++)
     {
      if(g_kbSDay[s] == 0 || d0 - g_kbSDay[s] > 7 * 86400) continue;
      int sc = 2 + s;
      for(int kd = 0; kd < 3; kd++)
        {
         int q = (sc * 3 + kd) * 4;
         n[kd] += g_kbSPN[q]; y[kd] += g_kbSPY[q]; e[kd] += g_kbSPS[q]; v[kd] += g_kbSPV[q];
        }
      for(int ty = 1; ty < 5; ty++)
        {
         int q = sc * 5 + ty;
         n[2 + ty] += g_kbSTN[q]; y[2 + ty] += g_kbSTK[q]; e[2 + ty] += g_kbSTE[q]; v[2 + ty] += g_kbSTV[q];
        }
     }
   for(int a = 0; a < 7; a++)
     {
      g_kbAlN[a] = (int)n[a]; g_kbAlE[a] = e[a]; g_kbAlY[a] = y[a];
      double z = (v[a] > 0) ? (y[a] - e[a]) / MathSqrt(v[a] * KB_DEFF[a]) : 0, gap = (n[a] > 0) ? (y[a] - e[a]) / n[a] : 0;
      g_kbAlZ[a] = z;
      int was = g_kbAl[a];
      if(n[a] < (a < 3 ? 300 : 40)) g_kbAl[a] = 0;
      else if(MathAbs(z) >= 3 && MathAbs(gap) >= 0.05) g_kbAl[a] = 1;
      else if(MathAbs(z) < 2 || MathAbs(gap) < 0.03) g_kbAl[a] = 0;
      //--- chart utama: kirim ALARM / pulih sekali tiap perubahan (GV = status terakhir yang sudah dikirim, aman untuk muat ulang)
      string gv = "GP_KBAL_" + IntegerToString(a);
      int sent = GlobalVariableCheck(gv) ? (int)GlobalVariableGet(gv) : 0;
      if(!g_gpMaster || !g_kbLive || g_kbLastBar == 0 || g_kbAl[a] == sent) continue;
      if(g_kbAl[a] == 1)
         KB_Out(g_kbLastBar, "ALARM", StringFormat("ALARM ANGKA: %s 7 hari terakhir angka rata2 %.0f%% -> nyata %.0f%% (%d kali, z %+.1f). "
                                                   "Angka ini disembunyikan di dashboard ([DICEK]) sampai kembali wajar.", KB_AlName[a],
                                                   100 * e[a] / n[a], 100 * y[a] / n[a], (int)n[a], z));
      else
         KB_Out(g_kbLastBar, "ALARM", StringFormat("PULIH: angka %s kembali wajar (7 hari: angka %.0f%% -> nyata %.0f%%). Tampil lagi di dashboard.",
                                                   KB_AlName[a], n[a] > 0 ? 100 * e[a] / n[a] : 0, n[a] > 0 ? 100 * y[a] / n[a] : 0));
      GlobalVariableSet(gv, g_kbAl[a]);
      if(was != g_kbAl[a]) PrintFormat("[GoldPro] kalibrasi %s: %s", KB_AlName[a], g_kbAl[a] == 1 ? "ALARM" : "wajar");
     }
  }
//--- baris dashboard pengganti angka yang sedang ALARM
string KB_AlLine(int a, string label)
  {
   return StringFormat("%s: [DICEK] 7 hr angka %.0f%% -> nyata %.0f%%", label, g_kbAlN[a] > 0 ? 100 * g_kbAlE[a] / g_kbAlN[a] : 0,
                       g_kbAlN[a] > 0 ? 100 * g_kbAlY[a] / g_kbAlN[a] : 0);
  }
string KB_AlTip(int a)
  {
   return StringFormat("MODE PRESISI: angka %s disembunyikan karena uji maju 7 hari terakhir meleset melebihi kebetulan\n"
                       "(%d kali, angka rata2 %.1f%% -> nyata %.1f%%, z %+.1f; batas |z| >= 3 & selisih >= 5 poin). Tampil lagi otomatis\n"
                       "bila kembali wajar. Pesan ALARM / PULIH dikirim ke Telegram.", KB_AlName[a], g_kbAlN[a],
                       g_kbAlN[a] > 0 ? 100 * g_kbAlE[a] / g_kbAlN[a] : 0, g_kbAlN[a] > 0 ? 100 * g_kbAlY[a] / g_kbAlN[a] : 0, g_kbAlZ[a]);
  }
string KB_AlSummary()
  {
   string s = "";
   for(int a = 0; a < 7; a++) if(g_kbAl[a] == 1) s += (s == "" ? "" : ", ") + KB_AlName[a];
   return s;
  }

//--- RAPOR HARIAN: sekali sesudah hari dagang server berganti (~05:02 WITA; Sabtu pagi = rapor Jumat). Hari tanpa catatan (akhir
//    pekan) tidak dikirim. Sekali saja untuk semua chart (GV GP_KBRAP_DAY = hari terakhir yang sudah dirapor).
void KB_Rapor()
  {
   if(!InpKBTelegram || g_kbLastBar == 0 || !g_kbLive || !g_gpMaster) return;
   datetime ts = TimeTradeServer();
   if(ts - g_kbRapChk < 30) return;
   g_kbRapChk = ts;
   datetime d0 = KB_Day(ts), dy = d0 - 86400;
   if(ts - d0 < 120) return;
   string gv = "GP_KBRAP_DAY";
   if(GlobalVariableCheck(gv) && GlobalVariableGet(gv) >= (double)dy) return;
   GlobalVariableSet(gv, (double)dy);
   g_kbSTick = 0; KB_SUpdate();                                          // baris terbaru ikut dihitung
   int sc = KB_SSlot(dy, false);
   if(sc < 0 || (g_kbSTN[sc * 5] == 0 && g_kbSPN[sc * 12] == 0)) return;
   string s = StringFormat("RAPOR HARIAN | %s %s - %s %s WITA", KB_DayTxt(dy), GP_LocalTime(dy), KB_DayTxt(d0), GP_LocalTime(d0));
   //--- catatan baru mulai di tengah hari itu (pertama dipasang) -> jam mulai ditulis agar angka tidak dikira sehari penuh
   string st0 = (g_kbSFirst[0] > dy) ? " (dicatat mulai " + GP_LocalTime(g_kbSFirst[0]) + ")" : "";
   string st1 = (g_kbSFirst[1] > dy) ? " (dicatat mulai " + GP_LocalTime(g_kbSFirst[1]) + ")" : "";
   if(g_kbSPN[sc * 12] > 0)
      s += StringFormat("^Kotak lahir %d | tembusan %d, tembus sungguhan %d%s", g_kbSBox[sc], g_kbSBrk[sc], g_kbSReal[sc], st1);
   if(g_kbSTN[sc * 5] > 0)
     {
      s += "^Target: " + KB_STgTxt(sc, 0, true) + st0;
      string tyN[5] = {"", "colek", "mepet", "kembali", "lanjut garis"};
      for(int ty = 1; ty < 5; ty++)
         if(g_kbSTN[sc * 5 + ty] > 0) s += "^   " + tyN[ty] + " " + KB_STgTxt(sc, ty, false);
     }
   string kn[3] = {"Pecah 5 mnt", "Kembali 5 mnt", "Tembus sungguhan"};
   for(int kd = 0; kd < 3; kd++)
     {
      s += KB_SCal(sc, kd, 0, "^" + kn[kd] + ": %dx, rata2 %.0f%% -> nyata %.0f%%");
      if(kd < 2) s += KB_SCal(sc, kd, 3, "^   yang >= 50%%: %dx, rata2 %.0f%% -> nyata %.0f%%");
     }
   if(g_kbSTN[0] > 0)
      s += StringFormat("^Total sejak %s: target %s", KB_DayTxt(g_kbSFirst[0]), KB_STgTxt(0, 0, true));
   g_kbAlRun = false; KB_CalCheck();                                     // cek angka 7 hari (dengan baris terbaru)
   string al = KB_AlSummary();
   s += (al == "") ? "^Cek angka 7 hari: semua wajar" : "^Cek angka 7 hari: ALARM " + al + " (disembunyikan di dashboard)";
   KB_Out(g_kbLastBar, "RAPOR", s);
  }

//--- tampilan  (MEPET kini = target dari close candle M1, bukan cerita dari harga bid)
//    skala layar Windows (DPI > 96, layar pengguna ~125%): lebar teks TextGetSize x DPI/96 (dulu ZW_Scale modul Zona, 10 Okt dibuang)
double KB_Scale() { long dpi = TerminalInfoInteger(TERMINAL_SCREEN_DPI); return (dpi > 96) ? dpi / 96.0 : 1.0; }
int KB_W(string s)
  {
   uint w = 0, h = 0;
   TextSetFont("Consolas", -10 * MathMax(7, InpKBFont));
   TextGetSize(s, w, h);
   return (int)MathCeil(w * KB_Scale());
  }
int KB_MaxW()
  {
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   return (int)MathMax(280, MathMin(560, cw * 0.42));
  }
void KB_Line(string s, color c, string tip = "")
  {
   int n = ArraySize(g_kbL);
   ArrayResize(g_kbL, n + 1); ArrayResize(g_kbC, n + 1); ArrayResize(g_kbT, n + 1);
   g_kbL[n] = StringSubstr(s, 0, KB_MAXCH); g_kbC[n] = c; g_kbT[n] = tip;
  }
void KB_Wrap(string s, color c, string tip = "")
  {
   int mw = KB_MaxW() - 12;
   if(KB_W(s) <= mw && StringLen(s) <= KB_MAXCH) { KB_Line(s, c, tip); return; }
   string w[];
   int nw = StringSplit(s, ' ', w);
   string cur = "";
   for(int i = 0; i < nw; i++)
     {
      string nx = (cur == "") ? w[i] : cur + " " + w[i];
      if(cur != "" && (KB_W(nx) > mw || StringLen(nx) > KB_MAXCH)) { KB_Line(cur, c, tip); cur = "   " + w[i]; }
      else cur = nx;
     }
   if(cur != "") KB_Line(cur, c, tip);
  }

//--- DASHBOARD RINGKAS (8 Okt 2026, pengguna: "keterangannya ringkas; di bawah kotak sideway yang utama: jam : pemicu, TARGET,
//    confidence; setelah lewat dicek tercapai atau tidak; tiap target masuk daftar"). Klik judul = tampilkan / sembunyikan cerita.
void KB_BuildLines(int show)
  {
   ArrayResize(g_kbL, 0); ArrayResize(g_kbC, 0); ArrayResize(g_kbT, 0);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), wd = g_kbHi - g_kbLo;
   int hr = KB_HourWITA(TimeCurrent());
   string tipT = "KOTAK SIDEWAY = 60 mnt harga sempit (definisi riset). Garis tebal biru = ATAP, oranye = LANTAI, titik-titik = pemicu\n"
                 "MEPET 90% / 10% (dibekukan saat kotak lahir, berlaku s/d 4 jam walau ditembus lalu kembali).\n"
                 "TARGET dibuat saat candle M1 COLEK dinding (sumbu lewat, close di dalam) atau MEPET (close >= 90% / <= 10%).\n"
                 "KENA = candle M1 close di luar dinding itu s/d jam batas (5 candle). YAKIN = hasil uji 2017-26 aturan yang sama\n"
                 "(colek 59%, mepet 52%; akhirnya 85% / 88%). Sesudah tembus: KEMBALI ke kotak s/d 5 candle 59%, LANJUT ke garis\n"
                 "GoldPro berikutnya sebelum kembali (peluang menurut jarak). INFO, bukan sinyal arah. Klik judul = cerita.";
   //--- 1 KOTAK
   if(g_kbSt == 0)
     {
      KB_Line(g_kbR60 >= 0 ? StringFormat("KOTAK SIDEWAY: tidak ada | 60 mnt $%.1f > batas $%.1f", g_kbR60, g_kbThrUsd)
                           : "KOTAK SIDEWAY: tidak ada (menunggu 60 mnt data utuh)", clrSilver,
              tipT + "\nKotak baru lahir saat rentang 60 mnt terakhir (high - low candle M1) <= batas sideway jam itu ($, = ambang\n"
                     "P20 slot NY x ADR). Sesudah kotak selesai, harga yang terus bergerak (tren) membuat rentang lebar -> belum ada kotak.");
      if(GDM::g_ms.st == 1)
         KB_Line(StringFormat("(label LIVE KONSOLIDASI %dm = rentang %d mnt)", GDM::g_ms.dur, GDM::g_ms.dur), clrDimGray, tipT);
     }
   else
      KB_Line(StringFormat("KOTAK SIDEWAY %s ($%.1f) | %s s/d %s", KB_Rng(), wd, GP_LocalTime(g_kbStart),
                           GP_LocalTime(g_kbStart + 240 * 60)), clrAqua,
              tipT + "\nJam kedua = kotak selesai paling lambat (umur 4 jam, bila harga di dalam). Bisa lebih cepat: 60 mnt terus di\n"
                     "luar (TEMBUS SUNGGUHAN) atau muncul kotak sideway baru.");
   //--- kotak pertama sesudah TEMBUS SUNGGUHAN: dinding kotak lama tersentuh lagi dalam 4 jam?
   if(g_kbSt != 0 && g_kbOldP >= 0 && g_kbOldT0 == g_kbStart && TimeCurrent() - g_kbOldT0 < 240 * 60)
      KB_Line(g_kbOldHit > 0 ? StringFormat("Dinding lama %s: tersentuh %s (yakin %d%%)", KB_Px(g_kbOldW), GP_LocalTime(g_kbOldHit), g_kbOldP)
                             : StringFormat("Dinding lama %s tersentuh lagi s/d %s: %d%%", KB_Px(g_kbOldW),
                                            GP_LocalTime(g_kbOldT0 + 240 * 60), g_kbOldP), g_kbOldHit > 0 ? clrLime : clrSilver,
              StringFormat("Kotak ini lahir sesudah TEMBUS SUNGGUHAN %s kotak sebelumnya (dinding %s). Uji 2017-26 (7.9 rb kotak, latih =\n"
                           "uji): arah sesudahnya LANJUT / BALIK = koin (tembusan pertama searah 52%%, gerak 4 jam ~0), tapi harga MENYENTUH\n"
                           "lagi dinding lama dalam 4 jam 57%%, menurut jarak tengah kotak baru dari dinding itu: di belakang dinding 99%%,\n"
                           "< 0.1 ADR 73%%, 0.1-0.25 44%%, 0.25-0.5 16%%, >= 0.5 ADR 2%%. Dicatat di kotak_prediksi.csv (dinding4j).",
                           g_kbOldS > 0 ? "ATAS" : "BAWAH", KB_Px(g_kbOldW)));
   //--- PERGANTIAN KOTAK: hitung mundur umur 4 jam (30 mnt terakhir) & kotak baru hampir terbentuk
   if(g_kbSt == 1 && wd > 0 && TimeCurrent() - g_kbStart >= 210 * 60)
     {
      int left = (int)MathMax(0, (g_kbStart + 240 * 60 - TimeCurrent()) / 60);
      KB_Line(StringFormat("Selesai %s (sisa %d mnt) | lalu kotak baru: %s", GP_LocalTime(g_kbStart + 240 * 60), left,
                           g_kbR60 < 0 ? "tunggu data" : (g_kbConsNow ? "langsung" : "belum")), clrGold,
              "Kotak selesai saat umur 4 jam bila harga di dalam. Sesudahnya: " + KB_After() + ".");
     }
   if(g_kbSt != 0 && KB_NewNear(TimeCurrent()))
      KB_Line(StringFormat("Kotak baru bisa segera: 60 mnt $%.1f (batas $%.1f)", g_kbR60, g_kbThrUsd), clrGold,
              "Kotak sideway baru (mengganti kotak ini) lahir bila rentang 60 mnt terakhir <= batas, sesudah >= 60 mnt tidak sempit.");
   if(g_kbSt == 1 && wd > 0)
     {
      double p = MathMax(0.0, MathMin(1.0, (bid - g_kbLo) / wd));
      int k = (int)MathMin(9, MathFloor(p * 10)), pu = KB_Pct(KB_CEX[k]);
      KB_Line(StringFormat("Harga %s = %d%% kotak | keluar %s %d%%", KB_Px(bid), KB_Pct(p), pu >= 50 ? "ATAP" : "LANTAI",
                           pu >= 50 ? pu : 100 - pu), clrWhite,
              "Dinding mana yang ditembus lebih dulu menurut posisi harga di kotak (uji 2017-26, 0% = lantai, 100% = atap).");
      if(g_kbPB >= 0)
        {
         string tipP = "Peluang candle M1 close di LUAR kotak (atap atau lantai) dalam 5 candle sesudah candle " + GP_LocalTime(g_kbPBT) +
                       ".\nModel uji 2017-26 (1.07 jt menit): posisi harga, colek, berita USD HIGH, data NY 08:30, buka London /\n"
                       "NY, jam WITA, umur kotak, pernah ditembus. Uji tahun-ditahan: tiap kelompok selisih <= 1 poin." + KB_SCalTip(0);
         if(g_kbAl[0] == 1) KB_Line(KB_AlLine(0, "Pecah 5 mnt"), clrTomato, KB_AlTip(0) + KB_SCalTip(0));
         else
            KB_Line(StringFormat("Pecah 5 mnt: %d%%%s", KB_Pct(g_kbPB), g_kbPBWhy == "" ? "" : " | " + g_kbPBWhy),
                    g_kbPB >= 0.5 ? clrGold : (g_kbPB >= 0.3 ? clrWhite : clrSilver), tipP);
        }
      if(g_kbBack && g_kbBackT >= g_kbBrkT && TimeCurrent() - g_kbBackT < 10 * 60)   // 10 mnt sesudah masuk lagi
        {
         int b5 = KB_Bin5(g_kbBackDepth);
         KB_Line(StringFormat("Baru masuk lagi %s: bertahan 10 mnt %d%% | ke tengah %d%%", GP_LocalTime(g_kbBackT), KB_RE_STAY[b5],
                              KB_RE_MID[b5]), clrYellow,
                 StringFormat("Uji 2017-26 (72 rb kali harga masuk lagi sesudah tembus): bertahan 10 mnt tanpa close di luar 26%%,\n"
                              "30 mnt 10%%; sampai tengah kotak sebelum keluar lagi 28%%. Masuk ini sedalam %.0f%% lebar kotak -> bertahan\n"
                              "10 mnt %d%%, ke tengah dulu %d%%; bila keluar lagi, lewat %s %d%%.", 100 * g_kbBackDepth, KB_RE_STAY[b5],
                              KB_RE_MID[b5], KB_wall(g_kbBackSide), KB_RE_SAME[b5]));
        }
     }
   else if(g_kbSt == 2)
     {
      int mins = (int)((TimeCurrent() - g_kbBrkT) / 60);
      double out = MathMax(g_kbMaxOut, g_kbBrkSide > 0 ? bid - g_kbHi : g_kbLo - bid);
      double dw = (g_kbBrkSide > 0) ? bid - g_kbHi : g_kbLo - bid;
      KB_Line(StringFormat("%s : TEMBUS %s | di luar %d mnt", GP_LocalTime(g_kbBrkT), g_kbBrkSide > 0 ? "ATAS" : "BAWAH", mins),
              g_kbBrkSide > 0 ? clrLime : clrTomato);
      if(g_kbPK >= 0)
        {
         int mo = (int)((g_kbPKT - g_kbBrkT) / 60);
         double mxw = g_kbMaxOut / wd, rt = g_kbPKd / MathMax(mxw, 1e-9);
         int cell = KB_MOB(mo) * 5 + KB_MXB(mxw), ph = KB_H60P(mo, g_kbPKd, g_kbPKT), pk = 100 - ph, mm = KB_MAPM[cell];
         if(g_kbAl[2] == 1) KB_Line(KB_AlLine(2, "Tembus sungguhan"), clrTomato, KB_AlTip(2) + KB_SCalTip(2));
         else
           {
            KB_Line(StringFormat("Tembus sungguhan %s bila bertahan | peluang %d%%", GP_LocalTime(g_kbBrkT + 3600), ph),
                    clrGold, "TEMBUS SUNGGUHAN = 60 mnt terus di luar kotak -> kotak ini selesai. Peluang dari uji 2017-26 (1.18 jt menit,\n"
                             "latih = uji): menurut menit di luar & jarak close dari dinding, DIKOREKSI PER JAM (v2, 10 Okt: tabel lama\n"
                             "meleset 4-10 poin pada 11 jam WITA; koreksi lebih tepat 1.2-1.6%, 10/10 tahun). Contoh sel 15-29 mnt &\n"
                             "0.25-0.5 lebar: tabel 48%, jam 07-08 WITA ~40%, 23-01 WITA ~60%.\n"
                             "Dicatat di menit 0 / 15 / 30 / 45 di luar." + KB_SCalTip(2));
            //--- peta kembali: kebalikan baris di atas + ujung terjauh & posisi close (ciri yang akan kembali)
            KB_Line(StringFormat("Kembali s/d 60 mnt: %d%%%s | ujung %.1fx, %s", pk, mm > 0 ? StringFormat(" (~%d mnt)", mm) : "", mxw,
                                 rt < 0.5 ? "balik >50%" : (rt < 0.8 ? "balik 20-50%" : "di ujung")), pk >= 50 ? clrYellow : clrSilver,
                    KB_MapTip(cell));
           }
        }
      KB_Line(dw > 0 ? StringFormat("Harga $%.2f %s %s | maks lewat $%.2f", dw, g_kbBrkSide > 0 ? "di atas" : "di bawah",
                                    KB_wall(g_kbBrkSide), out)
                     : "Harga di dalam kotak lagi (tunggu close M1)", dw > 0 ? clrWhite : clrYellow);
      if(g_kbPK >= 0)
        {
         string tipK = "Peluang candle M1 close KEMBALI DI DALAM kotak dalam 5 candle sesudah candle " + GP_LocalTime(g_kbPKT) + ".\n"
                       "Model uji 2017-26 (1.18 jt menit di luar kotak): menit di luar x jarak dari dinding, sedang balik mendekati\n"
                       "dinding?, colek dinding dari luar, berita / data NY 08:30, jam WITA, tembusan ke-n, lebar kotak.\n"
                       "Uji tahun-ditahan: tiap kelompok selisih <= 2 poin. Contoh: dekat dinding (< 0.1 lebar) ~60%, colek dari\n"
                       "luar ~59%, >= 1 lebar dari dinding ~1%, sudah 15-59 mnt di luar ~7%." + KB_SCalTip(1);
         if(g_kbAl[1] == 1) KB_Line(KB_AlLine(1, "Kembali 5 mnt"), clrTomato, KB_AlTip(1) + KB_SCalTip(1));
         else
            KB_Line(StringFormat("Kembali 5 mnt: %d%%%s", KB_Pct(g_kbPK), g_kbPKWhy == "" ? "" : " | " + g_kbPKWhy),
                    g_kbPK >= 0.5 ? clrGold : (g_kbPK >= 0.2 ? clrWhite : clrSilver), tipK);
         if(g_kbPKpkb)
            KB_Line(StringFormat("Colek dari luar: masuk & bertahan 10 mnt %d%%", KB_PKO_IN[KB_Bin5(g_kbPKd)]), clrSilver,
                    "Uji 2017-26 (140 rb colek dinding dari luar): close masuk lagi dlm 5 mnt 59% (close dekat dinding 71%), tapi\n"
                    "yang MASUK & BERTAHAN 10 mnt tanpa keluar lagi hanya 16% (dekat dinding 20%, jauh 3%). Biasanya harga\n"
                    "keluar-masuk di sekitar dinding; 93% yang keluar lagi lewat dinding yang sama.");
        }
     }
   //--- 2 TARGET yang sedang berjalan (maks 3, urut dibuat)
   int nt = ArraySize(g_kbTg), pend[];
   for(int i = nt - 1; i >= 0 && ArraySize(pend) < 3; i--)
      if(g_kbTg[i].res == 0) { int q = ArraySize(pend); ArrayResize(pend, q + 1); pend[q] = i; }
   if(ArraySize(pend) == 0 && g_kbSt == 1 && wd > 0)                    // belum ada target: tampilkan harga pemicu berikutnya
      KB_Line(StringFormat("Tunggu: colek dinding / close >= %s / <= %s", KB_Px(g_kbLo + 0.9 * wd), KB_Px(g_kbLo + 0.1 * wd)),
              clrSilver, "Target baru dibuat saat candle M1 COLEK dinding (sumbu lewat, close di dalam) atau close MEPET\n"
                         ">= 90% / <= 10% kotak (harga di baris ini), paling cepat 5 mnt sesudah target sebelumnya.");
   for(int q = ArraySize(pend) - 1; q >= 0; q--)
     {
      KBTarget x = g_kbTg[pend[q]];
      if(x.ty <= 2)
        {
         KB_Line(StringFormat("%s : %s", GP_LocalTime(x.t), x.ty == 1 ? "colek " + KB_Wall(x.side) : "mepet " + KB_Wall(x.side)),
                 x.side > 0 ? clrDeepSkyBlue : clrOrange);
         KB_Line("TARGET : " + KB_TgGoal(x, false), clrWhite);
         int a = (x.ty == 1) ? 3 : 4;
         if(g_kbAl[a] == 1) KB_Line(KB_AlLine(a, "YAKIN  "), clrTomato, KB_AlTip(a));
         else
            KB_Line(StringFormat("YAKIN  : %d%%  (15 mnt %d%% | akhirnya %d%%)", x.conf, x.ty == 1 ? 74 : 70, x.ty == 1 ? 85 : 88), clrGold,
                    "Uji 2017-26 aturan yang sama: dinding itu ditembus (close M1 di luar) s/d batas waktu / s/d 15 mnt / akhirnya.");
        }
      else if(x.ty == 3)
        {
         if(g_kbAl[5] == 1) KB_Line("TARGET : " + KB_TgGoal(x, false) + " | yakin [DICEK]", clrTomato, KB_AlTip(5));
         else
            KB_Line(StringFormat("TARGET : %s | yakin awal %d%%", KB_TgGoal(x, false), x.conf), clrWhite,
                    "Tembusan GAGAL: candle M1 close kembali di dalam kotak s/d batas waktu. YAKIN AWAL = peluang saat candle tembus\n"
                    "(model situasi: jarak, colek, jam, berita...; uji 2017-26 candle tembus 57% vs nyata 59%). Peluang TERBARU ada di\n"
                    "baris 'Kembali 5 mnt' (5 candle dari sekarang, diperbarui tiap candle).");
        }
      else
        {
         if(g_kbAl[6] == 1) KB_Line("LANJUT : " + KB_TgGoal(x, false) + " | yakin [DICEK]", clrTomato, KB_AlTip(6));
         else
            KB_Line(StringFormat("LANJUT : %s | yakin %d%%", KB_TgGoal(x, false), x.conf), clrWhite,
                    "Harga menyentuh garis GoldPro berikutnya SEBELUM close kembali ke kotak (uji 2017-26 menurut jarak:\n"
                    "< 0.01 ADR 57% | < 0.02 42 | < 0.04 32 | < 0.06 23 | < 0.10 17 | < 0.15 13 | < 0.25 8 | lebih 4%).");
        }
     }
   //--- 3 DAFTAR TARGET selesai (terbaru dulu) + ringkasan KENA vs harapan SEJAK PERTAMA DICATAT (9 Okt: dibaca dari
   //    kotak_target.csv -> tidak hilang saat ganti TF / muat ulang) + hari ini & rincian per jenis di tooltip
   string tyN[5] = {"semua", "colek", "mepet", "kembali", "lanjut garis"}, tipD = "";
   int sct = KB_SToday();
   tipD += "Hari ini (hari dagang mulai " + GP_LocalTime(KB_Day(TimeTradeServer())) + " WITA): " +
           ((sct >= 0 && g_kbSTN[sct * 5] > 0) ? KB_STgTxt(sct, 0, true) : "belum ada") + "\n";
   if(g_kbSTN[0] > 0)
     {
      tipD += StringFormat("Total sejak %s %s WITA:\n", KB_DayTxt(g_kbSFirst[0]), GP_LocalTime(g_kbSFirst[0]));
      for(int q = 1; q < 5; q++) tipD += "  " + tyN[q] + ": " + KB_STgTxt(0, q, true) + "\n";
      tipD += "  hanya live (tanpa putar ulang): " + KB_STgTxt(1, 0, true) + "\n";
     }
   tipD += "Harapan = jumlah angka YAKIN; KENA dekat harapan = angka yakin tepat. Dihitung dari MQL5\\Files\\GoldPro\\kotak_target.csv\n"
           "(semua hasil sejak pertama dicatat). Rapor harian dikirim ke Telegram tiap pagi (~05:00 WITA).";
   KB_Line(g_kbSTN[0] > 0 ? StringFormat("-- DAFTAR sejak %s: KENA %d dari %d (harapan %.0f) --", KB_DayTxt(g_kbSFirst[0]),
                                         g_kbSTK[0], g_kbSTN[0], g_kbSTE[0]) : "-- DAFTAR TARGET --", clrSilver, tipD);
   int ns = 0;
   for(int i = nt - 1; i >= 0 && ns < show; i--)
     {
      if(g_kbTg[i].res == 0) continue;
      KBTarget x = g_kbTg[i];
      //--- sesudah tembus: KEMBALI & LANJUT (dibuat di candle yang sama) = satu baris "kembali 59% KENA hh:mm | EQ 13% GAGAL"
      if(x.ty == 4 && i > 0 && g_kbTg[i - 1].ty == 3 && g_kbTg[i - 1].t == x.t && g_kbTg[i - 1].res != 0) continue;
      int pj = (x.ty == 3 && i + 1 < nt && g_kbTg[i + 1].ty == 4 && g_kbTg[i + 1].t == x.t && g_kbTg[i + 1].res != 0) ? i + 1 : -1;
      string s = "";
      if(pj >= 0)
         s = StringFormat("%s %s > kembali %d%% %s | %s %d%% %s", GP_LocalTime(x.t), KB_TgTrig(x), x.conf, KB_TgRes(x),
                          g_kbTg[pj].lns, g_kbTg[pj].conf, KB_TgRes(g_kbTg[pj]));
      if(pj >= 0 && StringLen(s) <= KB_MAXCH)
         KB_Line(s, x.res == 1 ? clrLime : clrTomato,
                 StringFormat("Sesudah tembus: KEMBALI ke kotak s/d %s (yakin %d%%) = %s\nLANJUT ke %s %s sebelum kembali (yakin %d%%) = %s",
                              GP_LocalTime(x.t + KB_TGW * 60), x.conf, KB_TgRes(x), g_kbTg[pj].ln, KB_Px(g_kbTg[pj].lvl),
                              g_kbTg[pj].conf, KB_TgRes(g_kbTg[pj])));
      else
        {
         KB_Line(StringFormat("%s %s > %s %d%% %s", GP_LocalTime(x.t), KB_TgTrig(x), KB_TgGoal(x, true), x.conf, KB_TgRes(x)),
                 x.res == 1 ? clrLime : clrTomato);
         if(pj >= 0)
           {
            KBTarget y = g_kbTg[pj];
            KB_Line(StringFormat("%s %s > %s %d%% %s", GP_LocalTime(y.t), KB_TgTrig(y), KB_TgGoal(y, true), y.conf, KB_TgRes(y)),
                    y.res == 1 ? clrLime : clrTomato);
           }
        }
      ns++;
     }
   if(ns == 0) KB_Line("(belum ada target selesai)", clrDimGray);
   //--- 4 cerita (klik judul)
   if(g_kbStory)
     {
      KB_Line("-- cerita (" + InpLocalTZName + ") --", clrDimGray);
      int ne = ArraySize(g_kbEv);
      for(int i = ne - 1; i >= 0 && i >= ne - MathMin(4, show); i--)
         KB_Wrap(GP_LocalTime(g_kbEv[i].t) + " " + g_kbEv[i].txt, g_kbEv[i].c);
     }
   if(hr == 23)
      KB_Line("[HIPOTESIS] 23 WITA: tembus ATAS 58% (wajar 51%)", clrGold);
   KB_Line(g_kbStory ? "uji 2017-26, bukan sinyal | klik judul: tutup cerita" : "uji 2017-26, bukan sinyal | klik judul: cerita",
           clrDimGray);
  }

void KB_Label(string n, int x, int y, string s, color c, int fs, string tip)
  {
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_ZORDER, 21);
      ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, n, OBJPROP_TEXT, s == "" ? " " : s);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, fs);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, tip == "" ? "Kotak Sideway GoldPro - klik judul = ringkas / lengkap" : tip);
  }

int KB_LineH()
  {
   uint tw = 0, th = 0;
   TextSetFont("Consolas", -10 * MathMax(7, InpKBFont));
   TextGetSize("Ag", tw, th);
   return (int)MathCeil(th * KB_Scale()) + 3;
  }
int KB_Width()
  {
   int w = 0;
   for(int i = ArraySize(g_kbL) - 1; i >= 0; i--) w = MathMax(w, KB_W(g_kbL[i]));
   return w + 12;
  }
//--- kiri, di kanan kolom tombol & di bawah label LIVE; geser agar tidak menimpa panel lain yang terbuka
void KB_Place(int w, int h, int &x0, int &y0)
  {
   x0 = (DMInpButtons ? GDM::BtnColR() : 0) + 8;
   y0 = GDM::PanelTop() + (DMInpButtons ? BTN_H + 12 : 8);
   if(GDM::g_vPanel) x0 = MathMax(x0, GDM::g_panR + 10);
   string cid = IntegerToString(ChartID());
   if(GDM::g_vTrade && GlobalVariableCheck("GP_EAPW_" + cid) && GlobalVariableGet("GP_EAPH_" + cid) > 0)
      x0 = MathMax(x0, GDM::BtnColR() + 6 + (int)GlobalVariableGet("GP_EAPW_" + cid) + 10);
   if(ObjectFind(0, "GPD_BG") >= 0)                                       // dashboard SALDO (EA, kiri) -> di bawahnya (muat) / kanannya
     {
      int sx = (int)ObjectGetInteger(0, "GPD_BG", OBJPROP_XDISTANCE), sy = (int)ObjectGetInteger(0, "GPD_BG", OBJPROP_YDISTANCE);
      int sw = (int)ObjectGetInteger(0, "GPD_BG", OBJPROP_XSIZE), sh = (int)ObjectGetInteger(0, "GPD_BG", OBJPROP_YSIZE);
      int chh = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
      if(sx < x0 + w && sx + sw > x0 - 4)                                  // bertumpuk mendatar dengan dashboard Saldo
        {
         if(sy + sh + 10 + h <= chh) y0 = MathMax(y0, sy + sh + 10);
         else x0 = sx + sw + 8;
        }
     }
  }

//--- susun & gambar: dashboard lebih tinggi dari chart (screenshot 8 Okt: baris bawah terpotong) -> cerita lama dikurangi satu per
//    satu; bila masih belum muat, baris sebelum penutup dipotong (penutup "INFO ... bukan sinyal arah" selalu tampil)
void KB_Render()
  {
   int lh = KB_LineH(), chh = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   int show = 8, x0 = 0, y0 = 0, w = 0, n = 0;                          // baris daftar target (dikurangi bila chart kurang tinggi)
   for(;;)
     {
      KB_BuildLines(show);
      n = ArraySize(g_kbL); w = KB_Width();
      KB_Place(w, n * lh + 8, x0, y0);
      if(y0 + n * lh + 8 <= chh - 2 || show <= 1) break;
      show--;
     }
   int maxn = (chh - 2 - y0 - 8) / lh;
   if(n > maxn && maxn >= 2)
     {
      g_kbL[maxn - 1] = g_kbL[n - 1]; g_kbC[maxn - 1] = g_kbC[n - 1]; g_kbT[maxn - 1] = g_kbT[n - 1];
      ArrayResize(g_kbL, maxn); ArrayResize(g_kbC, maxn); ArrayResize(g_kbT, maxn);
     }
   KB_Draw(x0, y0, lh, w);
  }

void KB_Draw(int x0, int y0, int lh, int w)
  {
   int n = ArraySize(g_kbL);
   if(n < 1) return;
   int fs = MathMax(7, InpKBFont), h = n * lh + 8;
   string bg = KB_PFX + "BG";
   if(ObjectFind(0, bg) < 0)
     {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, bg, OBJPROP_ZORDER, 20);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'14,24,34');
      ObjectSetString(0, bg, OBJPROP_TOOLTIP, "Kotak Sideway GoldPro - klik = ringkas / lengkap");
     }
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x0 - 4);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y0 - 4);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, w + 2);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, C'0,140,170');
   for(int i = 0; i < n; i++)
      KB_Label(KB_PFX + "L" + IntegerToString(i), x0 + 2, y0 + i * lh, g_kbL[i], g_kbC[i], fs, g_kbT[i]);
   for(int i = n; ObjectFind(0, KB_PFX + "L" + IntegerToString(i)) >= 0; i++)
      ObjectDelete(0, KB_PFX + "L" + IntegerToString(i));
  }

//--- garis ATAP & LANTAI kotak yang diawasi (dibekukan saat kotak lahir). 8 Okt 22:30 (pengguna: "garis atap dan lantai lebih jelas
//    dan terus update"): tebal & utuh di DEPAN candle, label "ATAP 4130.45" di ujung kanan + tanda harga berwarna, status ditembus di
//    label, garis titik-titik pemicu MEPET (90% / 10%); ujung kanan ikut candle berjalan tiap 2 dtk.
void KB_HLine(string n, double p, string txt, color c, int width, ENUM_LINE_STYLE st, bool tag)
  {
   datetime t2 = TimeCurrent() + PeriodSeconds(PERIOD_CURRENT) * 6;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_TREND, 0, g_kbT0, p, t2, p);
      ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
     }
   ObjectMove(0, n, 0, g_kbT0, p); ObjectMove(0, n, 1, t2, p);
   ObjectSetInteger(0, n, OBJPROP_BACK, false);                           // (diset tiap kali: objek versi lama masih BACK = true)
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, n, OBJPROP_STYLE, st);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, txt + " (Kotak Sideway, dibekukan saat kotak lahir " + GP_LocalTime(g_kbStart) + ")");
   string tl = n + "T";                                                   // nama + harga, di atas garis, berakhir di ujung kanan
   if(ObjectFind(0, tl) < 0)
     {
      ObjectCreate(0, tl, OBJ_TEXT, 0, t2, p);
      ObjectSetInteger(0, tl, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, tl, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, tl, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
   ObjectSetString(0, tl, OBJPROP_FONT, "Arial Bold");
   ObjectMove(0, tl, 0, t2, p);
   ObjectSetString(0, tl, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, tl, OBJPROP_COLOR, c);
   ObjectSetInteger(0, tl, OBJPROP_FONTSIZE, tag ? 8 : 7);
   string tp = n + "P";                                                   // tanda harga berwarna di ujung kanan
   if(!tag) { ObjectDelete(0, tp); return; }
   if(ObjectFind(0, tp) < 0)
     {
      ObjectCreate(0, tp, OBJ_ARROW_RIGHT_PRICE, 0, t2, p);
      ObjectSetInteger(0, tp, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, tp, OBJPROP_HIDDEN, true);
     }
   ObjectMove(0, tp, 0, t2, p);
   ObjectSetInteger(0, tp, OBJPROP_COLOR, c);
   ObjectSetInteger(0, tp, OBJPROP_WIDTH, 1);
  }
void KB_DrawLines()
  {
   if(!InpKBDrawLines || g_kbSt == 0 || g_kbHi <= g_kbLo)
     {
      if(ObjectFind(0, KB_PFX + "HA") >= 0 || ObjectFind(0, KB_PFX + "HM1") >= 0) ObjectsDeleteAll(0, KB_PFX + "H");
      return;
     }
   string ta = "ATAP " + KB_Px(g_kbHi), tb = "LANTAI " + KB_Px(g_kbLo);
   if(g_kbSt == 2)
     {
      if(g_kbBrkSide > 0) ta += " - DITEMBUS " + GP_LocalTime(g_kbBrkT);
      else                tb += " - DITEMBUS " + GP_LocalTime(g_kbBrkT);
     }
   KB_HLine(KB_PFX + "HA", g_kbHi, ta, C'0,191,255', 2, STYLE_SOLID, true);
   KB_HLine(KB_PFX + "HB", g_kbLo, tb, C'255,140,0', 2, STYLE_SOLID, true);
   if(g_kbSt == 1)                                                        // pemicu target MEPET (close >= 90% / <= 10% kotak)
     {
      double wd = g_kbHi - g_kbLo;
      KB_HLine(KB_PFX + "HM1", g_kbLo + 0.9 * wd, "mepet " + KB_Px(g_kbLo + 0.9 * wd), C'0,120,160', 1, STYLE_DOT, false);
      KB_HLine(KB_PFX + "HM2", g_kbLo + 0.1 * wd, "mepet " + KB_Px(g_kbLo + 0.1 * wd), C'170,95,0', 1, STYLE_DOT, false);
     }
   else if(ObjectFind(0, KB_PFX + "HM1") >= 0) { ObjectsDeleteAll(0, KB_PFX + "HM"); }
  }

//--- mesin dihentikan (chart tampilan, dashboard tertutup) -> keadaan dikosongkan; dijalankan lagi = putar ulang ~10 jam dari awal
void KB_Reset()
  {
   g_kbLastBar = 0; g_kbSt = 0; g_kbLastCons = 0; g_kbNBrk = 0; g_kbBrkT = 0; g_kbBack = false; g_kbLive = false;
   ArrayResize(g_kbEv, 0); ArrayResize(g_kbTg, 0);
   ArrayResize(g_kbPend, 0); ArrayResize(g_kbPendK, 0); ArrayResize(g_kbPendH, 0); ArrayResize(g_kbPendO, 0);
   g_kbPB = -1; g_kbPK = -1; g_kbRealT = 0; g_kbOldP = -1; g_kbOldHit = 0; g_kbTgLast = 0;
   TB_Reset();                                                           // kejadian Tembus Balik ikut diputar ulang
  }

void KB_Update()
  {
   if(MQLInfoInteger(MQL_TESTER)) return;
   //--- 10 Okt 2026 (pengerasan no. 1): di CHART TAMPILAN mesin kotak hanya jalan bila dashboard Kotak dibuka (MT5 lebih ringan);
   //    chart utama selalu menjalankannya (Telegram, catatan uji maju, rapor, alarm kalibrasi)
   //    11 Okt 2026: dashboard Tembus Balik juga butuh mesin ini (kejadian tembusan)
   //    14 Okt 2026: tombol "Kotak Sideway" = GARIS (g_vBox), kotak "i" di sampingnya = DASHBOARD (g_iBox); Tembus Balik juga dua
   if(!g_gpMaster && !GDM::g_vBox && !GDM::g_iBox && !GDM::g_vTbk && !GDM::g_iTbk)
     {
      if(g_kbLastBar != 0) KB_Reset();
      if(ObjectFind(0, KB_PFX + "BG") >= 0 || ObjectFind(0, KB_PFX + "HA") >= 0) ObjectsDeleteAll(0, KB_PFX);
      return;
     }
   KB_Machine();                                          // chart utama: selalu jalan (target & cerita lengkap saat dashboard dibuka)
   KB_SUpdate();                                          // hitungan kumulatif dari CSV (baris baru saja)
   KB_CalCheck();                                         // alarm kalibrasi 7 hari (tiap menit) -> mode presisi
   KB_Rapor();                                            // rapor harian Telegram (sekali sesudah hari dagang berganti)
   if(GDM::g_iBox)
     {
      if(g_kbRaise && GetTickCount() - g_kbRaiseTick > 20000)  // objek lain baru dibuat -> buat ulang agar di depan (maks 1x/20 dtk)
        {
         g_kbRaise = false; g_kbRaiseTick = GetTickCount();
         ObjectDelete(0, KB_PFX + "BG"); ObjectsDeleteAll(0, KB_PFX + "L");
        }
      KB_Render();
     }
   else if(ObjectFind(0, KB_PFX + "BG") >= 0) { ObjectDelete(0, KB_PFX + "BG"); ObjectsDeleteAll(0, KB_PFX + "L"); }
   if(GDM::g_vBox) KB_DrawLines();
   else if(ObjectFind(0, KB_PFX + "HA") >= 0 || ObjectFind(0, KB_PFX + "HM1") >= 0) ObjectsDeleteAll(0, KB_PFX + "H");
  }

void KB_ChartEvent(const int id, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CREATE)
     {
      if(StringFind(sparam, KB_PFX) != 0 && StringFind(sparam, "GPT_") != 0 && StringFind(sparam, "GPB_") != 0 &&
         StringFind(sparam, "GPN_") != 0 && StringFind(sparam, "GPD_") != 0 && StringFind(sparam, "GPV_") != 0 &&
         StringFind(sparam, "GPI_") != 0 && StringFind(sparam, "GPM_IC_") != 0 &&   // GPM_IC_ = kartu info kotak "i" (14 Okt)
         StringFind(sparam, "GPW_") != 0)                                          // GPW_ = peta gelombang (14 Okt)
         g_kbRaise = true;                                                  // GPD_ = dashboard Saldo (EA), GPV_ = baris cek kesehatan,
                                                                            // GPI_ = Tembus Balik (11 Okt)
      return;
     }
   if(id == CHARTEVENT_OBJECT_CLICK && ((sparam == "GPB_B_box" && GDM::g_vBox) || (sparam == "GPB_I_box" && GDM::g_iBox)))
     { KB_Update(); ChartRedraw(); return; }
   if(!GDM::g_iBox) return;
   if(id == CHARTEVENT_OBJECT_CLICK && (sparam == KB_PFX + "L0" || sparam == KB_PFX + "BG"))
     {
      g_kbStory = !g_kbStory;
      ObjectDelete(0, KB_PFX + "BG"); ObjectsDeleteAll(0, KB_PFX + "L");
      KB_Render(); ChartRedraw();
     }
   else if(id == CHARTEVENT_CHART_CHANGE) KB_Render();
  }

void KB_Deinit(bool isFinal)
  {
   if(isFinal) ObjectsDeleteAll(0, KB_PFX);
  }

#endif // GP_BOXWATCH_MQH
