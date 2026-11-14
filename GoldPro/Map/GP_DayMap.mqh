//+------------------------------------------------------------------+
//| GP_DayMap.mqh - GoldDayMap sebagai modul GoldPro (namespace GDM). |
//| Dibangkitkan dari MQL5/Indicators/GoldDayMap.mq5: input diberi    |
//| awalan DM, event handler jadi GDM::Init/Calculate/Timer/...       |
//| Prefix objek GPM_ (standalone tetap GDM_). Kunci & file jurnal    |
//| SAMA dengan standalone -> hanya satu yang menulis jurnal.         |
//+------------------------------------------------------------------+
#ifndef GP_DAYMAP_MQH
#define GP_DAYMAP_MQH

enum PanelMode { PANEL_FULL = 0,   // Lengkap
                 PANEL_SHORT = 1,  // Ringkas (live saja)
                 PANEL_OFF = 2     // Sembunyikan
               };
input group "=== GoldDayMap: peta harian, straddle EQ, peluang live, jurnal ==="
input int    DMInpShowDays       = 3;               // Jumlah hari yang digambar
input int    DMInpStatDays       = 250;             // Hari historis untuk statistik
input int    DMInpAdrDays        = 20;              // Periode ADR (hari)
input bool   DMInpAutoShift      = true;            // Aktifkan Chart Shift (ruang garis ke depan)
input PanelMode DMInpPanelMode   = PANEL_FULL;      // Panel info
input int    DMInpPanelFont      = 8;               // Ukuran huruf panel
input bool   DMInpShowTargetsHit = true;            // Tanda centang saat target tersentuh
input bool   DMInpShowBackup    = true;            // Garis cadangan live (uji 2017-26: tepat +/-3 poin)
input bool   DMInpShowT0         = true;            // Garis T0 = tengah EQ-T1 (uji 2017-26: salah satu sisi 99.6-100%/th)
input bool   DMInpShowNYOpen     = true;            // Garis Open NY 09:30 ET (magnet: +4.4 poin vs level biasa, 9/10 th)
input color  DMInpNYOpenColor    = clrMediumTurquoise; // Warna garis Open NY
input bool   DMInpShowSweeps     = true;            // Tandai sweep hari ini (x ungu) [INFO, BUKAN sinyal entry]
input bool   DMInpShowState      = true;            // KONDISI PASAR: sideway/tren/gejolak + kotak sideway [INFO]
input int    DMInpBackupP        = 80;              // Peluang garis cadangan (%), 60-95
input color  DMInpBackupColor    = clrKhaki;        // Warna garis cadangan
input bool   DMInpProbe          = true;            // Probe mouse: peluang harga di kursor (uji: +/-1.5 poin)
input bool   DMInpButtons        = true;            // Tombol interaktif di atas panel
input color  DMInpPinColor       = clrOrchid;       // Warna PIN (garis harga pilihan Anda)
input double DMInpVolB1          = 0.15;            // Penyesuaian vol: bobot gerak HARI INI (0 = mati)
input double DMInpVolB2          = 0.10;            // Penyesuaian vol: bobot gerak 2 JAM terakhir (0 = mati)
input bool   DMInpShowStraddle  = true;            // Straddle EQ: hitung, panel & jurnal (gagal 2017-25 -> info)
input bool   DMInpDrawStraddle   = false;           // Gambar garis straddle di chart (default mati: belum kokoh)
input double DMInpSdDist         = 0.15;            // Jarak stop order dari EQ (x ADR)
input double DMInpSdRR           = 1.5;             // TP straddle (x jarak SL; SL = EQ)
input color  DMInpBuyColor       = clrDodgerBlue;   // Warna BUY STOP
input color  DMInpSellColor      = clrRed;          // Warna SELL STOP
input double DMInpRiskPct        = 1.0;             // Risiko per trade (% saldo) untuk kalkulator lot
input bool   DMInpJournal       = true;            // Jurnal forward test (MQL5\Files\GoldDayMap)
input int    DMInpJournalMin     = 15;              // Interval snapshot jurnal (menit, kelipatan 5)
input color  DMInpBandColor      = C'90,72,18';     // Warna pita open/close
input color  DMInpEqColor        = clrGold;         // Warna garis equilibrium
input color  DMInpUpColor        = clrLimeGreen;    // Warna target atas
input color  DMInpDnColor        = clrTomato;       // Warna target bawah
input color  DMInpNeutralColor   = clrDarkGray;     // Warna target sebelum jam pertama selesai
input color  DMInpPanelColor    = clrWhite;        // Warna teks panel
input color  DMInpPanelBg        = C'20,20,28';     // Warna latar panel
input group "=== GoldPro: halaman CEK SIAP (rekap konfirmasi scalping + jam biaya) ==="
input int    DMInpCekMaxTrades   = 0;               // Maks trade per hari (hari server; 0 = tanpa batas)
input int    DMInpCekMaxLossRow  = 2;               // Berhenti setelah x kalah beruntun hari ini
input double DMInpCekMinMove     = 10.0;            // Rentang 1 jam ke depan minimal ($) agar target $5 masuk akal
input int    DMInpCekMinTouch    = 40;              // Garis layak bila peluang harga DATANG dlm 1 jam >= x %
input int    DMInpCekNewsMin     = 30;              // Tunggu bila data PENTING AS dalam x menit (dan 5 mnt sesudahnya)
input double DMInpCekSLTP        = 5.0;             // Pengingat SL = TP ($) di halaman CEK
void WV_InfoLines(string &L[], color &K[]);         // Map\GP_Wave.mqh (14 Okt 2026): isi kartu info tombol "Gelombang"

namespace GDM
{
//+------------------------------------------------------------------+
//| GoldDayMap.mq5                                                    |
//| Peta harian XAUUSD hasil riset:                                   |
//|  - Pita open hari ini / close kemarin = equilibrium (1 hari)      |
//|  - Garis target open +/- 0.25 / 0.50 / 0.75 / 1.00 ADR            |
//|  - Panah retest pita, panah pullback, tanda "lewat open"          |
//|  - Semua % dihitung ulang dari data historis M5                   |
//+------------------------------------------------------------------+


#define PFX "GPM_"
#define NLV 4
double LV[NLV] = {0.25, 0.50, 0.75, 1.00};

struct DayInfo
  {
   datetime          t0;     // awal hari (D1 broker = 18:00 ET)
   int               i0;     // indeks M5 pertama
   int               i1;     // indeks M5 terakhir + 1
   double            open;
   double            pdc;    // close kemarin
   double            adr;
   int               dir;    // arah jam pertama: +1 / -1 / 0 = belum selesai
   bool              done;   // hari sudah lengkap
  };

struct Ev
  {
   int               type;    // 0 retest pita, 1 pullback, 2 lewat open
   int               k;       // indeks bar M5
   int               side;    // +1 dari atas / tren naik, -1 sebaliknya
   int               num;     // nomor retest atau kedalaman pullback (%)
   int               outcome; // -1 belum, 0 ambigu, 1 pantul/lanjut, 2 tembus/gagal
   double            tip;     // ujung candle
   double            target;  // target panah
   double            ext;     // ekstrem sebelum pullback / lewat open (untuk jurnal)
  };

MqlRates g5[];
string   g_futName[];   // objek yang ujung kanannya ikut zoom
int      g_futPt[];
bool     g_futClip[];   // panah yang dipotong di tepi atas/bawah chart
datetime g_futA1[];
double   g_futP1[], g_futP2[];
datetime g_futT1 = 0;
bool     g_jOwner = false;   // chart ini yang menulis jurnal
datetime g_jStart = 0, g_lastSnap = 0, g_lastEv = 0;
#define JSNAP "GoldDayMap\\journal_snapshot.csv"
#define JEVT  "GoldDayMap\\journal_events.csv"
DayInfo  g_days[];
int      g_nd   = 0;
datetime g_last = 0;

int st_days, st_pb, st_pbCont, st_inv, st_invCont;
int st_sdN, st_sdWin, st_sdSkip;        // statistik straddle EQ (simulasi M5, 250 hari)
double st_sdR;
datetime g_sdLogged = 0;                // hari yang fill straddle-nya sudah dicatat di jurnal
datetime g_asLogged = 0;                // hari yang sinyal breakout Asia-nya sudah dicatat di jurnal

//--- Straddle EQ (backtest M1 1 th: pasang menit ke-5, OCO, SL = EQ, TP 1.5x;
//    menang ~47%, +0.13R/hari setelah slippage $0.5, 9/12 bulan positif)
struct Straddle
  {
   bool              valid;    // bar menit ke-5 sudah ada
   bool              skipped;  // harga sudah di luar zona saat menit ke-5
   double            up, dn, tpU, tpD, sl, risk;
   int               side;     // 0 belum terisi, +1 BUY, -1 SELL
   int               kFill, kExit;
   int               result;   // -1 berjalan, 1 TP, 2 SL, 3 ditutup akhir hari
   double            R;
  };
int st_hitS[NLV], st_hitO[NLV], st_touch[3], st_bounce[3];
int st_any1, st_both1;                  // T1 atas/bawah: salah satu / keduanya tersentuh (uji 2017-26: 98-99.6% / 32-40%)
//--- T0 = titik tengah EQ dan T1 (usulan pengguna 1 Okt 2026). Uji research\t0_test.py 2017-26: salah satu sisi
//    tersentuh 100% (99.6-100% tiap tahun), keduanya 66.5%, searah jam-1 91% / lawan 76% (tanpa sentuhan jam-1:
//    88/78). Setelah T0 tersentuh: T1 duluan 50.1% vs balik EQ duluan = KOIN -> T0 target/peta, BUKAN titik entry.
int st_hitS0, st_hitO0, st_any0, st_both0;
//--- Open NY 09:30 ET: setelah harga menjauh >= 0.05 ADR, kembali disentuh s/d tutup (250 hari). Uji ict_tests.py
//    2017-26: +4.4 poin lebih sering didatangi dari level palsu berjarak sama, 9/10 th (midnight open ICT: -3.5).
int st_nyN, st_nyBack;

//--- tampilan interaktif: status tombol, disimpan per chart (GlobalVariable) agar bertahan saat ganti TF
#define BPFX "GPB_"
bool g_vTarget = true, g_vBackup = true, g_vProbe = true, g_vPanel = true, g_vSMC = false;
//--- 10 Okt 2026 (pengguna: "kita buang"): halaman 2 ENTRY/TARGET (tangga target -> halaman 1, entry [HIPOTESIS] dibuang),
//    3 KOTAK, 4 JAM BIAYA (-> halaman CEK SIAP), tombol Radar, Panah & Zona OB/FVG dihapus. Halaman tersisa: 1 PETA & CEK SIAP
//    (nomor internal 5 dipertahankan agar status tersimpan lama tetap berlaku).
int  g_page = 1;                        // halaman panel: 1 PETA, 5 CEK SIAP (tombol "2 CEK SIAP")
bool g_vNews = false;                   // dashboard berita (GP_NewsBoard) tampil? - tombol "Berita", default tertutup
bool g_vTrade = false;                  // panel trading EA GoldPro_Panel tampil? - tombol "Trade" (3 Okt 2026), default tertutup
bool g_vSaldo = false;                  // dashboard SALDO & target harian (EA GoldPro_Panel) - tombol "Saldo" (10 Okt 2026)
bool g_vBox = false;                    // KOTAK SIDEWAY: dinding, colek, tembus & bertahan (Signal\GP_BoxWatch) - tombol "Kotak Sideway" (8 Okt 2026)
bool g_vTbk = false;                    // TEMBUS BALIK jam positif + rekap indikator (Signal\GP_TembusBalik) - tombol "Tembus Balik" (11 Okt 2026)
//--- 14 Okt 2026 (pengguna: "ada kotak juga disampingnya, kotak info, contoh smc (khusus gambar), disamping smc info, berarti info tentang
//    smc, dan semua begitu"): tombol utama = GAMBAR di chart, kotak "i" di sampingnya = INFO. Kotak Sideway / Tembus Balik / Berita
//    punya dashboard sendiri (g_iBox / g_iTbk / g_iNews); fitur lain memakai SATU kartu info umum (g_infoKey) di samping tombolnya.
bool g_iBox = false, g_iTbk = false, g_iNews = false;
bool g_vWave = false;                    // PETA GELOMBANG (Map\GP_Wave): range swing lebar + gelombang awal -> target - tombol "Gelombang" (14 Okt)
bool g_vSimple = false;                  // MODE TERUJI: satu klik -> SMC kotak mati, Gelombang / Target / Cad / Tembus Balik nyala (14 Okt)
string g_infoKey = "";                   // "" | page1 page5 target backup smc probe pin trade saldo wave simple
int    g_infX = 0, g_infY = 0, g_infW = 0, g_infH = 0;   // area kartu info (probe tidak menimpa)
uint   g_raiseTick = 0;                  // terakhir tombol dibuat ulang agar di depan (RaiseButtons)
string INFO_KEYS[] = {"page1", "page5", "target", "backup", "smc", "probe", "pin", "trade", "saldo", "wave", "simple"};
int    InfoIdx(string k)  { for(int i = 0; i < ArraySize(INFO_KEYS); i++) if(INFO_KEYS[i] == k) return i; return -1; }
string InfoKeyOf(int i)   { return (i >= 0 && i < ArraySize(INFO_KEYS)) ? INFO_KEYS[i] : ""; }
string g_pL[];                          // isi panel terakhir (untuk tata letak ulang saat chart diubah ukurannya)
color  g_pK[];
int    g_lastCH = 0;
int    g_panR = 0, g_panB = 0;          // tepi kanan & bawah area panel+tombol (piksel) -> probe tidak menimpa
bool   g_lastOneClick = false;
//--- cek hari-hari terakhir yang sudah selesai (halaman 2): hit target & akurasi garis cadangan
#define RC_DAYS 20
int st_rcDays, st_rcS[NLV], st_rcO[NLV], st_bkN, st_bkHit;
bool g_smcDirty = false;                // tombol SMC ditekan -> GoldPro_Main menggambar ulang SMC
bool g_pinMode = false;                 // menunggu klik chart untuk memasang PIN
uint g_pinModeTick = 0;
long g_mouseWas = 0;
//--- keadaan live untuk probe & PIN (diisi tiap Rebuild)
datetime g_pT0 = 0, g_pLastBar = 0;
double   g_pAdr = 0, g_lastBid = 0;
struct PinState
  {
   string            name;
   double            price;
   datetime          since;   // dipantau sejak (pasang / digeser / indikator aktif)
   datetime          hit;     // waktu tersentuh (0 = belum)
  };
PinState g_pins[];

//--- tabel peluang live: P(harga masih bergerak >= jarak X ADR sebelum hari tutup | sisa jam)
//    teruji konsisten di 3 periode; arah "garis mana duluan" ~ murni jarak (tidak ada bias arah)
#define NLB 24     // sisa jam 0..23
#define NDB 31     // jarak 0.00 .. 1.50 ADR, langkah 0.05
int lh_cnt[NLB];
int lh_hit[NLB][NDB];
//--- penyesuaian volatilitas hari ini: rvr = rentang hari ini s/d sekarang / rentang rata-rata pada jam yang sama
//    sejak buka. Tabel di atas meremehkan hari volatil (rvr > 1.8: tampil 32.8% vs nyata 41.5%) dan melebihkan
//    hari sepi. Jarak efektif = jarak / rvr^beta, beta 0.25 dipilih 2017-21, uji 2022-26: meleset 2.6 -> 1.0 poin,
//    semua tahun membaik. Simetris atas/bawah (tidak menebak arah).
//    Versi 2 (28 Sep): + rv2 = rentang 2 jam terakhir / normal 2 jam pada jam itu. Jarak / (rvr^0.15 * rv2^0.10),
//    dipilih 2017-21, uji 2022-26 logloss 0.42751 -> 0.42662 (lebih cepat bereaksi setelah rilis berita).
double e_sum[NLB], e2_sum[NLB];
int    e_cnt[NLB];
//--- PUNCAK/DASAR HARI BERTAHAN: peluang high/low hari ini TIDAK tertembus s/d tutup, menurut jarak harga dari
//    high/low (x ADR, bin 0.1) & sisa jam. Uji 2017-26 (high_hold.py): jarak $ lebih tepat dari % Fibonacci
//    (logloss 0.431 vs 0.463), stabil per tahun; puncak dekat sedikit lebih sering ditembus dari level biasa,
//    puncak jauh lebih jarang -> tabel khusus, bukan tabel sentuh biasa.
#define HHB 8
#define HHD 16
int hh_cnt[HHB][HHD], hh_brk[HHB][HHD];
double g_volK = 1.0, g_rvr = 1.0, g_rv2 = 1.0;
#define RV2_BARS 24

struct LiveInfo
  {
   bool              open;     // hari masih berjalan
   double            cur, hoursLeft, step;
   int               kUp, kDn;
   double            lvlUp, lvlDn, pUpFirst, pUpClose, pDnClose;
   int               last;     // indeks candle M5 terakhir yang sudah close
  };

//+------------------------------------------------------------------+
int Init(bool smcDefault = false)
  {
   EventSetTimer(2);   // tetap jalan walau tidak ada tick (pasar libur)
//--- status tombol: default dari input, ditimpa status terakhir chart ini (bila ada)
   g_vTarget = VGet("target", true);
   g_vBackup = VGet("backup", DMInpShowBackup);
   g_vProbe  = VGet("probe", DMInpProbe);
   g_vPanel  = VGet("panelv", false);   // panel TERTUTUP sampai tombol halaman diklik (kunci baru "panelv")
   g_vNews   = VGet("news", false);     // dashboard berita tertutup sampai tombol "Berita" diklik
   g_vTrade  = VGet("trade", false);    // panel trading (EA GoldPro_Panel) tertutup sampai tombol "Trade" diklik
   g_vSaldo  = VGet("saldo", false);    // dashboard saldo tertutup sampai tombol "Saldo" diklik
   g_vBox    = VGet("box", false);      // dashboard kotak sideway tersembunyi sampai tombol "Kotak Sideway" diklik
   g_vTbk    = VGet("tbk", false);      // dashboard & strip Tembus Balik tersembunyi sampai tombol "Tembus Balik" diklik
   g_vSMC    = VGet("smc", smcDefault);
   g_iBox    = VGet("i_box", false);    // 14 Okt: dashboard kotak sideway = kotak "i" (tombol utama = garis atap / lantai)
   g_iTbk    = VGet("i_tbk", false);    // dashboard & strip Tembus Balik = kotak "i" (tombol utama = tanda di chart)
   g_iNews   = VGet("i_news", false);   // dashboard berita = kotak "i" (tombol utama = garis jam berita)
   g_vWave   = VGet("wave", false);     // peta gelombang tersembunyi sampai tombol "Gelombang" diklik
   g_vSimple = VGet("simple", false);   // mode teruji (status tombol lain sudah tersimpan di GV masing-masing)
   g_infoKey = GlobalVariableCheck(VKey("infok")) ? InfoKeyOf((int)GlobalVariableGet(VKey("infok"))) : "";
   g_page    = GlobalVariableCheck(VKey("page")) ? (int)GlobalVariableGet(VKey("page")) : 1;
   if(g_page != 1 && g_page != 5) g_page = 1;   // halaman 2-4 sudah dibuang (10 Okt 2026)
   g_mouseWas = ChartGetInteger(0, CHART_EVENT_MOUSE_MOVE);
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   PinsLoad();
   if(DMInpAutoShift)    // sediakan ruang kosong di kanan untuk panah ke depan
     {
      ChartSetInteger(0, CHART_SHIFT, true);
      if(ChartGetDouble(0, CHART_SHIFT_SIZE) < 15)
         ChartSetDouble(0, CHART_SHIFT_SIZE, 20);
     }
//--- jurnal forward test: hanya satu chart per simbol yang menulis
   g_jOwner = false;
   g_jStart = TimeTradeServer() - 300;   // hanya catat kejadian sejak indikator aktif
   g_lastEv = g_jStart;
   g_lastSnap = 0;
   if(DMInpJournal && !MQLInfoInteger(MQL_TESTER) && !JournalClaim())
      Print("GoldDayMap: jurnal sedang dipegang instance/chart lain - diambil alih otomatis bila dilepas.");
   Status("GoldDayMap: memuat data M5 & D1...");
   return INIT_SUCCEEDED;
  }

//--- GoldPro PERBAIKAN SERAH-TERIMA JURNAL. Saat ganti TF, instance baru mulai SEBELUM instance lama
//    ditutup: dulu instance baru melihat jurnal "dipegang chart lain", lalu instance lama melepasnya
//    -> TIDAK ADA yang menulis jurnal sampai TF diganti lagi (log 30 Sep: berulang kali).
//    Sekarang: klaim atomik (SetOnCondition) + dicoba ulang tiap tick timer; pemilik menyimpan waktu
//    catatan terakhir di Global Variable sehingga pemilik berikutnya melanjutkan tanpa bolong/dobel.
double g_jToken = 0;
string JKey(string k) { return "GDM_J" + k + "_" + _Symbol; }

bool JournalClaim()
  {
   if(g_jOwner || !DMInpJournal || MQLInfoInteger(MQL_TESTER))
      return g_jOwner;
   if(g_jToken == 0)
      g_jToken = 1 + MathRand() + (double)(GetTickCount() % 100000) * 32768.0;
   if(!GlobalVariableCheck(JGV()))
      GlobalVariableTemp(JGV());                       // dibuat dengan nilai 0 = bebas
   if(!GlobalVariableSetOnCondition(JGV(), g_jToken, 0))
      return false;
   g_jOwner = true;
   if(GlobalVariableCheck(JKey("EV")))   g_lastEv   = (datetime)MathMax((double)g_lastEv, GlobalVariableGet(JKey("EV")));
   if(GlobalVariableCheck(JKey("SNAP"))) g_lastSnap = (datetime)GlobalVariableGet(JKey("SNAP"));
   if(GlobalVariableCheck(JKey("SD")))   g_sdLogged = (datetime)GlobalVariableGet(JKey("SD"));
   if(GlobalVariableCheck(JKey("AS")))   g_asLogged = (datetime)GlobalVariableGet(JKey("AS"));
   Print("GoldDayMap: jurnal aktif (", EnumToString((ENUM_TIMEFRAMES)_Period), ") -> MQL5\\Files\\", JSNAP, " & ", JEVT);
   return true;
  }

void JournalSaveState()
  {
   GlobalVariableSet(JKey("EV"), (double)g_lastEv);
   GlobalVariableSet(JKey("SNAP"), (double)g_lastSnap);
   GlobalVariableSet(JKey("SD"), (double)g_sdLogged);
   GlobalVariableSet(JKey("AS"), (double)g_asLogged);
  }

//--- tombol / panel hilang dari chart (dihapus instance lama, program lain, atau pengguna)?
bool NeedsRepair()
  {
   if(g_nd <= 0)
      return false;                                    // belum pernah dibangun: Update() yang menangani
   if(DMInpButtons && ObjectFind(0, BPFX + "B_panel") < 0)
      return true;
   if(DMInpPanelMode != PANEL_OFF && g_vPanel && ArraySize(g_pL) > 0 && ObjectFind(0, PFX + "Pbg") < 0)
      return true;
   return false;
  }

void Deinit(const int reason, bool isFinal = true)
  {
   if(g_jOwner)
     {
      JournalSaveState();
      if(GlobalVariableGet(JGV()) == g_jToken)
         GlobalVariableDel(JGV());                     // instance/chart lain boleh mengambil alih
     }
   EventKillTimer();
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, g_mouseWas);
//--- ganti TF / compile / ubah input: objek DIBIARKAN (instance baru sudah menggambar; lihat GoldPro_Main)
   if(isFinal)
     {
      ObjectsDeleteAll(0, PFX);
      if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE)
         ObjectsDeleteAll(0, BPFX);                    // PIN ikut dihapus bila indikator dilepas
      else
        {
         ObjectsDeleteAll(0, BPFX + "B_");
         ObjectsDeleteAll(0, BPFX + "I_");                // kotak "i" (14 Okt)
         ObjectDelete(0, BPFX + "PROBE");
        }
     }
//--- input diubah / indikator dilepas -> status tombol kembali mengikuti input
   if(reason == REASON_REMOVE || reason == REASON_PARAMETERS)
      GlobalVariablesDeleteAll(VKey(""));
   ChartRedraw();
  }

void Timer()
  {
   if(!g_jOwner && DMInpJournal)
      JournalClaim();     // ambil alih jurnal bila pemilik sebelumnya (mis. instance TF lama) sudah melepas
   Update();
   if(PinTick(true))
      Redraw();   // PIN tersentuh / digeser / dihapus -> panel ikut diperbarui
   static int lastSS = -1;                           // tombol Saldo: status ON / KUNCI dari EA (tiap 2 dtk)
   int ss = SaldoState();
   if(ss != lastSS) { lastSS = ss; SaldoBtn(); TradeGV(); ChartRedraw(); }
   if(g_infoKey != "" && g_nd > 0) InfoCard();       // 14 Okt: kartu info ikut harga & dashboard lain (tiap 2 dtk)
   static datetime lastM1 = 0;                       // label LIVE sesi + kondisi: diperbarui tiap candle M1
   datetime m1 = iTime(_Symbol, PERIOD_M1, 0);
   if(m1 != lastM1 && g_pAdr > 0)
     {
      lastM1 = m1;
      CalcMState(g_pAdr);
      LiveTag();
      ChartRedraw();
     }
  }

int Calculate()
  {
   Update();
   if(PinTick(false))
      Redraw();
   return 0;
  }

//--- rebuild sekali per bar M5 baru; kalau data belum siap, timer mencoba lagi
void Update()
  {
   datetime t = iTime(_Symbol, PERIOD_M5, 0);
   if(t == 0 || t == g_last)
      return;
   if(Rebuild())
      g_last = t;
  }

