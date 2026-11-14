#!/usr/bin/env python3
"""GoldPro SMC direction map / puzzle replay. ANALYSIS ONLY, never trades.

Maps which future direction (UP / DOWN / FLAT) follows the available SMC and
candle context by server-time 30-minute slot, hour, weekday, each supplied TF
independently, and selected combinations. Each row is a point-in-time M1
snapshot; features from other TFs are joined only after their bars close.

Reads every recognized XAUUSD_<TF>.csv in --data-dir, including M1/M2/M3/M4/
M5/M6/M10/M12/M15/M20/M30, H1/H2/H3/H4/H6/H8/H12, D1/W1/MN1. M1 is the
observation clock. Requires Time,Open,High,Low,Close. All times are treated
as broker/server timestamps; no timezone conversion is guessed.

This is a transparent Python research translation, not byte-for-byte MQL5
execution. It does not create entries/orders, positions, trading costs, PnL,
or trading recommendations. Output estimates direction frequencies/mean future
movement only. One year is discovery data, not proof of durable behavior.
"""
from __future__ import annotations
import argparse
import json
import re
import sys
from pathlib import Path
import numpy as np
import pandas as pd

OHLC = ("Open", "High", "Low", "Close")
TF_RE = re.compile(r"^XAUUSD_(M\d+|H\d+|D1|W1|MN1)\.csv$", re.I)
FIXED_MINUTES = {"D1": 1440, "W1": 10080}


def tf_duration_starts(time: pd.Series, tf: str) -> pd.Series:
    if tf in FIXED_MINUTES:
        return time + pd.to_timedelta(FIXED_MINUTES[tf], unit="m")
    if tf == "MN1":
        return (time + pd.offsets.MonthBegin(1)).dt.floor("min")
    n = int(tf[1:])
    unit = 1 if tf[0] == "M" else 60
    return time + pd.to_timedelta(n * unit, unit="m")


def discover_tfs(folder: Path) -> list[str]:
    found = []
    for p in folder.iterdir():
        m = TF_RE.match(p.name)
        if m and p.is_file():
            found.append(m.group(1).upper())
    if "M1" not in found:
        raise FileNotFoundError(f"XAUUSD_M1.csv not found in {folder}")
    # ensure each timeframe appears once, sorted by actual resolution
    def minutes(tf: str) -> int:
        if tf == "MN1": return 43200
        if tf == "W1": return 10080
        if tf == "D1": return 1440
        return int(tf[1:]) * (60 if tf[0] == "H" else 1)
    return sorted(set(found), key=lambda x: (minutes(x), x))


def load_bars(folder: Path, tf: str) -> pd.DataFrame:
    path = folder / f"XAUUSD_{tf}.csv"
    x = pd.read_csv(path)
    x.columns = [str(c).strip() for c in x.columns]
    missing = [c for c in ("Time", *OHLC) if c not in x.columns]
    if missing:
        raise ValueError(f"{path.name}: missing columns {missing}; found {list(x.columns)}")
    x["Time"] = pd.to_datetime(x.Time.astype(str).str.strip(), format="%Y.%m.%d %H:%M", errors="coerce")
    if x.Time.isna().any():
        raise ValueError(f"{path.name}: invalid Time; expected YYYY.MM.DD HH:MM")
    for c in OHLC:
        x[c] = pd.to_numeric(x[c], errors="coerce")
    x = x.dropna(subset=list(OHLC)).sort_values("Time").drop_duplicates("Time", keep="last").reset_index(drop=True)
    invalid = x.High.lt(x[["Open", "Close", "Low"]].max(axis=1)) | x.Low.gt(x[["Open", "Close", "High"]].min(axis=1))
    if invalid.any():
        print(f"WARNING {path.name}: dropped {int(invalid.sum())} invalid OHLC bars", file=sys.stderr)
        x = x.loc[~invalid].reset_index(drop=True)
    if x.empty:
        raise ValueError(f"{path.name}: no valid OHLC rows")
    x["AvailableAt"] = tf_duration_starts(x.Time, tf)
    return x


