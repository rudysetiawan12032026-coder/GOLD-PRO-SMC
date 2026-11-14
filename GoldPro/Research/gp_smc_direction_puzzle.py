#!/usr/bin/env python3
"""GoldPro SMC direction map / puzzle replay. ANALYSIS ONLY, never trades.

Maps which future direction (UP / DOWN / FLAT) follows the available SMC and
candle context by WITA 30-minute slot, hour, weekday, GoldPro session, each
supplied TF independently, and selected combinations. Each row is an M1
point-in-time snapshot; other-TF features are joined only when their candles
have closed. No orders, entries, positions, trading costs, or PnL.

WITA uses fixed UTC+8. Broker/server timestamps are converted to UTC using the
GoldPro GP_Time convention: server UTC offset is --server-utc-winter (default
+2), optionally +1 during US DST. Session labels follow the GoldPro config:
Asia 20:00-24:00 New York, London 07:00-10:00 London, NY 07:00-10:00 New York;
otherwise OFF. This session definition is for mapping, not a trading signal.

Reads recognized XAUUSD_<TF>.csv in --data-dir, including M1/M2/M3/M4/M5/M6/
M10/M12/M15/M20/M30, H1/H2/H3/H4/H6/H8/H12, D1/W1/MN1. Requires
Time,Open,High,Low,Close. All times in source files must be server timestamps.

This is a Python research translation, not byte-for-byte MQL5 execution. It does
not simulate trades. A 12-month sample describes that sample, not durable edge.
"""
from __future__ import annotations
import argparse
import calendar
import json
import re
import sys
from pathlib import Path
from datetime import datetime, timedelta
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
    return time + pd.to_timedelta(n * (60 if tf[0] == "H" else 1), unit="m")


def discover_tfs(folder: Path) -> list[str]:
    found = []
    for path in folder.iterdir():
        match = TF_RE.match(path.name)
        if match and path.is_file():
            found.append(match.group(1).upper())
    if "M1" not in found:
        raise FileNotFoundError(f"XAUUSD_M1.csv not found in {folder}")
    def duration(tf: str) -> int:
        if tf == "MN1": return 43200
        if tf == "W1": return 10080
        if tf == "D1": return 1440
        return int(tf[1:]) * (60 if tf[0] == "H" else 1)
    return sorted(set(found), key=lambda tf: (duration(tf), tf))


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
    for col in OHLC:
        x[col] = pd.to_numeric(x[col], errors="coerce")
    x = x.dropna(subset=list(OHLC)).sort_values("Time").drop_duplicates("Time", keep="last").reset_index(drop=True)
    bad = x.High.lt(x[["Open", "Close", "Low"]].max(axis=1)) | x.Low.gt(x[["Open", "Close", "High"]].min(axis=1))
    if bad.any():
        print(f"WARNING {path.name}: dropped {int(bad.sum())} invalid OHLC bars", file=sys.stderr)
        x = x.loc[~bad].reset_index(drop=True)
    if x.empty:
        raise ValueError(f"{path.name}: no valid OHLC rows")
    x["AvailableAt"] = tf_duration_starts(x.Time, tf)
    return x


def nth_weekday(year: int, month: int, weekday: int, n: int) -> datetime:
    first_weekday, _ = calendar.monthrange(year, month)
    day = 1 + (weekday - first_weekday) % 7 + 7 * (n - 1)
    return datetime(year, month, day)


def us_dst_mask(utc: pd.Series) -> np.ndarray:
    """US DST in UTC: second Sunday Mar 07:00 through first Sunday Nov 06:00."""
    vals = utc.to_numpy(dtype="datetime64[ns]")
    years = utc.dt.year.to_numpy()
    result = np.zeros(len(utc), dtype=bool)
    for year in np.unique(years):
        start = np.datetime64(nth_weekday(int(year), 3, 6, 2) + timedelta(hours=7))
        end = np.datetime64(nth_weekday(int(year), 11, 6, 1) + timedelta(hours=6))
        mask = years == year
        result[mask] = (vals[mask] >= start) & (vals[mask] < end)
    return result