void Status(string s)
  {
   string n = PFX + "status";
   if(ObjectFind(0, n) < 0)
      Label(n, DMInpButtons ? BtnColR() + 8 : 10, PanelTop(), s, clrYellow);
   else
      ObjectSetString(0, n, OBJPROP_TEXT, s);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
bool Rebuild()
  {
   if(!BuildDays())
      return false;
   ComputeStats();
   ComputeLiveTable();
   ComputeRecent();
//--- volatilitas hari berjalan (candle M5 terakhir yang sudah close, sama seperti GetLive)
   int lastI = g_days[g_nd - 1].i1 - 1;
   if(g5[lastI].time + 300 > TimeTradeServer() && lastI > g_days[g_nd - 1].i0)
      lastI--;
   g_rvr = DayRVR(g_days[g_nd - 1], lastI);
   g_rv2 = DayRV2(g_days[g_nd - 1], lastI);
   g_volK = VolK(g_rvr, g_rv2);
   ObjectsDeleteAll(0, PFX);
   ArrayResize(g_futName, 0);
   ArrayResize(g_futPt, 0);
   DayInfo dl = g_days[g_nd - 1];
   g_pT0 = dl.t0;
   g_pAdr = dl.adr;
   g_pLastBar = g5[dl.i1 - 1].time;
   PinSync();
   int from = MathMax(0, g_nd - DMInpShowDays);
   for(int n = from; n < g_nd; n++)
      DrawDay(g_days[n], n == g_nd - 1);
   FindSweeps(dl.t0, dl.adr);
   if(DMInpShowSweeps)
      DrawSweeps();
   CalcMState(dl.adr);
   if(DMInpShowState)
      DrawStateBox();
   if(DMInpButtons) { ObjectsDeleteAll(0, BPFX + "B_"); ObjectsDeleteAll(0, BPFX + "I_"); ObjectDelete(0, BPFX + "LIVE"); }   // 14 Okt: tombol di depan
   Buttons();
   LiveTag();
   g_raiseTick = GetTickCount();
   if(DMInpPanelMode != PANEL_OFF && g_vPanel)
      Panel(g_days[g_nd - 1]);
   else
      PanelLayout();   // panel tersembunyi: hanya perbarui batas area tombol (untuk probe)
   InfoCard();         // 14 Okt: kartu info kotak "i" (sesudah panel -> tahu posisi panel)
   PinTick(true);
   StraddleAlerts(g_days[g_nd - 1]);
   AsiaAlerts(g_days[g_nd - 1]);
   if(g_jOwner)
      Journal(g_days[g_nd - 1]);
   ChartRedraw();
   MoveFuture();   // sesuaikan panah ke depan dengan zoom & skala harga saat ini
   return true;
  }

//+------------------------------------------------------------------+
//| JURNAL FORWARD TEST                                               |
//| Snapshot peluang tiap DMInpJournalMin menit + setiap kejadian baru. |
//| Hasil sebenarnya dinilai oleh evaluate_journal.py (data MT5).     |
//+------------------------------------------------------------------+
string JGV() { return "GDM_JOURNAL_" + _Symbol; }

void AppendLine(string fname, string header, string line)
  {
   int h = FileOpen(fname, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(h == INVALID_HANDLE)
     {
      Print("GoldDayMap: gagal membuka jurnal ", fname, " err ", GetLastError());
      return;
     }
   if(FileSize(h) == 0)
      FileWriteString(h, header + "\r\n");
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, line + "\r\n");
   FileClose(h);
  }

string SnapHeader()
  {
   string s = "server_time,day,hours_left,price,adr,open,pdc,dir,up_name,up_lvl,p_up_first,p_up_close,"
              "dn_name,dn_lvl,p_dn_close,eq,p_eq_close";
   for(int q = 1; q <= NLV; q++)
      s += StringFormat(",t%du_lvl,t%du_hit,t%du_p,t%dd_lvl,t%dd_hit,t%dd_p", q, q, q, q, q, q);
   return s + ",bk_p,bk_up,bk_dn";
  }

void Journal(const DayInfo &d)
  {
   LiveInfo li;
   GetLive(d, li);
   int last = d.i1 - 1;
   datetime tb = g5[last].time;
   double eq = (d.open + d.pdc) / 2, half = MathAbs(d.open - d.pdc) / 2;

//--- snapshot tiap DMInpJournalMin menit (di awal bar M5, harga = open bar)
   if(li.open && tb >= g_jStart && tb != g_lastSnap && (tb % (DMInpJournalMin * 60)) == 0)
     {
      string s = StringFormat("%s,%s,%.3f,%s,%.2f,%s,%s,%d,%s,%s,%.4f,%.4f,%s,%s,%.4f,%s,%.4f",
                              TimeToString(tb, TIME_DATE | TIME_MINUTES), TimeToString(d.t0, TIME_DATE), li.hoursLeft,
                              Dts(li.cur), d.adr, Dts(d.open), Dts(d.pdc), d.dir,
                              LvlName(li.kUp), Dts(li.lvlUp), li.pUpFirst, li.pUpClose,
                              LvlName(li.kDn), Dts(li.lvlDn), li.pDnClose,
                              Dts(eq), LiveP(MathAbs(li.cur - eq) / d.adr, li.hoursLeft));
      for(int q = 0; q < NLV; q++)
         for(int sd = 1; sd >= -1; sd -= 2)
           {
            double lvl = d.open + sd * LV[q] * d.adr;
            int hit = 0;
            for(int k = d.i0; k <= last; k++)
               if((sd > 0 && g5[k].high >= lvl) || (sd < 0 && g5[k].low <= lvl)) { hit = 1; break; }
            s += StringFormat(",%s,%d,%.4f", Dts(lvl), hit, hit ? 1.0 : LiveP(MathAbs(lvl - li.cur) / d.adr, li.hoursLeft));
           }
      // garis cadangan live (selalu dicatat, walau tombolnya mati): -1 = tidak ada (sisa < 1 jam)
      double bthr = MathMax(0.6, MathMin(0.95, DMInpBackupP / 100.0)), bd = LiveInv(bthr, li.hoursLeft);
      s += StringFormat(",%.2f,%s,%s", bthr, bd > 0 ? Dts(li.cur + bd * d.adr) : "-1", bd > 0 ? Dts(li.cur - bd * d.adr) : "-1");
      AppendLine(JSNAP, SnapHeader(), s);
      g_lastSnap = tb;
     }

//--- kejadian baru (retest / pullback / lewat open) sejak indikator aktif
   Ev ev[];
   ScanDay(d, ev);
   datetime maxT = g_lastEv;
   for(int e = 0; e < ArraySize(ev); e++)
     {
      datetime te = g5[ev[e].k].time;
      if(te <= g_lastEv || te < g_jStart)
         continue;
      string ty; double p;
      if(ev[e].type == 0)
        {
         int b = (int)MathMin(ev[e].num, 3) - 1;
         ty = "retest"; p = Pct(st_bounce[b], st_touch[b]) / 100.0;
        }
      else
         if(ev[e].type == 1) { ty = "pullback";   p = Pct(st_pbCont, st_pb) / 100.0; }
         else                { ty = "lewat_open"; p = Pct(st_invCont, st_inv) / 100.0; }
      string s = StringFormat("%s,%s,%s,%d,%d,%s,%s,%s,%.4f,%s,%s,%s,%.3f,%.2f,%d",
                              TimeToString(te, TIME_DATE | TIME_MINUTES), TimeToString(d.t0, TIME_DATE), ty,
                              ev[e].side, ev[e].num, Dts(ev[e].tip), Dts(ev[e].target), Dts(ev[e].ext), p,
                              Dts(d.open), Dts(d.pdc), Dts(eq), half, d.adr, d.dir);
      AppendLine(JEVT, "server_time,day,type,side,num,tip,target,ext,p_shown,open,pdc,eq,half,adr,dir", s);
      if(te > maxT)
         maxT = te;
     }
   g_lastEv = maxT;

//--- straddle: catat saat order pertama terisi (sekali per hari)
   if(DMInpShowStraddle && g_sdLogged != d.t0)
     {
      Straddle sd;
      CalcStraddle(d, li.last, sd);
      if(sd.side != 0 && g5[sd.kFill].time >= g_jStart)
        {
         double en = (sd.side > 0) ? sd.up : sd.dn, tp = (sd.side > 0) ? sd.tpU : sd.tpD;
         string s = StringFormat("%s,%s,straddle,%d,0,%s,%s,%s,%.4f,%s,%s,%s,%.3f,%.2f,%d",
                                 TimeToString(g5[sd.kFill].time, TIME_DATE | TIME_MINUTES), TimeToString(d.t0, TIME_DATE),
                                 sd.side, Dts(en), Dts(tp), Dts(sd.sl), Pct(st_sdWin, st_sdN) / 100.0,
                                 Dts(d.open), Dts(d.pdc), Dts(eq), half, d.adr, d.dir);
         AppendLine(JEVT, "server_time,day,type,side,num,tip,target,ext,p_shown,open,pdc,eq,half,adr,dir", s);
         g_sdLogged = d.t0;
        }
     }

//--- breakout Asia: catat saat entry terjadi (sekali per hari); dinilai evaluate_journal.py
   if(g_asLogged != d.t0)
     {
      AsiaSig as;
      CalcAsia(d, li.last, as);
      if(as.side != 0 && as.kEntry >= 0 && g5[as.kEntry].time >= g_jStart)
        {
         string s = StringFormat("%s,%s,asia,%d,0,%s,%s,%s,0,%s,%s,%s,%.3f,%.2f,%d",
                                 TimeToString(g5[as.kEntry].time, TIME_DATE | TIME_MINUTES), TimeToString(d.t0, TIME_DATE),
                                 as.side, Dts(as.en), Dts(as.tp), Dts(as.sl), Dts(d.open), Dts(d.pdc), Dts(eq), half, d.adr, d.dir);
         AppendLine(JEVT, "server_time,day,type,side,num,tip,target,ext,p_shown,open,pdc,eq,half,adr,dir", s);
         g_asLogged = d.t0;
        }
     }
   JournalSaveState();   // pemilik berikutnya melanjutkan dari sini (tanpa dobel)
  }

//--- alert breakout Asia (hanya bila rezim vol tinggi, sesuai status panel)
void AsiaAlerts(const DayInfo &d)
  {
   if(!::InpGPAlertAsia || d.pdc <= 0 || d.adr / d.pdc * 100 < 2.0) return;
   LiveInfo li;
   GetLive(d, li);
   AsiaSig as;
   CalcAsia(d, li.last, as);
   if(as.side == 0 || as.kEntry < 0) return;
   ::GP_Notify("asia" + TimeToString(d.t0, TIME_DATE), StringFormat("ASIA BREAKOUT %s @%s SL %s TP %s (hipotesis, DEMO)",
               as.side > 0 ? "BUY" : "SELL", Dts(as.en), Dts(as.sl), Dts(as.tp)), g5[as.kEntry].time);
  }

//+------------------------------------------------------------------+
//| Susun daftar hari dari D1, petakan ke bar M5                      |
//+------------------------------------------------------------------+
bool BuildDays()
  {
   MqlRates d1[];
   int n1 = CopyRates(_Symbol, PERIOD_D1, 0, DMInpStatDays + DMInpAdrDays + 2, d1);
   if(n1 < DMInpAdrDays + 2)
     {
      Status(StringFormat("GoldDayMap: data D1 belum siap (%d bar), mencoba lagi...", n1));
      return false;
     }
   int n5 = CopyRates(_Symbol, PERIOD_M5, 0, (n1 + 1) * 290, g5);
   if(n5 < 300)
     {
      Status(StringFormat("GoldDayMap: data M5 belum siap (%d bar, err %d), mencoba lagi...", n5, GetLastError()));
      return false;
     }
   ArrayResize(g_days, 0);
   g_nd = 0;
   int p = 0;
   for(int j = DMInpAdrDays; j < n1; j++)
     {
      datetime t0 = d1[j].time, t1 = t0 + 86400;
      while(p < n5 && g5[p].time < t0)
         p++;
      int i0 = p, q = p;
      while(q < n5 && g5[q].time < t1)
         q++;
      p = q;
      if(q - i0 < 1 || g5[i0].time > t0 + 3 * 3600)
         continue;                               // data M5 tidak lengkap untuk hari ini
      double s = 0;
      for(int a = 1; a <= DMInpAdrDays; a++)
         s += d1[j - a].high - d1[j - a].low;
      DayInfo d;
      d.t0   = t0;
      d.i0   = i0;
      d.i1   = q;
      d.open = g5[i0].open;
      d.pdc  = d1[j - 1].close;
      d.adr  = s / DMInpAdrDays;
      d.dir  = 0;
      if(q - i0 >= 12)
         d.dir = (g5[i0 + 11].close >= d.open) ? 1 : -1;
      d.done = (j < n1 - 1);
      ArrayResize(g_days, g_nd + 1);
      g_days[g_nd++] = d;
     }
   return g_nd > 0;
  }

int AddEv(Ev &a[], Ev &e)
  {
   int n = ArraySize(a);
   ArrayResize(a, n + 1);
   a[n] = e;
   return n;
  }

//+------------------------------------------------------------------+
//| Deteksi kejadian dalam satu hari                                  |
//+------------------------------------------------------------------+
void ScanDay(const DayInfo &d, Ev &evs[])
  {
   ArrayResize(evs, 0);
   double adr = d.adr, op = d.open;

//--- retest pita open/close (setelah jam pertama)
   double top = MathMax(op, d.pdc), bot = MathMin(op, d.pdc);
   double mid = (top + bot) / 2, half = (top - bot) / 2;
   double band = half + 0.02 * adr, away = half + 0.10 * adr, react = half + 0.15 * adr;
   int side = 0, num = 0, k = d.i0 + 12;
   while(k < d.i1)
     {
      if(side == 0)
        {
         if(g5[k].low > mid + away)
            side = 1;
         else
            if(g5[k].high < mid - away)
               side = -1;
         k++;
         continue;
        }
      if((side > 0 && g5[k].low <= mid + band) || (side < 0 && g5[k].high >= mid - band))
        {
         // GoldPro (3 Okt 2026, research\eq_retest.py): hasil dihitung mulai candle SESUDAH sentuhan. Dulu termasuk
         // candle sentuhan itu sendiri -> pantul terlalu tinggi 3-6 poin (#2 63.6 / #3+ 67.1%) karena gerak di dalam candle
         // itu tidak bisa diambil trader. Sekarang = yang bisa ditradingkan (M1 dari menit sesudah sentuh: 58.6/59.5/61.3%)
         // = geometri jarak (60.5-60.8%); pita EQ asli = pita palsu -> EQ tidak istimewa, angka ini peta, bukan edge.
         int out = -1, j;
         for(j = k + 1; j < d.i1; j++)
           {
            bool up = g5[j].high >= mid + react, dn = g5[j].low <= mid - react;
            if(up && dn) { out = 0; break; }
            if(up)       { out = (side > 0) ? 1 : 2; break; }
            if(dn)       { out = (side < 0) ? 1 : 2; break; }
           }
         num++;
         Ev e;
         e.type = 0; e.k = k; e.side = side; e.num = num; e.outcome = out;
         e.tip = (side > 0) ? g5[k].low : g5[k].high;
         e.target = op + side * LV[0] * adr;
         e.ext = 0;
         AddEv(evs, e);
         side = 0;
         if(out < 0)
            break;
         k = j + 1;
         continue;
        }
      k++;
     }

//--- pullback & lewat open, untuk kedua arah
   for(int x = 1; x >= -1; x -= 2)
     {
      bool reached = false, pend = false, invalid = false;
      double ext = 0, pbExt = 0, invExt = 0;
      int pbIdx = -1, invIdx = -1;
      for(int b = d.i0; b < d.i1; b++)
        {
         double fav = (x > 0) ? g5[b].high : g5[b].low;
         double adv = (x > 0) ? g5[b].low  : g5[b].high;
         if(!reached)
           {
            if((fav - op) * x >= 0.25 * adr) { reached = true; ext = fav; }
            continue;
           }
         if(invalid)
           {
            if((fav - invExt) * x >= 0.10 * adr) { evs[invIdx].outcome = 1; break; }
            continue;
           }
         if((fav - ext) * x > 0)
            ext = fav;
         if(pend && (fav - pbExt) * x >= 0.10 * adr)
           {
            evs[pbIdx].outcome = 1;
            pend = false;
           }
         if((adv - op) * x <= 0)
           {
            if(pend) { evs[pbIdx].outcome = 2; pend = false; }
            Ev e;
            e.type = 2; e.k = b; e.side = x; e.num = 0; e.outcome = -1;
            e.tip = adv; e.target = op - x * LV[0] * adr; e.ext = ext;
            invIdx = AddEv(evs, e);
            invalid = true; invExt = ext;
            continue;
           }
         if(!pend && (ext - adv) * x >= 0.382 * (ext - op) * x)
           {
            double depth = (ext - adv) * x / ((ext - op) * x);
            double tgt = ext + x * 0.25 * adr;
            for(int q = 0; q < NLV; q++)
              {
               double lvl = op + x * LV[q] * adr;
               if((lvl - ext) * x > 0) { tgt = lvl; break; }
              }
            Ev e;
            e.type = 1; e.k = b; e.side = x; e.num = (int)MathRound(depth * 100); e.outcome = -1;
            e.tip = adv; e.target = tgt; e.ext = ext;
            pbIdx = AddEv(evs, e);
            pend = true; pbExt = ext;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Statistik historis                                                |
//+------------------------------------------------------------------+
//--- T0: titik tengah EQ dan T1 di sisi s (+1 atas, -1 bawah)
double T0Lvl(const DayInfo &d, int s)
  {
   double eq = (d.open + d.pdc) / 2;
   return (eq + d.open + s * LV[0] * d.adr) / 2;
  }

//--- indeks M5 bar 09:30 ET (pembukaan bursa saham NY) pada hari d; -1 bila belum/tidak ada
int NYOpenIdx(const DayInfo &d)
  {
   datetime tt = ::GP_ServerAtLocalHour(d.t0 + 12 * 3600, 9, false) + 30 * 60;
   for(int k = d.i0; k < d.i1; k++)
     {
      if(g5[k].time >= tt)
         return (g5[k].time - tt <= 600) ? k : -1;
     }
   return -1;
  }

//--- Open NY sudah "menjauh" (>= 0.05 ADR, dari close M5) lalu KEMBALI disentuh? kembali = indeks bar (-1 belum);
//    armed = sudah menjauh. Dicek s/d indeks lastK.
int NYBack(const DayInfo &d, int kn, int lastK, bool &armed)
  {
   armed = false;
   double lv = g5[kn].open;
   for(int k = kn; k <= lastK && k < d.i1; k++)
     {
      if(!armed)
        {
         if(MathAbs(g5[k].close - lv) >= 0.05 * d.adr) armed = true;
         continue;
        }
      if(g5[k].low <= lv && g5[k].high >= lv)
         return k;
     }
   return -1;
  }

void ComputeStats()
  {
   st_days = st_pb = st_pbCont = st_inv = st_invCont = 0;
   st_any1 = st_both1 = 0;
   st_hitS0 = st_hitO0 = st_any0 = st_both0 = 0;
   st_nyN = st_nyBack = 0;
   st_sdN = st_sdWin = st_sdSkip = 0;
   st_sdR = 0;
   ArrayInitialize(st_hitS, 0);
   ArrayInitialize(st_hitO, 0);
   ArrayInitialize(st_touch, 0);
   ArrayInitialize(st_bounce, 0);
   for(int n = 0; n < g_nd; n++)
     {
      if(!g_days[n].done || g_days[n].i1 - g_days[n].i0 < 200 || g_days[n].dir == 0)
         continue;
      st_days++;
      double op = g_days[n].open, adr = g_days[n].adr;
      double hmax = -DBL_MAX, lmin = DBL_MAX;
      for(int k = g_days[n].i0; k < g_days[n].i1; k++)
        {
         hmax = MathMax(hmax, g5[k].high);
         lmin = MathMin(lmin, g5[k].low);
        }
      for(int q = 0; q < NLV; q++)
        {
         bool up = hmax >= op + LV[q] * adr, dn = lmin <= op - LV[q] * adr;
         bool sa = (g_days[n].dir > 0) ? up : dn, lw = (g_days[n].dir > 0) ? dn : up;
         if(sa) st_hitS[q]++;
         if(lw) st_hitO[q]++;
         if(q == 0 && (up || dn)) st_any1++;
         if(q == 0 && up && dn)   st_both1++;
        }
      bool u0 = hmax >= T0Lvl(g_days[n], 1), d0 = lmin <= T0Lvl(g_days[n], -1);
      if((g_days[n].dir > 0) ? u0 : d0) st_hitS0++;
      if((g_days[n].dir > 0) ? d0 : u0) st_hitO0++;
      if(u0 || d0) st_any0++;
      if(u0 && d0) st_both0++;
      int kn = NYOpenIdx(g_days[n]);
      if(kn >= 0)
        {
         bool armed;
         if(NYBack(g_days[n], kn, g_days[n].i1 - 1, armed) >= 0) st_nyBack++;
         if(armed) st_nyN++;
        }
      Ev ev[];
      ScanDay(g_days[n], ev);
      for(int e = 0; e < ArraySize(ev); e++)
        {
         if(ev[e].type == 0 && (ev[e].outcome == 1 || ev[e].outcome == 2))
           {
            int b = (int)MathMin(ev[e].num, 3) - 1;
            st_touch[b]++;
            if(ev[e].outcome == 1) st_bounce[b]++;
           }
         if(ev[e].type == 1) { st_pb++;  if(ev[e].outcome == 1) st_pbCont++; }
         if(ev[e].type == 2) { st_inv++; if(ev[e].outcome == 1) st_invCont++; }
        }
      Straddle sd;
      CalcStraddle(g_days[n], g_days[n].i1 - 1, sd);
      if(sd.skipped) st_sdSkip++;
      if(sd.side != 0 && sd.result > 0)
        {
         st_sdN++;
         st_sdR += sd.R;
         if(sd.R > 0) st_sdWin++;
        }
     }
  }

//+------------------------------------------------------------------+
//| Straddle EQ: simulasi di bar M5 (konservatif: bar yang menyentuh  |
//| entry & SL sekaligus dihitung SL)                                 |
//+------------------------------------------------------------------+
void CalcStraddle(const DayInfo &d, int lastIdx, Straddle &s)
  {
   s.valid = false; s.skipped = false; s.side = 0; s.kFill = -1; s.kExit = -1; s.result = -1; s.R = 0;
   double eq = (d.open + d.pdc) / 2;
   s.risk = DMInpSdDist * d.adr;
   s.up = eq + s.risk; s.dn = eq - s.risk; s.sl = eq;
   s.tpU = s.up + DMInpSdRR * s.risk; s.tpD = s.dn - DMInpSdRR * s.risk;
   int st = d.i0 + 1;                        // bar M5 kedua = menit ke-5 setelah market buka
   if(st > lastIdx || st >= d.i1)
      return;
   s.valid = true;
   double p0 = g5[st].open;
   if(p0 >= s.up || p0 <= s.dn) { s.skipped = true; return; }
   for(int k = st; k <= lastIdx; k++)
     {
      double sp = g5[k].spread * _Point;
      if(s.side == 0)
        {
         bool bu = g5[k].high + sp >= s.up, se = g5[k].low <= s.dn;
         if(bu && se)
            s.side = (MathAbs(g5[k].open - s.up) <= MathAbs(g5[k].open - s.dn)) ? 1 : -1;
         else
            if(bu) s.side = 1;
            else
               if(se) s.side = -1;
               else continue;
         s.kFill = k;
         if((s.side > 0 && g5[k].low <= s.sl) || (s.side < 0 && g5[k].high + sp >= s.sl))
           { s.result = 2; s.R = -1; s.kExit = k; return; }
         continue;
        }
      if(s.side > 0)
        {
         if(g5[k].low <= s.sl)   { s.result = 2; s.R = -1;      s.kExit = k; return; }
         if(g5[k].high >= s.tpU) { s.result = 1; s.R = DMInpSdRR; s.kExit = k; return; }
        }
      else
        {
         if(g5[k].high + sp >= s.sl)  { s.result = 2; s.R = -1;      s.kExit = k; return; }
         if(g5[k].low + sp <= s.tpD)  { s.result = 1; s.R = DMInpSdRR; s.kExit = k; return; }
        }
     }
   if(s.side != 0 && d.done)
     {
      int k = d.i1 - 1;
      double px = (s.side > 0) ? g5[k].close : g5[k].close + g5[k].spread * _Point;
      double en = (s.side > 0) ? s.up : s.dn;
      s.R = (px - en) * s.side / s.risk; s.result = 3; s.kExit = k;
     }
  }

//--- baris panel: lot untuk DMInpRiskPct% saldo; bila lot minimum pun melebihi itu -> tampilkan risiko nyata (merah)
void LotLine(string &L[], color &K[], double riskPrice)
  {
   double lot = LotFor(riskPrice), mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(!(lot >= mn && lot > 0))
     {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE), cs = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      double pct = (bal > 0) ? riskPrice * cs * mn / bal * 100 : 0;
      AddLine(L, K, StringFormat(" SL $%.1f: lot %.2f = risk %.1f%%!", riskPrice, mn, pct), pct > 2 ? clrTomato : DMInpPanelColor);
     }
   else
      AddLine(L, K, StringFormat(" SL $%.1f: lot %.2f (risk %.1f%%)", riskPrice, lot, DMInpRiskPct), DMInpPanelColor);
  }

//--- lot untuk risiko DMInpRiskPct% saldo dengan jarak SL `riskPrice` (akun USD)
double LotFor(double riskPrice)
  {
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double cs = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(riskPrice <= 0 || cs <= 0 || step <= 0)
      return 0;
   double lot = bal * DMInpRiskPct / 100.0 / (riskPrice * cs);
   return MathFloor(lot / step) * step;
  }

void DrawStraddle(const DayInfo &d, const Straddle &s, string id, bool isLast, datetime tA, datetime tB)
  {
   color cb = DMInpBuyColor, cs = DMInpSellColor;
   HLine(id + "SDb", tA, tB, s.up, cb, STYLE_SOLID, 2);
   HLine(id + "SDs", tA, tB, s.dn, cs, STYLE_SOLID, 2);
   HLine(id + "SDtb", tA, tB, s.tpU, cb, STYLE_DASHDOT, 1);
   HLine(id + "SDts", tA, tB, s.tpD, cs, STYLE_DASHDOT, 1);
   string lb = "BUY STOP", ls = "SELL STOP";
   if(isLast)
     {
      double lot = LotFor(s.risk);
      string lt = (lot >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) ? StringFormat(" | lot %.2f (%.1f%%)", lot, DMInpRiskPct) : " | modal kurang utk min lot";
      lb = StringFormat("BUY STOP %s | SL %s (EQ) | TP %s%s", Dts(s.up), Dts(s.sl), Dts(s.tpU), lt);
      ls = StringFormat("SELL STOP %s | SL %s (EQ) | TP %s%s", Dts(s.dn), Dts(s.sl), Dts(s.tpD), lt);
     }
   Text(id + "SDbL", tA, s.up, lb, cb, ANCHOR_LEFT_LOWER);
   Text(id + "SDsL", tA, s.dn, ls, cs, ANCHOR_LEFT_UPPER);
   Text(id + "SDtbL", tA, s.tpU, "TP buy", cb, ANCHOR_LEFT_LOWER);
   Text(id + "SDtsL", tA, s.tpD, "TP sell", cs, ANCHOR_LEFT_UPPER);
   if(s.skipped)
      Text(id + "SDx", tA, s.sl, "straddle dilewati", clrSilver, ANCHOR_LEFT_UPPER);
   if(s.side != 0)
     {
      double en = (s.side > 0) ? s.up : s.dn;
      Arrow(id + "SDf", g5[s.kFill].time, en, (s.side > 0) ? 233 : 234, (s.side > 0) ? cb : cs);
      ObjectSetInteger(0, id + "SDf", OBJPROP_ANCHOR, (s.side > 0) ? ANCHOR_TOP : ANCHOR_BOTTOM);
      if(s.result > 0)
        {
         double px = (s.result == 1) ? ((s.side > 0) ? s.tpU : s.tpD) : ((s.result == 2) ? s.sl : g5[s.kExit].close);
         color cx = (s.R > 0) ? clrLimeGreen : clrTomato;
         Arrow(id + "SDe", g5[s.kExit].time, px, (s.result == 1) ? 252 : ((s.result == 2) ? 251 : 159), cx);
         Text(id + "SDeT", g5[s.kExit].time, px, StringFormat(" %+.1fR", s.R), cx, ANCHOR_LEFT);
        }
     }
  }

string SdStatus(const Straddle &s)
  {
   if(!s.valid)   return "menunggu menit ke-5";
   if(s.skipped)  return "DILEWATI (harga sudah di luar zona)";
   if(s.side == 0) return "menunggu (order belum tersentuh)";
   string sd = (s.side > 0) ? "BUY" : "SELL";
   if(s.result == 1) return sd + " kena TP (+" + DoubleToString(s.R, 1) + "R)";
   if(s.result == 2) return sd + " kena SL (-1R)";
   if(s.result == 3) return sd + StringFormat(" ditutup akhir hari (%+.2fR)", s.R);
   return sd + " AKTIF - batalkan order lawan (OCO)";
  }

//+------------------------------------------------------------------+
//| Tabel peluang live dari hari-hari historis                        |
//+------------------------------------------------------------------+
void ComputeLiveTable()
  {
   for(int a = 0; a < NLB; a++)
     {
      lh_cnt[a] = 0;
      e_sum[a] = 0;
      e2_sum[a] = 0;
      e_cnt[a] = 0;
      if(a < HHB)
         for(int b = 0; b < HHD; b++) { hh_cnt[a][b] = 0; hh_brk[a][b] = 0; }
      for(int b = 0; b < NDB; b++)
         lh_hit[a][b] = 0;
     }
   double FH[], FL[];
   for(int n = 0; n < g_nd; n++)
     {
      if(!g_days[n].done || g_days[n].i1 - g_days[n].i0 < 200)
         continue;
      int i0 = g_days[n].i0, len = g_days[n].i1 - i0;
      double adr = g_days[n].adr;
      datetime tEnd = g_days[n].t0 + 86400;
      ArrayResize(FH, len);
      ArrayResize(FL, len);
      double fh = -DBL_MAX, fl = DBL_MAX;
      for(int k = len - 1; k >= 0; k--)
        {
         fh = MathMax(fh, g5[i0 + k].high); FH[k] = fh;
         fl = MathMin(fl, g5[i0 + k].low);  FL[k] = fl;
        }
      double rh = -DBL_MAX, rl = DBL_MAX;
      int kr = 0;
      for(int k = 0; k < len - 1; k += 3)
        {
         for(; kr <= k; kr++) { rh = MathMax(rh, g5[i0 + kr].high); rl = MathMin(rl, g5[i0 + kr].low); }
         int eb = (int)MathMin(NLB - 1, (g5[i0 + k].time - g5[i0].time) / 3600);
         e_sum[eb] += (rh - rl) / adr;
         e2_sum[eb] += Range2h(i0, i0 + k) / adr;
         e_cnt[eb]++;
         if(k >= 3)   // puncak & dasar berjalan: tertembus sebelum tutup?
           {
            int hb = HHBucket((double)(tEnd - g5[i0 + k].time - 300) / 3600.0);
            double c0 = g5[i0 + k].close;
            int qh = (int)MathMin(HHD - 1, MathMax(0, (rh - c0) / adr / 0.1));
            int ql = (int)MathMin(HHD - 1, MathMax(0, (c0 - rl) / adr / 0.1));
            hh_cnt[hb][qh]++;
            if(FH[k + 1] > rh) hh_brk[hb][qh]++;
            hh_cnt[hb][ql]++;
            if(FL[k + 1] < rl) hh_brk[hb][ql]++;
           }
         int lb = (int)MathMin(NLB - 1, MathMax(0, (tEnd - g5[i0 + k].time) / 3600));
         double c = g5[i0 + k].close;
         double up = (FH[k + 1] - c) / adr, dn = (c - FL[k + 1]) / adr;
         lh_cnt[lb] += 2;
         for(int q = 0; q < NDB; q++)
           {
            double dist = q * 0.05;
            if(up >= dist) lh_hit[lb][q]++;
            if(dn >= dist) lh_hit[lb][q]++;
           }
        }
     }
  }

//--- peluang harga menyentuh level sejauh `dist` ADR sebelum tutup, dengan sisa `hours` jam
double LiveP(double dist, double hours)
  {
   if(hours <= 0)
      return 0.0;
   int lb = (int)MathMin(NLB - 1, MathMax(0, hours));
   if(lh_cnt[lb] < 50)
      return -1.0;
   double x = MathMax(0.0, dist) / g_volK / 0.05;   // jarak efektif (hari volatil -> jarak terasa lebih dekat)
   int q = (int)MathFloor(x);
   if(q >= NDB - 1)
      return (double)lh_hit[lb][NDB - 1] / lh_cnt[lb];
   double p0 = (double)lh_hit[lb][q] / lh_cnt[lb], p1 = (double)lh_hit[lb][q + 1] / lh_cnt[lb];
   return p0 + (p1 - p0) * (x - q);
  }

//--- kebalikan LiveP: jarak terjauh (ADR) yang peluangnya masih >= thr. -1 = tidak ada / data kurang.
//    Garis cadangan 80% diuji 2017-2026 (230 rb snapshot): tersentuh atas 80.2% / bawah 79.4%,
//    tiap tahun 77-82%; sisa jam < 1 hanya ~70% -> tidak ditampilkan.
double LiveInv(double thr, double hours)
  {
   if(hours < 1.0)
      return -1.0;
   int lb = (int)MathMin(NLB - 1, MathMax(0, hours));
   if(lh_cnt[lb] < 50)
      return -1.0;
   double c = lh_cnt[lb];
   if(lh_hit[lb][0] / c < thr)
      return -1.0;
   int qa = 0;
   for(int q = 0; q < NDB; q++)
      if(lh_hit[lb][q] / c >= thr)
         qa = q;
   if(qa == NDB - 1)
      return qa * 0.05 * g_volK;
   double p0 = lh_hit[lb][qa] / c, p1 = lh_hit[lb][qa + 1] / c;
   return (qa + (p0 - thr) / (p0 - p1)) * 0.05 * g_volK;
  }

//--- rvr hari d s/d candle `last`: rentang hari ini / rentang rata-rata pada jam yang sama sejak buka
double DayRVR(const DayInfo &d, int last)
  {
   if(last < d.i0 || d.adr <= 0)
      return 1.0;
   double hi = -DBL_MAX, lo = DBL_MAX;
   for(int k = d.i0; k <= last; k++) { hi = MathMax(hi, g5[k].high); lo = MathMin(lo, g5[k].low); }
   int eb = (int)MathMin(NLB - 1, (g5[last].time - g5[d.i0].time) / 3600);
   if(e_cnt[eb] < 20 || e_sum[eb] <= 0)
      return 1.0;
   return MathMax(0.4, MathMin(3.0, (hi - lo) / d.adr / (e_sum[eb] / e_cnt[eb])));
  }

//--- rentang 24 candle M5 terakhir (2 jam) di dalam hari yang sama: candle i0..k
double Range2h(int i0, int k)
  {
   double hi = -DBL_MAX, lo = DBL_MAX;
   for(int j = MathMax(i0, k - RV2_BARS + 1); j <= k; j++) { hi = MathMax(hi, g5[j].high); lo = MathMin(lo, g5[j].low); }
   return hi - lo;
  }

//--- rv2 hari d s/d candle `last`: rentang 2 jam terakhir / rentang 2 jam rata-rata pada jam yang sama sejak buka
double DayRV2(const DayInfo &d, int last)
  {
   if(last < d.i0 || d.adr <= 0)
      return 1.0;
   int eb = (int)MathMin(NLB - 1, (g5[last].time - g5[d.i0].time) / 3600);
   if(e_cnt[eb] < 20 || e2_sum[eb] <= 0)
      return 1.0;
   return MathMax(0.3, MathMin(4.0, Range2h(d.i0, last) / d.adr / (e2_sum[eb] / e_cnt[eb])));
  }

double VolK(double rvr, double rv2)
  {
   return MathPow(rvr, MathMax(0.0, DMInpVolB1)) * MathPow(rv2, MathMax(0.0, DMInpVolB2));
  }

string RvrTxt()
  {
   double m = MathMax(g_rvr, g_rv2);
   return StringFormat("Gerak: hari %.1fx | 2j %.1fx%s", g_rvr, g_rv2,
                       m >= 1.8 ? " SANGAT" : (m >= 1.4 ? " tinggi" : (m < 0.7 ? " sepi" : "")));
  }
color RvrClr() { return (MathMax(g_rvr, g_rv2) >= 1.4) ? clrGold : ((MathMax(g_rvr, g_rv2) < 0.7) ? clrSilver : DMInpPanelColor); }

double BackupThr() { return MathMax(0.6, MathMin(0.95, DMInpBackupP / 100.0)); }

//--- cek RC_DAYS hari terakhir yang sudah selesai: target T1-T4 searah/lawan & garis cadangan
//    (replay tiap 15 menit, sama dengan uji 2017-26). Monitor rezim: jauh dari statistik -> pasar berubah.
void ComputeRecent()
  {
   st_rcDays = st_bkN = st_bkHit = 0;
   ArrayInitialize(st_rcS, 0);
   ArrayInitialize(st_rcO, 0);
   double thr = BackupThr();
   double FH[], FL[];
   for(int n = g_nd - 1; n >= 0 && st_rcDays < RC_DAYS; n--)
     {
      if(!g_days[n].done || g_days[n].i1 - g_days[n].i0 < 200 || g_days[n].dir == 0)
         continue;
      st_rcDays++;
      int i0 = g_days[n].i0, len = g_days[n].i1 - i0;
      double op = g_days[n].open, adr = g_days[n].adr;
      ArrayResize(FH, len);
      ArrayResize(FL, len);
      double fh = -DBL_MAX, fl = DBL_MAX;
      for(int k = len - 1; k >= 0; k--)
        {
         fh = MathMax(fh, g5[i0 + k].high); FH[k] = fh;
         fl = MathMin(fl, g5[i0 + k].low);  FL[k] = fl;
        }
      for(int q = 0; q < NLV; q++)
        {
         bool up = FH[0] >= op + LV[q] * adr, dn = FL[0] <= op - LV[q] * adr;
         if((g_days[n].dir > 0) ? up : dn) st_rcS[q]++;
         if((g_days[n].dir > 0) ? dn : up) st_rcO[q]++;
        }
      double rh = -DBL_MAX, rl = DBL_MAX;
      int kr = 0;
      for(int k = 0; k < len - 1; k += 3)
        {
         // garis cadangan hari itu memakai rvr hari itu sendiri (sama seperti yang tampil live)
         for(; kr <= k; kr++) { rh = MathMax(rh, g5[i0 + kr].high); rl = MathMin(rl, g5[i0 + kr].low); }
         int eb = (int)MathMin(NLB - 1, (g5[i0 + k].time - g5[i0].time) / 3600);
         double E = (e_cnt[eb] >= 20) ? e_sum[eb] / e_cnt[eb] : 0, E2 = (e_cnt[eb] >= 20) ? e2_sum[eb] / e_cnt[eb] : 0;
         g_volK = VolK((E > 0) ? MathMax(0.4, MathMin(3.0, (rh - rl) / adr / E)) : 1.0,
                       (E2 > 0) ? MathMax(0.3, MathMin(4.0, Range2h(i0, i0 + k) / adr / E2)) : 1.0);
         double bd = LiveInv(thr, (double)(g_days[n].t0 + 86400 - g5[i0 + k].time - 300) / 3600.0);
         if(bd <= 0)
            continue;
         double c = g5[i0 + k].close;
         st_bkN += 2;
         if(FH[k + 1] >= c + bd * adr) st_bkHit++;
         if(FL[k + 1] <= c - bd * adr) st_bkHit++;
        }
     }
  }

int HHBucket(double hours)
  {
   if(hours < 1)  return 0;
   if(hours < 2)  return 1;
   if(hours < 4)  return 2;
   if(hours < 6)  return 3;
   if(hours < 9)  return 4;
   if(hours < 12) return 5;
   if(hours < 16) return 6;
   return 7;
  }

//--- peluang puncak/dasar hari ini BERTAHAN (tidak tertembus) s/d tutup; dist = jarak harga dari puncak/dasar (x ADR).
//    Monoton: makin jauh harga dari puncak, peluang bertahan tidak turun. -1 = data kurang.
double HoldP(double dist, double hours)
  {
   if(hours <= 0.05)
      return 1.0;
   int hb = HHBucket(hours);
   int q = (int)MathMin(HHD - 1, MathMax(0, dist / g_volK / 0.1));
   double best = -1.0;
   for(int i = 0; i <= q; i++)
      if(hh_cnt[hb][i] >= 30)
         best = MathMax(best, 1.0 - (double)hh_brk[hb][i] / hh_cnt[hb][i]);
   return best;
  }

//--- status live SEKARANG (untuk probe & PIN, di antara dua Rebuild)
bool LiveNow(double &hl)
  {
   datetime now = TimeTradeServer();
   hl = (double)(g_pT0 + 86400 - now) / 3600.0;
   return g_pT0 > 0 && g_pAdr > 0 && hl > 0.05 && now - g_pLastBar < 15 * 60;
  }

//--- kondisi live hari berjalan: garis terdekat di atas/bawah dan peluangnya
void GetLive(const DayInfo &d, LiveInfo &li)
  {
   // pakai candle M5 terakhir yang SUDAH CLOSE (bukan candle yang sedang berjalan)
   datetime now = TimeTradeServer();
   int last = d.i1 - 1;
   if(g5[last].time + 300 > now && last > d.i0)
      last--;
   li.last = last;
   li.cur = g5[last].close;
   li.hoursLeft = (double)(d.t0 + 86400 - g5[last].time - 300) / 3600.0;
   // jam server berjalan (bukan tick terakhir): saat libur/akhir hari dianggap tutup
   li.open = (li.hoursLeft > 0.05) && (now < d.t0 + 86400) && (now - g5[last].time < 15 * 60);
   li.step = 0.25 * d.adr;
   double kf = (li.cur - d.open) / li.step;
   li.kDn = (int)MathFloor(kf);
   li.kUp = li.kDn + 1;
   if(kf == li.kDn) li.kDn--;
   li.lvlUp = d.open + li.kUp * li.step;
   li.lvlDn = d.open + li.kDn * li.step;
   li.pUpFirst = (li.cur - li.lvlDn) / (li.lvlUp - li.lvlDn);   // teruji: setara geometri jarak
   li.pUpClose = LiveP((li.lvlUp - li.cur) / d.adr, li.hoursLeft);
   li.pDnClose = LiveP((li.cur - li.lvlDn) / d.adr, li.hoursLeft);
  }

string LvlName(int k)
  {
   if(k == 0) return "EQ/open";
   return StringFormat("T%d %s", MathAbs(k), (k > 0) ? "atas" : "bawah");
  }

string PStr(double p) { return (p < 0) ? "n/a" : StringFormat("%.0f%%", p * 100); }

//--- peluang live sebagai teks; jarak di luar jangkauan tabel (> 1.5 ADR efektif) -> "<x%" (batas atas, bukan nilai tepat)
string PStrD(double dist, double hours)
  {
   double p = LiveP(dist, hours);
   if(p >= 0 && MathMax(0.0, dist) / g_volK >= (NDB - 1) * 0.05)
      return "<" + PStr(p);
   return PStr(p);
  }

double Pct(int a, int b) { return (b > 0) ? 100.0 * a / b : 0.0; }
string Dts(double v)     { return DoubleToString(v, _Digits); }

//+------------------------------------------------------------------+
//| Gambar satu hari                                                  |
//+------------------------------------------------------------------+
void DrawDay(const DayInfo &d, bool isLast)
  {
   string id = PFX + TimeToString(d.t0, TIME_DATE) + "_";
   datetime tA = g5[d.i0].time, tB = d.t0 + 86400;
   LiveInfo li;
   GetLive(d, li);

//--- pita open / close kemarin + equilibrium
   double top = MathMax(d.open, d.pdc), bot = MathMin(d.open, d.pdc), eq = (top + bot) / 2;
   double minh = 0.02 * d.adr;
   if(top - bot < minh) { top = eq + minh / 2; bot = eq - minh / 2; }
   Rect(id + "band", tA, top, tB, bot, DMInpBandColor);
   HLine(id + "eq", tA, tB, eq, DMInpEqColor, STYLE_DASH, 1);
   Tip(id + "band", "Pita = open " + Dts(d.open) + " s/d close kemarin " + Dts(d.pdc) + " (hitungan harga)");
   Tip(id + "eq", "EQ = (open + close kemarin) / 2 = " + Dts(eq) + "\nTersentuh ~98% hari (dekat open)");
   // label lengkap hanya di hari terakhir, di sisi KIRI pita agar tidak menabrak hari berikutnya
   Text(id + "eqT", tA, top, isLast ? "EQ  open " + Dts(d.open) + " / close kmrn " + Dts(d.pdc) : "EQ",
        DMInpEqColor, ANCHOR_LEFT_LOWER);

//--- garis target
   for(int q = 0; q < NLV && g_vTarget; q++)
      for(int s = 1; s >= -1; s -= 2)
        {
         double lvl = d.open + s * LV[q] * d.adr;
         bool searah = (d.dir != 0 && s == d.dir);
         color c = (d.dir == 0) ? DMInpNeutralColor : ((s > 0) ? DMInpUpColor : DMInpDnColor);
         string nm = id + "T" + IntegerToString(q + 1) + ((s > 0) ? "u" : "d");
         HLine(nm, tA, tB, lvl, c, searah ? STYLE_SOLID : STYLE_DOT, 1);
         double pc = searah ? Pct(st_hitS[q], st_days) : Pct(st_hitO[q], st_days);
         int hitK = -1;
         for(int k = d.i0; k < d.i1; k++)
            if((s > 0 && g5[k].high >= lvl) || (s < 0 && g5[k].low <= lvl)) { hitK = k; break; }
         string tx;
         if(isLast)
           {
            tx = StringFormat("T%d %s%.2f ADR  %s", q + 1, (s > 0) ? "+" : "-", LV[q], Dts(lvl));
            if(d.dir != 0)
               tx += StringFormat("  | %s %.0f%%", searah ? "searah" : "lawan", pc);
            if(hitK >= 0)
               tx += "  | TERCAPAI";
            else
               if(li.open)
                  tx += "  | sisa " + PStrD(MathAbs(lvl - li.cur) / d.adr, li.hoursLeft);
           }
         else
            tx = (d.dir != 0) ? StringFormat("T%d %.0f%%", q + 1, pc) : StringFormat("T%d", q + 1);
         // hari lama: label di awal hari (kiri); hari terakhir: di ujung kanan
         if(isLast)
            Text(nm + "L", tB, lvl, tx, c, (s > 0) ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER);
         else
            Text(nm + "L", tA, lvl, tx, c, (s > 0) ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
         if(DMInpShowTargetsHit && hitK >= 0)
            Arrow(nm + "H", g5[hitK].time, lvl, 252, c);
         string tip = StringFormat("T%d %s = open %s %.2f x ADR %.2f = %s", q + 1, (s > 0) ? "atas" : "bawah",
                                   (s > 0) ? "+" : "-", LV[q], d.adr, Dts(lvl));
         if(d.dir != 0)
            tip += StringFormat("\n%s jam pertama: tersentuh %.0f%% hari (250 hari)", searah ? "Searah" : "Lawan", pc);
         if(hitK >= 0)
            tip += "\nTERCAPAI " + ::GP_LocalTime(g5[hitK].time) + " " + ::InpLocalTZName;
         else
            if(isLast && li.open)
               tip += "\nPeluang tersentuh s/d tutup: " + PStrD(MathAbs(lvl - li.cur) / d.adr, li.hoursLeft);
         Tip(nm, tip);
         Tip(nm + "L", tip);
        }

//--- garis T0 = tengah EQ - T1 (usulan pengguna; uji t0_test.py 2017-26). Target/peta, BUKAN titik entry.
   for(int s = 1; s >= -1 && g_vTarget && DMInpShowT0; s -= 2)
     {
      double lvl = T0Lvl(d, s);
      bool searah = (d.dir != 0 && s == d.dir);
      color c = (d.dir == 0) ? DMInpNeutralColor : ((s > 0) ? DMInpUpColor : DMInpDnColor);
      string nm = id + "T0" + ((s > 0) ? "u" : "d");
      HLine(nm, tA, tB, lvl, c, STYLE_DASHDOTDOT, 1);
      double pc = searah ? Pct(st_hitS0, st_days) : Pct(st_hitO0, st_days);
      int hitK = -1;
      for(int k = d.i0; k < d.i1; k++)
         if((s > 0 && g5[k].high >= lvl) || (s < 0 && g5[k].low <= lvl)) { hitK = k; break; }
      string tx;
      if(isLast)
        {
         tx = "T0 " + Dts(lvl);
         if(d.dir != 0)
            tx += StringFormat("  | %s %.0f%%", searah ? "searah" : "lawan", pc);
         if(hitK >= 0)
            tx += "  | TERCAPAI";
         else
            if(li.open)
               tx += "  | sisa " + PStrD(MathAbs(lvl - li.cur) / d.adr, li.hoursLeft);
        }
      else
         tx = (d.dir != 0) ? StringFormat("T0 %.0f%%", pc) : "T0";
      // label di AWAL garis (kiri, seperti label EQ): ujung kanan hari (24:00 server) sering di luar layar dan
      // area kanan sudah dipakai label panah live & Cadangan 80% (harga dekat T0 -> bertumpuk)
      Text(nm + "L", tA, lvl, tx, c, (s > 0) ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
      if(DMInpShowTargetsHit && hitK >= 0)
         Arrow(nm + "H", g5[hitK].time, lvl, 252, c);
      string tip = StringFormat("T0 %s = tengah EQ & T1 %s = (%s + %s) / 2 = %s", (s > 0) ? "atas" : "bawah", (s > 0) ? "atas" : "bawah",
                                Dts((d.open + d.pdc) / 2), Dts(d.open + s * LV[0] * d.adr), Dts(lvl));
      tip += StringFormat("\n250 hari: salah satu sisi %.0f%%, keduanya %.0f%%", Pct(st_any0, st_days), Pct(st_both0, st_days));
      if(d.dir != 0)
         tip += StringFormat("\n%s jam pertama: tersentuh %.0f%% hari", searah ? "Searah" : "Lawan", pc);
      tip += "\nUji 2017-26: salah satu sisi 100% (tiap tahun 99.6-100%), keduanya 66%"
             "\nSetelah T0 tersentuh: lanjut ke T1 dulu 50% / balik ke EQ dulu 50% (koin) -> bukan titik entry";
      if(hitK >= 0)
         tip += "\nTERCAPAI " + ::GP_LocalTime(g5[hitK].time) + " " + ::InpLocalTZName;
      else
         if(isLast && li.open)
            tip += "\nPeluang tersentuh s/d tutup: " + PStrD(MathAbs(lvl - li.cur) / d.adr, li.hoursLeft);
      Tip(nm, tip);
      Tip(nm + "L", tip);
     }

//--- Open NY 09:30 ET: level magnet (uji ict_tests.py 2017-26: +4.4 poin vs level palsu, 9/10 th). INFO, bukan sinyal.
   if(g_vTarget && DMInpShowNYOpen)
     {
      int kn = NYOpenIdx(d);
      if(kn >= 0)
        {
         double lv = g5[kn].open;
         string nm = id + "NYO";
         HLine(nm, g5[kn].time, tB, lv, DMInpNYOpenColor, STYLE_DOT, 1);
         bool armed;
         int kb = NYBack(d, kn, isLast ? li.last : d.i1 - 1, armed);
         string st = (kb >= 0) ? "KEMBALI " + ::GP_LocalTime(g5[kb].time)
                     : (!armed ? "belum menjauh" : ((isLast && li.open) ? "sisa " + PStrD(MathAbs(lv - li.cur) / d.adr, li.hoursLeft) : "tidak kembali"));
         // tag pendek di PANGKAL garis (kiri atas): di kanan harga NY biasanya dekat harga sekarang -> menumpuk
         // dengan label panah live & Cadangan 80%. Status lengkap: panel hal. 1 (LIVE), tangga hal. 2, tooltip.
         Text(nm + "L", g5[kn].time, lv, isLast ? "NY " + ::GP_LocalTime(g5[kn].time) : "NY", DMInpNYOpenColor, ANCHOR_RIGHT_LOWER);
         string tip = StringFormat("Open NY 09:30 ET (= %s %s) = %s\nSetelah menjauh >= 0.05 ADR, kembali disentuh s/d tutup: %.0f%% hari (250 hari)",
                                   ::GP_LocalTime(g5[kn].time), ::InpLocalTZName, Dts(lv), Pct(st_nyBack, st_nyN));
         tip += "\nUji 2017-26: +4.4 poin lebih sering didatangi dari level biasa berjarak sama (9/10 th)."
                "\nINFO level (magnet), bukan sinyal entry. Midnight open ICT (00:00 ET) bukan magnet.";
         if(kb >= 0) tip += "\nKEMBALI " + ::GP_LocalTime(g5[kb].time);
         Tip(nm, tip);
         Tip(nm + "L", tip);
        }
     }

//--- garis lanjutan T5, T6, ... (hari tren): hanya hari terakhir, sampai garis pertama di luar harga.
//    Tanpa % historis (jarang terjadi); peluang live s/d tutup dari tabel yang sama.
   if(isLast && g_vTarget)
      for(int s = 1; s >= -1; s -= 2)
         for(int q = NLV + 1; q <= ExtMax(li, s); q++)
           {
            double lvl = d.open + s * q * 0.25 * d.adr;
            color c = (s > 0) ? DMInpUpColor : DMInpDnColor;
            string nm = id + "X" + IntegerToString(q) + ((s > 0) ? "u" : "d");
            HLine(nm, tA, tB, lvl, c, STYLE_DOT, 1);
            int hitK = -1;
            for(int k = d.i0; k < d.i1; k++)
               if((s > 0 && g5[k].high >= lvl) || (s < 0 && g5[k].low <= lvl)) { hitK = k; break; }
            string tx = StringFormat("T%d %s%.2f ADR  %s", q, (s > 0) ? "+" : "-", q * 0.25, Dts(lvl));
            if(hitK >= 0)
              {
               tx += "  | TERCAPAI";
               if(DMInpShowTargetsHit)
                  Arrow(nm + "H", g5[hitK].time, lvl, 252, c);
              }
            else
               if(li.open)
                  tx += "  | sisa " + PStrD(MathAbs(lvl - li.cur) / d.adr, li.hoursLeft);
            Text(nm + "L", tB, lvl, tx, c, (s > 0) ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER);
            string tip = StringFormat("T%d %s = open %s %.2f x ADR = %s\nGaris lanjutan (hari tren, di luar T4)",
                                      q, (s > 0) ? "atas" : "bawah", (s > 0) ? "+" : "-", q * 0.25, Dts(lvl));
            Tip(nm, tip);
            Tip(nm + "L", tip);
           }

//--- straddle EQ: BUY STOP (biru) di atas, SELL STOP (merah) di bawah (gambar hanya bila diminta)
   if(DMInpShowStraddle && DMInpDrawStraddle)
     {
      Straddle sd;
      CalcStraddle(d, isLast ? li.last : d.i1 - 1, sd);
      DrawStraddle(d, sd, id, isLast, tA, tB);
     }

//--- (10 Okt 2026, pengguna: "kita buang") tombol "Panah" dihapus: panah retest / pullback / lewat open, panah live ke garis
//    terdekat & proyeksi besok tidak digambar lagi (peluangnya tepat tapi arah sesudahnya = koin; angka yang sama ada di panel).
//--- garis CADANGAN live: garis terjauh di atas & bawah harga yang peluangnya >= DMInpBackupP% tersentuh
//    sebelum hari tutup (kebalikan tabel live). Dihitung ulang tiap candle M5 close.
   if(isLast && g_vBackup && li.open)
     {
      double thr = MathMax(0.6, MathMin(0.95, DMInpBackupP / 100.0));
      double dist = LiveInv(thr, li.hoursLeft);
      if(dist > 0)
        {
         datetime t1 = g5[li.last].time, t2 = FutureT2(t1);
         g_futT1 = t1;
         for(int s = 1; s >= -1; s -= 2)
           {
            double lvl = li.cur + s * dist * d.adr;
            string nm = id + "BK" + ((s > 0) ? "u" : "d");
            FutLine(nm, t1, t2, lvl, DMInpBackupColor, STYLE_DASHDOT);
            FutText(nm + "T", t2, lvl, StringFormat("Cadangan %d%% %s (%s$%.1f)  ", (int)(thr * 100), Dts(lvl),
                    (s > 0) ? "+" : "-", dist * d.adr), DMInpBackupColor, (s > 0) ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER);
            string tip = StringFormat("Garis cadangan %d%%: %s\nPeluang tersentuh sebelum tutup >= %d%% (sisa %.1f jam)\n"
                                      "Uji 2017-26: tersentuh 79-80%%, tiap tahun 77-82%%\nDihitung ulang tiap candle M5 close",
                                      (int)(thr * 100), Dts(lvl), (int)(thr * 100), li.hoursLeft);
            Tip(nm, tip);
            Tip(nm + "T", tip);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Objek masa depan: ujung kanan mengikuti ruang kosong chart        |
//+------------------------------------------------------------------+
datetime FutureT2(datetime t1)
  {
   long wb = ChartGetInteger(0, CHART_WIDTH_IN_BARS);
   double bars = 6;
   if(ChartGetInteger(0, CHART_SHIFT))
      bars = MathMax(2.0, wb * ChartGetDouble(0, CHART_SHIFT_SIZE) / 100.0 * 0.85);
   return t1 + (datetime)(bars * PeriodSeconds(_Period));
  }

void RegFut(string n, int pt, bool clip = false, datetime t1 = 0, double p1 = 0, double p2 = 0)
  {
   int k = ArraySize(g_futName);
   ArrayResize(g_futName, k + 1);
   ArrayResize(g_futPt, k + 1);
   ArrayResize(g_futClip, k + 1);
   ArrayResize(g_futA1, k + 1);
   ArrayResize(g_futP1, k + 1);
   ArrayResize(g_futP2, k + 1);
   g_futName[k] = n;
   g_futPt[k] = pt;
   g_futClip[k] = clip;
   g_futA1[k] = t1;
   g_futP1[k] = p1;
   g_futP2[k] = p2;
  }

//--- panah ke depan: kalau target di luar layar, panah dipotong di tepi chart (kepala panah tetap terlihat)
void FutArrow(string n, datetime t1, double p1, datetime t2, double p2, color c)
  {
   ALine(n, t1, p1, t2, p2, c);
   ObjectSetInteger(0, n, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
   RegFut(n, 1, true, t1, p1, p2);
  }

void FutLine(string n, datetime t1, datetime t2, double p, color c, ENUM_LINE_STYLE st)
  {
   HLine(n, t1, t2, p, c, st, 1);
   RegFut(n, 1);
  }

void FutText(string n, datetime t, double p, string s, color c, ENUM_ANCHOR_POINT a)
  {
   Text(n, t, p, s, c, a);
   RegFut(n, 0);
  }

void MoveFuture()
  {
   if(g_futT1 == 0 || ArraySize(g_futName) == 0)
      return;
   datetime t2 = FutureT2(g_futT1);
   double pmax = ChartGetDouble(0, CHART_PRICE_MAX), pmin = ChartGetDouble(0, CHART_PRICE_MIN);
   double mg = (pmax - pmin) * 0.03;
   for(int i = 0; i < ArraySize(g_futName); i++)
     {
      if(!g_futClip[i] || pmax <= pmin)
        {
         ObjectSetInteger(0, g_futName[i], OBJPROP_TIME, g_futPt[i], t2);
         continue;
        }
      double p1 = g_futP1[i], p2 = g_futP2[i], pe = p2;
      if(p2 > pmax - mg) pe = pmax - mg;
      if(p2 < pmin + mg) pe = pmin + mg;
      double f = (p2 != p1) ? (pe - p1) / (p2 - p1) : 1.0;
      f = MathMax(0.15, MathMin(1.0, f));
      datetime te = g_futA1[i] + (datetime)(f * (double)(t2 - g_futA1[i]));
      ObjectSetInteger(0, g_futName[i], OBJPROP_TIME, 1, te);
      ObjectSetDouble(0, g_futName[i], OBJPROP_PRICE, 1, p1 + f * (p2 - p1));
     }
   ChartRedraw();
  }

void ChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE)
     {
      MoveFuture();
      PinLabels();
      bool oc = (bool)ChartGetInteger(0, CHART_SHOW_ONE_CLICK);
      if(oc != g_lastOneClick)
        {
         g_lastOneClick = oc;
         Redraw();        // One Click Trading dinyalakan/dimatikan -> tombol & panel pindah posisi
        }
      else
         if((int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0) != g_lastCH)
           {
            PanelLayout();   // jendela diubah ukurannya -> panel menyesuaikan
            InfoCard();
            ChartRedraw();
           }
      return;
     }
   if(id == CHARTEVENT_OBJECT_CLICK && StringFind(sparam, BPFX + "B_") == 0)
     {
      OnButton(sparam);
      return;
     }
   if(id == CHARTEVENT_OBJECT_CLICK && StringFind(sparam, BPFX + "I_") == 0)   // 14 Okt: kotak "i" (INFO)
     {
      OnInfo(sparam);
      return;
     }
   if(id == CHARTEVENT_OBJECT_CLICK && (sparam == PFX + "IC_bg" || sparam == PFX + "IC_L0"))   // klik judul kartu info = tutup
     {
      g_infoKey = "";
      GlobalVariableSet(VKey("infok"), -1);
      Redraw();
      return;
     }
   if(id == CHARTEVENT_CLICK && g_pinMode && GetTickCount() - g_pinModeTick > 300)
     {
      int x = (int)lparam, y = (int)dparam, sub;
      datetime t;
      double p;
      if(InButtons(x, y))
         return;
      if(ChartXYToTimePrice(0, x, y, sub, t, p) && sub == 0)
         PinAdd(NormalizeDouble(p, _Digits));
      g_pinMode = false;
      Redraw();
      return;
     }
   if(id == CHARTEVENT_MOUSE_MOVE)
     {
      Probe((int)lparam, (int)dparam);
      return;
     }
   if(id == CHARTEVENT_OBJECT_DRAG && StringFind(sparam, BPFX + "PIN_") == 0)
     {
      PinSync();
      Redraw();
     }
  }

//+------------------------------------------------------------------+
//| INTERAKTIF: tombol, probe mouse, PIN                              |
//+------------------------------------------------------------------+
string VKey(string k)         { return BPFX + IntegerToString(ChartID()) + "_" + k; }
bool   VGet(string k, bool v) { return GlobalVariableCheck(VKey(k)) ? (GlobalVariableGet(VKey(k)) != 0) : v; }
void   VSet(string k, bool v) { GlobalVariableSet(VKey(k), v ? 1 : 0); }

void Tip(string n, string s)
  {
   if(ObjectFind(0, n) >= 0)
      ObjectSetString(0, n, OBJPROP_TOOLTIP, s);
  }

//--- gambar ulang semua sekarang (bukan menunggu candle M5 berikutnya)
void Redraw()
  {
   g_last = 0;
   Update();
   ChartRedraw();
  }

//--- TOMBOL: satu kolom VERTIKAL di tepi kiri layar (permintaan pengguna 1 Okt 2026), berurutan dari atas.
//    Panel informasi TIDAK tampil sampai tombol halamannya diklik; klik tombol yang sama lagi = tutup panel.
#define BTN_X 2
#define BTN_W 88
#define BTN_H 17
#define BTN_N 15                         // 10 Okt 2026: 17 -> 12 (buang 3 KOTAK, Radar, Panah, Zona OB/FVG; gabung 2 & 4; + Saldo)
                                         // 11 Okt 2026: + Tembus Balik (indeks 12); 14 Okt 2026: + Gelombang (13), Mode Teruji (14)
#define BTN_TRADE 9                      // indeks tombol Trade (dibaca EA GoldPro_Panel lewat GP_TBY_)
#define BTN_SALDO 10                     // indeks tombol Saldo (GP_SBY_)
#define INFO_W   16                      // 14 Okt 2026: kotak "i" (INFO) di kanan tiap tombol
#define INFO_GAP 2
int BtnAreaH() { return 0; }                                           // (lama: baris tombol di atas panel)
int BtnColR()  { return DMInpButtons ? BTN_X + BTN_W + INFO_GAP + INFO_W : 0; }   // tepi kanan kolom tombol + kotak "i"
int BtnColB()  { return DMInpButtons ? PanelTop() + BTN_N * (BTN_H + 2) : 0; }

bool InButtons(int x, int y)
  {
   if(!DMInpButtons)
      return false;
   int y0 = PanelTop();
   return x >= BTN_X && x <= BTN_X + BTN_W + INFO_GAP + INFO_W && y >= y0 && y <= y0 + BTN_N * (BTN_H + 2);
  }

//--- kotak "i" kecil di kanan tombol: INFO fitur itu (tombol utama = gambar)
void IBtn(string key, int idx, bool on, string tip, color onClr)
  {
   string n = BPFX + "I_" + key;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, n, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_ZORDER, 10);
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, BTN_X + BTN_W + INFO_GAP);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, PanelTop() + idx * (BTN_H + 2));
   ObjectSetInteger(0, n, OBJPROP_XSIZE, INFO_W);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, BTN_H);
   ObjectSetString(0, n, OBJPROP_TEXT, "i");
   ObjectSetInteger(0, n, OBJPROP_COLOR, on ? clrWhite : clrSilver);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, on ? onClr : C'45,45,58');
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, clrDimGray);
   ObjectSetInteger(0, n, OBJPROP_STATE, false);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, "INFO: " + tip + " (klik = buka / tutup)");
  }

void Btn(string key, string txt, int idx, bool on, string tip, color onClr)
  {
   string n = BPFX + "B_" + key;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, n, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_ZORDER, 10);
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, BTN_X);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, PanelTop() + idx * (BTN_H + 2));
   ObjectSetInteger(0, n, OBJPROP_XSIZE, BTN_W);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, BTN_H);
   ObjectSetString(0, n, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, n, OBJPROP_COLOR, on ? clrWhite : clrSilver);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, on ? onClr : C'55,55,65');
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, clrDimGray);
   ObjectSetInteger(0, n, OBJPROP_STATE, false);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, tip);
  }