def true_atr(x: pd.DataFrame, n: int = 14) -> pd.Series:
    prev = x.Close.shift()
    tr = pd.concat([x.High - x.Low, (x.High - prev).abs(), (x.Low - prev).abs()], axis=1).max(axis=1)
    return tr.ewm(alpha=1 / n, adjust=False, min_periods=n).mean()


def candle_context(x: pd.DataFrame, tf: str, atr: pd.Series) -> pd.DataFrame:
    """Candle anatomy/state, independently calculated from each TF's own bars."""
    o, h, l, c = x.Open, x.High, x.Low, x.Close
    span = (h - l).replace(0, np.nan)
    body = c - o
    body_ratio = body.abs() / span
    upper = h - pd.concat([o, c], axis=1).max(axis=1)
    lower = pd.concat([o, c], axis=1).min(axis=1) - l
    close_pos = (c - l) / span
    direction = np.sign(body).astype("int8")
    body_size = pd.Series(np.select([body_ratio.lt(.25), body_ratio.lt(.60)], ["SMALL", "MEDIUM"], default="LARGE"), index=x.index)
    close_location = pd.Series(np.select([close_pos.le(1/3), close_pos.ge(2/3)], ["LOW", "HIGH"], default="MID"), index=x.index)
    wick_pattern = pd.Series(np.select([
        (lower / span >= .55) & (body_ratio <= .35),
        (upper / span >= .55) & (body_ratio <= .35),
        body_ratio <= .10,
        (body_ratio >= .75) & (close_pos >= .75),
        (body_ratio >= .75) & (close_pos <= .25)],
        ["LOWER_REJECTION", "UPPER_REJECTION", "DOJI", "BULL_MARUBOZU_LIKE", "BEAR_MARUBOZU_LIKE"], default="OTHER"), index=x.index)
    prev_h, prev_l = h.shift(), l.shift()
    inside = (h < prev_h) & (l > prev_l)
    outside = (h > prev_h) & (l < prev_l)
    prev_o, prev_c = o.shift(), c.shift()
    bull_engulf = (c > o) & (prev_c < prev_o) & (o <= prev_c) & (c >= prev_o)
    bear_engulf = (c < o) & (prev_c > prev_o) & (o >= prev_c) & (c <= prev_o)
    pattern = pd.Series(np.select([bull_engulf, bear_engulf, inside, outside], ["BULL_ENGULF", "BEAR_ENGULF", "INSIDE", "OUTSIDE"], default="OTHER"), index=x.index)
    rel_range = span / atr.replace(0, np.nan)
    range_size = pd.Series(np.select([rel_range.lt(.7), rel_range.gt(1.5)], ["CONTRACTED", "EXPANDED"], default="NORMAL"), index=x.index)
    # Consecutive same-color closed candles; run length resets on doji/opposite candle.
    run = np.zeros(len(x), dtype=np.int16)
    dirs = direction.to_numpy()
    for i in range(len(dirs)):
        run[i] = (run[i-1] + 1 if i and dirs[i] != 0 and dirs[i] == dirs[i-1] else 1) if dirs[i] != 0 else 0
    streak = pd.Series(np.select([direction.eq(1), direction.eq(-1)], ["UP", "DOWN"], default="DOJI"), index=x.index) + "_" + pd.Series(np.select([run <= 1, run == 2, run >= 3], ["1", "2", "3PLUS"], default="0"), index=x.index)
    out = pd.DataFrame({"AvailableAt": x.AvailableAt,
        f"{tf}_candle_dir": direction, f"{tf}_body_size": body_size,
        f"{tf}_body_ratio": body_ratio, f"{tf}_close_location": close_location,
        f"{tf}_wick_pattern": wick_pattern, f"{tf}_inside_outside": np.select([inside, outside], ["INSIDE", "OUTSIDE"], default="NORMAL"),
        f"{tf}_engulf_pattern": pattern, f"{tf}_range_state": range_size,
        f"{tf}_candle_streak": streak, f"{tf}_upper_wick_ratio": upper / span,
        f"{tf}_lower_wick_ratio": lower / span, f"{tf}_close_position": close_pos,
        f"{tf}_range_atr": rel_range})
    return out


