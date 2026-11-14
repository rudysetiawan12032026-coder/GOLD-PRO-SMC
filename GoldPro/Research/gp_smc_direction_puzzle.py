#!/usr/bin/env python3
"""GoldPro SMC direction-puzzle replay. Direction analysis only; never trades.

Reads MT5 OHLC CSV exports, builds causal approximations of GoldPro's
structure, dealing-range zone, FVG, liquidity/sweep, OB context, volatility
regime, candle pressure, and closed-bar MTF context. At each M1 close it
records a composite direction state and compares it with future UP/DOWN/FLAT
price movement. No orders, entries, exits, positions, spread, costs, or PnL.

This is a research translation of direction-relevant ideas, not a byte-for-byte
execution of the MQL5 indicator. Visual/UI, calendar/news, DST session/AMD,
full stateful POI lifecycle, GoldDayMap and SupplyDemand are not replayed.

Expected files in --data-dir: XAUUSD_M1.csv, M5, M15, H1, H4, D1, W1.
Columns: Time,Open,High,Low,Close. Other columns are ignored.
"""
from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path
import numpy as np
import pandas as pd

TF_MINUTES = {"M1": 1, "M5": 5, "M15": 15, "H1": 60, "H4": 240, "D1": 1440, "W1": 10080}
MTF = ("M1", "M5", "M15", "H1", "H4")
OHLC = ("Open", "High", "Low", "Close")


def load_bars(folder: Path, tf: str) -> pd.DataFrame:
    path = folder / f"XAUUSD_{tf}.csv"
    if not path.is_file():
        raise FileNotFoundError(f"Missing required data file: {path}")
    x = pd.read_csv(path)
    x.columns = [str(c).strip() for c in x.columns]
    missing = [c for c in ("Time", *OHLC) if c not in x.columns]
    if missing:
        raise ValueError(f"{path.name}: missing columns {missing}; found {list(x.columns)}")
    x["Time"] = pd.to_datetime(x.Time.astype(str).str.strip(), format="%Y.%m.%d %H:%M", errors="coerce")
    if x.Time.isna().any():
        raise ValueError(f"{path.name}: invalid timestamp; expected YYYY.MM.DD HH:MM")
    for c in OHLC:
        x[c] = pd.to_numeric(x[c], errors="coerce")
    x = x.dropna(subset=list(OHLC)).sort_values("Time").drop_duplicates("Time", keep="last").reset_index(drop=True)
    bad = x.High.lt(x[["Open", "Close", "Low"]].max(axis=1)) | x.Low.gt(x[["Open", "Close", "High"]].min(axis=1))
    if bad.any():
        print(f"WARNING {path.name}: dropped {int(bad.sum())} invalid OHLC bars", file=sys.stderr)
        x = x.loc[~bad].reset_index(drop=True)
    if x.empty:
        raise ValueError(f"{path.name}: no valid OHLC rows")
    x["AvailableAt"] = x.Time + pd.to_timedelta(TF_MINUTES[tf], unit="m")
    return x


def true_atr(x: pd.DataFrame, n: int = 14) -> pd.Series:
    prev = x.Close.shift()
    tr = pd.concat([x.High - x.Low, (x.High - prev).abs(), (x.Low - prev).abs()], axis=1).max(axis=1)
    return tr.ewm(alpha=1 / n, adjust=False, min_periods=n).mean()