//--- untuk EA GoldPro_Panel di chart yang sama: tampil/sembunyi panel trading + posisi panel & tombol Trade
void TradeGV()
  {
   string cid = IntegerToString(ChartID());
   GlobalVariableSet("GP_TRADEV_" + cid, g_vTrade ? 1 : 0);
   GlobalVariableSet("GP_PX_" + cid, BtnColR() + 6);
   GlobalVariableSet("GP_PY_" + cid, PanelTop() + (DMInpButtons ? BTN_H + 8 : 4));
   GlobalVariableSet("GP_TBX_" + cid, BtnColR() + 3);                  // tanda "!" EA di kanan kotak "i" (14 Okt)
   GlobalVariableSet("GP_TBY_" + cid, PanelTop() + BTN_TRADE * (BTN_H + 2));
   GlobalVariableSet("GP_SALDOV_" + cid, g_vSaldo ? 1 : 0);              // dashboard SALDO (digambar EA GoldPro_Panel)
   GlobalVariableSet("GP_SBY_" + cid, PanelTop() + BTN_SALDO * (BTN_H + 2));
  }
//--- status kunci target harian (ditulis EA GoldPro_Panel per akun): 0 OFF, 1 ON, 2 ON & TERKUNCI hari ini
int SaldoState()
  {
   string ac = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   if(!GlobalVariableCheck("GP_SD_ON_" + ac) || GlobalVariableGet("GP_SD_ON_" + ac) < 0.5) return 0;
   datetime d0 = iTime(_Symbol, PERIOD_D1, 0);
   return (GlobalVariableCheck("GP_SD_LKD_" + ac) && (datetime)GlobalVariableGet("GP_SD_LKD_" + ac) == d0) ? 2 : 1;
  }