def tf_features(x: pd.DataFrame, tf: str, pivot: int) -> pd.DataFrame:
    h, l, c, o = x.High, x.Low, x.Close, x.Open
    a = true_atr(x)
    width = 2 * pivot + 1
    # A centered pivot is usable only after right-side confirmation bars have closed.
    raw_hi = h.where(h.eq(h.rolling(width, center=True, min_periods=width).max())).shift(pivot)
    raw_lo = l.where(l.eq(l.rolling(width, center=True, min_periods=width).min())).shift(pivot)
    last_hi, last_lo = raw_hi.ffill(), raw_lo.ffill()
    prev_hi, prev_lo = last_hi.shift(), last_lo.shift()
    up = c.gt(prev_hi) & prev_hi.notna()
    dn = c.lt(prev_lo) & prev_lo.notna()
    event = pd.Series(np.select([up, dn], [1, -1], default=0), index=x.index, dtype="int8")
    struct = event.replace(0, np.nan).ffill().fillna(0).astype("int8")
    prior_struct = struct.shift().fillna(0)
    choch = (((event == 1) & (prior_struct == -1)) | ((event == -1) & (prior_struct == 1))).astype("int8")
    bos = (event * (choch == 0)).astype("int8")
    rng = last_hi - last_lo
    pos = ((c - last_lo) / rng).where(rng.gt(0))
    zone = pd.Series(np.select([pos.lt(.5), pos.gt(.5)], [-1, 1], default=0), index=x.index, dtype="int8")
    ote = ((struct.eq(1) & pos.between(.21, .382)) | (struct.eq(-1) & pos.between(.618, .79))).astype("int8")
    bull_fvg = l.gt(h.shift(2)) & (l - h.shift(2)).ge(.05 * a)
    bear_fvg = h.lt(l.shift(2)) & (l.shift(2) - h).ge(.05 * a)
    fvg_event = pd.Series(np.select([bull_fvg, bear_fvg], [1, -1], default=0), index=x.index, dtype="int8")
    fvg = fvg_event.replace(0, np.nan).ffill().fillna(0).astype("int8")
    sweep = pd.Series(np.select([h.gt(prev_hi) & c.lt(prev_hi), l.lt(prev_lo) & c.gt(prev_lo)], [-1, 1], default=0), index=x.index, dtype="int8")
    eqh = prev_hi.notna() & last_hi.notna() & (last_hi - prev_hi).abs().le(.1 * a)
    eql = prev_lo.notna() & last_lo.notna() & (last_lo - prev_lo).abs().le(.1 * a)
    liq = (eqh.astype(int) - eql.astype(int)).astype("int8")
    # Explicit OB proxy: previous opposite-color candle on structure break; not full persistent POI replay.
    prev_dir = np.sign(c.shift() - o.shift())
    ob_event = event.where((event != 0) & (prev_dir != event), 0)
    ob_dir = ob_event.replace(0, np.nan).ffill().fillna(0).astype("int8")
    ob_hi, ob_lo = h.shift().where(ob_event != 0).ffill(), l.shift().where(ob_event != 0).ffill()
    ob = ob_dir.where(((ob_dir == 1) & c.ge(ob_lo)) | ((ob_dir == -1) & c.le(ob_hi)), 0).astype("int8")
    er = (c - c.shift(20)).abs() / c.diff().abs().rolling(20, min_periods=20).sum().replace(0, np.nan)
    atr_rel = a / a.rolling(100, min_periods=30).mean()
    regime = pd.Series(np.select([atr_rel.lt(.6), er.ge(.35)], [-1, 1], default=0), index=x.index, dtype="int8")
    pressure = ((c - o) / (h - l).replace(0, np.nan)).clip(-1, 1).fillna(0)
    vals = {"structure": struct, "bos": bos, "choch": choch, "zone": zone, "ote": ote,
            "fvg": fvg, "sweep": sweep, "liquidity": liq, "ob": ob, "regime": regime,
            "er": er, "atr_rel": atr_rel, "pressure": pressure}
    out = pd.DataFrame({"AvailableAt": x.AvailableAt})
    for k, v in vals.items(): out[f"{tf}_{k}"] = v
    out[f"{tf}_close"] = c
    return out