def tf_features(x: pd.DataFrame, tf: str, pivot: int) -> pd.DataFrame:
    """Approximate causal GoldPro feature families for a single TF."""
    h, l, c, o = x.High, x.Low, x.Close, x.Open
    a = true_atr(x)
    width = 2 * pivot + 1
    # Centered pivot is timestamped only after right-side confirmation bars have closed.
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

    width_range = last_hi - last_lo
    pos = ((c - last_lo) / width_range).where(width_range.gt(0))
    zone = pd.Series(np.select([pos.lt(.5), pos.gt(.5)], [-1, 1], default=0), index=x.index, dtype="int8")
    ote = ((struct.eq(1) & pos.between(.21, .382)) | (struct.eq(-1) & pos.between(.618, .79))).astype("int8")
    bull_gap = l.gt(h.shift(2)) & (l - h.shift(2)).ge(.05 * a)
    bear_gap = h.lt(l.shift(2)) & (l.shift(2) - h).ge(.05 * a)
    fvg_event = pd.Series(np.select([bull_gap, bear_gap], [1, -1], default=0), index=x.index, dtype="int8")
    fvg = fvg_event.replace(0, np.nan).ffill().fillna(0).astype("int8")
    sweep = pd.Series(np.select([h.gt(prev_hi) & c.lt(prev_hi), l.lt(prev_lo) & c.gt(prev_lo)], [-1, 1], default=0), index=x.index, dtype="int8")
    eqh = prev_hi.notna() & last_hi.notna() & (last_hi - prev_hi).abs().le(.1 * a)
    eql = prev_lo.notna() & last_lo.notna() & (last_lo - prev_lo).abs().le(.1 * a)
    liq = (eqh.astype(int) - eql.astype(int)).astype("int8")

    # Transparent OB context proxy: opposite-color previous candle when structure breaks.
    prev_candle_dir = np.sign(c.shift() - o.shift())
    ob_event = event.where((event != 0) & (prev_candle_dir != event), 0)
    ob_dir = ob_event.replace(0, np.nan).ffill().fillna(0).astype("int8")
    ob_hi = h.shift().where(ob_event != 0).ffill()
    ob_lo = l.shift().where(ob_event != 0).ffill()
    ob = ob_dir.where(((ob_dir == 1) & c.ge(ob_lo)) | ((ob_dir == -1) & c.le(ob_hi)), 0).astype("int8")

    er_n = 20
    er = (c - c.shift(er_n)).abs() / c.diff().abs().rolling(er_n, min_periods=er_n).sum().replace(0, np.nan)
    atr_rel = a / a.rolling(100, min_periods=30).mean()
    regime = pd.Series(np.select([atr_rel.lt(.6), er.ge(.35)], [-1, 1], default=0), index=x.index, dtype="int8")
    pressure = ((c - o) / (h - l).replace(0, np.nan)).clip(-1, 1).fillna(0)
    names = {"structure": struct, "bos": bos, "choch": choch, "zone": zone, "ote": ote,
             "fvg": fvg, "sweep": sweep, "liquidity": liq, "ob": ob, "regime": regime,
             "er": er, "atr_rel": atr_rel, "pressure": pressure}
    out = pd.DataFrame({"AvailableAt": x.AvailableAt})
    for name, value in names.items():
        out[f"{tf}_{name}"] = value
    out[f"{tf}_close"] = c
    return out


def add_known_d_w_context(m1: pd.DataFrame, d1: pd.DataFrame, w1: pd.DataFrame) -> pd.DataFrame:
    # D1/W1 current open is known at period start; previous close is already finalized.
    z = pd.DataFrame({"DecisionAt": m1.AvailableAt})
    for tf, src in (("D1", d1), ("W1", w1)):
        q = src[["AvailableAt", "Open", "Close"]].copy().sort_values("AvailableAt")
        q[f"{tf}_prev_close"] = q.Close.shift()
        q = q.rename(columns={"Open": f"{tf}_open"})[["AvailableAt", f"{tf}_open", f"{tf}_prev_close"]]
        z = pd.merge_asof(z.sort_values("DecisionAt"), q, left_on="DecisionAt", right_on="AvailableAt", direction="backward").drop(columns="AvailableAt")
        z[f"{tf}_eq"] = (z[f"{tf}_open"] + z[f"{tf}_prev_close"]) / 2
        z[f"{tf}_bias"] = np.sign(m1.Close.to_numpy() - z[f"{tf}_eq"].to_numpy())
    return z.drop(columns="DecisionAt")


def future_labels(m1: pd.DataFrame, horizons: list[int], flat_band: float, max_stale: int) -> pd.DataFrame:
    """Compare current M1 close to last M1 close available at exact future horizon."""
    t = m1.Time.to_numpy(dtype="datetime64[ns]")
    close = m1.Close.to_numpy(dtype=float)
    decision = t + np.timedelta64(1, "m")
    result = pd.DataFrame(index=m1.index)
    for mins in horizons:
        target = decision + np.timedelta64(mins, "m")
        # Bar close = bar-open timestamp + 1m. Select only bars closed by target.
        exit_idx = np.searchsorted(t, target - np.timedelta64(1, "m"), side="right") - 1
        safe = np.clip(exit_idx, 0, len(t) - 1)
        close_time = t[safe] + np.timedelta64(1, "m")
        valid = (exit_idx >= 0) & (exit_idx < len(t)) & ((target - close_time) <= np.timedelta64(max_stale, "m"))
        move = np.full(len(t), np.nan)
        move[valid] = close[exit_idx[valid]] - close[valid]
        result[f"move_{mins}m"] = move
        result[f"label_{mins}m"] = np.where(move > flat_band, 1, np.where(move < -flat_band, -1, 0))
    return result