//--- tombol Saldo: teks & warna ikut status EA (dipanggil juga dari Timer tiap 2 dtk agar "KUNCI" langsung terlihat)
void SaldoBtn()
  {
   if(!DMInpButtons) return;
   bool eaOn = (ChartGetString(0, CHART_EXPERT_NAME) == "GoldPro_Panel");
   int ss = eaOn ? SaldoState() : 0;
   Btn("saldo", !eaOn ? "Saldo (EA?)" : (ss == 2 ? "Saldo KUNCI" : (ss == 1 ? "Saldo ON" : "Saldo")), BTN_SALDO, g_vSaldo && eaOn,
       eaOn ? "SALDO & TARGET HARIAN (EA GoldPro_Panel, kanan atas): saldo, equity, target % dari saldo awal hari (akumulasi), saklar "
              "ON/OFF. ON + target tercapai = order baru dikunci s/d hari berikutnya. Klik = tampil / sembunyi."
            : "EA GoldPro_Panel belum terpasang di chart ini: Navigator > Expert Advisors > GoldPro > GoldPro_Panel, seret ke chart.",
       ss == 2 ? C'150,40,40' : C'20,110,70');
   if(ss == 2)                                                          // terkunci: merah walau dashboard tertutup
     {
      ObjectSetInteger(0, BPFX + "B_saldo", OBJPROP_BGCOLOR, C'150,40,40');
      ObjectSetInteger(0, BPFX + "B_saldo", OBJPROP_COLOR, clrWhite);
     }
  }

void Buttons()
  {
   if(!DMInpButtons)
      return;
   ObjectDelete(0, BPFX + "B_panel");   // tombol "Panel" lama tidak dipakai lagi (halaman = buka/tutup)
   int P = (int)MathRound(MathMax(0.6, MathMin(0.95, DMInpBackupP / 100.0)) * 100);
   color on = C'30,100,60', tab = C'40,70,130';
   Btn("page1", "1 PETA", 0, g_vPanel && g_page == 1,
       "Panel 1: rute harga, tangga target hari ini (kena / belum + peluang), live, PIN, SMC, sesi (klik = buka / tutup)", tab);
   Btn("page5", "2 CEK SIAP", 1, g_vPanel && g_page == 5,
       "Panel 2: rekap konfirmasi scalping - biaya, gerak, lokasi garis, berita, disiplin -> SIAP / TUNGGU + JAM BIAYA (jam murah / "
       "mahal, menang minimum utk impas). Cek kondisi, bukan arah.", C'30,110,70');
   Btn("target", "Target", 2, g_vTarget, "Garis T0-T4: T0 = tengah EQ-T1, T1-T4 = open +/- 0.25/0.5/0.75/1 ADR; + garis Open NY 09:30 ET", on);
   Btn("backup", "Cad" + IntegerToString(P), 3, g_vBackup,
       StringFormat("Garis cadangan: peluang >= %d%% tersentuh sebelum tutup (uji 2017-26 tepat)", P), on);
   Btn("smc", "SMC", 4, g_vSMC, "SMC (GAMBAR): visual SMC lengkap - OB / Breaker / FVG, BOS / CHoCH, Premium / Discount, EQH / EQL, Paus. "
       "Info & PETA ARAH di zona -> kotak 'i' di sampingnya", C'100,80,20');
   Btn("probe", "Probe", 5, g_vProbe, "Arahkan mouse ke harga mana saja -> peluang tersentuh s/d tutup", on);
   Btn("pin", g_pinMode ? "Klik harga" : "+PIN", 6, g_pinMode,
       "Pasang PIN: tekan, lalu klik harga di chart. PIN bisa digeser; alert saat tersentuh", C'140,60,140');
   Btn("pinclr", "Hapus PIN", 7, false, "Hapus semua PIN (atau pilih satu PIN lalu tekan Delete)", on);
   Btn("news", "Berita", 8, g_vNews,
       "BERITA (GAMBAR): garis vertikal jam rilis USD & jam panas 24 jam ke depan (merah penting, oranye sedang, abu jam panas). "
       "Dashboard hitung mundur & risiko -> kotak 'i'", tab);
   //--- 14 Okt 2026: kotak "i" = INFO tiap fitur
   IBtn("page1", 0, g_infoKey == "page1", "cara membaca panel 1 PETA", tab);
   IBtn("page5", 1, g_infoKey == "page5", "cara membaca panel 2 CEK SIAP", C'30,110,70');
   IBtn("target", 2, g_infoKey == "target", "garis T0-T4: status kena / belum, peluang live, tangga target", on);
   IBtn("backup", 3, g_infoKey == "backup", "garis cadangan: harga & peluang", on);
   IBtn("smc", 4, g_infoKey == "smc", "SMC: bias, zona terdekat & PETA ARAH (colek / tembus) dengan angka uji", C'100,80,20');
   IBtn("probe", 5, g_infoKey == "probe", "cara membaca probe", on);
   IBtn("pin", 6, g_infoKey == "pin", "daftar PIN & peluang tersentuh", C'140,60,140');
   IBtn("news", 8, g_iNews, "dashboard berita (kanan atas): hitung mundur, dorongan & sweep", tab);
   bool eaOn = (ChartGetString(0, CHART_EXPERT_NAME) == "GoldPro_Panel");
   Btn("trade", eaOn ? "Trade" : "Trade (EA?)", BTN_TRADE, g_vTrade && eaOn,
       eaOn ? "Panel trading + PENGAWAL DISIPLIN (EA GoldPro_Panel) - klik = tampil / sembunyi. Panel halaman GoldPro ikut tertutup."
            : "EA GoldPro_Panel belum terpasang di chart ini: Navigator > Expert Advisors > GoldPro > GoldPro_Panel, seret ke chart.",
       C'150,95,20');
   SaldoBtn();
   Btn("box", "Kotak Sideway", 11, g_vBox,
       "KOTAK SIDEWAY (GAMBAR): garis ATAP & LANTAI kotak yang diawasi + garis titik MEPET, status ditembus di label. "
       "Dashboard cerita & angka uji 2017-26 -> kotak 'i' di sampingnya. INFO, bukan sinyal arah.", C'0,105,140');
   Btn("tbk", "Tembus Balik", 12, g_vTbk,
       "TEMBUS BALIK (GAMBAR): tanda tembusan di jam positif + garis TARGET tengah kotak & BATAL di chart, hasilnya "
       "(KENA / BATAL / HABIS); hijau = JAM BAGUS. Dashboard per jam, strip rekap indikator -> kotak 'i'. INFO, bukan sinyal.",
       C'110,60,150');
   bool eaOn2 = (ChartGetString(0, CHART_EXPERT_NAME) == "GoldPro_Panel");
   IBtn("trade", BTN_TRADE, g_infoKey == "trade", "panel trading & pengawal disiplin (EA GoldPro_Panel)" + (eaOn2 ? "" : " - EA belum terpasang"),
        C'150,95,20');
   IBtn("saldo", BTN_SALDO, g_infoKey == "saldo", "saldo & target harian: cara hitung, kunci", C'20,110,70');
   IBtn("box", 11, g_iBox, "dashboard Kotak Sideway: cerita, target colek / mepet / kembali, peluang tembus sungguhan", C'0,105,140');
   IBtn("tbk", 12, g_iTbk, "dashboard Tembus Balik per jam + JAM BAGUS + strip rekap indikator di bawah chart", C'110,60,150');
   Btn("wave", "Gelombang", 13, g_vWave,
       "PETA GELOMBANG (GAMBAR): range SWING lebar (Premium / Equilibrium / Discount, Strong / Weak High & Low) + GELOMBANG AWAL "
       "(range kecil internal) -> target 1.0 / 1.272 / 1.618 / 2.0 / 2.618 x gelombang awal & Weak swing, garis BATAL, peluang "
       "sampai sebelum batal dari harga sekarang (uji 2017-26: tepat, = hitungan jarak). INFO, bukan sinyal.", C'30,95,125');
   IBtn("wave", 13, g_infoKey == "wave", "peta gelombang: range, gelombang awal, target & peluang, angka uji 2017-26", C'30,95,125');
   Btn("simple", g_vSimple ? "Mode Teruji ON" : "Mode Teruji", 14, g_vSimple,
       "MODE TERUJI (satu klik): kotak SMC lama MATI (tidak terbukti), Gelombang + Target + Cadangan + Tembus Balik NYALA "
       "(angkanya tepat di uji 2017-26). Klik lagi = kembali ke pilihan tombol sebelumnya.", C'60,115,60');
   IBtn("simple", 14, g_infoKey == "simple", "apa yang tampil / disembunyikan di Mode Teruji", C'60,115,60');
   TradeGV();
  }

void OnButton(string name)
  {
   string k = StringSubstr(name, StringLen(BPFX + "B_"));
   if(k == "target")      { g_vTarget = !g_vTarget; VSet(k, g_vTarget); }
   else if(k == "backup") { g_vBackup = !g_vBackup; VSet(k, g_vBackup); }
   else if(k == "smc")    { g_vSMC = !g_vSMC;       VSet(k, g_vSMC); g_smcDirty = true; }
   else if(k == "probe")
     {
      g_vProbe = !g_vProbe;
      VSet(k, g_vProbe);
      if(!g_vProbe)
         ObjectDelete(0, BPFX + "PROBE");
     }
   else if(k == "page1" || k == "page5")
     {
      int pg = (int)StringToInteger(StringSubstr(k, 4));
      if(g_vPanel && g_page == pg)
         g_vPanel = false;                 // klik halaman yang sedang terbuka = tutup panel
      else
        {
         g_page = pg;
         g_vPanel = true;
         if(g_vTrade) { g_vTrade = false; VSet("trade", false); }   // panel trading & halaman GoldPro tidak bertumpuk
        }
      GlobalVariableSet(VKey("page"), g_page);
      VSet("panelv", g_vPanel);
     }
   else if(k == "saldo")
     {
      g_vSaldo = !g_vSaldo;
      VSet(k, g_vSaldo);
     }
   else if(k == "trade")
     {
      g_vTrade = !g_vTrade;
      VSet(k, g_vTrade);
      if(g_vTrade && g_vPanel) { g_vPanel = false; VSet("panelv", false); }
     }
   else if(k == "news")
     {
      g_vNews = !g_vNews;
      VSet(k, g_vNews);
      if(!g_vNews)
         ObjectsDeleteAll(0, "GPN_V");    // 14 Okt: tombol utama = garis jam berita (dashboard = kotak "i")
     }
   else if(k == "box")
     {
      g_vBox = !g_vBox;
      VSet(k, g_vBox);
      if(!g_vBox)
         ObjectsDeleteAll(0, "GPK_H");    // 14 Okt: tombol utama = garis atap / lantai (dashboard = kotak "i")
     }
   else if(k == "tbk")
     {
      g_vTbk = !g_vTbk;
      VSet(k, g_vTbk);
      if(!g_vTbk)
         ObjectsDeleteAll(0, "GPI_M");    // 14 Okt: tombol utama = tanda tembusan di chart (dashboard & strip = kotak "i")
     }
   else if(k == "wave")
     {
      g_vWave = !g_vWave;
      VSet(k, g_vWave);
      if(!g_vWave)
         ObjectsDeleteAll(0, "GPW_");     // peta gelombang (Map\GP_Wave, prefix WV_PFX)
      g_smcDirty = true;                  // range SMC lama disembunyikan / tampil lagi (satu range saja)
     }
   else if(k == "simple")                 // MODE TERUJI: simpan pilihan tombol, nyalakan yang teruji, matikan kotak SMC
     {
      g_vSimple = !g_vSimple;
      VSet(k, g_vSimple);
      if(g_vSimple)
        {
         VSet("sv_smc", g_vSMC); VSet("sv_wave", g_vWave); VSet("sv_target", g_vTarget); VSet("sv_backup", g_vBackup); VSet("sv_tbk", g_vTbk);
         g_vSMC = false; g_vWave = true; g_vTarget = true; g_vBackup = true; g_vTbk = true;
        }
      else
        {
         g_vSMC = VGet("sv_smc", g_vSMC); g_vWave = VGet("sv_wave", g_vWave); g_vTarget = VGet("sv_target", g_vTarget);
         g_vBackup = VGet("sv_backup", g_vBackup); g_vTbk = VGet("sv_tbk", g_vTbk);
        }
      VSet("smc", g_vSMC); VSet("wave", g_vWave); VSet("target", g_vTarget); VSet("backup", g_vBackup); VSet("tbk", g_vTbk);
      if(!g_vWave) ObjectsDeleteAll(0, "GPW_");
      if(!g_vTbk) ObjectsDeleteAll(0, "GPI_M");
      g_smcDirty = true;
     }
   else if(k == "pin")    { g_pinMode = !g_pinMode; g_pinModeTick = GetTickCount(); }
   else if(k == "pinclr") PinsClear();
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   Redraw();
  }

//--- 14 Okt 2026 (screenshot pengguna: garis putus-putus SMC menyilang tulisan tombol Berita / Tembus Balik / Gelombang): MT5
//    menggambar objek menurut urutan dibuat -> objek chart yang dibuat SESUDAH tombol menimpa tombol. Tombol, kotak "i", label
//    LIVE & kartu info dibuat ulang (paling akhir = paling depan) sesudah peta / SMC digambar ulang; maks 1x per 5 dtk kecuali force.
void RaiseButtons(bool force = false)
  {
   if(!DMInpButtons) return;
   if(!force && GetTickCount() - g_raiseTick < 5000) return;
   g_raiseTick = GetTickCount();
   ObjectsDeleteAll(0, BPFX + "B_");
   ObjectsDeleteAll(0, BPFX + "I_");
   ObjectDelete(0, BPFX + "LIVE");
   Buttons();
   LiveTag();
   if(g_infoKey != "" && g_nd > 0) { ObjectsDeleteAll(0, PFX + "IC_"); InfoCard(); }
  }

//--- kotak "i": Kotak Sideway / Tembus Balik / Berita = dashboard modulnya; lainnya = kartu info umum (satu sekaligus)
void OnInfo(string name)
  {
   string k = StringSubstr(name, StringLen(BPFX + "I_"));
   if(k == "box")
     {
      g_iBox = !g_iBox; VSet("i_box", g_iBox);
      if(!g_iBox) { ObjectDelete(0, "GPK_BG"); ObjectsDeleteAll(0, "GPK_L"); }
     }
   else if(k == "tbk")
     {
      g_iTbk = !g_iTbk; VSet("i_tbk", g_iTbk);
      if(!g_iTbk) { ObjectDelete(0, "GPI_BG"); ObjectsDeleteAll(0, "GPI_L"); ObjectsDeleteAll(0, "GPI_S"); }
     }
   else if(k == "news")
     {
      g_iNews = !g_iNews; VSet("i_news", g_iNews);
      if(!g_iNews) { ObjectDelete(0, "GPN_BG"); ObjectsDeleteAll(0, "GPN_L"); }
     }
   else
     {
      g_infoKey = (g_infoKey == k) ? "" : k;
      GlobalVariableSet(VKey("infok"), InfoIdx(g_infoKey));
     }
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   Redraw();
  }

//--- probe: peluang harga di kursor tersentuh sebelum hari tutup (LiveP, kalibrasi 2017-26 +/-1.5 poin)
void Probe(int x, int y)
  {
   string n = BPFX + "PROBE";
   int sub;
   datetime t;
   double p;
   bool overPanel = (x <= g_panR && y <= g_panB) || InLive(x, y);   // mouse di atas panel / tombol / label LIVE
   //--- panel Trade EA GoldPro_Panel (ukuran dari EA) & mode pilih harga EA -> probe disembunyikan agar tidak menimpa
   string cid = IntegerToString(ChartID());
   if(g_vTrade && GlobalVariableCheck("GP_EAPH_" + cid) && GlobalVariableGet("GP_EAPH_" + cid) > 0)
     {
      int ex0 = BtnColR() + 6, ey0 = PanelTop() + (DMInpButtons ? BTN_H + 8 : 4);
      int ew = (int)GlobalVariableGet("GP_EAPW_" + cid), eh = (int)GlobalVariableGet("GP_EAPH_" + cid);
      if(x >= ex0 - 4 && x <= ex0 + ew + 4 && y >= ey0 - 4 && y <= ey0 + eh + 4) overPanel = true;
     }
   if(GlobalVariableCheck("GP_PICKON_" + cid) && GlobalVariableGet("GP_PICKON_" + cid) > 0) overPanel = true;
   if(ObjectFind(0, "GPD_BG") >= 0)                                  // dashboard SALDO (EA GoldPro_Panel, kanan atas)
     {
      int sx = (int)ObjectGetInteger(0, "GPD_BG", OBJPROP_XDISTANCE), sy = (int)ObjectGetInteger(0, "GPD_BG", OBJPROP_YDISTANCE);
      if(x >= sx && x <= sx + (int)ObjectGetInteger(0, "GPD_BG", OBJPROP_XSIZE) &&
         y >= sy && y <= sy + (int)ObjectGetInteger(0, "GPD_BG", OBJPROP_YSIZE)) overPanel = true;
     }
   if(g_infW > 0 && x >= g_infX && x <= g_infX + g_infW && y >= g_infY && y <= g_infY + g_infH) overPanel = true;   // kartu info (14 Okt)
   if(g_iBox && ObjectFind(0, "GPK_BG") >= 0)                        // dashboard kotak sideway (GP_BoxWatch)
     {
      int kx = (int)ObjectGetInteger(0, "GPK_BG", OBJPROP_XDISTANCE), ky = (int)ObjectGetInteger(0, "GPK_BG", OBJPROP_YDISTANCE);
      if(x >= kx && x <= kx + (int)ObjectGetInteger(0, "GPK_BG", OBJPROP_XSIZE) &&
         y >= ky && y <= ky + (int)ObjectGetInteger(0, "GPK_BG", OBJPROP_YSIZE)) overPanel = true;
     }
   if(g_iTbk && ObjectFind(0, "GPI_BG") >= 0)                        // dashboard Tembus Balik (GP_TembusBalik, 11 Okt)
     {
      int ix = (int)ObjectGetInteger(0, "GPI_BG", OBJPROP_XDISTANCE), iy = (int)ObjectGetInteger(0, "GPI_BG", OBJPROP_YDISTANCE);
      if(x >= ix && x <= ix + (int)ObjectGetInteger(0, "GPI_BG", OBJPROP_XSIZE) &&
         y >= iy && y <= iy + (int)ObjectGetInteger(0, "GPI_BG", OBJPROP_YSIZE)) overPanel = true;
     }
   if((!g_vProbe && !g_pinMode) || overPanel || !ChartXYToTimePrice(0, x, y, sub, t, p) || sub != 0 || InButtons(x, y))
     {
      if(ObjectFind(0, n) >= 0) { ObjectDelete(0, n); ChartRedraw(); }
      return;
     }
   double hl, bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), dd = p - bid;
   string s;
   if(!LiveNow(hl) || bid <= 0)
      s = Dts(p) + " | market tutup";
   else
      s = StringFormat("%s %s$%.2f (%.2f ADR) | s/d tutup %s", Dts(p), dd >= 0 ? "+" : "-", MathAbs(dd),
                       MathAbs(dd) / g_pAdr, PStrD(MathAbs(dd) / g_pAdr, hl));
   if(g_pinMode)
      s = "Klik = PIN di " + s;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_EDIT, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_READONLY, true);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, n, OBJPROP_BGCOLOR, DMInpPanelBg);
      ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, clrDimGray);
      ObjectSetInteger(0, n, OBJPROP_YSIZE, 18);
      ObjectSetString(0, n, OBJPROP_TOOLTIP, "\n");
     }
   int w = StringLen(s) * 7 + 10;
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS), ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   int px = (x + 16 + w > cw) ? x - w - 12 : x + 16, py = (y + 36 > ch) ? y - 26 : y + 14;
   if(px < g_panR && py < g_panB)   // kotak akan menimpa panel -> geser ke kanan panel
      px = g_panR + 6;
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, MathMax(0, px));
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, MathMax(0, py));
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetString(0, n, OBJPROP_TEXT, s);
   ObjectSetInteger(0, n, OBJPROP_COLOR, g_pinMode ? DMInpPinColor : (dd >= 0 ? DMInpUpColor : DMInpDnColor));
   ChartRedraw();
  }

//--- PIN: garis harga pilihan pengguna (OBJ_HLINE bisa digeser), peluang live & alert saat tersentuh.
//    Garisnya objek chart biasa -> bertahan saat ganti TF / kompilasi ulang.
string PinLbl(string pin) { return BPFX + "PINL_" + StringSubstr(pin, StringLen(BPFX + "PIN_")); }

void PinPush(string name, double price)
  {
   int k = ArraySize(g_pins);
   ArrayResize(g_pins, k + 1);
   g_pins[k].name = name;
   g_pins[k].price = price;
   g_pins[k].since = TimeTradeServer();
   g_pins[k].hit = 0;
  }

void PinsLoad()
  {
   ArrayResize(g_pins, 0);
   for(int i = ObjectsTotal(0, 0, OBJ_HLINE) - 1; i >= 0; i--)
     {
      string n = ObjectName(0, i, 0, OBJ_HLINE);
      if(StringFind(n, BPFX + "PIN_") == 0)
         PinPush(n, ObjectGetDouble(0, n, OBJPROP_PRICE, 0));
     }
  }

void PinAdd(double p)
  {
   string n = BPFX + "PIN_" + IntegerToString((long)TimeLocal()) + "_" + IntegerToString(GetTickCount() % 1000);
   if(!ObjectCreate(0, n, OBJ_HLINE, 0, 0, p))
      return;
   ObjectSetInteger(0, n, OBJPROP_COLOR, DMInpPinColor);
   ObjectSetInteger(0, n, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, false);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, "PIN: klik dua kali lalu geser untuk pindah; pilih + Delete untuk hapus");
   PinPush(n, p);
  }

void PinsClear()
  {
   for(int i = 0; i < ArraySize(g_pins); i++)
     {
      ObjectDelete(0, g_pins[i].name);
      ObjectDelete(0, PinLbl(g_pins[i].name));
     }
   ArrayResize(g_pins, 0);
  }

//--- sinkron dengan chart: PIN dihapus pengguna / digeser -> perbarui. true = ada perubahan
bool PinSync()
  {
   bool ch = false;
   for(int i = ArraySize(g_pins) - 1; i >= 0; i--)
     {
      if(ObjectFind(0, g_pins[i].name) < 0)
        {
         ObjectDelete(0, PinLbl(g_pins[i].name));
         ArrayRemove(g_pins, i, 1);
         ch = true;
         continue;
        }
      double p = ObjectGetDouble(0, g_pins[i].name, OBJPROP_PRICE, 0);
      if(MathAbs(p - g_pins[i].price) > _Point / 2)
        {
         g_pins[i].price = p;
         g_pins[i].since = TimeTradeServer();
         g_pins[i].hit = 0;
         ch = true;
        }
     }
   return ch;
  }

string PinText(const PinState &ps, bool panel)
  {
   if(ps.hit > 0)
      return Dts(ps.price) + " KENA " + ::GP_LocalTime(ps.hit) + (panel ? "" : " " + ::InpLocalTZName);
   double hl, bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(!LiveNow(hl) || bid <= 0)
      return Dts(ps.price) + " (market tutup)";
   double dd = ps.price - bid;
   return StringFormat("%s %s$%.1f s/d tutup %s", Dts(ps.price), dd >= 0 ? "+" : "-", MathAbs(dd),
                       PStrD(MathAbs(dd) / g_pAdr, hl));
  }

//--- label PIN di tepi kanan (area kosong chart shift), diperbarui tiap 2 detik
void PinLabels()
  {
   if(ArraySize(g_pins) == 0)
      return;
   datetime t2 = FutureT2(iTime(_Symbol, _Period, 0));
   for(int i = 0; i < ArraySize(g_pins); i++)
     {
      string n = PinLbl(g_pins[i].name);
      if(ObjectFind(0, n) < 0)
        {
         ObjectCreate(0, n, OBJ_TEXT, 0, t2, g_pins[i].price);
         Common(n, DMInpPinColor);
         ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
        }
      // di BAWAH garis: label garis cadangan/target di tepi kanan berada di ATAS garisnya -> tidak bertumpuk.
      // Diset tiap kali (label PIN bertahan saat indikator dimuat ulang, jadi bisa masih memakai anchor lama).
      ObjectSetInteger(0, n, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_TIME, 0, t2);
      ObjectSetDouble(0, n, OBJPROP_PRICE, 0, g_pins[i].price);
      ObjectSetString(0, n, OBJPROP_TEXT, "PIN " + PinText(g_pins[i], false) + "  ");
     }
   ChartRedraw();
  }

//--- tiap tick & tiap 2 detik: deteksi harga menyentuh PIN (bid melintasi garis). true = ada perubahan
bool PinTick(bool labels)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool ch = PinSync();
   datetime now = TimeTradeServer();
   for(int i = 0; i < ArraySize(g_pins) && bid > 0; i++)
     {
      double p = g_pins[i].price;
      if(g_pins[i].hit == 0 && g_lastBid > 0 && now > g_pins[i].since && (g_lastBid - p) * (bid - p) <= 0)
        {
         g_pins[i].hit = now;
         ch = true;
         if(::InpGPAlertPin)
            ::GP_Notify("pin" + g_pins[i].name + Dts(p), StringFormat("Harga menyentuh PIN %s (%s %s)", Dts(p),
                        ::GP_LocalTime(now), ::InpLocalTZName), now);
        }
     }
   if(bid > 0)
      g_lastBid = bid;
   if(ch || labels)
      PinLabels();
   return ch;
  }

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| BREAKOUT RANGE ASIA (aturan riset, dikunci):                      |
//|  box = high/low 18:00-03:00 ET (server 01:00-10:00);              |
//|  close M5 pertama di luar box antara 03:00-11:00 ET -> entry di   |
//|  open bar berikut, SL = tengah box, TP 1.5R, tutup 16:00 ET.      |
//|  Hasil: tahun riset +0.12R; 2017-25 -0.10R; rezim vol >2%: +0.13  |
//|  s/d +0.18R (hampir seluruhnya 2025-26) -> HIPOTESIS.            |
//+------------------------------------------------------------------+
struct AsiaSig
  {
   bool              valid, ready;   // box terbentuk / box sudah selesai
   double            hi, lo, mid;
   int               side, kEntry, kExit, result;   // result: -1 jalan, 0 belum ada sinyal, 1 TP, 2 SL, 3 tutup waktu, 4 tidak ada sinyal hari ini
   double            en, sl, tp, R;
  };

void CalcAsia(const DayInfo &d, int lastIdx, AsiaSig &a)
  {
   a.valid = false; a.ready = false; a.side = 0; a.kEntry = -1; a.kExit = -1; a.result = 0; a.R = 0;
   a.hi = -DBL_MAX; a.lo = DBL_MAX; a.en = a.sl = a.tp = 0;
   datetime tBox = d.t0 + 10 * 3600, tWin = d.t0 + 18 * 3600, tExit = d.t0 + 23 * 3600;
   int nb = 0, k = d.i0;
   for(; k <= lastIdx && g5[k].time < tBox; k++) { a.hi = MathMax(a.hi, g5[k].high); a.lo = MathMin(a.lo, g5[k].low); nb++; }
   if(nb < 60) return;
   a.valid = true; a.mid = (a.hi + a.lo) / 2;
   if(k > lastIdx) return;                      // box belum selesai
   a.ready = true;
   for(; k <= lastIdx; k++)
     {
      double sp = g5[k].spread * _Point;
      if(a.side == 0)
        {
         if(g5[k].time >= tWin) { a.result = 4; return; }
         int s = (g5[k].close > a.hi) ? 1 : ((g5[k].close < a.lo) ? -1 : 0);
         if(s == 0) continue;
         a.side = s; a.result = -1;
         if(k + 1 > lastIdx) { a.en = g5[k].close; a.sl = a.mid; a.tp = a.en + s * 1.5 * MathAbs(a.en - a.sl); return; }
         int e = k + 1;
         a.kEntry = e;
         a.en = g5[e].open + (s > 0 ? g5[e].spread * _Point : 0);
         a.sl = a.mid + (s < 0 ? sp : 0);
         double risk = (a.en - a.sl) * s;
         if(risk <= 0.3 * d.adr / 20) { a.side = 0; a.result = 4; return; }   // filter risiko minimum (riset)
         a.tp = a.en + s * 1.5 * risk;
         k = e - 1;
         continue;
        }
      if(k < a.kEntry) continue;
      if(g5[k].time >= tExit)
        {
         double px = (a.side > 0) ? g5[k].open : g5[k].open + sp;
         a.R = (px - a.en) * a.side / MathAbs(a.en - a.sl); a.result = 3; a.kExit = k; return;
        }
      if(a.side > 0)
        {
         if(g5[k].low <= a.sl)  { a.R = -1;  a.result = 2; a.kExit = k; return; }
         if(k > a.kEntry && g5[k].high >= a.tp) { a.R = 1.5; a.result = 1; a.kExit = k; return; }
        }
      else
        {
         if(g5[k].high + sp >= a.sl) { a.R = -1;  a.result = 2; a.kExit = k; return; }
         if(k > a.kEntry && g5[k].low + sp <= a.tp) { a.R = 1.5; a.result = 1; a.kExit = k; return; }
        }
     }
  }

string AsiaStatus(const AsiaSig &a)
  {
   if(!a.valid || !a.ready) return "tunggu box selesai";
   if(a.result == 4) return "tidak ada sinyal";
   if(a.side == 0)   return "tunggu breakout";
   string s = (a.side > 0) ? "BUY" : "SELL";
   if(a.result == 1) return s + " kena TP +1.5R";
   if(a.result == 2) return s + " kena SL -1R";
   if(a.result == 3) return s + StringFormat(" tutup %+.2fR", a.R);
   return s + (a.kEntry < 0 ? " SIAP (bar berikut)" : " AKTIF");
  }

string BiasTxt(ENUM_BIAS b) { return b == BIAS_BULLISH ? "BULL" : (b == BIAS_BEARISH ? "BEAR" : "netral"); }
string SesTxt(ENUM_SESSION s)
  {
   return s == SESSION_ASIA ? "Asia" : (s == SESSION_LONDON ? "London" : (s == SESSION_NEWYORK ? "New York" : "di luar KZ"));
  }

//--- GoldPro: panel peta harian ditaruh tepat DI BAWAH dashboard SMC (kiri atas),
//    membaca posisi & tinggi background dashboard/narasi saat berjalan.
int PanelTop()
  {
   int y = 22;
   if(ChartGetInteger(0, CHART_SHOW_ONE_CLICK))   // panel One Click Trading MT5 menempati kiri atas
      y += 70;
   string bgs[2] = {"GP_DASH_BG", "GP_NARR_BG"};
   for(int i = 0; i < 2; i++)
      if(ObjectFind(0, bgs[i]) >= 0)
         y = (int)MathMax(y, ObjectGetInteger(0, bgs[i], OBJPROP_YDISTANCE) + ObjectGetInteger(0, bgs[i], OBJPROP_YSIZE) + 12);
   return y;
  }