def known_daily_weekly_context(m1: pd.DataFrame, bars: dict[str, pd.DataFrame]) -> pd.DataFrame:
    z = pd.DataFrame({"DecisionAt": m1.AvailableAt})
    for tf in ("D1", "W1"):
        q = bars[tf][["Time", "Open", "Close"]].copy().sort_values("Time")
        q[f"{tf}_prev_close"] = q.Close.shift()
        q = q.rename(columns={"Time": "period_start", "Open": f"{tf}_open"})[["period_start", f"{tf}_open", f"{tf}_prev_close"]]
        z = pd.merge_asof(z.sort_values("DecisionAt"), q, left_on="DecisionAt", right_on="period_start", direction="backward").drop(columns="period_start")
        z[f"{tf}_eq"] = (z[f"{tf}_open"] + z[f"{tf}_prev_close"]) / 2
        z[f"{tf}_bias"] = np.sign(m1.Close.to_numpy() - z[f"{tf}_eq"].to_numpy())
    return z.drop(columns="DecisionAt")


def future_labels(m1: pd.DataFrame, horizons: list[int], flat_band: float, max_stale: int) -> pd.DataFrame:
    t, close = m1.Time.to_numpy(dtype="datetime64[ns]"), m1.Close.to_numpy(dtype=float)
    now = t + np.timedelta64(1, "m")
    out = pd.DataFrame(index=m1.index)
    for mins in horizons:
        target = now + np.timedelta64(mins, "m")
        ix = np.searchsorted(t, target - np.timedelta64(1, "m"), side="right") - 1
        safe = np.clip(ix, 0, len(t) - 1)
        close_time = t[safe] + np.timedelta64(1, "m")
        valid = (ix >= 0) & (ix < len(t)) & ((target - close_time) <= np.timedelta64(max_stale, "m"))
        move = np.full(len(t), np.nan)
        move[valid] = close[ix[valid]] - close[valid]
        label = np.full(len(t), np.nan)
        label[valid] = np.where(move[valid] > flat_band, 1, np.where(move[valid] < -flat_band, -1, 0))
        out[f"move_{mins}m"], out[f"label_{mins}m"] = move, label
    return out


def map_table(data: pd.DataFrame, group_cols: list[str], horizon: int, min_n: int, global_rates: dict[int, float]) -> pd.DataFrame:
    y, move = data[f"label_{horizon}m"], data[f"move_{horizon}m"]
    rows = []
    grouped = data.groupby(group_cols, dropna=False, observed=True, sort=False)
    for key, g in grouped:
        yy = y.loc[g.index].dropna()
        if len(yy) < min_n: continue
        mm = move.loc[yy.index]
        rates = {"up": float((yy == 1).mean()), "down": float((yy == -1).mean()), "flat": float((yy == 0).mean())}
        dominant = max(("UP", rates["up"]), ("DOWN", rates["down"]), ("FLAT", rates["flat"]), key=lambda q:q[1])
        row = {"horizon_minutes": horizon, "samples": len(yy), "future_up_pct": 100*rates["up"], "future_down_pct": 100*rates["down"],
               "future_flat_pct": 100*rates["flat"], "dominant_outcome": dominant[0], "dominant_share_pct": 100*dominant[1],
               "directional_share_pct": 100*max(rates["up"], rates["down"]),
               "up_delta_vs_global_pp": 100*(rates["up"]-global_rates[1]), "down_delta_vs_global_pp": 100*(rates["down"]-global_rates[-1]),
               "mean_forward_move": float(mm.mean()), "median_forward_move": float(mm.median())}
        if len(group_cols) == 1: row[group_cols[0]] = key
        else: row.update(dict(zip(group_cols, key if isinstance(key, tuple) else (key,))))
        rows.append(row)
    return pd.DataFrame(rows)