def uk_dst_mask(utc: pd.Series) -> np.ndarray:
    """UK DST in UTC: last Sunday Mar 01:00 through last Sunday Oct 01:00."""
    vals = utc.to_numpy(dtype="datetime64[ns]")
    years = utc.dt.year.to_numpy()
    result = np.zeros(len(utc), dtype=bool)
    for year in np.unique(years):
        march_last = max(d for d in range(25, 32) if datetime(int(year), 3, d).weekday() == 6)
        october_last = max(d for d in range(25, 32) if datetime(int(year), 10, d).weekday() == 6)
        start = np.datetime64(datetime(int(year), 3, march_last, 1))
        end = np.datetime64(datetime(int(year), 10, october_last, 1))
        mask = years == year
        result[mask] = (vals[mask] >= start) & (vals[mask] < end)
    return result


def server_to_utc(server: pd.Series, winter_offset: int, follows_us_dst: bool) -> pd.Series:
    """Invert GoldPro GP_Time server offset with candidate validation near DST changes."""
    winter = server - pd.to_timedelta(winter_offset, unit="h")
    if not follows_us_dst:
        return winter
    summer = server - pd.to_timedelta(winter_offset + 1, unit="h")
    winter_is_dst = us_dst_mask(winter)
    summer_is_dst = us_dst_mask(summer)
    winter_valid = ~winter_is_dst
    summer_valid = summer_is_dst
    # Standard candidate for rare gap/ambiguity minutes; otherwise use valid candidate.
    choose_summer = np.where(summer_valid, True, np.where(winter_valid, False, winter_is_dst))
    return pd.Series(np.where(choose_summer, summer.to_numpy(), winter.to_numpy()), index=server.index)


def add_wita_and_sessions(data: pd.DataFrame, server_utc_winter: int, server_follows_us_dst: bool) -> pd.DataFrame:
    utc = server_to_utc(data.DecisionAt, server_utc_winter, server_follows_us_dst)
    wita = utc + pd.Timedelta(hours=8)
    data["Time_WITA"] = wita
    data["weekday_WITA"] = wita.dt.day_name()
    data["weekday_num_WITA"] = wita.dt.dayofweek
    data["hour_WITA"] = wita.dt.hour
    data["minute_WITA"] = wita.dt.minute
    data["slot_30m_WITA"] = wita.dt.hour.astype(str).str.zfill(2) + ":" + (wita.dt.minute.floordiv(30) * 30).astype(str).str.zfill(2)
    data["weekday_slot_30m_WITA"] = data.weekday_WITA + "|" + data.slot_30m_WITA

    et = utc - pd.to_timedelta(np.where(us_dst_mask(utc), 4, 5), unit="h")
    london = utc + pd.to_timedelta(uk_dst_mask(utc).astype(int), unit="h")
    et_hour = et.dt.hour
    london_hour = london.dt.hour
    # GoldPro config session precedence/killzone windows.
    asia = et_hour.ge(20) & et_hour.lt(24)
    london_kz = london_hour.ge(7) & london_hour.lt(10)
    ny_kz = et_hour.ge(7) & et_hour.lt(10)
    data["session_WITA"] = np.select([asia, london_kz, ny_kz], ["ASIA", "LONDON", "NEW_YORK"], default="OFF")
    data["session_slot_30m_WITA"] = data.session_WITA.astype(str) + "|" + data.slot_30m_WITA
    data["session_weekday_WITA"] = data.session_WITA.astype(str) + "|" + data.weekday_WITA
    data["hour_ET"] = et.dt.hour
    data["hour_London"] = london.dt.hour
    return data


def true_atr(x: pd.DataFrame, n: int = 14) -> pd.Series:
    prev = x.Close.shift()
    tr = pd.concat([x.High - x.Low, (x.High - prev).abs(), (x.Low - prev).abs()], axis=1).max(axis=1)
    return tr.ewm(alpha=1 / n, adjust=False, min_periods=n).mean()