//--- panel POTRET (kolom sempit, baris pendek; batas teks label MT5 = 63 karakter)
void Panel(const DayInfo &d)
  {
   LiveInfo li;
   GetLive(d, li);
   string L[];
   color  K[];
   if(g_page == 5)
      PanelPage5(d, li, L, K);   // tombol "2 CEK SIAP" (+ jam biaya)
   else
      PanelPage1(d, li, L, K);   // tombol "1 PETA" (+ tangga target)
   ArrayResize(g_pL, ArraySize(L));
   ArrayResize(g_pK, ArraySize(K));
   for(int i = 0; i < ArraySize(L); i++) { g_pL[i] = L[i]; g_pK[i] = K[i]; }
   PanelLayout();
  }

//--- tata letak panel yang menyesuaikan tinggi chart (layar laptop kecil):
//    1) spasi normal  2) spasi rapat  3) huruf 7  4) dua kolom (kolom 2 mulai di judul bagian)
void PanelLayout()
  {
   int n = ArraySize(g_pL);
   ObjectsDeleteAll(0, PFX + "P");
   g_panR = BtnColR();
   g_panB = BtnColB();
   string pcid = IntegerToString(ChartID());
   GlobalVariableSet("GP_PANR_" + pcid, 0);                // tepi kanan panel halaman (EA: dashboard Saldo di kanannya)
   if(n == 0 || !g_vPanel || DMInpPanelMode == PANEL_OFF)
      return;
   int y0 = PanelTop() + (DMInpButtons ? BTN_H + 8 : 4);   // panel di kanan kolom tombol, di BAWAH label LIVE
   int x0 = DMInpButtons ? BtnColR() + 6 : 4;
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   g_lastCH = ch;
   int avail = (ch > 100) ? ch - y0 - 6 : 100000;
   int fs = DMInpPanelFont, lh = (int)MathRound(fs * 1.75);
   if(n * lh + 8 > avail) lh = (int)MathRound(fs * 1.55);
   if(n * lh + 8 > avail && fs > 7) { fs = 7; lh = (int)MathRound(fs * 1.6); }
//--- kolom secukupnya (maks 4): tiap kolom tidak lebih tinggi dari chart; pindah kolom di judul bagian
   int maxRows = MathMax(6, (avail - 8) / lh);
   int cols = (int)MathMin(4, MathCeil((double)n / maxRows));
   int target = (int)MathCeil((double)n / cols);
   int colOf[], rowOf[];
   ArrayResize(colOf, n);
   ArrayResize(rowOf, n);
   int c = 0, r = 0;
   for(int i = 0; i < n; i++)
     {
      bool hdr = (StringFind(g_pL[i], "--") == 0 || StringFind(g_pL[i], "==") == 0);
      if(r > 0 && c < 3 && (r >= maxRows || (hdr && c < cols - 1 && r >= target - 4)))
        {
         c++;
         r = 0;
        }
      colOf[i] = c;
      rowOf[i] = r++;
     }
   int nc = c + 1, rows = 0, wc[4] = {0, 0, 0, 0}, rc[4] = {0, 0, 0, 0}, xs[4] = {0, 0, 0, 0}, x = 0;
   for(int i = 0; i < n; i++) { wc[colOf[i]] = MathMax(wc[colOf[i]], StringLen(g_pL[i])); rc[colOf[i]]++; }
   for(int k = 0; k < nc; k++)
     {
      rows = MathMax(rows, rc[k]);
      xs[k] = x;
      x += (int)(MathMax(wc[k], (k == 0) ? 30 : 0) * fs * 0.82) + 12;   // kolom 1 lebar minimal tetap
     }
   string bg = PFX + "Pbg";
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x0);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y0 - 4);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, x + 2);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, rows * lh + 8);
   g_panR = MathMax(g_panR, x0 + x + 2);
   g_panB = MathMax(g_panB, y0 - 4 + rows * lh + 8);
   GlobalVariableSet("GP_PANR_" + pcid, x0 + x + 2);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, DMInpPanelBg);
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, clrDimGray);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
   for(int i = 0; i < n; i++)
     {
      string nm = PFX + "P" + IntegerToString(i);
      int cc = colOf[i], rr = rowOf[i];
      Label(nm, x0 + 5 + xs[cc], y0 + rr * lh, g_pL[i], g_pK[i]);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, fs);
     }
  }

//--- JAM BIAYA (dulu halaman 4; 10 Okt 2026 digabung ke halaman CEK SIAP) (3 Okt 2026, permintaan pengguna; research\cost_map.py & cost_profile.py, 12 bln Okt 2025 -
//    Okt 2026): spread broker hampir tetap $0.17 -> jam MURAH = jam harga banyak bergerak. Profil per slot 30 mnt JAM
//    SERVER (= NY + 7) sehingga tampilan WITA otomatis ikut pergantian musim AS. Biaya% = (spread + slip $0.20) / gerak
//    15 mnt normal (median gerak/ADR20 slot itu x ADR20 sekarang). Blok >= 1 jam: MURAH biaya <= ~3.8%, MAHAL >= ~5.5%
//    atau spread melebar (p90 >= $0.35, sekitar rollover). Peringkat slot stabil antar tahun. Impas (TP = SL = X) =
//    50% + 50 x biaya / X (arah ~50/50 di semua uji). INFO biaya, bukan sinyal arah.
const double GP_CP_MOVE[48] = {0.1104, 0.0947, 0.0615, 0.0637, 0.0642, 0.0809, 0.0935, 0.1001, 0.0966, 0.0887, 0.0746, 0.0701,
                               0.0606, 0.0557, 0.0613, 0.0645, 0.0813, 0.0822, 0.0761, 0.0731, 0.0753, 0.0776, 0.0729, 0.0667,
                               0.0685, 0.0635, 0.0632, 0.0648, 0.0727, 0.0794, 0.1103, 0.1153, 0.1217, 0.1434, 0.1273, 0.1095,
                               0.1017, 0.0851, 0.0791, 0.0724, 0.0753, 0.0689, 0.0669, 0.0638, 0.0628, 0.0618, 0.0441, 0.0400};
//    kategori per slot jam server 00:00..23:30: -1 murah, 0 sedang, 1 mahal (blok >= 1 jam; 13:00 server 5.6% = tepi -> sedang)
const int GP_CP_CAT[48] = {1, 1, 1, 1, 1, 0, -1, -1, -1, 0, 0, 0,
                           1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, -1, -1, -1, -1, -1, -1,
                           -1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1};
#define CP_SLIP 0.20
#define CP_SPN  0.17

int    CpSlot(datetime server) { return (int)((server % 86400) / 1800); }
string CpCatTxt(int c)         { return (c < 0) ? "MURAH" : ((c > 0) ? "MAHAL" : "sedang"); }
color  CpCatClr(int c)         { return (c < 0) ? clrLimeGreen : ((c > 0) ? clrTomato : clrSilver); }
string CpDur(int sec)          { return (sec >= 3600) ? StringFormat("%dj %02dm", sec / 3600, (sec % 3600) / 60) : StringFormat("%dm", sec / 60); }
string CpWhy(int startSlot, int c)
  {
   if(c < 0 && startSlot == 6)  return "buka Asia";
   if(c < 0 && startSlot == 30) return "buka NY, data AS";
   if(c > 0 && startSlot == 43) return "rollover, spread lebar";
   if(c > 0 && startSlot == 12) return "Asia istirahat, sepi";
   return "";
  }
int CpRunStart(int s)   // slot awal blok yang memuat slot s
  {
   int j = s;
   for(int i = 0; i < 47 && GP_CP_CAT[(j + 47) % 48] == GP_CP_CAT[s]; i++) j = (j + 47) % 48;
   return j;
  }

void CostLines(const DayInfo &d, const LiveInfo &li, string &L[], color &K[])
  {
   datetime now = TimeTradeServer(), day0 = now - now % 86400;
   bool open = ::TT_MarketOpen();
   double spr = open ? SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point : CP_SPN;
   AddLine(L, K, "-- JAM BIAYA [KOKOH] --", clrLimeGreen);
   int s = CpSlot(now), c = GP_CP_CAT[s];
   if(open)
     {
      //--- (sekarang murah / mahal & spread sudah di baris [Biaya] CEK SIAP di atas)
      double mv = GP_CP_MOVE[s] * d.adr;
      if(mv > 0)
         AddLine(L, K, StringFormat("Gerak 15m normal ~$%.1f | biaya %.1f%%", mv, (spr + CP_SLIP) / mv * 100), clrWhite);
      for(int want = -1; want <= 1; want += 2)               // blok murah / mahal berikutnya
        {
         if(want == c) continue;
         for(int j = 1; j < 48; j++)
            if(GP_CP_CAT[(s + j) % 48] == want && GP_CP_CAT[(s + j + 47) % 48] != want)
              {
               datetime t = day0 + (datetime)((s + j) * 1800);
               AddLine(L, K, StringFormat("%s berikut %s WITA (%s lagi)", (want < 0) ? "Murah" : "Mahal", ::GP_LocalTime(t),
                                          CpDur((int)(t - now))), CpCatClr(want));
               break;
              }
        }
     }
   else
      AddLine(L, K, "Market tutup - jadwal berlaku saat buka", clrSilver);
   //--- jadwal harian, diurutkan dari 00:00 WITA (geser ikut musim AS otomatis)
   AddLine(L, K, "-- JADWAL HARIAN (WITA) --", clrLimeGreen);
   int off = (int)(::GP_UTCToLocal(::GP_ServerToUTC(now)) - now) / 1800;   // selisih WITA - server (slot)
   int j0 = ((-off) % 48 + 48) % 48;                                         // slot server saat 00:00 WITA
   for(int i = 0; i < 48; i++)
     {
      int j = (j0 + i) % 48, cj = GP_CP_CAT[j];
      if(cj == 0 || GP_CP_CAT[(j + 47) % 48] == cj) continue;               // hanya awal blok murah / mahal
      int k = 1;
      while(k < 48 && GP_CP_CAT[(j + k) % 48] == cj) k++;
      datetime a = day0 + (datetime)(j * 1800), b = a + (datetime)(k * 1800);
      string why = CpWhy(j, cj);
      AddLine(L, K, StringFormat("%s-%s %s%s", ::GP_LocalTime(a), ::GP_LocalTime(b), CpCatTxt(cj), (why != "") ? " (" + why + ")" : ""),
              CpCatClr(cj));
     }
   AddLine(L, K, "selain itu: sedang", clrSilver);
   //--- impas: berapa % menang yang dibutuhkan hanya untuk menutup biaya (spread sekarang)
   AddLine(L, K, "-- MENANG MINIMUM UTK IMPAS (TP = SL) --", clrLimeGreen);
   double X[4] = {2, 3, 5, 10};
   string pa = "pasar:", lm = "limit:";
   for(int i = 0; i < 4; i++)
     {
      pa += StringFormat(" $%.0f %.0f%%", X[i], 50 + 50 * (spr + CP_SLIP) / X[i]);
      lm += StringFormat(" $%.0f %.0f%%", X[i], 50 + 50 * spr / X[i]);
     }
   AddLine(L, K, pa, clrWhite);
   AddLine(L, K, lm, clrWhite);
   AddLine(L, K, "arah ~50/50: kelebihan di atas 50% = biaya", clrSilver);
   AddLine(L, K, StringFormat("Biaya/hari 0.01 lot: 3 trade ~$%.1f | 38 ~$%.0f", 3 * (spr + CP_SLIP), 38 * (spr + CP_SLIP)), clrSilver);
  }

//--- HALAMAN 5 "CEK SIAP" (4 Okt 2026, permintaan pengguna): rekap konfirmasi scalping dalam satu layar - cek KONDISI, bukan
//    sinyal arah (arah = 50/50 di semua uji 2017-26). Biaya (jam murah + spread; cost_map/cost_profile), Gerak (rentang 1 jam,
//    GP_TouchTime terkalibrasi), Lokasi (garis GoldPro terdekat atas/bawah + peluang harga DATANG dlm 1 jam), Berita (data
//    PENTING AS), Diri (riwayat akun hari ini - hanya dibaca: jumlah trade, kalah beruntun, tanpa SL, lock, posisi/order
//    terbuka). Semua OK -> SIAP; selain itu TUNGGU + alasan terpenting (Diri > Berita > Biaya > Gerak > Lokasi).
void CekLine(string &L[], color &K[], string lab, int st, string txt)   // st: 1 OK, 0 TUNGGU, 2 cek manual
  {
   string mk = (st == 1) ? "v" : ((st == 0) ? "x" : "?");
   color  cl = (st == 1) ? clrLimeGreen : ((st == 0) ? clrTomato : clrOrange);
   AddLine(L, K, StringFormat("[%s] %-6s %s", mk, lab, txt), cl);
  }

struct CekRes
  {
   bool              open, okB, okG, okL, okN, okD, stopD;
   string            tB, tG, tN, tD, why, nmB, nmA;
   int               stN;                // berita: 1 OK, 0 TUNGGU, 2 kalender kosong
   double            pxB, pxA, pB, pA;   // garis BUY LIMIT (bawah) / SELL LIMIT (atas) & peluang DATANG 1 jam (-1 = tak ada)
   datetime          nt, now;
  };

//--- hitung semua cek (dipakai halaman 5 CEK SIAP & RADAR)
void CekCompute(const DayInfo &d, const LiveInfo &li, CekRes &R)
  {
   datetime now = TimeTradeServer(), day0 = now - now % 86400;
   bool open = ::TT_MarketOpen();
   double bid = open ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : li.cur;
   //--- 1 BIAYA: blok jam murah + spread live
   double spr = open ? SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point : CP_SPN;
   int s = CpSlot(now), c = GP_CP_CAT[s];
   bool wide = (spr > CP_SPN + 0.03), okB = (c < 0 && !wide);
   string tB, wB = "";
   if(okB)
     {
      int k = 1;
      while(k < 48 && GP_CP_CAT[(s + k) % 48] == c) k++;
      tB = StringFormat("MURAH s/d %s | spread $%.2f", ::GP_LocalTime(day0 + (datetime)((s + k) * 1800)), spr);
     }
   else
     {
      datetime tn = 0;
      for(int j = 1; j < 48; j++)
         if(GP_CP_CAT[(s + j) % 48] < 0 && GP_CP_CAT[(s + j + 47) % 48] >= 0) { tn = day0 + (datetime)((s + j) * 1800); break; }
      tB = wide ? StringFormat("spread MELEBAR $%.2f", spr)
                : StringFormat("%s - murah lagi %s (%s)", CpCatTxt(c), ::GP_LocalTime(tn), CpDur((int)(tn - now)));
      wB = wide ? "spread melebar" : "jam " + CpCatTxt(c) + ", murah lagi " + ::GP_LocalTime(tn) + " WITA";
     }
   //--- 2 GERAK: rentang 1 jam ke depan
   double rm = 0, r20 = 0, r80 = 0;
   bool hasR = open && ::TT_Range60(rm, r20, r80), okG = hasR && rm >= DMInpCekMinMove;
   string tG = hasR ? StringFormat("1 jam ~$%.0f ($%.0f-%.0f)%s", rm, r20, r80, okG ? "" : StringFormat(" < $%.0f", DMInpCekMinMove)) : "-";
   string wG = hasR ? StringFormat("harga lambat (1 jam ~$%.0f)", rm) : "";
   //--- 3 LOKASI: garis GoldPro terdekat di bawah (BUY LIMIT) & di atas (SELL LIMIT), peluang DATANG dlm 1 jam
   double lv[];
   string nm[], sh[];
   int nl = (d.adr > 0) ? RtLadder(d, li, lv, nm, sh) : 0;
   double gap = MathMax(0.02 * d.adr, 1.0), thr = DMInpCekMinTouch / 100.0;
   int ib = -1, ia = -1;
   for(int i = 0; i < nl; i++)
     {
      if(lv[i] <= bid - gap) ib = i;
      if(ia < 0 && lv[i] >= bid + gap) ia = i;
     }
   double pb = (ib >= 0 && open) ? ::TT_P(bid - lv[ib], 60) : -1, pa = (ia >= 0 && open) ? ::TT_P(lv[ia] - bid, 60) : -1;
   bool okL = (pb >= thr || pa >= thr);
   //--- 4 BERITA: data PENTING AS dalam x menit ke depan / 5 menit terakhir
   string nn = "";
   datetime nt = 0;
   int nNews = ArraySize(::g_upcomingNews);
   for(int i = 0; i < nNews; i++)
     {
      if(::g_upcomingNews[i].currency != "USD" || ::g_upcomingNews[i].importance < 2) continue;
      datetime et = ::g_upcomingNews[i].eventTime;
      if(et >= now - 5 * 60 && et <= now + DMInpCekNewsMin * 60 && (nt == 0 || et < nt)) { nt = et; nn = ::g_upcomingNews[i].name; }
     }
   bool okN = (nt == 0);
   string tN = !okN ? StringSubstr(nn, 0, 18) + " " + ::GP_LocalTime(nt) + ((nt > now) ? " (" + CpDur((int)(nt - now)) + " lagi)" : " (baru rilis)")
               : ((nNews == 0) ? "kalender kosong - cek manual" : StringFormat("aman %d mnt ke depan", DMInpCekNewsMin));
   //--- 5 DIRI: riwayat akun hari ini (hanya dibaca; indikator tidak pernah membuka/menutup order)
   int nTr = 0, lossRow = 0, nOpen = 0, noSL = 0, nOrd = 0;
   bool hb = false, hs = false;
   double pl = 0;
   if(HistorySelect(d.t0, now + 3600))
      for(int i = 0; i < HistoryDealsTotal(); i++)
        {
         ulong tk = HistoryDealGetTicket(i);
         if(tk == 0 || HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol) continue;
         long typ = HistoryDealGetInteger(tk, DEAL_TYPE);
         if(typ != DEAL_TYPE_BUY && typ != DEAL_TYPE_SELL) continue;
         long en = HistoryDealGetInteger(tk, DEAL_ENTRY);
         double r = HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_SWAP) + HistoryDealGetDouble(tk, DEAL_COMMISSION);
         pl += r;
         if(en == DEAL_ENTRY_IN) nTr++;
         else if(en == DEAL_ENTRY_OUT || en == DEAL_ENTRY_OUT_BY) lossRow = (r < 0) ? lossRow + 1 : 0;
        }
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      nOpen++;
      if(PositionGetDouble(POSITION_SL) <= 0) noSL++;
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) hb = true;
      else hs = true;
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk != 0 && OrderGetString(ORDER_SYMBOL) == _Symbol) nOrd++;
     }
   bool okD = true, stopD = true;
   string tD;
   if(noSL > 0)                            { okD = false; tD = StringFormat("%d posisi TANPA SL - pasang SL!", noSL); }
   else if(hb && hs)                       { okD = false; tD = "posisi LOCK - tutup salah satu"; }
   else if(lossRow >= DMInpCekMaxLossRow)  { okD = false; tD = StringFormat("%d kalah beruntun - STOP hari ini", lossRow); }
   else if(DMInpCekMaxTrades > 0 && nTr >= DMInpCekMaxTrades)
                                           { okD = false; tD = StringFormat("%d/%d trade - STOP hari ini", nTr, DMInpCekMaxTrades); }
   else if(nOpen + nOrd > 0)               { okD = false; stopD = false; tD = StringFormat("ada %d posisi / %d order - tunggu", nOpen, nOrd); }
   else tD = (DMInpCekMaxTrades > 0) ? StringFormat("trade %d/%d | kalah beruntun %d | P/L $%.2f", nTr, DMInpCekMaxTrades, lossRow, pl)
                                     : StringFormat("trade %d | kalah beruntun %d | P/L $%.2f", nTr, lossRow, pl);
   //--- hasil
   R.open = open; R.now = now; R.nt = nt;
   R.okB = okB; R.okG = okG; R.okL = okL; R.okN = okN; R.okD = okD; R.stopD = stopD;
   R.tB = tB; R.tG = tG; R.tN = tN; R.tD = tD;
   R.stN = okN ? ((nNews == 0) ? 2 : 1) : 0;
   R.pxB = (ib >= 0) ? lv[ib] : 0; R.pxA = (ia >= 0) ? lv[ia] : 0;
   R.nmB = (ib >= 0) ? nm[ib] : ""; R.nmA = (ia >= 0) ? nm[ia] : "";
   R.pB = pb; R.pA = pa;
   R.why = (!okD && stopD) ? tD : (!open ? "" : (!okN ? "berita " + ::GP_LocalTime(nt) + " WITA" : (!okB ? wB : (!okG ? wG : (!okL ? "garis terlalu jauh" : (!okD ? tD : ""))))));
  }

void PanelPage5(const DayInfo &d, const LiveInfo &li, string &L[], color &K[])
  {
   CekRes R;
   CekCompute(d, li, R);
   double thr = DMInpCekMinTouch / 100.0;
   AddLine(L, K, StringFormat("CEK SIAP TRADE | WITA %s%s", ::GP_LocalTime(R.now), R.open ? "" : " | tutup"), clrGold);
   CekLine(L, K, "Biaya", R.okB ? 1 : 0, R.tB);
   CekLine(L, K, "Gerak", R.okG ? 1 : 0, R.tG);
   CekLine(L, K, "Lokasi", R.okL ? 1 : 0, R.okL ? "garis layak dituju (datang 1j)" : StringFormat("garis terdekat < %d%% datang 1j", DMInpCekMinTouch));
   if(R.pxB > 0)
      AddLine(L, K, StringFormat("     BUY LIMIT  %s %s | %s", Dts(R.pxB), R.nmB, ::TT_Pct(R.pB)), (R.pB >= thr) ? DMInpUpColor : clrSilver);
   if(R.pxA > 0)
      AddLine(L, K, StringFormat("     SELL LIMIT %s %s | %s", Dts(R.pxA), R.nmA, ::TT_Pct(R.pA)), (R.pA >= thr) ? DMInpDnColor : clrSilver);
   CekLine(L, K, "Berita", R.stN, R.tN);
   CekLine(L, K, "Diri", R.okD ? 1 : 0, R.tD);
   AddLine(L, K, "----------------------------------------", clrDimGray);
   if(!R.open)
      AddLine(L, K, (!R.okD && R.stopD) ? ">> STOP: " + R.tD : ">> MARKET TUTUP", (!R.okD && R.stopD) ? clrTomato : clrSilver);
   else if(R.okB && R.okG && R.okL && R.okN && R.okD)
      AddLine(L, K, ">> SIAP: pasang LIMIT di garis layak", clrLimeGreen);
   else
      AddLine(L, K, ">> TUNGGU: " + R.why, (!R.okD && R.stopD) ? clrTomato : clrOrange);
   AddLine(L, K, StringFormat("SL = TP $%.0f | limit saja | maks 60 mnt", DMInpCekSLTP), clrSilver);
   AddLine(L, K, "cek KONDISI, bukan sinyal arah (arah ~50/50)", clrDimGray);
   CostLines(d, li, L, K);                    // dulu halaman "4 JAM BIAYA" (10 Okt 2026 digabung ke sini)
  }

//--- PDH / PDL DITEMBUS S/D TUTUP (5 Okt 2026, upgrade dari bedah GA - research\ga_drift.py, pdhl_break.py): peluang = tabel
//    live GoldPro (LiveP: jarak harga -> PDH/PDL dlm ADR & sisa jam; uji 2017-26 +-1.5 poin). Dihitung saat buka, tabel jarak
//    saja: Brier uji 2022-26 0.175 vs rata2 0.250. Kekuatan hari kemarin (harga 22:40 server vs EQ, temuan GA) hanya menggeser
//    +-1..6 poin & TIDAK memperbaiki uji 2022-26 (Brier 0.1745 vs 0.1747) -> ditampilkan sebagai keterangan saja.
void PdhlUpdate()
  {
   if(g_nd < 2) return;
   DayInfo d = g_days[g_nd - 1], yd = g_days[g_nd - 2];
   LiveInfo li;
   GetLive(d, li);
   double pdh = iHigh(_Symbol, PERIOD_D1, 1), pdl = iLow(_Symbol, PERIOD_D1, 1);
   double th = iHigh(_Symbol, PERIOD_D1, 0), tl = iLow(_Symbol, PERIOD_D1, 0);
   double px = li.open ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : li.cur;
   if(pdh <= 0 || pdl <= 0 || d.adr <= 0) { ::g_pdhP = -1; ::g_pdlP = -1; return; }
   if(th >= pdh) ::g_pdhP = 2.0;
   else ::g_pdhP = li.open ? LiveP(MathMax(0.0, pdh - px) / d.adr, li.hoursLeft) : -1.0;
   if(tl > 0 && tl <= pdl) ::g_pdlP = 2.0;
   else ::g_pdlP = li.open ? LiveP(MathMax(0.0, px - pdl) / d.adr, li.hoursLeft) : -1.0;
   //--- kekuatan hari kemarin (temuan GA): harga 22:40 server dibanding EQ kemarin, dalam ADR kemarin
   ::g_pdCls = "";
   if(yd.adr > 0)
      for(int k = yd.i0; k < yd.i1; k++)
         if(g5[k].time >= yd.t0 + 22 * 3600 + 40 * 60)
           {
            double s = (g5[k].open - (yd.open + yd.pdc) / 2) / yd.adr;
            ::g_pdCls = StringFormat("%s (%+.2f ADR dari EQ jam 22:40 server)",
                                     s >= 0.7 ? "NAIK KUAT" : (s >= 0.3 ? "naik" : (s > -0.3 ? "datar" : (s > -0.7 ? "turun" : "TURUN KUAT"))), s);
            break;
           }
  }
string PdhlTxt(double p) { return (p >= 1.5) ? "TERTEMBUS" : ((p < 0) ? "-" : ::TT_Pct(p)); }

//--- panel diperbarui tanpa membangun ulang peta (dipanggil tiap menit baru, agar RUTE HARGA ikut bergerak)
void RefreshPanel()
  {
   if(g_nd <= 0 || DMInpPanelMode == PANEL_OFF || !g_vPanel)
      return;
   Panel(g_days[g_nd - 1]);
   ChartRedraw();
  }

//--- PULLBACK LEG (research\retrace.py, M5 28.8 rb & M15 10.1 rb leg 2017-26): zigzag ATR - puncak/lembah
//    terkonfirmasi saat harga berbalik >= 1.5 x ATR14 (rata2 TR 14 candle sebelumnya), leg >= 4 ATR.
//    Setelah puncak: P(puncak baru sebelum tembus lembah awal) = 1 - kedalaman pullback (38.2/50/61.8/78.6% ->
//    61.0/50.2/38.5/21.8% vs rumus 61.8/50/38.2/21.4, tiap tahun, naik = turun). Level Fibonacci TIDAK istimewa.
void LegLines(ENUM_TIMEFRAMES tf, string &L[], color &K[])
  {
   string tfn = (tf == PERIOD_M5) ? "M5" : "M15";
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int n = CopyRates(_Symbol, tf, 0, 800, r);
   if(n < 60) { AddLine(L, K, "Leg " + tfn + ": data kurang", clrSilver); return; }
   double tr[];
   ArrayResize(tr, n);
   tr[0] = r[0].high - r[0].low;
   for(int i = 1; i < n; i++)
      tr[i] = MathMax(r[i].high - r[i].low, MathMax(MathAbs(r[i].high - r[i - 1].close), MathAbs(r[i].low - r[i - 1].close)));
   int mode = 1, dir = 0;
   double ext = r[20].high, lastExt = r[20].low, from = 0, to = 0, aL = 0;
   for(int t = 21; t <= n - 2; t++)                       // hanya candle yang sudah close
     {
      double a = 0;
      for(int j = t - 14; j < t; j++) a += tr[j];
      a /= 14.0;
      if(a <= 0) continue;
      if(mode == 1)
        {
         if(r[t].high > ext) ext = r[t].high;
         else if(r[t].low <= ext - 1.5 * a) { from = lastExt; to = ext; dir = 1; aL = a; mode = -1; lastExt = ext; ext = r[t].low; }
        }
      else
        {
         if(r[t].low < ext) ext = r[t].low;
         else if(r[t].high >= ext + 1.5 * a) { from = lastExt; to = ext; dir = -1; aL = a; mode = 1; lastExt = ext; ext = r[t].high; }
        }
     }
   double S = MathAbs(to - from), px = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(dir == 0 || S <= 0) { AddLine(L, K, "Leg " + tfn + ": belum ada leg", clrSilver); return; }
   double depth = (dir > 0) ? (to - px) / S : (px - to) / S;   // kedalaman pullback dari puncak/lembah leg
   // leg terakhir masih aktif (harga di antara kedua ujungnya) & cukup besar -> peluang terukur
   if(depth >= 0 && depth <= 1 && S >= 4.0 * aL)
     {
      AddLine(L, K, StringFormat("%s %s %s>%s ($%.1f)", tfn, dir > 0 ? "naik" : "turun", Dts(from), Dts(to), S),
              dir > 0 ? DMInpUpColor : DMInpDnColor);
      AddLine(L, K, StringFormat(" tarik %.0f%% -> lanjut %.0f%% | balik %.0f%%", depth * 100, (1 - depth) * 100, depth * 100),
              clrWhite);
      return;
     }
   // selain itu tampilkan gerak yang SEDANG berjalan dari titik balik terakhir (puncak/lembah belum terkonfirmasi)
   bool up = (mode == 1);                                     // mode 1 = sedang naik dari lembah terakhir
   AddLine(L, K, StringFormat("%s %s dari %s, ekstrem %s ($%.1f)", tfn, up ? "naik" : "turun", Dts(lastExt), Dts(ext),
                              MathAbs(ext - lastExt)), up ? DMInpUpColor : DMInpDnColor);
   AddLine(L, K, depth > 1 ? " leg lama tertembus; puncak/lembah baru blm konfirmasi"
                 : (depth < 0 ? " leg lama memanjang; tunggu tarikan 1.5 ATR"
                    : StringFormat(" leg terakhir kecil (%.1f ATR < 4), tak dihitung", S / aL)), clrSilver);
  }

//--- baris panel: peluang puncak & dasar hari ini bertahan s/d tutup (tabel khusus HoldP)
//--- GoldPro (2 Okt 2026, research\pijakan_time.py): rentang 1 jam ke depan + peluang harga DATANG ke Pijakan / Tujuan
//    SMC dalam 30 mnt / 1 jam / 2 jam (Core\GP_TouchTime.mqh: ritme jam + volatilitas 2 jam, uji 2022-26 meleset rata2
//    1.8 poin) dan mana yang disentuh duluan (jarak relatif). Pijakan/Tujuan hanya bila garisnya tampil (tombol SMC).
//    Peluang DATANG, bukan peluang memantul (OB/zona SMC tidak memantulkan lebih dari level biasa).
void TouchLines(double cur, string &L[], color &K[])
  {
   double rm, r20, r80;
   if(!::TT_MarketOpen() || !::TT_Range60(rm, r20, r80))
      return;
   AddLine(L, K, StringFormat("Rentang 1 jam ke depan ~$%.0f ($%.0f-%.0f)", rm, r20, r80), RvrClr());
   double pj = ::g_ttPijPrice, tj = ::g_ttTujPrice;
   double dp = (pj > 0) ? MathAbs(pj - cur) : -1.0, dt = (tj > 0) ? MathAbs(tj - cur) : -1.0;
   if(dp >= 0)
      AddLine(L, K, StringFormat("Pijakan %s %s$%.1f: 30m %s 1j %s 2j %s", Dts(pj), (pj >= cur) ? "+" : "-", dp,
              ::TT_Pct(::TT_P(dp, 30)), ::TT_Pct(::TT_P(dp, 60)), ::TT_Pct(::TT_P(dp, 120))), clrDeepSkyBlue);
   if(dt >= 0)
      AddLine(L, K, StringFormat("Tujuan  %s %s$%.1f: 30m %s 1j %s 2j %s", Dts(tj), (tj >= cur) ? "+" : "-", dt,
              ::TT_Pct(::TT_P(dt, 30)), ::TT_Pct(::TT_P(dt, 60)), ::TT_Pct(::TT_P(dt, 120))), clrGoldenrod);
   if(dp > 0 && dt > 0 && (pj - cur) * (tj - cur) < 0)
      AddLine(L, K, StringFormat("Duluan: Pijakan %s | Tujuan %s", ::TT_Pct(dt / (dp + dt)), ::TT_Pct(dp / (dp + dt))),
              DMInpPanelColor);
  }