def encode_combos(data: pd.DataFrame, tfs: list[str]) -> list[str]:
    cols = []
    for tf in tfs:
        # Per-TF structural and candle features remain independently available in snapshots/maps.
        data[f"{tf}_structure_candle_combo"] = (data[f"{tf}_structure"].astype(str) + "|" +
            data[f"{tf}_candle_dir"].astype(str) + "|" + data[f"{tf}_wick_pattern"].astype(str) + "|" + data[f"{tf}_inside_outside"].astype(str))
        cols.append(f"{tf}_structure_candle_combo")
    # Broad MTF signature and consensus classes are intentionally compact to retain useful sample counts.
    struct_cols = [f"{tf}_structure" for tf in tfs]
    up = data[struct_cols].gt(0).sum(axis=1); down = data[struct_cols].lt(0).sum(axis=1)
    data["mtf_structure_consensus"] = np.select([up.eq(len(tfs)), down.eq(len(tfs)), up.gt(down), down.gt(up)],
                                                ["ALL_UP", "ALL_DOWN", "LEAN_UP", "LEAN_DOWN"], default="MIXED")
    for tf in tfs:
        data[f"combo_{tf}_structure_zone"] = data[f"{tf}_structure"].astype(str) + "|" + data[f"{tf}_zone"].astype(str)
        data[f"combo_{tf}_structure_sweep"] = data[f"{tf}_structure"].astype(str) + "|" + data[f"{tf}_sweep"].astype(str)
        data[f"combo_{tf}_structure_candle"] = data[f"{tf}_structure"].astype(str) + "|" + data[f"{tf}_candle_dir"].astype(str) + "|" + data[f"{tf}_body_size"].astype(str)
        cols += [f"combo_{tf}_structure_zone", f"combo_{tf}_structure_sweep", f"combo_{tf}_structure_candle"]
    cols.append("mtf_structure_consensus")
    return cols