def candle_context(x: pd.DataFrame, tf: str, atr: pd.Series) -> pd.DataFrame:
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
    wick = pd.Series(np.select([(lower / span >= .55) & (body_ratio <= .35), (upper / span >= .55) & (body_ratio <= .35), body_ratio <= .10,
        (body_ratio >= .75) & (close_pos >= .75), (body_ratio >= .75) & (close_pos <= .25)],
        ["LOWER_REJECTION", "UPPER_REJECTION", "DOJI", "BULL_MARUBOZU_LIKE", "BEAR_MARUBOZU_LIKE"], default="OTHER"), index=x.index)
    prev_h, prev_l, prev_o, prev_c = h.shift(), l.shift(), o.shift(), c.shift()
    inside, outside = h.lt(prev_h) & l.gt(prev_l), h.gt(prev_h) & l.lt(prev_l)
    bull_engulf = (c > o) & (prev_c < prev_o) & (o <= prev_c) & (c >= prev_o)
    bear_engulf = (c < o) & (prev_c > prev_o) & (o >= prev_c) & (c <= prev_o)
    pattern = pd.Series(np.select([bull_engulf, bear_engulf, inside, outside], ["BULL_ENGULF", "BEAR_ENGULF", "INSIDE", "OUTSIDE"], default="OTHER"), index=x.index)
    rel_range = span / atr.replace(0, np.nan)
    range_state = pd.Series(np.select([rel_range.lt(.7), rel_range.gt(1.5)], ["CONTRACTED", "EXPANDED"], default="NORMAL"), index=x.index)
    run = np.zeros(len(x), dtype=np.int16)
    dirs = direction.to_numpy()
    for i in range(len(dirs)):
        run[i] = ((run[i-1] + 1) if i and dirs[i] != 0 and dirs[i] == dirs[i-1] else 1) if dirs[i] != 0 else 0
    streak = pd.Series(np.select([direction.eq(1), direction.eq(-1)], ["UP", "DOWN"], default="DOJI"), index=x.index) + "_" + pd.Series(np.select([run <= 1, run == 2, run >= 3], ["1", "2", "3PLUS"], default="0"), index=x.index)
    return pd.DataFrame({"AvailableAt": x.AvailableAt, f"{tf}_candle_dir": direction, f"{tf}_body_size": body_size,
        f"{tf}_body_ratio": body_ratio, f"{tf}_close_location": close_location, f"{tf}_wick_pattern": wick,
        f"{tf}_inside_outside": np.select([inside, outside], ["INSIDE", "OUTSIDE"], default="NORMAL"),
        f"{tf}_engulf_pattern": pattern, f"{tf}_range_state": range_state, f"{tf}_candle_streak": streak,
        f"{tf}_upper_wick_ratio": upper / span, f"{tf}_lower_wick_ratio": lower / span,
        f"{tf}_close_position": close_pos, f"{tf}_range_atr": rel_range})


def tf_features(x: pd.DataFrame, tf: str, pivot: int) -> pd.DataFrame:
    h, l, c, o = x.High, x.Low, x.Close, x.Open
    a, width = true_atr(x), 2 * pivot + 1
    raw_hi = h.where(h.eq(h.rolling(width, center=True, min_periods=width).max())).shift(pivot)
    raw_lo = l.where(l.eq(l.rolling(width, center=True, min_periods=width).min())).shift(pivot)
    last_hi, last_lo = raw_hi.ffill(), raw_lo.ffill()
    prev_hi, prev_lo = last_hi.shift(), last_lo.shift()
    up, dn = c.gt(prev_hi) & prev_hi.notna(), c.lt(prev_lo) & prev_lo.notna()
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
    for name, value in vals.items(): out[f"{tf}_{name}"] = value
    out[f"{tf}_close"] = c
    return out


def known_daily_weekly_context(m1: pd.DataFrame, bars: dict[str, pd.DataFrame]) -> pd.DataFrame:
    z = pd.DataFrame({"DecisionAt": m1.AvailableAt})
    for tf in ("D1", "W1"):
        if tf not in bars: continue
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