//--- RUTE HARGA (3 Okt 2026, permintaan pengguna: "pijakan dari EQ, sekarang menuju T0 / T0 berhasil, sekarang menuju
//    T1 / T1 balik arah menuju T0"). Tangga garis GoldPro: EQ, T0 & T1..Tn atas/bawah (garis < 0.03 ADR digabung).
//    Urutan sentuhan dari candle M1 hari ini (jalur dalam candle: naik O-L-H-C, turun O-H-L-C; celah antar candle
//    dihitung melewati). Garis terakhir disentuh = X. Harga di seberang garis sebelumnya -> X TEMBUS, di sisi yang
//    sama -> X BALIK ARAH. Peluang garis tujuan duluan = % jalan dari X (research\eq_t0_progress.py: 34.7/57.1/79.9%
//    vs jarak 35.3/58.0/81.3, 2017-26; line_graph.py semua garis meleset 1-2 poin; 9 kondisi diuji, tidak ada yang
//    menambah ketepatan). PETA, bukan arah: untung & rugi seimbang dengan peluangnya.
void RtAdd(double &lv[], string &nm[], string &sh[], int &nl, double p, string n, string s)
  {
   ArrayResize(lv, nl + 1); ArrayResize(nm, nl + 1); ArrayResize(sh, nl + 1);
   lv[nl] = p; nm[nl] = n; sh[nl] = s;
   nl++;
  }

void RtSeg(const double &lv[], int nl, double a, double b, int &seq[], datetime &st[], int &ns, datetime t)
  {
   for(int i = 0; i < nl; i++)
     {
      int j = (b >= a) ? i : nl - 1 - i;                     // naik: garis bawah dulu; turun: garis atas dulu
      if(lv[j] < MathMin(a, b) || lv[j] > MathMax(a, b)) continue;
      if(ns > 0 && seq[ns - 1] == j) { st[ns - 1] = t; continue; }   // garis sama disentuh lagi -> jam terakhir
      ArrayResize(seq, ns + 1); ArrayResize(st, ns + 1);
      seq[ns] = j; st[ns] = t;
      ns++;
     }
  }

//--- tangga garis GoldPro (EQ, T0, T1..Tn atas/bawah), urut naik, garis < 0.03 ADR digabung. Dipakai RUTE HARGA & CEK SIAP.
int RtLadder(const DayInfo &d, const LiveInfo &li, double &lv[], string &nm[], string &sh[])
  {
   double tl[];
   string tn[], ts[];
   int nl = 0, nt = 0;
   ArrayResize(lv, 0); ArrayResize(nm, 0); ArrayResize(sh, 0);
   for(int s = -1; s <= 1; s += 2)
      for(int q = 1; q <= ExtMax(li, s); q++)
         RtAdd(tl, tn, ts, nt, d.open + s * q * 0.25 * d.adr, StringFormat("T%d %s", q, (s > 0) ? "atas" : "bawah"),
               StringFormat("T%d%s", q, (s > 0) ? "+" : "-"));
   if(DMInpShowT0)
     {
      RtAdd(tl, tn, ts, nt, T0Lvl(d, 1), "T0 atas", "T0+");
      RtAdd(tl, tn, ts, nt, T0Lvl(d, -1), "T0 bawah", "T0-");
     }
   RtAdd(tl, tn, ts, nt, (d.open + d.pdc) / 2, "EQ", "EQ");
   for(int i = 1; i < nt; i++)                                 // urutkan naik
      for(int j = i; j > 0 && tl[j] < tl[j - 1]; j--)
        {
         double tp = tl[j]; tl[j] = tl[j - 1]; tl[j - 1] = tp;
         string a = tn[j]; tn[j] = tn[j - 1]; tn[j - 1] = a;
         string b = ts[j]; ts[j] = ts[j - 1]; ts[j - 1] = b;
        }
   for(int i = 0; i < nt; i++)                                 // gabung garis yang berdempetan
     {
      if(nl > 0 && tl[i] - lv[nl - 1] < 0.03 * d.adr) { nm[nl - 1] += "/" + tn[i]; sh[nl - 1] += "/" + ts[i]; continue; }
      RtAdd(lv, nm, sh, nl, tl[i], tn[i], ts[i]);
     }
   return nl;
  }

void RouteLines(const DayInfo &d, const LiveInfo &li, string &L[], color &K[])
  {
   color W = DMInpPanelColor, G = clrSilver;
   AddLine(L, K, "-- RUTE HARGA [KOKOH] --", clrLimeGreen);
   if(d.adr <= 0) { AddLine(L, K, "ADR belum siap", G); return; }
   double lv[];
   string nm[], sh[];
   int nl = RtLadder(d, li, lv, nm, sh);
   //--- urutan sentuhan dari candle M1 hari ini (candle berjalan ikut dihitung)
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int n = CopyRates(_Symbol, PERIOD_M1, d.t0, TimeCurrent(), r);
   if(n <= 0) { AddLine(L, K, "data M1 belum siap", G); return; }
   int seq[];
   datetime st[];
   int ns = 0;
   double pt[5];
   for(int k = 0; k < n; k++)
     {
      bool up = (r[k].close >= r[k].open);
      pt[0] = (k > 0) ? r[k - 1].close : r[k].open;
      pt[1] = r[k].open;
      pt[2] = up ? r[k].low : r[k].high;
      pt[3] = up ? r[k].high : r[k].low;
      pt[4] = r[k].close;
      for(int g = 0; g < 4; g++)
         RtSeg(lv, nl, pt[g], pt[g + 1], seq, st, ns, r[k].time);
     }
   double cur = li.open ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : r[n - 1].close;
   string tag = li.open ? "" : " (terakhir)";
   if(ns == 0)
     {
      int ja = 0;
      while(ja < nl && lv[ja] <= cur) ja++;
      if(ja == 0 || ja >= nl) { AddLine(L, K, "Belum sentuh garis" + tag, G); return; }
      double f = (cur - lv[ja - 1]) / (lv[ja] - lv[ja - 1]);
      AddLine(L, K, "Belum sentuh garis" + tag + ":", W);
      AddLine(L, K, "di antara " + nm[ja - 1] + " & " + nm[ja], W);
      AddLine(L, K, StringFormat("%s duluan %.0f%% | %s %.0f%%", nm[ja], f * 100, nm[ja - 1], (1 - f) * 100), W);
      return;
     }
   int X = seq[ns - 1], side = (cur >= lv[X]) ? 1 : -1, Y = X + side;
   string head = (ns == 1) ? "Berangkat dari " + nm[X]
                 : nm[X] + (((lv[seq[ns - 2]] - lv[X]) * side < 0) ? " TEMBUS" : " BALIK ARAH");
   head += ((side > 0) ? " naik " : " turun ") + ::GP_LocalTime(st[ns - 1]) + tag;
   color dc = (side > 0) ? DMInpUpColor : DMInpDnColor;
   AddLine(L, K, head, dc);
   if(Y >= 0 && Y < nl)
     {
      double D = MathAbs(lv[Y] - lv[X]), dist = MathAbs(cur - lv[X]), f = MathMin(1.0, dist / D);
      AddLine(L, K, "sekarang menuju " + nm[Y] + " " + Dts(lv[Y]), dc);
      AddLine(L, K, StringFormat("jalan %.0f%% ($%.1f dari $%.1f)", f * 100, dist, D), W);
      AddLine(L, K, StringFormat("%s duluan %.0f%% | balik %s %.0f%%", nm[Y], f * 100, nm[X], (1 - f) * 100), W);
      if(li.open)
        {
         double dy = MathAbs(lv[Y] - cur);
         AddLine(L, K, StringFormat("sampai %s: 30m %s | 1j %s", nm[Y], ::TT_Pct(::TT_P(dy, 30)), ::TT_Pct(::TT_P(dy, 60))), G);
        }
     }
   else
      AddLine(L, K, "menjauh dari tangga garis", dc);
   string tr = "";
   int from = MathMax(0, ns - 6);
   for(int i = from; i < ns; i++)
      tr += ((i > from) ? ">" : "") + sh[seq[i]];
   AddLine(L, K, "Jejak: " + ((from > 0) ? "..>" : "") + tr, G);
  }

void HoldLines(const DayInfo &d, const LiveInfo &li, string &L[], color &K[], bool compact)
  {
   double hi = -DBL_MAX, lo = DBL_MAX;
   for(int k = d.i0; k <= li.last && k < d.i1; k++) { hi = MathMax(hi, g5[k].high); lo = MathMin(lo, g5[k].low); }
   if(hi < lo || d.adr <= 0)
      return;
   double ph = HoldP((hi - li.cur) / d.adr, li.hoursLeft), pl = HoldP((li.cur - lo) / d.adr, li.hoursLeft);
   if(compact)
      AddLine(L, K, StringFormat("Tahan: puncak %s | dasar %s", PStr(ph), PStr(pl)), DMInpPanelColor);
   else
     {
      AddLine(L, K, StringFormat("Puncak %s tahan %s", Dts(hi), PStr(ph)), DMInpUpColor);
      AddLine(L, K, StringFormat("Dasar  %s tahan %s", Dts(lo), PStr(pl)), DMInpDnColor);
     }
  }

double VolRatio(const DayInfo &d) { return (d.pdc > 0) ? d.adr / d.pdc * 100 : 0; }
string DirTxt(int dir)           { return (dir > 0) ? "NAIK" : ((dir < 0) ? "TURUN" : "menunggu..."); }

//--- HALAMAN 1 "PETA": statistik target, live, PIN, SMC, sesi
void PanelPage1(const DayInfo &d, const LiveInfo &li, string &L[], color &K[])
  {
   bool full = (DMInpPanelMode == PANEL_FULL);
   color W = DMInpPanelColor, G = clrSilver;
   AddLine(L, K, StringFormat("GOLDPRO %s  ADR %.2f", _Symbol, d.adr), clrGold);
   AddLine(L, K, "Open " + Dts(d.open) + " | Kmr " + Dts(d.pdc), W);
   AddLine(L, K, "Jam-1: " + DirTxt(d.dir), W);
   // Rezim (uji 2017-2026): setup hanya positif saat vol relatif tinggi (ADR20 > ~2% harga). HIPOTESIS.
   double vr = VolRatio(d);
   AddLine(L, K, StringFormat("Rezim vol %.2f%% %s", vr, vr >= 2.0 ? "TINGGI" : (vr >= 1.5 ? "sedang" : "RENDAH")),
           vr >= 2.0 ? clrGold : G);
   if(full)
     {
      AddLine(L, K, "-- TARGET [KOKOH] srh/lwn --", clrLimeGreen);
      AddLine(L, K, StringFormat("T1 %.0f/%.0f   T2 %.0f/%.0f", Pct(st_hitS[0], st_days), Pct(st_hitO[0], st_days),
              Pct(st_hitS[1], st_days), Pct(st_hitO[1], st_days)), W);
      AddLine(L, K, StringFormat("T3 %.0f/%.0f   T4 %.0f/%.0f", Pct(st_hitS[2], st_days), Pct(st_hitO[2], st_days),
              Pct(st_hitS[3], st_days), Pct(st_hitO[3], st_days)), W);
      // T1 atas ATAU bawah: hampir selalu tersentuh (uji 2017-26: 97.7-99.6% tiap tahun)
      double h1 = -DBL_MAX, l1 = DBL_MAX;
      for(int k = d.i0; k <= li.last && k < d.i1; k++) { h1 = MathMax(h1, g5[k].high); l1 = MathMin(l1, g5[k].low); }
      bool u1 = h1 >= d.open + LV[0] * d.adr, d1 = l1 <= d.open - LV[0] * d.adr;
      AddLine(L, K, StringFormat("T1 salah satu %.0f dua2 %.0f %s", Pct(st_any1, st_days), Pct(st_both1, st_days),
              (u1 && d1) ? "[dua2]" : (u1 ? "[atas]" : (d1 ? "[bawah]" : "[belum]"))), (u1 || d1) ? clrLimeGreen : W);
      if(DMInpShowT0)
        {
         bool u0 = h1 >= T0Lvl(d, 1), d0 = l1 <= T0Lvl(d, -1);
         AddLine(L, K, StringFormat("T0 %.0f/%.0f salah1 %.0f dua2 %.0f %s", Pct(st_hitS0, st_days), Pct(st_hitO0, st_days),
                 Pct(st_any0, st_days), Pct(st_both0, st_days), (u0 && d0) ? "[dua2]" : (u0 ? "[atas]" : (d0 ? "[bawah]" : "[belum]"))),
                 (u0 || d0) ? clrLimeGreen : W);
        }
      AddLine(L, K, StringFormat("Retest #1 %.0f #2 %.0f #3 %.0f", Pct(st_bounce[0], st_touch[0]), Pct(st_bounce[1], st_touch[1]),
              Pct(st_bounce[2], st_touch[2])), W);
      AddLine(L, K, StringFormat("Pullback %.0f | Lwt open %.0f", Pct(st_pbCont, st_pb), Pct(st_invCont, st_inv)), W);
     }
   RouteLines(d, li, L, K);
   //--- live (tabel peluang akurat di setiap tahun 2016-2026)
   AddLine(L, K, "-- LIVE [KOKOH] --", clrLimeGreen);
   if(li.open)
     {
      double eq = (d.open + d.pdc) / 2;
      AddLine(L, K, StringFormat("%s | sisa %.1f jam", Dts(li.cur), li.hoursLeft), W);
      AddLine(L, K, RvrTxt(), RvrClr());
      TouchLines(li.cur, L, K);
      AddLine(L, K, StringFormat("Atas  %s %s|%s", Dts(li.lvlUp), PStr(li.pUpFirst), PStr(li.pUpClose)), DMInpUpColor);
      AddLine(L, K, StringFormat("Bawah %s %s|%s", Dts(li.lvlDn), PStr(1.0 - li.pUpFirst), PStr(li.pDnClose)), DMInpDnColor);
      AddLine(L, K, StringFormat("EQ    %s tutup %s", Dts(eq), PStrD(MathAbs(li.cur - eq) / d.adr, li.hoursLeft)), DMInpEqColor);
      int kn = DMInpShowNYOpen ? NYOpenIdx(d) : -1;
      if(kn >= 0)
        {
         bool armed;
         int kb = NYBack(d, kn, li.last, armed);
         double lv = g5[kn].open;
         AddLine(L, K, StringFormat("NY %s %s %s", ::GP_LocalTime(g5[kn].time), Dts(lv),
                 (kb >= 0) ? "KEMBALI" : (armed ? "tutup " + PStrD(MathAbs(lv - li.cur) / d.adr, li.hoursLeft) : "dekat")), DMInpNYOpenColor);
        }
      AddLine(L, K, "(duluan | s/d tutup)", G);
      if(::g_pdhP > -1 || ::g_pdlP > -1)                  // 5 Okt 2026: PDH / PDL ditembus s/d tutup (tabel live)
         AddLine(L, K, StringFormat("PDH %s %s | PDL %s %s", Dts(iHigh(_Symbol, PERIOD_D1, 1)), PdhlTxt(::g_pdhP),
                                    Dts(iLow(_Symbol, PERIOD_D1, 1)), PdhlTxt(::g_pdlP)), clrOrange);
      double thr = BackupThr(), bd = LiveInv(thr, li.hoursLeft);
      if(bd > 0)
         AddLine(L, K, StringFormat("Cad%d %s/%s", (int)(thr * 100), Dts(li.cur + bd * d.adr), Dts(li.cur - bd * d.adr)), DMInpBackupColor);
      else
         AddLine(L, K, "Cadangan: sisa < 1 jam", G);
      HoldLines(d, li, L, K, false);
      AddLine(L, K, "-- PULLBACK LEG [KOKOH] --", clrLimeGreen);
      LegLines(PERIOD_M5, L, K);
      LegLines(PERIOD_M15, L, K);
     }
   else
      AddLine(L, K, "Market tutup", G);
   TargetLines(d, li, L, K);                 // tangga target + skor + cek akurasi (dulu halaman "2 ENTRY/TARGET")
   //--- PIN buatan Anda: peluang tersentuh s/d tutup (tabel live yang sama)
   int np = ArraySize(g_pins);
   if(np > 0)
     {
      AddLine(L, K, "-- PIN --", DMInpPinColor);
      for(int i = 0; i < np && i < 4; i++)
         AddLine(L, K, PinText(g_pins[i], true), DMInpPinColor);
     }
   //--- konteks SMC (arah belum terbukti -> info)
   BiasState bs = ::GetBiasState();
   MarketConditionState mc = ::GetMarketCondition();
   AddLine(L, K, "-- SMC [INFO] --", G);
   AddLine(L, K, StringFormat("H4 %s H1 %s M5 %s", BiasTxt(bs.htfBias), BiasTxt(bs.mtfBias), BiasTxt(bs.ltfBias)), G);
   string dec = (bs.decision == DECISION_ENTRY_OK) ? "ENTRY OK" : ((bs.decision == DECISION_WATCH) ? "watch" : "no zone");
   AddLine(L, K, StringFormat("%s | %s", mc.condition == CONDITION_TRENDING ? "trending" : (mc.condition == CONDITION_RANGING ? "ranging" : "compressed"), dec),
           bs.decision == DECISION_ENTRY_OK ? clrGold : G);
   if(full)
      AddLine(L, K, StringFormat("Zone %.0f POI %.0f [1 TH]", bs.scoreBreakdown.scoreZone, bs.scoreBreakdown.scorePOIQuality), G);
   //--- sesi & berita
   AddLine(L, K, "-- SESI --", G);
   ENUM_SESSION ns;
   string cd = ::GetNextKillzoneCountdown(ns);
   AddLine(L, K, "Jam " + ::InpLocalTZName + " " + ::GP_LocalTime(TimeTradeServer()), W);
   AddLine(L, K, SesTxt(::GetCurrentSession()) + " | " + SesTxt(ns) + " " + StringSubstr(cd, 0, 5), W);
   if(DMInpShowState)
      StateLines(L, K);
   SweepLines(L, K);
   NewsEvent ne;
   if(::GetNextNewsEvent(ne))
      AddLine(L, K, StringFormat("%s %dm%s", StringSubstr(ne.name, 0, 16), (int)((ne.eventTime - TimeCurrent()) / 60),
              ::IsNewsBlackout() ? " BLACKOUT" : ""), ::IsNewsBlackout() ? clrTomato : W);
   else
      AddLine(L, K, "Berita: tidak ada", G);
   AddLine(L, K, g_jOwner ? "Jurnal: AKTIF" : (DMInpJournal ? "Jurnal: chart lain" : "Jurnal: off"), g_jOwner ? clrLimeGreen : G);
  }

//--- MODEL PELUANG SWEEP per blok 5 menit jam New York (sweep = tembus high/low 60 mnt lalu balik >= 0.1 ADR
//    dalam 10 mnt). Dilatih M1 2017-2021, dicek 2022-2026: blok prediksi >= 8% -> prediksi 11% vs nyata
//    10-12% setiap tahun. logit p = B0 + B1*ln(dasar blok) + B2*ln(range 60 mnt / ADR). Dibatasi 14%
//    (di atas itu model terlalu tinggi). Ada data di blok ini -> angka kalender: 08:30 NY 26%, NFP 43%, FOMC 56%.
const double SWB0 = 0.6669, SWB1 = 0.8418, SWB2 = 0.7506;
const double SW_BASE[288] =
  {
   0.0031,0.0039,0.0047,0.0023,0.0078,0.0054,0.0218,0.0070,0.0039,0.0078,0.0047,0.0085,   // 00:00 NY
   0.0062,0.0093,0.0031,0.0078,0.0109,0.0148,0.0280,0.0101,0.0140,0.0062,0.0179,0.0217,   // 01:00 NY
   0.0381,0.0264,0.0256,0.0194,0.0194,0.0194,0.0280,0.0233,0.0155,0.0186,0.0318,0.0373,   // 02:00 NY
   0.0675,0.0311,0.0388,0.0264,0.0256,0.0202,0.0210,0.0194,0.0163,0.0171,0.0225,0.0194,   // 03:00 NY
   0.0225,0.0179,0.0155,0.0202,0.0148,0.0171,0.0148,0.0132,0.0148,0.0155,0.0179,0.0148,   // 04:00 NY
   0.0148,0.0117,0.0124,0.0140,0.0140,0.0109,0.0249,0.0101,0.0085,0.0078,0.0078,0.0124,   // 05:00 NY
   0.0132,0.0093,0.0109,0.0124,0.0171,0.0148,0.0179,0.0171,0.0085,0.0179,0.0171,0.0217,   // 06:00 NY
   0.0326,0.0194,0.0248,0.0225,0.0311,0.0287,0.0396,0.0179,0.0256,0.0303,0.0474,0.0489,   // 07:00 NY
   0.0916,0.0644,0.0970,0.0994,0.1545,0.0776,0.1514,0.0761,0.0745,0.0644,0.0660,0.0629,   // 08:00 NY
   0.0939,0.0698,0.0590,0.0559,0.0721,0.0512,0.1117,0.1102,0.0861,0.0861,0.1140,0.0861,   // 09:00 NY
   0.1319,0.0628,0.0644,0.0691,0.0659,0.0458,0.0644,0.0574,0.0543,0.0590,0.0613,0.0628,   // 10:00 NY
   0.0419,0.0465,0.0443,0.0357,0.0349,0.0497,0.0233,0.0287,0.0303,0.0233,0.0365,0.0248,   // 11:00 NY
   0.0279,0.0209,0.0272,0.0240,0.0194,0.0256,0.0163,0.0148,0.0124,0.0101,0.0203,0.0312,   // 12:00 NY
   0.0387,0.0310,0.0294,0.0246,0.0461,0.0477,0.0263,0.0231,0.0175,0.0136,0.0272,0.0208,   // 13:00 NY
   0.0424,0.0248,0.0240,0.0184,0.0224,0.0136,0.0280,0.0168,0.0232,0.0216,0.0176,0.0232,   // 14:00 NY
   0.0176,0.0200,0.0088,0.0072,0.0136,0.0128,0.0080,0.0136,0.0136,0.0240,0.0120,0.0230,   // 15:00 NY
   0.0060,0.0009,0.0035,0.0052,0.0001,0.0009,0.0026,0.0017,0.0069,0.0500,0.0460,0.0050,   // 16:00 NY
   0.0050,0.0050,0.0050,0.0050,0.0050,0.0050,0.0050,0.0050,0.0050,0.0050,0.0050,0.0050,   // 17:00 NY (tutup)
   0.0654,0.0202,0.0109,0.0101,0.0078,0.0109,0.0093,0.0078,0.0078,0.0054,0.0085,0.0078,   // 18:00 NY
   0.0179,0.0140,0.0085,0.0070,0.0093,0.0062,0.0093,0.0039,0.0062,0.0085,0.0256,0.0287,   // 19:00 NY
   0.0567,0.0264,0.0210,0.0132,0.0248,0.0155,0.0109,0.0070,0.0070,0.0116,0.0217,0.0287,   // 20:00 NY
   0.0714,0.0272,0.0202,0.0202,0.0109,0.0171,0.0116,0.0132,0.0140,0.0132,0.0078,0.0085,   // 21:00 NY
   0.0085,0.0054,0.0031,0.0047,0.0031,0.0062,0.0031,0.0054,0.0023,0.0008,0.0085,0.0078,   // 22:00 NY
   0.0062,0.0054,0.0039,0.0039,0.0023,0.0023,0.0016,0.0016,0.0039,0.0008,0.0016,0.0031    // 23:00 NY
  };

double SweepProb(double adr, string &why)
  {
   why = "";
   datetime now = TimeTradeServer();
   MqlDateTime et;
   TimeToStruct(::GP_UTCToET(::GP_ServerToUTC(now)), et);
   double p = 0;
   double hi[], lo[];
   if(adr > 0 && CopyHigh(_Symbol, PERIOD_M1, 1, 60, hi) == 60 && CopyLow(_Symbol, PERIOD_M1, 1, 60, lo) == 60)
     {
      double rv = MathMax((hi[ArrayMaximum(hi)] - lo[ArrayMinimum(lo)]) / adr, 0.01);
      double z = SWB0 + SWB1 * MathLog(SW_BASE[(et.hour * 60 + et.min) / 5]) + SWB2 * MathLog(rv);
      p = MathMin(1.0 / (1.0 + MathExp(-z)), 0.14);
     }
   datetime b0 = now - (et.min % 5) * 60 - et.sec;          // awal blok 5 menit ini
   for(int i = 0; i < ArraySize(::g_upcomingNews); i++)
     {
      datetime t = ::g_upcomingNews[i].eventTime;
      if(::g_upcomingNews[i].currency != "USD" || t < b0 || t >= b0 + 300) continue;
      string nm = ::g_upcomingNews[i].name;
      MqlDateTime e;
      TimeToStruct(::GP_UTCToET(::GP_ServerToUTC(t)), e);
      if(StringFind(nm, "Interest Rate Decision") >= 0 && p < 0.56)  { p = 0.56; why = " FOMC"; }
      else if(StringFind(nm, "Nonfarm Payrolls") >= 0 && p < 0.43)   { p = 0.43; why = " NFP"; }
      else if(e.hour == 8 && e.min == 30 && p < 0.26)                { p = 0.26; why = " DATA"; }
     }
   return p;
  }

//--- sweep hari ini dari M1 (definisi sama dengan riset). Terdeteksi SETELAH terjadi (maks 10 mnt):
//    INFO saja - uji 2017-26: masuk balik-arah setelah sweep rugi -0.16..-0.32R setiap tahun.
struct SwEv { datetime t; double px; int side; };
SwEv g_sw[];

void AddSw(const MqlRates &r[], int i, int j, int side)
  {
   double px = (side > 0) ? r[i].high : r[i].low;
   for(int k = i; k <= j; k++)
      px = (side > 0) ? MathMax(px, r[k].high) : MathMin(px, r[k].low);
   int n = ArraySize(g_sw);
   ArrayResize(g_sw, n + 1);
   g_sw[n].t = r[i].time; g_sw[n].px = px; g_sw[n].side = side;
  }

void FindSweeps(datetime from, double adr)
  {
   ArrayResize(g_sw, 0);
   MqlRates r[];
   if(adr <= 0) return;
   int n = CopyRates(_Symbol, PERIOD_M1, from - 2 * 3600, TimeTradeServer() + 60, r);
   if(n < 72) return;
   n--;                                                     // bar M1 terakhir belum close
   int rawU = -99, rawD = -99;
   for(int i = 60; i < n; i++)
     {
      double pm = r[i - 1].high, pn = r[i - 1].low;
      for(int k = i - 60; k < i - 1; k++) { pm = MathMax(pm, r[k].high); pn = MathMin(pn, r[k].low); }
      bool upP = r[i].high > pm, dnP = r[i].low < pn;
      if(!upP && !dnP) continue;
      int jU = -1, jD = -1;
      for(int j = i + 1; j < MathMin(i + 11, n); j++)
        {
         if(upP && jU < 0 && r[j].low <= pm - 0.1 * adr) jU = j;
         if(dnP && jD < 0 && r[j].high >= pn + 0.1 * adr) jD = j;
        }
      if(jU > 0) { if(i - rawU >= 10 && r[i].time >= from) AddSw(r, i, jU, 1);  rawU = i; }
      if(jD > 0) { if(i - rawD >= 10 && r[i].time >= from) AddSw(r, i, jD, -1); rawD = i; }
     }
  }

void DrawSweeps()
  {
   for(int i = 0; i < ArraySize(g_sw); i++)
     {
      string n = PFX + "SW" + IntegerToString((long)g_sw[i].t) + (g_sw[i].side > 0 ? "u" : "d");
      Arrow(n, g_sw[i].t, g_sw[i].px, 251, clrMagenta);
      ObjectSetInteger(0, n, OBJPROP_ANCHOR, g_sw[i].side > 0 ? ANCHOR_BOTTOM : ANCHOR_TOP);
      ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
      ObjectSetString(0, n, OBJPROP_TOOLTIP, StringFormat("SWEEP %s %s %s | INFO, bukan sinyal entry",
                      g_sw[i].side > 0 ? "ATAS" : "BAWAH", ::GP_LocalTime(g_sw[i].t), Dts(g_sw[i].px)));
     }
  }

//--- KONDISI PASAR (research consol.py & regime_state.py, M1 2017-2026). Ambang per slot 30 mnt jam NY (2017-21):
//    SIDEWAY = rentang W mnt <= 20% tersempit utk jam itu (W = 30/60/120/240); TREN / GEJOLAK = rentang 60 mnt
//    >= 80% terlebar jam itu, efisiensi |net|/rentang >= 0.6 (tren) atau < 0.6 (gejolak).
//    60 mnt berikutnya (2017-21 & 2022-26 sama): arah lanjut 47-49% di SEMUA kondisi (acak); rentang
//    sideway 0.81x, tren 1.29x, gejolak 1.34x normal jam itu [KOKOH]. Setelah sideway: tembus atas 50-51%, tembusan
//    lebih sering balik ke tengah kotak daripada lanjut 1 lebar; entry tembus kotak rugi setiap tahun -> INFO.
//    Penyebab terukur: jam sepi (Asia siang, awal Asia, akhir NY), menunggu data (rentang 0.80x), libur AS (0.39x).
const double CS_P20_30[48] = {0.0449,0.0483,0.0548,0.0685,0.0838,0.0872,0.0967,0.0942,0.0861,0.0800,0.0748,0.0747,
   0.0702,0.0708,0.0791,0.0873,0.1084,0.1502,0.1417,0.1489,0.1592,0.1353,0.1240,0.1058,0.0919,0.0810,0.0812,0.0852,
   0.0713,0.0662,0.0651,0.0603,0.0595,0.0407,0.0511,0.0511,0.0488,0.0479,0.0503,0.0524,0.0729,0.0725,0.0813,0.0728,
   0.0663,0.0563,0.0510,0.0467};
const double CS_P20_60[48] = {0.0653,0.0683,0.0754,0.0922,0.1110,0.1264,0.1337,0.1387,0.1301,0.1195,0.1112,0.1054,
   0.1029,0.1011,0.1073,0.1200,0.1439,0.1974,0.2121,0.2112,0.2225,0.2148,0.1834,0.1621,0.1394,0.1244,0.1177,0.1174,
   0.1130,0.0973,0.0938,0.0904,0.0866,0.0760,0.0726,0.0726,0.0726,0.0668,0.0708,0.0742,0.0926,0.1075,0.1154,0.1140,
   0.1018,0.0879,0.0778,0.0705};
