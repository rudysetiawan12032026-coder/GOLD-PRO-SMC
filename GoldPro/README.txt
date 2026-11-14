GOLDPRO SYSTEM - XAUUSD
=======================
Indikator utama : GoldPro_Main.mq5
Asal            : modul SMC_Pro_System (disalin & diperbaiki) + GoldDayMap (modul Map\GP_DayMap.mqh)
SMC_Pro_System  : TIDAK disentuh, tetap bisa dipakai sendiri.
GoldDayMap.mq5  : versi standalone dibekukan; pengembangan peta harian dilanjutkan di Map\GP_DayMap.mqh.

STRUKTUR
  Core\       Types, Config (semua input), Utils, GP_Time (konversi waktu + DST)
  Detection\  Structure (BOS/CHoCH), Zones, POI (OB/FVG/Breaker), Liquidity, MarketCondition, SupplyDemand
  Analysis\   Session, AMD, NewsFilter, MTF, Scoring, Stats, MultiTFEntry
  Narrative\  teks narasi
  Render\     ObjectPool + render struktur/POI/likuiditas/S&D/dashboard
  Signal\     SignalExport (JSON + Global Variable), Alert
  Map\        GP_DayMap: pita open/EQ, target ADR, peluang live, straddle EQ, rencana entry, jurnal forward test

PERBAIKAN DARI SMC_Pro_System (Tahap 1, 26 Sep 2026)
  1. Sesi/killzone: SMC membaca jam server mentah (input GMT offset tidak dipakai, DST diabaikan)
     -> "London" & "NY" meleset ~4 jam, AMD/Judas/killzone ikut salah.
     GoldPro: sesi dalam jam LOKAL bursa (Asia & NY = jam New York, London = jam London),
     konversi otomatis ikut DST AS & Inggris (Core\GP_Time.mqh). Diverifikasi di tanggal kritis.
  2. Statistik: SMC menulis CSV dengan FileWrite() pada FILE_TXT (tanpa pemisah) tapi membaca
     dengan koma -> histori hilang tiap restart (patternStats selalu null).
     GoldPro: ditulis dengan koma eksplisit, file GoldPro_Stats.csv.
  3. Ekspor sinyal: SMC memakai "PERIOD_CURRENT" di nama file & Global Variable -> beberapa chart
     saling menimpa. GoldPro: GoldPro_Signal_<SIMBOL>_<TF>.json dan GV GP_GV_<SIMBOL>_<TF>_*.
  4. Prefix sendiri (objek GP_, peta harian GPM_, GV GP_GV_) -> bisa jalan berdampingan dengan
     SMC_Main dan GoldDayMap standalone. Panel peta harian otomatis di bawah dashboard SMC.
  Jurnal forward test (MQL5\Files\GoldDayMap\) dipakai bersama GoldDayMap standalone;
  kunci GDM_JOURNAL_<SIMBOL> memastikan hanya satu yang menulis.

TAHAPAN
  [selesai] Tahap 1 - Fondasi (di atas)
  [selesai] Tahap 2 - Mesin validasi (26 Sep 2026): Experts\GoldPro\GoldPro_Validator.mq5 di Strategy
               Tester (XAUUSD M5, 2025.09.25-2026.09.25, open prices) -> 70.592 candle, 10.025 kejadian.
               Hasil (M1, spread asli, 3 periode):
                 - Bias HTF/MTF/LTF/ext/int: tepat arah 48-53% (1 & 4 jam) -> TIDAK prediktif.
                 - BOS/CHoCH: capai +1 ATR duluan 47-54% -> tidak ada kelanjutan istimewa.
                 - Sweep BSL/SSL: pembalikan 47-50% -> TIDAK terbukti.
                 - ENTRY OK (skor>=80): 83 candle/tahun, hasil negatif di 3 periode.
                 - Skor total tidak memprediksi hasil. Komponen Structure & LTF Confirm NEGATIF
                   konsisten; Zone (premium/discount) POSITIF konsisten; POI Quality positif 2/3.
                 - Kandidat: rekomendasi entry dengan Zone>=70 & POI>=80: +0.04/+0.61/+0.21R
                   (dipilih setelah melihat data -> wajib forward test).
               Filter berita straddle: kalender MT5 tidak tersedia di tester -> diuji terpisah (belum).
  [selesai] Tahap 2b - Gaya SMC mana yang bagus? (22.954 POI, retest pertama, zona acak sbg pembanding)
                 - Zona SMC lebih baik dari zona acak, tapi entry klasik (SL tipis di tepi zona) RUGI:
                   OB, FVG, OB+FVG, killzone, discount/premium, searah HTF -> semua negatif 3 periode.
                 - Zona < 0.5 ATR paling buruk; SL tipis = penyebab utama kerugian.
                 - MSS (sweep -> CHoCH) tidak konsisten lebih baik dari CHoCH biasa.
                 - LOLOS: BREAKER >= 1 ATR, limit di tepi, SL zona + 0.5 ATR, TP 2R:
                   +0.25 / +0.26 / +0.24R (latih/validasi/uji); parameter tetangga juga positif.
               Diterapkan di GoldPro:
                 - Signal\GP_Precision.mqh: garis LIMIT/SL/TP setup breaker teruji + status + jurnal
                   (MQL5\Files\GoldDayMap\journal_breaker.csv, dinilai bagian 5 evaluate_journal.py).
                 - Scoring: bobot Zone 50 / POI 50 (Structure, LTF, Liquidity, MC = 0);
                   ENTRY OK = Zone>=70 & POI>=80; gerbang lama AMD/range/faktor dimatikan (input).
  [selesai] Tahap 3 - (26 Sep 2026)
                 - Tampilan bersih: objek SMC tanpa bukti disembunyikan (input "GoldPro: Tampilan chart").
                 - Panel terpadu POTRET (peta harian, straddle, breaker, live, SMC [INFO], sesi, AM Fix, jurnal);
                   label [TERUJI]/[KANDIDAT]/[INFO]; peringatan risiko nyata bila lot minimum > risiko input.
                 - Alert (Core\GP_Notify.mqh): straddle siap/terisi/hasil, breaker baru, AM Fix -5 menit,
                   blackout berita, ENTRY OK (default mati). Push HP via MetaQuotes ID. Tidak mengulang alert lama.
                 - AM Fix SELL 10:20-10:29 London (GP_AMFixStart) di panel + alert.
                 - Ekspor kalender USD 400 hari -> Common\Files\GoldPro_Calendar.csv (sekali/hari).
                 - Uji filter berita untuk straddle (1.958 event): TIDAK membantu (fill hampir selalu di Asia,
                   hari berita besar malah +0.30R di validasi/uji; lewati hari berita = total turun 18.4R->15.6R).
                   Keputusan: straddle tanpa filter berita; blackout hanya info/alert.
  [selesai] UJI MULTI-TAHUN (27 Sep 2026) - data M1 broker 2017-2025 (8.7 th, belum pernah dilihat),
               aturan DIKUNCI persis seperti riset, spread asli + slippage diskala harga:
                 Setup            2017-2025 dgn biaya   tanpa biaya   tahun positif   tahun riset
                 Straddle EQ      -0.17R                ~0            1/9             +0.13R
                 AM Fix SELL      menang 29%            5/9 thn +     0/9             menang 65%
                 Asia breakout    -0.10R                ~0            2/9             +0.12R
                 Breaker >=1 ATR  -0.43R                -0.02R        0/9             +0.25R
               => Keunggulan setup hanya muncul di tahun riset (emas naik $3.300->$4.500, volatil).
                  Di tahun normal ~0 sebelum biaya, negatif setelah biaya. BUKAN edge yang kokoh.
               YANG KOKOH (stabil tiap tahun 2016-2026):
                 - Peluang target T1/T2 searah jam-1: T1 72-80%, T2 38-48% setiap tahun.
                 - Tabel peluang live (jarak + sisa waktu): prediksi 39% vs nyata 40-42% tiap tahun,
                   29-33% lebih akurat dari tebakan rata-rata.
               Replay SMC 9 th: GoldPro_Val9y_*.csv (Common\Files), validator_9y.ini.
  [selesai] Label jujur (27 Sep 2026): straddle/breaker/AM Fix/LIMIT = [1 TH SAJA] + hasil 2017-25 di panel;
               garis setup TIDAK digambar & alertnya mati secara default (tetap dihitung + dijurnal).
               Target & peluang live = [KOKOH].
  [selesai] Riset filter rezim (27 Sep 2026): fitur ex-ante (vol relatif, ekspansi vol, ER20, tren 60h,
               MA200, rasio biaya/SL); ambang dari 2017-21, uji 2022-25 & riset -> TIDAK ADA filter yang lolos
               (kelompok terbaik pun negatif di 2017-21). Pola monoton: hasil membaik seiring vol relatif naik
               (biaya/SL turun 31% -> 4%); >2% positif utk straddle/AM Fix/Asia, tapi hampir seluruhnya 2025-26;
               periode vol tinggi lain (2020, 2022) sebagian besar rugi; breaker hanya positif di 2026.
               => HIPOTESIS rezim vol tinggi, bukan filter terbukti. Panel: "Rezim vol x% / biaya/SL".
  [selesai] Panel SINYAL [HIPOTESIS] (27 Sep 2026): straddle, breakout Asia (baru, aturan riset dikunci,
               dicek cocok dgn Python), AM Fix; "aktif" hanya saat rezim vol >= 2%, selain itu "JANGAN entry".
               Breakout Asia dijurnal (type "asia") + alert (default mati). Breaker keluar dari panel.
  [selesai] Drift per jam/sesi 2017-2026 (27 Sep 2026):
               - Jam 18:00 ET (buka pasar) naik di 10/10 tahun, sesi Asia naik 9/10 tahun (KOTOR).
               - Dengan beli di ask + slippage, jual di bid: rugi 2017-2022, positif hanya 2023-2026.
                 Drift pembukaan hampir seluruhnya di menit pertama -> kemungkinan besar efek spread.
               - Short sesi mana pun tidak pernah menguntungkan.
               => Belum ada edge intraday yang kokoh setelah biaya; yang positif selalu era 2023-26
                  (emas naik kuat + biaya relatif turun).
  [selesai] "Pijakan -> retest -> tujuan" GoldPro 2017-2025 (aturan riset dikunci, biaya asli):
               retest #2 pita -> T1: -0.21R (menang 32%, 1/9 tahun positif); pullback 61.8 -> ekstrem:
               -0.17R (0/9). Sama seperti SMC (OB CE -> likuiditas): TIDAK menguntungkan.
               Keunggulan GoldPro = bagian "tujuan" (peluang target & live terkalibrasi), bukan entry.
  [selesai] INDIKATOR SEARAH M15 + M5 + M1 (1 Okt 2026, research\mtf_scan.py <mulai> <akhir> <out>, mtf_compare.py;
            laporan mtf_1y.txt & mtf_prev.txt): 29 indikator (EMA arah/posisi/cross, EMA50, MACD x2, RSI, Stoch,
            CCI, W%R, Supertrend, PSAR, Heiken Ashi, DMI, Bollinger, Donchian, Ichimoku x2, ROC, regresi, Aroon, TRIX,
            Hull, AO, OBV tick, MFI, DeMarker, warna candle) x kombinasi M15+M5+M1 / M15+M5 / M5+M1 / M15+M1 x
            (semua menit searah / menit pertama searah) x 1/2/5/15 mnt = 928 uji per tahun. M5/M15 = candle CLOSE
            terakhir (merge_asof, tanpa intip). Pembanding = peluang dasar arah sama di periode sama (reli emas!).
               - Okt25-Sep26: edge rata2 -1.28 poin; Okt24-Sep25: -0.43 poin (korelasi antar tahun 0.45).
                 3 TF searah: rata2 -1.1 (1 mnt) .. -2.0 (15 mnt) = harga sedikit lebih sering BERBALIK.
               - Ikut searah terbaik kedua tahun hanya +0.1..+1 poin (MFI M15+M5 menit pertama 2 mnt +0.95/+0.97),
                 bersih -$0.1..-0.2/trade. Fade terkuat (Supertrend 3 TF menit pertama 15 mnt -2.9/-2.8) bersih ~0/-0.18.
               - Lolos bersih di kedua tahun: 0 (ikut) dan 0 (fade). Gerak rata2 searah sinyal $0.0-0.2 << spread ~$0.17.
               - BUG diperbaiki: Supertrend NaN awal membuat arah selalu naik (hasil pertama tidak sah).
               => Searah multi-TF TIDAK menambah ketepatan; 1-2 menit ~ acak dan habis dimakan spread.
  [selesai] SISTEM "MURNI CHART" SELAIN SMC (1 Okt 2026, research\mp_tests.py -> mp_tests.txt, pa_tests.py ->
            pa_tests.txt; 2017-2026, eksekusi M1, biaya spread + slip seperti techniques.py):
               - MARKET PROFILE aturan 80% Dalton (buka di luar VA kemarin, masuk lagi): sampai sisi VA seberang hanya
                 34-45% (bukan 80%); vs level cermin jarak sama +1..+4.6 poin, "duluan" 50-54%, net R -0.03..-0.17,
                 HARI/NY RTH, TPO/volume, sentuh/Dalton 2x30m: 0 lolos. Subkelompok jarak > 0.35 ADR (dipilih sesudah
                 lihat hasil) HARI-TPO-Dalton +0.09R (+0.13/+0.05, 7/10 th) tapi versi volume & NY tidak konsisten.
               - POC/VAH/VAL kemarin: magnet lemah POC +1.3..+1.5 poin, naked POC 2-5 hari +2.1 (7/10 th) vs open hari
                 ini +4.3 & close kemarin +4.4 (direplikasi = cek metode OK). MENTOK (pantul): semua ~0 / negatif.
               - INITIAL BALANCE (60 mnt pertama HARI / LONDON 08:00 / NY 08:20): tabel kelipatan IB (mis. NY IB besar
                 perluasan 1x hanya 12-13%), tapi model kelipatan IB (gaya Market Profile) logloss 0.5665 vs jarak/ADR
                 GoldPro 0.5137; IB relatif tidak menambah apa pun di atas jarak/ADR + rvr (0.5142 vs 0.5133).
               - AL BROOKS MEASURED MOVE (leg zigzag GoldPro, tembus puncak lagi, target Q + x*leg1, stop Q): kena =
                 GEOMETRI acak +-1 poin (x=1: 50.1 vs 50.6 M5, 50.0 vs 49.4 M15) di semua kedalaman pullback.
               - AL BROOKS H1/H2 & L1/L2 (stop di luar signal bar, TP 1R/2R): menang kotor 50-53% (H2 lebih baik dari
                 H1 hanya ~1-2 poin), R kotor -0.02..+0.08, bersih -0.24..-0.83, 0/10 th positif, 0 lolos.
               - DEMARK TD SEQUENTIAL (setup 9, 9 sempurna, countdown 13; fade 1/4/9 bar; M5/M15/H1/D1): kotor - acak
                 ~0 (+-0.03 ATR) di M5/M15/H1; D1 beli +0.14..+0.19 ATR di atas drift tapi n=31 (3/th, ~0.7 SE), jual
                 negatif. 0 lolos.
               => Tidak ada yang diadopsi sebagai sinyal. Konfirmasi: kerangka jarak/ADR + gerak hari GoldPro lebih
                  tajam daripada kerangka IB/VA Market Profile; measured move = geometri (sudah tercakup baris leg).
  [selesai] SISTEM CHART LAIN (1 Okt 2026, research\pa_tests2.py -> pa_tests2.txt; biaya = spread saja, aturan dikunci):
            614 baris uji + 8 Renko/P&F -> LOLOS 0.
               - WYCKOFF spring/upthrust (rentang 40 bar, M5/M15/H1): TP 1R kotor -0.04..-0.01R; TP seberang kotor
                 +0.02..+0.16 tapi bersih negatif. Volume RINGAN (kata teori lebih kuat) justru lebih buruk.
               - POLA KLASIK (zigzag 1.5 ATR, measure rule): H&S menang 44-46% (bukan 89% Bulkowski), kotor ~0;
                 segitiga/rectangle/wedge/broadening/flag kotor -0.13..+0.16, bersih hampir semua negatif.
                 Terbaik H1 segitiga simetris +0.04 bersih (-0.09 / +0.18) -> gagal periode 1.
               - HARMONIC: Gartley, Butterfly, Crab, ABCD negatif; Bat H1 +0.16 tapi n=36 (3.6/th).
               - CANDLESTICK lain (M5/M15/H1): kotor ~0 (+-0.05 ATR) semua. D1 Three outside DOWN (jual) tahan 3 hari
                 +0.70 ATR vs jual acak -0.13 (t 3.6) tapi n=24 dari ~600 kombinasi -> tidak signifikan (hipotesis lemah).
               - VSA (tick volume): no demand/supply, stopping volume, climax, upthrust, test -> kotor ~0, 0 lolos.
               - RENKO (0.05/0.1/0.2 ADR) & P&F (0.05/0.1 ADR): untung hanya sisi BELI (reli emas), jual negatif;
                 P&F 0.1 bersih -0.06 (17-21) / +0.44 (22-26) = drift, bukan keunggulan.
               - GANN Square of 9 (45/90 derajat dari open, grid): magnet +0.4/+1.6/-0.4 (tak konsisten), mentok ~0.
               - Elliott (gelombang 3 = 1.618 = measured move x1.618 -> geometri), Gann sudut (tergantung skala),
                 footprint (tak ada volume bid/ask) tidak diuji terpisah.
               => Dari ~2.200 uji total, sistem arah murni-chart tidak ada yang lolos. Tetap: keunggulan GoldPro =
                  peluang jarak/waktu terkalibrasi, bukan sinyal entry.
  [selesai] ANTAR-PASAR (1 Okt 2026, research\im_tests.py -> im_tests.txt; M1 XAGUSD/EURUSD/USDJPY 2017-26, US500/US100
            Nov 2020-26 dari MT5 broker, pickle di scratchpad):
               - LEAD-LAG M1: menit yang SAMA korelasi perak +69, EURUSD +32, USDJPY -32, US500/US100 +18 (x100);
                 menit BERIKUTNYA semua |r| <= 0.9 -> tidak ada pasar yang mendahului emas.
               - 340 sinyal (KEJAR emas tertinggal / IKUT gerak X; M1/M5/H1; z 2/3): kotor $0.0-0.2 vs spread ~$0.3.
                 3 "lolos" (XAGUSD H1 4j jual, EURUSD M5 30m jual z3, US500 M5 beli) TIDAK kokoh: median ~$0,
                 untung dari segelintir trade raksasa (buang 5 terbesar -> ~$0.3/negatif), banyak dari 2026, sisi
                 lawan rugi, t ~2 dari 340 uji (~8 diharapkan kebetulan).
               - RASIO EMAS/PERAK z 20 hari (H1/D1): tidak konsisten, versi pasangan ~0 bp.
               - KALIBRASI peluang garis (logistik, snapshot 30 mnt): koreksi vol emas sendiri -0.69% logloss;
                 + volatilitas pasar lain hanya -0.01..-0.03%; + arah pasar lain MEMPERBURUK (+0.1..+1.9%).
  [selesai] HARGA + WAKTU (1 Okt 2026, research\time_tests.py -> time_tests.txt):
               - London PM Fix 15:00 London: 30 mnt SEBELUM turun -7.4 o/oo ADR (t -2.1, 9/10 th turun), sesudah
                 naik +4.7 (9/10 th) = sesuai literatur, tapi ~spread: jual jam-30 -> fix bersih +$0.03 (-0.16/+0.22).
               - WM/R 16:00 akhir bulan: 30 mnt sesudah turun (t -2.4, 9/10 th) tapi n=117, jual bersih -0.31 (17-21).
               - Shanghai AM 10:15 WITA sesudah +3.7 (t 2.5); menit fix/COMEX buka-tutup 1.4x lebih ramai.
               - 54 aturan dagang jam patokan: 0 lolos.
               - Hari: Senin datar (3/10 th naik), lainnya ikut reli; faktor hari utk peluang garis -0.03% (tak berguna).
                 Bulan: Jan/Des kuat, Sep lemah (10 sampel/bulan, lemah); faktor bulan memperburuk (+0.45%).
               - Awal kuartal (3 hari) +130 o/oo ADR di atas rata2 (t 2.0, 8/10) - tumpang tindih dgn efek pergantian
                 bulan; sehari sebelum libur AS +118 (t 2.0), di luar jendela pergantian bulan +94 (t 1.4) -> lemah.
               - PISAH SISI ATAS/BAWAH tabel peluang: statis -0.79% (melihat ke belakang reli 2022-26), tapi BERGULIR
                 250 hari seperti GoldPro +0.18% LEBIH BURUK (kalah 72/105 bulan) -> tabel GABUNGAN GoldPro sudah benar.
               => Tidak ada yang diadopsi. Hipotesis tetap: efek pergantian bulan (+ awal kuartal, terkait).
  [selesai] ICT LANJUTAN (1 Okt 2026, research\ict_tests.py -> ict_tests.txt; sebelumnya: Silver Bullet, Judas, Turtle
            Soup, OB/FVG/BOS, sweep, OTE/Fib, PDH/PDL, EQ sudah gagal):
               - CBDR 14-20 ET / Asia 20-00 ET / Flout 15-00 ET + proyeksi SD: high/low hari di 1-2.5 SD hanya 33-36%
                 hari; TIDAK ada tumpukan di SD bulat (0.99-1.04x di 1 SD, lebih jarang di 2-3 SD); magnet ~0.
                 Prediksi target: kelipatan SD (gaya ICT) logloss +13..+21% LEBIH BURUK dari jarak/ADR GoldPro;
                 ukuran CBDR/Asia tidak menambah apa pun ke GoldPro (+0.0..+0.3%).
                 "Mentok" Flout 1 SD +4.8 dicek dgn LIMIT SUNGGUHAN (SL/TP 0.05/0.1 ADR): level 58.1/55.8% vs palsu
                 56.9/52.9% - semua limit (asli & palsu) kotor 52-66% (pantulan kecil umum), bersih -0.06..-0.21R.
               - Level pembukaan (magnet vs palsu): open 09:30 ET +4.4 (9/10 th, 5.4/3.7), open harian 18:00 ET +3.0,
                 NDOG CE +5.7 (= close kemarin/open, sudah diketahui), open 08:30 ET +3.0 (tak konsisten),
                 MIDNIGHT OPEN 00:00 ET -3.5 (2/10 th; -10.3 di 2022-26) = BUKAN magnet. NWOG +2/+2/-0.5 tak konsisten.
                 Mentok semua ~0/negatif.
               - SMT divergence emas vs perak (M5/M15/H1, A emas sapu-perak tidak / B sebaliknya / pembanding keduanya
                 sapu): R kotor -0.05..+0.07, sama dgn tanpa SMT; 0/54 lolos.
               - Macro ICT (8 jendela): keramaian 0.90-1.09x (= jendela geser +30 mnt 0.95-1.13x), arah ~0, lanjut
                 46-49%; 0/16 aturan lolos.
               => Bagian ICT yang terbukti hanya: open (harian, 09:30 NY) & close kemarin sbg magnet, killzone = jam
                  ramai. Semua bagian penentu arah/entry gagal.
  [selesai] GARIS T0 + OPEN NY 09:30 (1 Okt 2026, permintaan pengguna; research\t0_test.py -> t0_test.txt):
               T0 = tengah EQ & T1 per sisi = (EQ + open +/- 0.25 ADR)/2 (replikasi persis GP_DayMap: hari = D1 server,
               ADR20 D1, EQ = (open+pdc)/2, dir = close M5 ke-12).
               - Tersentuh s/d tutup 2017-26: atas 87.4%, bawah 79.1%, SALAH SATU 100.0% (tiap th 99.6-100%),
                 keduanya 66.5% (2017-21 65-73%, 2024 62%, 2026 58%), searah 91.0% / lawan 75.5%; tanpa sentuhan
                 jam-1 (71% hari): searah 87.6% / lawan 77.7%, T0 pertama = searah 64.5% (= jarak lebih dekat).
                 Pembanding T1: salah satu 98.9%, keduanya 35.8%, searah 75.6 / lawan 59.1.
               - Waktu: median 158 mnt (atas) / 210 mnt (bawah) setelah open; 57% sentuhan pertama 06-10 WITA.
               - Setelah T0 tersentuh: T1 duluan 50.1% vs EQ duluan (koin; per th 44-54%); T1 s/d tutup 80.7%,
                 balik EQ s/d tutup 81.0%. Dagang ikut/lawan dari T0 (SL/TP garis tetangga): -0.14R, 0-1/10 th.
               - Meleset (sisi tak tersentuh): median 0.059 ADR; searah 0.035 ADR.
               - Live: belum tersentuh setelah 1/4/8/12/16 jam -> 80/66/56/41/18% (stabil 17-21 vs 22-26).
               KODE GP_DayMap.mqh: T0Lvl(), NYOpenIdx() (GP_ServerAtLocalHour 09:30 ET), NYBack(); ComputeStats
               st_hitS0/st_hitO0/st_any0/st_both0 + st_nyN/st_nyBack; DrawDay garis T0 (DASHDOTDOT, warna T) & NYO
               (DMInpNYOpenColor, dari bar 09:30 s/d akhir hari, status dekat/tutup x%/KEMBALI); panel hal. 1 baris
               T0 + baris NY di LIVE; tangga hal. 2 + T0 atas/bawah + NY open. Input DMInpShowT0, DMInpShowNYOpen,
               DMInpNYOpenColor. Kompilasi 0 error 0 warning. Cek: NY kembali 250 hari (Python M5) = 78%.
               Perbaikan setelah screenshot pengguna (21:12 WITA): label T0 hari ini terpotong di tepi kanan (ujung hari
               24:00 server di luar layar) -> label T0 kini di AWAL garis (kiri, seperti EQ); label Open NY hari ini =
               FutText (ujung kanan area kosong, ikut zoom). Label T1-T4 tetap di kanan (kebiasaan lama).
               Screenshot 21:4x: label Open NY (FutText) menumpuk dgn label panah live & Cadangan (harga dekat) -> kini
               tag pendek "NY 21:30" di pangkal garis (RIGHT_LOWER); status di panel/tangga/tooltip. Indikator T0
               4170.97/4147.49 = Python persis. Waktu T0 PERTAMA setelah open 2017-26: median 122 mnt, 1 jam 30%,
               2 jam 49%, 3 jam 72%, 4 jam 88%, 8 jam 97%; 250 hr median 82 mnt; T0 kedua median ~9 jam.
  [selesai] STRATEGI ORDER 2 ARAH MENUJU T0 (1 Okt 2026, permintaan pengguna; research\t0_strategy.py -> t0_strategy.txt;
            M1 realistis, spread broker, 2017-2026, 41 varian): LOLOS 0.
               - HEDGE buy+sell market open+5/+30, TP T0, SL T0/T1/T2 lawan/tanpa: kotor -0.6..+0.5 %ADR/hari, bersih
                 -3..-4 %ADR, 0-1/10 th. SL T0 lawan = satu kaki pasti TP, satu pasti SL -> rugi spread TIAP hari
                 (1.052 hari kalah beruntun). Tanpa SL: 81% kaki kena TP tapi rugi terbesar -$242/0.01 lot (2025-26),
                 drawdown -$1.352.
               - Hanya BUY ke T0 atas: positif 2022-26 (reli emas) tapi negatif 2017-21, 2-4/10 th. Hanya SELL: negatif.
               - STRADDLE stop +-0.03 ADR (OCO / tanpa), TP T0, SL EQ / stop lawan / T0 lawan: bersih -1.8..-4 %ADR.
               - LIMIT pantul di T0 -> EQ / T0 seberang, SL tengah/T1/T2: bersih -2.3..-2.9 %ADR.
               - BREAKOUT T0 -> T1: -3.0/-3.2 %ADR. JAM-1 -> T0 searah (86% kena TP tanpa SL): -1.6..-2.2 %ADR.
               => Peluang TP tinggi selalu dibayar oleh rugi yang jarang tapi besar (kotor ~0 = geometri), spread membuat
                  semua negatif. T0 tetap PETA/target, bukan sistem order.
  [selesai] EQ -> T0: BALIK KE EQ DULU? (1 Okt 2026, research\eq_t0_race.py -> eq_t0_race.txt): sudah menempuh
               10/25/50/75% jarak EQ->T0 -> T0 duluan 13.8/24.9/48.4/74.3% = GEOMETRI (f); searah = lawan = jam pertama
               (searah 50%: 47.4%). Sebelum T0 pertama kena, harga balik ke EQ 0x 22% (T0 kena cepat, median 12 mnt),
               1x 9%, 2x 8%, 3x 6%, 4x+ 55%. "Searah 91%" = s/d TUTUP, bukan tanpa balik ke EQ.
  [selesai] POSISI DI EQ: BERAPA KALI BALIK & SEJAUH APA PERGI (2 Okt 2026, permintaan pengguna; research\eq_hold.py ->
            eq_hold.txt): entry = sentuhan EQ pertama (89.6% hari, median menit 0 = saat open; T0 duluan 8.7%).
               - T0 TEMBUS (close M1) 100% hari, median 135 mnt setelah entry (p25 69, p75 201).
               - Balik ke EQ sebelum tembus (pergi >= 0.01/0.02/0.04 ADR ~ $1/$2/$4): median 4/3/1x, rata2 5.9/4.2/2.1x;
                 0x 22/24/33%, 6x+ 42/30/9%. Stabil 2017-21 = 2022-26 = 250 hari; per th rata2 3.6-4.5x (>=0.02 ADR).
               - Jarak pergi sebelum balik (>= 0.01 ADR): median 3.0% ADR, p75 5.2%, p90 8.4%; 250 hr: median $3.6,
                 rata2 $4.7, p75 $6.1, p90 $9.7 (ADR20 skrg $90; EQ->T0 $11.3). Lama pergi median 6/10/22 mnt.
               - Sumbu T0 lalu balik ke EQ tanpa close di luar: 1.4% kepergian, 8% hari.
               - LEVEL PALSU (EQ & T0 digeser +-0.05 ADR) = SAMA (5.9 vs 6.1x; jarak 2.96 vs 2.91% ADR); rumus random walk
                 (>= $4: 2.1x) = sama -> bolak-balik di EQ = sifat gerak harga, EQ bukan magnet khusus. Statistik ini =
                 ukuran "napas" harga di sekitar EQ, bukan sinyal arah.
  [selesai] BASE -> TEMBUS -> RETEST -> LANJUT (1 Okt 2026, permintaan pengguna; research\base_retest.py -> base_retest.txt):
               base = kotak sideway GoldPro (W 30/60/120, P20 per slot), tembus = close M1 di luar, pembanding = kotak
               biasa (P40-60). (a) RETEST tepi dulu sebelum target 1 lebar: BASE 85/88/91%, pembanding 89/91/93% =
               GEOMETRI 86/89/91% (close tembus biasanya baru sedikit di luar tepi; retest median 1 menit). (b) Setelah
               retest lanjut ke target sebelum tengah kotak 31-34% (acak 33%), sebelum tepi seberang 49-51% (acak 50%);
               base = pembanding. (c) Limit di tepi (TP 1 / 1/2 lebar, SL tengah/seberang) & konfirmasi close balik
               (SL ujung retest, TP 1R/2R): R kotor -0.22..+0.03, bersih -0.08..-0.46, 0-2/10 th -> LOLOS 0/30.
               => "Selalu retest dulu" BENAR (85-93%), tapi itu geometri; arah sesudah retest = koin.
  [selesai] RETEST + PUNCAK BARU (HH/LL) (1 Okt 2026, analisa pengguna; research\retest_hh.py -> retest_hh.txt):
               tembus -> puncak P -> retest lantai -> masuk BUY STOP saat menembus P (HH), SL dasar retest, TP 1R/2R/
               measured move, maks 4 jam; lantai = base W30/60/120, pembanding kotak biasa, pita EQ GoldPro; cermin turun.
               - HH terjadi setelah retest (sebelum gagal ke tengah/sisi lain): base 37-52%, pembanding 43-55%, pita 52%.
               - Setelah HH: TP 1R menang 47-55% (acak 50%), 2R 32-38% (acak 33%); R kotor -0.11..+0.11; retest yang
                 menembus lantai vs tertahan di tepi tidak konsisten berbeda; risiko median 0.05-0.08 ADR -> spread
                 berat: bersih -0.06..-0.30R, 0-4/10 th -> LOLOS 0/63.
  [selesai] AMD / POWER OF 3 LENGKAP (1 Okt 2026, permintaan pengguna; research\amd_tests.py -> amd_tests.txt; dulu hanya
            Judas = versi L1 V1, -0.43R). Model L1 (Asia 20-24 ET, manip London 02-05, distr s/d 12:00), L2 (Asia 18-24,
            s/d 16:00), NY (akum 00-08, manip 08-10 ET, distr s/d 16:00). SAPUAN SEGAR saja (harga masih di dalam range
            sampai sapuan; L1/L2 62%/54% hari SUDAH keluar range sebelum 02:00 ET). CATATAN BIAS: versi pertama tanpa
            filter ini memberi "lanjut 59.5%" palsu (harga sudah di luar range -> balapan berat sebelah); diperbaiki.
               - Balapan sesudah sapu (seberang vs lanjut 1 range, acak 50%): DISTRIBUSI duluan 44.9 / 46.1 / 46.7%
                 (L1/L2/NY) = sedikit LEBIH SERING LANJUT (kebalikan AMD), per th tak konsisten (2021 56%, 2026 15-18%).
               - Dagang fade AMD (V1 close balik, TP seberang): bersih -0.21..-0.33R, 0-2/10 th; MSS (V2): -0.03..-0.12R.
                 IKUT sapuan (V3 OCO stop di tepi, SL seberang, TP 1 range): L1 +0.039R (17-21 -0.021, 22-26 +0.121,
                 7/10 th), L2 +0.020 (5/10), NY -0.003 -> tidak lolos (2017-21 negatif; tren 2022-26).
               - Mingguan: high minggu di Sen-Sel 36% (acak 44%), low 46% (acak 43%); low Jumat 21% (acak 30%) =
                 jejak reli emas, bukan pola AMD. LOLOS 0/15.
  [selesai] SISTEM DI SEMUA PAIR FOREX (2 Okt 2026, permintaan pengguna; research\multi_pair.py -> multi_pair.txt,
            long_check.py -> long_check.txt; data M1 broker 27 pair forex + XAUUSD, Agu 2024-Okt 2026, scratchpad\fx).
            Saring Okt25-Sep26 (2 paruh, bulanan), uji ulang Okt24-Sep25, kandidat -> data panjang 2017-2023.
               - PETA GoldPro UNIVERSAL: T0 salah satu sisi 100% di 27/27 pair; T1 salah satu 95.8-100% (rata2 98.9,
                 Y1 99.1); searah 68-80% / lawan 51-64%. Tertinggi: NZDCHF, USDCHF, GBPCAD 100%; terendah EURJPY 95.8.
               - PELUANG LIVE: tabel paruh 1 -> paruh 2 meleset 1.7-4.4 poin (rata2 2.8; XAUUSD 4.2), tahun -> tahun
                 1.0-3.5 (rata2 1.4). Paling presisi: EURGBP 1.7, GBPCAD 1.8, GBPCHF 1.9, CADJPY 1.9, AUDCHF 2.1, USDJPY 2.1.
                 Cad80 kena 78-83.5% (rata2 81.3).
               - MAGNET forex: open NY 09:30 ET +5.2 (Y2) / +4.8 (Y1) rata2, positif kedua tahun 15/27 pair (acak ~7)
                 -> KOKOH lintas pasar; close kemarin +3.9 / +0.2 (tak kokoh); open harian -1.5 / +0.6 (bukan magnet di forex).
               - SINYAL SMC (S1 sweep, S2 BOS, S3 FVG, S4 OB x M5/M15/H1 x sesi x TP): 2.016 kombinasi, R bersih rata2
                 -0.23; konsisten di tahun saring 16 (0.8% = kebetulan), positif juga di uji ulang 4: XAUUSD M15 BOS TP2R
                 (semua/Asia/NY) & GBPUSD H1 FVG London. DATA PANJANG 2017-2023: XAUUSD BOS -0.117R, 0/7 th positif
                 (positif hanya 2025-26 = tren emas ekstrem); GBPUSD FVG London -0.116R, 1/7 th. -> LOLOS 0.
               => Yang konsisten di semua pair = PETA & PELUANG GoldPro (geometri rentang harian), bukan sinyal arah.
  [selesai] PAIR YANG LANGSUNG KE T0? (2 Okt 2026, research\t0_pairs.py -> t0_pairs.txt; Okt24-Sep26, 27 pair + XAU):
               - LANGSUNG (T0 tanpa balik ke EQ, tanpa sentuhan 5 mnt pertama): 12-24% hari (acak ~10%); terbaik USDCHF
                 23.9, EURGBP 23.4, GBPCAD 21.8 - tapi per bulan 0-52% dan SEMUA pair turun dari Y1 ke Y2 (mis. EURGBP
                 29.7 -> 17.0) -> tidak konsisten. 76-88% hari harga balik ke EQ dulu.
               - CEPAT: median menit ke T0 pertama 22-140 (NZDCHF 22, AUDNZD 37, CHFJPY 40; GBPUSD 140, EURUSD 126);
                 bagian besar sentuhan cepat = 5 mnt pertama (lonjakan spread rollover / gap): NZDCHF 37%, CHFJPY 29%.
               - MENEMBUS T0 -> T1 sebelum EQ: 44.6-56.7% (rata2 51.5 ~ koin). USDJPY 56.7 (55/58) dicek 2017-2023:
                 49.9% (n=1809, 2/7 th > 52) -> hanya 2024-26. EURUSD 2017-23 48.5%.
  [selesai] PENYEBAB: SINGGAH EQ vs LANGSUNG, T0 BAWAH vs ATAS (2 Okt 2026; research\t0_factors.py, t0_factors2.py):
               - SINGGAH EQ: rentang median per 30 mnt setelah open 0.064-0.093 ADR (0-120 mnt) < jarak EQ->T0 0.125 ADR
                 -> harga butuh ~2-3 jam gerak Asia untuk sampai; sebelum itu mondar-mandir di sekitar open/EQ.
               - Faktor SAAT OPEN (gap, rentang kemarin, 2 jam terakhir kemarin, posisi close, tren 5/20 hari, ADR5/20,
                 spread, Senin, NFP, FOMC, open di luar range kemarin): lemah & tak konsisten; model gabungan AUC uji
                 0.52 (langsung) / 0.51-0.52 (sisi). Satu-satunya konsisten (emas): close kemarin dekat LOW -> T0 atas
                 duluan 59/66% vs 55/57% (pembalikan kecil).
               - Faktor 30 MNT PERTAMA: rentang kecil -> langsung 5-6%, besar 14-16%; arah naik kuat -> atas duluan 72%,
                 turun kuat 39-42% (AUC 0.61 / 0.67) - TAPI = GEOMETRI POSISI: di menit 30/60 peluang T0 atas duluan =
                 posisi harga di antara T0 bawah & atas (nyata - geometri +1.2/+1.7 poin); T0 sebelum EQ = fraksi jalan
                 yang sudah ditempuh (11/33/60/73 vs 12/36/60/82).
               - JEBAKAN ROLLOVER (forex jelas, emas sedikit): saat open spread melebar (+0.027 ADR), bid tertekan lalu
                 naik +0.04 ADR dalam 15 mnt (70% hari) -> open/EQ/T0 tergambar terlalu rendah -> T0 ATAS duluan forex
                 63.7% (open broker) -> 55.5% (open menit-15); XAUUSD 59 -> 56%. Usulan: jangkar open di harga tengah
                 (bid + spread/2) atau setelah spread normal (belum diubah, menunggu keputusan pengguna).
  [selesai] TOMBOL VERTIKAL + PANEL TERTUTUP + BARIS PULLBACK LEG (1 Okt 2026, permintaan pengguna):
               - Tombol = satu kolom vertikal di tepi kiri (atas->bawah): 1 PETA, 2 ENTRY & TARGET, 3 KOTAK, Target,
                 Panah, Cad80, SMC, Probe, +PIN, Hapus PIN. Tombol "Panel" dihapus.
               - Panel TERTUTUP secara default (kunci GV baru "panelv"); klik tombol halaman = buka di sebelah kanan
                 kolom tombol, klik halaman yang sama lagi = tutup.
               - Label "LIVE: <SESI> | <KONDISI>" di samping tombol 1 PETA (LiveTag, diperbarui tiap candle M1):
                 SESI jam bursa lokal + DST (ASIA / LONDON / LONDON+NY / NEW YORK; WITA musim panas 06-15 / 15-20 /
                 20-23:30 / 23:30-05), KONDISI = CalcMState 60 mnt (KONSOLIDASI / UPTREND / DOWNTREND / BERGEJOLAK /
                 NORMAL). Tooltip: uji 2017-26 = meramal keramaian (0.81x / 1.29x / 1.34x), arah lanjut 47-49% (acak).
                 Panel kini dibuka di bawah label LIVE.
                 + lapisan 15 mnt: "15m SIDEWAY" (rentang 15 mnt <= P20 jam itu; tabel CS_P20_15 dari p20_15.py,
                 metode divalidasi: hitung ulang P20_30 vs tabel korelasi 0.999) / "15m JEDA" (setelah tren/gejolak,
                 rentang 15 mnt <= 35% rentang 60 mnt). Kasus 1 Okt 11:2x WITA: 60 mnt naik $17 (0.18 ADR >= P80
                 $15) -> BERGEJOLAK/UPTREND (efisiensi 0.55-0.63), 15 mnt $4.8 (28% dari 60 mnt) -> "15m JEDA".
               - Tombol ke-11 "Berita": tampil/sembunyi dashboard berita (GDM::g_vNews, GV "news", default
                 tertutup); InpNBShow tidak dipakai lagi. Label "2 ENTRY/TARGET" (dulu terpotong), lebar 88 px.
               - Hal. 1 "-- PULLBACK LEG [KOKOH] --" M5 & M15 (LegLines, replika retrace.py): leg aktif + "tarik x% ->
                 lanjut (100-x)% | balik x%"; bila leg lama tertembus/memanjang/kecil -> tampil gerak yang sedang
                 berjalan tanpa angka peluang. Cek silang research\leg_live.py.
  [selesai] PULLBACK SETELAH PUNCAK / LEMBAH (1 Okt 2026), research\retrace.py: zigzag ATR (konfirmasi 1.5 ATR),
            leg >= 4 ATR, M5 28.8 rb & M15 10.1 rb leg, 2017-26.
               - Pullback terdalam sebelum lanjut: <23.6% 3-4%, 23.6-38.2 27%, 38.2-50 25%, 50-61.8 17%, 61.8-78.6 16%,
                 78.6-100 12-13% (median 47% leg); 31-32% leg berbalik penuh (tembus lembah awal).
               - Setelah menyentuh 38.2/50/61.8/78.6%: P(puncak baru) M5 61.0/50.2/38.5/21.8%, M15 62.3/50.0/38.1/20.3%
                 = gerak acak (1-x) 61.8/50/38.2/21.4% (selisih <= 1.1 poin), stabil per tahun & latih/uji, naik=turun.
                 Reaksi lokal pantul 1 ATR vs terus 1 ATR: 47.5-51.6% (acak).
               -> Level Fibonacci TIDAK istimewa; kecenderungan = geometri jarak: P(lanjut) = 1 - kedalaman.
  [selesai] SUPPLY/DEMAND RBR-DBR-RBD-DBD + FILTER PISAU JATUH (1 Okt 2026), research\sd_base*.py, sd_filters*.py,
            sd_knife_years.py. Definisi: eksplosif body>=60% & range>=1 ATR; base 1-6 candle body<=50%; leg-out close
            melewati base; zona proximal=body ekstrem base, distal=wick base; limit di proximal sentuhan PERTAMA,
            SL distal+-0.1 ATR, TP 1R/2R; dinilai di M1, spread asli. Pembanding: zona "palsu" (base tanpa leg eksplosif).
               - Menang 1R: M5 47-49%, M15 48-50%, H1 46-52%; 2R 29-37% -> sama dengan zona palsu & lempar koin.
               - "Candle sentuh besar" 39% vs kecil 56-60% = MENGINTIP HASIL (candle yg tembus ke SL jadi besar; zona
                 palsu sama: 32% vs 59%). Ukuran ex-ante: datang cepat (6 candle >2.5 ATR) atau candle sebelum >1.5 ATR
                 -> M5 46.2% vs tenang 49.2% (9/11 th), M15 48.1 vs 50.0 (7/11), 2025-26 tidak berbeda.
               -> Zona S&D tidak memberi keunggulan; filter pisau jatuh hanya menghindari ~3 poin terburuk, tidak
                  menciptakan keunggulan. TIDAK dibangun sebagai sinyal.
  [selesai] MODUL "PAUS" (SMC_SupplyDemand.mqh, adopsi SMC lama) - AUDIT + UJI + PERBAIKAN (2 Okt 2026, permintaan
            pengguna; research\paus_test.py [TF menit] -> paus_test.txt (H1), paus_test_M15.txt, paus_test_M5.txt).
               AUDIT kode lama (replikasi live, H1 2017-26; M15/M5 serupa):
               - 71% zona muncul TELAT (median 40 bar H1 setelah pola; M15 80%, M5 86%) karena tiap jam memindai ulang
                 200 bar dgn rata2 body/range SAAT INI; 55% zona sudah tersentuh sebelum muncul (tampil "fresh").
               - 6% memakai candle H1 yang BARU terbentuk (range 0) sebagai leg keluar; 19% "base" tidak pernah
                 ditinggalkan (leg keluar tidak close di luar zona).
               - Setelah ganti TF / pasang ulang status hanya dicek dari 1 candle terakhir: 78% zona yang TAMPIL sudah
                 tersentuh (seharusnya hilang), 41% di sisi salah harga (demand di atas harga / supply di bawah).
               AKURASI (sentuhan pertama, limit di tepi dekat, SL tepi jauh + 0.1 rata2 range, TP 1R/2R, spread M1):
               - H1: menang 1R 50.5% / 2R 33.7% (acak 50/33), bersih -0.09R, 2-3/11 th; diperbaiki sama (50.6/33.0);
                 zona PALSU (leg tidak impulsif) 51.1/34.7 -> SAMA. M15: 49.3/34.1, -0.24R; M5: 48.0/33.2, -0.51R.
               - 11 filter (pola lanjutan/balik, sisi, sesi, tren D1, diskon/premium EQ, jumlah base, lebar, kekuatan
                 leg, perpindahan leg, umur, kecepatan datang), latih 2017-21 -> uji 2022-26: LOLOS 0 (H1, M15, M5).
                 Demand H1 uji +0.04R tapi latih -0.11R (= reli emas 2022-26, bukan zona).
               - Konfirmasi M1 (close kembali di luar zona, SL ujung sentuhan): 50.3% 1R, -0.31R (H1); palsu sama.
               => Zona Paus = acak; tidak bisa dijadikan sinyal. Tetap INFO (tombol SMC), tooltip: "uji 2017-26 = acak".
               KODE (GoldPro saja; SMC_Pro_System asli tidak disentuh): TrySDPattern(tf, n) dinilai SEKALI saat candle
               leg keluar ke-3 close, rata2 shift n..n+19 (live = backfill), leg keluar wajib close di luar zona;
               backfill n = 200..1 (tua -> baru), live n = 1..3; sourceTF_time = waktu zona lahir; SDTouchedSince()
               cek iLowest/iHighest TF chart sejak lahir (status benar setelah ganti TF); g_sdBackfilled (ulang bila
               histori belum siap). Label "bar H1" ikut input TF. Compile live 2 Okt 09:34 WITA (izin pengguna):
               GoldPro_Main + GoldPro_Validator 0 error 0 warning.
               Verifikasi Python 2 Okt 09:22 WITA (scratchpad\paus_now.py): 5 zona/200 bar, tampil hanya Supply
               4257.61-4266.31 (DBD 1 bar, lahir 28 Sep 06:00 server); Demand: tidak ada zona fresh.
  [selesai] SAAT KOTAK OB MUNCUL, HARGA KE MANA? (2 Okt 2026, pertanyaan pengguna dari screenshot; research\ob_appear.py ->
            ob_appear.txt; M5 2017-26, struktur versi diperbaiki, 31.008 event):
               - OB BIRU (bullish) muncul: harga lebih rendah 60 mnt kemudian 51.4% (semua candle 48.8%); balapan +-1 ATR
                 turun duluan 50.2% (acak 50.3) -> koin.
               - OB PINK (bearish) muncul: lebih rendah 60 mnt kemudian hanya 45.4% (BOS 44.5, CHoCH 46.2) = sedikit
                 MANTUL naik setelah candle tembus; balapan +-1 ATR turun duluan 48.2% (2017-26 per th 46-51).
               - Dagang ikut/lawan saat kotak muncul (30/60 mnt): kotor -0.13..+0.13 ATR, bersih -0.25..-0.51 ATR
                 (spread ~0.38 ATR), 0-2/10 th -> tidak ada sinyal. Kotak muncul SETELAH gerak terjadi.
  [selesai] TANDA WARNA NAIK/TURUN DI SEMUA TF? (2 Okt 2026, permintaan pengguna; research\dir_ml.py -> dir_ml.txt):
            gradient boosting per TF, 31 fitur gabungan (momentum, posisi range, EMA, RSI, Stoch, MACD, volatilitas, candle,
            volume, jam/hari, jarak open/EQ, struktur SMC), latih 2017-21, uji 2022-26, target close k bar > open berikut.
               - SEMUA SINYAL: AUC 0.496-0.525, akurasi 50.4-51.8% (selalu-naik 50.4-57.0%) -> tanda warna tiap candle = koin.
               - 10% PALING YAKIN: benar 53-57% (M1-H1, tiap th 53-59% di M1/M5), tapi gerak 0.04-0.2 ATR < spread:
                 M1/M5 bersih negatif 0-1/5 th; M15/H1 ~0..+0.03 ATR.
               - 2% PALING YAKIN: M5 k12 61% +0.087 ATR, M15 k4 62% +0.116, M15 k16 57% +0.258, H1 k4 58% +0.142 bersih,
                 tapi hanya 3/5 th positif; top10 2026 turun ke 49-50% (M5 k12, M15 k4) -> belum lolos (syarat >= 70% th).
               - D1 k1 top10 62% (4/5 th) tapi n 123 & ikut reli emas; H4 = koin.
               => Tanda naik/turun umum TIDAK dibuat (melanggar "jangan tampilkan bila kurang presisi"). Kandidat satu-satunya:
                  sinyal 2% paling yakin M15/H1 -> perlu uji walk-forward per tahun sebelum dipertimbangkan.
  [selesai] PETA AKURASI ARAH PER JAM & KONDISI, M1/M5 (2 Okt 2026, permintaan pengguna; research\dir_map.py -> dir_map.txt):
            model dir_ml, uji dibelah A 2022-24 / B 2025-26; NYATA = sinyal yakin >= 55% & bersih > 0 di A dan B.
               - Semua sinyal per jam WITA: 49-52% hampir semua jam; terbaik 04-06 WITA (sekitar open harian/rollover)
                 52-55% (A) tapi B lebih rendah & spread rollover -> bersih negatif.
               - Sinyal yakin: 50-58% (periode terburuk) per jam; kondisi (volatilitas, tren/datar, hari, berita, bias SMC)
                 semua ~54-56%, tanpa beda konsisten.
               - Lolos A & B: harga sudah > 0.5 ADR dari open harian (M1 15m 57/55%, M5 15m 57/56%) bersih hanya
                 +0.03..+0.07 ATR; M5 60m jam 09 & 22 WITA (59/58, 55/60%) tapi jam tetangga 47-50% & ~100 sel diuji
                 -> kemungkinan kebetulan. => Tidak ada jam/kondisi M1/M5 di mana arah bisa ditebak cukup presisi.
  [selesai] TANDAI CANDLE D1 KEMARIN (PDH / PDL / TENGAH 50%) -> ENTRY TF KECIL (2 Okt 2026, permintaan pengguna;
            research\d1_range.py -> d1_range.txt; M1 2017-26, pembanding = candle kemarin digeser +-0.1 ADR):
               - PETA: open hari ini di dalam candle kemarin 96.4%; PDH tersentuh 51.2%, PDL 44.8%, salah satu 84.8%,
                 keduanya 11.2%, tengah 68.2%. Setelah PDH tembus: close kembali di bawah 48.6%, tengah 35.6%, PDL 13.2%
                 (palsu 48.3/36.1/13.0); PDL: 53.2/40.8/13.2 (palsu 53.5/40.4/14.4) -> SAMA dgn level acak.
                 Sentuhan pertama PDH/PDL: 06-09 WITA 33%, 14-18 19%, 19-21 18%.
               - ENTRY (15 varian): CRT sapu-balik M5/M1 (TP tengah/seberang/1R/2R), breakout M5 (1R/2R/tutup),
                 tembus+retest, pantul tengah 50% -> bersih -0.10..-0.50R, 0-3/10 th, LOLOS 0.
               - CRT M5 satu-satunya yang lebih baik dari palsu (2R kotor +0.085 vs -0.046R, ASLI > PALSU 9/10 th) tapi
                 kotor kecil; filter SL >= 0.08 ADR: kotor +0.089, bersih -0.093R (22-26 -0.075), 3/10 th -> tidak lolos.
  [selesai] 16 POLA CANDLESTICK daftar pengguna (2 Okt 2026; research\candle16.py -> candle16.txt; definisi persis teks,
            konteks tren 10 bar +-1 ATR, M1/M5/M15/H1 2017-26, pembanding "konteks saja"): Hammer, Inverted Hammer, Bullish
            Engulfing, Piercing, Morning Star, Three White Soldiers, Bullish Marubozu, Dragonfly Doji, Hanging Man, Shooting
            Star, Bearish Engulfing, Dark Cloud, Evening Star, Three Black Crows, Bearish Harami, Spinning Top (2 arah).
               - Searah setelah 3 candle: M5 41.8-53.1%, M1 43.9-50.7% (acak 50); kotor -0.10..+0.05 ATR = konteks saja.
                 Three Soldiers/Crows justru 42-47% (lebih sering mundur sedikit).
               - SL di ujung pola + TP 2R: bersih M1 -0.6..-12.7R (SL setipis spread), M5 -0.2..-3.8R, M15 -0.0..-2.3R,
                 0-5/10 th. H1 Dark Cloud +0.13R (n 153/10 th, 17-21 negatif, 6/10 th) & Morning Star +0.08 (n 78) = kebetulan
                 di antara 68 uji. LOLOS 0/68. (Putaran lama: pa_tests2 & indicator_screen juga 0.)
  [selesai] LUXALGO SMART MONEY CONCEPTS (2 Okt 2026; research\luxalgo_smc.py -> luxalgo_smc.txt; replika logika publik dari
            pengetahuan, kode LuxAlgo TIDAK disalin): leg() pivot kanan-saja, struktur internal 5 & swing 50 (crossover,
            BOS/CHoCH), OB = bar low/high terurai ekstrem antara pivot & tembus (bar >= 2x ATR200 ditukar). M5/M15 2017-26.
               - Arah setelah event (balapan +-1 ATR): 48.7-51.4% searah (swing BOS M5 51.4%, M15 51.0%) = koin.
               - Sentuhan pertama OB (limit tepi, SL tepi jauh + 0.1 ATR): menang 1R 52.6-55.4% tapi OB PALSU (bar acak
                 di rentang sama) 53.5-57.2% = sama/lebih baik; bersih -0.16..-0.52R, 0-4/10 th. LOLOS 0/8.
               => Tidak ada bagian LuxAlgo SMC yang bisa diadopsi sebagai sinyal; isinya setara SMC GoldPro.
  [selesai] 4 SARAN DEEPSEEK (2 Okt 2026; research\deepseek_tests.py -> deepseek_tests.txt; M1 2017-26):
               - STRESS-STRAIN (deviasi EMA21 %): M5 99.8% candle di zona "elastis" (<0.8%), M15 98.9% -> ambang %
                 tak terpakai utk scalping; "6 filter fisika" tak terdefinisi (tak bisa diuji). Versi ATR M5/M15: ikut
                 yield/hardening searah 44-50%, bersih 0-2/10 th; UTS lawan BUY 55-56% tapi bersih negatif.
                 H1/H4 BUY positif 6-7/10 th = ikut reli emas (SELL negatif); H1 % yield ikut 12 bar +0.15 ATR di atas
                 pembanding kedua sisi tapi n ~1.100/10 th, TF besar, dipilih dari ~100 baris -> catatan saja.
               - DELTA PERKIRAAN (tick vol x CLV, M5): divergensi CVD menang 1R 49.1-49.3% vs tanpa divergensi 47.7-47.9%;
                 absorpsi 49.9-51.2% vs pembanding 49.5-50.1%; "terjebak" 48.9-50.6% vs 49.2-49.4%; bersih semua negatif.
               - VOLUME PROFILE 03-07 NY sapu VAH/VAL & kembali: menang 1R 50.3%, kotor 0.00; palsu sama; searah bentuk
                 P/b lebih buruk (47.2%). Bersih -0.42..-0.53R.
               - PULLBACK EMA20/50 + pita ATR + RSI>50: M5/M15 menang 1R 49.6-50.7%, kotor ~0, bersih -0.18..-0.45R.
               => LOLOS 0. Gabungan filter yang masing2 tanpa keunggulan tetap tanpa keunggulan (dir_ml: 31 fitur = 51%).
  [selesai] FAKTOR PEMBENTUK POLA CHART (2 Okt 2026; research\chart_factors.py -> chart_factors.txt; M1 2017-26):
               - JAM: gerak/menit 20-23 WITA 1.41-1.72x rata2 (NY buka + data AS); terendah 12 WITA 0.61x, 04-07 WITA
                 0.67-0.72x dgn spread terlebar ($0.34-0.38 vs $0.26-0.28 malam).
               - BERITA penting (-5..+30 mnt): 3.2% waktu = 6.2% gerak (1.9x); menit rilis 4.7x.
               - KONSENTRASI: 1% menit terbesar = 9.1% gerak, 5% = 25.6%, 50% menit terkecil = 13.5%.
               - BESAR GERAK bisa ditebak (autokorelasi |return| lag 1: M5 +35, H1 +30, D1 +15; range jam berikut dari jam
                 ini + jam sama kemarin R2 34%); ARAH tidak (autokorelasi return M5 -1.3, H1 -1.5, D1 +0.4; arah jam berikut
                 = jam ini 47.9%).
               - TREN: +0.051%/hari vs simpangan 1.01% (5% dari bising), hari naik 54%; th 2017-26 -6%..+62%.
               => Chart = ritme jam/berita + volatilitas berkelompok + magnet open/close kemarin + level stop yg ditembus,
                  di atas arah yang ~acak. GoldPro memetakan yang bisa ditebak (kapan, seberapa jauh, di mana), bukan arah.
  [selesai] KAPAN HARGA DATANG KE PIJAKAN / TUJUAN / ZONA (2 Okt 2026, permintaan pengguna; research\pijakan_time.py ->
            pijakan_time.txt, parameter pijakan_profile.npy):
               - MODEL: gerak acak dgn ritme jam: varians/menit = ADR^2 x profil 48 slot 30 mnt WITA (2017-21) x volK^2,
                 volK = (realisasi 120 mnt / profil)^0.5, sigma_T = 0.90 x akar(jumlah varians); P(sentuh d dlm T) =
                 2(1-Phi(d/sigma)). Uji 2022-26: meleset rata2 1.8 poin (maks 4.5), tiap th 1.3-2.5; ritme jam
                 logloss 0.4381 vs rata 0.4549 vs tanpa vol 0.4573. Sedikit melebihkan jarak dekat (~3 poin).
               - PIJAKAN OB (replika GoldPro M5, 311 rb sampel): tersentuh -0.1..-1.2 poin dari prediksi (jarak dekat
                 -3..-3.5 = sama dgn level biasa) -> OB bukan magnet & bukan dihindari.
               - RENTANG 60 mnt: median 1.44 x sigma60 (p20 0.70x, p80 1.46x), R2 log 42%.
               KODE: Core\GP_TouchTime.mqh (TT_Update tiap menit: ADR20 D1 + volK; TT_P, TT_Min50, TT_Range60, TT_Tip);
               label Pijakan / Tujuan / kotak OB / Premium-Discount-OTE-Equilibrium + "| 1j x% 2j y%" dan tooltip
               lengkap (15m/30m/1j/2j/4j, 50% dalam ~x mnt, catatan "peluang DATANG bukan memantul"); label kuning
               "retest SMC?" -> "Pijakan duluan x% | 1j y%" (jarak relatif); panel LIVE: "Rentang 1 jam ke depan",
               "Pijakan/Tujuan ... 30m 1j 2j", "Duluan: Pijakan x% | Tujuan y%". GoldPro_Main: render & panel tiap menit.
               Compile live 2 Okt 14:47 WITA (izin pengguna), Main + Validator 0 error.
               Perbaikan setelah screenshot pengguna (label bertumpuk di harga Pijakan): kotak OB slot ANCHOR tanpa angka
               (sudah di garis Pijakan); label kuning "Pijakan duluan" pindah ke tengah panah; Premium/Discount hanya
               "(harga di sini)" (angka tepi = Equilibrium, dulu dobel); OTE & OB tujuan cukup "1j x%"; <1% / >99%. Compile live 2 Okt 17:15 WITA.
               Putaran 2 (screenshot 17:1x): kotak Premium/Discount < 15% tinggi chart -> 1 label "EQ | 1j x% (harga di
               Premium/Discount/...)" (tooltip: batas semua zona); label kuning cukup "duluan x%" (tanpa Tujuan / market
               tutup -> tidak ada); "Pijakan <jenis> <harga> | 1j 2j", "Tujuan BSL swing <harga> ($x) | 1j 2j".
               Compile live 2 Okt 17:18 WITA, 0 error.
  [selesai] KONSISTENSI SENTUHAN EQH / EQL (2 Okt 2026, permintaan pengguna; research\eq_hl.py -> eq_hl.txt; replika
            SMC_Liquidity: swing fractal 5, toleransi 0.1 ATR14, 2x = EQH/EQL, 3x+ = pool; M5 & M1 2017-26, 134 rb):
               - Lahir rata2 1.7-1.9 ATR dari harga (M5 ~$7, M1 ~$3 skrg). Tersentuh M5: 15m 17-19%, 1j 40-43%, 4j 63-68%,
                 24j 84-88%, 5 hari 92-95%; M1: 15m 46-47%, 1j 69-71%, 24j 93-95%. Level CERMIN jarak sama: sama / +2
                 poin; model GP_TouchTime +3..+4 poin (melebihkan jarak dekat). Per th stabil (M5 1j 40-42%).
                 => EQH/EQL BUKAN magnet: tersentuh sesering level apa pun di jarak yang sama. 2x = 3x+.
               - Waktu ke sentuhan pertama: M5 median 75-81 mnt [20-330], M1 16-17 mnt [4-77].
               - Setelah disentuh: candle sentuhan close kembali ("SWEPT") 45-51%; dari close candle itu balapan
                 +-1 ATR lanjut 47-50% (setelah sapu 49-50%, setelah tembus 47-50%) = koin. Versi pertama mengukur dari
                 menit sentuhan (mengintip close candle) -> "balik setelah sapu 71-74%" PALSU; diperbaiki.
  [selesai] GARIS KE GARIS (3 Okt 2026, permintaan pengguna; research\line_graph.py -> line_graph.txt, line_graph_events.pkl):
            simpul = open, pdc, EQ, T0+-, T1-T4+-, PDH, PDL, open NY 09:30 (gabung < 0.03 ADR); setelah menyentuh simpul X,
            tetangga atas/bawah mana duluan (M1, 55.886 peristiwa 2017-26) vs geometri jarak.
               - Geometri tepat: per kelompok meleset 0.6-2.3 poin; rata2 +0.76 poin ke atas (reli emas).
               - KONSISTEN (t >= 3, kedua periode, >= 7/10 th): PDH disentuh dari bawah -> atas duluan 46.5% vs 42.3%
                 (+4.1, 8/10); PDL dari atas -> bawah duluan +3.9 (10/10) = garis kemarin cenderung DITEMBUS (sesuai
                 level_react). Sentuhan pertama klaster open/EQ/pdc -> atas duluan 60.1% vs 52.1% (+8.0, 10/10) =
                 JEBAKAN ROLLOVER (bid tertekan saat open, lihat t0_factors2).
               - Dagang (masuk di garis, TP tetangga searah, SL tetangga lawan, spread + slip $0.20): PDH -0.35$ (1/10 th),
                 PDL -0.19$ (1/10), tetangga >= 0.05 ADR -0.23/-0.14$ (2/10); open-rollover -0.19$ (4/10; + hanya 2023-26).
                 Jarak TP/SL hanya $4-10 -> kotor +$0.18-0.48 habis dimakan biaya. LOLOS 0.
               - Waktu antar garis median: dari PDH/PDL/pdc 6-8 mnt, dari T0 19-28 mnt, T1 14-40 mnt, T2/T3 16-37 mnt.
  [selesai] RUTE TRADING DARI GARIS (3 Okt 2026, permintaan pengguna "tepat dari titik mana"; research\route_table.py ->
            route_table.txt/.pkl): masuk limit TEPAT di garis saat sentuhan pertama (EQ >= 15 mnt, T0 atas/bawah, EQ setelah
            T0, T1 atas/bawah, open NY kembali, PDH/PDL), LANJUT / BALIK, TP garis GoldPro berikutnya, SL garis seberang /
            0.03 / 0.06 ADR, M1 2017-26, 54 rute.
               - Menang vs geometri rata2 -3.7 poin (bar sentuhan dihitung konservatif), terbesar +2.1. LOLOS 0/54
                 (bersih 17-21 & 22-26 positif + >= 7/10 th).
               - Dolar asli 2025-26 (SL garis seberang): EQ lanjut +$0.30, PDH lanjut +$0.22, open NY lanjut $0.00, sisanya
                 -$0.3..-1.7 -> 1.75 th saja; 10 th 0-2/10 positif. PDH lanjut = efek "PDH ditembus" (line_graph).
               - MAE pemenang (melawan dulu sebelum TP, SL garis seberang, 2025-26): median $2.5-5, p80 $6-12; SL 0.06
                 ADR (~$3.5) memotong banyak pemenang (menang 19-39%). Menit ke TP median 7-75.
  [selesai] INFOGRAFIS PENGGUNA (3 Okt 2026; research\infografis.py -> infografis.txt; M5/M15/H1 2017-26, eksekusi M1):
               - FIBONACCI golden zone 50/61.8% (SL 78.6/100, TP 0%/127.2%, + tren EMA50/200, + candle konfirmasi) vs zona
                 palsu 30/75%: menang = geometri persis (50% zona SL100 TP B 50.2-51.2%; 61.8% 38.7-39.9%), kotor ~0,
                 konfirmasi tidak menambah. LOLOS 0/84.
               - BREAKOUT SIGN (jarak sentuhan menyusut < 0.75x): tembus +0.2 ATR sebelum menjauh 2 ATR 29.4/29.5% vs
                 tidak menyusut 27.1/26.8% (kedua periode; M5/M15 +0.5..+4 poin, H1 0) = efek nyata tapi KECIL. Dagang stop
                 M5/M15 negatif; H1 resistance BUY menyusut +0.25/+0.40R (8/10 th) tapi n 66 (6.6/th), SELL cermin negatif,
                 tahan s/d 4 hari -> drift reli emas + kebetulan (2 lolos dari 24).
               - BREAKOUT TYPES: M5/M15 ascending/descending/range = pembanding tanpa pola (menang 48-50% 1R), negatif.
                 H1 ASCENDING BUY 2R +0.245R (8/10) vs tanpa pola +0.021, tapi DESCENDING SELL negatif & n 30/th, tahan
                 s/d 4 hari -> hipotesis drift, bukan scalping. MA/divergensi/price action/S&D sudah gagal sebelumnya.
  [selesai] MENINGGALKAN PIJAKAN -> BENAR-BENAR MENEMBUS GARIS? (3 Okt 2026, permintaan pengguna; research\tembus_garis.py ->
            tembus_garis.txt; 51.069 kedatangan di garis GoldPro, M1 2017-26; pijakan = garis terakhir yang disentuh):
               - Candle M5 sentuhan close TEMBUS 46-54% (semua 49.1%) = koin.
               - BENAR TEMBUS (sampai garis berikutnya sebelum balik ke pijakan) 44.6% vs geometri jarak 43.8% (+0.8);
                 per garis 25-49% sesuai jarak (mis. T1 -> T2 $15 jauh vs balik $7: 34.5% / geometri 34.9%).
               - Tanpa mengintip (balapan mulai setelah candle close): stl close TEMBUS lanjut 54.0% = geometri dari posisi
                 close 54.0%; stl close BALIK lanjut 34.4% vs 34.8% -> close M5 tidak menambah informasi.
               - Lebih sering tembus dari geometri: PDH dari bawah 45.8 vs 41.6 (+4.1, 9/10 th), PDL dari atas 46.3 vs 43.2
                 (+3.2, 8/10), T0+ naik +1.8 (8/10). Lainnya +-2. Waktu sampai selesai median 8-40 mnt.
  [selesai] PENAMBAHAN AKURASI (3 Okt 2026, arahan pengguna: "yang meningkatkan akurasi bot, itu yang ditambahkan"):
               - KALIBRASI ULANG GP_TouchTime (research\touch_calib.py, touch_calib_table.npy): pemetaan isotonic p_mentah ->
                 p (latih 2017-21, 101 titik TT_CAL + TT_Cal()); uji 2022-26 meleset rata2 1.82 -> 0.74 poin (maks 4.5 ->
                 1.9), logloss 0.4381 -> 0.4358, membaik 9/10 th. Dipakai di TT_P & TT_Min50 (semua label/panel).
               - LABEL PDH/PDL (SMC_RenderLiquidity, tombol SMC): "PDH | 1j x% 2j y% | cenderung tembus" (atau "harga di
                 atas/bawah"); tooltip: peluang waktu + sifat terukur (tembus 45.8/46.3% vs jarak 41.6/43.2%, 9/10 & 8/10 th;
                 memantul = rute terburuk; close M5 tidak menambah info).
               - PANEL KOTAK (GP_BoxSignal): Atas/EQ/Bawah + "1j x%" (peluang DATANG dlm 1 jam).
               Compile live 3 Okt 10:59 WITA (pasar tutup), Main + Validator 0 error.
  [selesai] EA PANEL TRADING + PENGAWAL DISIPLIN (3 Okt 2026, permintaan pengguna setelah bedah riwayat akun:
            1.141 posisi/30 hari = 38/hari, 1.6% ber-SL, 59% lock, 10 rugi terbesar -$637, biaya ~$200; "seandainya"
            maks 3 trade/hari +$51 vs asli -$315; SL $3-5 memperburuk karena MAE median $2.5, p80 $6).
               Experts\GoldPro\GoldPro_Panel.mq5 (indikator tidak boleh order). Pasang di chart yang sama dgn GoldPro.
               - SELL/BUY market: lot +/-, SL $ WAJIB (default $10), TP $ opsional; klik 2x dlm 3 dtk.
               - RENCANA: BUY LIMIT di garis GoldPro terdekat di bawah (TP garis terdekat di atas) & SELL LIMIT cermin;
                 garis = rumus GP_DayMap (EQ/open/pdc/T0/T1-T4/PDH/PDL/open NY) + Pijakan/Tujuan dari indikator (GV
                 GP_PIJ_/GP_TUJ_/GP_TS_<ChartID>), gabung < 0.03 ADR; tampil "isi 1j x%" (GP_TouchTime terkalibrasi) &
                 "TP dulu y%" (geometri SL/(SL+jarak TP)); peringatan bila entry di PDH/PDL (cenderung tembus).
                 Order limit kedaluwarsa InpPendingHrs (bila broker mendukung SPECIFIED).
               - PENGAWAL: trade hari ini (deal IN sejak open D1) vs InpMaxTradesDay (5), P/L + komisi hari ini, batas rugi
                 harian (InpMaxLossDay, 0 = 10% saldo awal hari), posisi tanpa SL, lock (BUY & SELL bersamaan), rugi
                 ditahan > InpWarnHoldMin, jarak stop out ($ harga). Batas tercapai / lock / > InpMaxOpen -> order DITOLAK.
               - GP_TouchTime kini berdiri sendiri (TT_ServerToUTC: server UTC+2 + DST AS) agar EA tidak menarik input SMC.
               Compile 3 Okt 11:31: Panel 0 error (ex5 baru via path 8.3 bernama GOLDPR~2.ex5 -> di-rename), Main + Validator
               11:32 0 error. EA TIDAK dipasang / tidak ada order dari Claude.
               Perbaikan setelah screenshot (panel di kanan bawah menutup chart): tombol ke-12 "Trade" di kolom tombol
               GoldPro (GP_DayMap: g_vTrade, VSet "trade", BTN_N 12; teks "Trade (EA?)" bila EA belum terpasang -
               ChartGetString CHART_EXPERT_NAME). Panel trading muncul di TEMPAT panel halaman (kanan kolom tombol, di bawah
               LIVE); buka Trade -> panel halaman tertutup, buka halaman -> Trade tertutup. Indikator -> EA via GV
               GP_TRADEV_/GP_PX_/GP_PY_/GP_TBX_/GP_TBY_<ChartID> (TradeGV()). EA: timer 250 ms (tampil/sembunyi), hitung
               penuh 1 dtk; panel tersembunyi + ada masalah (tanpa SL / lock / rugi lama / batas harian) -> "!" merah di
               samping tombol Trade (tooltip = daftar masalah). Tanpa indikator GoldPro di chart: EA menggambar tombol
               "Trade" sendiri di kiri atas. Compile 3 Okt 11:43-11:44: Panel, Main, Validator 0 error.
  [selesai] RETEST PITA EQ "pantul x%" DIPECAHKAN (3 Okt 2026, permintaan pengguna; research\eq_retest.py -> eq_retest.txt):
            replika persis ScanDay (pergi = candle M5 di luar mid +- (half+0.10 ADR), retest = sentuh mid +- (half+0.02),
            pantul = mid +- (half+0.15) sisi asal duluan), 2017-26, ~4.900 retest.
               - Pantul tampil (cara lama) #1 61.7 / #2 63.6 / #3+ 67.1% vs geometri jarak 60.5-60.8% -> tapi PITA PALSU
                 (digeser +-0.15 ADR) 63.6/64.1/67.2% = sama -> EQ tidak istimewa. Kelebihan = ARTEFAK: hasil dihitung
                 termasuk candle sentuhan (gerak di dalam candle itu tak bisa diambil). Mulai candle SESUDAH sentuhan:
                 58.7/60.2/61.3%; M1 sesudah menit sentuh: 58.6/59.5/61.3% = geometri. "Pantul 63-72%" = jarak pantul
                 (0.13 ADR ~$10) lebih dekat dari tembus (~$15).
               - Dagang limit di titik retest, TP pantul, SL titik tembus / tepi jauh / 0.05 / 0.08 ADR: bersih
                 -0.12..-0.51R, 0-2/10 th, pita palsu sama. LOLOS 0/12. Waktu: pantul median 40 mnt, tembus 72 mnt.
               KODE (koreksi akurasi): ScanDay retest outcome mulai j = k + 1; tooltip Retest dijelaskan (jarak, bukan edge);
               komentar "Retest #2 +0.13R konsisten" dikoreksi. Compile live 3 Okt 11:49, 0 error.
  [selesai] INDIKATOR DI SEKITAR EQ (3 Okt 2026, permintaan pengguna; research\eq_indicators.py -> eq_indicators.txt,
            eq_touch_events.pkl): 22 fitur (RSI M5/M1, Stoch, MACD, momentum 5-60 mnt, EMA20/50 & kemiringan, %B, ATR rasio,
            candle, volume, jam, hari, menit sejak buka, sentuhan EQ, tren D1) vs GEOMETRI jarak; latih 17-21 / uji 22-26.
               (a) BALIK ke EQ vs LANJUT ke garis (200 rb sampel tiap 15 mnt): geometri AUC 0.791; + indikator logloss 0.4883 ->
                   0.4860 (-0.5%), AUC 0.792 = hampir nol. Per indikator desil ekstrem +-1..3 poin (bias umum -1.6). "10% paling
                   yakin" sempat +$1.61/trade = ARTEFAK (hanya sampel yang kena target; terpilih menjelang tutup hari). Jujur
                   (semua sampel, tak kena = tutup akhir hari): -$0.33/trade, 1/5 th.
               (b) SENTUH EQ -> lanjut tembus vs balik (11 rb): indikator tidak memperbaiki logloss (0.6127 -> 0.6133). Satu
                   efek nyata & konsisten: MOMENTUM kuat ke EQ -> lebih sering TEMBUS (mom15 desil atas +4.5/+5.2 poin di atas
                   geometri, latih/uji; desil 95: lanjut 70.6% vs 63.7%). Dagang (TP garis seberang, SL garis asal): R bersih
                   -0.03..-0.25, 17-21 negatif, 22-26 +0.03..+0.28, 2-4/10 th -> TIDAK LOLOS (pola "hanya era 2023-26").
               => Indikator tidak menambah keunggulan di EQ. Peta jarak tetap yang terbaik; momentum kuat = info "tembus lebih
                  mungkin" (sejalan dgn PDH/PDL & level likuiditas ditembus).
  [selesai] T0 TERSENTUH: SEBERAPA DALAM TEMBUS & BALIK (3 Okt 2026, permintaan pengguna; research\t0_touch.py -> t0_touch.txt,
            t0_touch.pkl; 4.169 sentuhan pertama 2017-26; $ = %ADR x ADR20 sekarang $90):
               - TEMBUS melewati T0 (median / p75 / p90): 30m $4.9/9.9/17.5, 1j $6.7/12.8/22.5, 2j $9.4/17.4/29.1,
                 4j $12.8/23.2/39.6; sampai balik ke EQ $10.4/30.1/67.5. Tembus >= $3.6 sebelum balik EQ 72%, >= $7.2 58%,
                 sampai T1 48%.
               - BALIK dari T0 ke arah EQ: 30m $5.5/9.4/15.3, 1j $7.3/12.6/20.1, 2j $10.0/17.4/27.5, 4j $13.2/23.9/37.8;
                 sampai T1 $11.4/32.3/66.9. Balik >= $3.6 sebelum T1 78%, >= $7.2 62%, sampai EQ 50%.
               - BALAPAN dari T0 (+X vs -X, X = $1.8-7.2): tembus 49.3-50.5% (palsu 48.6-50.0%) = KOIN; searah jam-1
                 51-53% / lawan 47-48% (kecil). T0 asli = palsu (median sama). Tembus terjauh median 40 mnt setelah sentuh.
               => Setelah T0 tersentuh, besar tembus & balik SIMETRIS (~$5-7 per jam median) -> "napas" untuk ukuran SL/TP,
                  bukan arah. Periode 17-21 = 22-26. Contoh 2 Okt 14:45 WITA: ADR20 $90.1, rentang 1 jam ~$16 ($11-23).
  [selesai] EQ -> T0: SETELAH MENINGGALKAN EQ, DI JARAK BERAPA PASTI SAMPAI T0? + CARI CELAH (3 Okt 2026; research\eq_t0_progress.py
            -> eq_t0_progress.txt, .pkl; 48.563 keberangkatan dari EQ 2017-26, 42.031 peristiwa + 39.230 EQ PALSU):
               - Jarak EQ->T0 2025-26: median $9.6 (p25 $5.5, p75 $13.1) = 0.125 ADR + gap/4. Keberangkatan dari EQ ~19/hari,
                 balik ke EQ median 5 mnt. Sebelum balik ke EQ harga menempuh >= 25% 61%, >= 50% 36%, >= 75% 25%, sampai T0 19%
                 (median jauh 33% = ~$3.4).
               - Candle CLOSE melewati f, masuk open berikutnya: T0 duluan 34.7 / 57.1 / 79.9% vs geometri posisi masuk
                 35.3 / 58.0 / 81.3 (f 25/50/75%) = selisih -0.6..-1.4 poin, EQ PALSU sama (-0.8..-1.3). Tidak ada ambang
                 "pasti": peluang naik LURUS dengan jarak yang sudah ditempuh. Yang sampai: menit ke T0 median 12/10/3.
               - 9 kondisi (lama tempuh, jam WITA, searah jam-1, lebar EQ->T0, keberangkatan ke-n, T0 sudah disentuh,
                 momentum 15 mnt, gap pagi, sisi): tidak ada CELAH (semua |selisih| < 3 di kedua periode, sama dgn PALSU).
                 Pohon keputusan: daun latih -14..+11 -> uji -2..+2 (hilang). Dagang IKUT/LAWAN di 25/50/75%: R bersih
                 negatif, 0/10 tahun positif (biaya).
               - CATATAN METODE: versi pertama (isi stop di titik f, syarat "candle isi tidak menyentuh EQ") memberi
                 +5..7 poin palsu & daun momentum +25..40 poin -> intip masa depan (membuang isi-lalu-balik di menit
                 yang sama). Versi close + masuk open berikutnya = bersih.
               => Semua garis GoldPro (line_graph, route_table, tembus_garis, t0_touch, eq_t0_progress) = PETA yang
                  TEPAT (geometri ±1-2 poin, waktu ±0.7 poin), bukan sumber arah. Celah arah yang ada (PDH/PDL tembus
                  +3-4, reli emas +1) < biaya scalping.
  [selesai] PANEL "RUTE HARGA [KOKOH]" (3 Okt 2026, permintaan pengguna: "pijakan dari EQ, sekarang menuju T0 / T0
            berhasil, menuju T1 / T1 balik arah menuju T0"; Map\GP_DayMap.mqh RouteLines, di atas ketiga halaman panel):
               - Tangga EQ, T0 & T1..Tn atas/bawah (< 0.03 ADR digabung). Urutan sentuhan dari M1 hari ini (jalur dalam
                 candle naik O-L-H-C / turun O-H-L-C; celah antar candle = melewati). Garis terakhir X: "Berangkat dari X",
                 "X TEMBUS naik/turun" (harga di seberang garis sebelumnya) atau "X BALIK ARAH naik/turun" + jam WITA
                 sentuhan terakhir; "sekarang menuju Y <harga>"; "jalan f% ($a dari $D)"; "Y duluan f% | balik X (1-f)%"
                 (= jarak, teruji eq_t0_progress / line_graph); "sampai Y: 30m | 1j" (GP_TouchTime); "Jejak: EQ>T0+>..".
               - Panel diperbarui tiap menit di semua halaman (RefreshPanel(newMin)); dulu hanya halaman 3.
               - Simulasi 2 Okt 2026 (scratchpad route_sim.py) cocok dengan urutan harga nyata.
  [selesai] POLA PENOLAKAN DI UJUNG KOTAK + "BOLAK-BALIK DULU" (3 Okt 2026, usul pengguna; research\box_reject.py ->
            box_reject.txt, .pkl; kotak cepat SMC_Zones; M5 2017-26, M1 2021-26; jalur di M1, masuk open candle berikut):
               - Pola: candle panjang (badan >= 0.8 ATR) melawan arah di zona 15% ujung kotak, candle berikutnya tidak
                 membuat high/low baru, SL = ujung candle panjang. Menang = geometri jarak: TP EQ 54.3% vs 54.8 (M5),
                 51.9 vs 53.5 (M1); TP ujung seberang 29.0 vs 29.0 / 28.2 vs 28.2; TP 1R 49.4 / 48.1 vs 50. Badan
                 >= 1.2 ATR, c2 searah, SELL/BUY saja: sama (-2..+0.3 poin). Rugi bersih 0/11 th (M5), 0/7 th (M1);
                 2025-26 -$0.40..-1.10 per trade 0.01 lot. "Menang 66%" varian c2 searah = jarak (geometri 67%).
               - Bolak-balik: sejak kotak baru tampil, kembali ke EQ median 2x (M5) / 1x (M1), tapi 36-37% kotak
                 ditinggalkan TANPA pernah kembali ke EQ. Pada posisi awal yang sama, kotak PALSU sama (selisih 0-3
                 poin; M5 kotak asli malah sedikit lebih sering langsung keluar). Kesan "jarang terjun bebas" =
                 sifat gerak acak; 1 dari 3 kotak terjun langsung -> berbahaya tanpa SL (cocok dgn riwayat akun).
  [selesai] POLA HIERARKI KOTAK (3 Okt 2026, usul pengguna; research\box_hier.py -> box_hier.txt, box_hier_A/B.pkl;
            kotak cepat; M1 dalam M5 2021-26 = 471.641 sentuhan, M5 dalam M15 & H1 2017-26 = 175.941; balapan mulai
            setelah candle sentuh close, geometri dari harga close):
               - Sentuh ujung kotak kecil -> EQ kecil duluan: +1.0..1.4 poin di atas geometri, konsisten (M1 7/7 th,
                 M5 10/11) = sedikit balik ke tengah, terlalu kecil untuk spread.
               - Letak di kotak besar (di luar / = ujung besar / dalam / = EQ besar / seberang EQ besar), isi (penuh di
                 dalam / sebagian masuk / di luar), perbandingan tinggi: semua -1.4..+2.9 poin di uji; tidak ada
                 kelompok yang menonjol. Ujung kecil = ujung besar (pertemuan dua ujung) +0.7 (sama dgn rata2).
               - Candle SEBAGIAN MASUK (tusuk keluar, close di dalam) -> masuk lawan, SL ujung tusukan, TP EQ kecil:
                 menang = geometri (M1 33.1 vs 32.9, M5 34.0 vs 34.3), juga saat ujung kecil = ujung besar; rugi
                 0/7 & 0/11 th. 2025-26: SL median $0.84 (M1) / $1.96 (M5), rugi ~$0.36 per trade = biaya.
  [selesai] PETA BIAYA (3 Okt 2026, permintaan pengguna; research\cost_map.py -> cost_map.txt; 12 bln Okt 2025-Okt 2026):
               - Spread broker hampir TETAP $0.17 (p90 $0.17-0.19) kecuali 04:30-07:30 WITA (rollover; p90 $0.35-0.75).
                 Cocok dgn biaya nyata akun (1.073 posisi XAU x ~$0.17 = ~$182 spread; komisi $10.73; swap tercatat $0).
               - Biaya% = (spread + slip $0.20) / gerak 15 mnt: TERMURAH 20:30-23:00 WITA (2.7-3.3%; buka NY & data AS)
                 dan 08:30-09:30 WITA (3.3-3.7%); TERMAHAL 04:00-07:00 WITA (6.1-9.6%) dan 11:30-12:30 WITA (~6.2%).
                 Peringkat slot stabil antar tahun (Spearman 0.90-0.98). Menang minimum utk impas (TP = SL = 1/2 gerak
                 15 mnt): 52.7% (21:30) vs 59.3% (06:00); order limit 51.3% vs 55.9%. Hari: hampir sama (4.2-5.0%).
                 ADR tinggi -> biaya% turun (5.4% -> 3.1%).
               - Trade pengguna: 58% masuk di 1/3 slot termurah, 16% di 1/3 termahal -> JAM sudah cukup baik; bocor
                 utama = JUMLAH trade (38/hari) & target kecil. Dengan TP/SL tetap $X, biaya per trade sama di jam apa
                 pun (~$0.37 pasar / $0.17 limit); impas = 50% + 50 x biaya / X: $1 -> 68.5%, $2 -> 59.3%,
                 $3 -> 56.2%, $5 -> 53.7%, $10 -> 51.9% (pasar); limit $2 -> 54.3%, $5 -> 51.7%.
  [selesai] PANEL "4 JAM BIAYA" (3 Okt 2026, permintaan pengguna; Map\GP_DayMap.mqh PanelPage4, tombol baru indeks 3,
            tombol lain turun satu, Trade = indeks 12 -> GP_TBY_; BTN_N 13). Profil research\cost_profile.py (slot 30 mnt
            JAM SERVER, 12 bln; korelasi peringkat vs 12 bln sebelumnya 0.71) -> WITA otomatis ikut musim AS:
               - SEKARANG murah/sedang/mahal + s/d jam berapa, spread live vs normal $0.17, gerak 15 mnt normal
                 (GP_CP_MOVE x ADR20) & biaya%, blok murah/mahal berikutnya + hitung mundur.
               - Jadwal (musim panas AS): 02:30-07:30 MAHAL (rollover), 08:00-09:30 MURAH (buka Asia), 11:00-12:30
                 MAHAL (Asia sepi), 20:00-23:30 MURAH (buka NY, data AS); musim dingin (mulai 1 Nov) +1 jam.
               - Menang minimum utk impas TP = SL $2/$3/$5/$10, order pasar & limit, dgn spread live; biaya/hari 3 vs 38 trade.
            Kompilasi 17:45 WITA (Main + Validator 0 error).
  [perbaikan] PANEL TRADE TERTIMPA GARIS INDIKATOR (3 Okt 2026, screenshot pengguna): MT5 menggambar objek menurut urutan
            pembuatan -> garis/label GoldPro yang dibuat ulang menimpa panel EA. Experts\GoldPro\GoldPro_Panel.mq5
            RaiseIfCovered(): ada objek baru dari program lain (CHARTEVENT_OBJECT_CREATE / jumlah objek berubah) -> panel
            dibuat ulang (kembali paling depan), maks tiap 1.5 dtk, tidak saat mouse di atas panel. Kompilasi 21:10 WITA.
            21:17 WITA: aturan diperhalus - boleh naik saat mouse DIAM di atas panel; tidak saat mengetik (klik kolom isian
            s/d ENDEDIT, maks 60 dtk), tombol mouse ditekan, atau mouse baru bergerak di atas panel (< 0.8 dtk).
  [selesai] LIMIT HARGA MANUAL di panel Trade (3 Okt 2026, permintaan pengguna; GoldPro_Panel DoManual/ManualInfo):
            baris "Harga [....] [BUY LIMIT] [SELL LIMIT]" di bawah SELL/BUY; isi awal = harga sekarang. BUY LIMIT hanya
            di bawah ask, SELL LIMIT di atas bid (> stops level); SL/TP dari kolom SL$/TP$; klik 2x, pengawal (wajib SL,
            tolak lock, batas trade/rugi/posisi) & kedaluwarsa InpPendingHrs sama dgn rencana. Keterangan: di atas/bawah
            harga, jarak $, peluang harga DATANG dlm 1 jam (GP_TouchTime). Panel 18 baris. Kompilasi 21:17 WITA.
  [selesai] CANDLE RANGE THEORY / CRT (3 Okt 2026, usul pengguna: kotak 1 candle H4 dilihat di M15/M5/M1; research\crt_test.py
            -> crt_test.txt, .pkl; H1/H4/D1 2017-26): C2 sapu high/low C1 lalu close di dalam -> masuk open berikut ke
            ujung seberang / tengah C1, SL ujung sapuan. Menang = geometri jarak: H1 47.4 vs 47.6, H4 48.7 vs 48.2, D1 47.2
            vs 47.1 (ujung seberang); tengah 60.7/61.5/60.5 vs 60.9/60.8/61.2. Varian (close lewat tengah, C2 searah, sapu
            1 sisi, ketiganya, SELL/BUY saja) -0.6..+1.7 poin bila n besar; "75% menang" = jarak (geometri 75-76%).
            R bersih negatif: H1 0/11 th, H4 0-3/11, D1 2-4/11. Tidak dipasang. GOTCHA: candle D1/H4 00:00 server baru ada
            harga ~01:00 -> batas celah masuk 10 mnt membuang hampir semua D1 (61 vs 1.092 kejadian); pakai 90 mnt.
  [selesai] CRT + STOCHASTIC (3 Okt 2026, usul pengguna; research\crt_stoch.py -> crt_stoch.txt): filter Stochastic (5,3,3)
            (14,3,3) (21,5,5) di TF CRT (jenuh >= 80 / <= 20, silang %K-%D balik, keduanya) & di M15/M5 saat masuk; 69 varian
            H1/H4/D1. Hampir semua = geometri (-3..+2 poin); "jenuh" di TF CRT malah sedikit MENURUNKAN menang (momentum
            tembus). 2/69 lolos syarat longgar (H4 + M15 Stoch(5) jenuh: +3.6/+3.5 poin tapi R latih -0.13, 4/11 th; D1 + M15
            silang: n 56 = 5/th, 6/11 th) = sesuai peluang kebetulan dari 69 percobaan; gagal syarat baku (>= 7/10 th, net +
            kedua periode). Stochastic tidak membantu CRT (sama dgn stoch_box.py).
  [selesai] ARAH DI JAM MURAH (3 Okt 2026, usul pengguna; research\cheap_dir.py -> cheap_dir.txt; 2.515 hari 2017-26):
            jendela ASIA 03:00-04:30 & NY 15:00-18:30 server (+ bagian DATA 15:30-16:30, BURSA 16:30-18:30). Naik 50.3-52.0%
            (drift naik emas +0.3..+0.9% ADR per jendela; Asia t 2.6 = reli emas, bersih + hanya 3/10 th). Ikut posisi vs
            open / EQ, 60 mnt terakhir, sesi London, hari kemarin, 15 mnt pertama: searah 47.4-50.9% (semua |t| < 2.1).
            0 aturan lulus (bersih + kedua periode & >= 7/10 th). Jam murah = biaya kecil, BUKAN arah.
  [selesai] STOCHASTIC: BELOKAN & TEMBUS GARIS SEBERANG di JAM MURAH (4 Okt 2026, usul pengguna; research\stoch_turn.py ->
            stoch_turn.txt, .pkl; M1 & M5, (5,3,3) & (14,3,3), 2017-26, ~1 juta belokan/silang):
               - Cara kerja: %K mulai melengkung dari < 20 -> median berhenti di ~30 (14,3,3) / ~60 (5,3,3); sampai >= 80
                 hanya 15-17% / 26-29%; lengkungan 3-4 candle. Harga dari masuk s/d %K berbelok balik: median -$0.10..-0.38,
                 searah hanya 36-42% (saat lengkungan terlihat, gerak sudah terjadi; keluar juga terlambat).
               - "Langsung tembus" bisa sedikit ditebak dari GARIS-nya: belokan curam / %K di atas %D -> sampai >= 80 23% vs
                 12% (14) & 37% vs 23% (5), sama latih & uji (inersia rata-rata). TAPI harga tidak ikut: dagang kelompok
                 curam kotor -0.04..+0.05, bersih -0.27..-0.71 per trade.
               - Konfirmasi masuk (belok / silang, per zona, per jendela): TP = SL 1 ATR menang 48.5-50.8%; ikut lengkungan
                 s/d belok balik kotor ~0; 0 dari 112 uji lulus, 0-2/11 th +. Garis indikator bisa ditebak, harga tidak.
  [selesai] STOCHASTIC 2 TF: M5 TEMBUS GARIS -> KONFIRMASI M1 (4 Okt 2026, usul pengguna; research\stoch_m5m1.py ->
            stoch_m5m1.txt, .pkl; jam murah 2017-26): pemicu M5 %K tembus 20 (keluar jenuh) / 50 / 80 (garis seberang),
            konfirmasi M1 dlm 5 candle (silang %K-%D, belok, sudah searah) vs tanpa; keluar 1 ATR M5, $5 maks 60 mnt, atau
            ikut lengkungan M5. Menang 48.3-52.3% (acak 50); konfirmasi M1 mengubah -1.3..+0.5 poin; bersih negatif
            hampir semua tahun (maks 1/11); 0 dari 72 uji lulus.
  [selesai] PANEL "5 CEK SIAP" (4 Okt 2026, permintaan pengguna: satu tombol rekap konfirmasi, singkat padat; GP_DayMap
            PanelPage5, tombol indeks 4, tombol lain turun satu, Trade = indeks 13 -> GP_TBY_; BTN_N 14; RtLadder dipisah
            dari RouteLines). Cek KONDISI, bukan arah: [v]/[x] Biaya (blok jam murah + spread live), Gerak (rentang 1 jam
            >= DMInpCekMinMove $10), Lokasi (garis GoldPro terdekat bawah/atas = BUY/SELL LIMIT + peluang DATANG 1 jam >=
            DMInpCekMinTouch 40%), Berita (data PENTING AS dlm DMInpCekNewsMin 30 mnt / 5 mnt sesudah), Diri (riwayat akun
            hari ini, hanya dibaca: tanpa SL, lock, >= DMInpCekMaxLossRow 2 kalah beruntun, >= DMInpCekMaxTrades 3 trade,
            posisi/order terbuka). Kesimpulan ">> SIAP" / ">> TUNGGU: alasan" (urutan Diri > Berita > Biaya > Gerak >
            Lokasi) + pengingat SL = TP $5, limit, maks 60 mnt. Kompilasi 4 Okt 17:24 WITA (Main + Validator 0 error).
  [selesai] PILIH HARGA DI CHART di panel Trade (4 Okt 2026, permintaan pengguna: seperti +PIN tapi untuk order;
            GoldPro_Panel SnapPx/PickPreview/PickClick): tombol "PILIH HARGA DI CHART" -> garis pratinjau mengikuti mouse
            (biru BUY LIMIT di bawah harga / merah SELL LIMIT di atas, otomatis), MENEMPEL ke garis GoldPro (BuildLines) bila
            <= max($0.5, 1% ADR), keterangan harga, nama garis, peluang DATANG 1 jam, SL/TP. Klik 1 = kunci (garis tebal),
            klik 2 di garis yang sama <= 5 dtk (+-10 px) = kirim lewat DoManual (pengawal, wajib SL, kedaluwarsa sama);
            klik tempat lain = pilih ulang; tombol lagi = batal; mati sendiri 2 mnt tanpa aktivitas / panel ditutup.
            Klik di panel & kolom tombol GoldPro diabaikan. Panel 19 baris. Kompilasi 4 Okt 17:31 WITA (0 error).
            17:37 WITA: tooltip MT5 "GPT_PKL <harga>" (garis pratinjau selalu di bawah mouse) dimatikan (OBJPROP_TOOLTIP "\n").
  [selesai] PANEL TRADE DITATA ULANG + RADAR (4 Okt 2026, permintaan pengguna: buka/kelola posisi tanpa menu MT5; garis
            beli/jual + SL/TP hasil olahan proyek, bisa tampil/sembunyi). Kompilasi 19:07 WITA (Main, Validator, Panel 0 error).
            EA GoldPro_Panel:
               - JENIS: LIMIT (BUY bawah / SELL atas harga) / STOP (BUY atas / SELL bawah = ikut tembus) - berlaku utk kolom
                 Harga & PILIH HARGA DI CHART (DoOrder; validasi sisi; pengawal, wajib SL, kedaluwarsa sama).
               - POSISI & ORDER: maks 3 baris posisi/order simbol ini (SL "TIDAK" merah) + TUTUP / BATAL per baris, TUTUP
                 SEMUA POSISI / BATAL SEMUA ORDER (klik 2x; menutup selalu boleh walau pengawal BERHENTI).
               - RENCANA di panel dihapus (pindah ke RADAR); PENGAWAL dipadatkan (3 baris + STATUS). Panel 18 baris.
               - Klik garis RADAR (GPM_RDR_B / GPM_RDR_S) = kunci (garis emas tebal + bunyi), klik lagi <= 5 dtk = kirim
                 LIMIT di harga garis itu. SL$/TP$ panel diterbitkan ke GV GP_EASL_/GP_EATP_<chart> untuk radar.
            Indikator GoldPro: tombol "Radar" (indeks 5; tombol lain turun satu; Trade = 14; BTN_N 15), RadarDraw/RadarUpdate
            (Rebuild + tiap 5 dtk dari OnCalculate): garis BUY LIMIT di garis GoldPro terdekat di bawah & SELL LIMIT di atas
            (gap >= max(0.02 ADR, $1)), SL/TP (SL$/TP$ EA atau DMInpCekSLTP), teks "RADAR .. | 1j xx%"; berwarna bila semua
            CEK SIAP OK & datang 1j >= DMInpCekMinTouch, abu-abu + "TUNGGU: alasan" bila tidak. CekCompute dipisah dari
            PanelPage5 (struct CekRes) agar radar = CEK SIAP. Peta, bukan sinyal arah (TP = SL -> ~50%).
            19:20 WITA: teks radar ANCHOR_RIGHT_LOWER (berakhir di ujung garis; dulu terpotong tepi kanan chart).
  [selesai] SL / TP DI CHART di panel Trade (5 Okt 2026 07:21 WITA, permintaan pengguna; GoldPro_Panel SlTp*): tombol
            "SL DI CHART" / "TP DI CHART" -> garis pratinjau merah / hijau mengikuti mouse (menempel ke garis GoldPro).
            Sasaran: posisi pertama simbol ini -> order tertunda pertama -> bila tidak ada, kolom SL$/TP$ (jarak dari
            kolom Harga / harga sekarang, 1 klik). Posisi/order: klik 1 = kunci, klik 2 = UBAH (PositionModify /
            OrderModify), dicek ulang sebelum dikirim. SL/TP di sisi salah ditolak; InpBlockWidenSL (default true): SL posisi
            tidak boleh digeser menjauh dari harga masuk. Panel 19 baris.
            Perbaikan: baris kosong POSISI & ORDER menulis "Label" (teks kosong MT5) -> " ". Probe indikator tidak lagi
            digambar di atas panel Trade EA (EA terbitkan GP_EAPW_/GP_EAPH_) atau saat mode pilih di chart (GP_PICKON_).
  [selesai] SETTING HP "RSI(1000) + MACD(10,22,4) + MA(1), LEVEL 10/15/50/85/90" vs GARIS GOLDPRO (5 Okt 2026, usul
            pengguna; research\macd_zone.py -> macd_zone.txt, .pkl; M5 2017-26): RSI(1000) ~50 = kanvas level; MACD diskalakan
            sendiri ke tinggi jendela -> level = posisi MACD di antara min-max N candle yang tampil (direplikasi N 40 & 100).
               - "Gerakannya sama?": TIDAK. Korelasi pos MACD vs posisi harga thd EQ -0.01 / 0.00; di semua zona tangga
                 GoldPro (di bawah T1- s/d di atas T1+) median pos 42-57 & zona BUY/SELL 12-29% (merata). MACD = momentum
                 N candle terakhir, garis GoldPro = level harian -> mengukur hal berbeda.
               - Sinyal ZONA / FULL / BALIK (8-15 per hari!): TP = SL $5 menang 45.7-50.8%; cara setting (tutup saat pos 50)
                 bersih -$0.30..-0.97/trade; TP garis GoldPro 46.8-51.6% (acak 50). Tepat di garis GoldPro / jam murah tidak
                 lebih baik. 0/10 th positif (maks 1/10), 0 lulus.
  [ubah] BATAS TRADE HARIAN DIMATIKAN (5 Okt 2026 10:55 WITA, permintaan pengguna): EA InpMaxTradesDay default 0 (tanpa
            batas); indikator DMInpCekMaxTrades default 0 (CEK SIAP "Diri" tidak lagi STOP karena jumlah trade; 0 ditangani).
            Pengaman lain tetap: wajib SL, tolak lock, batas rugi harian, maks posisi terbuka, 2 kalah beruntun (CEK SIAP).
  [selesai] ML TERBAIK (LightGBM) + PETA GOLDPRO, WALK-FORWARD 2020-26 (5 Okt 2026, usul pengguna; research\ml_wf.py ->
            ml_wf.txt): 42 bahan (dir_ml + 11 bahan peta GoldPro), latih ulang tiap tahun, ambang "paling yakin" dari tahun
            sebelumnya, masuk open candle berikut, 1 posisi sekaligus, spread + slip $0.20:
               - AUC 0.51-0.53 (sedikit di atas koin). 2% paling yakin MENANG 56-62% (ada sedikit informasi arah), tapi gerak
                 kecil: kotor +$0.19 (M5 15 mnt) .. +$1.06 (M15 4 jam) per trade 0.01 lot.
               - Bersih: M5 15m -$0.31 (0/7 th), M5 1j -$0.01 (3/7; 2026 -$0.64), M15 1j -$0.15 (2/7), M15 4j +$0.56 (3/7,
                 positif total hanya karena 2026 +$4.09 x 108 trade). 10% paling yakin: negatif hampir semua tahun. 0 lulus.
               - Bahan peta GoldPro menaikkan AUC +0.003 (0.5200 -> 0.5231, 0.5169 -> 0.5202): membantu sedikit, tidak cukup.
            Tidak dipasang (tidak lolos & 2026 memburuk utk M5). Jalur bila diteruskan: model ONNX di MQL5 mode BAYANGAN
            (hanya jurnal, tidak tampil) utk uji maju.
  [selesai] SEMUA JENIS ML (13 + ensemble) MENEBAK ARAH (5 Okt 2026, usul pengguna; research\ml_zoo.py -> ml_zoo.txt; M5,
            latih 2017-21, ambang 2022, uji 2023-26): Regresi Logistik, Naive Bayes, SVM, KNN, Decision Tree, Random Forest,
            Extra Trees, HistGB, LightGBM, XGBoost, MLP, LSTM (urutan 32 candle), CNN-1D; target 15 mnt / 1 jam / balapan 1 ATR.
               - AUC 0.502-0.520 semua; boosting terbaik (0.519); jaringan saraf (MLP/LSTM/CNN) TIDAK lebih baik; balapan 1 ATR
                 ~acak (<= 0.508). 2% paling yakin menang 54-62% (1 jam), kotor +$0.1..+0.96, bersih -$0.30..+0.56, maks 3/4 th
                 (XGBoost 1 jam +$0.07 3/4; LSTM/CNN + karena sedikit gerak besar 2026, 2/4 th). Tidak ada yang kokoh.
               - POLA KONSISTEN (pohon pengganti, 4/4 th di 2023-26): (1) "BELI SETELAH TURUN TAJAM": harga >= ~1.6-1.7 ATR di
                 bawah EMA20 / di dasar 100 candle / Stoch rendah -> naik 53-56% (15 mnt-1 jam); terkuat sore NY (lewat ~17 jam
                 sejak buka): naik 55.7% (54/59/56/54), kotor +$0.35, bersih -$0.03. Cermin (jual setelah naik tajam) TIDAK
                 konsisten (~50%, efek pasar naik emas). (2) Jam server 23 (sebelum jeda harian) -> naik 1 jam 63% (69/63/63/55),
                 bersih +$0.48 TAPI melintasi jeda/rollover (spread lebar, artefak bid buka ulang yg sudah dikenal) -> tidak dipercaya.
               - Bahan paling dipakai LightGBM: jam, gp_rvr (rentang hari / ADR, peta GoldPro), rezim volatilitas, pos100, EMA200,
                 Stoch, volume, EMA20, momentum 20/50, gp_rpos, gp_up/gp_dn. Tidak dipasang.
  [selesai] FUZZY, GENETIC ALGORITHM, EKONOMETRIKA, HYBRID (5 Okt 2026, usul pengguna; research\fuzzy_ga_econ.py ->
            fuzzy_ga_econ.txt; aturan main = ml_zoo; bedah aturan GA: scratchpad ga_rule_check.py):
               - FUZZY (Sugeno): balik arah klasik AUC 0.509-0.513 menang ~52%; ikut tren 0.486-0.489 (< acak = sedikit
                 balik); belajar Wang-Mendel 81 aturan 0.513-0.516, 2% teryakin 54-55%; bersih negatif 0-1/4 th.
               - AR(12) / ARIMA: AUC 0.509-0.515, bersih negatif 0/4. Autokorelasi M5 lag-1 -17..-49 (x1000) 2017-22 (sedikit
                 balik) -> ~0 di 2023-26. Rasio varians 1 jam 0.85-1.0 (2017-22, balik) -> ~1.0 (2023-26 = acak murni).
               - GARCH(1,1) rentang hari besok: korelasi log 0.829 vs ADR20 0.819 / EWMA 0.824; RMSE log 0.410 vs 0.427 (-4%).
                 SEDIKIT lebih tepat dari ADR20 -> kandidat uji: apakah ADR versi GARCH memperbaiki kalibrasi peluang GoldPro.
               - HYBRID LightGBM + AR: AUC 0.5178 vs 0.5184 (tidak menambah).
               - GA (200 x 40 generasi, fitness t-stat 2017-21 = 5.85): aturan terbaik "BUY jam server >= 22:40 bila harga
                 >= 0.70 ADR di atas EQ & >= 0.24 ADR di atas garis GoldPro bawah, tahan 12 candle M5". Bersih + 7/10 th
                 (2020 +4.85, 2023 +5.04, 2025 +3.81, 2026 +11.80; 2021 -0.73, 2022 -1.37 [validasi], 2024 -1.57). 78% melewati
                 JEDA harian -> untung dari celah buka ulang; keluar SEBELUM jeda: negatif kecuali tahun reli. BUY jam sama SEMUA
                 hari kotor + tiap tahun (+$0.06..+2.30) = DRIFT MALAM emas (sudah dikenal), < biaya kecuali 2025-26; spread jam
                 itu median $0.33-0.35 (p90 $0.55). = efek pasar naik emas, bukan scalping; tidak dipasang (hipotesis).
  [selesai] BEDAH TEMUAN GA (5 Okt 2026, permintaan pengguna: arah, pucuk / lower low, pakai di TF kecil; research\ga_drift.py
            -> ga_drift.txt, .pkl; 2.435 hari 2017-26; kekuatan hari = (harga 22:40 server - EQ)/ADR):
               - Sumber untung (Senin-Kamis, hari NAIK KUAT): pra-jeda 22:40->tutup +$0.73, celah buka ulang kecil (+$0.13 bid
                 / +$0.21 harga tengah), Asia pagi 01:15-04:30 +$2.58 - TAPI Asia pagi naik di hampir SEMUA jenis hari (TURUN
                 KUAT +$2.83) & didominasi 2025-26 (2026 +$24 / +$19) = drift naik emas umum, bukan khas aturan GA. Jumat beda.
               - PUCUK: setelah NAIK KUAT, high hari itu ditembus besok 80.7% (semua hari 51.5%); pada JARAK SAMA tambahan
                 +5..14 poin (0.1-0.2 ADR: 87% vs datar 73%; 0.2-0.35: 70% vs 66%; 0.35-0.6: 53% vs 46%) = sedikit momentum.
                 LOWER LOW setelah TURUN KUAT: tidak ada tambahan di luar jarak (efek pasar naik emas).
               - TF KECIL Asia pagi, TP = SL $5: BUY pasar 01:15 menang 55-58% hampir semua jenis hari, tapi spread buka ulang
                 lebar (median $0.39, p90 $0.59) -> bersih -$0.23..-0.48, 1-3/10 th. BUY pasar 03:00 (jam murah, spread $0.31)
                 menang ~50% (drift sudah habis), bersih negatif 0/10. LIMIT di garis GoldPro searah bias 43-55%, negatif.
               => Arah GA = drift naik 2 jam pertama setelah buka ulang (jam MAHAL); hilang saat spread normal. Yang berguna:
                  info "high kemarin cenderung ditembus" setelah hari naik kuat (kalibrasi PDH). Tidak dipasang.
  [selesai] UPGRADE PDH/PDL: PELUANG DITEMBUS S/D TUTUP (5 Okt 2026 20:49 WITA, permintaan pengguna "upgrade"; research\pdhl_break.py
            -> pdhl_break.txt): tabel kelas kemarin x jarak (shrink k=30) diuji jujur: Brier 2022-26 PDH 0.1745 (kelas+jarak) vs
            0.1747 (jarak saja) vs 0.2497 (rata2); PDL 0.1913 vs 0.1911 -> kekuatan kemarin TIDAK menambah, JARAK yang menentukan.
            Dipasang: GDM::PdhlUpdate (tiap 5 dtk) = LiveP(jarak harga -> PDH/PDL dlm ADR, sisa jam) ke globals g_pdhP/g_pdlP
            (GP_TouchTime.mqh; 2 = sudah tertembus hari ini). Label PDH/PDL: "| tembus s/d tutup xx%" / "TERTEMBUS hari ini";
            tooltip + kekuatan kemarin (g_pdCls, keterangan saja). Panel 1 PETA: baris "PDH .. xx% | PDL .. yy%".
  [selesai] SERI "TEKNIK BELUM DIUJI" 1/3: MANAJEMEN POSISI & MODAL (5 Okt 2026; research\trade_mgmt.py -> trade_mgmt.txt;
            pengguna: JANGAN tambah ke bot sebelum seri selesai). M1 2023-26, 5.816 trade (3 entri/hari jam murah, arah acak):
               - Cara keluar (bersih $/trade 0.01 lot): TP=SL $5 maks 60 mnt -0.55 | s/d tutup -0.52 | TP10/SL5 -0.43 | TP2.5/SL5
                 -0.62 | BE +2.5 -0.48 | BE +4 -0.52 | trailing $5 -0.24 | trailing $3 setelah +$3 -0.27 (menang 51.7%) |
                 tutup 50% -0.56 | batas 30 mnt -0.57 (terburuk -$308) | TANPA SL TP2.5 menang 85.9% tapi rata2 rugi -$19,
                 terburuk -$525, -0.87. Semua negatif 2023-25 (trailing + hanya 2026 = tahun tren). Beda = biaya relatif
                 thd besar trade; trailing membiarkan untung berjalan -> beban biaya terkecil.
               - GRID/AVERAGING (+0.01 tiap $3 melawan, maks 5, tanpa SL): menang 95.5% siklus, terburuk -$745, -0.36/siklus.
               - Umur modal $100 (2.000 simulasi; median trade s/d habis | % habis <= 60 trade): trailing ~207-214 | 5-6%;
                 BE 164 | 4%; prosedur TP=SL $5 140 | 6%; TP2.5 131; LOCK 110 | 17%; TANPA SL 80 | 41%; GRID 43 | 58%;
                 ANTI-martingale 35 | 76%; MARTINGALE 15 | 93%. Tanpa keunggulan arah, $100 habis ~140-210 trade apa pun
                 caranya; no-SL / grid / lock / martingale = tercepat (pola riwayat akun pengguna).
  [selesai] SERI 2/3: STRUKTUR TICK (5 Okt 2026; research\tick_micro.py -> tick_micro.txt, .pkl; tick bid/ask asli broker,
            160 hari acak 2024-01..2026-09, jam murah, 184.440 titik keputusan tiap 15 dtk):
               - Imbalans tick naik/turun (10/60/300 dtk), lonjakan laju tick, spread melebar, gerak 60 dtk: korelasi dgn gerak
                 60 dtk / 5 mnt ke depan -0.008..+0.013 (= nol). Desil ekstrem ikut arah: kotor +$0.00..+0.07 per trade.
               - Dagang (beli ASK / jual BID asli + slip $0.10/sisi): bersih -$0.42..-0.54, semua tahun negatif; lawan arah juga.
               - PENTING: spread tick ASLI di jam murah median $0.26 (lebih besar dari kolom spread M1 = $0.17, yang tampaknya
                 nilai TERENDAH dalam candle) -> biaya nyata per trade ~$0.09 lebih besar dari anggapan uji M1 sebelumnya.
  [selesai] SERI 3/3: MUSIMAN + LEVEL MINGGUAN/BULANAN (5 Okt 2026; research\season_levels.py -> season_levels.txt):
               - Bulan: JANUARI +14% ADR/hari (t 2.8, 7/10 th) & DESEMBER +12.5% (t 2.6, 8/9) konsisten 2 periode (musiman
                 emas Des-Jan; harian/beberapa hari, bukan scalping). Tanggal 1-3 +10.5% (t 2.2) = pergantian bulan (sudah
                 dikenal). Hari: Jumat +7.6% (t 2.3), lain lemah.
               - Jam WITA x hari (120 sel): 8 konsisten (kebetulan ~1.4), hampir semua JAM 06:00-07:00 WITA Sen-Kam (= jam buka
                 ulang server 01:00) naik: t 3.8-7.1, 9-10/10 th = drift naik awal Asia (sama dgn temuan GA). Dagang BUY 60 mnt:
                 +$0.13..+0.29 (kolom spread M1) tapi hanya 4-6/10 th; spread tick asli jam itu lebih lebar -> kemungkinan <= 0.
               - Level PWH/PWL, PMH/PML, open pekan/bulan/kuartal: magnet ASLI - PALSU -8.2..+3.4 poin (bukan magnet); tembus
                 dulu 44.9-56.6% vs palsu 46.3-52.5% (tak konsisten). Tidak menambah peta.
            RINGKASAN SERI: tidak ada teknik baru yang memberi keunggulan arah setelah biaya. Yang berguna: (1) TRAILING stop
            menekan beban biaya (-$0.27 vs -$0.55/trade, umur modal ~210 vs 140 trade); (2) bukti angka bahaya tanpa SL/grid/
            martingale; (3) biaya nyata (spread tick $0.26) > anggapan; (4) drift naik jam buka ulang = nyata tapi di jam mahal.
            Belum ada yang dipasang ke bot (permintaan pengguna) - menunggu keputusan.
  [selesai] SISTEM PENGGUNA: LOCK GANTI SL, LALU LEPAS SATU KAKI (5 Okt 2026; research\lock_unlock.py -> lock_unlock.txt;
            entri sama dgn trade_mgmt, spread tick asli, slip $0.20, semua ditutup s/d tutup hari):
               - Bersih $/trade | umur modal $100 (median trade | % habis <= 60): SL $5 biasa -0.61 | 126 | 13%; LOCK s/d tutup
                 -0.84 | 96 | 21%; lepas lawan saat +$5 & posisi awal tanpa SL -1.34 | 52 | 56% (menang 69% tapi terburuk
                 -$520); + SL $5 lagi -0.92 | 81 | 36%; lepas posisi awal & ikut tren -0.82 | 96 | 25%; lepas lawan saat harga
                 balik $2.5 -1.08 | 73 | 42% (terburuk -$233); lepas lawan di garis GoldPro -1.31 | 52 | 56% (terburuk -$517).
               - Trade yg sampai -$5: SL biasa -5.67 selesai 15 mnt (median); semua cara lock -6.09..-7.14, tertahan 2.5-8.5 jam.
                 SEMUA cara lock lebih buruk dari SL, tiap tahun 2023-26. Sebab: lock = rugi beku (eksposur bersih 0 = sama
                 dgn tutup) + spread & slip ke-2; melepas satu kaki = entry arah baru 50/50 -> hasil = SL + entry ulang,
                 hanya lebih mahal; "lepas lawan" mengubah rugi kecil pasti jadi peluang rugi besar (pola riwayat akun).
  [selesai] SISTEM GOLDPRO DI CRYPTO: BTCUSDT BINANCE FUTURES (5 Okt 2026; research\crypto\crypto_test.py -> crypto_test.txt;
            data M1 resmi data.binance.vision 2020-01..2026-09 (152 MB, crypto\zip\, btcusdt_m1.pkl); kode sama utk emas & BTC;
            hari BTC = 00:00 UTC (08:00 WITA); fee VIP0 taker 0.05% + slip 0.005%, maker 0.02%; funding tidak dihitung):
               - PETA PINDAH SEMPURNA: % tersentuh T0..T4 hampir sama (T1 salah satu emas 99 / BTC 94, kedua 36 / 33; T2 74 / 67).
                 Peluang live (cara LiveP, tabel 250 hari) BTC uji 2022-26: selisih tampil-nyata rata2 0.4 poin (emas 0.8),
                 Brier 0.128 vs 0.199. -> peta GoldPro = penggaris volatilitas, berlaku di pasar lain.
               - ARAH: close tembus T0 -> T1 dulu vs EQ dulu: BTC -0.1..-1.7 poin dari peluang wajar, garis PALSU sama
                 (-1.2..-3.2) -> tidak ada keunggulan arah, sama seperti emas. Ikut/lawan -0.14..-0.24 R bersih, 0 tahun +.
               - BIAYA (R = SL 0.1 ADR): BTC pasar 0.28-0.35 R (2023-26), limit-masuk 0.19-0.24 R; emas 0.21 (2024) ->
                 0.13 (2025) -> 0.06 R (2026, ADR emas $105 = 2.3% harga, spread tetap kecil). Kini EMAS jauh lebih murah.
               - Manajemen (3 entri/hari arah acak, risiko $5/trade), 2025-26: emas TP=SL -$0.44/trade (umur $100 164 trade),
                 trailing -$0.27 (232); BTC pasar TP=SL -$1.46 (57), trailing -$1.67 (53); BTC limit -$0.91 (91); LOCK
                 terburuk di kedua aset. Di BTC trailing TIDAK membantu (biaya relatif besar).
               - Jam BTC termurah (gerak 60 mnt / biaya): 21:00-00:59 WITA (pembukaan AS) & 08:00; termahal ~11:00-14:00.
                 Drift jam: 06:00 WITA naik (t 2.9, konsisten latih/uji; mirip drift emas jam 06-07) tapi bersih negatif.
               - KESIMPULAN: sistem bekerja sama di BTC (peta tepat, arah 50/50), tapi scalping BTC di Binance 2-5x lebih
                 mahal per trade daripada emas saat ini. Tidak ada alasan pindah ke crypto.
  [selesai] DRIFT 2 JAM SETELAH BUKA ULANG UTK MELEPAS SELL DARI LOCK (5 Okt 2026; research\reopen_release.py ->
            reopen_release.txt; jarak $ akun pengguna diubah ke ADR (ADR20 $88.9) & diuji semua hari 2017-26):
               - 2 jam setelah buka ulang: naik 59% hari (Sel-Jum 61%, Senin 53%; 2026 hanya 52%), rata2 +$2.5..3.0 per 0.01,
                 median +$0.2..2.1, sebaran (sd) $11-18 -> drift kecil dibanding goyangan. Jam 10:00 / 16:00 server: 51-52%.
               - Lepas 2 SELL (sisa BUY 0.02, stop out setelah turun $11.2, impas total setelah naik $14.5): 2025-26 stop out
                 28% dalam 2 jam, impas dulu 25% vs stop out dulu 26% (2026: 22% vs 29%). Lepas 1 SELL (BUY 0.01): stop out
                 9%, impas dulu 8%, sisanya masih rugi mengambang. Jam buka ulang memang jam terbaik (jam lain stop out 35-61%),
                 tapi tetap = koin dengan sisi buruk akun habis.
  [diubah] EA GoldPro_Panel: BATAS RUGI HARIAN DIHAPUS (6 Okt 2026 13:41 WITA, permintaan pengguna "hapus aja dulu batas rugi,
            nanti kalau modal sudah besar baru itu diterapkan"). Penyebab tombol BUY/SELL "tidak merespon": PENGAWAL menolak semua
            order karena rugi hari itu -$24.75 > batas 10% saldo awal ($5.47). Kini InpMaxLossDay 0 = tanpa batas (isi angka $ di
            input EA untuk memasang lagi). Pengaman lain TETAP: klik 2x, SL wajib, tolak lock/hedge, maks 2 posisi/order.
  [selesai] AKURASI INTEGRASI BERITA (6 Okt 2026; research\news_accuracy.py -> news_accuracy.txt; CalendarFull 2017-2026,
            3.276 menit rilis penting USD, jam dikoreksi DST):
               - JAM: candle M1 terbesar di +-3 mnt = menit rilis 49% (+1 mnt 15%, +2 13%; sebelum rilis 15%; acak 14%/menit),
                 musim panas 48% / dingin (dikoreksi) 51% -> jam kalender & koreksi DST tepat.
               - PERKIRAAN DORONGAN dashboard: di periode asal (Agu25-Sep26) lewat batas 1-dari-10 12.3%, urutan jenis
                 Spearman 0.89; DI LUAR periode asal (2017-Jul25) lewat 23% (harus 10%), urutan 0.52 -> batas "1 dari 10"
                 terlalu kecil (Retail Sales 64%, ISM jasa 49%, PPI 43%, ISM manuf. 42%, klaim 34%); sampel asal kecil (n 8-13).
               - BUG: NBExpect mencari "Nonfarm" lebih dulu -> "ADP Nonfarm Employment Change" diberi angka NFP (16.3% ADR);
                 nyata ADP 6.9% vs NFP asli 22.8% ADR (angka 16.3% = campuran keduanya). -> DIPERBAIKI (lihat di bawah).
               - CAKUPAN gerak besar 5 mnt (>= 0.25 ADR, 0.45/hari): dekat rilis penting 38%, rilis sedang 10%, jam panas NY 6%,
                 TANPA jadwal 47%. Per tahun tanpa jadwal: 2021-24 27-40%, 2020 71% (COVID), 2025 63%, 2026 64% -> rezim
                 sekarang digerakkan berita mendadak (geopolitik/tarif/bank sentral) yg tidak ada di kalender MT5.
  [diubah] DASHBOARD BERITA: PERKIRAAN DORONGAN DIKALIBRASI ULANG (6 Okt 2026 15:41 WITA, permintaan pengguna "perbaiki dan
            lengkapi"; research\news_calib.py -> news_calib.txt, news_calib_mql.txt; Signal\GP_NewsBoard.mqh NBExpect/NBAdd):
               - 11.577 menit rilis (sedang+penting) & jam panas NY 2017-2026; tiap menit = jenis berita terkuat (median &
                 1-dari-10 kini SEPASANG dari jenis yang sama, dulu max terpisah). 48 kunci / 37 jenis + cadangan per jam NY.
               - Uji walk-forward 2020-2026 (tabel dari data sebelum tahun uji): jendela "semua data sebelumnya" + susut k=15
                 terbaik: lewat batas 1-dari-10 10.5% (ideal 10; per tahun 6-13%), di atas median 50.6%, pinball q0.5 14.1 /
                 q0.9 9.2 vs tabel lama 13.5% / 42.6% / 17.8 / 13.1. 12 bln terakhir: lewat batas 7.6%, > median 44% (kini
                 sedikit kebesaran: ADR 2025-26 membesar oleh berita mendadak).
               - Perbaikan: ADP 6.3% ADR (dulu dapat angka NFP 16.3%); NFP asli 20.7% / 1-dari-10 47.9%; "Fed Chair" ganti
                 "Powell"; "Nonfarm Productivity" tidak lagi dianggap NFP; jenis baru GDP, Durable Goods, Philly Fed, Empire,
                 Michigan, perumahan, lelang obligasi, notulen FOMC, Beige Book, pejabat Fed, dll; jam panas NY tanpa rilis
                 (NYSE 09:30 3.0% / 10:00 NY 3.3% ADR) kini tampil dengan +/-$.
  [selesai] KONSISTENSI MENIT RILIS (6 Okt 2026; research\news_minute.py -> news_minute.txt; kalender 2017-2026):
               - Data ekonomi terjadwal = jam NY TETAP 97-100% (klaim/CPI/NFP/PPI/GDP/Retail/Philly/Empire 08:30, ADP 08:15,
                 S&P PMI & Chicago 09:45, ind. production 09:15, ISM/JOLTS/CB/Michigan 10:00, FOMC & notulen 14:00, konpers
                 14:30, lelang 13:00); yang bergeser TANGGAL (NFP Jumat pertama 82%). Pengecualian: EIA minyak 10:30 Rabu 84%
                 (minggu libur Kamis 11:00), PCE 08:30 90% (kadang 10:00), pejabat/ketua Fed bicara = jam acak (6-29%).
                 WITA = NY + 12 jam (musim panas AS) / + 13 jam (mulai 1 Nov). 1 catatan 07:30 per jenis = salah jam di
                 minggu pergantian DST (abaikan).
               - Candle M1 terbesar (+-3 mnt) di menit rilis: CPI 87%, NFP 83%, Retail 79%, ISM manuf. 73%, ADP 73%, GDP/Philly
                 71%, klaim 69% (acak 14%). Reaksi TERLAMBAT: konpers FOMC & lelang +1/+2 mnt; EIA 24%. Chicago PMI: -3 mnt
                 22% = rilis ke pelanggan 09:42 (3 mnt lebih awal dari jadwal publik 09:45).
  [selesai+dipasang] BERITA PEMICU SWEEP: PERINGATAN YA, KESEMPATAN TIDAK (6 Okt 2026 16:32 WITA, permintaan pengguna
            "jadikan peringatan sekaligus kesempatan emas"; research\news_sweep.py -> news_sweep.txt, news_sweep_mql.txt):
               - Sweep di menit T..T+5 vs menit sama tanpa rilis: NFP 70% (13%), keputusan Fed 64% (2.5%), CPI 58%, Retail 45%,
                 GDP 42%, ADP 41%, PCE 40%, ISM manuf. 40%, notulen FOMC 38% (2%), ISM jasa 34%, Philly 32%, PPI 29%, konpers
                 27% (2%); kedua periode 2017-21 / 2022-26 searah. CANDLE TUSUK (M1 rentang >= 0.08 ADR, ekor >= 60%): NFP 16%,
                 Retail 16%, ISM 14%, Fed 12% vs 0.1-0.3% biasa (50-100x). Tapi menit rilis hanya 11% dari semua sweep jendela NY.
               - KESEMPATAN diuji: jaring BUY/SELL LIMIT 2 mnt sebelum rilis di p0 -/+ k x dorongan median (k 0.5-3, TP 0.5/1 x d,
                 SL d lagi, spread berita >= $0.50): SEMUA rugi di latih 2017-21 (-$0.25..-1.17/event); terbaik k=3 di uji
                 2022-26 -$0.40/event, 1/5 th +. Per jenis tidak ada yang + di latih & uji (ADP k3 +0.02/+0.31 = ~8 order,
                 kebetulan dari 26 uji). Bersama uji lama (ikut/lawan/straddle/kejutan rugi) -> TIDAK ada kesempatan entry berita.
               - DIPASANG (Signal\GP_NewsBoard.mqh): baris "SWEEP 6 mnt x% (tanpa berita y%) | tusuk z%" (merah >= 35%, oranye
                 >= 20%) s/d T+5; daftar: tag "sw70%" & merah utk pemicu kuat; alert 15 mnt kini juga utk berita "sedang" dgn
                 sweep >= 30% (notulen FOMC) + isi sweep % & dorongan $. Kesempatan sengaja tidak ditampilkan (tidak presisi).
  [selesai] EQ -> M (TENGAH EQ & T0) SETELAH MENINGGALKAN EQ (6 Okt 2026, permintaan pengguna; research\eq_mid.py -> eq_mid.txt;
            ~19 keberangkatan/hari, 45.268 peristiwa + EQ PALSU; EQ->M ~0.0625 ADR = ~$5.5 sekarang):
               - SERING: sampai M sebelum balik ke EQ 35.6% (PALSU 36.3%; latih = uji); keberangkatan pertama hari itu 43%;
                 s/d tutup hari 91%; yang sampai: median 3 mnt (p75 8).
               - AKURAT (masuk open candle berikut): M dulu vs balik EQ 31.1/30.9% vs wajar 31.0/30.3 (selisih +0.2/+0.5; PALSU
                 0.0/+0.1); M vs M seberang 64.9/65.1 vs 65.4/65.1. Per tahun -1.4..+2.2. 7 kondisi (sesi, keberangkatan ke-n,
                 kekuatan candle, menit sejak open, lebar, menuju open/close kemarin, sisi) semua |selisih| <= 2 = PALSU.
               - DI M: lanjut ke T0 dulu 51.1/53.0% vs PALSU 51.8/52.7% (= geometri). [versi pertama 13.8% = bug indeks relatif,
                 diperbaiki sebelum dibaca.]
               - DAGANG: IKUT TP M SL EQ -$0.77, SL M seberang -$0.73, LAWAN -$0.70 per trade; 0/10 tahun +.
               => M = penanda jarak yang TEPAT (peluang = jarak yang sudah ditempuh), bukan penentu arah. Tidak dipasang.
  [selesai] "AGAR PUNYA ARAH" - 4 JALAN (6 Okt 2026, pengguna: "kerjakan semuanya"):
            Ambang: menang >= 50 + 50 x biaya / target (TP=SL $5, biaya $0.46 -> 55%); semua uji lama 49-51%.
            (4) JURNAL forward test (evaluate_journal.py, 6 hari s/d 6 Okt, BELUM bisa dipercaya < 20-40 hari): peluang peta
                Brier 0.107 vs 0.245 (+56%), minggu ini tampil sedikit terlalu rendah (+4..6 poin, pasar ramai); 'duluan'
                tampil 51.7% atas vs nyata 53.3%; setup live n 2-13 (tak bermakna).
            (2+3) GABUNG CELAH LEMAH + EKSEKUSI TERMURAH (research\weak_stack.py -> weak_stack.txt; titik :00/:30 server,
                BUY, balapan +-X 0.04/0.06/0.10 ADR, maks 120 mnt; 7 celah: buka ulang Sel-Jum, kemarin naik kuat, awal/akhir
                bulan, Des-Jan, turun tajam M5, close kemarin dekat low, Jumat; logistik dilatih 2017-21):
               - Sendiri (uji 2022-26, X 0.06): hanya buka ulang 56.7% (latih 50.2%!), Des-Jan 51.4%, Jumat 51.4%; lainnya ~50.
               - Gabung: skor 3-4 -> 51-54% naik dulu; logistik >= 0.53 -> 52-56% (n kecil). Bersih PASAR & LIMIT negatif di
                 semua kelompok, 0-1/5 th +. LIMIT (tanpa slip) tidak menolong: terisi saat harga turun = seleksi buruk.
               - Rezim 2025-26 (ADR besar, ambang 53-56%): satu-satunya + = BUY buka ulang X 0.10 ADR pasar +$0.46 (1x/hari
                 +0.22; +kemarin kuat +0.75) TAPI per tahun 2017-21 -0.9, 2022 -0.5, 2023 +0.16, 2024 -0.19, 2025 +0.57,
                 2026 -0.24 (1x/hari) & "naik dulu" 64-85% di beberapa tahun = JEBAKAN SPREAD buka ulang (bid tertekan lalu
                 naik saat spread normal). -> TIDAK lolos.
            (1) ANTAR-PASAR: SUDAH diuji 1 Okt (im_tests.py, broker 2017-26: menit berikutnya |r| <= 0.009, 340 sinyal tak
                kokoh) - saya sempat keliru menyebut belum. Cek independen Dukascopy (EURUSD/USDJPY/XAUUSD Okt25-Sep26,
                research\cross\) -> HASIL (7 Okt; cross_lead.py -> cross_lead.txt; Dukascopy M1 Okt25-Sep26, server lambat
                ~22 dtk/file -> dipersempit ke 3 instrumen x 12 bln): korelasi menit sama EURUSD +0.35 / USDJPY -0.21, dolar duluan
                1 mnt |r| <= 0.011 (praktis nol); kejutan dolar z>=3-5: emas menit itu searah 72-87%, SESUDAHNYA 47-51% (koin);
                "emas tertinggal 5 mnt": korelasi -0.03/-0.02, 1% terbesar mengejar 52/51% (uji n 137), 15 mnt berbalik
                negatif -> tidak kokoh. SAMA dgn im_tests 1 Okt: tidak ada pasar lain yg mendahului emas.
  [selesai] OB BULLISH/BEARISH, BREAKER, FVG + PENDUKUNG: HARGA BERBALIK DI SITU? (7 Okt 2026, permintaan pengguna;
            research\smc_react.py -> smc_react.txt, .pkl; replika PERSIS SMC_Structure/SMC_POI sesudah audit 30 Sep; M5/M15/H1
            dari M1 2017-26; sentuhan pertama dicari di M1, masuk tepi dekat / harga buka bila menit itu buka di dalam zona;
            pembanding = zona PALSU sama tinggi, lahir sama, digeser 0.5-1.5 ATR):
               - MANTUL dulu (+-1 ATR, acak 50%): OB bullish M5 53.5% (palsu 53.2), bearish 52.0 (52.4); M15 52.5/52.1 (52.0/49.4;
                 bearish latih 54.0 -> uji 50.2); H1 50-51 (palsu 48-50); Breaker 47-52.5 (palsu 48-52); FVG 51-53 (palsu 49-53).
                 Pantul ~52% muncul SAMA di zona palsu = sifat harga (balik kecil setelah datang), bukan kekuatan OB.
               - PENDUKUNG (asli - palsu, poin): OB+FVG -0.4, sapuan likuiditas +0.1, CHoCH 0.0, discount/premium benar +0.4,
                 ekor penolakan 0.0, ukuran -0.8..+0.2, umur +0.1, sesi -1.5..+0.3. OB "sempurna" (FVG + sapuan + D/P) 53.5 vs
                 palsu 52.6. Semua |selisih| <= 1.5 di latih & uji.
               - Tersentuh dlm umur zona: OB 80-91%, Breaker 93-97%, FVG 93-97% (palsu lebih jauh dari harga -> sedikit lebih
                 jarang; uji jarak-sama 2 Okt pijakan_time: OB = level biasa, bukan magnet).
               - DAGANG limit tepi, SL sisi jauh + 0.1 ATR, TP 1R/2R: R kotor NEGATIF semua (-0.01..-0.53), bersih M5 OB -0.52,
                 M15 OB -0.27, H1 OB -0.13; FVG -0.37..-1.73 (SL 0.42 ATR = biaya besar); 0-2/11 th +; ASLI = PALSU.
               => OB/Breaker/FVG = penanda tempat, BUKAN titik balik. Label "Pijakan" tetap berarti "peluang DATANG". Tidak diubah.
  [selesai] PETA JAM & KONDISI OB/BREAKER/FVG (7 Okt 2026, permintaan pengguna; research\smc_map.py -> smc_map.txt; data
            smc_react.pkl + kondisi saat sentuhan): jam WITA, hari, keramaian 60 mnt, ADR terpakai, searah hari, tren 4 jam,
            kecepatan datang, berita +-30 mnt, rezim vol, TF, jam x TF. LOLOS = asli - palsu >= +3 & R bersih > 0 di latih & uji.
               - 162 sel: LOLOS 0. Selisih >= +3 di kedua periode hanya 4 sel (OB 06 WITA +6.4/+4.5, OB M15 15 WITA +6.1/+7.5,
                 M15 20 WITA +3.3/+3.3, ...) ~ sebanyak yg diharapkan kebetulan dari 162 sel, dan R bersih tetap negatif;
                 24 sel bagus di SATU periode saja (berbalik di periode lain, mis. berita +-30 mnt +3.0 -> -2.9).
               - Pantul lebih tinggi saat RAMAI (OB 55.7/52.4) tapi zona palsu sama (55.0/52.5). R bersih terbaik di uji -0.009;
                 "paling tidak rugi" = H1, ramai, 20-23 WITA (biaya relatif kecil), bukan karena OB bekerja.
               => Tidak ada jam / kondisi di mana OB, Breaker, atau FVG berbalik lebih tepat dari zona acak. Tidak dipasang.
  [selesai] PERILAKU DI OB/BREAKER/FVG TANPA TRADING: LANJUT TREN, TEMBUS PALSU, TEMBUS SUNGGUHAN (7 Okt 2026, pengguna: "jangan
            pakai sistem trade; harga balik & lanjut tren? jika tembus, benar-benar lewat atau 1-2 candle lalu balik?";
            research\smc_break.py -> smc_break.txt, .pkl; 505 rb sentuhan asli+palsu; LANJUT = tepi dekat + 1 ATR searah tren
            sebelum TEMBUS = tepi jauh - 1 ATR):
               - OB M5/M15/H1 setelah sentuhan pertama: LANJUT TREN 66-67% (palsu 65-66), HORMAT BERSIH 53-54% (51-52), sapu
                 sumbu 8%, tembus palsu 1 / 2 / 3+ candle 2.3-2.8 / 0.8-1.0 / 1.0-1.5%, TEMBUS SUNGGUHAN 33-34% (34-35).
                 66% = geometri (tebal zona = bantalan), sama di zona palsu. Breaker 65% = palsu. FVG 57-58% vs palsu 56%
                 (+1.5..+2.3, konsisten latih & uji di 3 TF; kecil, mungkin konteks impuls baru - FVG disentuh dekat lahirnya).
               - SETELAH CLOSE DI LUAR TEPI JAUH: ternyata PALSU (kembali & lanjut tren) hanya 23% (1 candle), 14% (2), 9.5% (3)
                 untuk OB M5; M15 21/13/11; zona palsu SAMA. Harga menyentuh lagi tepi yg ditembus (retest) 60-66% tapi
                 kebanyakan lalu tetap tembus. OB H1 1 candle 24.5% vs palsu 19.1% (latih +4.0, uji +6.7, n 413) = hipotesis lemah.
               - CIRI candle tembus pertama (OB, % palsu; zona palsu sama -> ciri harga umum, bukan khas OB): close lewat < 0.1
                 ATR 29% vs > 0.6 ATR 8%; badan < 0.3 ATR 26.5% vs > 1.2 ATR 19.7%; close dekat zona (ekor balik) 28% vs close
                 di ujung 22%; candle besar 20%; pasar ramai 21% vs sepi 25%; berita 24%. Stabil latih/uji.
               - LAMA (median candle): hormat 1-2, sapu sumbu 3-5, tembus palsu 1 candle 6-8 / 2 candle 9-11 / 3+ 18-26,
                 tembus sungguhan 3-4.
               => Close di luar tepi jauh = biasanya tembus SUNGGUHAN (77-91%); ciri palsu = close tipis + badan kecil + ekor balik.
                  Peluang ini TEPAT (stabil 2 periode) tapi = geometri, bukan kekuatan zona. Belum dipasang (ditawarkan sbg info).
               - Tambahan (tabel detektor, bagian 5): lanjut tren per tebal zona 0-.25-.5-.75-1-1.5-2-3+ ATR: OB 51/56/59/63/66/71/74/81%,
                 FVG 53/57/61/65/68/73/75/85%; palsu setelah 1 close per (lewat x badan) OB 31..10%, FVG 42..14%; 2 close 15/20%,
                 3 close 11/15%; retest tepi 64/67%; SUMBU lewat tapi close di dalam -> lanjut hanya 48% (OB) / 59% (FVG).
  [DIPASANG] DETEKTOR ZONA OB/FVG SEMUA TF - tombol ke-16 "Zona OB/FVG" (7 Okt 2026 06:29 WITA, permintaan pengguna: "detektor di
            chart, satu tombol khusus mengawasi OB & FVG di semua TF termasuk M1, dashboard interaktif yang paling banyak bernarasi";
            Signal\GP_ZoneWatch.mqh; GP_DayMap: g_vZone/GV "zone", BTN_N 16; GoldPro_Main: ZW_Update di timer, ZW_ChartEvent, ZW_Deinit):
               - Deteksi sendiri M1/M5/M15/H1/H4 (CopyRates 1500/1200/800/600/400 candle, dibangun ulang tiap candle baru TF itu) =
                 replika PERSIS mesin GoldPro sesudah audit (fractal 5, swing terbaru, OB asal leg, FVG >= 0.05 ATR, Breaker 90% +
                 close tembus). Cek Python (scratchpad zw_check.py) pada data broker: zona per TF masuk akal.
               - CERITA (jam WITA): zona BARU (tebal ATR, CHoCH/BOS, +FVG, sapu likuiditas, "bila disentuh lanjut ~x%"), harga MASUK
                 (live di candle berjalan + saat tutup), SUMBU lewat close di dalam (48/59%), CLOSE TEMBUS 1/2/3 candle (sungguhan
                 ~x% menurut jauh lewat & badan, retest ~64%), close KEMBALI ke dalam, BERTAHAN (+1 ATR), TEMBUS SUNGGUHAN (-1 ATR).
                 FVG M1 tidak dinarasikan (terlalu sering), hanya di tabel.
               - Dashboard kanan (di bawah Berita): SEKARANG (di dalam zona apa / terdekat bawah & atas semua TF), tabel per TF OB &
                 FVG terdekat bawah | atas (jarak $, peluang datang 1 jam GP_TouchTime), 9 cerita terbaru; klik judul = ringkas.
               - Chart: kotak putus-putus OB/Breaker terdekat tiap sisi untuk TF selain TF chart + label "OB M15" (InpZWDraw).
               - Alert (GP_Notify) sentuhan & close tembus pertama untuk TF >= InpZWAlertMinTF (default 15 = M15/H1/H4).
               - Label jujur di footer & tooltip: peluang = geometri (zona acak sama), INFO bukan sinyal. Compile 0/0; pengguna ganti TF.
               - Log v1 di chart pengguna = replika Python (M5: OB/BRK 5, FVG 7, diuji 2 sama persis).
               - VERSI 2 (7 Okt 06:39 WITA, dari 4 screenshot pengguna): teks keluar kotak -> lebar diukur PIKSEL (TextSetFont/
                 TextGetSize, Consolas skala Windows) + bungkus per kata, lebar maks InpZWMaxWidthPct 48% chart; dashboard tertimpa
                 label peta (T0/Cadangan/EQ/sideway) -> buat ulang ke depan saat objek lain dibuat (CHARTEVENT_OBJECT_CREATE, maks 1x/
                 20 dtk; GPT_/GPB_/GPN_ dikecualikan agar tidak saling dorong dgn EA & probe); terlalu tinggi -> tabel 1 baris/TF (jarak
                 + datang 1j, rentang harga di tooltip), 6 cerita (ringkas 3), kalimat pendek, FVG diceritakan hanya TF >= M15
                 (InpZWFvgStoryMinTF); OB M5 4157.8-4162.4 di chart tapi tidak di tabel -> zona AKTIF kini = belum terisi 90% (sama
                 dgn mesin SMC), dulu dibuang setelah episode sentuhan pertama selesai.
               - VERSI 3 (7 Okt 06:49 WITA, pengguna: "tampilkan sebelah kiri biar tidak menghalangi ujung chart"): dashboard di
                 KIRI (kanan kolom tombol, bawah label LIVE; geser ke kanan panel halaman / panel Trade bila terbuka; InpZWLeft);
                 teks masih terpotong di layar skala ~125% -> lebar & tinggi baris dikali DPI/96 (TERMINAL_SCREEN_DPI); judul tabel
                 dipendekkan (penjelasan di tooltip); probe GoldPro sembunyi di atas dashboard zona.
               - 7 Okt 06:58 WITA: cerita masih terpotong ("close di dalam: l") = BATAS OBJ_LABEL MT5 63 karakter (bukan lebar) ->
                 bungkus kata juga maks 62 karakter/baris (ZW_MAXCH). Detektor cocok dgn kotak SMC M1 (OB atas 4162.9-4164.3).
               - 7 Okt 07:06 WITA: footer dipendekkan (masih kena batas 63); cerita "sumbu lewat, close di dalam" tidak ditulis bila
                 candle yg sama sudah lewat 1 ATR (dulu dua cerita bertentangan di 07:03); TEMBUS SUNGGUHAN lewat sumbu saja diberi
                 keterangan "hanya sumbu, close di dalam".
  [selesai] KONSOLIDASI DI GARIS SMC + STRUKTUR PASAR, TANPA TRADING (8 Okt 2026, permintaan pengguna; research\consol_smc.py ->
            consol_smc.txt, .pkl; KONSOLIDASI = definisi label LIVE (rentang 60 mnt <= 20% tersempit slot NY, CS_P20_60); 11.741
            episode baru 2017-26; struktur & zona = replika GoldPro M5; pembanding = wajar dari jarak):
               - TEMBUS atas dulu 51.6% vs wajar 51.1 (latih 51.3 / uji 52.1); menit sampai close di luar kotak median 16 (p25 6,
                 p75 32). Sesudah tembus: lanjut 1 lebar kotak 39.0% vs balik ke tengah kotak dulu 61% (wajar 40.6) -> tembusan
                 pertama lebih sering kembali ke tengah.
               - STRUKTUR: tren naik -> tembus atas 52.4 (wajar 52.1); tren turun 50.7 (50.0); tembus searah tren 51.0 vs wajar
                 51.1; CHoCH vs BOS terakhir sama. Event M5 berikutnya searah tren 51.0% (latih 49.8 / uji 52.2; semua waktu 48.6).
                 Arah tembus = arah BOS/CHoCH M5 berikutnya 78% (latih 77.9 / uji 78.1) = AKIBAT tembusan, bukan ramalan.
               - LOKASI: kotak di OB/Breaker 22% / FVG 14% / luar zona 64%: tembus atas 51.5-52.3 vs wajar 50.6-51.2; di dalam zona
                 tembus searah zona 55.8 vs wajar 56.7. Discount dalam -> tembus atas 39.0 (wajar 37.0), premium dalam 61.3 (63.2);
                 swing high/low duluan = wajar persis (17.9 vs 17.8 ... 82.8 vs 82.8).
               - Gabungan "paling SMC" (OB/Breaker + searah tren + discount/premium benar): searah tren 41.9% vs wajar 38.9, n 473
                 (t ~1.3) = tidak bermakna.
               => Konsolidasi di garis SMC TIDAK memberi arah di luar geometri. Yang tepat & stabil: waktu tembus (~16 mnt), 6/10
                  tembusan balik ke tengah kotak dulu, BOS/CHoCH berikutnya mengikuti arah tembus. Belum dipasang (ditawarkan).
  [selesai] MELACAK "78%" (8 Okt 2026, pengguna: "coba lacak kebiasaan yg 78%"; research\consol_78.py -> consol_78.txt; [catatan:
            consol_smc.py lambat 18 mnt krn m.t.dt.year dihitung ulang tiap peristiwa - di consol_78 dihitung sekali, 3 dtk]):
               - URUTAN: BOS/CHoCH M5 berikutnya muncul SESUDAH kotak tembus 93.1%, sebelum (swing di dalam kotak patah) 6.9%. Yang
                 sebelum: arah tembus cocok 81.7% tapi wajar dari posisi harga 86.9% (-5.2; latih -2.8 / uji -7.7) -> BUKAN petunjuk dini.
               - KONFIRMASI: muncul median 4 mnt sesudah tembus (p25 2, p75 36), harga sudah 0.26 lebar kotak di luar tepi; 18% sempat
                 balik ke tengah dulu. SESUDAH konfirmasi: lanjut 1 lebar lagi 44.4% vs wajar 45.7 (BOS 42.7/45.3, CHoCH 46.2/46.1).
               - 22% TIDAK COCOK = tembusan GAGAL: 86.9% balik ke tengah kotak (yang cocok 53.6%); separuh event berlawanan = CHoCH.
               - Tembus searah tren lama 51% / melawan 49%; struktur mengikuti tembusan 78% di keduanya (BOS / CHoCH).
               => 78% = mesin struktur MENCATAT tembusan (~4 mnt kemudian), bukan meramal; sesudahnya geometri. Tanda gagal: struktur
                  berbalik atau harga kembali ke tengah kotak.
  [selesai+DIPASANG] POLA "MEPET TEPI KOTAK SIDEWAY -> KELUAR LEWAT TEPI ITU" (8 Okt 2026, pengguna: "yg ini kita cari ... kita bisa
            mendefinisikan dan mendeteksi pola itu"; research\consol_edge.py -> consol_edge.txt; 147 rb sampel tiap 5 mnt selama
            KONSOLIDASI 2017-26, kotak 60 mnt, keluar = close M1 di luar):
               - KALIBRASI per desil posisi harga di kotak: keluar ATAS 12.5/20.6/28.8/37.1/45.9/53.1/61.6/70.2/78.5/87.9% (latih =
                 uji +-1.4) - sedikit di bawah posisi murni (95% -> 88%): tepi sering hanya disentuh sumbu lalu close kembali.
               - Penajam (sentuhan tepi 60 mnt, arah 15 mnt, penyempitan 15/60, ADR terpakai): logloss uji 0.5794 vs posisi saja 0.5793
                 = tidak menambah. Menit sampai keluar: mepet tepi median 4 (p75 14-15), tengah 20 (p75 37-38).
               - SESUDAH keluar lewat tepi dekat: lanjut 1 lebar kotak 39.5% vs wajar 40.0, balik ke tengah dulu 60.5% (latih/uji
                 40.9/38.2). Jarak ke tepi dekat 2025-26 median $0.80, lebar kotak $9.2.
               => TEPAT & STABIL utk "lewat pintu mana keluar" (gerak kecil), bukan arah jauh.
               - DIPASANG di detektor Zona (Signal\GP_ZoneWatch.mqh, compile 8 Okt 16:55 WITA): baris "SIDEWAY xm lo-hi: harga di p%
                 kotak -> keluar ATAS a% | BAWAH b% (~t mnt)" saat KONSOLIDASI (kotak = GDM::g_ms = kotak sideway di chart); cerita
                 "mepet ATAP/LANTAI" (posisi >= 90% / <= 10%, maks 1x/15 mnt/sisi) & "KELUAR ATAS/BAWAH: lanjut ~40% | balik ke tengah
                 ~60%" (close M1 di luar kotak menit sebelumnya). Tabel ZW_CEX/ZW_CMED/ZW_CP75.
                 -> 8 Okt 17:54 WITA DIPINDAH ke tombol khusus "Kotak Sideway" (Signal\GP_BoxWatch.mqh, lihat di bawah); Zona kembali
                    khusus OB/FVG.
  [selesai] SIMULASI ENTRY TANPA SL DI TEPI KOTAK SIDEWAY (8 Okt 2026, permintaan pengguna; research\consol_entry_sim.py ->
            consol_entry_sim.txt, .pkl; 11.7 rb episode, sisi atap & lantai, 6 titik: 80% / 90% / atap / close tembus / retest tepi /
            kembali ke tengah; IKUT & LAWAN; TP 0.25 / 0.5 / 1 lebar kotak; tanpa SL, tutup paksa 240 mnt; spread asli + slip):
               - KENA TP: 0.25 lebar 89-93%, 0.5 lebar 79-82%, 1 lebar 61-63% di SEMUA titik & arah (geometri TP kecil tanpa SL).
               - BERSIH per trade NEGATIF di 36/36 kombinasi (-0.15..-0.36 lebar kotak), 0-1/10 th +. Terbaik: TENGAH-IKUT TP 0.25
                 (93%, -0.148; latih -0.24 / uji -0.05) & ATAP-LAWAN TP 0.25 (92%, -0.155); 2025-26 ~ +$0.16..-$0.03/trade.
               - EKOR TANPA SL (2025-26, 0.01 lot): rugi terburuk -$118..-$164, rugi mengambang maks $129-$209, 90% $14-$33; trade
                 dgn mengambang >= $25 (akun ~$30 stop out) 4.7-5.8% = sekali tiap ~17-21 trade, sementara menang rata2 ~$2.
               => "Presisi" tinggi (90%+) = TP kecil tanpa SL; ekor rugi besar menghapusnya -> pola riwayat akun pengguna. Tidak ada
                  titik masuk yang untung bersih.
  [selesai] SIMULASI ENTRY DI TENGAH KOTAK SIDEWAY DENGAN SL (8 Okt 2026, pengguna: "pakai sl, posisi di tengah, sl di bawah garis &
            sebaliknya tergantung peluang, tp di luar kotak 1-2 candle"; research\consol_mid_sim.py -> consol_mid_sim.txt; limit di
            tengah; arah IKUT-TEMBUS / LAWAN-TEMBUS (kembali ke tengah sesudah tembus) / TREN-M5 (sentuh tengah sebelum tembus, arah
            BOS/CHoCH M5) / ACAK; SL di luar tepi seberang + 1 ATR M1/M5; TP di tepi tujuan / +1-2 ATR M1 / +1-2 ATR M5):
               - MENANG = WAJAR dari jarak di 40/40 kombinasi (selisih -2.3..+2.7; terbaik IKUT-TEMBUS SL+ATR M5 TP tepi 65.7 vs 63.8).
               - R BERSIH negatif semua (-0.25..-0.43R), 0-1/10 th +; latih -0.36..-0.64, uji -0.12..-0.23 (kotak 2017-21 kecil ->
                 biaya relatif besar). 2025-26: -$0.03..-$0.74 per trade, RISIKO per trade $5.2-7.2 (0.01 lot) = 17-24% akun $30.
               => Tengah kotak + SL di luar garis + TP di luar kotak = geometri; tidak ada arah (tembusan, tren M5) yang menambah.
  [selesai] KONSOLIDASI PER JAM: KAPAN, DINDING MANA DITEMBUS, IKUT TREN?, SEBERAPA JAUH TEMBUSAN (8 Okt 2026, pengguna: "deteksi
            peluang candle menembus dinding kotak; sekali tembus tetap tembus walau kembali; konsolidasi ikut tren?; semua jam, arah &
            konsistensi"; research\consol_hours.py -> consol_hours.txt, .pkl; 11.7 rb episode, jam WITA ikut musim AS):
               - KAPAN (% waktu rentang 60 mnt <= 0.112 ADR): 07 WITA 62%, 12 61%, 06 58%, 05 52%, 13 50%, 04 47%, 11 43%, 08 41%;
                 paling jarang 21-23 WITA 1-3%, 00 9%, 20 11%. Episode label LIVE ~40-70/th tiap jam (05-06 ~15, jam buka ulang).
               - ARAH PER JAM: tembus atas = wajar +-2 di hampir semua jam (2 SE = +-4.5). Pengecualian 23 WITA: atas 57.9% vs wajar
                 51.2 (+6.7; latih +5.6 / uji +8.0; 9/10 th; t ~3) = KANDIDAT (1 dari 24 jam, bisa kebetulan ~5%); 03-04 WITA +3.4/+4.6
                 (7-8/10 th) lemah.
               - IKUT TREN? 7 definisi (gerak 60/120/240 mnt sebelum kotak, harga vs open hari, H1 EMA20, D1, struktur M5): tembus
                 searah tren - wajar = -0.1..+0.5 poin -> konsolidasi TIDAK mengikuti tren.
               - SEKALI TEMBUS (close di luar dinding): lewat dinding maks sebelum close kembali di dalam median 0.26 lebar kotak
                 (2025-26 $1.94; p75 $4.94); >= 0.1 lebar 81%, >= 0.25 51%, >= 0.5 30%, >= 1 lebar 16% (latih = uji +-3). Kembali close
                 di dalam kotak dlm 15 mnt 74%, dlm 60 mnt 87%. SESUDAH candle tembus close (bisa diambil): close sudah lewat $0.47,
                 SISA median $1.11 (>= $1 52%, >= $2 36%, >= $5 20%, 2025-26). Lewat terjauh jam 13 & 20-21 WITA ($2.7-3.6 2025-26).
               => Tembus = dorongan pendek yg biasanya kembali ke dalam kotak; arah tak terbaca dari tren; satu-satunya miring = 23 WITA ke atas.
  [selesai] BERTAHAN SESUDAH TEMBUS + KONSOLIDASI DI TENGAH TREN PADA TANGGA GARIS GOLDPRO (8 Okt 2026, permintaan pengguna;
            research\consol_lines.py -> consol_lines.txt; tanpa trading; pembanding garis PALSU digeser 0.06 ADR & wajar dari jarak):
               - BERTAHAN (menit dari close tembus s/d close kembali ke sisi asal): dinding kotak KONSOLIDASI median 3 mnt (p25 0, p75 15),
                 > 5 mnt 38%, > 15 25%, > 60 13%, s/d tutup hari 3%. Garis T0/T1/T2 median 2 mnt, > 5 mnt 37-40%, > 15 25-27%, > 60
                 14-15%, sampai garis berikut sebelum kembali 12-20% - garis PALSU SAMA.
               - KONSOLIDASI SESUDAH TREN KUAT (gerak 120 mnt >= 0.15 ADR, 3.442 episode): tembus LANJUT tren 50.3% vs wajar 49.2;
                 garis berikut dulu 48.4 vs 47.8. Per letak (di T0/T1/T2/T3/EQ, mendekati, baru lewat, tengah): selisih -4.6..+6.7,
                 tanda berbeda latih vs uji kecuali "menuju T3" +5.6/+5.1 (n 181) = hipotesis lemah dari ~15 sel.
               - Kotak konsolidasi memuat garis GoldPro 66.7% vs PALSU 65.7% -> garis bukan tempat berhenti khusus.
               => Konsolidasi di tengah tren = jeda acak, bukan tanda lanjut/balik; tembusan garis/dinding biasanya hanya bertahan menit.
  [selesai] PEMBENTUKAN CANDLE DI DINDING KOTAK: "COLEK BEREKOR, DIKOCOK, LALU TEMBUS" & "COLEK + INSIDE BAR" (8 Okt 2026, pengguna;
            research\consol_poke.py -> consol_poke.txt; COLEK = candle high > dinding tapi close kembali di dalam kotak; tembus = close
            M1 di luar; wajar = posisi close candle colek). [BUG pertama: kolom object campuran numpy.bool_ -> mean() = OR -> "0.0%";
            diperbaiki dgn float()/astype(bool) sebelum dibaca.]
               - M1 (colek sebelum tembus di 44.7% episode): sesudah colek pertama dinding SAMA yg ditembus 85.3% vs wajar 92.8 (-7.5;
                 latih -8.8 / uji -6.2; 0/10 th di atas wajar); dikocok median 4 mnt (p25 1, p75 14). Ekor panjang > 2/3: 83.8 vs 90.1.
                 Colek + inside bar: 82.7 vs 90.7 (wajar dari close inside bar). 1 / 2 / 3+ colek di dinding sama (0 di seberang):
                 90.2 / 91.5 / 92.0 vs wajar 92.8-93.8.
               - M5 (colek di 25.1% episode): dinding sama 76.6% vs wajar 83.3 (-6.7); dikocok median 8 mnt (p75 22); colek + inside
                 bar 71.5 vs 77.6; 1-3+ colek 80-83 vs 84-86.
               => Pengamatan pengguna BENAR: sesudah colek berekor, kebanyakan dinding yg SAMA akhirnya ditembus (85% M1, 77% M5) dalam
                  ~4-8 mnt. Tapi itu terutama krn harga sudah di dinding; ekor justru MENGURANGI ~7 poin dari geometri (penolakan kecil
                  yg nyata & konsisten). Inside bar sesudah colek tidak menambah.
  [DIPASANG] TOMBOL KE-17 "KOTAK SIDEWAY" - dashboard khusus konsolidasi (8 Okt 2026 17:54 WITA, pengguna: "buat tombol khusus, seperti
            yg lain ... buat keterangan/narasi yg jelas, mudah difahami"). Signal\GP_BoxWatch.mqh (prefix GPK_); GP_DayMap: g_vBox / GV
            "box", BTN_N 17, tombol indeks 16, probe tidak muncul di atas GPK_BG; GoldPro_Main: KB_Update di timer, KB_ChartEvent,
            KB_Deinit, bersih GPK_. Fitur sideway di dashboard Zona DIHAPUS (pindah ke sini). Compile 0 error 0 warning.
               - KOTAK = definisi riset persis: 60 candle M1 tanpa celah, rentang <= CS_P20_60[slot NY] x ADR, 60 mnt sebelumnya tanpa
                 kotak. ATAP/LANTAI = high/low 60 mnt itu, DIBEKUKAN saat kotak lahir (garis putus biru/oranye di chart; bisa beda
                 dari kotak abu "sideway x mnt" peta yang ikut bergerak). Mesin jalan terus walau dashboard tertutup; saat indikator
                 dimuat: putar ulang 600 candle M1 terakhir (60 pertama pemanasan) -> cerita langsung terisi.
               - Keadaan: KOTAK AKTIF (s/d 240 mnt) -> posisi harga %, peluang keluar ATAP/LANTAI (consol_edge), ~menit keluar,
                 colek terakhir M1/M5 (85/77%; + inside bar 83/72%, bukan inside 78/60% - consol_poke), dorongan bila tembus (per
                 jam WITA, consol_hours). SUDAH TEMBUS (diawasi 60 mnt) -> menit di luar, lewat dinding maks, bertahan > 15 mnt 25% /
                 > 60 13% (consol_lines), tanda SAH (BOS/CHoCH M5 78%) & GAGAL (close balik, 74% dlm 15 mnt). Tanpa kotak -> % waktu
                 sepi jam ini. Jam 23 WITA -> [HIPOTESIS] tembus atas 58%.
               - Tiap keadaan ada baris "Artinya: ..." (kalimat sederhana, kuning). Cerita (6 / ringkas 3): KOTAK BARU, COLEK (ekor %),
                 INSIDE BAR, MEPET ATAP/LANTAI (live, >= 90% / <= 10%, maks 1x/15 mnt/sisi), TEMBUS, BERTAHAN 15 mnt, KEMBALI.
               - Tampilan kiri (di bawah dashboard Zona bila muat, kalau tidak di kanannya; di kanan panel halaman / panel Trade), klik
                 judul = ringkas/lengkap, maks 62 huruf/baris, lebar piksel x skala DPI, naik ke depan bila tertutup (maks 1x/20 dtk).
                 Input: InpKBDrawLines, InpKBFont. INFO perilaku harga, bukan sinyal arah (arah tembus tetap ~50:50 dari tren).
               - REVISI 18:08 WITA (screenshot pengguna: label LIVE "KONSOLIDASI 240m" tapi dashboard "Tidak ada kotak" - kotak 15:40
                 tembus 15:45, kembali 15:46, lalu pengawasan berhenti 16:45 walau harga masih sideway di kotak yang sama):
                 research\consol_frozen.py (-> consol_frozen.txt): dinding BEKU 240 mnt, sampel tiap 5 mnt harga di dalam -
                 tabel posisi -> keluar atas sebelum tembus / sesudah 1 gagal / sesudah >= 2 gagal: selisih rata2 1.4 / 1.1 / 1.3 poin
                 dari tabel consol_edge (latih = uji). Tembusan ke-1 / ke-2 / ke-3+: bertahan median 4/3/4 mnt, > 15 26/25/25%, > 60
                 13/12/13%, dorongan 0.25/0.24/0.26 lebar, balik <= 15 mnt 74/75/75%. Colek sesudah tembusan gagal: M1 85.1% (= 85.2
                 sebelum), M5 73.5% (76.9 sebelum).
                 -> Kotak kini HIDUP s/d 240 mnt walau ditembus lalu kembali (keadaan: di dalam / di luar), selesai bila 60 mnt di luar
                    ("TEMBUS SUNGGUHAN"); tidak ada kotak hidup & 60 mnt terakhir sempit -> "KOTAK DIPERBARUI" (= sampel consol_edge).
                    Colek sesudah tembusan / kotak diperbarui: M1 85% / M5 74% (tanpa angka inside bar). Tanpa kotak & label LIVE
                    KONSOLIDASI -> dijelaskan (rentang x mnt sempit, 60 mnt belum).
                 -> "Tanda SAH: BOS/CHoCH" DIHAPUS (consol_78: sesudah BOS/CHoCH searah, lanjut 1 lebar 44.4% = wajar 45.7) -> diganti
                    "BOS/CHoCH biasanya muncul (78%) tapi TIDAK membuat tembusan lebih kuat".
                 -> Cerita digabung agar tidak banjir: tembus <= 5 mnt lalu kembali = 1 baris ("TEMBUS ATAS sebentar 3x (ke-3 s/d ke-5)"),
                    colek beruntun dinding sama M1+M5 <= 15 mnt = 1 baris ("COLEK LANTAI berulang (M1 5x, M5 2x)"); inside bar masuk ke
                    baris colek-nya. Simulasi Python data live 8 Okt 08-18 WITA: 19 cerita (kotak 15:40 = 9 baris, 7 tembusan 1 mnt).
               - REVISI 18:50 WITA (screenshot: kotak 18:08 4119.4-4128.5 tembus bawah 18:25, BERTAHAN 15 mnt, lewat $9.46 = tampil
                 benar; tapi dashboard lebih tinggi dari chart -> baris bawah terpotong): KB_Render menyusun ulang dengan cerita lama
                 dikurangi satu per satu sampai muat ("-- cerita (WITA, n terbaru - chart kurang tinggi) --"); bila masih tidak muat,
                 baris sebelum penutup dipotong (penutup "INFO ... bukan sinyal arah" selalu tampil). Saat harga di luar kotak: baris
                 baru "Harga sekarang X = $d di bawah lantai / di atas atap" (atau "sudah di dalam lagi - tunggu close M1").
               - REVISI 20:24 WITA - TARGET + DAFTAR + TAMPILAN RINGKAS (pengguna: "keterangannya ringkas; di bawah kotak sideway
                 yang utama: 18:55 mencolek atas / TARGET menembus dalam 4-5 menit / confidence 85%; setelah lewat dicek tercapai atau
                 tidak; tiap target masuk daftar; sesudah di luar kotak bot terus mengontrol kembali atau berlanjut; garis-garis
                 GoldPro terdeteksi"). KOREKSI: 85% = dinding AKHIRNYA ditembus; 4 mnt = median -> "85% dalam 4-5 mnt" salah.
                 research\consol_target.py (-> consol_target.txt), peluang PER BATAS WAKTU, latih = uji +-1, tiap tahun +-1.5:
                   COLEK M1 -> dinding sama tembus s/d 3/5/10/15/30 mnt 49/58/69/74/80%, akhirnya 85% | COLEK M5 28/36/48/55/64,
                   akhirnya 74 | MEPET >= 90% 45/55/66/72/79, akhirnya 87 | sesudah TEMBUS close kembali s/d 5/10/15/30 mnt
                   59/69/75/82% | LANJUT ke garis GoldPro berikutnya (dari ekstrem candle tembus) sebelum close kembali, per jarak
                   x ADR: <0.01 57% | <0.02 42 | <0.04 32 | <0.06 23 | <0.10 17 | <0.15 13 | <0.25 8 (tabel ADR logloss uji 0.4686
                   vs tabel x lebar 0.4703 vs dasar 0.5187).
                   ALIRAN TARGET persis aturan dashboard (colek M1, kalau bukan colek -> mepet; target baru >= 5 mnt sesudah target
                   sebelumnya; ~9 target / kotak): colek KENA s/d 5 candle 58.6% (latih 58.2 / uji 58.9), mepet 52.1% (51.0/53.5).
                 -> GP_BoxWatch: KBTarget (colek 59% / mepet 52% / kembali 59% / lanjut tabel jarak), batas = 5 candle M1 sesudah
                    candle pemicu ("s/d hh:mm" = jam buka candle terakhir), hasil KENA / TIDAK / GAGAL dicek tiap candle M1 close
                    dengan dinding kotak saat target dibuat. Garis LANJUT = GDM::RtLadder (EQ/T0/T1..) hari ini. Colek M5 tidak
                    jadi target (selalu didahului colek M1 & lebih lemah). Mepet kini dari close M1 (dulu harga bid).
                 -> Dashboard ringkas: KOTAK lo-hi ($lebar) | jam lahir; Harga = p% | keluar ATAP/LANTAI x%; target berjalan
                    ("18:55 : colek ATAP / TARGET : tembus ATAS s/d 19:00 / YAKIN : 59% (15 mnt 74% | akhirnya 85%)"; sesudah tembus
                    "TARGET : kembali ke kotak s/d .. | yakin 59%" + "LANJUT : T1 bawah 4105.2 | yakin 13%"); "-- DAFTAR | n selesai:
                    KENA k (harapan e) --" + 8 baris terakhir (hijau KENA / merah TIDAK-GAGAL). Penjelasan panjang pindah ke tooltip;
                    cerita lama hanya bila judul diklik.
                 -> CSV uji maju: MQL5\Files\GoldPro\kotak_target.csv (dibuat, pemicu, target, yakin, hasil, waktu, kotak, sumber
                    live/putar-ulang), tiap target sekali (kunci naik di GlobalVariable GP_KBJ_KEY).
                 -> Simulasi Python data live 8 Okt 10:20-20:19 WITA: 54 target; colek KENA 5/10 (harapan 5.9), mepet 5/10 (5.2),
                    kembali 13/17 (10.0), lanjut 1/17 (3.7).
               - REVISI 21:23 WITA (screenshot: tampil benar, "40 selesai: KENA 19 (harapan 18)"): "40" = batas memori daftar ->
                 kini penghitung terpisah sejak dimuat ("-- DAFTAR sejak hh:mm | n selesai: KENA k (harapan e) --"), rincian per
                 jenis di tooltip judul daftar; KEMBALI + LANJUT dari tembusan yang sama digabung 1 baris ("21:01 tembus BAWAH >
                 kembali 59% KENA 21:02 | EQ 13% GAGAL"; > 62 huruf -> 2 baris). CSV pertama (putar ulang 13:22-21:01 WITA, 66
                 target): colek KENA 7/13 (harapan 7.7), mepet 6/11 (5.7), kembali 17/21 (12.4), lanjut 0/21 (4.2) - hari sideway,
                 tembusan dalam satu kotak saling berkaitan; nilai sesudah beberapa hari.
               - REVISI 21:34 WITA (screenshot: "sejak 15:43 | 56 selesai: KENA 26 (harapan 26)" = tepat): tanpa target berjalan &
                 harga di dalam kotak -> baris "Tunggu: colek dinding / close >= (lantai + 90% lebar) / <= (lantai + 10%)".
               - REVISI 21:37 WITA (screenshot: harga naik ke dekat atap lalu turun, tanpa target): dicek candle M1 - 21:31 close
                 4129.04 (88.9%) vs pemicu mepet 4129.18 (kurang $0.14), high tertinggi 4129.87 vs atap 4130.45 (tidak colek) ->
                 benar tidak ada target. Harga kini tampil 2 desimal (_Digits; dulu 1 desimal: atap 4130.45 tampil "4130.4").
  [selesai] OB SEBAGAI MAGNET UNTUK HARGA DI KOTAK SIDEWAY? (8 Okt 2026 malam, pengguna: "apakah kemunculan OB bearish / bullish bisa
            menjadi target candle di dalam kotak; entah tersentuh atau tidak, intinya apakah itu sebuah magnet?").
            research\consol_ob.py -> consol_ob.txt. 11.7 rb kotak 2017-26; zona replika GoldPro (consol_smc) di M1/M5/M15/H1, OB &
            Breaker terpisah; OB bearish terdekat seluruhnya DI ATAS kotak & OB bullish DI BAWAH, jarak <= 0.5 ADR (116 rb baris).
               - A SENTUH dalam 240 mnt, zona vs level CERMIN (jarak sama, sisi seberang): M1 OB 58.8 vs 58.8, M5 OB 45.1 vs 45.0,
                 M15 OB 35.4 vs 35.0, H1 OB 26.4 vs 27.4; Breaker M1 -0.8, M5 0.0, M15 -0.6, H1 -1.9 poin. Per jarak sama saja
                 (<= 0.05 ADR ~85% vs ~85%). Satu-satunya pola: Breaker H1 sangat dekat (<= 0.1 ADR, n 773) disentuh -7 poin LEBIH
                 JARANG dari cermin (latih & uji) = sedikit menahan, bukan menarik; sampel kecil.
               - B ARAH tembus kotak ke sisi zona vs peluang posisi: -0.8..+0.0 poin di semua TF (50% = koin).
               - C TARIKAN gerak bersih 60/240 mnt ke arah zona: -0.005..+0.0004 ADR (~0), tahun searah 2-6/10.
               - D sesudah tembus ke arah zona, zona tercapai sebelum close kembali: -0.2..-1.3 poin vs level biasa di jarak sama.
               => OB / Breaker BUKAN magnet: harga memperlakukan tepi zona seperti harga mana pun di jarak yang sama. Peluang
                  tersentuh = jarak + waktu saja (sama dengan garis GoldPro, consol_lines). TIDAK ditambahkan sebagai alasan target.
  [selesai] ALASAN HARGA MENEMBUS KOTAK; ADAKAH "HARGA SEBELUMNYA" YANG DICAPAI? (8 Okt 2026 malam, pengguna). research\consol_why.py
            -> consol_why.txt. 11.7 rb kotak 2017-26.
            BAGIAN 1 KE MANA - level terdekat di luar kotak (<= 0.5 ADR) vs level CERMIN di jarak sama (sentuh 240 mnt) | arah keluar
            vs posisi | sesudah tembus tercapai vs level biasa:
               PDH/PDL kemarin -0.5 | +0.3 | -0.7 ; HOD/LOD hari ini -0.2 | 0.0 | -0.3 ; LIKUIDITAS swing M5 belum disapu (BSL/SSL)
               -0.2 | 0.0 | -1.4 ; angka bulat $10 -0.5 | +0.1 | -0.8 ; $50 -0.7 | +0.2 | -0.6 ; dinding kotak sebelumnya 0.0 | +0.2 |
               -1.5 ; open hari -0.9 | +0.1 | -1.8 ; open NY 09:30 -3.8 (1/10 th, latih & uji negatif) | 0.0 | -1.8 poin.
               => TIDAK ada harga sebelumnya yang menarik harga keluar kotak: tersentuh menurut jarak & waktu saja (sama OB, garis
                  GoldPro). [Catatan: ict_tests "open NY +4.4" = ukuran lain (kembali s/d tutup sesudah menjauh); dari kotak: -3.8.]
            BAGIAN 2 KAPAN - keluar kotak dalam 5 mnt vs harapan dari posisi saja (dasar per desil posisi 40/27/16/9/6/6/9/15/26/41%):
               rilis berita USD penting dlm 5 mnt x2.13 (latih 1.85 / uji 2.51, n 304); data NY 08:30 ET x2.60 (2.90/2.39, n 139);
               buka London 08:00 x1.51; buka NY 09:30 ET x1.53. Jam WITA: aktif 08 x1.40, 09 x1.22, 13 x1.45, 14 x1.33, 19 x1.26,
               20 x1.49, 21 x1.33; sepi 00-06 x0.73-0.88, 10-12 x0.78-0.84, 23 x0.83 (latih = uji). Umur kotak: 0-15 mnt x1.12,
               15-60 x0.98, 60-120 x0.66, 120-240 x0.48 (kotak tua makin awet).
               => ALASAN PECAH = PEMICU WAKTU (berita, buka sesi, jam aktif) + kotak masih muda; ARAH = posisi harga di kotak + colek /
                  mepet. Belum dipasang di dashboard (menunggu keputusan pengguna).
  [DIPASANG] BARIS "PECAH 5 MNT: x% | alasan" DI TOMBOL KOTAK SIDEWAY (8 Okt 2026 22:23 WITA, pengguna: "itu perlu untuk
            meningkatkan kualitas"). research\consol_when.py / consol_when2.py / consol_when3.py (+ consol_when_mql_C.txt = bobot).
            Sampel: tiap menit candle M1 close di dalam kotak beku (1.07 jt menit 2017-26, termasuk sesudah tembusan gagal), hasil =
            candle M1 close di luar kotak dalam 5 candle berikut (rata2 26%). Regresi logistik: desil posisi + colek per desil +
            berita USD HIGH & data NY 08:30 dlm 5 candle (dibedakan harga di tengah desil 2-7 vs dekat dinding) + buka London 08:00 +
            buka NY 09:30 ET + jam WITA + umur kotak + pernah ditembus + lebar kotak relatif ambang.
               - latih 2017-21 -> uji 2022-26: logloss 0.4821 vs posisi saja 0.5029; kalibrasi awal: tengah kurang 3-4 poin, > 60%
                 lebih 5-13 poin (colek dihitung dobel -> colek per desil; berita dekat dinding terlalu tinggi -> dipisah tengah/tepi).
               - SATU-TAHUN-DITAHAN (latih 9 th, nilai th ke-10): logloss 0.4716 (posisi saja 0.4929). Tabel koreksi (20 kuantil, dari
                 tahun lain) bila TANPA berita/08:30; model langsung bila ADA (> 70% dikecilkan separuh). Hasil campuran: tiap
                 kelompok prediksi selisih <= 1 poin (> 70%: 74.8 vs 73.0); berita 52.9 vs nyata 53.8, data 08:30 59.9 vs 61.1, berita
                 dekat dinding 63.7 vs 65.9, colek 58.5 vs 60.5, jam 20-21 WITA 38.4 vs 38.7; lebar kotak < 0.55x ambang 44.0 vs 41.6,
                 0.55-0.75 35.0 vs 35.6, 0.75-0.9 28.5 vs 28.6, 0.9-1 25.2 vs 25.2; per tahun 24-28% vs 24-28%.
               - Simulasi data live 8 Okt (kotak lebar 4117.8-4130.4, 324 menit): prediksi rata2 28% vs nyata 18% - satu hari sideway,
                 menit saling berkaitan; kelompok lebar yang sama di uji 10 th tepat (25.2 vs 25.2).
            -> GP_BoxWatch: KB_PBreak (bobot = consol_when_mql_C.txt, dicek 0 angka beda), kalender MT5 USD HIGH dibaca sendiri
               (GP_CalTime, putar ulang 10 jam + 24 jam ke depan, segar tiap 10 mnt), dihitung tiap candle M1 close di dalam kotak.
               Baris: "Pecah 5 mnt: 31% | berita 20:30" (alasan: berita / data NY 08:30 / buka London / buka NY / colek / jam aktif /
               jam sepi). Tooltip: cek live sejak dimuat (prediksi rata2 -> nyata, per kelompok < 20 / 20-50 / >= 50%).
            -> 22:29 WITA (screenshot: SMC dimatikan, tembus ATAS 22:20, daftar KENA 29 vs harapan 29; pengguna: "garis atap dan lantai
               lebih jelas dan terus update"): garis ATAP biru / LANTAI oranye kini tebal 2 & utuh di DEPAN candle (dulu putus-putus 1,
               di belakang), label "ATAP 4130.45" (Arial Bold 8) berakhir di ujung kanan + tanda harga berwarna (OBJ_ARROW_RIGHT_PRICE),
               saat tembus label "ATAP 4130.45 - DITEMBUS 22:20", garis titik-titik pemicu MEPET 90% / 10% saat harga di dalam.
               Properti diset tiap gambar (objek versi lama ikut berubah). Ujung kanan = candle berjalan + 6 candle, tiap 2 dtk.
  [DIPASANG] BARIS "KEMBALI 5 MNT: x% | alasan" SAAT HARGA DI LUAR KOTAK (8 Okt 2026 22:53 WITA, pengguna: "setelah harga keluar kotak
            dan akan kembali lagi ke dalam kotak, itu juga perlu"). research\consol_back.py -> consol_back.txt, consol_back_mql.txt.
            Sampel: tiap candle M1 close DI LUAR kotak beku, menit 0 (candle tembus) s/d 59 (1.18 jt menit 2017-26, termasuk
            tembusan ke-2 dst); hasil = close di dalam kotak dalam 5 candle (rata2 18.3%).
               - Tabel menit di luar x jarak close dari dinding (x lebar kotak), kembali 5 mnt: candle tembus 67/49/34/25/11% (< 0.1 /
                 0.1-0.25 / 0.25-0.5 / 0.5-1 / >= 1 lebar); 5-9 mnt 59/32/16/7/2; 30-59 mnt 56/26/10/3/0. Colek dinding dari luar
                 59.3% vs tanpa 12.8%; close di ekstrem (>= 0.8) 10.4%, sudah balik separuh 34.8%; berita 27.1%; latih = uji.
               - Regresi logistik (sel menit x jarak 40 + sedang balik + colek dari luar + berita / 08:30 + jam WITA + tembusan ke-n +
                 lebar + sisi), uji satu-tahun-ditahan + tabel koreksi tahun lain: logloss 0.3203 (rata2 0.4762, tabel menit x jarak
                 0.3305); tiap kelompok prediksi selisih <= 0.7 poin; per kelompok <= 2 poin (colek dari luar 57.4 vs 59.3, berita 25.4
                 vs 27.1, jarak < 0.1 60.7 vs 62.5, candle tembus 57.0 vs 59.0); per tahun 16.8-19.5 vs 17.3-19.5. (Tanpa koreksi:
                 > 70% terlalu tinggi 5-25 poin.)
               - Simulasi data live 8 Okt (168 menit di luar): prediksi 22.6% vs nyata 31.0%; urutan benar (< 20%: 8% nyata, 20-50%:
                 48%, >= 50%: 81%) - hari sangat sideway (searah "pecah 5 mnt" yang juga meleset ke arah kotak bertahan).
            -> GP_BoxWatch: KB_PKBack (bobot dari consol_back_mql.txt, dicek 0 beda), tiap candle close di luar (state 2) mulai candle
               tembus; baris di bawah "Harga $x di atas atap": "Kembali 5 mnt: 37% | colek atap dari luar"; alasan: colek dari luar /
               dekat / jauh dari dinding / sudah balik separuh / berita / lama di luar. Tooltip cek live (rata2 -> nyata, per kelompok).
  [DIPASANG] MASUK LAGI = BENAR-BENAR MASUK ATAU KELUAR-MASUK? (8 Okt 2026 23:00 WITA, screenshot garis baru "lebih enak dan meyakinkan";
            pengguna: "saat menyentuh dinding kotak setelah dari luar, seberapa yakin harga akan benar-benar masuk?"). research\
            consol_retest.py -> consol_retest.txt, latih = uji.
               - COLEK DARI LUAR (140.572; candle close di luar, sumbu masuk lagi): close masuk dlm 5 mnt 59.3% / 15 mnt 74.9%; sesudah
                 masuk bertahan 10 mnt 26.2%; ke tengah kotak dulu 28.4%; MASUK (<= 5 mnt) & BERTAHAN 10 mnt 15.8%. Per jarak close
                 dari dinding < 5% / 5-10 / 10-25 / 25-50 / >= 50% lebar: masuk 5 mnt 70.7/61.1/49.0/34.5/21.7%, masuk & bertahan
                 20.4/16.5/11.7/6.3/2.7%. Menit di luar, colek ke-n, tembusan ke-n: hampir tidak berpengaruh (57-60%).
               - SEMUA MASUK LAGI sesudah tembus (71.996): bertahan 10 mnt 26.2%, 30 mnt 9.5%, ke tengah dulu 28.3%; bila keluar lagi
                 lewat dinding yang SAMA 93.1%. Per dalamnya close masuk < 5% / 5-10 / 10-25 / 25-50 / >= 50% lebar: bertahan 10 mnt
                 20/28/34/34/22%, ke tengah dulu 17/26/40/69/100%, keluar lagi sisi sama 98/96/89/70/40%.
               => Dinding yang baru ditembus = zona KELUAR-MASUK; "masuk lagi" jarang menetap.
            -> GP_BoxWatch: di luar & candle colek dari luar -> "Colek dari luar: masuk & bertahan 10 mnt 20%"; 10 mnt sesudah masuk
               lagi -> "Baru masuk lagi 22:41: bertahan 10 mnt 34% | ke tengah 40%" (tooltip: keluar lagi lewat dinding sama x%).
            -> 23:17 WITA (screenshot: 23:09 mepet LANTAI -> tembus BAWAH 23:10 KENA; daftar KENA 30 vs harapan 30; tampil bersamaan
               "Kembali 5 mnt: 26%" & "TARGET kembali ... yakin 59%" = membingungkan): yakin target KEMBALI kini = model kembali 5 mnt
               di candle tembus (situasi: jarak, colek, jam, berita; uji candle tembus 57.0 vs nyata 59.0), bukan rata2 59%; label
               "yakin awal" + tooltip (angka terbaru = baris "Kembali 5 mnt"). Juga untuk tembus loncat ke sisi seberang.
  [DIBUAT] EA TELEGRAM KOTAK SIDEWAY (8 Okt 2026 23:29 WITA, pengguna: "ini yang paling meyakinkan untuk menemukan jalan emas di peta
            kita; buat EA telegram yang memuat informasi ini, lengkap dengan simbolnya").
            - Indikator (GP_BoxWatch, input InpKBTelegram = true): tiap kejadian LIVE ditulis ke MQL5\Files\GoldPro\kotak_telegram.txt,
              1 baris "SIMBOL|TAG|teks" ('^' = baris baru, "->" = panah). TAG: BOX kotak baru/diperbarui (+ keluar atap/lantai %,
              pecah 5 mnt), TGT target colek/mepet, KENA/TIDAK/GAGAL hasil, UP/DN tembus (+ target kembali yakin awal & lanjut ke garis),
              HOLD bertahan 15 mnt, BACK masuk lagi (bertahan 10 mnt %, ke tengah %), END kotak selesai (alasan + rekap KENA/harapan
              target kotak itu), PECAH pecah 5 mnt >= 50% (jeda 15 mnt, tidak di candle yg sudah membuat target), BACKP kembali 5 mnt
              >= 50% (jeda 10 mnt, + "colek dari luar: masuk & bertahan"). Putar ulang TIDAK ditulis; GoldPro di beberapa chart -> sekali
              (kunci jam candle x 1000 + urutan di GV GP_KBTG_KEY). File > 1 MB -> mulai baru.
            - EA Experts\GoldPro\GoldPro_Telegram.mq5 (TIDAK ada fungsi trading): token & chat_id dari Common\Files\SMCI\telegram.cfg
              (sama SMCI_TelegramEA; "dry_run=" di file itu diabaikan) atau input cadangan; baca baris baru tiap 2 dtk (mulai dari
              akhir file saat dipasang), emoji dari kode Unicode (sumber ASCII), HTML (& < > di-escape), UTF-8 persen-encode
              (pola SMCI yang sudah diperbaiki untuk emoji), gabung kejadian per pesan (maks ~3500 huruf), maks 1 pesan/dtk, gagal ->
              antre & coba lagi (jeda naik), DryRun -> MQL5\Files\GoldPro\telegram_dryrun.log, pesan uji saat dipasang, status di
              Comment chart. Input pilih isi: kotak / target / hasil / tembus / peringatan. Compile 0 error 0 warning (ex5 sempat
              bernama pendek GOLDPR~3.ex5 karena kompilasi via jalur 8.3 - diganti nama).
            - Pasang di chart LAIN dari chart GoldPro_Panel; perlu Allow WebRequest https://api.telegram.org (Tools > Options >
              Expert Advisors) - dilakukan pengguna sendiri.
            - 9 Okt 2026 05:39 WITA: akun Telegram pengguna sempat diretas & dipulihkan (data terhapus) -> bot & token BARU. EA kini
              memakai file SENDIRI <Common>\Files\GoldPro\telegram.cfg (contoh kosong dibuat, tanpa token; file SMCI lama tidak
              dipakai - tokennya dianggap bocor). EA membaca ulang config tiap 15 dtk sampai lengkap; chat_id kosong -> getUpdates
              tiap 10 dtk, chat ID + nama pengirim tampil di chart/log (TIDAK disimpan otomatis: orang lain bisa mengirim pesan ke
              bot); token ditolak -> pesan di chart; pesan uji dikirim begitu config lengkap. Comment chart menuntun LANGKAH 1-3.
              Kompilasi lewat jalur folder pendek + nama file panjang -> ex5 bernama benar.
            - 9 Okt 05:49 WITA: pengguna membuat bot baru @GoldPro_2026_bot (token ditempel sendiri di telegram.cfg; format dicek
              tanpa ditampilkan), EA di XAUUSD H1 menemukan chat ID 8787331757 (Rudi, private) lewat getUpdates, pengguna mengisi
              chat_id -> "Config lengkap - Telegram AKTIF", pesan uji DITERIMA dengan semua emoji. Perbaikan kecil: log "Chat ID
              ditemukan" sekali saja (dulu tiap 10 dtk); teks pesan uji bila file kejadian belum ada = "belum ada kejadian live"
              (dulu peringatan). Indikator versi Telegram berjalan sejak reload 05:26; file kejadian dibuat pada kejadian live pertama.
            - 9 Okt 06:21 WITA screenshot: pesan live pertama DITERIMA (06:08 target mepet -> 06:09 KENA + TEMBUS ATAS ke-7 + target
              kembali 68% / lanjut T0+ 13% -> 06:14 KENA kembali, GAGAL T0+, MASUK LAGI, target colek -> 06:16 KENA + TEMBUS ke-8 ->
              06:21 TIDAK kembali). Label LIVE "MARKET TUTUP" selama 60 mnt pertama sesudah jeda harian (CalcMState: jendela 60 mnt
              terpotong jeda -> st -1) padahal pasar buka -> st -2 = "BARU BUKA (< 60 mnt)" (+ panel KONDISI). Garis LANJUT memakai
              tangga hari ini (T0+ 4144.75 dari open 4134.57) - benar. Compile 06:24 WITA.
  [DIPASANG] PERGANTIAN KOTAK DIBERI TAHU LEBIH DULU (9 Okt 2026 06:37 WITA, pengguna: "saat akan ada pergantian kotak ke kotak baru, ada
            keterangan di dashboard dan telegram?"). research\consol_hold60.py -> consol_hold60.txt, consol_hold60_mql.txt: peluang
            tembusan jadi TEMBUS SUNGGUHAN (60 mnt terus di luar) per menit di luar x jarak close dari dinding (1.18 jt menit, latih =
            uji +-2): candle tembus 9/16/24/33/50% (< 0.1 / 0.1-0.25 / 0.25-0.5 / 0.5-1 / >= 1 lebar), 15-29 mnt 15/31/48/66/84,
            30-44 mnt 21/42/62/80/94, 45-59 mnt 41/67/85/95/99.
            -> Dashboard: judul "KOTAK ... | 03:53 s/d 07:53" (selesai paling lambat); 30 mnt terakhir umur 4 jam: "Selesai 07:53 (sisa
               12 mnt) | lalu kotak baru: langsung/belum" (= 60 mnt terakhir sempit / tidak); kotak baru hampir terbentuk (>= 60 mnt
               tidak sempit, rentang 60 mnt <= 115% batas): "Kotak baru bisa segera: 60 mnt $X (batas $Y)"; di luar: "Tembus
               sungguhan HH:MM bila bertahan | peluang x%".
            -> Telegram tag SOON (jam pasir, ikut input "kotak"): 10 mnt sebelum umur 4 jam (+ kotak baru langsung / belum), menit 30
               & 45 di luar (jam tembus sungguhan + peluang), kotak baru bisa segera (sekali per kotak). EA perlu dipasang ulang
               (ganti TF tidak memuat ulang EA) agar ikon jam pasir tampil; versi lama tetap mengirim dgn ikon info.
            -> 9 Okt 08:09 WITA (pengguna: "kenapa kotak hilang?"): kotak 03:53 selesai 07:16 TEMBUS SUNGGUHAN ATAS (rekap KENA 13/20,
               harapan 10.3; lanjut T0+ 13% KENA 07:55); sesudahnya harga naik terus -> rentang 60 mnt $11.08 > batas $7.82 -> belum
               ada kotak (benar). Dashboard tanpa kotak kini: "KOTAK SIDEWAY: tidak ada | 60 mnt $11.1 > batas $7.8".
  [selesai] BERAPA KOTAK SIDEWAY SEHARI & SIKLUS HIDUPNYA (8 Okt 2026 malam, pengguna: "berapa kali kotak itu muncul dalam sehari,
            dan bagaimana proses updatenya?"). research\consol_count.py -> consol_count.txt; mesin persis KB_Bar, 2017-26.
               - rata2 5.6 kotak/hari dagang (median 6; 10% hari <= 3, 90% <= 8, maks 11): KOTAK BARU 4.8 + DIPERBARUI 0.8; hari tanpa
                 kotak 2.5%. Per tahun 4.9-6.1; Senin-Jumat sama (5.4-5.8). Lahir merata ~0.2-0.3/jam tiap jam WITA, paling jarang
                 05-06 WITA (jeda pasar harian 0.09-0.11).
               - umur median 140 mnt (p25 98, p75 206). Berakhir: TEMBUS SUNGGUHAN 60 mnt di luar 61.0% (umur median 126), diganti
                 KOTAK BARU 27.6% (139), umur 4 jam 11.4%. Tembusan per kotak (gagal + jadi): 1x 15%, 2x 13%, 3x 11%, 4x 11%, 5x 10%,
                 >= 6x 39% (median 4-5). Lebar 2025-26 median $8.5 (p25 $5.2, p75 $12.4), 0.102 ADR.
  [selesai] KELUAR-MASUK PER KOTAK (9 Okt 2026, pengguna: "berapa kali dalam 1 kotak harga keluar masuk?"; kotak 03:53 WITA sudah 8x).
            research\consol_inout.py -> consol_inout.txt (mesin persis tombol). Per kotak: rata2 5.2, median 4 (25% <= 2, 75% <= 7,
            90% <= 10, maks 26); sebaran 1x 15%, 2x 13%, 3x 11%, 4x 11%, 5x 10%, 6-7x 15%, 8-9x 10%, 10-14x 11%, 15+ 3%; per tahun
            4.8-5.6; ~1.8 tembusan per jam umur kotak. Tiap tembusan: 85.6% kembali ke dalam; yg kembali: 1 mnt 34%, <= 3 58%,
            <= 5 68%, <= 15 86% (median 3 mnt). Kotak berakhir TEMBUS SUNGGUHAN (61%): gagal dulu median 3 (rata2 3.5), langsung jadi
            di tembusan pertama hanya 21%; diganti kotak baru 5.7; umur 4 jam 7.7. Jam lahir WITA: paling ramai 06 (6.8), 07 (6.2),
            18-20 (6.1-6.5); paling tenang 03-05 (3.5-3.8). Lebar kotak hampir tidak berpengaruh (5.5 -> 4.9).
            + ("kotak berganti sesudah berapa kali sentuh / berapa jam?") umur kotak median 140 mnt (25% <= 98, 75% <= 206, 90% <=
            243); TEMBUS SUNGGUHAN median 126 (90-175), diganti 139 (103-180), umur 4 jam 240. Jeda ke kotak berikutnya: langsung
            40%, <= 30 mnt 55%, <= 60 65%, <= 120 76%, median 18 mnt. Umur menurut keluar-masuk: 0-2x 91 mnt, 3-5x 130, 6-9x 172,
            10x+ 237 (makin sering keluar-masuk = kotak makin lama hidup; jumlah sentuhan TIDAK mengganti kotak).
  [selesai] ENTRY / SL / TP DARI PEMICU TOMBOL KOTAK SIDEWAY (9 Okt 2026, pengguna: "bot sudah tau harga akan terus naik? buat notifikasi
            & keterangan entry, SL, TP"). research\consol_trade.py -> consol_trade.txt. Aturan ditetapkan sebelum hasil; entry = open
            candle sesudah pemicu + spread asli; SL & TP satu candle = SL; maks 240 mnt.
               S1 ikut target colek/mepet: SL 0.5/TP 0.5 lebar menang 49.7%, R kotor -0.006, bersih -$0.32/0.01 lot, 0/10 th; SL 0.25/
                  TP 0.25 -$0.33; SL 0.5/TP 0.25 menang 65.9% -$0.33 (0/10).
               S2 lawan tembus (taruhan kembali, SL ekstrem candle tembus + 0.1 lebar): TP dinding-0.25 menang 30.9%, R kotor +0.075 tapi
                  bersih -$0.28 (SL dekat -> spread besar dibanding risiko), tiap tahun negatif (2026 -0.03); TP tengah -$0.28.
               S3 ikut tembus (SL 0.25 lebar di dalam, 1:1): menang 49.1%, -$0.34, 0/10.
               S4 ikut tembus sungguhan (menit 30, peluang bertahan >= 60%, SL dinding, 1:1): menang 49.7%, -$0.25, 1/10 th (2026
                  +$0.65 n 884; 2025 -0.12, 2024 -0.03) = kemungkinan tren kuat 2026, bukan keunggulan.
               => Pemicu kotak memberi peta waktu/perilaku yang tepat, tapi ARAH sesudahnya = koin; tiap aturan entry kalah spread.
                  "Bertahan di luar" (peluang tembus sungguhan) BUKAN "harga terus naik". Entry/SL/TP TIDAK dipasang sebagai sinyal.
  [selesai] BEDAH CANDLE DI LUAR KOTAK & POLA MASUK-LAGI-LALU-TEMBUS (9 Okt 2026, pengguna: "ciri candle yang akan berbalik masuk
            sesudah beberapa menit di luar? masuk dulu lalu menembus - ciri benar-benar menembus, sepertiga, seperempat, sampai garis
            tengah?"). research\consol_candle.py -> consol_candle.txt.
               A Ciri candle di luar -> kembali 5 mnt, TAMBAHAN di atas sel menit x jarak (1.09 jt menit, latih = uji): 2 candle
                 berlawanan berturut +1.7 poin (10/10 th), engulfing berlawanan +1.2, candle berlawanan +1.1, close di ujung ke arah kotak
                 +0.9; searah + close menjauhi kotak + ekstrem baru -2.8 (12.2 vs 14.9, 0/10 th); inside bar -0.1, candle mengecil -0.3,
                 ekor ke arah kotak >= 50% +0.4. => konsisten tapi KECIL (1-3 poin); penentu utama tetap jarak & lama di luar + colek
                 dari luar (sudah di model "Kembali 5 mnt").
               B Sesudah masuk lagi (71.963): kedalaman masuk < 0.1 lebar 25%, 0.1-1/4 27%, 1/4-1/3 9%, 1/3-1/2 11%, lewat tengah
                 1/2-3/4 10%, 3/4-1 12%, tembus seberang 8%. Tembusan berikutnya di dinding SAMA: 99-100% bila masuk <= 1/3, 98% s/d
                 tengah, 88.5% lewat tengah, 40% 3/4-1. Tembusan ulang jadi TEMBUS SUNGGUHAN 12-13% di SEMUA kedalaman & lama di dalam
                 (= tembusan pertama ~13%) -> kedalaman 1/4 / 1/3 / tengah TIDAK memberi tanda tembusan sungguhan.
               C Retest dari luar yang tidak masuk (5 candle tetap di luar): jadi tembus sungguhan 31.4% vs harapan menit x jarak SAAT
                 DIKETAHUI (5 candle sesudah colek) 33.6 -> -2.2 (latih -2.5, uji -1.8). [Versi pertama membandingkan dgn harapan saat
                 colek -> +17 poin = efek "sudah bertahan 5 mnt", bukan efek retest; dikoreksi.]
               => Tanda tembus sungguhan = LAMA & JARAK di luar (tabel consol_hold60, baris dashboard "Tembus sungguhan .. peluang"),
                  bukan bentuk candle, retest, atau kedalaman masuk.
  [selesai] PETA DURASI DI DALAM / DI LUAR KOTAK (9 Okt 2026, pengguna: "petakan berapa lama di dalam kotak lalu tembus, berapa lama di
            luar lalu masuk lagi"). research\consol_durasi.py -> consol_durasi.txt (mesin persis tombol, 2017-26, latih = uji).
               - DI DALAM sejak kotak lahir -> tembus (13.894): <= 5 mnt 23%, <= 15 50%, <= 30 72%, <= 60 90%, <= 120 98%; median 15
                 mnt (rata2 33.5). Per jam WITA: tercepat 08 & 13 (10 mnt), 09 (12), 20-21 (12); terlama 04 (30), 05 (39), 00-03 (16-20).
               - DI DALAM sesudah masuk lagi -> tembus lagi (59.040): <= 1 mnt 30%, <= 2 44%, <= 5 63%, <= 15 83%, <= 30 92%; median 3
                 mnt di semua fase ke-2 dst & semua jam. Fase di dalam berakhir umur 4 jam 2.1%, diganti 2.7%.
               - DI LUAR -> berakhir: masuk lagi 85.6%, tembus sungguhan 11.7%, loncat seberang 0.2%, diganti 2.5%. Yang masuk lagi:
                 <= 1 mnt 34%, <= 2 49%, <= 3 58%, <= 5 68%, <= 10 80%, <= 15 86%, <= 30 94%; median 3 mnt (semua jam 2-3).
               - Sudah X mnt di luar -> akhirnya masuk lagi (vs tembus sungguhan): 0 88%, 2 79%, 5 70%, 10 59%, 15 50%, 20 43%, 30 30%,
                 45 14% -> titik 50:50 = 15 mnt di luar.
  [selesai] PERILAKU CANDLE DI KOTAK: M1 vs M5 (9 Okt 2026, pengguna: "apakah perilaku candle sama di TF M1 dan M5? mana lebih stabil /
            konsisten?"). research\consol_m1m5.py -> consol_m1m5.txt. Kotak sama (11.7 rb), dibaca dari close M1 vs close M5:
               M1: tembusan/kotak 6.2 (antar-tahun sd 0.3); kembali 87.0% (sd 0.6); jadi tembus sungguhan 12.8% (sd 0.6); tembusan
                   pertama setelah median 15 mnt, close lewat dinding 0.07 lebar ($0.47 2025-26); kembali median 3 mnt; colek -> dinding
                   sama 15 mnt 73.9% / akhirnya 85.4%.
               M5: tembusan/kotak 3.0 (sd 0.1); kembali 71.4% (sd 1.3); tembus sungguhan 27.5% (sd 1.3); tembusan pertama median 24 mnt,
                   close lewat 0.14 lebar ($1.07); kembali median 10 mnt; colek -> sama 15 mnt 49.4% / akhirnya 73.8%.
               => Keduanya sama STABIL (latih = uji, antar-tahun sd kecil). M1 = cepat tapi banyak tembusan palsu; M5 = separuh
                  tembusan palsu disaring tapi konfirmasi ~9 mnt lebih lambat & harga sudah ~$0.6 lebih jauh; colek lebih tepat di M1.
                  (Tembus sungguhan M5 lebih longgar: close M1 boleh sempat masuk di antara close M5.) Tombol tetap memakai M1 (model
                  "tembus sungguhan" per menit x jarak sudah mencakup penyaringan ala M5). Arah tetap koin di keduanya.
  [selesai] KOTAK DIBACA DARI CANDLE 20 DETIK vs M1 vs M5 (9 Okt 2026, pengguna: "semakin kecil TF semakin cepat merespon? bagaimana
            dengan 20 detik?"). research\consol_s20.py -> consol_s20.txt. Tick bid broker (copy_ticks_range, hanya dibaca), 698 kotak
            acak 2024-26; dari tick yang sama dibangun candle 20 dtk / 60 dtk / 300 dtk:
               tembusan/kotak 9.4 / 5.6 / 2.8 | palsu (kembali) 91.9 / 86.3 / 70.6% | tembus sungguhan 8.1 / 13.6 / 28.1% | tembusan
               pertama sesudah lahir 13.3 / 16.0 / 23.0 mnt, close lewat dinding $0.20 / $0.30 / $0.71 | di luar sebelum kembali
               60 / 180 / 600 dtk | colek -> dinding sama 15 mnt 83.8 / 73.0 / 48.4%, akhirnya 90.5 / 84.8 / 72.0%.
               Awal tembusan yang AKHIRNYA jadi sungguhan terlihat di 20 dtk hanya median +20 dtk lebih cepat dari M1 (M5: 120 dtk
               lebih lambat). (M1 dari tick = M1 data penuh: palsu 86.3 vs 87.0.)
               => Makin kecil TF makin cepat tapi makin bising: 20 dtk menambah ~4 tembusan palsu per kotak demi 20 dtk lebih awal
                  untuk tembusan sungguhan; jarak $0.20 ~ seukuran spread. M1 tetap titik seimbang; tidak dipasang.
  [selesai] UJI MAJU SEMUA PREDIKSI + RAPOR HARIAN + DAFTAR KUMULATIF (9 Okt 2026, usulan perbaikan no. 1-3, disetujui pengguna).
            Signal\GP_BoxWatch.mqh:
            1. MQL5\Files\GoldPro\kotak_prediksi.csv: tiap prediksi + hasilnya (sekali; kunci GV GP_KBP_KEY0/1/2 = jam candle prediksi).
               pecah5 = tiap candle close di dalam kotak (YA = close di luar dinding dlm 5 candle); kembali5 = tiap candle di luar
               (YA = close di dalam dlm 5 candle); sungguhan60 = peluang "tembus sungguhan" di menit 0 / 15 / 30 / 45 di luar (YA =
               60 mnt terus di luar sisi sama, TIDAK = kembali / loncat ke seberang). Kolom: waktu_wita; jenis; peluang_pct; hasil;
               waktu_hasil_wita; menit (umur kotak / menit di luar); harga; kotak_bawah; kotak_atas; alasan; sumber (live / putar-ulang).
               ~900 baris / hari (~100 KB). JANGAN biarkan CSV terbuka di Excel saat MT5 jalan (Excel mengunci file -> baris hilang);
               salin dulu bila mau dibuka.
            2. RAPOR HARIAN Telegram (tag RAPOR, ikon grafik): sekali sesudah hari dagang server berganti (~05:02 WITA; Sabtu pagi =
               rapor Jumat; hari tanpa catatan tidak dikirim; GV GP_KBRAP_DAY). Isi: kotak lahir, tembusan & tembus sungguhan, target
               KENA vs harapan per jenis, pecah / kembali / sungguhan: rata2 angka -> nyata (+ kelompok >= 50%), total sejak awal.
               Hari dihitung dari WAKTU HASIL. Sekaligus tanda sistem hidup (tidak ada rapor = indikator / EA / PC mati).
            3. DAFTAR KUMULATIF: kedua CSV dibaca bertahap (hanya baris baru, tiap 5 dtk) -> judul "-- DAFTAR sejak 8 Okt: KENA x
               dari y (harapan z) --" tetap walau ganti TF; tooltip: hari ini, per jenis, hanya live. Tooltip Pecah / Kembali /
               Tembus sungguhan: "Uji maju sejak ..." per kelompok angka (dulu "cek live sejak dimuat" - hilang tiap ganti TF).
            Penilai: MQL5\Files\GoldPro\evaluate_kotak.py (-> evaluate_kotak.txt): KENA vs harapan + z (|z| < 2 wajar), per kelompok
            angka 0-10..90-100%, skor Brier, alasan (berita / data NY / colek / jam), per hari. Awal (9 Okt 08:55): 118 target 8-9 Okt
            KENA 54 vs harapan 53.7 (z +0.1); colek 13/26 (harapan 15.3), mepet 13/23 (12.0), kembali 24/35 (20.4), lanjut 4/34 (6.1).
            EA GoldPro_Telegram: input InpSendRapor + ikon rapor (pasang ulang EA untuk ikon; tanpa pasang ulang tetap terkirim, ikon info).
            Cek pertama sesudah ganti TF (09:35): kotak_prediksi.csv 315 baris (putar ulang + live), rapor 8 Okt terkirim (tandai
            "dicatat mulai"); pecah 71x rata2 28% -> nyata 35%, kembali 101x 20 -> 21%, sungguhan 15x 28 -> 27% (sampel kecil).
  [selesai] TEMBUS - MASUK LAGI - TEMBUS LAGI SEARAH: LEBIH JAUH & LAMA? (9 Okt 2026, pengguna: "kalau candle balik masuk dan kembali ke
            arah sebelumnya apakah kembalinya akan lebih jauh dan lama daripada sebelumnya?"). research\consol_rebreak.py ->
            consol_rebreak.txt. 73 rb tembusan, 13.9 rb kotak 2017-26; pasangan tembusan yang KEMBALI lalu tembusan berikutnya:
               sesudah kembali, tembusan berikutnya lewat dinding SAMA 86% (seberang 14%).
               SEARAH (49 rb): LEBIH JAUH 53.5%, LEBIH LAMA 49.0%, keduanya 43.1%, jadi tembus sungguhan 11.6% (semua tembusan 11.7%,
                  tembusan pertama 13.0%), kembali lagi 88%; latih = uji (52.5 / 54.5% lebih jauh). Median: pertama $0.53 / 3 mnt,
                  kedua $0.62 / 3 mnt; rasio jarak median 1.15x (>= 2x 35%, <= 0.5x 26%).
               Menurut tembusan PERTAMA: lewat < 0.1 lebar -> kedua lebih jauh 83%; 0.1-0.25: 60%; 0.25-0.5: 40%; 0.5-1: 25%; >= 1: 16%.
                  1 mnt di luar -> lebih lama 70%; 16-59 mnt -> 18%. = REGRESI KE RATA-RATA: tembusan kedua seperti tembusan biasa
                  (~$0.6, ~3 mnt), lebih besar dari yang kecil & lebih kecil dari yang besar. Peluang tembus sungguhan TETAP ~11-12%
                  di semua kelompok (jarak / lama pertama, dalamnya & lamanya masuk lagi, urutan ke-1..6+) -> tidak ada petunjuk.
               Bila kedua memang lebih jauh: lewat ujung pertama di candle tembus itu 44%, <= 2 mnt 82%; tambahan median $0.68.
               => Tembusan searah sesudah masuk lagi TIDAK lebih kuat; tanda tembus sungguhan tetap lama & jarak di luar (KB_H60).
               Tidak dipasang (opsi: baris "lewat ujung tembusan sebelumnya x%" menurut ukuran tembusan sebelumnya).
  [selesai] CIRI TEMBUS SUNGGUHAN + HARI / SESI SEBELUMNYA (9 Okt 2026, pengguna: "yang pasti menembus itu seperti apa ciri-cirinya?
            apakah ada hubungannya dengan hari/sesi sebelumnya?"). research\consol_real.py -> consol_real.txt. 71 rb tembusan 2017-26,
            dasar 12.0% jadi tembus sungguhan (60 mnt di luar). Semua angka latih ~ uji.
               SAAT CANDLE TEMBUS CLOSE: jarak close dari dinding < 0.1 lebar 9% | 0.1-0.25 15% | 0.25-0.5 23% | 0.5-1 32% | >= 1 lebar
                  54% (hanya 0.4% tembusan); candle tembus >= 2 lebar 47%, 1-2 lebar 27%; berita USD HIGH +-5 mnt 19%; close = high/low
                  BARU hari ini 17%; jam 09-10 WITA 15-16%, 18-19 & 06-07 WITA 9-10% (jam 04-05 WITA tinggi = efek pasar tutup harian).
               TIDAK BERPENGARUH (11-13% semua): arah candle harian KEMARIN (searah 12.0 / berlawanan 12.1%), rentang kemarin, sudah
                  lewat PDH/PDL 13% vs jauh 12%, arah hari ini dari open, ADR terpakai, gerak 60 / 240 mnt (sesi) sebelum kotak, hari
                  dalam pekan, lebar & umur kotak, tembusan ke-n, close di ujung candle.
               Model semua ciri menit 0: AUC 0.601 -> 0.619; 1% teratas nyata 40% -> TIDAK ADA yang "pasti" di candle tembus.
               MENIT 15 masih di luar (dasar 50%): tabel dashboard (jarak) AUC 0.704; + gerak di luar (ujung terjauh, sudah balik?)
                  0.723, 10% teratas 78 -> 84%; + hari / kemarin / sesi tetap 0.723 (tidak menambah). Ujung terjauh s/d menit 15 >= 2
                  lebar 80%, 1-2 lebar 60%, < 0.5 lebar 29-35%; close dibanding ujung: di ujung 72%, balik 5-20% 67%, balik > separuh 28%.
               => Hari / sesi sebelumnya TIDAK ada hubungan. Ciri utama = seberapa jauh & seberapa lama harga bertahan di luar.
               Opsi (belum dipasang): baris tembus sungguhan di menit 15+ ditambah "ujung terjauh & sudah balik?" (+6 poin di 10% teratas).
  [selesai] PETA KEMBALI / TIDAK + KOTAK BERIKUTNYA SESUDAH TEMBUS SUNGGUHAN (9 Okt 2026, pengguna: "petakan waktu / ujung terjauh,
            mana yang akan kembali dan mana yang tidak ... setelah kotak berakhir, harga jauh di atas, lalu terbentuk kotak selanjutnya,
            melanjutkan atau sebaliknya?"). research\consol_map.py -> consol_map.txt. Lebar kotak median: semua $2.39, 2025-26 $8.54,
            2026 $11.86.
            A. 951 rb menit-di-luar 2017-26, % TIDAK kembali (tembus sungguhan), latih ~ uji (selisih umumnya <= 3 poin):
               menit \ ujung terjauh (x lebar):  < 0.25 | 0.25-0.5 | 0.5-1 | 1-2 | >= 2
                  0 (candle tembus)               10    |   19     |  26   |  42 |  -
                  1-4                             14    |   22     |  32   |  47 |  66
                  5-9                             19    |   26     |  37   |  52 |  73
                  10-14                           25    |   30     |  42   |  57 |  77
                  15-29                           27    |   39     |  50   |  66 |  85
                  30-44                           52    |   55     |  65   |  79 |  92
                  45-59                            -    |   77     |  86   |  93 |  97
               posisi close vs ujung (balik > separuh / 20-50% / di ujung): menit 5-9 18/35/48, 15-29 33/63/78, 30-44 52/84/93.
               Yang kembali: median 2-6 mnt lagi (ujung < 0.25 lebar), 10-17 mnt (1-2 lebar), ~21 mnt (>= 2 lebar).
               Peta mana paling tepat (logloss uji): dashboard KB_H60 (menit x jarak SEKARANG) 0.4763 ~ menit x ujung x posisi 0.4770
               ~ menit x jarak x ujung 0.4741; ujung saja 0.5160. => tabel dashboard sudah setara; ujung terjauh hanya penjelas.
            B. 7.9 rb kotak berakhir TEMBUS SUNGGUHAN lalu kotak baru <= 8 jam (jeda median 52 mnt): tembusan pertama kotak baru
               SEARAH 51.7% (harapan dari posisi harga di kotak 51.5%), tembus sungguhan kotak baru searah 49.9%, gerak 1/2/4 jam
               +0.001/+0.000/+0.002 ADR (|gerak 4 jam| biasa 0.122 ADR), naik searah 4 jam 48.9%; latih = uji. Kotak baru jauh
               (>= 0.5 ADR dari dinding lama) 51.7% searah (n 319). => LANJUT / BALIK = KOIN. Yang nyata: harga MENYENTUH dinding lama
               lagi dalam 4 jam 57% (kotak baru dekat < 0.1 ADR 73%, 0.1-0.25 44%, 0.25-0.5 16%, >= 0.5 ADR 2%).
            DIPASANG (9 Okt 10:19, pengguna: "pasang"), Signal\GP_BoxWatch.mqh:
            - di luar kotak, di bawah "Tembus sungguhan": "Kembali s/d 60 mnt: x% (~y mnt) | ujung z.zx, di ujung / balik 20-50% /
              balik >50%". x = 100 - KB_H60 (sama dgn baris di atasnya), y = KB_MAPM (median menit sampai kembali, yang kembali),
              ujung = g_kbMaxOut / lebar, posisi = jarak close / ujung. Tooltip = peta KB_MAPK (% kembali menit x ujung, [ ] = sel sekarang).
            - kotak PERTAMA sesudah tembus sungguhan (lahir <= 8 jam): "Dinding lama X tersentuh lagi s/d HH:MM: p%" (KB_OldP menurut
              jarak tengah kotak baru dari dinding lama x ADR), jadi "Dinding lama X: tersentuh HH:MM (yakin p%)" bila kena; tampil
              4 jam. Ikut pesan Telegram BOX ("^Dinding lama ..."). Dicatat ke kotak_prediksi.csv jenis dinding4j (GV GP_KBP_KEY3);
              evaluate_kotak.py ikut menilai. (Rapor harian belum menghitung dinding4j.)
  [selesai] PANEL TRADE TANPA BATASAN (9 Okt 2026 13:17, pengguna: "fitur trade jangan dibatasi, lepas aja batasan-batasannya").
            Experts\GoldPro\GoldPro_Panel.mq5, bawaan input: InpRequireSL false (SL $ 0 = order tanpa SL), InpMaxOpen 0 (posisi /
            order tanpa batas), InpBlockLock false (lock/hedge boleh), InpBlockWidenSL false (SL boleh digeser menjauh), InpPendingHrs
            0 (order tertunda tidak kedaluwarsa); maks trade/hari & rugi harian sudah 0 sejak 5-6 Okt. Tetap: konfirmasi klik 2x
            (InpConfirm2x, cegah salah klik), aturan broker (lot min/maks/step, jarak stop, sisi harga order), market tutup / Algo
            Trading mati. Panel: baris baru "Batasan: tidak ada (semua dilepas)" / daftar yang masih aktif; pesan order "tanpa SL".
            EA yang sedang terpasang memakai input lamanya -> harus DIPASANG ULANG (cek tab Inputs).
  [selesai] REVISI TOMBOL + SALDO & TARGET HARIAN + LABEL SMC (10 Okt 2026, pengguna: "apa yang tidak kita butuhkan lagi?" ->
            "kita buang, tapi SMC tetap kita pakai, kalau perlu lebih dipresisikan; tambah 1 tombol untuk mengontrol dan
            menampilkan saldo, ada tombol ON/OFF yang bisa digeser, target 7% harian dari akumulasi saldo, saat ON target
            tercapai -> posisi tidak bisa dibuka lagi hari itu; tulisan diperbesar"). Kompilasi 09:44-09:45 WITA, semua 0/0.
            1. DIBUANG (tidak terbukti / dobel): tab "3 KOTAK" (Signal\GP_BoxSignal.mqh tidak dimuat, journal_box.csv berhenti),
               tombol Radar (RadarDraw / GPM_RDR_ + RadarClick di EA), Panah (panah retest/pullback/lewat open, panah live,
               proyeksi besok, DrawSetups/SetupObj + inputnya), "Zona OB/FVG" (Signal\GP_ZoneWatch.mqh tidak dimuat; sumber
               47 dari 49 popup 9 Okt), blok ENTRY [HIPOTESIS] halaman 2. File modul tetap di folder (riwayat).
            2. DIGABUNG: halaman 2 -> TargetLines() di halaman 1 PETA (tangga target, skor 3 hari, cek 20 hari); halaman 4 JAM
               BIAYA -> CostLines() di halaman CEK SIAP (tombol "2 CEK SIAP", g_page internal 5). BTN_N 17 -> 12; Trade indeks 9
               (GP_TBY_), Saldo 10 (GP_SBY_). GP_BoxWatch: ZW_Scale -> KB_Scale.
            3. SMC TETAP + LABEL PRESISI: Render\GP_LabelFix.mqh - posisi asal tiap label teks SMC dicatat (SMC_LabelHome di
               CreateOrUpdateText); kotak piksel (TextGetSize x DPI, anchor) dicek terhadap semua label teks lain (peta GPM_,
               kotak sideway GPK_, PIN, label SMC lain); menimpa -> geser naik / turun selangkah tinggi teks (maks 4), dari
               posisi asal tiap render / zoom / 2 dtk. Deteksi SMC tidak berubah.
            4. SALDO & TARGET HARIAN (EA GoldPro_Panel, tombol "Saldo" indikator, prefix objek GPD_, kanan atas, InpSaldoFont 12):
               saldo, equity + floating, target % (kolom isian, GV GP_SD_PCT_<login>, bawaan InpDayTargetPct 7) x SALDO AWAL
               HARI (= saldo - hasil ditutup hari ini; besok dari saldo baru = akumulasi), bilah kemajuan HASIL YANG SUDAH
               DITUTUP (profit+swap+komisi; floating tidak dihitung), saklar ON/OFF digeser (klik; GP_SD_ON_<login>).
               ON + hasil >= target -> KUNCI s/d hari broker berikutnya (GP_SD_LKD_/LKT_<login>): CanTrade menolak (g.stop),
               InpSaldoEnforce: order tertunda dihapus & posisi yang dibuka SESUDAH kunci (HP / One Click) ditutup tiap 2 dtk;
               posisi sebelum kunci tidak disentuh. Alert + pesan Telegram tag SALDO (ikon kantong uang). OFF saat terkunci =
               klik 2x. Tombol indikator "Saldo ON" hijau / "Saldo KUNCI" merah (dibaca tiap 2 dtk).
            Pengguna: ganti TF (indikator) & PASANG ULANG EA GoldPro_Panel (+ GoldPro_Telegram untuk ikon).
            10 Okt 09:53 (screenshot: dashboard Saldo jalan di kanan atas; pengguna: "pindah ke kiri seperti yang lain"): Saldo di
            KIRI = tempat panel (GP_PX_/GP_PY_), geser ke kanan panel halaman (GV GP_PANR_<cid> dari PanelLayout) / panel Trade;
            KB_Place: dashboard Kotak Sideway di bawah Saldo bila muat, selain itu di kanannya. Bilah rugi: "rugi hari ini -$x"
            (dulu "-$24.33 / +$1.82 (-1337%)").
            10 Okt 10:07 (pengguna: "tambahkan nominal rupiahnya, itu memotivasi saya"): baris "= Rp ..." besar emas di bawah saldo,
            rupiah di target, bilah hasil hari ini & sisa target, popup / Telegram saat tercapai. Kurs: kolom "Kurs" di dashboard
            (GV GP_SD_IDR, 1.000-100.000), awal InpUsdIdr 17900 (JISDOR BI 6 Okt 2026 Rp17.917; broker tidak punya pasangan IDR).
  [selesai] GARIS TENGAH KOTAK + PETA JAM & MODEL CANDLE DI DALAM / DI LUAR + METODE SESUDAH TEMBUS + STRATEGI GABUNGAN (10 Okt 2026,
            pengguna: "beri garis tengah, backtest untuk melihat arah lebih jelas, petakan rinci semua jam & model candle di dalam &
            di luar kotak, metode setelah di luar kotak, strategi yang mampu membaca berbagai hal"). research\consol_mid.py -> consol_mid.txt,
            consol_mid2.py -> consol_mid2.txt. Mesin tombol; 14 rb kotak, 877 rb menit di dalam, 71 rb tembusan 2017-26; latih / uji.
            A. DI DALAM (dinding mana dulu; "selisih" = di luar harapan dari posisi desil 10/17/26/35/45/54/64/73/82/90%):
               di atas / bawah tengah 72.1 / 27.7% = PERSIS harapan posisi (selisih 0.0) -> garis tengah TIDAK menambah informasi;
               berapa kali lewat tengah, porsi waktu di atas tengah, colek tengah: |selisih| <= 2 poin; 12 model candle x zona: semua
               |selisih| <= 1.5 poin; satu-satunya konsisten: > 60 mnt terus di BAWAH tengah -> lantai dulu 85% vs harapan 79.5%
               (-4.5 / -5.8). Jam: 05 WITA atap dulu +6 / +5 poin (dekat tutup harian), 00/05/06 di atas tengah & 09/13 di bawah tengah
               +3..9 kedua periode (5 dari 48 sel - sebagian kebetulan). LightGBM semua ciri AUC uji 0.792 vs posisi saja 0.795.
            B. DI LUAR (lanjut +1 lebar dulu vs ke tengah dulu, rata2 39.0%; sungguhan 12.0%): jarak close dari dinding 35 / 41.5 / 55 /
               73% (< 0.1 / 0.1-0.25 / 0.25-0.5 / 0.5-1 lebar); candle tembus marubozu searah 41-42% (sungguhan 14-15%), berekor
               penolakan 34-35% (7-8%); CANDLE KE-2 masih di luar & marubozu searah -> lanjut 53% vs 44% (sungguhan 26-27%), candle
               ke-2 melawan / doji / inside bar 37-39%; berita USD HIGH 53% (sungguhan 22%); jam 09 WITA 44% , 00/03/04 30-34%;
               tembusan ke-n tidak berpengaruh. LightGBM semua ciri AUC uji 0.563 = jarak saja 0.563.
            C. METODE (biaya nyata, 0/10 th positif semua): S1 ikut tembus (SL tengah, TP +1 / +0.5 lebar) R bersih -0.33 (kotor -0.03),
               S2 retest dinding limit -0.19 (kotor -0.03), S3 gagal tembus -> tengah -0.46 (kotor +0.01), S4 mepet -> tengah -0.58
               (kotor +0.02), S5 tengah ditembus -> dinding -0.56 (kotor -0.01). Tidak ada jam positif di latih. Filter LightGBM tidak
               membuat satu pun positif (terbaik S2 -0.14, S3 -0.19). KOREKSI: versi pertama S5 R kotor +0.04 (9/10 th) = BOCORAN masa
               depan (sampel hanya menit yang kotaknya akhirnya ditembus); semua menit -0.006. consol_mid2: limit di tengah & kotak >= $12
               +0.014R hanya 2026 (n 1.295) = impas.
            => Garis tengah & model candle tidak mempertajam arah: informasi arah di dalam kotak = POSISI harga (sudah di dashboard).
               Sesudah tembus, ciri terkuat = jarak, candle ke-2 kuat searah, berita (sebagian besar sudah di model kembali / sungguhan).
               Tidak ada metode positif setelah biaya. Tidak dipasang (garis tengah bisa ditambahkan sebagai garis bantu visual saja).
  [selesai] KOTAK DALAM SEHARI: JUMLAH, PERTAMA / TERAKHIR, DI ATAS / BAWAH EQ & T0-T4, DIKOCOK x HARI SEBELUMNYA (10 Okt 2026, pengguna:
            "hitung berapa kotak yang muncul dalam sehari ... kecenderungan kotak pertama dan terakhir ... di bawah EQ dan di atas EQ,
            hubungannya dengan garis T0-T4 ... bolak-balik / dikocok di dalam kotak ... bandingkan dengan hari-hari sebelumnya ... tidak
            usah pakai TP dan SL"). research\consol_day.py -> consol_day.txt. Mesin tombol; 14.069 kotak 2017-26; latih / uji; TANPA TP/SL.
            1. JUMLAH: rata2 5.6 / hari (median 6; 5-7 kotak = 56% hari; 0 kotak 3%). Hari sepi (< 0.7 ADR) 6.8, hari ramai (> 1.3) 3.8,
               hari tren (|close-open| > 0.6 ADR) 4.8. Kotak pertama lahir 06-08 WITA (58%). HARI KEMARIN -> JUMLAH HARI INI (stabil
               latih & uji): kemarin 0-3 kotak -> 3.7 | 4-5 -> 5.3 | 6-7 -> 6.2 | 8+ -> 6.5 (korelasi +0.45); kemarin ramai > 1.3 ADR
               -> 4.3, kemarin sepi < 0.7 -> 6.4.
            2. URUTAN: arah tembus pertama ke-1..5+ = harapan posisi (+-2 poin). Tembus SUNGGUHAN kotak ke-1 69.5%, ke-2 61%, ke-3 64%,
               ke-5+ 55%; kotak pertama di EQ 72.7%; lahir < 2 jam sebelum tutup 44%; terakhir (hindsight) 55.6%. Sesudah tembus
               sungguhan, tutup hari searah hanya 49% (ke-1 49.1 / ke-2 49.9 / ke-3+ 49.1%) -> tembusan TIDAK menentukan arah hari.
            3. EQ & TANGGA: kotak MEMUAT EQ 1.28x lebih sering dari garis palsu digeser (latih 1.25 / uji 1.32) = harga paling sering
               berhenti di EQ; T0-T2 tidak (0.92-1.03x). Kotak di EQ sungguhan 65.8% (lain 55-60%), arah 52%. Di atas / bawah EQ (x arah
               hari ini): atas dulu = harapan posisi (+-2 poin); gerak s/d tutup +-0.04 ADR (umum +0.012). Garis tangga terdekat atas vs
               bawah, cek JALUR DICERMINKAN: kotak di bawah EQ (T0-T1 / T1-T2 bawah) garis bawah dulu +5 poin (latih -5.4 / -9.4, uji
               -5.4 / -4.5); di atas EQ tidak simetris (+2.9/+1.5, +0.4/-5.9, -2.4/-11.1); > 0.75 ADR dari EQ cenderung lanjut tapi n
               57 / 92 -> petunjuk lemah, belum layak dashboard.
            4. DIKOCOK (potret menit 30, belum ditembus, 3.805 kotak): kocok di atas tengah atas dulu 61.9% vs harapan posisi 61.7%,
               di bawah 39.5 vs 41.0, seimbang 51.5 vs 50.5 -> kocokan = posisi saja. Lewat tengah 0 / 1-2 / 3-5 / > 5x: +-2.5 poin.
               x kemarin naik/turun, tren 3 hari, di dalam / luar range kemarin, arah hari ini, rentang kemarin: 5 dari ~70 sel bertanda
               (kebetulan diharapkan ~4-5) -> hari-hari sebelumnya TIDAK mempengaruhi ARAH kotak.
            => Celah nyata hanya: (a) jumlah kotak / rezim hari bisa ditebak dari kemarin, (b) kotak pertama & kotak di EQ lebih sering
               tembus sungguhan. Arah tetap ~50/50. Tidak dipasang.
  [selesai] UJI: INFO HARIAN MEMPERTAJAM "TEMBUS SUNGGUHAN"? (10 Okt 2026, pengguna: "baik, jalankan"). research\consol_day2.py ->
            consol_day2.txt. 1,04 jt menit di luar kotak (mesin tombol), hasil = close tetap di luar 60 mnt (= tabel KB_H60). Aturan
            pasang ditetapkan sebelum hasil: logloss turun >= 0.5% kedua arah (latih 17-21 -> nilai 22-26 DAN dibalik), >= 4/5 tahun.
            M1 tabel + kotak ke-n + EQ + jumlah kotak kemarin: logloss +0.06% / +0.17% (LEBIH BURUK), 3/5 & 2/5 th -> GAGAL.
            M4 tabel + JAM SERVER (= jam NY + 7): -1.25% / -1.64%, 5/5 & 5/5 th (jam WITA -1.24 / -1.47%; sisa ke tutup -0.31 / -0.27%)
            -> LOLOS. Tabel dashboard meleset >= 3 poin searah di kedua periode pada 11 jam WITA: 00-03 terlalu rendah (+4..+8; nyata
            54-56%), 08 terlalu tinggi (-8 / -10; nyata 41%), 10-12 terlalu rendah (+4..+8; nyata 57-65%), 20-21 terlalu tinggi (-6..-8;
            nyata 46-53%), 23 terlalu rendah (+5 / +5.5). Angka dashboard berubah median 4 poin, 90% <= 10, maks ~15. Di menit yang
            dicatat CSV (0/15/30/45) lebih kecil: -0.35% / -0.62%. Menunggu keputusan pengguna (belum dipasang).
            Pengguna 10 Okt: "1 dan 2 simpan dulu" (koreksi jam & rencana pengerasan disimpan, belum dikerjakan).
            -> DIPASANG 10 Okt 15:54 (pengguna: "kita tambahkan aja dulu waktu yg konsisten itu 1 dan 2") - lihat entri di bawah.
  [selesai] SIMULASI OPEN POSISI DARI SINYAL BER-% DASHBOARD KOTAK (10 Okt 2026, pengguna: "jika bot memberikan signal tembus atas/bawah
            65% ... 95%, lakukan simulasi open posisi, di harga antrian atau langsung market"). research\consol_sig.py -> consol_sig.txt.
            Mesin tombol & angka % persis dashboard; TANPA TP/SL, tutup 15/30/60 mnt; biaya pasar/stop $0.37, limit $0.17 per 0.01 lot.
            A "keluar ATAP/LANTAI x%" >= 65/75/85%: ramalan BENAR 79/83/88% (= dashboard), tapi posisi pasar untung 34-41%, bersih
               -$0.37..-0.44, KOTOR -0.03..-0.00; stop di dinding -0.34..-0.42; limit di tengah (isi 31-43%) -0.21..-0.24; 0/10 th.
            B TARGET colek/mepet: tembus s/d 15 mnt nyata 74/70% (= dashboard); posisi bersih -0.13..-0.45, kotor -0.10..+0.02, 0-3/10 th.
            C "Tembus sungguhan" >= 65..95%: benar 58/69/71/81/84/88% (dashboard 69-97%, sedikit terlalu tinggi); pasar bersih
               -0.27..-0.46, kotor -0.09..+0.06; limit retest di dinding (isi 8-19%) -0.03..-0.56, <= 4/10 th.
            PEMBANDING arah ACAK di menit yang sama: kotor +0.06, bersih -0.30; selalu beli kotor +0.14 (arus naik emas).
            MFE ~= MAE (median $1.4-2.0 keduanya) -> tidak ada sisi yang lebih jauh; kotor ~0 berarti TP/SL apa pun juga ~0 kotor.
            => % dashboard = peluang KEJADIAN (dinding ditembus / bertahan di luar), BUKAN peluang untung. Ramalan benar 70-88% tapi
               gerak sesudahnya koin -> semua versi rugi sebesar biaya. Tidak dipasang.
  [selesai] COLEK DINDING -> TURUN KEMBALI -> CANDLE TIDAK LEBIH TINGGI / RENDAH = KONFIRMASI DIJEBOL? (10 Okt 2026, ide pengguna).
            research\consol_rej.py -> consol_rej.txt. 122 rb colek (sumbu lewat, close di dalam) 2017-26; konfirmasi dalam 15 candle:
            P1 inside bar 35 rb, P2 berhenti membuat low/high baru sesudah turun/naik kembali 36 rb, P3 dua inside bar 7 rb, P4 3 candle
            di dalam rentang candle colek 2 rb. Pembanding = posisi harga saat konfirmasi (desil, latih).
            Dinding yang dicolek ditembus DULUAN: P1 74.1 vs 74.0% | P2 72.5 vs 72.4 | P3 69.8 vs 70.3 | P4 78.0 vs 78.6 (selisih latih /
            uji <= 1.5 poin) = posisi saja. P2 per sisi (atap / lantai) & per jarak dari dinding: <= 1 poin (kecuali > 60% n 1.7 rb +1/+5).
            Tembus s/d 15 mnt +5 poin di atas posisi, TAPI colek tanpa syarat +7 -> efek dari colek itu sendiri (sudah di target dashboard
            "15 mnt 74%"), pola berhenti justru sedikit mengurangi. Posisi searah dinding dicolek: pasar / STOP bersih -0.36..-0.52, 0-2/10 th.
            => "berhenti sesudah colek" tidak menambah informasi; dinding dekat memang sering dijebol karena DEKAT. Tidak dipasang.
  [selesai] RADAR GARIS COLEK -> BILA TIDAK DITEMBUS, ANTRIAN DI HARGA TERTINGGI / TERENDAH KOTAK (10 Okt 2026, ide pengguna).
            research\consol_fade.py -> consol_fade.txt. 46.5 rb setup colek 2017-26; antrian berlaku 60 mnt, batal bila close di luar
            kotak; biaya limit $0.17. F1 SELL/BUY LIMIT di dinding yang dicolek (terisi 91%), F2 di ujung sumbu colek (57%), F3 di
            dinding seberang (14%), F0 PEMBANDING tanpa colek = limit di kedua dinding saat kotak lahir (52%).
            (a) tanpa TP/SL tutup 15/30/60 mnt: F1 bersih -0.18/-0.14/-0.10 (kotor -0.01/+0.03/+0.07), F2 -0.17/-0.13/-0.11, F3 -0.26/
                -0.23/-0.21, F0 -0.19/-0.16/-0.13; tahun + 0-2/10 (hanya 2026 positif di 60 mnt).
            (b) tutup bila close di luar dinding (aturan "ditembus = salah"): untung hanya 7-9% (dinding dekat ditembus ~85%), bersih
                -0.19..-0.28, 0/10 th. (c) + ambil untung di garis tengah: untung 13-19%, bersih -0.19..-0.23, 0/10 th.
            MFE = MAE ($1.5 / $1.5). F1 = F0 -> colek tidak menambah apa pun. => Lawan dinding (jual atas / beli bawah) kotor ~0,
            rugi sebesar biaya, sama dgn uji fade 29 Sep & S2 consol_mid. Tidak dipasang.
  [selesai] SUDAH 30 MNT DI LUAR KOTAK = PELUANG? (10 Okt 2026 sore, pengguna: "kalau sudah 30 menit diluar kotak, kemungkinan tidak
            akan kembali ya, berarti disana bisa jadi peluang juga?"). research\consol_m30.py -> consol_m30.txt. 12.7 rb tembusan
            2017-26 yang masih close di luar pada menit 30; jadi tembus sungguhan 65.4%. Masuk pasar searah tembusan (biaya $0.37),
            jarak ke dinding median $1.75:
              tanpa SL tutup 30 / 60 mnt: untung 38 / 41%, kotor +0.04 / +0.06, bersih -0.33 / -0.31, 1/10 th
              keluar bila close kembali ke kotak (maks 30 mnt): kena 29%, bersih -0.34, 1/10 th
              SL dinding disentuh (tutup 30 / 60 mnt): kena SL 34 / 46% (dinding disentuh jauh lebih sering dari "kembali"),
                bersih -0.34 / -0.32; + TP 1x / 2x jarak: untung 42 / 36%, bersih -0.36 / -0.34, 0-1/10 th
            PEMBANDING arah ACAK di menit yang sama: kotor +0.05..+0.09, bersih -0.28..-0.32 (sama / sedikit lebih baik).
            => "tidak kembali ke kotak" (65%) TIDAK berarti lanjut menjauh; sisi tembusan tidak memberi keunggulan di menit 30.
  [selesai] KOTAK BARU SESUDAH 30 MNT DI LUAR (pola "bendera") (10 Okt 2026 sore, pengguna: "mengapa kita tidak membuat dinding atau
            kotak baru setelah 30 menit diluar?"). research\consol_newbox.py -> consol_newbox.txt. 12.7 rb tembusan 2017-26 masih di
            luar menit 30. K30 = high/low menit 0..30 (lebar median $3.06; kotak lama $2.35): ditembus searah tembusan awal 65.0% vs
            harapan posisi 64.2% (latih +0.3 / uji +1.4) = geometri (harga menit 30 biasanya di ujung jauh). K15 = 15 mnt terakhir
            (bendera, $1.79): searah 51.7% vs harapan 52.3% = koin. Ikut tembus KB (searah atau berlawanan, tutup 15/30/60 mnt atau
            SL sisi seberang + TP 1x lebar): untung 33-46%, bersih -0.33..-0.46, 0-1/10 th. => kotak baru berperilaku sama dengan
            semua kotak lain: arah = posisi, dagang rugi sebesar biaya. Tidak dipasang.
  [selesai] OB DI DINDING KOTAK = KONFIRMASI? OB = MAGNET DARI TENGAH KOTAK? (10 Okt 2026 sore, pengguna dari screenshot: "selalu
            muncul OB bullish dan OB bearish saat garis muncul ... signal konfirmasi ... atau magnet?"). research\consol_ob.py ->
            consol_ob.txt. OB M1 replika GoldPro (smc_react), aktif = belum terisi 90%, umur <= 600 candle.
            - OB menempel dinding saat kotak lahir: 88% kotak (bearish di atap 3.5 rb, bullish di lantai 3.6 rb, keduanya 5.3 rb,
              tanpa 1.7 rb) -> wajar: dinding = high/low 60 mnt, OB = candle di asal swing yang SAMA (ekstrem yang sama digambar 2x).
            - Atap ditembus dulu vs harapan posisi: OB bearish di atap 44.8 vs 43.2 (latih +2.4 / uji +0.7), OB bullish di lantai
              58.3 vs 58.4 (-0.8 / +0.6), keduanya 51.0 vs 50.6, tanpa 52.6 vs 51.3 -> tidak ada efek "penahan / penopang".
              Tembus sungguhan sesudah tembus pertama 12-14% di semua kelompok (tanpa OB 12.9 / 12.8).
            - MAGNET (harga 30-70% kotak, 50.6 rb sampel, tepi OB terdekat vs level cermin sejarak sama): 50.3% = +0.3 poin
              (latih +0.7 / uji -0.2); di dalam / luar kotak, per jarak: -1.1..+0.7 tak konsisten. OB BUKAN magnet (sama 2 Okt).
            => OB di dinding bukan konfirmasi & bukan magnet. Tidak dipasang.
  [selesai] STRUKTUR GELOMBANG HH/HL/LH/LL SEBAGAI KONFIRMASI - UJI 1 TAHUN (10 Okt 2026 sore, pengguna: "uji dulu 1 tahun jangan
            langsung banyak, lalu cocokkan dengan sistem kotak dan garis kita"). research\consol_hhll.py -> consol_hhll.txt. Data 1 th
            terakhir (28 Sep 2025 - 27 Sep 2026, 2 paruh 6 bln). Swing fractal 5 (= SMC GoldPro) M1 & M5; konfirmasi NAIK = HL baru
            saat high terakhir HH, TURUN = LH baru saat low terakhir LL; campur = pembanding.
            A lanjut ke puncak / lembah baru dulu vs geometri jarak: M1 NAIK 48.7 vs 48.7, TURUN 46.5 vs 46.8; M5 NAIK 46.2 vs 47.5,
              TURUN 43.5 vs 43.3 -> = geometri. (M5 campur HL+LH 52.5 vs 49.9, +3.0/+2.1, n 660 = petunjuk lemah, bisa kebetulan.)
            B dagang (SL di HL/LH, TP HH lama / 1R / 2R, biaya $0.37): M1 -0.14..-0.26R semua; M5 -0.13..+0.04R (campur HL+LH
              +0.04R / $+0.31, tidak stabil). Tidak ada versi positif yang jelas.
            C KOTAK x struktur M5 saat lahir: atap dulu di bawah harapan posisi di SEMUA struktur (naik -6.3/-3.4, turun -2.7/-2.2,
              campur -6.6/-4.9) = kecenderungan tahun ini, bukan struktur; tembus searah struktur jadi sungguhan 11.1 / 8.9% vs
              melawan 12.7 / 15.9% (n ~200) -> struktur tidak mengonfirmasi tembusan kotak.
            D GARIS GoldPro saat konfirmasi M5: garis searah struktur dulu NAIK 49.5 vs 49.7, TURUN 51.0 vs 48.0 (+3.1/+2.8, n 873,
              lemah), campur -2.6..+2.8. => HH/HL/LH/LL = geometri dalam 1 tahun; 2 petunjuk lemah perlu uji 10 th. Tidak dipasang.
  [selesai] SARAN DEEPSEEK: "DAILY CANDLE BIAS BACKTESTING STATS" (MaxMaserati) - KELANJUTAN 67.8% DI 4H (10 Okt 2026 sore).
            research\consol_4h.py -> consol_4h.txt. Definisi persis halaman indikator: BuBC = close 4H di atas high candle
            sebelumnya (Plus = close dekat puncak), target = HIGH candle itu, invalidasi = LOW candle itu, mana tersentuh dulu.
            Angka 67.8% = S&P 500 4H Sep 2022 - Des 2025 (bukan emas). XAUUSD 4H 2017-26 (9.968 candle; urutan dari M1, maks 24 jam):
              BuBC target dulu 78.7% vs GEOMETRI posisi close 78.8% (latih -0.6 / uji +0.4); Plus 87.2 vs 86.6, Minus 54.4 vs 56.5;
              BeBC 76.3 vs 75.9 (Plus 85.9 vs 85.0, Minus 55.3 vs 55.9) -> "kelanjutan" = jarak close ke ujung candle, bukan arah.
              Candle 4H berikutnya searah: BuBC 51.1% (semua candle naik 52.2% = arus emas), BeBC turun 46.1% -> koin.
              Dagang aturan itu (masuk close, TP ujung searah, SL ujung seberang, $0.37): untung 55-74% tapi rata2 -$0.07..-0.36,
              1-4/10 th positif. Per jam buka candle 4H: tak ada jam konsisten.
              1 th terakhir: BuBC 80.4 vs 78.7 (+1.8), BeBC 79.1 vs 74.1 (+5.1), dagang +$1.1 / +$2.9 = tahun reli bergejolak
              (pola sama dgn straddle / AM Fix yang hanya jalan 2025-26). Tidak dipasang.
  [selesai] SARAN DEEPSEEK 2: "FILTER ARAH" KAMIS 04:45 JAM BROKER HANYA SHORT (klaim TradingView: short 14-0, long 4-12, BO +-6 /
            SL 18 / TP 20; 10 Okt 2026 sore). research\consol_thu.py -> consol_thu.txt. 2017-26, 3 tafsiran satuan, biaya $0.37:
              (a) $6/$18/$20: SHORT n 115 menang 57% +0.19R, tapi latih -0.05R / uji +0.26R; hampir semua dari 2025 (+7.8R) & 2026
                  (+13.8R) - tahun lama jarang terisi (BO $6 jauh saat ADR kecil). LONG -0.01R, OCO +0.14R (juga 2025-26).
              (b) $0.6/$1.8/$2.0: SHORT -0.17R, 3/10 th; LONG -0.22R -> rugi.
              (c) skala ADR 0.10/0.30/0.33: SHORT n 269 menang 52% +0.05R, latih -0.09R / uji +0.19R, 7/10 th (17 +3.1, 20 -7.9,
                  21 -6.5, 24 +4.9, 25 +8.1, 26 +9.5R); hari lain: Senin +0.02, Selasa -0.03, Rabu -0.19, Jumat -0.15R; jam 04:00-05:30
                  Kamis semua +0.03..+0.10R (uji +0.08..+0.25, latih -0.09..+0.03); SHORT semua hari -0.06R.
            => Aturan lolos (positif latih DAN uji, >= 7/10 th) GAGAL: 2017-21 rugi, untung hanya 2022-26 (terutama 2024-26) = pola
               rezim reli bergejolak (sama straddle / AM Fix / 4H candle bias). t ~0.8 seluruhnya, ~2.2 di uji sesudah dipilih dari
               banyak hari/jam/arah -> HIPOTESIS terkuat yang pernah muncul untuk 2024-26, belum bukti. Tidak dipasang.
            Usulan lain DeepSeek (dinilai tanpa uji): OI COMEX (GC Prime Logic) = data harian, perlu unduhan, bukan skala scalping;
            VGRSI profit 2024-25 / DL 60% arah / LSTM+BB = klaim 1-2 th atau harian tanpa uji luar sampel.
  [selesai] SARAN DEEPSEEK 3: HIGH/LOW SESI ASIA "SAPU DULU BARU KEMBALI" + ENTRY SAPU+KONFIRMASI RASIO ASIMETRIS (10 Okt 2026 sore).
            research\consol_asia.py -> consol_asia.txt. Dikoreksi: sesi Asia 19:00-03:00 ET (= 07-15 WITA musim panas; usulan
            "00-07 WITA" = NY siang); "Kingdom Saga" (rugi rata2 2.6x untung, menang 91%) = TP KECIL / SL besar, bukan TP 2.5x ->
            keduanya diuji. Kriteria DeepSeek: selisih >= 5 poin dari baseline jarak, stabil 10 th, bersih positif.
            1A high vs low Asia tersentuh dulu sesudah London buka: 52.5% vs geometri 51.2% (latih +1.2 / uji +1.5; per tahun -2.6..+4.9)
               -> GAGAL (< 5 poin).
            1B sesudah sapuan pertama: close kembali ke dalam <= 60 mnt 88% (pola "sapu lalu kembali" terlihat nyata), tapi dinding
               SEBERANG dulu 46.7% vs geometri 49.0% (latih -0.8 / uji -4.1; London -4.2, NY -3.0) -> tidak balik ke seberang -> GAGAL.
            2  entry close kembali ke dalam, melawan sapuan, SL ujung sapuan (median $0.84), TP 2.5R / 1R / 0.4R: kotor +0.01 / -0.03 /
               -0.09R, bersih -0.73 / -0.77 / -0.83R (bootstrap 95% seluruhnya negatif), 0-1/10 th -> GAGAL (biaya $0.37 = 44% risiko).
  [selesai] AUDIT SISTEMATIS HARI x JAM x ARAH (10 Okt 2026 sore, usulan DeepSeek: "apakah ada kombinasi yang positif di 10 tahun,
            bukan hanya 2022-2026?"). research\consol_scan.py -> consol_scan.txt. Masuk open jam server hh:00, BELI / JUAL, tahan 60 /
            240 mnt, Senin-Jumat 2017-26 = 464 kombinasi. Aturan (ditetapkan sebelum hasil): bersih ($0.37) > 0 latih DAN uji, >= 7/10 th.
            - Lolos 8 vs PEMBANDING ACAK (hasil tiap trade dibalik acak 200x) rata2 2.3 (95% s/d 5). Kriteria DeepSeek "kotor positif
              kedua periode": 105 asli vs 107.8 acak (s/d 120) -> kriteria itu dipenuhi kebetulan saja (~1/4 kombinasi).
            - 7 dari 8 = jam server 01 BELI (buka ulang harian, ~06-07 WITA). Spread ASLI jam itu median $0.40-0.45 (bukan $0.17):
              bersih latih -0.03..-0.32 -> GAGAL; masuk 5 mnt kemudian (01:05) kotor $1.29 -> $0.67, bersih +0.05 (latih -0.46) =
              harga BID pembukaan tertekan spread rollover (artefak, sama temuan 27 Sep & 2 Okt). Sisa 1: Senin 06 JUAL bersih spread
              asli -0.08 -> gagal. Kamis 04 JUAL (usulan DeepSeek sebelumnya): latih -0.31, 4/10 th.
            => Tidak ada hari x jam x arah yang bertahan lintas rezim sesudah biaya nyata. Kesimpulan yang bisa dipegang (DeepSeek
               setuju bila 0 lolos): di XAUUSD M1-M5, aturan waktu / arah sederhana tidak punya keunggulan sesudah biaya.
  [selesai] SIMULASI TARGET 7% HARIAN DENGAN STRATEGI BOT (10 Okt 2026 malam, pengguna: "buat simulasi trade, 7% capaian harian dari
            100 dan 200 usd, strategi saya serahkan ke kamu, yg sesuai dengan bot kita"). research\sim7_bot.py -> sim7_bot.txt / .pkl;
            Excel MQL5\Files\GoldPro\Simulasi_Target7persen_BotGoldPro.xlsx (Ringkasan, Asumsi, Harian $100/$200, Posisi $100,
            Sebaran 106x; dicek di Excel 0 galat). Strategi = SOP 4 Okt + kunci Saldo: 20:30-23:00 WITA, +-10 mnt berita dihindari,
            LIMIT di garis GoldPro terdekat, SL = TP maks($5, 0.1 ADR), 60 mnt, maks 3 posisi / 2 rugi, kunci 7%, lot 0.01 per $100,
            spread asli + $0.01.
            - 12 bln terakhir (9 Okt 2025 - 9 Okt 2026): $100 BANGKRUT 20 Agu 2026 (sempat $218 Feb); $200 -> $35 (sempat $388 Feb).
              Target 7% tercapai 33-38% hari, hari untung 55-57%, tapi turun maks 95-97%.
            - 106 awal bulan 2017-01..2025-10 x 12 bln: $100 untung 4%, BANGKRUT 86%, median $7; $200 untung 0%, bangkrut 62%.
              TANPA biaya: $100 untung 40% / bangkrut 49%; $200 untung 25% / bangkrut 4%, median $144.
              Varian tanpa kunci 7%: sama (88% / 68% bangkrut); SL = TP tetap $5: 81% / 56% bangkrut.
            - Mulai 2017: $100 habis Mei 2018, $200 habis Sep 2018. Per posisi 0.01 lot: n 4.457, menang 47.9%, -$0.32 (9/10 th rugi).
            => Rugi karena: tanpa keunggulan + biaya; risiko 5-10% saldo per posisi (lot min 0.01 vs saldo kecil); untung dikunci +7%
               tapi rugi bisa -10..-20% sehari; naik-turun besar menggerus saldo walau tanpa biaya.
  [selesai] 147 VARIASI STRATEGI UNTUK SIMULASI 7% (10 Okt 2026 malam, pengguna: "mungkin kamu hanya menggunakan model 1 strategi. coba
            cari setiap celah, variasikan model entry, tp dan sl dari berbagai lini"). research\sim7_grid.py -> sim7_grid.txt / .pkl;
            lembar "Variasi 147 strategi" di Simulasi_Target7persen_BotGoldPro.xlsx (0 galat). Entry: LIMIT / STOP garis GoldPro, STOP /
            LIMIT dinding Kotak, pasar searah hari, pasar kembali ke EQ, ACAK; SL/TP: 0.05 / 0.10 / 0.20 ADR sama, TP 2x, TP kecil
            (0.20/0.10), garis ke garis; sesi Asia / London / NY murah; tutup 120 mnt; spread asli; akun = aturan 7%.
            - R bersih per posisi: SEMUA 126 negatif (terbaik -0.041, median -0.152) = acak (median -0.152). Lolos (R > 0 latih & uji,
              >= 7/10 th): 0 (acak 0). Entry tidak berpengaruh (median -0.144..-0.155); SL besar mengurangi beban biaya (0.05 ADR -0.26R,
              0.20 ADR -0.08R) tapi tetap negatif; sesi -0.145..-0.162.
            - Akun $100 mulai 2022-25: median untung 2% / bangkrut 78% (acak 4% / 78%). Terbaik dipilih di latih (LIMIT dinding Kotak
              NY SL=TP 0.20: untung 27% / bangkrut 43%) -> uji untung 15% / bangkrut 61%. Terbaik di uji (STOP garis London) = 0% untung
              / 97% bangkrut di 2017-21 (hanya tahun reli). Peringkat latih #3 = strategi ACAK -> peringkat ditentukan keberuntungan.
  [selesai] SIMULASI 7% VERSI LUWES (10 Okt malam, pengguna: "7% itu dicapai sehari, jangan kaku"). research\sim7_flex.py -> sim7_flex.txt.
            Sepanjang hari, s/d 10 posisi kecil / hari, entry ADAPTIF (kotak -> dinding, naik -> beli koreksi, turun -> jual, normal ->
            garis) + E1 / E3 / ACAK, TP/SL $1-3 (+ TP kecil / besar), breakeven ya/tidak, batas rugi -7% ya/tidak = 80 varian.
            R per posisi median -0.185 (acak -0.185), terbaik -0.097; lolos 0; hari +7% tercapai 25-39%; akun $100 bangkrut ~100% semua
            -> lebih buruk dari versi 3 posisi (posisi kecil = biaya relatif lebih besar).
  [selesai] 256 STRATEGI DI 7 HARI BURSA TERAKHIR (11 Okt 2026, pengguna: "ambil aja dulu 7 hari ... buat puluhan hingga ratusan strategi
            dari berbagai lini dan model"). research\sim7_week.py, sim7_week2.py -> .txt / .pkl; Excel MQL5\Files\GoldPro\
            Uji_7hari_256strategi.xlsx (0 galat). 8 entry x 8 TP/SL x 4 sesi, akun 7%, 7 hari = 1-9 Okt 2026.
            - 7 hari: untung 85/256 (bot 32%, ACAK 41%), median $100 -> $88; juara: sepanjang hari STOP tembus garis, garis ke garis
              $100 -> $219.66 (6/7 hari +7%), $200 -> $455 - minggu sebelumnya strategi yang sama $100 -> $63.75. ACAK peringkat #7.
            - 36 pasang blok 7 hari setahun: 5 juara di bloknya +103.5%, di blok BERIKUTNYA -5.4% (semua -9.2%, ACAK -5.6%); korelasi
              peringkat +0.15 -> juara mingguan = keberuntungan.
            - 5 terbaik rata2 setahun (+13..+21% per 7 hari, 62-76% blok untung) diuji 2017-2025: rugi SETIAP tahun ($-0.15..-0.74 per
              posisi), untung hanya 2026 (+1 strategi 2024); akun 7% 12 bln 2017-25 bangkrut 93-100% -> keadaan khusus 2026.
  [selesai] STRATEGI DISESUAIKAN DENGAN STRUKTUR PASAR (11 Okt 2026, pengguna: "strategi yg berhasil semestinya diolah dan disamakan
            dengan struktur pasar; jika berhasil, strategi lain dibuat di kondisi pasar yg berbeda"). research\sim7_regime.py -> .txt/.pkl.
            256 strategi sim7_week 2017-26 (3,11 jt posisi), tiap posisi diberi kondisi saat masuk. Skema 1 (27): struktur H1 (swing
            fractal 5) x keramaian kemarin x tren 3 hari; skema 2 (12): posisi vs high/low kemarin & EQ x keramaian. Prosedur dikunci:
            tiap kondisi diberi strategi R terbaik (min 100 posisi), kondisi tanpa strategi positif tidak ditradingkan; nilai di periode lain.
            - Skema 1 pilih 2017-21 -> uji 2022-26: 13 kondisi, R +0.049 TAPI $ -0.05/posisi (untung R dari posisi SL kecil), per th
              +0.02 / -0.04 / -0.05 / +0.05 / +0.31 (2026 penentu); ACAK -0.126. Akun 7% $100 (46x 12 bln): untung 24%, bangkrut 43%,
              median $45. DIBALIK (pilih 2022-26 -> uji 2017-21): R -0.322, 0/5 th (R pilih +0.271) - lebih buruk dari ACAK (-0.249).
            - Skema 2: pilih 17-21 -> uji R -0.051 (1/5 th, hanya 2026); dibalik -0.259, 0/5. Akun $100 bangkrut 72%.
            - Tiap strategi hanya di kondisi positifnya: uji 22-26 positif 31% (11/35), dibalik 0% (0/187).
            => Mencocokkan strategi dengan kondisi pasar = 6.912 kombinasi dipilih; tampak bagus di periode pilih (+0.27R), hilang /
               berbalik di periode lain. Tidak kokoh; tidak dipasang.
  [selesai] 3,1 JUTA POSISI DIBEDAH PER SEL (11 Okt 2026, pengguna: "masak tidak ada 1 pun model entry yg cukup konsisten? jangan hanya
            melihat persentasenya secara keseluruhan"). research\sim7_cells.py, sim7_cells2.py -> .txt. Sel = strategi saja (224) /
            x kondisi 1 (3.345) / x kondisi 2 (2.121) / x jam WITA (1.737), dinilai per TAHUN. Ketat (>= 300 posisi, $ + di >= 8/10 th,
            + di 2017-21 & 2022-26): 0 sel (kebetulan rata2 0-0.4). Strategi saja: terbaik 3/10 th. Longgar (>= 7/10 & kedua periode +):
            2 sel, kebetulan rata2 0.4 (maks 1) -> sedikit di atas kebetulan, sampel kecil:
              (1) NY 20:30-23 | LIMIT dinding Kotak | TP/SL garis ke garis | harga EQ..high kemarin | kemarin ramai: n 389 (~3/bln),
                  +$0.50/posisi, 52% menang; 17 -0.34, 18 -0.27, 19 +0.20, 20 -0.01, 21 +0.45, 22 +0.29, 23 +0.39, 24 +0.40, 25 +0.28,
                  26 +2.53 (2026 = $132 dari total $194).
              (2) NY 20:30-23 | STOP tembus garis | garis ke garis | harga > high kemarin | kemarin sepi: n 350, +$0.29; 17 -0.18,
                  18 -0.29, 19 +0.30, 20 +0.37, 21 +0.18, 22 -0.80, 23 +0.55, 24 +1.14, 25 +0.83, 26 +1.25.
            => HIPOTESIS (kandidat uji maju diam-diam), bukan bukti; ~3 posisi / bulan -> tidak bisa menopang target 7% harian.
  [selesai] STRATEGI HANYA BUY (11 Okt 2026, pengguna: "bagaimana dengan strategi buy?"). research\sim7_buy.py -> sim7_buy.txt.
            Versi BUY saja dari 256 strategi (BUY LIMIT garis bawah, BUY STOP garis atas, BUY STOP atap / LIMIT lantai Kotak, BUY bila
            hari naik, BUY di bawah EQ, ADAPTIF BUY, BUY WAKTU ACAK = arus naik saja), 1,97 jt posisi 2017-26, spread asli.
            - Per posisi: median -$0.31 (BUY acak -$0.28); terbaik Asia BUY STOP garis, garis ke garis +$0.07 tapi untung hanya 3/10 th
              (2024 +0.37, 2025 +0.90, 2026 +0.76; 2017-23 rugi). Konsisten >= 8/10 th: 0 (acak 0). Beberapa mengalahkan BUY acak 7-8/10 th
              tapi tetap rugi di 7/10 th.
            - Sel strategi x kondisi: ketat & longgar 0 dari 1.638 + 1.221 sel (acak 0).
            - Akun 7% $100: terbaik dipilih 2017-21 -> 2022-26 untung 2-24%, bangkrut 39-50%; dibalik untung 0%; BUY acak bangkrut 100%.
            => Arus naik emas nyata (~$1/hari rata2 2017-26) tapi per posisi scalping 60 mnt hanya ~$0.05 vs biaya ~$0.30. BUY baru
               memetik arus naik bila ditahan lama (uji 30 Sep: BUY acak tahan 24 jam +0.27 ATR) = bukan scalping. Tidak dipasang.
  [selesai] STRATEGI PENGGUNA: OCO DI DINDING KOTAK + POSISI KEMBALI KE KOTAK (11 Okt 2026, pengguna: "antri pas di garis, buy di garis
            atas, sell di garis bawah bersamaan, tp & sl 3 usd lot 0.01, satu kena lepas yg lain; setelah beberapa menit di luar kotak dan
            akan kembali, sell lagi di garis atas & sebaliknya, tp di dalam kotak"). research\sim_kotak_oco.py -> .txt / .pkl. 2017-26.
            T1 BUY STOP atap + SELL STOP lantai (OCO, dipasang lagi bila kotak hidup & harga di dalam); T2 sesudah W mnt di luar (0/5/10/
            15/30) antrian berlawanan di dinding yg ditembus s/d menit 60. TP=SL $3 (+ $2 / $5), 240 mnt, spread asli + $0.01.
            - $3: T1 n 23.203 (~198/bln) menang 46% -$0.43/posisi; T2 W0 -0.32, W5 -0.35, W10 -0.34, W15 -0.33, W30 -0.42; SEMUA 0/10 th,
              semua sesi negatif (-$0.30..-0.48). $2 lebih buruk; $5 -0.29..-0.36 (maks 1/10 th).
            - Akun 7% ($100): T1, T2 W5, gabungan -> bangkrut 100% di 2017-21 & 2022-26; 12 bln terakhir $100 -> $5.96, $200 -> $1.12.
            => tembus dinding = koin (riset 8-9 Okt), harga balik ke dinding = keluar-masuk (93% keluar lagi lewat dinding sama), biaya
               $0.30 = 10% TP $3. Tidak dipasang.
            Lanjutan "berarti tp 3, sl 2" (research\sim_kotak_oco2.py -> .txt): TP $3 / SL $2: TP kena 32-34% (tanpa keunggulan 40%),
            T1 -$0.48/posisi, T2 W0..W30 -$0.34..-0.47, semua 0/10 th; TP $3/SL $1 (TP 19-22% vs 25%) & TP $4/SL $2 (24-26% vs 33%) juga
            0/10 th. Akun 7% bangkrut 100% (106x); 12 bln terakhir tahap 1+2: $100 -> $3.84. SL kecil lebih sering tersapu gerak kecil.
  [selesai] ORDER DI GARIS MEPET KOTAK (90% / 10%) (11 Okt 2026, pengguna: "bagaimana kalau pasang order di garis mepet?").
            research\sim_kotak_mepet.py -> .txt. M1 OCO STOP (BUY 90% / SELL 10%), M2 OCO LIMIT (SELL 90% / BUY 10%), M3 kembali lewat
            mepet sesudah W 0/5/15 mnt di luar (STOP berlawanan di garis mepet sisi tembus). TP/SL $3/$3 & $3/$2, 2017-26.
            - $3/$3: TP kena 41-44% (acak 50%), -$0.30..-0.39 / posisi; $3/$2: TP 33-36% (acak 40%), -$0.34..-0.46; SEMUA 0/10 th.
            - Akun 7% $100: bangkrut 95-100%, 12 bln terakhir $100 -> -$20..$10. => garis mepet = dinding kotak (sama-sama koin). Tidak dipasang.
  [selesai] MASUK ZONA MEPET DULU, LALU STOP SEARAH KECENDERUNGAN (11 Okt 2026, pengguna: "biarkan masuk dulu lalu buy/sell stop di
            kecenderungan harga"). research\sim_kotak_mepet2.py -> .txt. Pemicu = candle M1 close masuk zona >= 90% / <= 10% kotak
            (17 rb, ~147/bln). A pasar searah, A' pasar BERLAWANAN (pembanding), B STOP di high/low candle pemicu, C STOP di dinding;
            berlaku 15 mnt; TP/SL $3/$3 & $3/$2; 2017-26.
            - $3/$3: TP kena 43% (acak 50%); A -$0.36, B -$0.36, C -$0.35 per posisi, 0/10 th; BERLAWANAN -$0.24 (rugi lebih kecil =
              kecenderungan sedikit BALIK, bukan lanjut). $3/$2: -$0.33..-0.36 (A' -0.25), 0/10 th. Akun 7% $100 bangkrut 100%.
  [selesai] POLA 2 CANDLE DI ZONA MEPET / DINDING (11 Okt 2026, pengguna: "1. close di mepet / luar, candle berikut mengarah turun ->
            sell dari atas / buy dari bawah; 2. close di atas mepet / dinding, candle berikut lebih tinggi / sudah di luar -> searah").
            research\sim_kotak_2candle.py -> .txt. Masuk open candle i+2; TP/SL $3/$3 & $3/$2; tiap pola + arah BERLAWANAN; 2017-26.
            $3/$3 (acak TP 50%): P1-dalam BALIK TP 45% -$0.26 (lawan -$0.34) | P1-luar BALIK 46% -$0.27 (lawan -$0.29) | P2-dalam-HH
            LANJUT 42% -$0.37 (lawan -$0.23) | P2-dalam-KELUAR 43% -$0.36 (lawan -$0.24) | P2-luar-HH 45% -$0.33 (lawan -$0.23).
            $3/$2 sama polanya (-$0.22..-0.34). SEMUA 0/10 th. => dekat dinding harga sedikit BALIK (pola balik / lawan-lanjut rugi
            lebih kecil) tapi tak ada yang menutup biaya. Tidak dipasang.
  [selesai] COLEK -> BALIK SAMPAI MENTOK SISI SEBERANG -> 2 CANDLE BERBALIK -> ENTRY (11 Okt 2026, ide pengguna). research\
            sim_kotak_swing.py -> .txt. BUY: colek atap, lalu low ke zona lantai (<= 10%), lalu 2 candle high & close lebih tinggi
            (close di dalam, <= 60 mnt) -> BUY open berikutnya (SELL cermin). 9.387 setup 2017-26 (~55-73 posisi / bln).
            $3/$3 menang 49% -$0.31 (lawan -$0.32) | $3/$2 40% -$0.34 (lawan -$0.32) | SL titik mentok / TP tengah 46% -$0.36 | SL titik
            mentok / TP dinding seberang 48% -$0.33; semua 0/10 th. Tanpa syarat colek dulu (51 rb setup): -$0.29..-0.32 = sama.
            => ayunan penuh + 2 candle berbalik = koin. Tidak dipasang.
  [selesai] POLA DUA LAPIS STOCHASTIC: M5 = KONFIRMASI, M1 = PEMICU (12 Okt 2026, pengguna: "cari ratusan pola yg m5 sebagai signal
            konfirmasi dan m1 sebagai signal entry"). research\mtf_stoch.py -> .txt / mtf_stoch_sel.csv / .pkl; mtf_stoch_olah.py.
            Excel MQL5\Files\GoldPro\Pola_Stochastic_M5_M1.xlsx (Ringkasan, 200 pola teratas, Konfirmasi M5, Pemicu M1; 0 galat).
            7.200 pola = 13 kondisi M5 x 10 pemicu M1 x 6 setelan (M5 5,3,3 / 14,3,3 / 21,5,5; M1 5,3,3 / 14,3,3) x BELI/JUAL x 5 sesi;
            TP/SL $3/$3, spread asli. LOLOS lengkap 1 (kebetulan 0.0). Pemicu M1 sendiri -$0.41..-0.47 / -$0.20..-0.23 (= spread);
            konfirmasi M5 menambah -$0.03..+$0.01. Kelompok positif: BELI, M5 (14,3,3) silang naik dari bawah 20 & M1 (14,3,3) naik dari
            bawah 20 / sesudah K < 30, sesi NY sore (server 20-01): +$0.076 / pemicu, 7/10 th, 15 mnt +$0.26; per jam WITA 01 -0.21,
            02 +0.02, 03 +0.08, 04 +0.15, 05 +0.69. Semua jam -$0.21 (1/10); cermin JUAL rugi tiap th; tidak bertumpuk ~13/bln
            +$0.014 (~impas), 2025-26 -$0.06. => yang positif = JAM dini hari (sama dgn Tembus Balik), bukan Stochastic. Tidak dipasang.
  [selesai] LACAK POLA STOCHASTIC YANG LOLOS DI SEMUA KONDISI (12 Okt 2026, pengguna: "lacak yg lolos dulu, lalu test kembali di semua
            kondisi, tidak mesti fokus ke garis kotak"). research\lolos_stoch.py -> .txt / .pkl. Pola: BELI, M5 (14,3,3) silang naik
            dari bawah 20 (<= 3 candle) + M1 (14,3,3) silang naik sesudah K < 30 (<= 5), tanpa syarat kotak / sesi.
            SEMUA JAM: n 13.198 (~113 / bln), $3/$3 -$0.21 (17-21 -0.39 / 22-26 -0.04), 2/10 th; keluar lain ($2, $5, TP3/SL2, TP5/SL3,
            1 ATR M5, tutup 15/30/60 mnt) semua minus 10 th (2022-26 $5/$5 +0.105, 2025-26 tutup 30 mnt +0.18). Cermin JUAL minus semua.
            272 sel kondisi (jam, sesi, hari, arah hari, tren H1/D1, volatilitas, kemarin, posisi hari, berita, spread, kedalaman,
            tahun) vs BELI ACAK di kondisi sama: LOLOS 2 (sesi NY sore +$0.04 / +$0.055, acak -0.31 / -0.01; jam 04 WITA +$0.007 /
            +$0.25). Tambahan pola vs acak 2017-21 ~0, 2022-26 +$0.04..+0.47 hampir semua kondisi; jam 02-04 WITA tambahan + kedua periode
            (+0.27..+0.48 / +0.09..+0.25); kemarin ramai +0.18 / +0.21. => pola menambah sedikit atas BELI acak (terutama 2022-26 &
            dini hari) tapi hanya untung bersih di dini hari WITA. Tidak dipasang.
  [selesai] TEMBUS BALIK + POLA STOCHASTIC M5/M1 (12 Okt 2026, pengguna: "coba uji"). research\uji_tb_stoch.py -> .txt.
            12.280 tembusan jam 23 & 03-07 WITA; pola Stochastic searah balik (BELI utk tembus bawah, cermin JUAL utk atas) dicari s/d
            30 mnt sesudah tembus (muncul di 18% tembusan). Aturan tombol (TP tengah, batal 1W, 240 mnt).
            Masuk saat STOCHASTIC muncul: balik 52.7% vs acak 55.1% (lebih -2.4, 2/10 th), $ -0.016 (tombol: 60.3% vs 61.1%, -0.8,
            $ -0.015); 2025-26 $ +1.19 vs tombol +0.90 (hanya baru-baru ini). Tembusan yang DIIKUTI Stochastic, diukur dari candle
            tembus: 52.5% vs 61.6% (-9.2) = tembusan yang lanjut lebih dalam dulu (cocok dgn temuan tembusan besar lebih jarang balik).
            Kelompok "tanpa Stochastic" tampak lebih baik (+1.1) tapi BIAS SELEKSI (termasuk yang sudah balik cepat) - bukan penyaring live.
            => Stochastic TIDAK menambah konfirmasi Tembus Balik; tombol tetap seperti sekarang. Tidak dipasang.
  [selesai] 18 INDIKATOR YANG BELUM PERNAH DIUJI (12 Okt 2026, pengguna: "inidikator apa yg belum pernah diuji?" -> "baik, kita uji").
            research\ind_baru_lib.py (rumus), indikator_baru_umum.py -> .txt / .csv, indikator_baru_tb.py -> .txt / .csv.
            Accelerator, Alligator, Fractals, Gator, BW Market Facilitation Index, Envelopes 0.1 / 0.2%, Standard Deviation, Bulls / Bears
            Power (Elder Ray), Force Index 13 / 2, Chaikin Osc & Money Flow, KAMA, Ehlers Fisher, Schaff Trend Cycle, Vortex, Ultimate
            Osc, Chande Momentum, QQE, Hurst (rasio ragam).
            A. SINYAL UMUM: 28 aturan x M5 / M15 x BELI / JUAL x (semua jam | jam positif) x ($3/$3 | tutup 30 mnt) = 448 sel.
               LOLOS 0 (kebetulan 0.0). Per aturan rata2 -$0.39..-0.59 (17-21) / -$0.18..-0.25 (22-26) = spread; selisih dari BELI /
               JUAL acak +-0.05. Terbaik: BELI M5 Hurst tren + ikut gerak 1 jam di jam positif +0.15 / +0.21 di atas acak, bersih
               -$0.20 / +$0.16 (5/10 th). Catatan: "close silang KAMA" = "KAMA berbelok" (identik secara matematis).
            B. PENYARING TEMBUS BALIK: 25 keadaan x M1 / M5 = 48 (diarahkan ke tembusan). Lebih baik di kedua periode 7/48 (kebetulan
               ~12); tambahan semua dalam +-3 poin (tombol: LONJAKAN +2.4 / +5.8). Pilih-periksa: Hurst > 0.55 M5 +2.8 -> +0.5;
               StdDev mengembang M1 +3.3 -> -0.5. => tidak ada yang menambah; penyaring tombol tetap. Tidak dipasang.
  [selesai] DATA LUAR MT5 - DXY SINTETIS (12 Okt 2026, pengguna: "saya serahkan ke kamu mana yg terbaik dan mudah"). research\dxy_test.py,
            dxy_cek.py -> .txt. Broker tidak punya DXY / obligasi / VIX; DXY dihitung dari M1 broker EURUSD, USDJPY, GBPUSD, USDCAD,
            USDCHF (bobot ICE, tanpa USDSEK), cocok 99.9% menit emas 2017-26. FRED (yield DGS10 / DFII10 / DTWEXBGS) TIDAK bisa dijangkau
            dari PC ini (3x habis waktu) -> tidak diuji; COT & ETF GLD ditunda (mingguan / harian).
            1 KORELASI emas vs dolar 1 mnt -0.26..-0.55 per tahun, beta ~ -1 (2026 -2.25).
            2 CELAH (gerak emas - beta x gerak dolar, z bergulir 1 hari): dagang MENUTUP celah kotor +$0.06..+0.10 / posisi (arah
              sebaliknya sama besar negatif = efek nyata), tapi bersih -$0.20..-0.27 (2017-21 -0.33..-0.39 / 2022-26 -0.07..-0.15),
              0-1/10 th; per tahun bersih + hanya 2026 (+0.29..+0.57) & 2022 (k=15); 2025 negatif. Spread 2025-26 rata2 $0.19.
            3 PENYARING TEMBUS BALIK: dolar 15 mnt mengonfirmasi tembusan emas -> balik LEBIH JARANG (tambahan -3.3 / -2.5); dolar diam
              +0.6 / +0.4; dolar melawan -0.7 / -2.9; gerak emas sendiri searah tembus besar -2.9 / -4.3. Hipotesis "tembusan tanpa
              dukungan dolar = palsu" TIDAK terbukti; tidak ada penyaring yang menambah. Tidak dipasang.
  [selesai] PETA TEKNIK PER JAM WITA (12 Okt 2026, pengguna: "di jam sekian ada yg konsisten menggunakan teknik apa, di jam sekian
            teknik lain juga konsisten ... jam 23 sudah ada, tetap kita simpan, tinggal cari yg lain"). research\jam_teknik.py,
            jam_teknik2.py -> .txt / .csv. 119 aturan (kotak, Stochastic, EMA20 tajam, candle M5 besar, range 60 mnt, RSI2, Bollinger,
            arah jam lalu, PDH/PDL, angka bulat $10, garis GoldPro, LBMA, 28 indikator M5, ORB Tokyo / London / NY, candle berita
            08:30 NY) x BELI / JUAL x 24 jam x 8 cara keluar ($2/$2, $3/$3, $5/$5, TP4/SL2, tutup 15/30/60/120 mnt). LOLOS = n >= 200
            tiap periode, bersih > 0 di 2017-21 & 2022-26, >= 7/10 th, > acak jam & arah & keluar sama.
            1 $3/$3 saja: 5 lolos (kebetulan 0.3) - semua BELI 03-06 WITA. CEK ROLLOVER: 4 dari 5 (03 EMA20 tajam, 04 Bollinger,
              04 RSI2, 05 BW MFI) hilang bila trade ditutup sebelum server 23:55 (BELI acak 05 WITA +$0.79 -> -$0.09 = untung dari
              data rollover, bukan teknik). Bertahan: 06 WITA BELI KOTAK tembus BALIK (+0.09 / +0.42; tanpa masuk 23:30-01:30
              +0.35 / +0.70, 8/10 th) = tombol Tembus Balik yang sudah dipasang.
            2 8 cara keluar, ditutup sebelum rollover: lolos 5 (kebetulan rata2 5.0, 95% s/d 10); jam 07-22 WITA lolos 2 (kebetulan
              4.2); kandidat lemah >= 6/10 th 10 (kebetulan 13.7). Jam bangun = setara kebetulan. Kandidat jam bangun gugur di uji
              silang: 14 WITA BELI angka bulat IKUT $5/$5 (+0.14 / +0.29) -> $3/$3 negatif, cermin JUAL 0/10 th, jam 13 & 15 negatif
              (= arah naik emas 2022-26, bukan teknik); 08 WITA BELI garis GoldPro LAWAN tutup 120 (+0.00 / +3.20 = hanya 2025-26).
              Saudara di jendela sama: 06 WITA BELI KOTAK colek BALIK $5/$5 +0.04 / +0.28 7/10 th (belum dicek rollover).
            => Jam 07-22 WITA: tidak ada teknik data broker yang konsisten. Jendela tetap 23 & 03-07 WITA. Tidak dipasang.
  [selesai] DAGANG DI GARIS KOTAK GELOMBANG (15 Okt 2026, pengguna: "seandainya saya open posisi buy di garis (pas garis atas
            kotak, atau diatasnya sedikit) dan sebaliknya sell, lalu menempatkan stoploss diluar garis, tp ditempatkan di garis
            tengah / sepertiga garis kotak" + "itu yg kita uji, fitur baru" + screenshot Gelombang M1). research\sim_gelombang_garis.py
            -> .txt / .pkl. Kotak = range swing Gelombang (definisi GP_Wave). BUY LIMIT di garis atas kotak hijau Discount (dasar +
            0.05R) / +0.02R; SELL LIMIT di garis bawah kotak merah Premium; SL dasar - 0.02R / - 0.10R; TP sepertiga (R/3) / tengah
            EQ (R/2); garis dihitung ulang tiap candle, SL / TP dikunci saat terisi; ditutup sebelum rollover; spread asli + $0.01.
            M1 / M5 / M15, 2017-26 (M1 119 rb posisi aturan utama).
            - M1: TP kena PERSIS = acak (sepertiga 19 / 19%, EQ 13 / 13%, longgar 33 / 34%, 23 / 25%), kotor -$0.00..-0.05, bersih
              -$0.32..-0.37 / posisi (risiko median M1 $0.39 vs biaya $0.32), 0/10 th semua varian.
            - M5 / M15: TP DI BAWAH acak (M5 17 vs 19, M15 15 vs 20 / 8 vs 13), kotor -$0.06..-0.46, bersih -$0.38..-0.78, 0-2/10 th.
            - Range lebar >= $25 (seperti chart 15 Okt, R $51.50) & 2025-26: M1 19 vs 20% / 12 vs 13%, bersih -$0.22..-0.28; M5 / M15
              lebih buruk (BUY Discount M5 2025-26 kotor -$0.45). Strong / Weak, lebar range: sama. Candle SL & TP sama 0.0-0.2%
              (aturan "SL dulu" tidak mengubah hasil). Per jam WITA: 1 sel (M15 SELL 10 WITA, n 141) vs kebetulan 0.1 (95% s/d 1).
            => Garis kotak Gelombang = peluang geometri yang JUJUR (19% = jarak SL / jarak SL + TP), bukan keunggulan; biaya
               membuat rugi. Sama dgn premium / discount smc_analytics.py 14 Okt. Tidak dipasang.
  [DIPASANG] POLA 3 CANDLE DI GARIS M1 & M5 + NOTIF (16 Okt 2026 11:41 WITA, pengguna + screenshot M1 & M5: "fokus ke tf m1 dan m5,
            lacak ciri-ciri candle yg close di garis premium, eq dan discount ... yg close dan kembali bagaimana? yg tembus bagaimana,
            apakah cukup close 1 candle ditambah 2 candle selanjutnya? ini nanti yg jadi notifikasi, 2 tf ya"). research\gel_candle3.py
            (-> .txt, .pkl). Sentuhan garis M1 345 rb / M5 70 rb (2017-26); close candle sentuh & 2 berikut L (lewat) / D (kembali).
            - SEMUA pola 1 / 2 / 3 candle di semua garis: TEMBUS 1 ATR 48-52% (M5 sel kecil s/d 54%), garis palsu sama. LLL "tembus
              bertahan" M1 48.9% (lebih sering BALIK), DDD "tolak bertahan" M1 51.2% (lebih sering TEMBUS) = M1 berbalik sesudah 3
              candle searah, juga di garis palsu (-1.2 / +0.4).
            - Berapa candle cukup (pola dipelajari 17-21 -> dinilai 22-26 & dibalik, logloss vs acak): M1 1 / 2 / 3 candle +0.02 /
              +0.02 / +0.01% & -0.03 / -0.04 / -0.02%; M5 +0.05 / +0.06 / +0.11% (lebih buruk) -> tidak ada jumlah candle yang menambah.
            - NOTIF (indikator 2026101601, compile 0 / 0, EA tidak berubah): Signal\GP_GarisTg.mqh garis M1 & M5 (input nama baru
              InpGTtfM1 / M5 = true, M15 = false), pesan utama sesudah candle sentuh + 2 candle tutup: pola L/D + nama, peluang tembus /
              balik 1 ATR dari close ke-3 (tabel GT_P3 [TF][garis][pola] dari gel_candle3.pkl), n uji, garis palsu, jarak, range. Pesan
              candle sentuh tutup = InpGT1Candle (mati). Hasil 1 ATR dari close ke-3 (saklar EA "hasil" mati). CSV gelombang_pola.csv.
  [selesai] KONFIRMASI ANTAR TF DI UJUNG RANGE (16 Okt 2026, pengguna: "bagaimana cara melihat pola close dari ujung/dasar garis tf
            besar yg kembali ke dalam range itu bisa terkonfirmasi melalui tf kecil, atau dari tf kecil terkonfirmasi di tf besar ...
            sebagai tanda reversal atau pullback? cari celahnya agar signal dan entry presisi"). research\mtf_konfirmasi.py (-> .txt,
            .pkl). 2017-26, pasangan H1/M5, H1/M1, M15/M5, M15/M1, M5/M1; episode = sentuh garis Premium / Discount TF besar, close di
            ujung (j1) lalu close kembali ke dalam (j2), jendela 6 candle; struktur TF kecil = pivot internal 5 (BOS / CHoCH).
            Model: Z tanpa konfirmasi | A close TF besar kembali | B BOS TF kecil saja | C BOS TF kecil dulu -> close TF besar | C' A tanpa
            BOS | D close TF besar -> BOS TF kecil (SL pivot TF kecil = entry presisi) | D' (SL ekstrem). TP EQ / 1R / 2R / 3R. 102.8 rb
            kejadian.
            - LOLOS 0 dari ~350 kombinasi (+ PULLBACK / REVERSAL). Kotor rata2: Z +0.025R, A -0.016, B -0.050, C -0.003, C' -0.027,
              D -0.043, D' -0.040; bersih semua negatif (terbaik C H1/M5 TP 3R -0.012R, D H1/M5 1R -0.054R).
            - C vs C' (BOS kecil dulu atau tidak): H1/M5 +0.022 vs -0.202R (TP EQ) tetapi M15/M1 -0.031 vs +0.064 -> tidak konsisten.
            - D SL presisi: risiko lebih kecil -> biaya / risiko naik, kotor sama / lebih buruk (-0.04..-0.18R).
            - PULLBACK (searah tren TF besar) kotor -0.012 / -0.017R vs REVERSAL -0.014 / -0.025R (TP EQ / 2R) = sama.
            - Per jam WITA: 1-2 sel lolos = tingkat kebetulan (95% s/d 1).
            => Konfirmasi antar TF hanya menggeser harga masuk & besar SL, peluang tetap = jarak; tidak dipasang. Celah yang
               terbukti tetap: JAM BAGUS (tembus BAWAH kotak 06:10-06:59 WITA -> balik) & kandidat tembus garis M15 (lanjut, bukan balik).
  [DIPERBAIKI] AKURASI TARGET GELOMBANG "SEKARANG" & CIRI-CIRI (15 Okt 2026 23:30, pengguna + screenshot kartu: "seberapa akurat
            angka-angka diatas disentuh? bagaimana ciri-cirinya akan menyentuh area/garis-garis itu?"). research\gel_target_cek.py
            (-> .txt). 168 rb gelombang M1 2017-26, 4.1 jt cuplikan (tiap 5 mnt selama gelombang hidup) x target.
            - KALIBRASI angka chart (dengan koreksi M1 -1.5): 6 -> 8.5 | 15 -> 17.1 | 25 -> 26.4 | 35 -> 36.2 | 45 -> 46.2 | 55 -> 56.0 |
              65 -> 65.9 | 75 -> 75.6 | 84 -> 84.7 | 93 -> 92.5%; semua +1.3 poin (17-21 +0.9 / 22-26 +1.6) = koreksi terlalu besar
              sesudah menit awal (umur <= 15 mnt +0.6, 15-60 mnt +0.9, > 4 jam +2.6). PERBAIKAN (indikator 2026101507, compile 0 / 0):
              koreksi -1.5 hanya s/d 15 mnt sesudah candle BOS (WV_P); CSV saat BOS tetap dikoreksi. Perkiraan sisa selisih +-1 poin.
            - CIRI-CIRI (nyata - angka): gelombang besar / kecil +1.5 / +0.7, MACD M5 / M15 / H1 searah vs lawan +0.9..+1.6 / +0.9..+1.9,
              KOMBI MACD 4 TF +1.1, RSI M15 sangat searah +1.7 vs lawan +0.1, momentum 15 mnt lawan kuat +1.9 vs searah +0.7, searah /
              melawan swing +1.5 / +1.0, bersih / tidak +1.3 / +0.6, jam 05 WITA -1.3, 08-13 WITA +1.8..+2.3 -> semua dalam ~+-1 poin
              dari rata2 (+1.3); satu-satunya penentu = jarak (harga makin dekat target -> angka naik).
            - Uji maju gelombang.csv 14 Okt 13:50 - 15 Okt 20:39: M1 81 gel KENA 61 / 53 / 45 / 41 / 30% vs angka 63 / 59 / 53 / 46 / 38
              (z -0.2..-1.5, belum bermakna); M5 20 gel 62 / 67 / 63 / 63 / 53% vs 67 / 68 / 60 / 49 / 37 (di atas).
  [selesai] ARAH DI RANGE GELOMBANG - KOMBINASI INDIKATOR (15 Okt 2026 malam, pengguna + screenshot M1 harga 65% range: "kira-kira
            kombinasi indikator apa untuk melihat pergerakan harga akan merangkak naik ke equilibrium dan premium, atau arah sebaliknya?
            apa perlu kita retest indikator?"). research\gel_arah.py (-> .txt). 624 rb sampel M1 (tiap 5 mnt) 2017-26, garis dikunci.
            A PREMIUM DULU (sebelum Discount): nyata 51.9% = acak (geometri) 52.0%, 17-21 +0.0 / 22-26 -0.3, per tahun -2..+2.
            B KE EQUILIBRIUM DULU: 50.0% = 50.1%.
            Indikator (M1 / M5 / M15 / H1 close vs EMA20, EMA20 vs EMA50, MACD hist, RSI14; momentum 15 / 60 mnt; open hari ini; arah
            kemarin; tren swing; ATR5/50; KOMBINASI jumlah TF searah): semua |lebih| <= 1.6 poin. Terbesar: MACD hist > 0 di SEMUA 4 TF
            -> Premium dulu +1.5 (n 19.8 rb, 10/10 th); RSI14 M15 atas 20% +1.6, M5 +1.2 (10/10); RSI14 M1 atas 20% -1.1 (M1 balik).
            Model logistik semua indikator: logloss -0.06% / -0.01% (A), +0.00 / -0.05% (B); desil teratas uji +1.0 / +0.6 poin.
            => Arah dari posisi sekarang = hitungan jarak (posisi di range); indikator klasik & kombinasinya menambah <= 1-2 poin.
               Indikator tidak dipasang. [DIPASANG 23:13, pengguna: "baik, kita tambahkan itu"] angka JARAK di kartu "i" Gelombang
               (PREMIUM dulu / DISCOUNT dulu / EQUILIBRIUM dulu dari harga sekarang) & baris "dari sini (jarak)" di pesan Telegram
               sentuh zona (EQ -> Premium / Discount dulu; Premium / Discount -> Equilibrium / ujung range dulu). Indikator
               2026101506, compile 0 / 0 (EA tidak berubah).
  [DIPASANG] TELEGRAM RAPI (15 Okt 2026 13:54 WITA, pengguna + screenshot pesan uji: "notifikasinya sangat berantakan. bisa rapi
            tidak? kotak sideway: menyentuh bawah dan lainnya; gelombang: menyentuh premium, equilibrium, discount; kirim signal lebih
            rapi, tidak usah terlalu banyak dan bercampur aduk; ketika menyentuh, informasikan candle yg sudah tutup"). Indikator
            2026101505, EA Telegram 2026101504 (GP_NEED_TG / GP_NEED_IND ikut). Compile 0 / 0.
            - EA: SATU pesan per kejadian (dulu semua kejadian 2 dtk digabung di bawah judul "Kotak Sideway"); judul per kelompok
              (Kotak Sideway / Gelombang / Tembus Balik / GoldPro / Saldo) + simbol + jam; baris pertama (s/d '^' atau " | ") tebal;
              '^' = baris baru tanpa indentasi; antrean 80; pesan uji pendek (hanya kelompok yang nyala). Saklar nama BARU (agar bawaan
              berlaku): InpKotakBaru / Sentuh / Tembus = true; InpKotakMasuk / Dekat / Hasil / Info = false; InpGelSentuh = true,
              InpGelHasil = false; Tembus Balik / rapor / alarm tetap.
            - Kotak (GP_BoxWatch): TGT "menyentuh ATAP / LANTAI x | candle hh:mm tutup" + high / low lewat $ + close kembali + peluang
              tembus 5 mnt + kotak; mepet jadi tag TGM "mendekati" (saklar sendiri, mati); TEMBUS / MASUK LAGI / KOTAK BARU / KOTAK
              SELESAI / BERTAHAN berjudul singkat + detail per baris. Perkiraan 14 Okt: colek 35 + tembus 42 + kotak 5 + selesai 5
              = ~87 pesan Kotak / hari (dulu ~450 dengan target, hasil & peringatan).
            - Gelombang (GP_GarisTg): zona PREMIUM / EQUILIBRIUM / DISCOUNT (tag GZP / GZE / GZD), SATU pesan saat candle sentuh
              TUTUP, hanya PINDAH ZONA (m1_zona: ~23 / hari, Premium 6 / EQ 11 / Discount 6, jarak median 36 mnt, TEMBUS 48.5%).
              Isi: arah + zona sebelumnya, model candle, lanjut tembus / balik 1 ATR dengan harga, range M1. Pesan candle berjalan
              (InpGTAwal) & konfirmasi (InpGTKonf) mati; hasil dari close candle sentuh (GTT / GTB / GTH, saklar EA mati). CSV baru
              gelombang_sentuh.csv (garis_sentuh.csv lama 2 baris dibiarkan).
  [DIPERBAIKI] EA TELEGRAM TERSUMBAT PESAN YANG DITOLAK (15 Okt 2026 13:40 WITA; ditemukan dari log saat pengguna bertanya kenapa
            notif sentuh garis belum datang). Pesan "GoldPro BERHENTI" berisi "<=" mentah di HTML -> Telegram HTTP 400 "Unsupported
            start tag" -> EA mencoba ulang pesan yang SAMA tiap ~60 dtk selamanya, semua pesan lain tertahan di belakangnya (log:
            14 Okt 15:31-23:42 243x, 15 Okt 11:20-13:34 136x, sampai EA dipasang ulang). Perbaikan EA 2026101503: "<=" -> "maks";
            HTTP 400 -> kirim ulang sebagai teks biasa tanpa HTML, ditolak lagi -> dibuang & dicatat (antrean tidak pernah macet).
            Indikator 2026101504 meminta EA >= 2026101503 (baris merah "EA Telegram VERSI LAMA"). Compile 0 / 0 keduanya.
            Notif sentuh garis sendiri jalan: indikator baru dimuat 13:34:51, CSV garis_sentuh.csv mencatat 13:33 BAWAH naik & 13:34
            EQ (bukan bolak-balik -> tidak dikirim, benar); sentuhan BAWAH bolak-balik ~13:28-13:31 terjadi sebelum indikator dimuat.
  [DIPASANG] NOTIF TELEGRAM SENTUH GARIS GELOMBANG (15 Okt 2026 12:01 WITA, pengguna: tabel model candle di garis "itu dijadikan
            notifikasi, tapi sebelum itu terjadi, artinya saat candle baru menyentuh garis, notif sudah masuk ditelegram, sampai pada
            area konfirmasi balik atau akan terus menembus dan lanjut trad"). Signal\GP_GarisTg.mqh (chart utama, jalan walau tombol
            mati) + EA GoldPro_Telegram. Indikator 2026101502, EA Telegram 2026101501 (GP_NEED_TG / GP_NEED_IND ikut). Compile
            0 / 0 keduanya (salinan sementara dulu).
            - Garis range swing TF terpisah dari chart (default M15; input InpGTM5 / InpGTM1 mati: ~28 / ~135 sentuhan per hari
              dagang vs M15 ~9), definisi = gel_candle.py (pivot swing 50, ATAS 0.95R / EQ 0.5R / BAWAH 0.05R, range >= 2 ATR14,
              sentuhan dari sisi seberang, maks 1 per 3 candle per garis). Jendela 2000 candle = garis sejarah penuh (cek_jendela:
              0 beda di k >= 300).
            - 4 pesan: GTS SENTUH (candle berjalan; % semua sentuhan) | GTC candle TUTUP (model 1 candle + TEMBUS / BALIK 1 ATR
              dengan harga target, n uji, garis palsu) | GTK KONFIRMASI (model 2 candle) | GTT / GTB / GTH HASIL (1 ATR dari close
              konfirmasi, candle M1, berhenti sebelum 23:55 server / 24 jam; candle M1 kena keduanya = tidak dinilai). Kunci
              GV GP_GT_<simbol>_<tf>_<garis> (ganti TF tidak dobel); hasil yang selesai sebelum dimuat ulang tidak dikirim.
            - Angka % TEMBUS = gel_candle.pkl garis asli gabungan 3 garis & 2 arah (M1 / M5 / M15), garis palsu ditampilkan.
            - Uji maju: MQL5\Files\GoldPro\garis_sentuh.csv (model, %, hasil tahap tutup & konfirmasi).
            - Saklar EA: InpSendGaris (sentuh / tutup / konfirmasi), InpSendGarisHasil (hasil).
            - 12:55 (pengguna: "kita fokus ajalah dulu ke m1" -> pilih "bolak-balik saja"): default garis M1, hanya sentuhan
              BOLAK-BALIK (ATAS / BAWAH pertama sesudah sentuhan terakhir di garis seberang; EQ tidak dikirim). Input baru (nama
              baru agar default berlaku): InpGTfM1 = true, InpGTfM5 / InpGTfM15 = false, InpGTBolak = true. CSV = semua sentuhan
              (kolom bolak, dikirim). Indikator 2026101503, EA Telegram 2026101502 (teks pesan uji; GP_NEED_TG tetap 2026101501).
              Compile 0 / 0. Data M1 2017-26 (scratchpad m1_bolak / garis_m1_hari): sentuhan ~135 / hari (ATAS 45 / EQ 56 / BAWAH
              36), jarak median 4 mnt (38% <= 3 mnt), 92% berulang di garis sama; bolak-balik 6.4 / hari, jarak median 166 mnt
              (75-310); TEMBUS bolak-balik 49.1% vs berulang 49.5% (sama). Garis bergeser: puncak / dasar swing baru ~10 / hari
              masing2, puncak ditembus ~49 candle / hari (2025-26 58), 7-8% candle M1 menggeser garis; umur puncak median 75 mnt.
  [selesai] MODEL CANDLE DI GARIS GELOMBANG + ATURAN GARIS HIJAU (15 Okt 2026, pengguna + screenshot Peta Gelombang M1: "teliti
            bagaimana model candle saat sampai ke garis bawah, atas dan equilibrium ... yg close dan terkonfirmasi kembali, dan yg menembus
            lalu lanjut trandnya. kedua, aturan garis hijau, persentase bagaimana yg benar-benar kena"). research\gel_candle.py (-> .txt,
            .pkl). Garis ATAS / EQ / BAWAH + GARIS PALSU 0.27R / 0.73R; sentuhan M1 345 rb, M5 70 rb, M15 23 rb; 7 model 1 candle + 7
            model 2 candle; hasil = 1 ATR ke arah tembus (LANJUT) atau berlawanan (BALIK) dulu, acak ~50%.
            - M1: SEMUA model 48.4-51.3% (TEMBUS KUAT 48.7, 2 candle LANJUT 48.5, BALIK KONFIRMASI 51.3 = sedikit kembali MENEMBUS),
              garis palsu SAMA (+-0.6) -> bentuk candle di garis M1 tidak memberi arah.
            - M15: candle "kembali" justru lebih sering diikuti TEMBUS: PIN BAR 53.1% (palsu 50.5), BALIK LEMAH 52.9 (50.1), COLEK
              BIASA 51.6 (50.3); terkuat BAWAH dari atas colek close kembali 54.2% turun (17-21 +4.2 / 22-26 +3.8), EQ dari atas balik
              lemah 55.0%. TEMBUS KUAT 49.9% (tidak lanjut). Sel konsisten 5/126, semua arah LANJUT; DAGANG 1 ATR (ATR M15 ~$2.3, biaya
              $0.32) rugi -0.11..-0.28R, 1-2/10 th. => pantulan di garis M15 sering palsu (info / peringatan, bukan sinyal).
            - GARIS HIJAU: sesudah target KENA -> target berikut sebelum BATAL M1 78.6 / 78.8 / 81.4 / 76.1% vs geometri 78.6 / 78.6 /
              80.9 / 76.4 (n 55-73 rb; M5 / M15 & kedua periode sama) -> angka "sekarang" dashboard tepat. CLOSE lewat garis 82-85% vs
              EKOR saja 68-72%, tapi terhadap geometri dari close sama (-1..-2) -> tidak perlu menunggu close. Persen tinggi karena BATAL
              jauh (1.618A -> 2.0A 81% tapi untung 0.382A vs risiko 1.618A = nilai harapan ~0).
            - Uji maju gelombang.csv 14 Okt 13:50 - 15 Okt 10:12: M1 57 gel KENA 57 / 48 / 38 / 35 / 26% vs angka 61 / 58 / 51 / 45 / 37
              (di bawah, z ~ -1.7, gelombang tumpang tindih -> belum bermakna; awasi s/d ~200 gel); M5 13 gel 71 / 70 / 58 / 58 / 50% vs
              71 / 64 / 56 / 45 / 35.
  [kandidat] VARIASI SL / TP / RR DI GARIS GELOMBANG (15 Okt 2026, pengguna: "coba uji dengan berbagai aturan sl dan tp, mulai dari
            garis equilibrium, atas dan bawah. variasikan RR nya"). research\sim_gelombang_rr.py (-> .txt, .csv) + sim_gelombang_tembus.py
            (-> .txt). Garis ATAS (puncak - 0.05R) / EQ / BAWAH (dasar + 0.05R); 8 setup = BALIK (LIMIT memantul) & TEMBUS (STOP lanjut)
            di tiap garis (EQ dari atas & dari bawah); SL 0.05R / 0.10R / 0.20R / $1 / $2 / $3 / $5 x RR 0.5 / 1 / 1.5 / 2 / 3 + TP garis
            berikut (0.45R); M1 / M5 / M15; 966 kombinasi x 2 aturan urutan candle (JALUR O-L-H-C / O-H-L-C & HATI2 SL dulu - aturan
            hati2 saja membuat TEMBUS M1 tampak -10 poin; candle SL & TP sama rata2 3% jalur / 15% hati2).
            - BALIK (ide awal pengguna) di SEMUA garis / TF / SL / RR: TP 3-7 poin DI BAWAH acak (mis. M15 BAWAH balik BUY SL 0.10R RR 2:
              26 vs 33%), bersih -$0.31..-0.71, kotor > 0 di 2 periode 4/504. RR tidak memperbaiki: RR besar = TP makin jarang (geometri).
            - TEMBUS (BUY STOP garis bawah kotak merah / SELL STOP garis atas kotak hijau / EQ): kotor POSITIF +0.05..+0.17R, M15 32/35
              kombinasi tiap sisi kotor > 0 di kedua periode, kedua aturan candle, kedua arah (= efek momentum masuk Premium / Discount).
            - LOLOS 1 (jalur): M15 ATAS tembus BUY SL 0.20R RR 3: n 2.311 (~20/bln), TP 18% (acak 25%; untung juga dari tutup waktu
              28% +0.56R), 17-21 +0.015R / 22-26 +0.137R, 8/10 th (hati2 -0.014 / +0.093R, 7/10). RR 2: +0.006 / +0.127R.
              Cermin SELL STOP garis hijau RR 3: -0.010 / +0.065R; rasio risiko / biaya >= 15 (dipilih di 17-21): +0.059 / +0.083R 9/10.
            - Biaya vs risiko: rasio < 5 rugi (2017-21 risiko kecil); >= 5-15 bersih +0.03..+0.20R -> 2017-21 tipis, 2022-26 lebih baik.
              M5 bersih + hanya 22-26 / rasio >= 10; M1 rugi (biaya).
            - 2025-26 M15 BUY RR 2: risiko lot 0.01 median $14.82 ($9.63-24.04), rugi beruntun maks 8 (RR 3: 12), turun terdalam 10.6R
              (RR 3: 14.4R), bulan + 16/22.
            => KANDIDAT (belum dipasang): tembus garis Premium / Discount M15, SL 0.20R, RR 2-3, rasio risiko / spread >= 5-15. Untung per
               posisi kecil (+0.07..+0.14R), 17-21 hampir 0, dipilih dari 966 kombinasi -> perlu uji maju sebelum dipakai.
  [DIPASANG] PERBAIKAN & PENINGKATAN (14 Okt 2026 13:28-13:50 WITA, pengguna: "apa yg kamu usulkan kita eksekusi. jika masih ada
            yg belum presisi, segera update dan upgrade"). Versi indikator 2026101407. Compile 0 / 0 (cek salinan sementara dulu).
            1 SATU RANGE: tombol Gelombang nyala -> RenderDealingRangeZones SMC lama tidak digambar (Premium / OTE / EQ / Discount
              kecil tidak bertabrakan dengan range swing lebar).
            2 GELOMBANG: BOS internal terbaru tidak bersih -> gelombang bersih terakhir tetap digambar (redup, "lama") + label status
              ("menunggu BOS bersih" / "LAMA"); label di DALAM chart (WV_RightT: ujung kanan tidak melewati tepi chart, anchor kanan)
              & didaftarkan ke GP_LabelFix (maks 1 langkah geser - screenshot: label 1.272A / 1.618A sempat terdorong ~85 px).
            3 UJI MAJU GELOMBANG: MQL5\Files\GoldPro\gelombang.csv (per simbol & TF, hanya gelombang SESUDAH dipasang, dicatat saat
              batal / semua target kena / 2 hari; kunci GV GP_WVJ_<simbol>_<tf>); kartu "i": KENA / harapan per target.
            4 Label likuiditas "SWEPT" tidak digambar (garis titik tetap). 5 OTE & Equilibrium SMC = garis tepi tanpa isi (tidak ada
              warna campuran MT5).
            6 TOMBOL KE-15 "MODE TERUJI": simpan pilihan tombol (GV sv_*), nyalakan Gelombang / Target / Cadangan / Tembus Balik,
              matikan SMC lama termasuk kotak OB / Breaker & label BOS / CHoCH; klik lagi = pulihkan.
            7 ANGKA KHUSUS M1 (research\m1_cek.py; gelombang.py dioptimalkan bisect - dulu O(n2), M1 > 10 mnt -> 28 dtk):
              gelombang_m1.txt (110.543 gelombang bersih): 1.0A 64 | 1.272A 56 | 1.618A 46 | 2.0A 38 | 2.618A 29%, NYATA - ACAK
              -0.0..-2.3 (rata2 ~-1.5) di semua sel -> chart M1: peluang live dikurangi 1.5 poin; jauh gelombang 0.92 / 1.50 / 3.0 /
              7.4A. smc_peta_m1.txt (~4 jt sentuhan): OB/Brk colek-tolak 79 | dalam 59 | 1 close luar sungguhan 77 | 2 close 81 |
              pin 79 | engulf 85; FVG 72 | 54 | 71 | 76 | 72 | 79; asli - palsu -2.9..+1.6 (= zona acak) -> SMC_PA1 dipakai di M1.
            8 13:57 (screenshot pengguna, v2026101408): gelombang "LAMA" & sudah batal tampil terus, pita Equilibrium biru tua
              (abu + pita coklat peta harian dicampur MT5). Cek gelombang TIDAK BERSIH (cek_tidakbersih, gelombang.pkl /
              gelombang_m1.pkl): M5 / M15 nyata = jarak +-2.5, M1 -1.0..-2.7 (koreksi M1 sama) -> BOS internal TERBARU selalu
              digambar (tidak bersih diberi tanda), target yang sudah terlewati saat BOS = "dilewati" (tidak dinilai di uji maju;
              CSV + kolom "bersih"), pita Equilibrium Gelombang = garis tepi. Compile 0 / 0.
  [DIPASANG] TOMBOL KE-14 "GELOMBANG" - PETA GELOMBANG (14 Okt 2026 12:35 WITA, pengguna: "kita bikin yg lebih lebar dengan
            perhitungan matang ... dari range kecil sebagai gelombang awal untuk melihat tujuan ke gelombang lebih jauh. hitung secara
            akurat, jangan asal gambar" + screenshot SMC Analytics; "warnanya yg membuat saya bingung"). Versi indikator 2026101403.
            RISET research\gelombang.py -> .txt, .pkl (M5 & M15 2017-26, pivot gaya LuxAlgo: swing 50, internal 5; BOS internal
            bersih 12.160 / 10.175 M5, 4.218 / 3.414 M15 searah / melawan swing):
            - sampai T = L1 + k x A sebelum L1 tertembus: 1.0A 64% | 1.272A 57% | 1.618A 47% | 2.0A 39% | 2.618A 30%; NYATA - ACAK
              (hitungan jarak) -2.3..+1.5 poin di semua sel, searah = melawan swing, 2017-21 = 2022-26; habis waktu 2 hari < 5%.
              Weak swing searah 60% (acak 61), melawan 29-33% (acak 31-34).
            - jauh gelombang (puncak sebelum batal, dari L1): 25% 0.93-1.01A | 50% 1.52-1.61A | 75% 2.9-3.2A | 90% 5.0-6.9A; sama
              searah / melawan, kedua periode. Gelombang tidak bersih lebih panjang (median 3.7A) karena A kecil.
            => angka TEPAT (stabil) tapi = geometri; jejak institusi tidak terbukti -> peta INFO dengan peluang hitungan jarak live.
            FILE: Map\GP_Wave.mqh (prefix GPW_; pivot swing / internal di TF chart, 3.000 candle, hitung ulang tiap candle baru):
            range swing lebar Premium 5% (merah) / Equilibrium 47.5-52.5% (abu) / Discount 5% (hijau), garis puncak merah & dasar
            hijau (padat = Strong, putus = Weak menurut tren swing), label posisi harga %; GELOMBANG AWAL = BOS internal terakhir
            yang bersih (emas), pullback = BATAL (oranye), target 1.0-2.618A (biru titik) dengan status KENA / batal / peluang
            sekarang = (harga - batal) / (target - batal). Kartu info "i": range, gelombang, target, angka uji. GP_DayMap: BTN_N 14,
            g_vWave (GV "wave"), INFO_KEYS + "wave", prototipe WV_InfoLines. GoldPro_Main: include, timer, event, deinit, bersih.
            SESUDAH COMPILE: ganti TF sekali di tiap chart GoldPro.
            PERBAIKAN 12:41 (screenshot pengguna, v2026101404): garis putus-putus SMC menyilang tulisan tombol (MT5 menggambar
            menurut urutan dibuat) -> GDM::RaiseButtons: tombol, kotak "i", label LIVE & kartu info dibuat ulang paling akhir di
            Rebuild & sesudah GP_RenderAll (maks 1x / 5 dtk). GP_LabelFix: kotak label diberi jarak aman 3 / 2 px ("Bearish OB" &
            "Tujuan BSL swing" bersenggolan). Compile 0 / 0.
            PERBAIKAN 13:09 (screenshot pengguna, v2026101405): kartu SMC INFO menulis "colek lalu close balik -> BALIK NAIK 80%"
            padahal candle BERJALAN sudah jatuh $3 di bawah batas tembus. Kini candle berjalan dicek: batas tembus / target balik
            tersentuh -> "LIVE: SUDAH TEMBUS / BALIK ... SELESAI" (angka lama tidak berlaku); di luar tepi jauh -> "bila close -> TEMBUS
            x%"; lainnya "LIVE: belum ada yang tersentuh". Jam candle keputusan ditampilkan. Compile 0 / 0.
  [DIPASANG] KOTAK "i" INFO DI SAMPING TIAP TOMBOL (14 Okt 2026 11:06 WITA, pengguna: "ada kotak juga disampingnya, kotak info,
            contoh smc (khusus gambar), disamping smc info, berarti info tentang smc, dan semua begitu"). Versi indikator 2026101401
            (EA Telegram & Panel tidak berubah; EA Panel membaca posisi baru lewat GV). Compile 0 / 0 (cek salinan sementara dulu).
            - Map\GP_DayMap.mqh: kolom tombol + kotak "i" 16 px (BtnColR melebar -> panel, dashboard, label LIVE ikut geser; tanda
              "!" EA di GP_TBX_ = kanan kotak "i"). IBtn / OnInfo; flag g_iBox / g_iTbk / g_iNews (GV i_box / i_tbk / i_news);
              kartu info umum g_infoKey (GV infok, satu sekaligus; objek GPM_IC_*, diperbarui tiap 2 dtk, tidak menimpa panel 1 PETA,
              panel Trade, dashboard Kotak / Tembus Balik / Saldo; probe tidak menimpa kartu). Isi kartu: InfoSMC (bias, zona OB /
              FVG aktif terdekat, baca candle TF chart terakhir di zona -> SMC_PA tabel smc_peta.py, target 1 ATR & batas tembus),
              InfoTarget, InfoBackup, panduan 1 PETA / 2 CEK SIAP / Probe, daftar PIN, Trade, Saldo.
            - Tombol utama = GAMBAR: Kotak Sideway hanya garis (GP_BoxWatch: dashboard pindah ke g_iBox); Tembus Balik = TB_Marks
              (panah + garis TARGET / BATAL + label hasil, 24 jam, prefix GPI_M; dashboard & strip pindah ke g_iTbk); Berita =
              NBVLines (garis vertikal rilis 2 jam lalu s/d 24 jam, prefix GPN_V; dashboard pindah ke g_iNews).
            SESUDAH COMPILE: ganti TF sekali di tiap chart GoldPro (M1 > M5 > M1). Status lama "box" / "tbk" / "news" kini berarti
            GAMBAR; dashboard-nya dibuka lewat kotak "i".
            PERBAIKAN 11:28 (screenshot pengguna, v2026101402): label SMC di ujung kiri garis ("LIQ PDOL ... SWEPT", "EQL (2x) @ ...
            SWEPT", "Daily Open") menimpa tombol Target / Cad80 / SMC / Probe / +PIN. Render\GP_LabelFix.mqh: area kolom tombol +
            kotak "i", label LIVE, kartu info, panel halaman, dashboard Kotak / Tembus Balik / Saldo / Berita = TERLARANG; label SMC
            yang jatuh di situ digeser ke KANAN area itu (+1 lebar candle; harga tetap, dihitung ulang dari posisi asal tiap 2 dtk /
            geser chart), lalu tetap dicek tumpukan naik / turun seperti biasa. Include dipindah sesudah GP_DayMap. Compile 0 / 0.
  [selesai] PETA ARAH SMC GOLDPRO: JAM SINKRON, COLEK-BALIK / TEMBUS, MODEL CANDLE (14 Okt 2026, pengguna: "petakan jam-jam berapa
            harga benar-benar sinkron dengan sistem smc ... aturan candle singgah colek lalu balik, menyentuh garis dan menembusnya,
            model candle konfirmasi ... levelnya lebih tinggi dan akurat"). research\smc_peta.py -> .txt, .pkl. Level = replika mesin
            SMC GoldPro (OB, Breaker, FVG) + garis swing (fractal 5), M5 & M15, sentuhan pertama, zona PALSU pembanding, acak geometri.
            1 PELUANG BALIK 1 ATR sebelum TEMBUS 1 ATR (17-21 / 22-26 stabil +-1-2 poin): OB/Breaker colek-tolak 80%, close di dalam
              57-59%, close tembus 20-25%, sesudah 1 close tembus 20-22% (= 78-80% tembus sungguhan), 2 close 17%, pin bar 79-81%,
              engulfing 87-90%; FVG 72 / 54 / 31 / 29 / 23 / 73 / 79-81%; garis swing 67 / - / 33 / 33 / 27 / 68-72 / 78-81%.
              TAPI zona PALSU sama (asli - palsu -5..+4, hampir semua +-1) & acak geometri sama (asli - acak -2..+4) -> angka akurat
              tapi milik POSISI CLOSE terhadap garis, bukan milik zona SMC.
            2 JAM SINKRON (asli - palsu >= +3 & > acak di kedua periode): 17 dari 787 sel, kebetulan rata2 19.8 (95% s/d 26) = TIDAK
              ADA jam sinkron. Paling rapi: M15 OB/Breaker close di dalam zona 14 / 17 / 19 / 23 WITA (asli 59-65% vs palsu 46-58%).
            3 DAGANG (SL tepi jauh + 0.1 ATR, TP 1.5R): semua bersih negatif 2017-21, asli = palsu. Kandidat lemah: M15 OB/Breaker
              ENGULFING asli - acak +3.6 / +2.9 (n 357 / 349), dagang -$0.06 / +$0.85, 4/10 th - hanya uji maju.
  [selesai] SMC ANALYTICS MT5 dari Market (14 Okt 2026, pengguna: "coba cek sistem smc ini di dalam mt5, itu yg saya ambil di
            market"). File MQL5\Indicators\Market\SMC Analytics MT5.ex5 (116.552 byte, sama dengan Indicators\SMC.ex5) terkunci -> kode
            tidak bisa dibaca; tampilannya = desain LuxAlgo SMC (Strong High / Weak Low, Premium / Equilibrium / Discount, EQH / EQL,
            BOS / CHoCH internal & swing, OB, FVG, PDH / PDL). Bagian yang SUDAH diuji: BOS / CHoCH & OB LuxAlgo (luxalgo_smc.py,
            arah 48.7-51.4% = koin, OB asli = OB palsu, 0/8), OB / Breaker / FVG (smc_react / smc_map / smc_break: pantul sama
            dengan zona palsu, 0/162 sel), PDH / PDL (jam_teknik.py, 0). BARU research\smc_analytics.py -> .txt (M5 & M15, 2017-26):
            1 PREMIUM -> JUAL / DISCOUNT -> BELI (5% ujung rentang swing): 0 lolos, ikut maupun dibalik rugi -$0.13..-0.53.
            2 SAPU EQH -> JUAL / EQL -> BELI: 0 lolos (dibalik juga 0). Per jam WITA 0 / 384 (kebetulan 0.1).
            3 STRONG / WEAK: sampai WEAK dulu +0.9..+4.7 poin di atas acak, TAPI pada posisi harga yang sama di rentang label tren
              hanya -0.9 / +0.7 (2017-21) dan +2.0 / +3.1 (2022-26) = efek tren 2022-26 saja. Dagang searah tren (TP weak, SL
              strong) dengan perhitungan JUJUR (habis waktu ditutup, candle sama -> SL): -$0.44 / -$0.16..-0.27, 1/10 th = sama
              dengan LAWAN tren. (Versi "hanya trade yang selesai" sempat +$0.56 / +$2.98 10/10 th = bias buang trade belum
              selesai, TP dekat $10 vs SL jauh $29 - DIKOREKSI.) => SMC Analytics tidak membawa info arah. Tidak dipasang.
  [selesai] TRIPLE SUPERTREND (14 Okt 2026, pengguna: "teori baru yang beredar di internet ... 3 supertrend: atr 20 faktor 3, 10 / 1,
            11 / 2"). research\supertrend3.py, supertrend3_lawan.py -> .txt, supertrend3.csv. SuperTrend = TradingView ta.supertrend
            (numba). TF M1 / M5 / M15; R1 ketiga searah, R2 "Trade Pro" (>= 2 dari 3 + EMA200 + StochRSI silang dari jenuh), R3 ST
            cepat (10,1) berbalik searah 2 lainnya; keluar E1 SL garis ST ke-2 / TP 1.5R, E2 mayoritas ST berbalik, E3 $3/$3; ditutup
            sebelum jeda harian, spread asli. LOLOS 0 / 54 sel (rata2 bersih -$0.44 / -$0.12); per jam WITA 0 / 864 (kebetulan 0.4).
            Sinyal M1 37-47 / hari, M5 4-8, M15 2-3. Hanya M15 di 2022-26 sebagian + (R2 JUAL E1 +$0.94, R1 E1 +$0.39..0.43) tapi
            2017-21 rugi semua, th+ <= 5/10. KENA TP di bawah acak di KEDUA arah (dibalik / melawan sinyal juga 0 / 36, per jam 0 /
            864; $3/$3 ikut 41-48% vs lawan 42-48%) = selisih karena trade habis waktu & aturan candle sama, bukan arah -> SuperTrend
            tidak membawa info arah. Tidak dipasang.
  [DIPASANG] JAM BAGUS TEMBUS BALIK - dashboard + Telegram (12 Okt 2026 19:05 WITA, pengguna: "kumpulkan jam-jam bagus itu dan
            masukkan di dalam dashbord serta notif ke telegram"). Versi indikator & EA Telegram 2026101201 (EA Panel tetap
            2026101002). Compile GoldPro_Main + GoldPro_Telegram 0 error / 0 peringatan (cek salinan sementara dulu).
            RISET research\tbk_jam_bagus.py -> .txt (per MUSIM x JAM SERVER x ARAH, aturan tombol TARGET tengah / BATAL 1W / 240 mnt):
            - G1 tembus BAWAH jam server 01 (= jam pertama sesudah pasar buka): KENA 60.9 / 74.1% vs acak 59.3 / 59.6 (8/10 th);
              musim panas (06 WITA) +2.9 / +11.8, musim dingin (07 WITA) -1.6 / +21.2 = menempel ke JAM SERVER. Menit 00-09
              +0.9 / +12.5, menit 10-59 +1.9 / +15.4 (62.5 / 76.9% vs 60.6 / 61.5; $ -0.31 / +0.76) -> dipasang menit 10-59.
            - tembus ATAS: server 01 +9.4 / -0.6, server 02 +0.9 / +2.9; 07 WITA +3.9 / +5.7 (63.3 / 66.2% vs 59.4 / 60.4) tapi
              per musim tidak stabil (panas server 02 +1.3 / +8.0, dingin server 01 +11.4 / -1.2) -> G2 LEMAH, dashboard saja.
            FILE: Signal\GP_TembusBalik.mqh (TB_Good, TB_EvP / TB_EvS, TB_G1Start, TB_GoodStatus, TB_GoodTick pengingat, kolom CSV
            jam_bagus G1 / G2, status PASAR TUTUP jeda harian server 23:55-01:00, strip baris ke-4 S3, input InpTBGoodRemind),
            Signal\GP_Health.mqh (versi), Experts\GoldPro\GoldPro_Telegram.mq5 (ikon TBGJAM weker+bintang, TBG bintang+panah,
            TBGOK / TBGNO / TBGTO, saklar InpSendTbg). Pesan G2 & jam lain tetap TBK (+ "LEMAH" / "jam ini setara acak").
            SESUDAH COMPILE: ganti TF sekali di tiap chart GoldPro (M1 > M5 > M1) & pasang ulang EA GoldPro_Telegram.
  [selesai] JALAN 1 (JENDELA STRUKTURAL) & JALAN 2 (DATA LUAR) (12 Okt 2026, pengguna: "2 jalan itu kita implementasi", "unduh semua").
            JALAN 1 - research\colek_balik.py, tbk_rollover.py, gerak_rollover.py -> .txt.
            1 COLEK dinding kotak (high/low sentuh dinding, close di dalam) -> tengah, aturan tombol (TARGET tengah, BATAL 1W, 240 mnt,
              ditutup sebelum rollover): LOLOS 0 dari 137 sel jam x jenis x arah. 06 WITA colek BELI KENA 72/81% (acak 72) tapi $ -0.43 /
              -0.07. Tidak ditambahkan.
            2 JEDA HARIAN BROKER: XAUUSD tutup server 23:55 - 01:00 (candle pertama hari = 01:00 di 2.374 hari) = 04:55-06:00 WITA saat
              AS musim panas, 05:55-07:00 WITA mulai 2 Nov 2026. 5 mnt pertama sesudah buka bid naik rata2 +$0.61 (t 8.9, 10/10 th;
              spread tercatat $0.51 vs $0.34 biasa) = harga di sekitar jeda tidak bisa dipercaya; +5 mnt -> 02:00 +$0.28 (kebanyakan 2025-26).
            3 TEMBUS BALIK dicek ulang: 03-05 WITA ~1/4 KENA baru tercapai SESUDAH pasar buka lagi (KENA di menit jeda sendiri hanya
              ~2%); bila ditutup sebelum jeda KENA 03 WITA 43-47%, 04 WITA 28-33% (acak 61-62). Jadi 03-05 WITA = harus menahan posisi
              melewati jeda (swap + lonjakan spread). 06-07 WITA (sesudah buka, tanpa jeda): KENA 63-67% vs acak 59-60 (+3..+8) = jendela
              paling bersih; $ 17-21 masih negatif (spread). 23 WITA: KENA 56-60% vs acak 61 (tidak di atas acak; $ + hanya 2022-26).
            JALAN 2 - research\cot_test.py -> .txt; data research\cot_emas.csv (CFTC fut_disagg_txt_2017..2026.zip, 20.6 MB, baris
              088691 GOLD COMEX, 510 minggu s/d 6 Okt 2026; zip di scratchpad, tidak disalin). GLD (spdrgoldshares.com) GAGAL: alamat
              arsip CSV kini mengarah ke PDF daftar batangan -> berhenti, tidak disimpan.
            4 COT: H1 MM jenuh lawan / H2 aliran MM ikut / H3 komersial ekstrem / H4 MM vs rata2 26 mgg x jeda +4 & +11 hari.
              Scalp $3/$3 searah condong vs arah acak: -$0.041..+0.007 (p 0.11-0.93). Harian: H2 jeda +4 -$0.98/hari (9/10 th, p 0.05)
              tapi jeda +11 -$0.04 (p 0.94) = tidak kuat. Penyaring Tembus Balik: searah condong lebih baik hanya di 2022-26. => COT
              tidak membantu scalping. Tidak dipasang.
  [DIPASANG] TOMBOL KE-13 "TEMBUS BALIK" - jam positif + rekap indikator + Telegram (11 Okt 2026 22:12 WITA, pengguna: "buatkan
            tombol baru yg merekap indikator itu, tampil di bawah chart lalu ditampilkan di dalam dashboard sesuai jamnya, dan
            dikirim ke telegram"). Versi indikator & EA Telegram 2026101101 (EA Panel tetap 2026101002, tidak berubah).
            Compile GoldPro_Main + GoldPro_Telegram 0 error / 0 peringatan (cek salinan sementara dulu).
            FILE: Signal\GP_TembusBalik.mqh (BARU, prefix objek GPI_). Sambungan: GP_BoxWatch (TB_Break di 2 titik TEMBUS, TB_Bar tiap
            candle M1, TB_Reset; mesin kotak juga jalan di chart tampilan bila dashboard Tembus Balik dibuka), GP_DayMap (tombol
            "tbk" indeks 12, BTN_N 13, probe tidak menimpa GPI_BG), GoldPro_Main (include, TB_Update di timer, event, deinit),
            GP_Health (versi), Experts\GoldPro\GoldPro_Telegram (ikon TBK / TBKOK / TBKNO / TBKTO, saklar InpSendTbk).
            ATURAN (dari research\jam_positif.py, indikator_jam_positif.py, tbk_angka.py): kejadian = TEMBUS mesin kotak (candle M1
            pertama close di luar dinding, termasuk loncat) yang candle-nya jam 23 atau 03-07 WITA; server 23:50-23:59 = dilewati.
            TARGET tengah kotak, BATAL 1W di luar dinding (candle sama -> batal dulu), HABIS 240 mnt. Penyaring dinilai di candle
            tembus: LONJAKAN = vol M1 / rata2 60 candle >= 2 atau ATR5/ATR50 M1 >= 1.5; M5 BELUM IKUT = RSI7 M5 < 50 (atas) / > 50
            (bawah) atau kemiringan MACD 10,22,4 M5 melawan (dihitung sendiri dari 300 close M5, candle M5 tutup terakhir).
            YAKIN = kategori: L+B 59% (acak 56), L 59 (57), B 63 (62), tanpa 60 (62). Telegram lewat KB_Out (kunci & SUSULAN sama).
            Uji maju: MQL5\Files\GoldPro\tembus_balik.csv (chart utama, kunci GP_TBJ_KEY). INFO, bukan sinyal; tidak membuka order.
            SESUDAH COMPILE: ganti TF sekali di tiap chart GoldPro (M1 > M5 > M1) & pasang ulang EA GoldPro_Telegram.
            PERBAIKAN 23:04 (screenshot pengguna, v2026101102 indikator saja): strip "TB |" dulu tertutup dashboard Kotak bila
            chart utama pendek (jendela RSI) -> strip digeser ke kanan dashboard yang menimpanya; akhir pekan dulu tertulis
            "JAM POSITIF sekarang" -> kini "MARKET TUTUP" bila tick terakhir > 10 mnt. Compile 0 / 0.
  [selesai] STRATEGI RANCANGAN CLAUDE "BELI KOREKSI TAJAM SEARAH ARUS" (11 Okt 2026, pengguna: "coba kamu buat strategi sendiri").
            research\sim_claude.py -> .txt / .pkl. Aturan dikunci sebelum melihat hasil: hanya BUY bila close D1 kemarin > SMA50 D1;
            pemicu M15 close <= EMA20 - 1.6 ATR14 (M15); masuk open M1 berikutnya; maks 1 / hari, satu posisi sekaligus.
            V1 TP/SL 0.25 ADR 24 jam: n 1.202, menang 52%, R -0.014, 4/10 th (BUY acak -0.028) -> rugi.
            V2 tanpa TP, SL 0.5 ADR, tutup 24 jam: n 926, menang 47%, R +0.117, +$1.77/posisi, 2017-21 +0.022 / 2022-26 +0.204,
               8/10 th (2020 & 2021 minus). TAPI BUY WAKTU ACAK di hari arus naik, keluar sama: R +0.105 (20x: +0.053..+0.158)
               -> pemicu TIDAK lebih baik dari acak; untungnya = arus naik emas 2017-26 yang ditahan 24 jam. Tanpa syarat arus
               +0.090; cermin SELL -0.047. Lot tetap 0.01: total +$1.643 / 10 th, turun terdalam $665, rugi terbesar $118,
               7 kalah beruntun, ~94 posisi / th; $100 -> $1.743 (sempat $25), $200 -> $1.843 (sempat $125).
            V3 TP 0.5 / SL 0.25 ADR 48 jam: R +0.058 vs acak +0.027 (-0.057..+0.069), 6/10 th; $100 bangkrut.
            => bukan scalping, bukan 7%/hari, bergantung arus naik emas (pasar turun panjang = rugi). Tidak dipasang.
  [selesai] PELACAKAN MENIT & BENTUK CANDLE KONSISTEN 5-10 MNT (11 Okt 2026, pengguna: "lacak siapa tau ada kesamaan bentuk candle yg
            stabil, waktu konsisten naik 5-10 menit atau sebaliknya, di menit keberapa dan sesi apa"). research\pola_menit.py -> .txt.
            Sel: menit dalam hari (1.440), hari x menit (7.200), sesi x menit ke- dalam jam (300), sesi x bentuk 2 / 3 candle M1, sesi x
            2 candle M5 (27 bentuk / candle); BELI & JUAL; tahan 5 & 10 mnt; spread asli. Lolos = bersih > 0 kedua periode & >= 8/10 th.
            BERSIH lolos: 0 di SEMUA kelompok (2017-21 spread $0.35-0.45 > gerak 5 mnt $0.3-0.8). KOTOR (arah saja) vs acak per hari:
            menit-dalam-jam 47 vs 21 (nyata tapi cuma $0.04-0.07), bentuk candle sedikit di atas acak (balik sesudah 2-3 candle besar,
            $0.2-0.4 < biaya). Menit JUAL terbaik berkumpul di jam server 12:21-12:27 & 16:51-16:59 = menjelang LELANG EMAS LBMA London.
            research\pola_fix.py (aturan dikunci): R1 JUAL London 14:55 -> 15:00, R2 JUAL 10:25 -> 10:30 (WITA 21:55 & 17:25 saat
            Inggris musim panas / 22:55 & 18:25 musim dingin). Kotor + 8/10 & 9/10 th, tapi bersih RUGI tiap tahun 2017-2024
            (R1+R2: -$52..-$209 / th per 0.01 lot); 2025 +$237, 2026 +$549. pola_fix_cek.py 2025-26: R1 rata2 +$0.93 median +$0.79
            untung 59% t 4.05 | R2 +$0.80 median +$0.66 untung 64% t 5.98; per kuartal + 6/7; menit acak London 2025-26 -$0.16.
            Gabungan: +$1.73 / hari per 0.01 lot, hari terburuk -$29, turun terdalam $33, hari >= +$7 hanya 12.7%.
            => satu-satunya pola waktu yang punya sebab nyata (lelang LBMA) & kuat di 2025-26; dipilih dari data yang sama -> butuh
            uji maju. Tidak dipasang.
  [selesai] SISTEM INDIKATOR PENGGUNA: RSI(1000) + MACD(10,22,4) + MA(1) di data MACD, M5 - LENGKUNGAN KURVA + KOTAK (11 Okt 2026).
            research\macd_kotak.py -> .txt, macd_kotak_cek.py -> .txt. Di layar: RSI(1000) ~datar di 50 (hanya menggambar level 10/15/
            50/85/90); MACD digambar skala sendiri (nilai -0.7 tapi memenuhi jendela) -> level = posisi kurva relatif layar; MA(1) = garis
            utama MACD (kurva merah), garis putih = sinyal SMA4. Diuji pada candle M5 tutup 2017-26: BELOK (lembah/puncak), BELOK DALAM
            (< / > 0), BELOK ZONA (15% rentang 60 candle), SILANG utama x sinyal, SILANG ZONA.
            A arah: 15 mnt sesudah lengkung, searah hanya 47-49% (gerak +-$0.01-0.05 vs biaya $0.33).
            B dagang ($3/$3, $3/$2, kurva ke kurva, + SL $3): semua -$0.29..-0.40 / posisi, 0/10 th; arah BERLAWANAN sama rugi.
            D terlambat: saat lengkung terkonfirmasi harga sudah jalan dari titik balik 30 mnt median $1.07 (17-21) / $1.61 (22-24)
              / $5.09 (25-26); 30 mnt berikutnya ~$0.
            C1 KOTAK (harga di 30% bawah/atas kotak): kurva BELOK searah -$0.244 vs BERLAWANAN -$0.378; SILANG searah -$0.238 vs -$0.391;
              2025-26: belok -$0.05 (menang 52%) vs -$0.35, silang -$0.075 (53%) vs -$0.32; kurva masih MELAWAN di dinding -> beli
              -$0.23 lebih buruk dari jual -$0.15 (cenderung tembus). Kecocokan ada (~$0.15 / posisi kotor) tapi < biaya, 0-1/10 th.
            C2 TEMBUSAN: kurva layar searah -> kembali ke kotak 86.8% vs melawan 88.7% (9/10 th sama arah, kecil); ikut tembus -$0.36.
            => bukan sinyal masuk; paling jauh penyaring di dinding kotak. Tidak dipasang.
  [selesai] RACIKAN KONFIRMASI DINDING: MENTOK atau TEMBUS? (11 Okt 2026, pengguna: "racik dan cari celah ... harga mentok atas / bawah
            dan akan menembus keluar kotak, atau candle terkonfirmasi HH / LL di dalam kotak"). research\racik_kotak.py -> .txt.
            439.832 candle M1 di 25% dekat dinding (2017-26). 30 mnt ke depan: TEMBUS (close di luar dulu) 61.4% | MENTOK (ke tengah
            dulu) 33.4% | HH/LL terkonfirmasi 4.3%. 50 bahan (kotak, bentuk candle, momentum, kurva MACD layar, hari & garis GoldPro,
            waktu & berita & lelang, volume & spread), gradient boosting, latih 17-21 -> nilai 22-26 dan sebaliknya.
            KETEPATAN: racikan TIDAK lebih baik dari model dasar (posisi, jarak, lebar, jam): logloss 0.761 vs 0.756 / 0.775 vs 0.763,
            AUC tembus 0.636 vs 0.639, mentok 0.644 vs 0.644; HH/LL AUC 0.49-0.50 (= koin). Sumbangan bahan (logloss naik bila diacak):
            kotak +0.148, waktu & berita +0.020 (menit ke lelang LBMA, jam), garis GoldPro +0.002, volume +0.001, MACD +0.0004,
            momentum +0.0001, bentuk candle 0.
            5% teratas P(TEMBUS): nyata 82-83% tapi = candle menempel dinding (posisi 0.98) & tembusan biasanya kembali; IKUT TEMBUS
            $3/$3 racikan -$0.40, dasar -$0.31, acak -$0.29. 5% teratas P(MENTOK): nyata 51-52%; BALIK -$0.28 (dasar -$0.30, acak -$0.26).
            1% teratas BALIK racikan +$0.12 (n 350, 3 / bln, 17-21 -$0.22) = kemungkinan kebetulan.
            => isi dashboard sekarang (posisi + jam) sudah memuat hampir semua informasi; tambahan bahan tidak menajamkan. Tidak dipasang.
  [selesai] UJI MANDIRI 232 ATURAN INDIKATOR x PARAMETER sebagai KONFIRMASI KOTAK, 1 TAHUN (9 Okt 2025 - 9 Okt 2026) (11 Okt 2026,
            pengguna: "test RSI, Stochastic dan lainnya ... semua kondisi, semua jam ... angka indikator variasikan ... ambil test dulu 1
            tahun"). research\indikator_kotak.py -> .txt + indikator_kotak_sel.csv (semua 25.984 sel). RSI 6 periode, Stochastic 4,
            CCI 3, MACD 4, Bollinger 3, ATR, ADX 2, EMA 4, ROC 3, Volume, Ichimoku, SAR, MFI, OBV, Donchian 2, divergensi 4; M1 & M5.
            Kejadian: COLEK 10.803, TEMBUS 7.013; aksi BALIK / IKUT; keluar $3/$3 & 0.1 ADR; 14 irisan (sesi, arah hari, volatilitas,
            kemarin). Paruh A (6 bln) menemukan, paruh B (6 bln) memeriksa.
            LOLOS 1.487 sel vs KEBETULAN rata2 1.656 (95% s/d 1.942) -> secara keseluruhan = kebetulan. Hanya COLEK-BALIK-$3 di atas
            kebetulan tipis (201 vs 112, 95% 194). Tema yang searah antar keluarga (irisan semua, $3): TEMBUS-IKUT saat osilator M5
            ekstrem (RSI5 M5 >=85 +$0.38/+$0.26 n 56/52; Stoch21 M5 K>=90 +$0.20/+$0.25 n 121/136; BB20,2.5 M5 %B>=1 +$0.23/+$0.10);
            COLEK-BALIK saat Stoch5 M1 K>=90 (+$0.25/+$0.05 n 380/450) atau harga di high 60 candle M5 (+$0.17/+$0.12 n 265/359).
            Indikator tren (MACD, EMA, ADX, SAR, Ichimoku, OBV), volume, ATR, divergensi: selisih vs dasar ~0.
            => belum ada peta "indikator per kondisi" yang lebih dari kebetulan; kandidat tema perlu dicek di 2017-2025. Tidak dipasang.
  [selesai] PETA ARAH KOTAK: SESUDAH MENTOK / TEMBUS / MASUK, HARGA SAMPAI MANA? + UJI 5 KANDIDAT (11 Okt 2026, pengguna: "signal
            konfirmasi jika sl dan tp tidak menguntungkan ... cenderung naik setelah mentok di bawah sampai dimana ... signal tembus &
            masuk ... petakan di semua kondisi, semua jam"). research\peta_kotak.py -> .txt / .pkl; Excel MQL5\Files\GoldPro\
            Peta_Arah_Kotak.xlsx (Ringkasan, Peta per jam WITA, Peta MENTOK / TEMBUS / MASUK, Uji 5 kandidat; cek Excel 0 galat).
            2017-2026: MENTOK 111.751, TEMBUS 72.966, MASUK 61.870. Target vs GAGAL, dibanding peluang ACAK dari jarak:
            MENTOK tengah 58.9% (acak 59.4%), seberang 38.4% (39.7%), lewat 0.5W 28.4% (29.8%) | TEMBUS +0.5W 58.9% (60.1%), +1W 39.1%
            (40.4%), +2W 22.1% (24.3%) sebelum balik ke tengah, lebih < 0 di 10/10 th | MASUK tengah 58.1% (58.6%). 60 mnt searah = lawan.
            Jam: TEMBUS gagal 03-07 WITA (-5..-8 poin, 1-2/10 th) & sesi NY sore; MENTOK/MASUK 06-07 WITA +2..3 (7/10), MENTOK 12 WITA
            +2.3 (8/10). Kondisi & 13 keadaan indikator (MACD 10,22,4, RSI, Stoch, BB, Donchian, volume): dalam +-3 poin.
            UJI 5 KANDIDAT 2017 - 9 Okt 2025: semua rugi ($-0.34..-0.48 / posisi, 0-1/9 th untung), tidak konsisten > dasar -> GAGAL.
            => sesudah mentok / tembus / masuk harga bergerak ~ tanpa arah; peluang ke tengah ~59% datang dari JARAK. Tidak dipasang.
  [selesai] OLAH ANGKA POSITIF PETA (11 Okt 2026, pengguna: "jangan bilang gagal dulu. ambil angka-angka positif di dalam, lalu kita
            olah lagi"). research\olah_positif.py, olah_tembus_balik.py, olah_tembus_balik_cek.py (-> .txt).
            Sel positif dipilih di 2017-21 diperiksa di 2022-26 & sebaliknya. BERTAHAN DUA ARAH: TEMBUS -> BALIK ke tengah (24/29 &
            18/20 sel tetap +): jam 04-05 WITA +7.6 poin 10/10 th, 03-07 +5.4 10/10, 23 +2.4 7/10, Jumat +2.5, volume >= 2x +2.3,
            volatilitas rendah +1.6, kotak sedang +1.6, kemarin sepi +1.2 (10/10); 03-07 & (Jumat|volume|kemarin sepi) +6.1 10/10.
            MASUK jam 06-07/15/20 WITA +1.7 9/10; MENTOK 06-07 WITA +2..3. TEMBUS -> lanjut: tidak ada yang bertahan.
            UANG (TEMBUS -> BALIK, TP tengah kotak): kotor + tapi spread 2017-21 $0.37-0.53 di jam 03-07 > kotor. SL 1W di luar dinding:
            2025-26 jam 03-07 & 23 pasar +$0.49 / posisi (~114 / bln, menang 63%), LIMIT di dinding +$0.46 (~106 / bln, 68%);
            jam 23 saja LIMIT +$1.33 (26 / bln, 70%); semua jam LIMIT +$0.16. Per tahun (pasar 03-07 & 23): 2022 -0.01, 2023 +0.02,
            2024 -0.06, 2025 +0.00, 2026 +1.11 -> sebagian besar dari 2026. SL 0.5W: tetap minus.
            => arah tembus-balik 03-07 WITA nyata (10/10 th); uangnya baru muncul saat spread kecil & gerak besar (2026). Kandidat uji maju.
  [selesai] DETAIL JAM POSITIF TEMBUS -> BALIK (11 Okt 2026, pengguna: "konsentrasi ke jam positif, lebih detail").
            research\jam_positif.py -> .txt / .pkl. 12.344 tembusan 03-07 & 23 WITA (2017-26).
            SAMPAI MANA: kembali ke tengah <= 30/60/120/240 mnt 31/46/60/72% (median 38 mnt; jam pembanding 24 mnt). Yang kembali,
            terjauh di luar dinding: median 0.40W, 75% 0.75W, 90% 1.3W, 95% 1.7-2.0W (2025-26: $2.94 / $6.27 / $12 / $17; kotak median $7.76).
            KISI 120 (3 masuk x 4 TP x 5 SL x 2 batas): terbaik masuk PASAR candle berikut, TP tengah (0.5W), SL 1W luar dinding, 240 mnt:
            22-26 +$0.30 / posisi, 2025-26 +$0.90, menang 62-64%. TP tengah > 0.25/0.75/1W; SL 1W > 0.5/0.75/1.5/2W; pasar > LIMIT > tunggu.
            JAM (aturan itu, 22-26): 23 WITA +$0.54, 04 +$0.47, 03 +$0.31, 05 +$0.26, 00 +$0.24, 20 +$0.20; 01-02 WITA -$0.36/-$0.52;
            10 mnt sebelum rollover -$1.37. Server 18:00-18:30 +$0.94 (5/10 th), 23:30 +$0.82.
            PER TAHUN: 2017-21 -$0.29..-0.41, 2022 +0.04, 2023 -0.02, 2024 -0.21, 2025 -0.03, 2026 +2.07; bulan 2025-26 untung 10/22.
            Kotak >= $8 +$1.76 (2022-26). Tembusan kecil < 0.25W menang 62-66%, >= 0.25W 42-47%. Filter spread <= $0.25 / $0.15: tidak
            konsisten per tahun. RISIKO lot 0.01 2025-26: 555 posisi +$309, rugi terbesar -$75.76, kalah beruntun 5, turun terdalam $150.
            => arah konsisten; uang = keadaan 2026 (kotak lebar). Kandidat uji maju: server 18:00-19:00 & 22:00-23:50. Tidak dipasang.
  [selesai] INDIKATOR PENYARING UNTUK TEMBUS -> BALIK DI JAM POSITIF (11 Okt 2026, pengguna: "indikator apa yg tepat ini?").
            research\indikator_jam_positif.py -> .txt / .csv. 51 keadaan indikator (RSI 5/7/14, Stoch, BB, CCI, MACD 10,22,4 & 12,26,9,
            ADX, ATR, volume, EMA, ROC, Donchian; M1 & M5) di 12.280 tembusan 03-07 & 23 WITA; aturan TP tengah / SL 1W / 240 mnt.
            Catatan: dengan SL 1W peluang balik dasar = acak (60.3% vs 61.1%); keunggulan +5.4 poin sebelumnya = terhadap 0.5W.
            Lolos pilih -> periksa DUA arah: Volume M1 >= 2x (+2.4 / +5.8 poin), ATR5/50 M1 >= 1.5 (+2.4 / +5.2). Lainnya positif kedua
            periode: RSI7 M5 < 50 (+0.8 / +6.0), RSI5 M5 < 50 (+1.2 / +4.4), CCI20 M1 >= 200 searah (+0.9 / +3.4), MACD 10,22,4 M5 kurva
            masih melawan (+0.5 / +2.7). Merugikan: Volume <= 0.7x (-4.8 / -2.7), CCI M5 >= 200, RSI5 M5 >= 70 searah, Stoch21 M5 >= 90.
            Jumlah keadaan lebih baik di kedua periode 14/51 ~ kebetulan 13 -> hanya tema yang masuk akal dipegang.
            GABUNGAN (LONJAKAN = vol >= 2x | ATR >= 1.5; M5 BELUM IKUT = RSI7 M5 < 50 | MACD masih melawan): keduanya n 726, lebih +3.3
            poin, th+ 8/10; tanpa keduanya th+ 1/10. $ per tahun tetap minus kecuali 2024 +0.16 & 2026 +3.13. Tidak dipasang.
  [DIPASANG] KOREKSI JAM "TEMBUS SUNGGUHAN" + RENCANA PENGERASAN 6 POIN (10 Okt 2026 15:54 WITA, pengguna: "jika belum ada
            peningkatan, kita tambahkan aja dulu waktu yg konsisten itu 1 dan 2"). Compile GoldPro_Main + GoldPro_Panel +
            GoldPro_Telegram 0 error / 0 peringatan (cek salinan sementara dulu). Versi semua program 2026101002.
            1. KOREKSI JAM (Signal\GP_BoxWatch.mqh KB_H60P(mo, d, t)): p = sigmoid(1.0358 * logit(KB_H60) + 0.0435 + HR[jam server]),
               research\consol_h60hr.py (latih semua 2017-26; cek ulang dua arah -1.21% / -1.64%, 5/5 th). Baris "Tembus sungguhan",
               "Kembali s/d 60 mnt" (= 100 - itu), pesan SOON & catatan CSV (alasan "... v2") memakai angka baru. evaluate_kotak.py
               memisah versi 1 / 2. Dalam poin (consol_h60hr2.py, koreksi selalu dari periode lain): angka per jam WITA meleset
               dari kenyataan rata2 4.2 poin -> 0.6 poin; jam yang meleset >= 4 poin 12 -> 0 (mis. 08 WITA tampil 52.6% vs nyata
               43.7% -> baru 45.4%; 00 WITA 48.4% vs 56.2% -> 56.4%; 20 WITA 56.0% vs 47.8% -> 48.8%).
            2. PENGERASAN:
               (1) CHART UTAMA - Core\GP_Master.mqh: satu chart per simbol (klaim atomik token, detak 2 dtk, ambil alih bila detak
                   > 20 dtk / dilepas). Hanya chart utama: Telegram (KB_Out), CSV uji maju (KB_PredLog / KB_TgLog), rapor, alarm,
                   alert popup GP_Notify (kecuali PIN). Chart lain: mesin kotak jalan hanya bila dashboard Kotak dibuka
                   (KB_Reset saat ditutup -> putar ulang saat dibuka lagi).
               (2) SUSULAN - KB_Out: kejadian putar ulang <= 30 mnt terakhir yang belum terkirim (kunci GP_KBTG_KEY) dikirim dgn
                   tanda "SUSULAN (kejadian hh:mm, terlambat x mnt)"; kejadian live > 3 mnt terlambat juga diberi tanda.
               (3) CEK VERSI - Signal\GP_Health.mqh + EA: GV GP_VERI_<chart> / GP_VER_IND_MAX (indikator), GP_VERP_<chart> +
                   GP_VERPT_ (EA Panel), GP_VERT + GP_VERTT (EA Telegram). Baris merah kecil kiri bawah (indikator: GPV_I*, EA
                   Panel: GPV_E) hanya bila ada yang versi lama / EA Telegram berhenti > 5 mnt; status chart EA Telegram juga.
               (4) ALARM KALIBRASI - KB_CalCheck tiap menit: uji maju 7 hari kalender (slot hari dari CSV), 7 angka (pecah5,
                   kembali5, sungguhan60, target colek / mepet / kembali / lanjut); z dgn DEFF 5/5/4/1.5; ALARM bila n >= 300
                   (prediksi) / 40 (target), |z| >= 3 & selisih >= 5 poin; padam |z| < 2 atau < 3 poin. Pesan Telegram ALARM /
                   PULIH sekali tiap perubahan (GV GP_KBAL_x), baris rapor "Cek angka 7 hari".
               (5) MODE PRESISI - selama ALARM baris angka itu diganti "[DICEK] 7 hr angka x% -> nyata y%" (merah) & pesan
                   Telegram yang memuat angka itu diberi tanda "[angka sedang dicek]".
               (6) PENJAGA HIDUP - chart utama menulis GP_HB (jam PC) tiap 2 dtk; EA Telegram: tidak ada detak >= 15 mnt
                   (InpWatchMin) saat pasar buka (tick XAUUSD < 5 mnt) -> "GoldPro BERHENTI", detak kembali -> "jalan lagi".
                   Batas: MT5 tertutup / PC mati tidak bisa dilaporkan (EA ikut mati).
            Status uji maju saat dipasang (evaluate_kotak.py, 8-10 Okt): semua angka "wajar"; pecah 5 mnt 20.7% -> nyata 14.9%
            (n 725, z -1.9 dgn DEFF) = paling dekat ke alarm, dipantau.
  [KOREKSI] SINYAL KOTAK - ENTRY REALISTIS (29 Sep 2026 malam), research\box_scalp3.py, box_touchnum_real.py:
               - Uji di bawah (57-63%, net + 2025-26) KELIRU: entry dianggap di garis walau candle M1 sudah BUKA di
                 luar garis (55-59% sentuhan ULANG setelah kotak berubah, 2% sentuhan pertama). Entry di harga buka:
                 ikut tembus M5 ke-1 52.5%, ke-2 50.5%, ke-3+ 51.1%; M1 54.1/51.9/52.6%. Net 2026 ~0 (M5 +0.02..-0.06R,
                 M1 -0.01..-0.06R), tahun lain negatif. Varian: 1 sinyal per level 53%, konfirmasi close 49%.
                 -> UJUNG KOTAK TIDAK MEMBERI KEUNGGULAN ARAH MANA PUN. Panel & alert diberi label [TIDAK TERBUKTI],
                 BxOutcome & evaluator memakai entry realistis.
               - PELAJARAN: uji sentuhan level wajib memakai harga buka bila candle sudah melewati level (gap / level
                 yang berpindah) - jangan pernah mengasumsikan terisi di level.
  [selesai] SINYAL KOTAK SMC (dealing range) M5 & M1 (29 Sep 2026), research\box_scalp2.py, box_follow_years.py:
               - Replika persis SMC_Structure (fractal 5, konfirmasi +5 bar) + SMC_Zones (leg terbaru >= ATR14 SMA-TR,
                 fallback 10 swing). Hasil dinilai di M1 (urutan intra-candle), spread asli. M5 2016-26 55 rb sentuhan,
                 M1 2023-26 80 rb sentuhan.
               - FADE di ujung kotak (SELL di atas / BUY di bawah, ide pengguna): menang 38-44% (TP=SL 0.5-2 ATR),
                 SETIAP tahun 37-44% (M5) / 39-41% (M1) -> harga lebih sering MENEMBUS garis kotak. Net -0.25..-1.0R.
               - PENOLAKAN (close kembali di dalam kotak): 49-51% = acak, net negatif.
               - IKUT-TEMBUS (kebalikan fade): menang 57-63% (k=1) tiap tahun; net setelah spread negatif 2016-22,
                 ~0 2023-24, POSITIF 2025 (+0.10R) & 2026 (+0.14R) M5 k=1, M1 2026 +0.11R -> bergantung ATR/spread
                 (rezim volatil), belum termasuk slippage stop order -> HIPOTESIS.
  [selesai] PROFIL PER JAM WITA (28 Sep 2026), research\hour_profile.py:
               - % jam ditutup naik 2017-26: 46-54% di semua jam KECUALI jam buka (06 WITA 61%, 07 WITA 56%: jam buka
                 musim panas/dingin) = efek harga bid menit pertama (sama dengan temuan gap) -> tidak ada jam berarah.
               - Gerak 1 jam median 12 bln: terbesar 21-22 WITA $25-26, 09 WITA $24, 23 WITA $23, 20 WITA $21;
                 terkecil 04 WITA $10.5, 12 WITA $12, 05 WITA $13. Spread $0.17 kecuali jam buka $0.35 (menit 1 $0.65).
  [selesai] MENIT 1-10 SETELAH BUKA (28 Sep 2026), research\open_minutes.py, open_minutes_recent.py:
               - Searah pola sebelum tutup (5/15/60 mnt terakhir, candle kemarin, 5 hari) pada menit 1,2,3,5,10:
                 46-52% (acak), juga dari close menit ke-1, Senin vs Selasa-Jumat, dan pola kuat. Per tahun 40-58%,
                 tidak konsisten (5 hari 2024-26: 54-58% = rezim reli, sama dengan temuan sebelumnya).
               - Besar gerak 5 mnt pertama median: 2017-19 $0.3-0.4, 2025 $2.0, 2026 $3.6; spread saat buka 2026
                 median $0.65 (normal $0.17). -> TIDAK ada kelanjutan pasti di menit-menit awal.
               - DIPASANG: "Puncak/Dasar tahan xx%" (HoldP: tabel khusus jarak x sisa jam, bin 0.1 ADR, 8 kelompok jam,
                 monoton, jarak / g_volK).
  [selesai] TREN SAAT BUKA & PUNCAK HARI BERTAHAN (28 Sep 2026), research\open_cont.py, gap_check.py, high_hold.py
               (dijalankan lewat open_tests.py; data M1 diambil ulang dari MT5 s/d 28/09 16:36):
               - $10 searah tren duluan: kemarin 49.1%, 5 hari 50.4% (tapi 2024-26: 57/56/58%, 2017-23 45-52% ->
                 rezim baru-baru ini, bukan aturan), 3 jam terakhir 48.1% (kuat 56%, n=66 terlalu kecil).
               - Gap buka tampak berbalik 62% TAPI hanya gap TURUN & hanya dari harga pembukaan; mulai menit 5/15:
                 46-53% (acak) -> efek harga bid di menit pertama, BUKAN pola.
               - Lanjut duluan: median $17 (p75 $25) sebelum pullback $10, ~2-2.3 jam; berbalik duluan: median $16
                 (p75 $23), ~2-2.5 jam. $10 pertama 40-75 mnt, $25 pertama 3.5-5.5 jam, kedua arah setara.
               - Puncak/dasar hari bertahan s/d tutup (jarak x sisa jam): 80/90/95% butuh jarak: sisa 12-24j $71/-/-,
                 6-12j $48/$74/$100, 2-6j $19/$29/$40, <2j $7/$10/$14. Jarak $ lebih baik dari % Fibonacci
                 (logloss 0.431 vs 0.463). Pembalikan 50-62%: bertahan 30% (12-24j), 62% (6-12j), 94% (2-6j).
                 Per tahun stabil (59-71% utk $29-38 & 6-12j). Puncak dekat (<$19) lebih sering ditembus dari level
                 biasa (+3..5 poin), puncak jauh (>$29) lebih jarang (-4..6 poin).
  [selesai] UJI REFERENSI (28 Sep 2026), research\daily_scale.py & vol_calib2.py (latih 2017-21, uji 2022-26):
               - HAR (Corsi) / HAR Garman-Klass / EWMA / ADR5-10 pengganti ADR20: HAR meramal rentang sedikit lebih
                 baik (MAE log 0.316 vs 0.332) TAPI Brier peluang T1-T4 lebih buruk 3.1% (HAR_GK -3.9%), EWMA +0.08%.
                 -> ADR20 DIPERTAHANKAN.
               - Hari berita tier-1 (kalender 13 bln, awal): rentang 0.99x vs 0.94x ADR20 hari biasa; NFP 0.96, CPI 0.88,
                 GDP 0.93, PCE 0.95, FOMC 1.30 (n=9). -> tidak ada penyesuaian hari berita (lonjakan pasca rilis
                 sudah ditangkap rvr/rv2).
               - Vol 2 jam terakhir (rv2) + rvr: jarak/(rvr^0.15*rv2^0.10) dipilih di latih; uji logloss 0.42751 ->
                 0.42662 (tanpa penyesuaian 0.42988); 2 jam sangat ramai meleset +4.0 -> +3.4. DIPASANG
                 (input DMInpVolB1/DMInpVolB2, nama baru agar default berlaku).
  [selesai] PENYESUAIAN VOLATILITAS HARI INI (28 Sep 2026, hari live pertama), research\vol_calib.py:
               - Pemicu: hari tren 28/09 (turun 0.75 ADR dlm 4 jam). Analog 125 hari (trend_day.py) memberi peluang
                 lebih tinggi dari panel -> diuji penuh (918 rb baris, jarak acak, tabel 250 hari sebelumnya).
               - rvr = rentang hari ini s/d sekarang / rentang rata2 pada jam yang sama sejak buka. Tabel lama:
                 sepi(<0.7) -1.9 poin, normal 0.1, 1.4-1.8 +3.2, >1.8 +8.7 poin (meremehkan). Simetris searah/balik.
               - Jarak efektif = jarak / rvr^beta. beta 0.25 dipilih 2017-21 (logloss); UJI 2022-26: meleset rata2
                 per tingkat vol 2.62 -> 1.00 poin, >1.8: 8.7 -> 2.6, semua tahun 2017-26 membaik, desil terkalibrasi.
               - Dipasang di LiveP/LiveInv (semua peluang live, cadangan, probe, PIN, tangga, jurnal) + baris panel
                 "Gerak hari ini x.x normal". ComputeRecent memakai rvr tiap hari lampau. Input DMInpVolBeta (0 = mati).
               - Jurnal: snapshot sebelum 28/09 ~11:00 WITA memakai tabel lama.
  [selesai] JARAK DARI EQ -> T1 (27 Sep 2026), research\leave_eq.py & prev_eq.py (2017-26, 2.510 hari):
               - Harga sudah menjauh $0/5/10/15/20 (x ADR101) dari open ke satu arah: T1 arah itu tersentuh
                 s/d tutup 67/71/77/83/89%, tembus close M5 63/66/72/78/84%, median waktu 8j/5j/3j/85m/30m.
                 Per tahun stabil (mis. $15: 81-85%). Tidak ada ambang ajaib: naik bertahap ~5-6 poin per $5.
               - T1 duluan vs balik ke open: 20/38/57/75% ~ geometri acak (20/40/60/80) -> meninggalkan EQ
                 TIDAK memberi momentum; sering balik ke EQ dulu. Sampai x setelah >10 jam buka: -12..14 poin.
               - Atas > bawah (72 vs 63% di awal) = tren naik emas 2017-26, bisa tidak bertahan.
               - EQ kemarin TIDAK istimewa: tersentuh 49.2% vs level cermin jarak sama 48.2%.
               - Indikator sudah menampilkan ini live: LIVE "duluan|s/d tutup" & tangga halaman 2.
  [selesai] INTERAKTIF + GARIS CADANGAN (27 Sep 2026), research\backup_lines.py & live_lines_test.py:
               - Garis cadangan live = kebalikan tabel LiveP (jarak terjauh dgn peluang >= 80%).
                 Uji 2017-26 (230 rb snapshot, tabel 250 hari sebelumnya): atas 80.2% / bawah 79.4%,
                 per tahun 76.7-82.4%; sisa jam < 1 hanya ~70% -> disembunyikan. 70%: 70.3/69.5; 90%: 90.0/89.7.
               - Probe mouse (LiveP jarak bebas 0-1.2 ADR): kalibrasi tiap desil tampil vs nyata <= 0.7 poin,
                 per tahun rata2 0.3-1.5 poin, maks satu desil/tahun 3.0 poin.
               - T1 salah satu: prediksi 97.6-99.6% vs nyata 97.7-99.6% per tahun; keduanya 32-40%.
               - Kalau T2 searah gagal (55% hari): T1 lawan tetap 81.5% (78-89%/th), EQ 99.6%.
                 Kalau T1 searah juga gagal: T1 lawan 96%, T2 lawan 74% (diketahui akhir hari -> info).
               - Tombol (Target/Panah/Cad80/SMC/Probe/+PIN/Hapus PIN/Panel, status per chart di GV GPB_<chart>_*),
                 PIN (OBJ_HLINE GPB_PIN_*, alert InpGPAlertPin, bertahan ganti TF), tooltip di semua garis.
               - Jurnal snapshot + kolom bk_p,bk_up,bk_dn; evaluate_journal.py menilai "garis cadangan".
               - Panel 2 halaman (tab): 1 PETA / 2 ENTRY & TARGET (entry hipotesis, tangga target kena/belum+%,
                 skor 3 hari, cek 20 hari = ComputeRecent). Pratinjau data broker s/d 25 Sep 2026: cad80 20 hari
                 kena 80% (uji kode 10 th: 78.3%), 20hr T1 65/75 T2 35/50 (250hr ~75/59 44/34).
                 GOTCHA python: numpy bool + bool = OR, bukan 2 -> selalu int() sebelum menjumlah.
  [selesai] AUDIT GARIS (27 Sep 2026, tanpa trading/biaya), research\audit_lines.py:
               - Nilai garis = hitungan harga: open/close kmrn/ADR20/EQ/T1-T2/straddle hari terakhir sama
                 persis dengan data D1 broker.
               - Persentase (replikasi persis logika indikator, 250 hari sebelumnya) vs nyata 2017-2026:
                 target T1-T4 meleset rata2 1.5-4.2 poin/tahun; retest #1/#2/#3+ 62.3/63.6/67.7% vs
                 61.8/63.6/66.9%; pullback 42.7 vs 43.3%; lewat open 28.2 vs 27.6%; "duluan" terkalibrasi
                 (meleset 0.2-1.8 poin/tahun, 214 rb pengamatan). Proyeksi besok: open besok vs close
                 hari ini median $2.25 (ADR 100).
               => Garis = hitungan pasar, angka = peluang statistik yang AKURAT (bukan tebakan arah).
  [selesai] Saklar "Mode tampilan": Bersih (default) / Lengkap SMC (semua visual SMC lama sbg [INFO]).
  [selesai] Evaluator jurnal: ambil data UTC-aware (bug zona waktu), bagian 4c AM Fix, hasil per rezim.
  [selesai] research\: script riset utama + make_data.py (buat ulang data dari MT5).
  [selesai] Jendela RAWAN SWEEP [KOKOH] di panel (hal. 1 bagian SESI + hal. 2) dan alert 10 menit
               sebelumnya (InpGPAlertSweep, default nyala). Jendela = 08:00-11:30 New York
               = 20:00-23:30 WITA saat DST AS (21:00-00:30 WITA setelah 1 Nov), otomatis ikut DST.
               Uji M1 2017-2026 (sweep = tembus high/low 60 mnt lalu balik >= 0.1 ADR dalam 10 mnt):
               rata2 7.4 sweep/hari; 7 slot 30-menit teratas SEMUA di jendela ini (2.3-4.1x rata2 slot;
               puncak 09:30 NY = 21:30 WITA). Paling sepi 11:00-13:00 dan 04:00-06:00 WITA.
               Pola per tahun berkorelasi 0.91-0.99 -> ini POLA WAKTU, bukan sinyal arah.
  [selesai] Penyebab & menit sweep (research sweep_cause.py, M1 2017-2026, blok 5 mnt = % hari ada sweep):
               08:30 NY 18% | 08:20 16% | 10:00 14% | 09:30 12% | 09:50 12% (rata2 blok 2.7%), 9-10/10 tahun.
               Penyebab terbukti: pelaku AS hadir (libur AS/NYSE tutup: 0-2%), data PENTING 08:30 (26% vs 8%
               tanpa rilis; NFP 43% vs 16%; 10 mnt sebelumnya 19% vs 7%), NYSE buka 09:30 (24% vs 13% per 10 mnt),
               FOMC 14:00 NY (56% vs 3%). BUKAN penyebab: data 10:00 (11% vs 10%), PM Fix London & London buka
               (uji minggu selisih DST). 10:00 NY = jam New York, sebab pastinya belum terbukti.
               Bentuk: tusukan median $0.57 lewat high/low lama, balik dalam 6 mnt; 53% tembus lagi dalam 60 mnt
               (BUKAN sinyal reversal); 50-80% hari sweep DUA arah di jendela. Panel: baris "menit panas" +
               NFP/data 08:30/FOMC dari kalender MT5.
  [selesai] Menit tepat & entry (research sweep_entry.py, 10 th): menit 08:30 (12x rata2), 08:20 (10.6x), 08:31
               & 10:00 (8.2x) = 10/10 tahun; 09:50 5.8x, 09:30/09:35 5.2x (9/10). Tick 3 bln: data besar gerak $3
               dalam 0.7-1.7 DETIK; lalu 5-60 dtk lanjut ATAU balik keras (CPI 11 Sep +$9.75 -> -$35). Spread broker
               mentok ~$0.59 saat rilis (bukan permainan spread). Setelah candle menit rilis close, lanjutan 47-51%
               (acak). UJI ENTRY semua RUGI 2017-2026: momentum ikut dorongan -0.09..-0.32R (0-2/10 th +),
               fade/balik-arah sweep -0.22R (0/10), straddle stop 08:30/09:30/10:00 -0.34..-0.39R (0/10).
               -> TIDAK ada sinyal entry sweep. Tusukan sweep di jendela: median 0.024 ADR, 90% <= 0.085, 95% <= 0.115.
  [selesai] Panel: "peluang sweep 5 mnt ini" (model logit jam+range 60 mnt, latih 2017-21, cek 2022-26: prediksi
               11% vs nyata 10-12%/th; batas 14%; data 08:30 26%, NFP 43%, FOMC 56%) + tanda x ungu sweep hari ini
               (DMInpShowSweeps, INFO). Script Scripts\GoldPro\GP_CalendarExport.mq5 -> GoldPro_CalendarFull.csv
               (actual/forecast 2017-) untuk uji kejutan data (belum dijalankan).
  [selesai] Pendalaman (research level_sweep*.py, tick_collect.py, tick_analyze.py):
               - Level besar (Asia/London/semalam/kemarin) ditembus di jendela NY: 76-83% close balik <= 15 mnt,
                 TAPI balik-arah rugi -0.09..-0.47R (0/10 th) walau SL dilonggarkan s/d 0.15 ADR; ikut tembus rugi.
                 Tanpa biaya: balik-arah +0.03..+0.05R -> pola ada tapi terlalu kecil untuk biaya.
               - Tick 2020-2026 (3531 event): dorongan >= 0.03 ADR dlm 2 dtk di 17% hari (08:30), 12% (10:00),
                 36% FOMC. 08:30 capai $3 dlm 1.8 dtk; spread median $0.57 sebelum, maks ~$1. Setelah dtk-2 lanjut
                 51-54% (acak). Arah 60 dtk sebelum rilis tidak memberi petunjuk (47%). Dorongan terbesar
                 (>20% ADR) = NFP & CPI. Uji masuk 2-60 dtk (ikut/lawan) RUGI; dorongan besar positif 2020-22
                 tapi rugi 2023-26 (gagal). FOMC ikut 10 dtk tahan 10 mnt +9% ADR 6/6 th tapi n=19 -> hipotesis.
  [selesai] Gerak cepat 5 mnt (research fast_move.py, fast_freq.py): >= 0.06 ADR ~20x/hari, >= 0.10 ~8x,
               >= 0.15 ~3x, >= 0.25 ~0.7x/hari. Lanjut searah 44-49% di semua sesi; konfirmasi perak tidak
               membantu; ikut arah rugi 0-1/10 th. Contoh 30 Sep 11:30 WITA: -$6.8 (0.07 ADR) bertahap 6 mnt,
               spread normal, perak -0.20%, USD sedikit kuat; hari dagang terakhir China sebelum Golden Week +
               akhir kuartal. Panel: baris "gerak 5 mnt +/-$x = y ADR (~n x/hari)" [INFO].
  [selesai] SIDEWAY / KONDISI PASAR (research consol.py, regime_state.py, M1 2017-2026):
               - KAPAN (rentang 60 mnt <= 0.112 ADR): 12:00 WITA 60% waktu, 06-07 WITA 55%, 04:00 52%, 11:00 49%,
                 13:00 41%; paling jarang 21-22 WITA 1-2%. Senin 28% .. Jumat 22%. (WITA musim panas AS.)
               - SEBAB: jam sepi/likuiditas; menunggu data penting (rentang 60 mnt sebelum 0.80x); libur AS (0.39x).
                 Sebelum FOMC/NFP TIDAK lebih sepi. Setelah gerak 60 mnt >= 0.30 ADR, 2 jam berikut 1.42x (ramai).
               - SETELAH sideway (20% tersempit utk jam itu, W 30/60/120/240): tembus ATAS 50-51% (acak); median
                 10/16/25/43 mnt sampai tembus; tembusan lanjut 1 lebar 37/30/22/13% vs balik ke tengah 56/52/41/31%;
                 jam berikut 0.87-0.90x normal (BUKAN meledak). Penebak arah: tren sebelum 49-51%, SMA20 50-52%,
                 candle kemarin 50%, posisi vs open hari 52-57% (kecil); sisi kotak terdekat 65-70% (geometri).
                 Entry tembus kotak (OCO, SL tengah) rugi 0/10 th di semua W, juga searah tren sebelumnya.
               - KONDISI 60 mnt -> 60 mnt berikut: arah lanjut 47-49% semua kondisi; rentang sideway 0.81x,
                 tren 1.29x, gejolak 1.34x (sama 2017-21 & 2022-26) -> meramal KERAMAIAN, bukan arah.
               - Panel hal.1 "KONDISI: SIDEWAY/TREN/BERGEJOLAK/normal" + kotak sideway di chart (DMInpShowState).
  [selesai] AUDIT & PERBAIKAN MESIN SMC (30 Sep 2026; research\smc_audit.py, smc_audit2.py = replika Python
               persis logika lama, data M5 2 bulan). Temuan -> perbaikan (hanya GoldPro, SMC_Pro_System asli utuh):
               1. BOS/CHoCH: semua swing lama (s/d 50) yang belum ditembus bisa memicu event -> 55% event dari swing
                  yang BUKAN terbaru, 25% candle breakout menghasilkan >1 event (maks 8), 64 candle CHoCH+BOS
                  sekaligus; 1207 event vs 549 bila benar. -> hanya swing TERBARU tiap sisi, maks 1 event/candle.
               2. Outside bar (high & low sekaligus swing): low-nya hilang. -> keduanya dicatat.
               3. SMC_Structure_Update selalu "ada perubahan" tiap candle -> OB dicari ulang tiap candle,
                  Mitigation Block tidak pernah jalan. -> hanya true saat ada event; Mitigation Block (definisi
                  longgar) input baru InpDetectMitigationBlk default mati.
               4. Definisi OB: candle berlawanan terbaru <= 20 bar sebelum BOS -> 79% OB TIDAK di asal leg (median
                  4 candle dari asal, 26% naik di tengah leg). -> OB = candle berlawanan terakhir di ASAL leg
                  (ekstrem antara swing yang ditembus & candle BOS), zona mencakup ekstrem itu.
               5. Status OB/FVG setelah pasang ulang/ganti TF/compile hanya dicek dgn 1 candle terakhir -> 68% OB
                  "belum termitigasi" sebenarnya sudah; "Pijakan" = zona yang sudah ditembus habis 67% waktu, 6% di
                  sisi salah harga. -> backfill replay candle demi candle; mitigasi dihitung dari candle SESUDAH
                  BOS (bornTime); breaker yang gagal -> INVALIDATED; Pijakan hanya di sisi benar harga.
               6. Label: "Tujuan (321 pips)" = $3.21 (1 pip dianggap $0.01) -> ditulis $; 95% target hanya 1 swing
                  -> ditandai "swing"; Pijakan selalu disebut "OB" walau Breaker -> jenis sebenarnya; BOS turun
                  berwarna CHoCH -> warna = arah; "Retest?" SMC -> "retest SMC? [blm teruji]".
               BENAR sejak awal: rumus Premium/Discount/EQ/OTE (62-79%), FVG 3 candle, fractal tanpa look-ahead,
               PDH/PDL, target Tujuan tidak basi (0%). CATATAN: skor "POI Quality" (Tahap 2) diuji dgn definisi OB
               lama -> perlu diuji ulang; bias/BOS SMC tetap TIDAK terbukti menebak arah.
  [selesai] "SMC / tombol kadang hilang" (log MT5 30 Sep, 20+ kali ganti TF M1/M5/M15): MT5 memuat instance
               BARU dulu lalu menutup instance LAMA 2-3 dtk kemudian; OnDeinit lama menghapus semua objek GoldPro
               (tombol, panel, SMC, kotak) milik instance baru -> hilang s/d candle berikut (5-15 mnt). Juga jurnal:
               instance baru melihat jurnal "dipegang chart lain", instance lama lalu melepas -> TIDAK ADA penulis
               jurnal s/d ganti TF lagi. Perbaikan: OnDeinit hanya menghapus objek bila indikator dilepas/chart
               ditutup/template; OnInit membersihkan sisa instance lama; timer 2 dtk memperbaiki objek yang hilang
               + gambar ulang penuh 6 dtk setelah mulai; jurnal diklaim atomik (SetOnCondition) & dicoba ulang tiap
               tick, pemilik menyimpan waktu catatan terakhir (GV GDM_JEV/SNAP/SD/AS_<simbol>) -> tanpa bolong/dobel;
               jurnal breaker hanya dari chart M5 (dulu bisa dari M1/M15 = anomali breaker jauh dari harga).
  [selesai] DASHBOARD BERITA (Signal\GP_NewsBoard.mqh, kanan atas; klik judul = ringkas/lengkap):
               1 Okt 2026: default TERTUTUP atas permintaan user (chart penuh, berita tidak bisa di-scalp);
               tampil/sembunyi lewat tombol "Berita" (GDM::g_vNews). InpNBShow tidak dipakai lagi.
               rilis USD kalender MT5 (sedang+penting) + jam panas NY tanpa berita (09:30 NYSE, 10:00), jam WITA.
               Baris besar = rilis berikutnya; kuning 15 mnt, oranye 10 mnt, merah 1 mnt sebelum; setelah rilis
               panduan MENIT & CANDLE (M1 #, M5 #), perkiraan dorongan per jenis berita ($ dari ADR), gerak sejak
               rilis. Alert 15 mnt sebelum rilis PENTING (InpNBAlert15). Angka: research\news_phase.py (323 rilis
               penting, 13 bln): menit 0 = 2.4x gerak normal, menit 1 2.0x, 2-4 1.6-1.8x, 5-20 ~1.55x; dorongan
               2 mnt median 3.2% ADR; arah sesudahnya 50-54%; balik lewat harga pra-rilis 20/28/36% (5/10/20 mnt).
               Per berita (median $ 2 mnt): NFP/AHE ~$22, CPI ~$13, FOMC ~$10, PMI/klaim ~$4, PCE ~$3, EIA ~$2.
  [selesai] "MENTOK DI MANA / TUJUAN KE MANA" (research\level_react.py, level_magnet.py, M1 2017-2026,
               181 rb level, pembanding = level yang sama digeser +/-0.13 ADR / angka bulat +$5/+$25):
               - PANTUL di sentuhan pertama (X = 0.05 ADR): TIDAK ada tipe level yang lebih sering mentok dari
                 level palsu. Level likuiditas justru lebih sering DITEMBUS: PDH -8.3 poin (1/10 th), Asia high
                 -5.7, swing high/low M5 -3.6/-3.9 (0-1/10), EQH/EQL M5 -3.8/-3.0 (0/10), EQ/open -3.6, London
                 -2.7/-2.8. T1/T3 +2.3/+2.4 tidak konsisten. X = 0.10 ADR: pola sama (PDH -8.9).
               - MAGNET (didatangi s/d kedaluwarsa, jarak sama): EQH/swing/PDH/Asia/London/angka bulat -1.6..+1 =
                 BUKAN magnet. Hanya OPEN hari ini (+4.8) & CLOSE kemarin (+4.3), kedua periode.
               - Arah "duluan" GoldDayMap = geometri jarak (kode: pUpFirst = jarak relatif), akurat tapi bukan
                 ramalan arah. => Level SMC/likuiditas = tempat stop DITUSUK/DITEMBUS, bukan tembok/tujuan.
  [selesai] JALUR HARGA DI DALAM KOTAK SMC (research\box_path.py; kotak = aturan SMC_Zones persis, M5, jalur di
               M1 <= 6 jam; 42.718 sentuhan ujung PERTAMA 2017-26, ~18/hari, tinggi kotak median 14.6% ADR).
               Dibanding geometri jarak acak:
               - ujung kena -> EQ dulu vs tembus 1/4 kotak: 32.8% (acak 33.3%); vs tembus 1/2: 49.8% (acak 50%)
               - ujung kena -> ujung seberang dulu vs tembus 1/4: 18.5% (acak 20%, 0/10 th di atas acak)
               - ujung -> EQ, lalu: lanjut ke seberang 48.1% vs balik ke ujung (acak 50%)
               - ujung -> EQ -> seberang, lalu tembus seberang 1/4: 67.8% (acak 66.7%)
               - sisi yang tembus duluan = sisi yang disentuh: 85% (acak 83.3%, 0/10 th sebaliknya)
               Jendela NY 20:00-23:30 WITA: condong TEMBUS di ujung yang disentuh +4..5 poin (0/10 th sebaliknya);
               Asia ~ acak. => kotak TIDAK "dihormati"; sedikit momentum tembus (terlalu kecil untuk spread,
               lihat box_scalp3: ikut tembus ~52%, ~impas).
  [selesai] KOTAK CEPAT + TREN (research\box_trend.py, M5 2017-26):
               - Kotak SMC lama muncul median 25 mnt setelah puncak/dasar (konfirmasi fractal 5), harga sudah
                 bergerak median 46% tinggi kotak, 46% sudah lewat EQ. KOTAK CEPAT (ujung = high/low berjalan
                 sejak swing terakhir, leg >= 1 ATR): 0 mnt, 13%, 8%. Dipasang di SMC_Zones (InpFastBox, default
                 nyala) -> kotak Premium/EQ/Discount. Tab 3 (garis kotak + jurnal box) tetap kotak terkonfirmasi.
               - Jalur kotak cepat = geometri acak juga (EQ dulu 33.9 vs 33.3; seberang dulu 19.2 vs 20).
               - TREN (ujung searah vs lawan tren; SMA50 H1 / open hari / SMA20 D1 / arah leg): efek KONSISTEN tapi
                 KECIL. Ujung SEARAH tren: lebih sering tembus (+1.5..+2.2 poin, 10/10 th; jam NY +2.7..+4.2).
                 Ujung LAWAN tren: sedikit lebih sering balik ke EQ (+0.8..+1.9 poin; vs open hari 35.2% 10/10 th).
                 SMA20 D1 & arah leg: ~tidak ada beda.
  [selesai] SCALPING KOTAK + STOCHASTIC per JAM (research\stoch_box.py): kotak cepat, M5 2017-26 & M1 2021-26,
               Stochastic (5,3,3) (9,3,3) (14,3,3) (21,5,5); PANTUL (ujung 1/4 + silang dari 80/20 + candle searah)
               & TEMBUS (ujung 1/4 + silang searah K>=50 + candle searah); TP=SL 1xATR atau 1/2 kotak.
               KOTOR (tanpa biaya): menang 48.3-50.6% di SEMUA 32 kombinasi (R -0.035..+0.012) = lempar koin.
               BERSIH: M5 -0.30..-0.49R, M1 -0.43..-0.81R, 0 tahun positif. Per jam: 0 jam lolos (positif kedua
               periode & >=70% tahun) di M5 maupun M1; jam "terbaik" kotor 53-55% = sebaran acak (n 300-1500).
               => Stochastic tidak menambah konfirmasi di kotak SMC; scalping M1 dimakan biaya (ATR M1 ~$1).
  [selesai] PENYARINGAN SEMUA INDIKATOR (research\indicator_screen.py, screen_side.py, screen_drift.py):
               28 keluarga x 3 versi (EMA/MA cross, harga x EMA, MACD sinyal & nol, RSI pantul & x50, Stochastic,
               CCI, Williams %R, Bollinger pantul & tembus, Keltner, Donchian, DMI/ADX, PSAR, Supertrend, Ichimoku,
               Aroon, ROC, TRIX, Awesome, MFI, OBV, DeMarker, Heiken Ashi, Engulfing, Pin bar) x M5/M15/H1 x 2 exit
               = 438 strategi, 2017-2026. LOLOS (bersih + kedua periode + >=7/10 th): 0. Strategi ACAK: 1/1800.
               Menang kotor rata2 49.2-49.3%, R kotor ~-0.02. Kandidat "terbaik" = BUY tembus H1 tahan 24 jam,
               tapi BUY ACAK kapan saja juga +0.27 ATR/trade (reli emas). Hanya Keltner(50,2.5) BUY > BUY acak
               (+0.12 / +0.45, 8/10 th) - dipilih dari 438 lalu dipecah sisi -> HIPOTESIS, bukan temuan.
  [selesai] SURVEI TEKNIK TRADER (research\techniques.py, tom_check.py; aturan asli, eksekusi M1, 2017-2026):
               LOLOS 1 dari 26: Efek pergantian bulan (BUY close hari terakhir bulan, keluar close hari ke-3):
               +0.30 ATR harian bersih, 57% menang, kedua periode +, 7/10 th; vs BUY acak tahan sama: +0.14..+0.23
               ATR, lebih baik 7-9/10 th, t-stat 1.0-2.1 (dipilih dari 26 -> hipotesis kuat-sedang, 12 trade/th).
               GAGAL (bersih): ICT Silver Bullet -0.49R 0/10, ICT Judas Swing -0.43R 0/10, Holy Grail H1/M15 -0.24/-0.35,
               Turtle Soup -0.33, Turtle Soup+1 +0.12 (n=53, 6/10), 80-20 -0.41, Larry Williams VB ~0 (4/10),
               Connors RSI2 D1 +0.07 (5/10) / H1 -0.15, IBS -0.05, NR7 -0.05, inside bar D1 +0.03 (7/10, 2017-21 -0.01)
               / H1 -0.24, pivot pantul -0.10 / tembus -0.04, Camarilla pantul -0.14 / tembus -0.16, London breakout
               -0.04 (3/10), NY ORB 15/30 -0.14/-0.07, TTM squeeze -0.17, divergensi RSI -0.10, VWAP band -0.52,
               fade gap Senin -0.40.
  [selesai] STRATEGI PENGGUNA "Trend Pullback M5/M1 + BB & EMA" (research\scalp_test.py <hari>, 1 bulan 30 Agu-30 Sep
               2026): tren M5 EMA50&200 (+HH/HL opsional), pullback M1 ke EMA20/BB bawah, RSI14 M5 40-50 berbalik,
               rejection/engulfing M1; SL = low/high candle konfirmasi -/+ $0.30, TP 1/1.5/2R, maks 60 mnt.
               Aturan persis TP 1R: 377 trade (~18/hari), menang KOTOR 50.1% (R 0.00) = acak; bersih 35.5%, -0.38R,
               total -142R/bulan. Dengan HH/HL 108 trade, kotor 50.9%, bersih -0.36R. Semua sesi negatif.
               SL median $1.93 -> kena noise (tusukan sweep median $2.3).
  [selesai] STRATEGI PENGGUNA 2 "London/NY Liquidity Sweep + SMS" (research\sweep_sms_test.py <hari>, 1 bulan):
               sweep low/high Asia di 14-16 WIB & range London di 19-21 WIB, konfirmasi candle M5 kuat close melewati
               candle koreksi, SL wick sweep -$0.5 (min $3.75), TP 2R / swing M15. 36 trade: menang 30.6% (impas
               2R = 33.3%), -0.15R kotor / -0.17R bersih, total -6R (-$85 @0.01); TP swing M15 -0.25R. SL median ~$11.
               Biaya kini kecil (0.02R) tapi n=36 terlalu sedikit; logika mirip ICT Judas (10 th: -0.43R, 0/10).
  [selesai] 3 KOMBINASI PENGGUNA M5/M1 (research\combo_test.py <hari>, 1 bulan): K1 PSAR M5 + Donchian20 + CCI14 M1;
               K2 Williams%R M5 + EMA50 + candle penolakan + OBV M1; K3 MACD M5 + Fast Stoch(5,3) M1, SL 1.5/2 ATR M1.
               700-1370 trade/bulan; menang KOTOR = titik impas geometri (49-51% @1R, 33-36% @2R), R kotor -0.04..+0.05;
               bersih -0.17..-0.27R, total -133..-332R/bulan; semua sesi negatif.
  [selesai] KEJUTAN DATA (actual vs forecast; research\surprise_test.py; GoldPro kini mengekspor otomatis
               Common\Files\GoldPro_CalendarFull.csv, 18.073 rilis USD 2016-2026, impact_type MT5):
               A. menit rilis searah kejutan 56-58% (penting 58%, |z|>2 62%), SETIAP tahun >= 51% -> nyata tapi lemah.
               B. scalp M1 masuk menit ke-2 searah kejutan, tahan 5/15/30 mnt: untung kotor 50-51%, +$0.03..0.13; bersih
                  -$0.8..-0.9 per 0.01 lot, 0/10 th. Melawan menit-1 yang salah arah: kotor +$0.17..0.38, bersih -$0.6..-0.8.
               C. tick 2020-26: masuk +2 dtk searah kejutan: menang 52-56%, kotor +$0.50..0.65; bersih -$0.28..-0.47
                  (spread saat rilis); 2023-26 tahan 5-10 mnt +$0.09..0.36 tapi hanya 3/7 th positif. +10/+30 dtk kotor
                  +$0.11..0.36, bersih negatif. => arah kejutan terlihat hanya di detik-detik pertama; setelah bisa
                  dieksekusi manual/MT5 (latensi kalender), sisa gerak ~acak dan kalah biaya. TIDAK dipakai sbg sinyal.
               SIGNIFIKANSI (research\surprise_sig.py): arah 57.5% z=7.4 (2017-21 z=4.5, 2022-26 z=6.1) = nyata.
                  Candle M1 rilis 2.2x menit biasa. Jalur searah kejutan (mid dari -2 dtk): +2 dtk +$0.68, +10 dtk +$0.97,
                  +600 dtk +$1.33 -> separuh gerak habis di 2 dtk. Sisa +$0.65 < biaya ~$0.93; sd per trade $6.6;
                  scalp terbaik t=-1.34 (semua) / +1.02 (2023-26) = TIDAK signifikan untuk profit.
  [PENTING] BUG JAM KALENDER MT5: CalendarValueHistory memberi jam SEMUA tanggal dengan offset server SAAT
               INI -> di GoldPro_Calendar.csv (diekspor musim panas) rilis musim dingin tercatat +1 jam. Riset
               kini mengoreksi (sweep_cause.py, news_phase.py); GP_CalTime() mengoreksi di indikator (filter berita &
               dashboard) sekitar pergantian DST. Hasil terkoreksi: data 08:30 NY sweep 26% vs 5% tanpa rilis (5.8x),
               10 mnt sebelumnya 17% vs 6%; data 10:00 NY tetap tidak menambah (1.0x).
  [ ] Tahap 4 - Forward test (jurnal) di rezim vol tinggi sekarang; evaluasi per rezim (~akhir Oktober).
               Pengguna memutuskan sendiri soal trading live; proyek tidak membuat EA sampai ada bukti.

CATATAN TEKNIS PENTING
  - MetaTrader5 (Python): datetime TANPA zona waktu = jam lokal komputer (WITA) -> ujung data terpotong.
    Selalu pakai datetime UTC-aware atau copy_rates_from_pos.
  - Server broker = New York + 7 jam sepanjang tahun (ikut DST AS). London = UTC (+1 DST Inggris).
  - Data M1 broker bersih sejak 2017 (2015-2016 bolong).

TEMUAN RISET YANG MENJADI DASAR (1 tahun M5/M1, spread asli, uji 3 periode)
  - Arah antar-garis 0.25 ADR ~acak; peluang tersentuh (jarak + sisa waktu) terkalibrasi.
  - Straddle EQ (+/-0.15 ADR, menit ke-5, OCO, SL=EQ, TP 1.5x): +0.13R/hari setelah slippage.
  - AM Fix SELL 05:20-05:29 ET: menang ~72%. Breakout range Asia: +0.15R. HL/LH zigzag: +0.11R.
  - Gagal: 50 indikator klasik & kombinasinya, NY ORB, double top/bottom, fade/sweep.