def grouped_direction_results(data: pd.DataFrame, columns: list[str], horizon: int, min_n: int) -> pd.DataFrame:
    y, move = data[f"label_{horizon}m"], data[f"move_{horizon}m"]
    rows = []
    for col in columns:
        if col not in data:
            continue
        s = data[col]
        if s.nunique(dropna=True) > 8:
            try:
                group = pd.qcut(s, q=5, duplicates="drop")
            except ValueError:
                continue
        else:
            group = s
        for state, index in data.groupby(group, dropna=True, observed=True).groups.items():
            # Skip neutral component state; include composite score zero as useful calibration state.
            if col not in ("puzzle_score", "puzzle_agreement") and str(state) in ("0", "0.0"):
                continue
            actual = y.loc[index].dropna()
            if len(actual) < min_n:
                continue
            m = move.loc[actual.index]
            up, down, flat = float((actual == 1).mean()), float((actual == -1).mean()), float((actual == 0).mean())
            rows.append({"feature_or_combo": col, "state_or_quantile": str(state), "samples": len(actual),
                         "future_up_pct": 100 * up, "future_down_pct": 100 * down, "future_flat_pct": 100 * flat,
                         "dominant_direction": "UP" if up > down else "DOWN" if down > up else "TIE",
                         "directional_share_pct": 100 * max(up, down), "edge_vs_50pp": 100 * (max(up, down) - .5),
                         "mean_forward_move": float(m.mean()), "median_forward_move": float(m.median())})
    return pd.DataFrame(rows).sort_values(["edge_vs_50pp", "samples"], ascending=[False, False]) if rows else pd.DataFrame()