const double CS_P20_120[48] = {0.1030,0.1034,0.1050,0.1157,0.1412,0.1623,0.1798,0.1908,0.1921,0.1889,0.1741,0.1631,
   0.1511,0.1472,0.1509,0.1584,0.1840,0.2390,0.2660,0.2932,0.3122,0.3059,0.2971,0.2743,0.2335,0.2075,0.1860,0.1762,
   0.1638,0.1552,0.1465,0.1368,0.1312,0.1174,0.1170,0.1170,0.1170,0.1170,0.1170,0.1295,0.1190,0.1336,0.1531,0.1683,
   0.1636,0.1485,0.1284,0.1146};
const double CS_P20_240[48] = {0.2038,0.1899,0.1756,0.1723,0.1805,0.1967,0.2115,0.2343,0.2480,0.2544,0.2597,0.2601,
   0.2470,0.2397,0.2346,0.2318,0.2423,0.2893,0.3160,0.3430,0.3711,0.3869,0.4018,0.4074,0.3986,0.3744,0.3561,0.3373,
   0.3022,0.2690,0.2446,0.2230,0.2085,0.1965,0.2391,0.2391,0.2391,0.2391,0.2391,0.2391,0.2391,0.2391,0.2391,0.2214,
   0.2118,0.2139,0.2121,0.2121};
const double CS_P80_60[48] = {0.1327,0.1420,0.1642,0.1873,0.2186,0.2398,0.2548,0.2645,0.2636,0.2412,0.2239,0.2155,
   0.2092,0.2025,0.2202,0.2449,0.2901,0.4134,0.4598,0.4337,0.4608,0.4474,0.3903,0.3374,0.2927,0.2553,0.2500,0.2570,
   0.2563,0.2380,0.2221,0.2120,0.1868,0.1625,0.1881,0.1881,0.1881,0.1601,0.1746,0.1696,0.2011,0.2224,0.2344,0.2391,
   0.2142,0.1837,0.1593,0.1467};

//--- 15 mnt (1 Okt 2026, research\p20_15.py, metode sama: validasi hitung ulang P20_30 vs tabel korelasi 0.999)
const double CS_P20_15[48] = {0.0306,0.0333,0.0386,0.0477,0.0602,0.0585,0.0692,0.0614,0.0581,0.0533,0.0506,0.0505,
   0.0485,0.0489,0.0564,0.0595,0.0824,0.0996,0.0962,0.1060,0.1036,0.0893,0.0833,0.0681,0.0608,0.0534,0.0572,0.0545,
   0.0482,0.0450,0.0435,0.0417,0.0338,0.0278,0.0341,0.0292,0.0341,0.0317,0.0348,0.0368,0.0535,0.0478,0.0549,0.0480,
   0.0431,0.0367,0.0345,0.0303};

double CsP20(int k, int s)
  {
   if(k == 0) return CS_P20_30[s];
   if(k == 1) return CS_P20_60[s];
   if(k == 2) return CS_P20_120[s];
   return CS_P20_240[s];
  }

struct MState { int st; int dur; int hNY; int slot; double hi, lo, net, w60, w15; datetime t0; };   // st: -1 ?, 0 normal, 1 sideway, 2 tren, 3 gejolak
MState g_ms;

void CalcMState(double adr)
  {
   g_ms.st = -1; g_ms.dur = 0; g_ms.w60 = 0; g_ms.net = 0; g_ms.w15 = 0; g_ms.slot = 0;
   MqlRates r[];
   if(adr <= 0) return;
   int n = CopyRates(_Symbol, PERIOD_M1, 1, 241, r);                  // bar M1 yang sudah close, lama -> baru
   if(n < 61 || TimeTradeServer() - r[n - 1].time > 600) return;       // data kurang / market tutup
   MqlDateTime et;
   TimeToStruct(::GP_UTCToET(::GP_ServerToUTC(r[n - 1].time)), et);
   int s = (et.hour * 60 + et.min) / 30;
   g_ms.hNY = et.hour;
   g_ms.slot = s;
   int Ws[4] = {30, 60, 120, 240};
   double h = r[n - 1].high, l = r[n - 1].low;
   int k = 0;
   for(int W = 1; W <= 240 && W <= n && k < 4; W++)
     {
      int i = n - W;
      if(r[n - 1].time - r[i].time != (W - 1) * 60) break;               // celah: akhir pekan / tutup harian
      h = MathMax(h, r[i].high); l = MathMin(l, r[i].low);
      if(W == 15) g_ms.w15 = (h - l) / adr;                             // rentang 15 mnt terakhir (label LIVE)
      if(W != Ws[k]) continue;
      double w = (h - l) / adr;
      if(w <= CsP20(k, s)) { g_ms.dur = W; g_ms.hi = h; g_ms.lo = l; g_ms.t0 = r[i].time; }
      if(W == 60 && i >= 1)
        {
         g_ms.w60 = w; g_ms.net = r[n - 1].close - r[i - 1].close;
         double eff = MathAbs(g_ms.net) / MathMax(h - l, _Point);
         g_ms.st = (w >= CS_P80_60[s]) ? ((eff >= 0.6) ? 2 : 3) : 0;
        }
      k++;
     }
   if(g_ms.dur > 0) g_ms.st = 1;
   else if(g_ms.st == -1) g_ms.st = -2;                              // data segar tapi 60 mnt terakhir terpotong jeda (baru buka)
  }

void DrawStateBox()
  {
   if(g_ms.st != 1) return;
   Rect(PFX + "CSBOX", g_ms.t0, g_ms.hi, TimeTradeServer(), g_ms.lo, C'28,48,58');
   ObjectSetString(0, PFX + "CSBOX", OBJPROP_TOOLTIP,
                   StringFormat("SIDEWAY >= %d mnt | arah tembus 50:50, INFO bukan sinyal", g_ms.dur));
   Text(PFX + "CSBOXT", g_ms.t0, g_ms.hi, StringFormat("sideway %d mnt", g_ms.dur), clrLightSteelBlue, ANCHOR_LEFT_LOWER);
  }

//--- LABEL "LIVE: <SESI> | <KONDISI>" di samping tombol "1 PETA" (permintaan pengguna 1 Okt 2026).
//    SESI menurut jam bursa lokal (ikut DST): ASIA (buka s/d London 08:00), LONDON (08:00 London s/d 08:00 NY),
//    LONDON+NY (08:00 NY s/d 16:30 London), NEW YORK (s/d tutup 17:00 NY).
//    KONDISI = CalcMState (60 mnt terakhir, ambang per jam 2017-21): KONSOLIDASI / UPTREND / DOWNTREND /
//    BERGEJOLAK / NORMAL. Uji 2017-26: meramal KERAMAIAN 1 jam berikut (sideway 0.81x, tren 1.29x, gejolak 1.34x)
//    TAPI arah lanjut hanya 47-49% -> UPTREND/DOWNTREND = deskripsi 60 mnt terakhir, BUKAN ramalan arah.
//    Lapisan 15 mnt (1 Okt): "15m SIDEWAY" = rentang 15 mnt <= 20% tersempit jam itu (CS_P20_15);
//    "15m JEDA" = setelah jam ramai (tren/gejolak) 15 mnt terakhir <= 35% rentang 60 mnt (harga berhenti sejenak).
//    Keduanya DESKRIPSI apa yang terlihat di chart; arah sesudahnya tetap acak (uji sideway/kondisi 2017-26).
#define LIVE_W 250
string SessName()
  {
   datetime u = ::GP_ServerToUTC(TimeTradeServer());
   MqlDateTime et, ld;
   TimeToStruct(::GP_UTCToET(u), et);
   TimeToStruct(::GP_UTCToLondon(u), ld);
   int e = et.hour * 60 + et.min, l = ld.hour * 60 + ld.min;
   bool ldn = (l >= 8 * 60 && l < 16 * 60 + 30), ny = (e >= 8 * 60 && e < 17 * 60);
   if(ldn && ny) return "LONDON+NY";
   if(ldn)       return "LONDON";
   if(ny)        return "NEW YORK";
   return "ASIA";
  }

void LiveTag()
  {
   string n = BPFX + "LIVE";
   if(!DMInpButtons) { ObjectDelete(0, n); return; }
   double adr = g_pAdr;
   string cond, tip;
   color bg;
   if(g_ms.st == -2 && adr > 0)                                   // 9 Okt (screenshot 06:19 WITA): dulu tertulis "MARKET TUTUP"
     { cond = "BARU BUKA (< 60 mnt)"; bg = C'55,55,65';
       tip = "Pasar sudah buka lagi sesudah jeda harian, tapi data M1 tanpa jeda belum 60 mnt -> kondisi pasar (sideway/tren)\n"
             "belum bisa dinilai. Tombol Kotak Sideway juga menunggu 60 mnt data utuh."; }
   else if(g_ms.st < 0 || adr <= 0)
     { cond = "MARKET TUTUP"; bg = C'55,55,65'; tip = "Market tutup / data M1 belum ada"; }
   else if(g_ms.st == 1)
     {
      cond = StringFormat("KONSOLIDASI %dm", g_ms.dur); bg = C'30,70,95';
      tip = StringFormat("KONSOLIDASI >= %d mnt: rentang %s-%s ($%.1f) termasuk 20%% tersempit untuk jam ini.\n"
                         "1 jam ke depan biasanya tenang (0.8x). Arah tembus 50:50 [uji 2017-26].",
                         g_ms.dur, Dts(g_ms.lo), Dts(g_ms.hi), g_ms.hi - g_ms.lo);
     }
   else if(g_ms.st == 2)
     {
      cond = g_ms.net > 0 ? "UPTREND" : "DOWNTREND"; bg = g_ms.net > 0 ? C'20,95,45' : C'120,30,30';
      tip = StringFormat("TREN %s 60 mnt terakhir %+.1f$ (%.2f ADR), gerak searah & lebar.\n"
                         "1 jam ke depan tetap ramai (1.3x) TAPI arah lanjut hanya 47%% (acak) - deskripsi, bukan ramalan.",
                         g_ms.net > 0 ? "NAIK" : "TURUN", g_ms.net, MathAbs(g_ms.net) / adr);
     }
   else if(g_ms.st == 3)
     {
      cond = "BERGEJOLAK"; bg = C'130,75,10';
      tip = StringFormat("BERGEJOLAK: rentang 60 mnt $%.1f lebar tapi bolak-balik.\n1 jam ke depan ramai (1.3x), arah acak.", g_ms.w60 * adr);
     }
   else
     {
      cond = g_ms.net >= 0 ? "NORMAL (naik)" : "NORMAL (turun)"; bg = C'55,55,65';
      tip = StringFormat("Normal: rentang 60 mnt $%.1f, gerak bersih %+.1f$ - tidak sideway, tidak tren kuat.", g_ms.w60 * adr, g_ms.net);
     }
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_EDIT, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_READONLY, true);
      ObjectSetInteger(0, n, OBJPROP_ALIGN, ALIGN_CENTER);
      ObjectSetString(0, n, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_ZORDER, 10);
      ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, clrDimGray);
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, BtnColR() + 4);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, PanelTop());
   ObjectSetInteger(0, n, OBJPROP_XSIZE, LIVE_W);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, BTN_H);
   string m15 = "";
   if(g_ms.st >= 0 && g_ms.w15 > 0 && adr > 0)
     {
      if(g_ms.w15 <= CS_P20_15[g_ms.slot])
         m15 = " | 15m SIDEWAY";
      else if((g_ms.st == 2 || g_ms.st == 3) && g_ms.w15 <= 0.35 * g_ms.w60)
         m15 = " | 15m JEDA";
      tip += StringFormat("\n15 mnt terakhir: rentang $%.2f (%.0f%% dari 60 mnt; sideway 15m bila <= $%.2f untuk jam ini)",
                          g_ms.w15 * adr, g_ms.w60 > 0 ? g_ms.w15 / g_ms.w60 * 100 : 0, CS_P20_15[g_ms.slot] * adr);
      if(m15 != "")
         tip += "\n15m = gambaran 15 menit terakhir; arah sesudahnya tetap acak (50:50).";
     }
   ObjectSetString(0, n, OBJPROP_TEXT, "LIVE: " + SessName() + " | " + cond + m15);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, tip);
  }

bool InLive(int x, int y)
  {
   if(!DMInpButtons) return false;
   int x0 = BtnColR() + 4, y0 = PanelTop();
   return x >= x0 && x <= x0 + LIVE_W && y >= y0 && y <= y0 + BTN_H;
  }

void StateLines(string &L[], color &K[])
  {
   double adr = g_pAdr;
   if(g_ms.st < 0 || adr <= 0)
     { AddLine(L, K, (g_ms.st == -2 && adr > 0) ? "KONDISI: - (baru buka, data < 60 mnt)" : "KONDISI: - (market tutup)", clrSilver); return; }
   if(g_ms.st == 1)
     {
      int back = (g_ms.dur == 30) ? 56 : ((g_ms.dur == 60) ? 52 : ((g_ms.dur == 120) ? 41 : 31));
      AddLine(L, K, StringFormat("KONDISI: SIDEWAY >= %d mnt [KOKOH]", g_ms.dur), clrAqua);
      AddLine(L, K, StringFormat(" kotak %s-%s ($%.1f = %.2f ADR)", Dts(g_ms.lo), Dts(g_ms.hi), g_ms.hi - g_ms.lo,
                                 (g_ms.hi - g_ms.lo) / adr), clrSilver);
      AddLine(L, K, StringFormat(" tembus atas:bawah 50:50 | %d%% balik ke tengah", back), clrSilver);
      AddLine(L, K, " 1 jam ke depan biasanya tenang (0.8x)", clrSilver);
      //--- penyebab yang terukur: menunggu data penting / jam sepi (likuiditas rendah)
      string why = "";
      datetime now = TimeTradeServer();
      for(int i = 0; i < ArraySize(::g_upcomingNews); i++)
        {
         datetime t = ::g_upcomingNews[i].eventTime;
         if(::g_upcomingNews[i].currency == "USD" && t > now && t <= now + 90 * 60)
           { why = "menunggu " + StringSubstr(::g_upcomingNews[i].name, 0, 16) + " " + ::GP_LocalTime(t); break; }
        }
      int hn = g_ms.hNY;
      if(why == "" && (hn == 0 || hn == 1 || hn == 16 || hn == 18 || hn == 19 || hn == 23))
         why = "jam sepi (likuiditas rendah)";
      if(why != "")
         AddLine(L, K, " sebab: " + why, clrSilver);
     }
   else if(g_ms.st == 2)
     {
      AddLine(L, K, StringFormat("KONDISI: TREN %s 60 mnt %+.1f$ (%.2f ADR)", g_ms.net > 0 ? "NAIK" : "TURUN", g_ms.net,
                                 MathAbs(g_ms.net) / adr), g_ms.net > 0 ? DMInpBuyColor : DMInpSellColor);
      AddLine(L, K, " 1 jam ke depan tetap ramai (1.3x) [KOKOH]", clrSilver);
      AddLine(L, K, " arah lanjut hanya 47% (acak)", clrSilver);
     }
   else if(g_ms.st == 3)
     {
      AddLine(L, K, StringFormat("KONDISI: BERGEJOLAK rentang 60m $%.1f", g_ms.w60 * adr), clrOrange);
      AddLine(L, K, " 1 jam ke depan tetap ramai (1.3x), arah acak", clrSilver);
     }
   else
      AddLine(L, K, StringFormat("KONDISI: normal (rentang 60m $%.1f)", g_ms.w60 * adr), clrSilver);
  }

//--- jendela RAWAN SWEEP 08:00-11:30 jam New York [KOKOH]: sweep 3-4x rata-rata, pola per tahun
//    korelasi 0.91-0.99 (2017-2026). Menampilkan jendela berikutnya (lewati akhir pekan) + hitung mundur.
void SweepLines(string &L[], color &K[])
  {
   datetime now = TimeTradeServer();
   datetime s0 = ::GP_SweepStart(now);
   if(now >= s0 + 210 * 60) s0 = ::GP_SweepStart(now + 86400);
   for(int i = 0; i < 3; i++)                        // lewati Sabtu/Minggu (tanggal New York)
     {
      MqlDateTime ny;
      TimeToStruct(::GP_UTCToET(::GP_ServerToUTC(s0)), ny);
      if(ny.day_of_week >= 1 && ny.day_of_week <= 5) break;
      s0 = ::GP_SweepStart(s0 + 86400);
     }
   datetime s1 = s0 + 210 * 60;
   string st; color c = clrSilver;
   if(now >= s0 && now < s1) { st = " SEKARANG! SL ketat mudah tersapu"; c = clrTomato; }
   else
     {
      int m = (int)((s0 - now) / 60);
      st = (m >= 24 * 60) ? " berikutnya hari kerja" : StringFormat(" mulai %dj%02dm lagi", m / 60, m % 60);
      c = (m <= 30) ? clrOrange : clrSilver;
     }
   AddLine(L, K, "RAWAN SWEEP " + ::GP_LocalTime(s0) + "-" + ::GP_LocalTime(s1) + " " + ::InpLocalTZName + " [KOKOH]",
           (c == clrTomato) ? clrTomato : clrGold);
   AddLine(L, K, st, c);
   //--- menit terpanas New York 08:20 08:30 09:30 09:50 10:00 (uji M1 2017-26: 12-18% hari ada sweep di
   //    blok 5 mnt itu vs rata2 2.7%, 9-10 dari 10 tahun). Hilang saat libur AS (NYSE tutup: 0-2%).
   AddLine(L, K, " menit panas " + ::GP_LocalTime(s0 + 20 * 60) + " " + ::GP_LocalTime(s0 + 30 * 60) + " " +
           ::GP_LocalTime(s0 + 90 * 60) + " " + ::GP_LocalTime(s0 + 110 * 60) + " " + ::GP_LocalTime(s0 + 120 * 60),
           (c == clrSilver) ? clrSilver : clrOrange);
   if(TimeTradeServer() - iTime(_Symbol, PERIOD_M1, 0) < 600)          // market sedang jalan
     {
      string why;
      double sp = SweepProb(g_pAdr, why);
      AddLine(L, K, StringFormat(" peluang sweep 5 mnt ini %.0f%%%s (rata2 3%%)", sp * 100, why),
              sp >= 0.10 ? clrTomato : (sp >= 0.05 ? clrOrange : clrSilver));
      //--- GERAK 5 MENIT dalam ukuran ADR (chart yang di-zoom membuat $5 tampak seperti jatuh besar).
      //    Uji M1 2017-26: >= 0.06 ADR ~20x/hari, >= 0.10 ~8x, >= 0.15 ~3x, >= 0.25 ~0.7x/hari. Sesudahnya
      //    arah lanjut hanya 44-49% (acak, perak ikut pun sama); ikut arah rugi setiap tahun -> INFO saja.
      double cl[];
      if(g_pAdr > 0 && CopyClose(_Symbol, PERIOD_M1, 1, 6, cl) == 6)
        {
         double mv = cl[5] - cl[0], ra = MathAbs(mv) / g_pAdr;
         string fq = (ra >= 0.25) ? "langka <1x/hari" : ((ra >= 0.15) ? "~3x/hari" :
                     ((ra >= 0.10) ? "~8x/hari" : ((ra >= 0.06) ? "~20x/hari" : "normal")));
         AddLine(L, K, StringFormat(" gerak 5 mnt %+.1f$ = %.2f ADR (%s)", mv, ra, fq), ra >= 0.15 ? clrOrange : clrSilver);
        }
     }
   int nsw = ArraySize(g_sw);
   if(nsw > 0)
      AddLine(L, K, StringFormat(" sweep hari ini %d | akhir %s %s", nsw, ::GP_LocalTime(g_sw[nsw - 1].t),
              g_sw[nsw - 1].side > 0 ? "ATAS" : "BAWAH"), clrMagenta);
   //--- penyebab terbukti (kalender MT5 Agu 2025-Sep 2026 + 2017-26): data PENTING 08:30 NY -> 26% vs 8%
   //    tanpa rilis; NFP (Jumat pertama) 43% vs 16%; FOMC 14:00 NY -> 56% vs 3%. Data 10:00 NY TIDAK menambah.
   bool at830 = false, nfp = false, fomc = false;
   datetime tf = 0;
   string nm = "";
   for(int i = 0; i < ArraySize(::g_upcomingNews); i++)
     {
      if(::g_upcomingNews[i].currency != "USD") continue;
      datetime et = ::g_upcomingNews[i].eventTime;
      if(et < now - 15 * 60 || et > now + 86400) continue;
      string n = ::g_upcomingNews[i].name;
      if(StringFind(n, "Interest Rate Decision") >= 0 && !fomc) { fomc = true; tf = et; }
      if(et == s0 + 30 * 60)
        {
         if(!at830) nm = n;
         at830 = true;
         if(StringFind(n, "Nonfarm Payrolls") >= 0) nfp = true;
        }
     }
   if(nfp)
      AddLine(L, K, " NFP " + ::GP_LocalTime(s0 + 30 * 60) + ": sweep 43% hari (biasa 16%)", clrTomato);
   else if(at830)
      AddLine(L, K, " " + StringSubstr(nm, 0, 14) + " " + ::GP_LocalTime(s0 + 30 * 60) + ": sweep 26% (tanpa 5%)", clrOrange);
   if(fomc)
      AddLine(L, K, " FOMC " + ::GP_LocalTime(tf) + ": sweep 56% (biasa 3%)", clrTomato);
  }

//--- HALAMAN 2 "ENTRY & TARGET": entry [HIPOTESIS], tangga target live (hit / belum + peluang),
//    garis cadangan, skor hari-hari terakhir, cek akurasi 20 hari.
//--- TANGGA TARGET + SKOR + CEK AKURASI (dulu halaman "2 ENTRY/TARGET"; 10 Okt 2026 pindah ke halaman 1 PETA, blok
//    ENTRY [HIPOTESIS] straddle / breakout Asia / AM Fix dibuang: rugi setelah biaya 2017-25). Cadangan & puncak bertahan
//    sudah ada di bagian LIVE halaman 1.
void TargetLines(const DayInfo &d, const LiveInfo &li, string &L[], color &K[])
  {
   color W = DMInpPanelColor, G = clrSilver;
   double thr = BackupThr();
   //=== TARGET HARI INI: tangga harga dari atas ke bawah, posisi harga sekarang di tengahnya
   AddLine(L, K, "-- TARGET HARI INI (% s/d tutup) --", clrLimeGreen);
   Ladder(d, li, L, K);

   //=== SKOR hari-hari terakhir: target terjauh yang tersentuh
   AddLine(L, K, "-- SKOR 3 HARI (terjauh) --", clrLimeGreen);
   int shown = 0;
   for(int n = g_nd - 2; n >= 0 && shown < 3; n--)
     {
      if(!g_days[n].done || g_days[n].dir == 0)
         continue;
      double hm = -DBL_MAX, lm = DBL_MAX;
      for(int k = g_days[n].i0; k < g_days[n].i1; k++) { hm = MathMax(hm, g5[k].high); lm = MathMin(lm, g5[k].low); }
      int qu = -1, qd = -1;
      for(int q = 0; q < NLV; q++)
        {
         if(hm >= g_days[n].open + LV[q] * g_days[n].adr) qu = q;
         if(lm <= g_days[n].open - LV[q] * g_days[n].adr) qd = q;
        }
      AddLine(L, K, StringFormat("%s %-5s atas %s bwh %s", DayLbl(g_days[n].t0), DirTxt(g_days[n].dir),
              qu >= 0 ? "T" + IntegerToString(qu + 1) : "-", qd >= 0 ? "T" + IntegerToString(qd + 1) : "-"), W);
      shown++;
     }

   //=== CEK AKURASI hari-hari terakhir (monitor: apakah pasar masih seperti statistiknya)
   AddLine(L, K, StringFormat("-- CEK %d HARI TERAKHIR --", st_rcDays), clrLimeGreen);
   if(st_bkN > 0)
     {
      double acc = Pct(st_bkHit, st_bkN);
      AddLine(L, K, StringFormat("Cad%d kena %.0f%% (harus ~%d)", (int)(thr * 100), acc, (int)(thr * 100)),
              MathAbs(acc - thr * 100) <= 8 ? clrLimeGreen : clrTomato);
     }
   AddLine(L, K, StringFormat("%dhr  T1 %.0f/%.0f T2 %.0f/%.0f", st_rcDays, Pct(st_rcS[0], st_rcDays), Pct(st_rcO[0], st_rcDays),
           Pct(st_rcS[1], st_rcDays), Pct(st_rcO[1], st_rcDays)), W);
   AddLine(L, K, StringFormat("%dhr T1 %.0f/%.0f T2 %.0f/%.0f", st_days, Pct(st_hitS[0], st_days), Pct(st_hitO[0], st_days),
           Pct(st_hitS[1], st_days), Pct(st_hitO[1], st_days)), G);
  }

//--- tangga target hari ini: T4 atas ... T4 bawah + EQ + harga sekarang, diurutkan dari harga tertinggi.
//    Sudah kena -> "KENA jam"; belum -> peluang kena s/d tutup (berubah tiap candle M5).
//--- garis terjauh yang ditampilkan di satu sisi: T1-T4 selalu; lewat T4 (hari tren) -> T5, T6, ... sampai
//    garis pertama DI LUAR harga (maks T12 = 3 ADR). s = +1 atas, -1 bawah.
int ExtMax(const LiveInfo &li, int s)
  {
   int k = (s > 0) ? li.kUp : -li.kDn;
   return (int)MathMin(12, MathMax(NLV, k));
  }

void Ladder(const DayInfo &d, const LiveInfo &li, string &L[], color &K[])
  {
   double pr[];
   string tx[];
   color  cl[];
   int n = 0;
   double eq = (d.open + d.pdc) / 2;
   for(int s = 1; s >= -1; s -= 2)
      for(int q = 1; q <= ExtMax(li, s) + ((s > 0) ? 1 : 0); q++)
        {
         bool isEq = (s > 0 && q == ExtMax(li, s) + 1);   // EQ ditambahkan sekali di akhir sisi atas
         double lvl = isEq ? eq : d.open + s * q * 0.25 * d.adr;
         string nm = isEq ? "EQ     " : StringFormat("T%d %s", q, (s > 0) ? "atas " : "bawah");
         int hitK = -1;
         for(int k = d.i0; k <= li.last && k < d.i1; k++)
            if(isEq ? (g5[k].low <= lvl && g5[k].high >= lvl)
               : ((s > 0 && g5[k].high >= lvl) || (s < 0 && g5[k].low <= lvl))) { hitK = k; break; }
         string st;
         if(hitK >= 0)
            st = "KENA " + ::GP_LocalTime(g5[hitK].time);
         else
            st = li.open ? "belum " + PStrD(MathAbs(lvl - li.cur) / d.adr, li.hoursLeft) : "tidak kena";
         ArrayResize(pr, n + 1); ArrayResize(tx, n + 1); ArrayResize(cl, n + 1);
         pr[n] = lvl;
         tx[n] = nm + " " + Dts(lvl) + " " + st;
         cl[n] = isEq ? DMInpEqColor : ((hitK >= 0) ? ((s > 0) ? DMInpUpColor : DMInpDnColor) : DMInpPanelColor);
         n++;
        }
   //--- T0 atas/bawah (tengah EQ-T1)
   for(int s = 1; s >= -1 && DMInpShowT0; s -= 2)
     {
      double lvl = T0Lvl(d, s);
      int hitK = -1;
      for(int k = d.i0; k <= li.last && k < d.i1; k++)
         if((s > 0 && g5[k].high >= lvl) || (s < 0 && g5[k].low <= lvl)) { hitK = k; break; }
      ArrayResize(pr, n + 1); ArrayResize(tx, n + 1); ArrayResize(cl, n + 1);
      pr[n] = lvl;
      tx[n] = StringFormat("T0 %s %s %s", (s > 0) ? "atas " : "bawah", Dts(lvl), (hitK >= 0) ? "KENA " + ::GP_LocalTime(g5[hitK].time)
              : (li.open ? "belum " + PStrD(MathAbs(lvl - li.cur) / d.adr, li.hoursLeft) : "tidak kena"));
      cl[n] = (hitK >= 0) ? ((s > 0) ? DMInpUpColor : DMInpDnColor) : DMInpPanelColor;
      n++;
     }
   //--- Open NY 09:30 ET (setelah terbentuk)
   int kn = DMInpShowNYOpen ? NYOpenIdx(d) : -1;
   if(kn >= 0)
     {
      bool armed;
      int kb = NYBack(d, kn, li.last, armed);
      double lv = g5[kn].open;
      ArrayResize(pr, n + 1); ArrayResize(tx, n + 1); ArrayResize(cl, n + 1);
      pr[n] = lv;
      tx[n] = "NY open " + Dts(lv) + " " + ((kb >= 0) ? "KEMBALI " + ::GP_LocalTime(g5[kb].time)
              : (!armed ? "dekat" : (li.open ? "belum " + PStrD(MathAbs(lv - li.cur) / d.adr, li.hoursLeft) : "tidak kembali")));
      cl[n] = DMInpNYOpenColor;
      n++;
     }
   ArrayResize(pr, n + 1); ArrayResize(tx, n + 1); ArrayResize(cl, n + 1);
   pr[n] = li.cur;
   tx[n] = ">> HARGA " + Dts(li.cur) + " <<";
   cl[n] = clrGold;
   n++;
   for(int i = 0; i < n - 1; i++)             // urutkan dari harga tertinggi
      for(int j = 0; j < n - 1 - i; j++)
         if(pr[j] < pr[j + 1])
           {
            double tp = pr[j]; pr[j] = pr[j + 1]; pr[j + 1] = tp;
            string ts = tx[j]; tx[j] = tx[j + 1]; tx[j + 1] = ts;
            color  tc = cl[j]; cl[j] = cl[j + 1]; cl[j + 1] = tc;
           }
   for(int i = 0; i < n; i++)
      AddLine(L, K, tx[i], cl[i]);
  }