def map_features(data: pd.DataFrame, features: list[str], horizon: int, min_n: int, global_rates: dict[int, float]) -> pd.DataFrame:
    """One feature/state per row; avoids accidental giant cross-product groupings."""
    y, move = data[f"label_{horizon}m"], data[f"move_{horizon}m"]
    rows = []
    for feature in features:
        if feature not in data: continue
        values = data[feature]
        unique = values.nunique(dropna=True)
        if unique > 12:
            try: states = pd.qcut(values, q=5, duplicates="drop")
            except ValueError: continue
        else: states = values
        for state, idx in data.groupby(states, dropna=True, observed=True, sort=False).groups.items():
            actual = y.loc[idx].dropna()
            if len(actual) < min_n: continue
            m = move.loc[actual.index]
            up, down, flat = float((actual == 1).mean()), float((actual == -1).mean()), float((actual == 0).mean())
            rows.append({"horizon_minutes": horizon, "feature": feature, "state": str(state), "samples": len(actual),
                "future_up_pct": 100*up, "future_down_pct": 100*down, "future_flat_pct": 100*flat,
                "dominant_direction": "UP" if up > down and up > flat else "DOWN" if down > up and down > flat else "FLAT_OR_TIE",
                "up_delta_vs_global_pp": 100*(up-global_rates[1]), "down_delta_vs_global_pp": 100*(down-global_rates[-1]),
                "mean_forward_move": float(m.mean()), "median_forward_move": float(m.median())})
    return pd.DataFrame(rows)


def map_joint(data: pd.DataFrame, feature: str, horizon: int, min_n: int, global_rates: dict[int, float]) -> pd.DataFrame:
    if feature not in data: return pd.DataFrame()
    y, move = data[f"label_{horizon}m"], data[f"move_{horizon}m"]
    rows = []
    for state, idx in data.groupby(feature, dropna=True, observed=True, sort=False).groups.items():
        actual = y.loc[idx].dropna()
        if len(actual) < min_n: continue
        m = move.loc[actual.index]
        up, down, flat = float((actual == 1).mean()), float((actual == -1).mean()), float((actual == 0).mean())
        rows.append({"horizon_minutes": horizon, "combination": feature, "state": str(state), "samples": len(actual),
            "future_up_pct":100*up, "future_down_pct":100*down, "future_flat_pct":100*flat,
            "up_delta_vs_global_pp":100*(up-global_rates[1]), "down_delta_vs_global_pp":100*(down-global_rates[-1]),
            "mean_forward_move":float(m.mean()), "median_forward_move":float(m.median())})
    return pd.DataFrame(rows)


def encode_combos(data: pd.DataFrame, tfs: list[str]) -> list[str]:
    combo_cols=[]
    candle_tf=[tf for tf in tfs if f"{tf}_candle_dir" in data]
    struct_tf=[tf for tf in tfs if f"{tf}_structure" in data]
    for tf in candle_tf:
        data[f"{tf}_structure_candle_combo"] = (data[f"{tf}_structure"].astype(str)+"|"+data[f"{tf}_candle_dir"].astype(str)+"|"+
            data[f"{tf}_body_size"].astype(str)+"|"+data[f"{tf}_wick_pattern"].astype(str)+"|"+data[f"{tf}_inside_outside"].astype(str))
        data[f"{tf}_structure_candle_zone_combo"] = data[f"{tf}_structure"].astype(str)+"|"+data[f"{tf}_candle_dir"].astype(str)+"|"+data[f"{tf}_zone"].astype(str)
        combo_cols += [f"{tf}_structure_candle_combo", f"{tf}_structure_candle_zone_combo"]
    if struct_tf:
        up=data[[f"{tf}_structure" for tf in struct_tf]].gt(0).sum(axis=1)
        down=data[[f"{tf}_structure" for tf in struct_tf]].lt(0).sum(axis=1)
        data["mtf_structure_consensus"] = np.select([up.eq(len(struct_tf)), down.eq(len(struct_tf)), up.gt(down), down.gt(up)], ["ALL_UP", "ALL_DOWN", "LEAN_UP", "LEAN_DOWN"], default="MIXED")
        combo_cols.append("mtf_structure_consensus")
    for tf in struct_tf:
        data[f"combo_{tf}_structure_zone"] = data[f"{tf}_structure"].astype(str)+"|"+data[f"{tf}_zone"].astype(str)
        data[f"combo_{tf}_structure_sweep"] = data[f"{tf}_structure"].astype(str)+"|"+data[f"{tf}_sweep"].astype(str)
        data[f"combo_{tf}_structure_candle"] = data[f"{tf}_structure"].astype(str)+"|"+data[f"{tf}_candle_dir"].astype(str)+"|"+data[f"{tf}_body_size"].astype(str)
        combo_cols += [f"combo_{tf}_structure_zone", f"combo_{tf}_structure_sweep", f"combo_{tf}_structure_candle"]
    return combo_cols