def run(a: argparse.Namespace) -> dict:
    root, out = Path(a.data_dir), Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    bars = {tf: load_bars(root, tf) for tf in TF_MINUTES}
    features = {tf: tf_features(bars[tf], tf, a.pivot) for tf in MTF}
    m1 = bars["M1"]
    data = pd.DataFrame({"Time": m1.Time, "DecisionAt": m1.AvailableAt, "Close": m1.Close})
    for tf in MTF:
        f = features[tf].sort_values("AvailableAt")
        data = pd.merge_asof(data.sort_values("DecisionAt"), f, left_on="DecisionAt", right_on="AvailableAt", direction="backward")
        data = data.drop(columns="AvailableAt")
    context = add_known_d_w_context(m1, bars["D1"], bars["W1"])
    for c in context.columns:
        data[c] = context[c].to_numpy()

    # Puzzle score is a fixed descriptive vote across feature families/timeframes, not fitted on outcome.
    component_cols = ([f"{tf}_{family}" for tf in MTF for family in ("structure", "zone", "fvg", "sweep", "ob")] + ["D1_bias", "W1_bias"])
    votes = data[component_cols].fillna(0).to_numpy(dtype=float)
    data["puzzle_score"] = votes.sum(axis=1)
    data["puzzle_up_votes"] = (votes > 0).sum(axis=1)
    data["puzzle_down_votes"] = (votes < 0).sum(axis=1)
    data["puzzle_agreement"] = np.maximum(data.puzzle_up_votes, data.puzzle_down_votes) / len(component_cols)
    data["puzzle_direction"] = np.where(data.puzzle_score >= a.min_score, 1, np.where(data.puzzle_score <= -a.min_score, -1, 0))
    # Explicit puzzle-combination states allow discovery beyond isolated indicators.
    for tf in ("M5", "M15", "H1", "H4"):
        data[f"combo_{tf}_structure_zone"] = data[f"{tf}_structure"].astype(str) + "|" + data[f"{tf}_zone"].astype(str)
        data[f"combo_{tf}_structure_sweep"] = data[f"{tf}_structure"].astype(str) + "|" + data[f"{tf}_sweep"].astype(str)
    data["combo_mtf_structure"] = np.select([
        data[[f"{tf}_structure" for tf in ("M5", "M15", "H1", "H4")]].gt(0).all(axis=1),
        data[[f"{tf}_structure" for tf in ("M5", "M15", "H1", "H4")]].lt(0).all(axis=1)], ["ALL_UP", "ALL_DOWN"], default="MIXED")
    data["combo_structure_zone_puzzle"] = data.combo_mtf_structure.astype(str) + "|" + data.puzzle_direction.astype(str)

    labels = future_labels(m1, a.horizons, a.flat_band, a.max_stale_min)
    data = pd.concat([data.reset_index(drop=True), labels.reset_index(drop=True)], axis=1)
    data.to_csv(out / "direction_snapshots.csv.gz", index=False, compression="gzip")
    families = [c for c in data.columns if any(c.endswith("_" + fam) for fam in ("structure", "bos", "choch", "zone", "ote", "fvg", "sweep", "liquidity", "ob", "regime", "er", "atr_rel", "pressure"))]
    combos = [c for c in data.columns if c.startswith("combo_")] + ["puzzle_direction", "puzzle_score", "puzzle_agreement"]
    ranking = []
    for horizon in a.horizons:
        table = grouped_direction_results(data, families + combos + ["D1_bias", "W1_bias"], horizon, a.min_samples)
        if not table.empty:
            table.insert(0, "horizon_minutes", horizon)
            ranking.append(table)
    ranked = pd.concat(ranking, ignore_index=True) if ranking else pd.DataFrame()
    if not ranked.empty:
        ranked.to_csv(out / "direction_feature_results.csv", index=False)

    # Fixed composite is checked in chronological halves. This is directional accuracy only, not trading.
    cut = len(data) // 2
    checks = []
    for horizon in a.horizons:
        y = data[f"label_{horizon}m"]
        for period, start, end in (("first_half_descriptive", 0, cut), ("second_half_chronological_check", cut, len(data))):
            pred = data.puzzle_direction.iloc[start:end]
            actual = y.iloc[start:end]
            valid = pred.ne(0) & actual.notna()
            n = int(valid.sum())
            up_mask, down_mask = valid & pred.eq(1), valid & pred.eq(-1)
            checks.append({"horizon_minutes": horizon, "period": period, "directional_samples": n,
                           "coverage_pct": 100 * n / max(1, int(actual.notna().sum())),
                           "accuracy_pct_including_flat_as_wrong": 100 * float((pred[valid] == actual[valid]).mean()) if n else None,
                           "up_prediction_count": int(up_mask.sum()), "down_prediction_count": int(down_mask.sum()),
                           "up_prediction_future_up_pct": 100 * float((actual[up_mask] == 1).mean()) if up_mask.any() else None,
                           "down_prediction_future_down_pct": 100 * float((actual[down_mask] == -1).mean()) if down_mask.any() else None})
    pd.DataFrame(checks).to_csv(out / "direction_composite_check.csv", index=False)

    summary = {"purpose": "market direction discovery only; no trade simulation or PnL",
               "data_dir": str(root), "rows": {tf: int(len(df)) for tf, df in bars.items()},
               "first_bar": {tf: str(df.Time.iloc[0]) for tf, df in bars.items()},
               "last_bar": {tf: str(df.Time.iloc[-1]) for tf, df in bars.items()},
               "horizons_minutes": a.horizons, "flat_band_price": a.flat_band,
               "feature_families": ["confirmed swing/BOS-CHoCH", "premium/discount/OTE approximation", "daily/weekly open and EQ",
                                    "3-candle FVG", "equal-swing liquidity/sweep proxy", "last-opposite-candle OB proxy",
                                    "efficiency ratio/relative ATR regime", "candle pressure", "closed MTF context"],
               "not_faithfully_replayed": ["MQL chart UI/rendering/alerts", "economic calendar/news blackout", "broker DST sessions and AMD/Judas exact replay",
                                           "full persistent OB/FVG/Breaker lifecycle and nested POI", "GoldDayMap probability tables", "SupplyDemand lifecycle"],
               "composite_rule": f"fixed unweighted sign sum of structure, zone, FVG, sweep, OB proxies across M1/M5/M15/H1/H4 plus D1/W1 EQ; direction when absolute score >= {a.min_score}",
               "outputs": ["direction_snapshots.csv.gz", "direction_feature_results.csv", "direction_composite_check.csv", "direction_summary.json"],
               "limitations": ["Python research approximation, not direct MQL5 module execution.", "A single 12-month sample is discovery, not evidence of year-to-year robustness.",
                               "Future labels use M1 close-to-close at horizon; flat means within configured price band.",
                               "Samples overlap and are dependent; directional hit rate is not a trade result.",
                               "Do not select feature rules on the chronological check set and then call it out-of-sample."]}
    (out / "direction_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--data-dir", required=True)
    p.add_argument("--out-dir", default=r"D:\GoldProResearch\direction_puzzle")
    p.add_argument("--horizons", type=int, nargs="+", default=[15, 30, 60])
    p.add_argument("--pivot", type=int, default=5)
    p.add_argument("--flat-band", type=float, default=0.0, help="Future move +/- price amount labeled FLAT")
    p.add_argument("--min-score", type=int, default=3)
    p.add_argument("--min-samples", type=int, default=100)
    p.add_argument("--max-stale-min", type=int, default=2, help="Maximum late M1 close after target horizon")
    a = p.parse_args()
    if a.pivot < 1 or a.min_score < 1 or a.min_samples < 1 or a.flat_band < 0 or a.max_stale_min < 0 or any(h < 1 for h in a.horizons):
        p.error("pivot, min-score, min-samples, and horizons must be positive; flat-band and max-stale-min nonnegative")
    try:
        run(a)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    print("\nDIRECTION PUZZLE ANALYSIS COMPLETE — NO TRADES SIMULATED")
    print(f"Outputs: {a.out_dir}")
    print("Review direction_feature_results.csv and direction_composite_check.csv; see direction_summary.json for scope.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