string DayLbl(datetime t)
  {
   MqlDateTime m;
   TimeToStruct(t, m);
   string dn[7] = {"Min", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab"};
   return StringFormat("%s %02d/%02d", dn[m.day_of_week], m.day, m.mon);
  }

//--- alert straddle: siap pasang (menit ke-5), terisi (batalkan lawan), hasil
void StraddleAlerts(const DayInfo &d)
  {
   if(!DMInpShowStraddle || !::InpGPAlertStraddle) return;
   LiveInfo li;
   GetLive(d, li);
   Straddle s;
   CalcStraddle(d, li.last, s);
   if(!s.valid || s.skipped) return;
   string day = TimeToString(d.t0, TIME_DATE);
   double lot = LotFor(s.risk);
   string lt = (lot >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) ? StringFormat(" lot %.2f", lot) : " (cek lot/risiko)";
   ::GP_Notify("sdready" + day, StringFormat("PASANG straddle: BUY STOP %s / SELL STOP %s, SL EQ %s, TP %s / %s%s",
               Dts(s.up), Dts(s.dn), Dts(s.sl), Dts(s.tpU), Dts(s.tpD), lt), g5[d.i0 + 1].time);
   if(s.side != 0)
      ::GP_Notify("sdfill" + day, StringFormat("%s STOP terisi di %s -> BATALKAN %s STOP. SL %s TP %s",
                  s.side > 0 ? "BUY" : "SELL", Dts(s.side > 0 ? s.up : s.dn), s.side > 0 ? "SELL" : "BUY",
                  Dts(s.sl), Dts(s.side > 0 ? s.tpU : s.tpD)), g5[s.kFill].time);
   if(s.result == 1 || s.result == 2)
      ::GP_Notify("sdres" + day, StringFormat("straddle %s %s", s.side > 0 ? "BUY" : "SELL", s.result == 1 ? "kena TP" : "kena SL"),
                  g5[s.kExit].time);
  }

string SdShort(const Straddle &s)
  {
   if(!s.valid)    return "Status: tunggu menit ke-5";
   if(s.skipped)   return "Status: DILEWATI";
   if(s.side == 0) return "Status: order menunggu";
   string sd = (s.side > 0) ? "BUY" : "SELL";
   if(s.result == 1) return sd + StringFormat(" kena TP +%.1fR", s.R);
   if(s.result == 2) return sd + " kena SL -1R";
   if(s.result == 3) return sd + StringFormat(" tutup hari %+.2fR", s.R);
   return sd + " AKTIF - batalkan lawan";
  }

void AddLine(string &L[], color &K[], string s, color c)
  {
   int n = ArraySize(L);
   ArrayResize(L, n + 1);
   ArrayResize(K, n + 1);
   L[n] = s;
   K[n] = c;
  }

//+------------------------------------------------------------------+
//| KARTU INFO kotak "i" (14 Okt 2026)                                |
//+------------------------------------------------------------------+
//--- PETA ARAH di zona SMC (research\smc_peta.py, 14 Okt 2026: M5 & M15 2017-26, sentuhan pertama zona replika GoldPro; BALIK = harga
//    1 ATR menjauh searah hormat sebelum TEMBUS 1 ATR di luar tepi jauh). Angka stabil 2017-21 vs 2022-26 (+-1-2 poin), TAPI zona /
//    garis sembarang memberi angka sama (+-1) -> yang menentukan = POSISI CLOSE candle terhadap garis, bukan zona SMC. Jam sinkron:
//    tidak ada (17 / 787 sel = kebetulan 19.8). Dagang (SL tepi jauh + 0.1 ATR, TP 1.5R) rugi spread, zona asli = palsu.
//    [0] OB / Breaker, [1] FVG: colek-tolak, close di dalam, (cadangan), 1 close di luar = sungguhan, 2 close = sungguhan, pin bar, engulfing
int SMC_PA[2][7] = {{80, 58, 25, 79, 83, 81, 87}, {73, 54, 31, 71, 77, 73, 81}};
//    14 Okt 2026 (research\m1_cek.py -> smc_peta_m1.txt, ~4 jt sentuhan M1, 17-21 / 22-26 selisih <= 1.5): chart M1 memakai angka M1
int SMC_PA1[2][7] = {{79, 59, 26, 77, 81, 79, 85}, {72, 54, 31, 71, 76, 72, 79}};
struct SZone { double hi, lo; bool bull; int grp; string name; };
int SmcZones(SZone &z[])
  {
   ArrayResize(z, 0);
   for(int i = 0; i < ::GetOBCount(); i++)
     {
      OrderBlock ob;
      if(!::GetOB(i, ob) || ob.status == ZONE_MITIGATED || ob.status == ZONE_INVALIDATED || ob.high <= ob.low) continue;
      int n = ArraySize(z); ArrayResize(z, n + 1);
      z[n].hi = ob.high; z[n].lo = ob.low; z[n].bull = ob.isBullish; z[n].grp = 0; z[n].name = ::POITypeText(ob);
     }
   for(int i = 0; i < ::GetFVGCount(); i++)
     {
      FVGZone fz;
      if(!::GetFVG(i, fz) || fz.status == ZONE_MITIGATED || fz.status == ZONE_INVALIDATED || fz.top <= fz.bottom) continue;
      int n = ArraySize(z); ArrayResize(z, n + 1);
      z[n].hi = fz.top; z[n].lo = fz.bottom; z[n].bull = fz.isBullish; z[n].grp = 1; z[n].name = fz.isBullish ? "Bullish FVG" : "Bearish FVG";
     }
   return ArraySize(z);
  }
double ChartATR14()
  {
   double s = 0; int c = 0;
   for(int i = 1; i <= 14; i++)
     {
      double h = iHigh(_Symbol, PERIOD_CURRENT, i), l = iLow(_Symbol, PERIOD_CURRENT, i), pc = iClose(_Symbol, PERIOD_CURRENT, i + 1);
      if(h <= 0 || l <= 0 || pc <= 0) continue;
      s += MathMax(h - l, MathMax(MathAbs(h - pc), MathAbs(l - pc))); c++;
     }
   return (c > 0) ? s / c : 0;
  }
void InfoSMC(string &L[], color &K[])
  {
   color W = DMInpPanelColor, G = clrSilver;
   int PA[2][7];
   for(int a = 0; a < 2; a++) for(int b = 0; b < 7; b++) PA[a][b] = (_Period == PERIOD_M1) ? SMC_PA1[a][b] : SMC_PA[a][b];
   string paTf = (_Period == PERIOD_M1) ? "M1" : "M5/M15";
   BiasState bs = ::GetBiasState();
   MarketConditionState mc = ::GetMarketCondition();
   AddLine(L, K, "SMC INFO  (gambar = tombol SMC)", clrGold);
   AddLine(L, K, StringFormat("Bias H4 %s | H1 %s | M5 %s", BiasTxt(bs.htfBias), BiasTxt(bs.mtfBias), BiasTxt(bs.ltfBias)), G);
   AddLine(L, K, StringFormat("Kondisi %s", mc.condition == CONDITION_TRENDING ? "trending" : (mc.condition == CONDITION_RANGING ? "ranging" : "compressed")), G);
   SZone z[];
   int nz = SmcZones(z);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), atr = ChartATR14();
   int ia = -1, ib = -1, ii = -1;
   double da = DBL_MAX, db = DBL_MAX;
   for(int i = 0; i < nz; i++)
     {
      if(z[i].lo > bid && !z[i].bull && z[i].lo - bid < da) { da = z[i].lo - bid; ia = i; }
      if(z[i].hi < bid && z[i].bull && bid - z[i].hi < db) { db = bid - z[i].hi; ib = i; }
      if(z[i].lo <= bid && z[i].hi >= bid) ii = i;
     }
   AddLine(L, K, "-- ZONA TERDEKAT (belum termitigasi) --", clrLimeGreen);
   if(ii >= 0) AddLine(L, K, StringFormat("DI DALAM %s %s-%s", z[ii].name, Dts(z[ii].lo), Dts(z[ii].hi)), clrYellow);
   if(ia >= 0) AddLine(L, K, StringFormat("ATAS  %s %s-%s (+$%.2f)", z[ia].name, Dts(z[ia].lo), Dts(z[ia].hi), da), DMInpUpColor);
   else        AddLine(L, K, "ATAS  tidak ada zona supply aktif", G);
   if(ib >= 0) AddLine(L, K, StringFormat("BAWAH %s %s-%s (-$%.2f)", z[ib].name, Dts(z[ib].lo), Dts(z[ib].hi), db), DMInpDnColor);
   else        AddLine(L, K, "BAWAH tidak ada zona demand aktif", G);
   //--- BACA CANDLE terakhir yang sudah tutup di zona yang disentuhnya
   string tfn = StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7);
   double o1 = iOpen(_Symbol, PERIOD_CURRENT, 1), h1 = iHigh(_Symbol, PERIOD_CURRENT, 1), l1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1), o2 = iOpen(_Symbol, PERIOD_CURRENT, 2), c2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   int it = -1;
   double best = DBL_MAX;
   for(int i = 0; i < nz; i++)
      if(h1 >= z[i].lo && l1 <= z[i].hi && MathAbs(c1 - (z[i].hi + z[i].lo) / 2) < best) { best = MathAbs(c1 - (z[i].hi + z[i].lo) / 2); it = i; }
   AddLine(L, K, StringFormat("-- CANDLE %s TERAKHIR DI ZONA --", tfn), clrLimeGreen);
   if(it < 0 || atr <= 0)
      AddLine(L, K, "belum ada candle yang menyentuh zona aktif", G);
   else
     {
      int s = z[it].bull ? 1 : -1, g = z[it].grp;
      double prox = (s > 0) ? z[it].hi : z[it].lo, far = (s > 0) ? z[it].lo : z[it].hi;
      string hor = (s > 0) ? "BALIK NAIK" : "BALIK TURUN", tem = (s > 0) ? "TEMBUS TURUN" : "TEMBUS NAIK";
      AddLine(L, K, StringFormat("%s %s-%s (candle %s)", z[it].name, Dts(z[it].lo), Dts(z[it].hi),
                                 ::GP_LocalTime(iTime(_Symbol, PERIOD_CURRENT, 1))), W);
      //--- 14 Okt 2026 (screenshot: kartu masih "BALIK NAIK 80%" padahal candle berjalan sudah jatuh $4 di bawah batas tembus):
      //    candle BERJALAN dicek dulu -> bila batas tembus / target balik sudah tersentuh, hasilnya ditulis & angka lama tidak berlaku
      double lvB = prox + s * atr, lvT = far - s * atr;
      double h0 = iHigh(_Symbol, PERIOD_CURRENT, 0), l0 = iLow(_Symbol, PERIOD_CURRENT, 0);
      bool hitT = (s > 0) ? (l0 > 0 && l0 <= lvT) : (h0 >= lvT);
      bool hitB = (s > 0) ? (h0 >= lvB) : (l0 > 0 && l0 <= lvB);
      if(hitT || hitB)
        {
         AddLine(L, K, hitT ? StringFormat("LIVE: SUDAH %s lewat %s - angka di bawah", tem, Dts(lvT))
                            : StringFormat("LIVE: SUDAH %s ke %s - angka di bawah", hor, Dts(lvB)), hitT ? clrTomato : clrLime);
         AddLine(L, K, "  untuk candle tutup tadi, sekarang SELESAI", hitT ? clrTomato : clrLime);
         AddLine(L, K, StringFormat("balik = %s (1 ATR) | tembus = %s", Dts(lvB), Dts(lvT)), G);
         AddLine(L, K, "-- PETA ARAH di zona (uji 2017-26 " + paTf + ") --", clrLimeGreen);
         AddLine(L, K, "                       OB/Brk  FVG", G);
         AddLine(L, K, StringFormat("colek -> close balik    %3d%%  %3d%%  balik", PA[0][0], PA[1][0]), W);
         AddLine(L, K, StringFormat("close di dalam zona     %3d%%  %3d%%  balik", PA[0][1], PA[1][1]), W);
         AddLine(L, K, StringFormat("1 close di luar         %3d%%  %3d%%  tembus", PA[0][3], PA[1][3]), W);
         AddLine(L, K, StringFormat("2 close di luar         %3d%%  %3d%%  tembus", PA[0][4], PA[1][4]), W);
         AddLine(L, K, "angka = peluang, bukan kepastian: 80% = 1 dari 5 gagal", G);
         AddLine(L, K, "garis SEMBARANG = angka sama (+-1). INFO, bukan sinyal.", G);
         return;
        }
      if(s * (bid - far) < 0)
         AddLine(L, K, StringFormat("LIVE: di luar tepi jauh, bila close -> %s %d%%", tem, PA[g][3]), clrOrange);
      double rg = h1 - l1;
      bool pin = rg > 0 && ((s > 0) ? (MathMin(o1, c1) - l1 >= 0.6 * rg && (c1 - l1) / rg >= 0.6) : (h1 - MathMax(o1, c1) >= 0.6 * rg && (h1 - c1) / rg >= 0.6));
      bool eng = (s > 0) ? (c1 > o1 && o1 <= MathMin(o2, c2) && c1 >= MathMax(o2, c2)) : (c1 < o1 && o1 >= MathMax(o2, c2) && c1 <= MathMin(o2, c2));
      if(s * (c1 - far) < 0 && s * (c2 - far) < 0)
         AddLine(L, K, StringFormat("2 close di luar tepi jauh -> %s %d%%", tem, PA[g][4]), clrTomato);
      else if(s * (c1 - far) < 0)
         AddLine(L, K, StringFormat("close di luar tepi jauh -> %s %d%%", tem, PA[g][3]), clrTomato);
      else if(s * (c1 - prox) > 0)
        {
         AddLine(L, K, StringFormat("colek lalu close balik -> %s %d%%", hor, PA[g][0]), clrLime);
         if(pin) AddLine(L, K, StringFormat("+ pin bar tolak -> %s %d%%", hor, PA[g][5]), clrLime);
         if(eng) AddLine(L, K, StringFormat("+ engulfing -> %s %d%%", hor, PA[g][6]), clrLime);
        }
      else
         AddLine(L, K, StringFormat("close DI DALAM zona -> %s %d%% (hampir koin)", hor, PA[g][1]), clrYellow);
      AddLine(L, K, StringFormat("balik = %s (1 ATR) | tembus = %s", Dts(lvB), Dts(lvT)), W);
      AddLine(L, K, "LIVE: belum ada yang tersentuh - masih berlaku", G);
     }
   AddLine(L, K, "-- PETA ARAH di zona (uji 2017-26 " + paTf + ") --", clrLimeGreen);
   AddLine(L, K, "                       OB/Brk  FVG", G);
   AddLine(L, K, StringFormat("colek -> close balik    %3d%%  %3d%%  balik", PA[0][0], PA[1][0]), W);
   AddLine(L, K, StringFormat("pin bar tolak           %3d%%  %3d%%  balik", PA[0][5], PA[1][5]), W);
   AddLine(L, K, StringFormat("engulfing hormat        %3d%%  %3d%%  balik", PA[0][6], PA[1][6]), W);
   AddLine(L, K, StringFormat("close di dalam zona     %3d%%  %3d%%  balik", PA[0][1], PA[1][1]), W);
   AddLine(L, K, StringFormat("1 close di luar         %3d%%  %3d%%  tembus", PA[0][3], PA[1][3]), W);
   AddLine(L, K, StringFormat("2 close di luar         %3d%%  %3d%%  tembus", PA[0][4], PA[1][4]), W);
   AddLine(L, K, "balik = 1 ATR menjauh dulu sebelum tembus 1 ATR", G);
   AddLine(L, K, "garis SEMBARANG = angka sama (+-1): yang menentukan", G);
   AddLine(L, K, "posisi CLOSE, bukan zona. Jam sinkron: tidak ada.", G);
   AddLine(L, K, "Dagang (SL tepi jauh, TP 1.5R) = rugi spread. INFO.", G);
  }
void InfoTarget(string &L[], color &K[])
  {
   DayInfo d = g_days[g_nd - 1];
   LiveInfo li;
   GetLive(d, li);
   color W = DMInpPanelColor, G = clrSilver;
   AddLine(L, K, "TARGET T0-T4  (garis = tombol Target)", clrGold);
   AddLine(L, K, StringFormat("Open %s | ADR %.2f | 1 tingkat $%.2f", Dts(d.open), d.adr, 0.25 * d.adr), W);
   AddLine(L, K, "-- % hari tersentuh [KOKOH] searah/lawan jam-1 --", clrLimeGreen);
   AddLine(L, K, StringFormat("T1 %.0f/%.0f   T2 %.0f/%.0f", Pct(st_hitS[0], st_days), Pct(st_hitO[0], st_days),
                              Pct(st_hitS[1], st_days), Pct(st_hitO[1], st_days)), W);
   AddLine(L, K, StringFormat("T3 %.0f/%.0f   T4 %.0f/%.0f", Pct(st_hitS[2], st_days), Pct(st_hitO[2], st_days),
                              Pct(st_hitS[3], st_days), Pct(st_hitO[3], st_days)), W);
   double h1 = -DBL_MAX, l1 = DBL_MAX;
   for(int k = d.i0; k <= li.last && k < d.i1; k++) { h1 = MathMax(h1, g5[k].high); l1 = MathMin(l1, g5[k].low); }
   bool u1 = h1 >= d.open + LV[0] * d.adr, d1 = l1 <= d.open - LV[0] * d.adr;
   AddLine(L, K, StringFormat("T1 salah satu %.0f dua2 %.0f %s", Pct(st_any1, st_days), Pct(st_both1, st_days),
                              (u1 && d1) ? "[dua2]" : (u1 ? "[atas]" : (d1 ? "[bawah]" : "[belum]"))), (u1 || d1) ? clrLimeGreen : W);
   if(li.open)
     {
      AddLine(L, K, "-- LIVE (duluan | s/d tutup) --", clrLimeGreen);
      AddLine(L, K, StringFormat("Atas  %s %s|%s", Dts(li.lvlUp), PStr(li.pUpFirst), PStr(li.pUpClose)), DMInpUpColor);
      AddLine(L, K, StringFormat("Bawah %s %s|%s", Dts(li.lvlDn), PStr(1.0 - li.pUpFirst), PStr(li.pDnClose)), DMInpDnColor);
     }
   else
      AddLine(L, K, "Market tutup", G);
   TargetLines(d, li, L, K);
   AddLine(L, K, "INFO peluang (uji 2017-26), bukan sinyal arah", G);
  }
void InfoBackup(string &L[], color &K[])
  {
   DayInfo d = g_days[g_nd - 1];
   LiveInfo li;
   GetLive(d, li);
   color W = DMInpPanelColor, G = clrSilver;
   double thr = BackupThr();
   AddLine(L, K, StringFormat("GARIS CADANGAN Cad%d  (garis = tombol Cad)", (int)MathRound(thr * 100)), clrGold);
   AddLine(L, K, StringFormat("= harga yang >= %d%% TERSENTUH sebelum tutup", (int)MathRound(thr * 100)), W);
   if(li.open)
     {
      double bd = LiveInv(thr, li.hoursLeft);
      if(bd > 0)
        {
         AddLine(L, K, StringFormat("Atas  %s (+$%.2f)", Dts(li.cur + bd * d.adr), bd * d.adr), DMInpBackupColor);
         AddLine(L, K, StringFormat("Bawah %s (-$%.2f)", Dts(li.cur - bd * d.adr), bd * d.adr), DMInpBackupColor);
         AddLine(L, K, StringFormat("sisa %.1f jam: makin sore, garis makin dekat", li.hoursLeft), G);
        }
      else
         AddLine(L, K, "sisa < 1 jam: garis tidak dihitung", G);
     }
   else
      AddLine(L, K, "Market tutup", G);
   AddLine(L, K, "tabel live 2017-26: tepat +-1.5 poin tiap tahun", G);
   AddLine(L, K, "pakai: batas wajar gerak / TP aman hari ini", G);
   AddLine(L, K, "atas & bawah dihitung terpisah = bukan arah", G);
  }
void InfoLines(string k, string &L[], color &K[])
  {
   color W = DMInpPanelColor, G = clrSilver;
   if(k == "smc") { InfoSMC(L, K); return; }
   if(k == "wave") { ::WV_InfoLines(L, K); return; }
   if(k == "simple")
     {
      AddLine(L, K, "MODE TERUJI - satu klik, hanya yang teruji", clrGold);
      AddLine(L, K, StringFormat("status: %s", g_vSimple ? "ON" : "OFF (klik tombol Mode Teruji)"), g_vSimple ? clrLime : G);
      AddLine(L, K, "NYALA: Target T0-T4 & Cadangan [KOKOH tiap th]", W);
      AddLine(L, K, "       Gelombang (peluang tepat, = jarak)", W);
      AddLine(L, K, "       Tembus Balik + JAM BAGUS (06:10 WITA)", W);
      AddLine(L, K, "MATI : kotak SMC lama (OB / Premium / OTE ...)", W);
      AddLine(L, K, "       = zona acak di uji 2017-26", G);
      AddLine(L, K, "tidak diubah: Probe, Berita, Kotak Sideway, PIN", G);
      AddLine(L, K, "klik lagi = kembali ke pilihan sebelumnya", G);
      return;
     }
   if(k == "target") { InfoTarget(L, K); return; }
   if(k == "backup") { InfoBackup(L, K); return; }
   if(k == "page1")
     {
      AddLine(L, K, "PANEL 1 PETA - cara baca", clrGold);
      AddLine(L, K, "TARGET [KOKOH]: % hari T1-T4 tersentuh", W);
      AddLine(L, K, "  (searah / lawan arah jam pertama)", G);
      AddLine(L, K, "RUTE HARGA: garis yang paling mungkin disentuh", W);
      AddLine(L, K, "LIVE Atas / Bawah: peluang duluan | s/d tutup", W);
      AddLine(L, K, "EQ, NY, PDH / PDL: peluang tersentuh s/d tutup", W);
      AddLine(L, K, "Cad = garis cadangan, TAHAN = bertahan di luar", W);
      AddLine(L, K, "PULLBACK LEG: puncak / lembah baru (M5, M15)", W);
      AddLine(L, K, "TANGGA TARGET: target berikut + cek akurasi", W);
      AddLine(L, K, "SMC [INFO] & SESI: konteks, bukan sinyal", W);
      AddLine(L, K, "[KOKOH] = tepat di uji 2017-26 setiap tahun", G);
      return;
     }
   if(k == "page5")
     {
      AddLine(L, K, "PANEL 2 CEK SIAP - cara baca", clrGold);
      AddLine(L, K, "Cek KONDISI scalping, BUKAN arah:", W);
      AddLine(L, K, "biaya: spread + slip dibanding gerak 15 mnt", W);
      AddLine(L, K, "gerak: pasar cukup bergerak untuk TP?", W);
      AddLine(L, K, "lokasi: harga dekat garis (T / EQ)?", W);
      AddLine(L, K, "berita: tidak ada rilis penting dekat", W);
      AddLine(L, K, "disiplin: aturan pengawal trading", W);
      AddLine(L, K, "SIAP = semua OK | TUNGGU = ada yang belum", W);
      AddLine(L, K, "JAM BIAYA: MURAH / MAHAL + menang minimum impas", W);
      AddLine(L, K, "arah tetap ~50/50 di semua uji", G);
      return;
     }
   if(k == "probe")
     {
      AddLine(L, K, "PROBE - arahkan mouse ke harga", clrGold);
      AddLine(L, K, StringFormat("status: %s", g_vProbe ? "AKTIF" : "mati (klik tombol Probe)"), W);
      AddLine(L, K, "kotak kecil: harga | jarak $ & ADR | peluang", W);
      AddLine(L, K, "= harga itu TERSENTUH sebelum hari tutup", W);
      AddLine(L, K, "tabel live 2017-26, tepat +-1.5 poin tiap tahun", G);
      AddLine(L, K, "makin jauh / makin sore = peluang makin kecil", G);
      AddLine(L, K, "atas & bawah terpisah = bukan arah", G);
      return;
     }
   if(k == "pin")
     {
      AddLine(L, K, "PIN - garis harga pilihan Anda", clrGold);
      int np = ArraySize(g_pins);
      if(np == 0) AddLine(L, K, "belum ada PIN: tekan +PIN, lalu klik harga", G);
      for(int i = 0; i < np && i < 10; i++) AddLine(L, K, PinText(g_pins[i], true), DMInpPinColor);
      AddLine(L, K, "PIN bisa digeser; alert saat tersentuh", G);
      AddLine(L, K, "peluang = tabel live yang sama dengan Probe", G);
      AddLine(L, K, "hapus: tombol Hapus PIN / pilih PIN + Delete", G);
      return;
     }
   if(k == "trade")
     {
      bool ea = (ChartGetString(0, CHART_EXPERT_NAME) == "GoldPro_Panel");
      AddLine(L, K, "TRADE - panel EA GoldPro_Panel", clrGold);
      AddLine(L, K, StringFormat("EA di chart ini: %s", ea ? "TERPASANG" : "BELUM (Navigator > Experts)"), ea ? clrLime : clrTomato);
      AddLine(L, K, "panel order + PENGAWAL DISIPLIN", W);
      AddLine(L, K, "tanda '!' di kanan tombol = peringatan pengawal", W);
      AddLine(L, K, "klik Trade = tampil / sembunyi panel", W);
      AddLine(L, K, "order hanya dari klik Anda", G);
      return;
     }
   if(k == "saldo")
     {
      string ac = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
      int ss = SaldoState();
      double pct = GlobalVariableCheck("GP_SD_PCT_" + ac) ? GlobalVariableGet("GP_SD_PCT_" + ac) : 7.0;
      AddLine(L, K, "SALDO & TARGET HARIAN (EA GoldPro_Panel)", clrGold);
      AddLine(L, K, StringFormat("status: %s", ss == 2 ? "TERKUNCI s/d 05:00 WITA" : (ss == 1 ? "ON" : "OFF")),
              ss == 2 ? clrTomato : (ss == 1 ? clrLime : G));
      AddLine(L, K, StringFormat("saldo $%.2f | target %.1f%% / hari", AccountInfoDouble(ACCOUNT_BALANCE), pct), W);
      AddLine(L, K, "target = % x saldo awal hari (05:00 WITA)", W);
      AddLine(L, K, "saldo awal = saldo - hasil tertutup hari ini", W);
      AddLine(L, K, "setoran / tarikan bukan profit", G);
      AddLine(L, K, "ON + tercapai -> order baru ditolak s/d besok", W);
      AddLine(L, K, "posisi dibuka SEBELUM kunci tidak disentuh", G);
      return;
     }
  }
int InfoRow(string k)
  {
   if(k == "page1") return 0;
   if(k == "page5") return 1;
   if(k == "target") return 2;
   if(k == "backup") return 3;
   if(k == "smc") return 4;
   if(k == "probe") return 5;
   if(k == "pin") return 6;
   if(k == "trade") return BTN_TRADE;
   if(k == "saldo") return BTN_SALDO;
   if(k == "wave") return 13;
   if(k == "simple") return 14;
   return 0;
  }
//--- gambar kartu info di samping tombolnya; tidak menimpa panel halaman / panel Trade / dashboard Kotak, Tembus Balik, Saldo
void InfoCard()
  {
   string pre = PFX + "IC_";
   g_infW = 0; g_infH = 0;
   if(g_infoKey == "" || !DMInpButtons || g_nd <= 0)
     {
      if(ObjectFind(0, pre + "bg") >= 0) ObjectsDeleteAll(0, pre);
      return;
     }
   string L[];
   color  K[];
   InfoLines(g_infoKey, L, K);
   int n = ArraySize(L);
   if(n == 0) { ObjectsDeleteAll(0, pre); return; }
   int fs = 8, lh = 14, w = 0;
   for(int i = 0; i < n; i++) w = MathMax(w, StringLen(L[i]));
   w = (int)(w * 6.3) + 14;
   int h = n * lh + 8, ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   int ymin = PanelTop() + BTN_H + 8;                                      // di bawah label LIVE (kanan tombol baris 1)
   int y0 = MathMax(ymin, PanelTop() + InfoRow(g_infoKey) * (BTN_H + 2)), x0 = BtnColR() + 8;
   if(ch > 100 && y0 + h > ch - 4) y0 = MathMax(ymin, ch - 4 - h);
   string bgs[4];
   bgs[0] = PFX + "Pbg"; bgs[1] = "GPK_BG"; bgs[2] = "GPI_BG"; bgs[3] = "GPD_BG";
   string cid = IntegerToString(ChartID());
   for(int pass = 0; pass < 2; pass++)
     {
      for(int k = 0; k < 4; k++)
        {
         if(ObjectFind(0, bgs[k]) < 0) continue;
         int bx = (int)ObjectGetInteger(0, bgs[k], OBJPROP_XDISTANCE), by = (int)ObjectGetInteger(0, bgs[k], OBJPROP_YDISTANCE);
         int bw = (int)ObjectGetInteger(0, bgs[k], OBJPROP_XSIZE), bh = (int)ObjectGetInteger(0, bgs[k], OBJPROP_YSIZE);
         if(by < y0 + h && by + bh > y0 - 4 && bx < x0 + w && bx + bw > x0 - 4) x0 = bx + bw + 8;
        }
      if(g_vTrade && GlobalVariableCheck("GP_EAPW_" + cid) && GlobalVariableGet("GP_EAPH_" + cid) > 0)
        {
         int ex = BtnColR() + 6, ey = PanelTop() + BTN_H + 8;
         int ew = (int)GlobalVariableGet("GP_EAPW_" + cid), eh = (int)GlobalVariableGet("GP_EAPH_" + cid);
         if(ey < y0 + h && ey + eh > y0 - 4 && ex < x0 + w && ex + ew > x0 - 4) x0 = ex + ew + 10;
        }
     }
   string bg = pre + "bg";
   if(ObjectFind(0, bg) < 0)
     {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, bg, OBJPROP_ZORDER, 23);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'18,26,40');
      ObjectSetString(0, bg, OBJPROP_TOOLTIP, "Kartu INFO GoldPro - klik judul untuk menutup");
     }
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x0 - 4);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y0 - 4);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, w + 2);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, C'200,170,60');
   for(int i = 0; i < n; i++)
     {
      string nm = pre + "L" + IntegerToString(i);
      if(ObjectFind(0, nm) < 0)
        {
         ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, nm, OBJPROP_ZORDER, 24);
         ObjectSetString(0, nm, OBJPROP_FONT, "Consolas");
        }
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x0 + 2);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y0 + i * lh);
      ObjectSetString(0, nm, OBJPROP_TEXT, StringSubstr(L[i], 0, 62) == "" ? " " : StringSubstr(L[i], 0, 62));
      ObjectSetInteger(0, nm, OBJPROP_COLOR, K[i]);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, fs);
      ObjectSetString(0, nm, OBJPROP_TOOLTIP, i == 0 ? "klik = tutup kartu info" : "\n");
     }
   for(int i = n; ObjectFind(0, pre + "L" + IntegerToString(i)) >= 0; i++)
      ObjectDelete(0, pre + "L" + IntegerToString(i));
   g_infX = x0 - 4; g_infY = y0 - 4; g_infW = w + 2; g_infH = h;
  }

//+------------------------------------------------------------------+
//| Helper objek                                                      |
//+------------------------------------------------------------------+
void Common(string n, color c)
  {
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
  }

void Rect(string n, datetime t1, double p1, datetime t2, double p2, color c)
  {
   ObjectCreate(0, n, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   Common(n, c);
   ObjectSetInteger(0, n, OBJPROP_FILL, true);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
  }

void HLine(string n, datetime t1, datetime t2, double p, color c, ENUM_LINE_STYLE st, int w)
  {
   ObjectCreate(0, n, OBJ_TREND, 0, t1, p, t2, p);
   Common(n, c);
   ObjectSetInteger(0, n, OBJPROP_STYLE, st);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
  }

void ALine(string n, datetime t1, double p1, datetime t2, double p2, color c)
  {
   ObjectCreate(0, n, OBJ_ARROWED_LINE, 0, t1, p1, t2, p2);
   Common(n, c);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, 2);
  }

void Text(string n, datetime t, double p, string s, color c, ENUM_ANCHOR_POINT a)
  {
   ObjectCreate(0, n, OBJ_TEXT, 0, t, p);
   Common(n, c);
   ObjectSetString(0, n, OBJPROP_TEXT, s);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, a);
  }

void Arrow(string n, datetime t, double p, int code, color c)
  {
   ObjectCreate(0, n, OBJ_ARROW, 0, t, p);
   Common(n, c);
   ObjectSetInteger(0, n, OBJPROP_ARROWCODE, code);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, 2);
  }

void Label(string n, int x, int y, string s, color c)
  {
   ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   Common(n, c);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, n, OBJPROP_TEXT, s);
   ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 9);
  }
//+------------------------------------------------------------------+
}

#endif