def run(a: argparse.Namespace) -> None:
    root, out = Path(a.data_dir), Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    tfs = discover_tfs(root)
    bars = {tf: load_bars(root, tf) for tf in tfs}
    m1 = bars["M1"]
    data = pd.DataFrame({"Time": m1.Time, "DecisionAt": m1.AvailableAt, "Close": m1.Close})
    candle_cols_by_tf, feature_cols_by_tf = {}, {}
    for tf in tfs:
        x = bars[tf]
        atr = true_atr(x)
        f = tf_features(x, tf, a.pivot)
        candle = candle_context(x, tf, atr)
        full = f.merge(candle, on="AvailableAt", how="inner").sort_values("AvailableAt")
        data = pd.merge_asof(data.sort_values("DecisionAt"), full, left_on="DecisionAt", right_on="AvailableAt", direction="backward")
        data = data.drop(columns="AvailableAt")
        candle_cols_by_tf[tf] = [c for c in candle.columns if c != "AvailableAt"]
        feature_cols_by_tf[tf] = [c for c in f.columns if c != "AvailableAt"]
    if "D1" in bars and "W1" in bars:
        ctx = known_daily_weekly_context(m1, bars)
        for c in ctx: data[c] = ctx[c].to_numpy()
    # Server-time buckets, computed at decision timestamp, not converted to local/UTC.
    dt = data.DecisionAt
    data["weekday"] = dt.dt.day_name()
    data["weekday_num"] = dt.dt.dayofweek
    data["hour_server"] = dt.dt.hour
    data["minute_server"] = dt.dt.minute
    data["time_30m_server"] = dt.dt.hour.astype(str).str.zfill(2) + ":" + (dt.dt.minute.floordiv(30)*30).astype(str).str.zfill(2)
    data["time_hour_server"] = dt.dt.hour.astype(str).str.zfill(2) + ":00"
    data["weekday_time30"] = data.weekday + "|" + data.time_30m_server
    # Composite puzzle score from available directional SMC component signs; no fitting on future labels.
    component_cols = [f"{tf}_{fam}" for tf in tfs for fam in ("structure", "zone", "fvg", "sweep", "ob")]
    for c in ("D1_bias", "W1_bias"):
        if c in data: component_cols.append(c)
    votes = data[component_cols].fillna(0).to_numpy(dtype=float)
    data["puzzle_score"] = votes.sum(axis=1)
    data["puzzle_up_votes"] = (votes > 0).sum(axis=1)
    data["puzzle_down_votes"] = (votes < 0).sum(axis=1)
    data["puzzle_direction"] = np.where(data.puzzle_score >= a.min_score, 1, np.where(data.puzzle_score <= -a.min_score, -1, 0))
    data["puzzle_agreement"] = np.maximum(data.puzzle_up_votes, data.puzzle_down_votes) / max(1, len(component_cols))
    combo_cols = encode_combos(data, tfs)
    # Time x broad MTF state and time x puzzle state: compact joint puzzle maps.
    data["time30_mtf_consensus"] = data.time_30m_server.astype(str) + "|" + data.mtf_structure_consensus.astype(str)
    data["weekday_mtf_consensus"] = data.weekday.astype(str) + "|" + data.mtf_structure_consensus.astype(str)
    data["time30_puzzle_direction"] = data.time_30m_server.astype(str) + "|" + data.puzzle_direction.astype(str)
    data["weekday_puzzle_direction"] = data.weekday.astype(str) + "|" + data.puzzle_direction.astype(str)
    combos += ["time30_mtf_consensus", "weekday_mtf_consensus", "time30_puzzle_direction", "weekday_puzzle_direction"]
    lab = future_labels(m1, a.horizons, a.flat_band, a.max_stale_min)
    data = pd.concat([data.reset_index(drop=True), lab.reset_index(drop=True)], axis=1)
    data.to_csv(out / "direction_snapshots.csv.gz", index=False, compression="gzip")

    maps = {
        "direction_map_30m.csv": ["time_30m_server"],
        "direction_map_hour.csv": ["hour_server"],
        "direction_map_weekday.csv": ["weekday", "weekday_num"],
        "direction_map_weekday_30m.csv": ["weekday_time30"],
        "direction_structure_candle_tf.csv": [c for tf in tfs for c in candle_cols_by_tf[tf]],
        "direction_structure_tf.csv": [c for tf in tfs for c in feature_cols_by_tf[tf]],
        "direction_puzzle_combinations.csv": combos + ["puzzle_direction", "puzzle_score", "puzzle_agreement"],
    }
    global_summary = {}
    for horizon in a.horizons:
        y = data[f"label_{horizon}m"].dropna()
        global_summary[horizon] = {-1: float((y == -1).mean()), 0: float((y == 0).mean()), 1: float((y == 1).mean())}
    # Detailed conditional maps each get explicit horizon column; append all horizons to one file.
    for filename, cols in maps.items():
        sections = []
        for horizon in a.horizons:
            if filename == "direction_structure_candle_tf.csv":
                # Add one-feature-at-a-time tables for every TF candle state, plus independent direction/structure state.
                use = cols + [f"{tf}_structure" for tf in tfs] + [f"{tf}_candle_dir" for tf in tfs]
            else: use = cols
            use = [c for c in dict.fromkeys(use) if c in data]
            tbl = map_table(data, use, horizon, a.min_samples, global_summary[horizon])
            if not tbl.empty: sections.append(tbl)
        if sections: pd.concat(sections, ignore_index=True).to_csv(out / filename, index=False)

    # Chronological directional check of fixed puzzle direction, not a trading backtest.
    check = []
    split = int(len(data) * .5)
    for horizon in a.horizons:
        y = data[f"label_{horizon}m"]
        for period, lo, hi in (("first_half_descriptive", 0, split), ("second_half_chronological_check", split, len(data))):
            p = data.puzzle_direction.iloc[lo:hi]; actual = y.iloc[lo:hi]
            mask = p.ne(0) & actual.notna(); n = int(mask.sum())
            check.append({"horizon_minutes": horizon, "period": period, "directional_samples": n,
                          "coverage_pct": 100*n/max(1, int(actual.notna().sum())),
                          "directional_accuracy_including_flat_wrong_pct": 100*float((p[mask] == actual[mask]).mean()) if n else None,
                          "up_predictions": int((p[mask] == 1).sum()), "down_predictions": int((p[mask] == -1).sum()),
                          "up_prediction_followed_by_up_pct": 100*float((actual[mask & p.eq(1)] == 1).mean()) if (mask & p.eq(1)).any() else None,
                          "down_prediction_followed_by_down_pct": 100*float((actual[mask & p.eq(-1)] == -1).mean()) if (mask & p.eq(-1)).any() else None})
    pd.DataFrame(check).to_csv(out / "direction_composite_check.csv", index=False)
    summary = {"purpose": "market direction mapping only; no trades, positions, costs, or PnL",
        "time_basis": "raw broker/server timestamps; timezone/DST not inferred",
        "input_timeframes": tfs, "input_rows": {tf: int(len(x)) for tf,x in bars.items()},
        "first_bar": {tf: str(x.Time.iloc[0]) for tf,x in bars.items()}, "last_bar": {tf: str(x.Time.iloc[-1]) for tf,x in bars.items()},
        "mapping_dimensions": ["30-minute server-time slot", "hour", "weekday", "weekday x 30-minute slot",
                               "each TF candle anatomy/state independently", "each TF structure/context independently",
                               "TF structure+candle/zone/sweep combinations", "MTF consensus", "time x consensus/puzzle state"],
        "direction_horizons_minutes": a.horizons, "flat_band_price": a.flat_band,
        "feature_families": ["confirmed swing/BOS-CHoCH", "premium/discount/OTE approximation", "daily/weekly open and EQ",
          "FVG", "liquidity/sweep proxy", "OB context proxy", "ATR/efficiency regime", "candlestick direction/body/wicks/inside-outside/engulf/range/streak", "all discovered TFs independently"],
        "not_faithfully_replayed": ["MQL chart/render/dashboard/alerts", "economic calendar/news blackout", "broker-specific session/DST and exact AMD/Judas",
          "full stateful OB/FVG/Breaker lifecycle and nested POI", "GoldDayMap probability tables", "SupplyDemand lifecycle"],
        "limitations": ["Python research approximation, not direct MQL5 execution.", "A 12-month sample describes this sample only; not year-to-year robustness.",
          "Direction labels compare M1 close now to latest M1 close available at horizon; no trading simulation.",
          "Observations overlap and are dependent; counts are not independent trials.", "Do not tune based on the chronological check and call it out-of-sample."],
        "outputs": list(maps) + ["direction_snapshots.csv.gz", "direction_composite_check.csv", "direction_summary.json"]}
    (out / "direction_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print("\nDIRECTION MAP COMPLETE — NO TRADES SIMULATED")
    print(f"TFs: {', '.join(tfs)}; M1 observations: {len(m1):,}; horizons: {a.horizons}")
    print(f"Outputs: {out}")
    return None


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--data-dir", required=True)
    p.add_argument("--out-dir", default=r"D:\GoldProResearch\direction_map")
    p.add_argument("--horizons", type=int, nargs="+", default=[15, 30, 60])
    p.add_argument("--pivot", type=int, default=5, help="confirmed swing radius per TF")
    p.add_argument("--flat-band", type=float, default=0.0, help="future move within +/- this XAU price amount is FLAT")
    p.add_argument("--min-score", type=int, default=3)
    p.add_argument("--min-samples", type=int, default=100)
    p.add_argument("--max-stale-min", type=int, default=2)
    a = p.parse_args()
    if a.pivot < 1 or a.min_score < 1 or a.min_samples < 1 or a.flat_band < 0 or a.max_stale_min < 0 or any(h < 1 for h in a.horizons):
        p.error("pivot, min-score, min-samples, horizons must be positive; flat-band/max-stale nonnegative")
    try:
        run(a)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
