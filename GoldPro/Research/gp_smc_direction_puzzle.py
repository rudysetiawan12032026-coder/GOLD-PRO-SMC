#!/usr/bin/env python3
"""GoldPro SMC direction-puzzle research: market direction only, never trades.

This standalone file combines causal, direction-relevant feature families from
GoldPro into one replay/evaluation pipeline. It reads exported MT5 OHLC CSVs,
forms snapshots using only information available at each M1 close, then asks
which feature states/combinations are historically associated with subsequent
UP, DOWN, or FLAT price movement. It does NOT create orders, entries, exits,
position sizing, PnL, spread costs, or a trading recommendation.

Feature families: confirmed swing structure/BOS-CHoCH bias, dealing-range
premium/discount/OTE, daily/weekly EQ context, FVG formation, liquidity sweep
and approximate equal-high/low pools, a causal last-opposite-candle OB proxy,
ATR/efficiency market regime, candle pressure, and closed-bar MTF context.
This is an auditable Python research translation of direction-relevant
concepts, not an execution of MQL5 modules or a claim that every visual,
notification, statistics, news-calendar, session-DST, map, and supply-demand
utility has been ported. Unsupported families are explicitly listed in report.

Expected CSVs in --data-dir: XAUUSD_M1.csv, M5, M15, H1, H4, D1, W1.
Columns: Time,Open,High,Low,Close (Spread/volume columns are ignored).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import numpy as np
import pandas as pd

TF_MINUTES = {"M1": 1, "M5": 5, "M15": 15, "H1": 60, "H4": 240, "D1": 1440, "W1": 10080}
FEATURE_TFS = ("M1", "M5", "M15", "H1", "H4")
OHLC = ("Open", "High", "Low", "Close")


def load_bars(folder: Path, tf: str) -> pd.DataFrame:
    path = folder / f"XAUUSD_{tf}.csv"
    if not path.is_file():
        raise FileNotFoundError(f"Missing required input: {path}")
    df = pd.read_csv(path)
    df.columns = [str(c).strip() for c in df.columns]
    missing = [c for c in ("Time", *OHLC) if c not in df.columns]
    if missing:
        raise ValueError(f"{path.name}: missing columns {missing}")
    df["Time"] = pd.to_datetime(df["Time"].astype(str).str.strip(), format="%Y.%m.%d %H:%M", errors="coerce")
    if df["Time"].isna().any():
        raise ValueError(f"{path.name}: invalid Time values")
    for c in OHLC:
        df[c] = pd.to_numeric(df[c], errors="coerce")
    df = df.dropna(subset=list(OHLC)).sort_values("Time").drop_duplicates("Time", keep="last").reset_index(drop=True)
    bad = (df.High < df[["Open", "Close", "Low"]].max(axis=1)) | (df.Low > df[["Open", "Close", "High"]].min(axis=1))
    if bad.any():
        print(f"WARNING {path.name}: dropped {int(bad.sum())} inconsistent OHLC bars", file=sys.stderr)
        df = df.loc[~bad].reset_index(drop=True)
    if df.empty:
        raise ValueError(f"{path.name}: no valid OHLC rows")
    # Bar timestamps are treated as bar-open timestamps; feature is usable at close.
    df["AvailableAt"] = df.Time + pd.to_timedelta(TF_MINUTES[tf], unit="m")
    return df


def atr(df: pd.DataFrame, period: int = 14) -> pd.Series:
    prev = df.Close.shift(1)
    tr = pd.concat([df.High - df.Low, (df.High - prev).abs(), (df.Low - prev).abs()], axis=1).max(axis=1)
    return tr.ewm(alpha=1 / period, adjust=False, min_periods=period).mean()


def signed_position(price: pd.Series, level: pd.Series) -> pd.Series:
    return np.sign(price - level).astype("float64")


def build_tf_features(df: pd.DataFrame, tf: str, pivot_n: int) -> pd.DataFrame:
    """Causal per-timeframe concepts. Pivots become visible only after right bars close."""
    x = df.copy()
    c, h, l, o = x.Close, x.High, x.Low, x.Open
    a = atr(x)
    # A centered pivot is shifted by pivot_n: detection becomes available at confirmation time,
    # rather than at the historical pivot candle (prevents pivot look-ahead).
    win = 2 * pivot_n + 1
    ph_raw = h.eq(h.rolling(win, center=True, min_periods=win).max())
    pl_raw = l.eq(l.rolling(win, center=True, min_periods=win).min())
    ph = h.where(ph_raw).shift(pivot_n)
    pl = l.where(pl_raw).shift(pivot_n)
    last_ph = ph.ffill()
    last_pl = pl.ffill()
    prev_bias = pd.Series(0, index=x.index, dtype="int8")
    up_break = c.gt(last_ph.shift(1)) & last_ph.shift(1).notna()
    dn_break = c.lt(last_pl.shift(1)) & last_pl.shift(1).notna()
    struct_event = pd.Series(np.select([up_break, dn_break], [1, -1], default=0), index=x.index, dtype="int8")
    struct_bias = struct_event.replace(0, np.nan).ffill().fillna(0).astype("int8")
    prior_bias = struct_bias.shift(1).fillna(0)
    choch = (((struct_event == 1) & (prior_bias == -1)) | ((struct_event == -1) & (prior_bias == 1))).astype("int8")
    bos = (struct_event * (choch == 0)).astype("int8")

    # Latest opposite confirmed swing pair approximates active dealing leg.
    last_ph_time = x.Time.where(ph.notna()).ffill()
    last_pl_time = x.Time.where(pl.notna()).ffill()
    leg_high = last_ph
    leg_low = last_pl
    range_ok = leg_high.gt(leg_low) & leg_high.notna() & leg_low.notna()
    pct = ((c - leg_low) / (leg_high - leg_low)).where(range_ok)
    zone = pd.Series(np.select([pct.lt(.5), pct.gt(.5)], [-1, 1], default=0), index=x.index, dtype="int8")
    # OTE band is side determined by latest structural bias, following Zones.mqh convention.
    ote_bull = pct.between(.21, .382, inclusive="both") & struct_bias.eq(1)
    ote_bear = pct.between(.618, .79, inclusive="both") & struct_bias.eq(-1)
    ote = (ote_bull | ote_bear).astype("int8")

    # Three-candle imbalance/FVG formation; latest direction persists as context.
    bull_fvg = (l > h.shift(2)) & ((l - h.shift(2)) >= .05 * a)
    bear_fvg = (h < l.shift(2)) & ((l.shift(2) - h) >= .05 * a)
    fvg_event = pd.Series(np.select([bull_fvg, bear_fvg], [1, -1], default=0), index=x.index, dtype="int8")
    fvg_bias = fvg_event.replace(0, np.nan).ffill().fillna(0).astype("int8")

    # Liquidity pool/sweep proxy from the latest confirmed swing, with 0.1 ATR equal-level tolerance.
    ph2 = ph.where(ph.notna())
    pl2 = pl.where(pl.notna())
    prev_ph = last_ph.shift(1)
    prev_pl = last_pl.shift(1)
    sweep = pd.Series(np.select([h.gt(prev_ph) & c.lt(prev_ph), l.lt(prev_pl) & c.gt(prev_pl)], [-1, 1], default=0), index=x.index, dtype="int8")
    equal_hi = (prev_ph.notna() & last_ph.notna() & (last_ph - prev_ph).abs().le(.1 * a)).astype("int8")
    equal_lo = (prev_pl.notna() & last_pl.notna() & (last_pl - prev_pl).abs().le(.1 * a)).astype("int8")
    liquidity_context = (equal_hi - equal_lo).astype("int8")

    # Causal OB proxy: last opposite candle at the immediately preceding bar when BOS/CHoCH closes.
    ob_event = struct_event.where((struct_event != 0) & ((np.sign(c.shift(1) - o.shift(1)) != struct_event)), 0)
    ob_bias = ob_event.replace(0, np.nan).ffill().fillna(0).astype("int8")
    ob_hi = h.shift(1).where(ob_event != 0).ffill()
    ob_lo = l.shift(1).where(ob_event != 0).ffill()
    ob_active = ((ob_bias == 1) & (c >= ob_lo)) | ((ob_bias == -1) & (c <= ob_hi))
    ob_context = ob_bias.where(ob_active, 0).astype("int8")

    # Regime: SMC efficiency ratio plus relative ATR, calculated using closed history only.
    er_n = 20
    er = (c - c.shift(er_n)).abs() / c.diff().abs().rolling(er_n, min_periods=er_n).sum().replace(0, np.nan)
    atr_rel = a / a.rolling(100, min_periods=30).mean()
    regime = pd.Series(np.select([atr_rel.lt(.6), er.ge(.35)], [-1, 1], default=0), index=x.index, dtype="int8")
    candle_pressure = ((c - o) / (h - l).replace(0, np.nan)).clip(-1, 1).fillna(0)
    eq_daily = signed_position(c, (c * 0 + np.nan))  # placeholder replaced by D1/W1 context below

    out = pd.DataFrame({
        "AvailableAt": x.AvailableAt,
        f"{tf}_structure": struct_bias,
        f"{tf}_bos": bos.astype("int8"),
        f"{tf}_choch": choch,
        f"{tf}_zone": zone,
        f"{tf}_ote": ote,
        f"{tf}_fvg": fvg_bias,
        f"{tf}_sweep": sweep,
        f"{tf}_liquidity": liquidity_context,
        f"{tf}_ob": ob_context,
        f"{tf}_regime": regime,
        f"{tf}_er": er,
        f"{tf}_atr_rel": atr_rel,
        f"{tf}_pressure": candle_pressure,
        f"{tf}_close": c,
    })
    return out


def add_daily_weekly_context(m1: pd.DataFrame, d1: pd.DataFrame, w1: pd.DataFrame) -> pd.DataFrame:
    """Map known daily/weekly open and prior close; never use current D/W high or low."""
    base = pd.DataFrame({"DecisionAt": m1.AvailableAt})
    for tf, src in (("D1", d1), ("W1", w1)):
        z = src[["AvailableAt", "Open", "Close"]].copy().sort_values("AvailableAt")
        z[f"{tf}_prev_close"] = z.Close.shift(1)
        z = z.rename(columns={"Open": f"{tf}_open"})[["AvailableAt", f"{tf}_open", f"{tf}_prev_close"]]
        base = pd.merge_asof(base.sort_values("DecisionAt"), z, left_on="DecisionAt", right_on="AvailableAt", direction="backward").drop(columns="AvailableAt")
        base[f"{tf}_eq"] = (base[f"{tf}_open"] + base[f"{tf}_prev_close"]) / 2
        base[f"{tf}_bias"] = np.sign(m1.Close.to_numpy() - base[f"{tf}_eq"].to_numpy())
    return base.drop(columns="DecisionAt")


def labels(m1: pd.DataFrame, horizons: list[int], flat_band: float) -> pd.DataFrame:
    """Future direction label only; no entry, trade, stop, target, or PnL."""
    t = m1.Time.to_numpy(dtype="datetime64[ns]")
    close = m1.Close.to_numpy(dtype=float)
    result = pd.DataFrame(index=m1.index)
    for mins in horizons:
        target = t + np.timedelta64(mins, "m")
        ix = np.searchsorted(t, target, side="right") - 1
        safe = np.clip(ix, 0, len(t) - 1)
        age = target - t[safe]
        move = np.full(len(t), np.nan)
        valid = (ix >= 0) & (ix < len(t)) & (age <= np.timedelta64(2, "m"))
        move[valid] = close[ix[valid]] - close[valid]
        result[f"move_{mins}m"] = move
        result[f"label_{mins}m"] = np.where(move > flat_band, 1, np.where(move < -flat_band, -1, 0))
    return result


def evaluate_groups(data: pd.DataFrame, features: list[str], horizon: int, min_n: int) -> pd.DataFrame:
    y = data[f"label_{horizon}m"]
    move = data[f"move_{horizon}m"]
    rows = []
    for feature in features:
        if feature not in data:
            continue
        vals = data[feature]
        # Directional states only. Continuous market measures are quantile-binned for discovery.
        if vals.nunique(dropna=True) > 7:
            try:
                group = pd.qcut(vals, q=5, duplicates="drop").astype(str)
                groups = [(str(k), idx) for k, idx in data.groupby(group, observed=True).groups.items()]
            except (ValueError, TypeError):
                continue
        else:
            groups = [(str(k), idx) for k, idx in data.groupby(vals, dropna=True).groups.items()]
        for state, idx in groups:
            if state in ("0", "0.0", "nan", "NaN"):
                continue
            yy = y.loc[idx].dropna()
            ix = yy.index
            if len(ix) < min_n:
                continue
            mm = move.loc[ix]
            buy_rate = float((yy == 1).mean())
            sell_rate = float((yy == -1).mean())
            rows.append({"feature": feature, "state_or_bin": state, "samples": len(ix),
                         "future_up_pct": 100 * buy_rate, "future_down_pct": 100 * sell_rate,
                         "future_flat_pct": 100 * float((yy == 0).mean()),
                         "dominant_future_direction": "UP" if buy_rate > sell_rate else "DOWN" if sell_rate > buy_rate else "TIE",
                         "mean_forward_move": float(mm.mean()), "median_forward_move": float(mm.median()),
                         "direction_edge_vs_50pp": 100 * (max(buy_rate, sell_rate) - .5)})
    if not rows:
        return pd.DataFrame()
    return pd.DataFrame(rows).sort_values(["direction_edge_vs_50pp", "samples"], ascending=[False, False])


def run(args: argparse.Namespace) -> dict:
    folder = Path(args.data_dir)
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    bars = {tf: load_bars(folder, tf) for tf in TF_MINUTES}
    features = {tf: build_tf_features(bars[tf], tf, args.pivot) for tf in FEATURE_TFS}

    m1 = bars["M1"].copy()
    data = pd.DataFrame({"Time": m1.Time, "DecisionAt": m1.AvailableAt, "Close": m1.Close})
    feature_cols: list[str] = []
    for tf in FEATURE_TFS:
        feat = features[tf].sort_values("AvailableAt")
        data = pd.merge_asof(data.sort_values("DecisionAt"), feat, left_on="DecisionAt", right_on="AvailableAt", direction="backward")
        data = data.drop(columns="AvailableAt")
        feature_cols.extend([c for c in feat.columns if c != "AvailableAt"])
    context = add_daily_weekly_context(m1, bars["D1"], bars["W1"])
    for c in context.columns:
        data[c] = context[c].to_numpy()
        feature_cols.append(c)

    # Transparent composite, not trained/tuned: direction feature votes from actual component families.
    vote_cols = [f"{tf}_structure" for tf in FEATURE_TFS] + [f"{tf}_zone" for tf in FEATURE_TFS] + [f"{tf}_fvg" for tf in FEATURE_TFS] + [f"{tf}_ob" for tf in FEATURE_TFS] + ["D1_bias", "W1_bias"]
    votes = data[vote_cols].fillna(0).to_numpy(dtype=float)
    data["puzzle_score"] = votes.sum(axis=1)
    data["puzzle_direction"] = np.where(data.puzzle_score >= args.min_score, 1, np.where(data.puzzle_score <= -args.min_score, -1, 0))
    data["puzzle_agreement"] = np.maximum((votes > 0).sum(axis=1), (votes < 0).sum(axis=1)) / votes.shape[1]
    feature_cols += ["puzzle_score", "puzzle_direction", "puzzle_agreement"]

    lab = labels(m1, args.horizons, args.flat_band)
    data = pd.concat([data.reset_index(drop=True), lab.reset_index(drop=True)], axis=1)
    data.to_csv(out / "direction_snapshots.csv.gz", index=False, compression="gzip")
    reports = []
    for horizon in args.horizons:
        report = evaluate_groups(data, feature_cols, horizon, args.min_samples)
        if not report.empty:
            report.insert(0, "horizon_minutes", horizon)
            reports.append(report)
    if reports:
        ranked = pd.concat(reports, ignore_index=True)
        ranked.to_csv(out / "direction_feature_results.csv", index=False)
    else:
        ranked = pd.DataFrame()

    # Evaluate fixed composite separately on chronological halves, reporting directional correctness/coverage.
    split = int(len(data) * .5)
    composite_rows = []
    for horizon in args.horizons:
        y = data[f"label_{horizon}m"]
        for period, sl in (("first_half_descriptive", slice(0, split)), ("second_half_out_of_sample_check", slice(split, len(data)))):
            pred = data.puzzle_direction.iloc[sl]
            yy = y.iloc[sl]
            valid = pred.ne(0) & yy.notna()
            n = int(valid.sum())
            composite_rows.append({"horizon_minutes": horizon, "period": period, "directional_samples": n,
                                   "coverage_pct": 100 * n / max(1, int(yy.notna().sum())),
                                   "directional_accuracy_pct": 100 * float((pred[valid] == yy[valid]).mean()) if n else None,
                                   "predicted_up": int((pred[valid] == 1).sum()), "predicted_down": int((pred[valid] == -1).sum()),
                                   "actual_up_pct": 100 * float((yy[valid] == 1).mean()) if n else None,
                                   "actual_down_pct": 100 * float((yy[valid] == -1).mean()) if n else None,
                                   "mean_forward_move_when_up_prediction": float(data.loc[valid[valid].index[pred[valid] == 1], f"move_{horizon}m"].mean()) if (valid & pred.eq(1)).any() else None,
                                   "mean_forward_move_when_down_prediction": float(data.loc[valid[valid].index[pred[valid] == -1], f"move_{horizon}m"].mean()) if (valid & pred.eq(-1)).any() else None})
    comp = pd.DataFrame(composite_rows)
    comp.to_csv(out / "direction_composite_check.csv", index=False)
    manifest = {
        "purpose": "direction discovery only; no simulated or real trades",
        "data_dir": str(folder), "feature_source_timeframes": list(FEATURE_TFS),
        "input_rows": {tf: int(len(df)) for tf, df in bars.items()},
        "input_start": {tf: str(df.Time.iloc[0]) for tf, df in bars.items()},
        "input_end": {tf: str(df.Time.iloc[-1]) for tf, df in bars.items()},
        "horizons_minutes": args.horizons, "flat_band_price": args.flat_band,
        "feature_families": ["confirmed swing/BOS-CHoCH structure", "premium/discount/OTE dealing-range approximation",
                             "daily/weekly open and EQ", "3-candle FVG", "equal swing liquidity/sweep approximation",
                             "last-opposite-candle OB proxy", "efficiency ratio/relative ATR regime", "candle pressure", "closed MTF context"],
        "not_ported_or_not_faithfully_replayable_here": ["MQL chart rendering/dashboard/alerts/export", "economic calendar/news blackout",
                             "broker-specific DST sessions and AMD/Judas exact replay", "full persistent OB/FVG/Breaker lifecycle and nested POI state",
                             "GoldDayMap probability tables and its journal", "SupplyDemand module lifecycle"],
        "limitations": ["One year of history is discovery-sized, not enough to establish a durable edge.",
                        "Feature concepts are Python research translations; not byte-for-byte MQL execution.",
                        "Current daily/weekly open and prior close are used; no developing D1/W1 high/low is used.",
                        "Direction labels use close-to-close move at each horizon; flat band is configurable.",
                        "Directional samples overlap; treat observations as dependent, not independent trials.",
                        "Second chronological half is an out-of-sample check only if parameters were not selected using its results.",
                        "No trading costs are relevant because this measures direction, not trade profitability."],
        "composite_rule": f"unweighted sum of structural, zone, FVG, OB-proxy, daily EQ, weekly EQ signs; direction only if |score| >= {args.min_score}",
        "outputs": ["direction_snapshots.csv.gz", "direction_feature_results.csv", "direction_composite_check.csv", "direction_summary.json"]
    }
    (out / "direction_summary.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--data-dir", required=True)
    p.add_argument("--out-dir", default=r"D:\GoldProResearch\direction_puzzle")
    p.add_argument("--horizons", type=int, nargs="+", default=[15, 30, 60])
    p.add_argument("--pivot", type=int, default=5, help="Confirmed swing radius; confirmed only after this many bars")
    p.add_argument("--flat-band", type=float, default=0.0, help="Future move inside +/- this price amount is labeled FLAT")
    p.add_argument("--min-score", type=int, default=3, help="Minimum unweighted feature vote magnitude for composite direction")
    p.add_argument("--min-samples", type=int, default=100)
    a = p.parse_args()
    if a.pivot < 1 or a.flat_band < 0 or a.min_score < 1 or a.min_samples < 1 or any(h < 1 for h in a.horizons):
        p.error("pivot, min-score, min-samples, and horizons must be positive; flat-band must be nonnegative")
    try:
        manifest = run(a)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    print("\nDIRECTION PUZZLE ANALYSIS COMPLETE — NO TRADES SIMULATED")
    print("Outputs:", a.out_dir)
    print("Feature ranking: direction_feature_results.csv")
    print("Composite chronological check: direction_composite_check.csv")
    print("See direction_summary.json for exact scope and limitations.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