def run(a: argparse.Namespace) -> None:
    root, out = Path(a.data_dir), Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    tfs = discover_tfs(root)
    bars = {tf: load_bars(root, tf) for tf in tfs}
    m1 = bars["M1"]
    data = pd.DataFrame({"Time":m1.Time, "DecisionAt":m1.AvailableAt, "Close":m1.Close})
    candle_by_tf, feature_by_tf = {}, {}
    for tf in tfs:
        x=bars[tf]; f=tf_features(x,tf,a.pivot); candle=candle_context(x,tf,true_atr(x))
        full=f.merge(candle,on="AvailableAt",how="inner").sort_values("AvailableAt")
        data=pd.merge_asof(data.sort_values("DecisionAt"),full,left_on="DecisionAt",right_on="AvailableAt",direction="backward").drop(columns="AvailableAt")
        candle_by_tf[tf]=[c for c in candle if c!="AvailableAt"]
        feature_by_tf[tf]=[c for c in f if c!="AvailableAt"]
    ctx=known_daily_weekly_context(m1,bars)
    for col in ctx: data[col]=ctx[col].to_numpy()
    data=add_wita_and_sessions(data,a.server_utc_winter,not a.no_server_us_dst)
    # Fixed directional puzzle score, no fitting on future labels.
    component_cols=[f"{tf}_{family}" for tf in tfs for family in ("structure","zone","fvg","sweep","ob")]
    component_cols += [c for c in ("D1_bias","W1_bias") if c in data]
    votes=data[component_cols].fillna(0).to_numpy(dtype=float)
    data["puzzle_score"]=votes.sum(axis=1)
    data["puzzle_up_votes"]=(votes>0).sum(axis=1); data["puzzle_down_votes"]=(votes<0).sum(axis=1)
    data["puzzle_direction"]=np.where(data.puzzle_score>=a.min_score,1,np.where(data.puzzle_score<=-a.min_score,-1,0))
    data["puzzle_agreement"]=np.maximum(data.puzzle_up_votes,data.puzzle_down_votes)/max(1,len(component_cols))
    combo_cols=encode_combos(data,tfs)
    # Explicit session/time/day x context puzzle states. Session uses GoldPro exchange-hour windows, time buckets are WITA.
    for key, base in (("session_slot_WITA","session_slot_30m_WITA"),("session_weekday_WITA","session_weekday_WITA"),
                      ("session_mtf_consensus","session_WITA"),("session_puzzle_direction","session_WITA"),
                      ("session_slot_puzzle_direction","session_slot_30m_WITA"),("weekday_slot_puzzle_direction","weekday_slot_30m_WITA")):
        suffix = data.puzzle_direction.astype(str) if "puzzle_direction" in key else data.mtf_structure_consensus.astype(str) if "mtf_consensus" in key else None
        if suffix is not None:
            data[key]=data[base].astype(str)+"|"+suffix
            combo_cols.append(key)
    lab=future_labels(m1,a.horizons,a.flat_band,a.max_stale_min)
    data=pd.concat([data.reset_index(drop=True),lab.reset_index(drop=True)],axis=1)
    data.to_csv(out/"direction_snapshots.csv.gz",index=False,compression="gzip")

    global_rates={}
    for horizon in a.horizons:
        y=data[f"label_{horizon}m"].dropna()
        global_rates[horizon]={-1:float((y==-1).mean()),0:float((y==0).mean()),1:float((y==1).mean())}
    map_specs={
        "direction_map_30m_WITA.csv":["slot_30m_WITA"], "direction_map_hour_WITA.csv":["hour_WITA"],
        "direction_map_weekday_WITA.csv":["weekday_WITA"], "direction_map_weekday_30m_WITA.csv":["weekday_slot_30m_WITA"],
        "direction_map_session.csv":["session_WITA"], "direction_map_session_30m_WITA.csv":["session_slot_30m_WITA"],
        "direction_map_session_weekday_WITA.csv":["session_weekday_WITA"],
    }
    for filename,features in map_specs.items():
        pieces=[]
        for h in a.horizons: pieces.append(map_features(data,features,h,a.min_samples,global_rates[h]))
        result=pd.concat([p for p in pieces if not p.empty],ignore_index=True) if any(not p.empty for p in pieces) else pd.DataFrame()
        if not result.empty: result.to_csv(out/filename,index=False)
    # Per-TF features are tabulated independently, avoiding a massive all-feature cross product.
    all_independent=[]
    for tf in tfs:
        feats=feature_by_tf[tf]+candle_by_tf[tf]
        for h in a.horizons:
            tbl=map_features(data,feats,h,a.min_samples,global_rates[h])
            if not tbl.empty:
                tbl.insert(1,"timeframe",tf); all_independent.append(tbl)
    if all_independent: pd.concat(all_independent,ignore_index=True).to_csv(out/"direction_features_by_tf.csv",index=False)
    # Main market-structure/candle profile: each TF independently; output row has feature/state identifying TF.
    structure_candle=[]
    for tf in tfs:
        feats=[c for c in feature_by_tf[tf]+candle_by_tf[tf] if c.endswith(("_structure","_bos","_choch","_zone","_ote","_sweep","_liquidity","_ob","_candle_dir","_body_size","_close_location","_wick_pattern","_inside_outside","_engulf_pattern","_range_state","_candle_streak"))]
        for h in a.horizons:
            tbl=map_features(data,feats,h,a.min_samples,global_rates[h])
            if not tbl.empty:
                tbl.insert(1,"timeframe",tf); structure_candle.append(tbl)
    if structure_candle: pd.concat(structure_candle,ignore_index=True).to_csv(out/"direction_structure_candle_by_tf.csv",index=False)
    joint=[]
    for feature in combo_cols+["puzzle_direction","puzzle_score","puzzle_agreement"]:
        for h in a.horizons:
            tbl=map_joint(data,feature,h,a.min_samples,global_rates[h])
            if not tbl.empty: joint.append(tbl)
    if joint: pd.concat(joint,ignore_index=True).to_csv(out/"direction_puzzle_combinations.csv",index=False)

    # Chronological directional check, descriptive only—not trade stats.
    checks=[]; cut=len(data)//2
    for h in a.horizons:
        actual=data[f"label_{h}m"]
        for period,lo,hi in (("first_half_descriptive",0,cut),("second_half_chronological_check",cut,len(data))):
            pred=data.puzzle_direction.iloc[lo:hi]; y=actual.iloc[lo:hi]; valid=pred.ne(0)&y.notna(); n=int(valid.sum())
            upm=valid&pred.eq(1); downm=valid&pred.eq(-1)
            checks.append({"horizon_minutes":h,"period":period,"directional_samples":n,"coverage_pct":100*n/max(1,int(y.notna().sum())),
                "directional_accuracy_including_flat_wrong_pct":100*float((pred[valid]==y[valid]).mean()) if n else None,
                "up_predictions":int(upm.sum()),"down_predictions":int(downm.sum()),
                "up_prediction_followed_by_up_pct":100*float((y[upm]==1).mean()) if upm.any() else None,
                "down_prediction_followed_by_down_pct":100*float((y[downm]==-1).mean()) if downm.any() else None})
    pd.DataFrame(checks).to_csv(out/"direction_composite_check.csv",index=False)
    summary={"purpose":"direction mapping only; no trades, positions, costs, or PnL",
        "timezone":"WITA fixed UTC+8", "server_to_utc":"GP_Time convention: server winter UTC offset configurable; optionally +1 during US DST",
        "session_windows":"GoldPro configuration: ASIA 20-24 ET; LONDON 07-10 London; NEW_YORK 07-10 ET; precedence Asia, London, New York; else OFF",
        "server_utc_winter_hours":a.server_utc_winter,"server_follows_us_dst":not a.no_server_us_dst,
        "input_timeframes":tfs,"input_rows":{tf:int(len(x)) for tf,x in bars.items()},
        "first_bar_server":{tf:str(x.Time.iloc[0]) for tf,x in bars.items()},"last_bar_server":{tf:str(x.Time.iloc[-1]) for tf,x in bars.items()},
        "first_bar_wita":str(data.Time_WITA.iloc[0]),"last_bar_wita":str(data.Time_WITA.iloc[-1]),
        "mapping_dimensions":["WITA 30-minute slot/hour/weekday/weekday x slot","GoldPro ASIA/LONDON/NY/OFF session x WITA time/day",
          "each TF candle and structure independently","structure+candle/zone/sweep combinations","MTF consensus and puzzle direction by session/time"],
        "horizons_minutes":a.horizons,"flat_band_price":a.flat_band,
        "limitations":["Python approximation, not direct MQL5 execution.","12-month input is discovery evidence only.","No order simulation or transaction economics.","Per-bar observations overlap and are dependent.",
          "Server timezone convention must match the source export; verify --server-utc-winter/--no-server-us-dst.","DST transition-boundary timestamps may need broker-specific validation.",
          "Do not tune using chronological check period and call it independent test."],
        "outputs":["direction_snapshots.csv.gz","direction_map_30m_WITA.csv","direction_map_hour_WITA.csv","direction_map_weekday_WITA.csv",
          "direction_map_weekday_30m_WITA.csv","direction_map_session.csv","direction_map_session_30m_WITA.csv","direction_map_session_weekday_WITA.csv",
          "direction_features_by_tf.csv","direction_structure_candle_by_tf.csv","direction_puzzle_combinations.csv","direction_composite_check.csv","direction_summary.json"]}
    (out/"direction_summary.json").write_text(json.dumps(summary,indent=2),encoding="utf-8")
    print("\nDIRECTION MAP COMPLETE — NO TRADES SIMULATED")
    print(f"TFs: {', '.join(tfs)}; M1 observations: {len(m1):,}; horizons: {a.horizons}")
    print(f"WITA: {summary['first_bar_wita']} .. {summary['last_bar_wita']}; outputs: {out}")


def main() -> int:
    p=argparse.ArgumentParser(description=__doc__,formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--data-dir",required=True)
    p.add_argument("--out-dir",default=r"D:\GoldProResearch\direction_map_WITA")
    p.add_argument("--horizons",type=int,nargs="+",default=[15,30,60])
    p.add_argument("--pivot",type=int,default=5)
    p.add_argument("--flat-band",type=float,default=0.0)
    p.add_argument("--min-score",type=int,default=3)
    p.add_argument("--min-samples",type=int,default=100)
    p.add_argument("--max-stale-min",type=int,default=2)
    p.add_argument("--server-utc-winter",type=int,default=2,help="GoldPro server winter UTC offset (default UTC+2)")
    p.add_argument("--no-server-us-dst",action="store_true",help="Disable +1 server offset during US DST")
    a=p.parse_args()
    if a.pivot<1 or a.min_score<1 or a.min_samples<1 or a.flat_band<0 or a.max_stale_min<0 or any(h<1 for h in a.horizons):
        p.error("pivot, min-score, min-samples, horizons must be positive; flat-band/max-stale nonnegative")
    if not -12<=a.server_utc_winter<=14: p.error("server-utc-winter must be between -12 and 14")
    try: run(a)
    except Exception as e:
        print(f"ERROR: {e}",file=sys.stderr); return 2
    return 0

if __name__=="__main__": raise SystemExit(main())
