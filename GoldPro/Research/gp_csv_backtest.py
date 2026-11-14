#!/usr/bin/env python3
"""GoldPro standalone CSV research baseline (not the live GoldPro logic).

Reads MT5-exported OHLCV CSVs and evaluates a causal multi-timeframe EMA
consensus on M1 decision bars. No orders are sent. Signals use only bars whose
close time is at or before the decision time; simulated entry is the next M1
bar open. Output is diagnostic research, not a claim of a profitable strategy.

Expected files: XAUUSD_M1.csv, XAUUSD_M5.csv, XAUUSD_M15.csv,
XAUUSD_H1.csv, XAUUSD_H4.csv. Optional timeframe files are not required.
Expected columns: Time,Open,High,Low,Close,TickVolume,Spread,RealVolume.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import numpy as np
import pandas as pd

TF_MINUTES = {"M1": 1, "M5": 5, "M15": 15, "H1": 60, "H4": 240}
REQUIRED = ("Time", "Open", "High", "Low", "Close", "Spread")


def load_bars(path: Path, tf: str) -> pd.DataFrame:
    if not path.is_file():
        raise FileNotFoundError(f"Missing required data file: {path}")
    df = pd.read_csv(path)
    df.columns = [str(c).strip() for c in df.columns]
    missing = [c for c in REQUIRED if c not in df.columns]
    if missing:
        raise ValueError(f"{path.name}: missing columns {missing}; found {list(df.columns)}")
    df["Time"] = pd.to_datetime(df["Time"].astype(str).str.strip(), format="%Y.%m.%d %H:%M", errors="coerce")
    if df["Time"].isna().any():
        bad = int(df["Time"].isna().sum())
        raise ValueError(f"{path.name}: {bad} timestamps did not match YYYY.MM.DD HH:MM")
    for col in ("Open", "High", "Low", "Close", "Spread"):
        df[col] = pd.to_numeric(df[col], errors="coerce")
    df = df.dropna(subset=["Open", "High", "Low", "Close", "Spread"])
    df = df.sort_values("Time").drop_duplicates("Time", keep="last").reset_index(drop=True)
    if df.empty:
        raise ValueError(f"{path.name}: no valid OHLC rows")
    if (df["High"] < df[["Open", "Close", "Low"]].max(axis=1)).any() or (df["Low"] > df[["Open", "Close", "High"]].min(axis=1)).any():
        raise ValueError(f"{path.name}: invalid OHLC bar (high/low inconsistent)")
    # MT5 timestamps denote bar open. Signals become available only at bar close.
    df["AvailableAt"] = df["Time"] + pd.to_timedelta(TF_MINUTES[tf], unit="m")
    return df


def make_tf_vote(df: pd.DataFrame, tf: str) -> pd.DataFrame:
    close = df["Close"]
    ema = close.ewm(span=20, adjust=False, min_periods=20).mean()
    # Require both price/EMA position and a rising/falling EMA; all inputs are closed bars.
    prior = ema.shift(3)
    vote = np.where((close > ema) & (ema > prior), 1,
                    np.where((close < ema) & (ema < prior), -1, 0))
    return pd.DataFrame({"AvailableAt": df["AvailableAt"], f"vote_{tf}": vote})


def run(args: argparse.Namespace) -> dict:
    root = Path(args.data_dir)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    bars = {tf: load_bars(root / f"XAUUSD_{tf}.csv", tf) for tf in TF_MINUTES}

    m1 = bars["M1"].copy()
    # Decisions happen on a just-closed M1 bar; execution is at the following M1 open.
    m1["DecisionAt"] = m1["AvailableAt"]
    m1["EntryTime"] = m1["Time"].shift(-1)
    m1["EntryOpen"] = m1["Open"].shift(-1)
    m1["EntrySpread"] = m1["Spread"].shift(-1)
    votes = ["M5", "M15", "H1", "H4"]
    merged = m1[["Time", "DecisionAt", "EntryTime", "EntryOpen", "EntrySpread"]].copy()
    for tf in votes:
        feature = make_tf_vote(bars[tf], tf).sort_values("AvailableAt")
        merged = pd.merge_asof(merged.sort_values("DecisionAt"), feature,
                               left_on="DecisionAt", right_on="AvailableAt", direction="backward")
        merged = merged.drop(columns=["AvailableAt"])
    vote_cols = [f"vote_{tf}" for tf in votes]
    vote_matrix = merged[vote_cols].fillna(0).to_numpy(dtype=int)
    merged["bull_votes"] = (vote_matrix == 1).sum(axis=1)
    merged["bear_votes"] = (vote_matrix == -1).sum(axis=1)
    merged["signal"] = np.where(merged["bull_votes"] >= args.min_votes, 1,
                                np.where(merged["bear_votes"] >= args.min_votes, -1, 0))

    # Position exits are measured from next-bar open. Only contiguous M1 windows are included.
    m1_times = pd.Series(m1["Time"].to_numpy())
    m1_close = pd.Series(m1["Close"].to_numpy())
    m1_spread = pd.Series(m1["Spread"].to_numpy())
    time_to_index = {t: i for i, t in enumerate(m1_times)}
    entry_indices = merged["EntryTime"].map(time_to_index)
    summaries = []
    all_predictions = []
    for horizon in args.horizons:
        records = []
        for row_idx, entry_idx in entry_indices.items():
            sig = int(merged.at[row_idx, "signal"])
            if sig == 0 or pd.isna(entry_idx):
                continue
            ei = int(entry_idx)
            xi = ei + horizon - 1
            if xi >= len(m1):
                continue
            entry_time = m1_times.iloc[ei]
            exit_time = m1_times.iloc[xi]
            # Exit at the close of the bar ending horizon minutes after entry.
            if exit_time + pd.Timedelta(minutes=1) - entry_time != pd.Timedelta(minutes=horizon):
                continue  # skip market closures / missing-minute windows
            entry = float(merged.at[row_idx, "EntryOpen"])
            exit_bid = float(m1_close.iloc[xi])
            entry_spread = max(0.0, float(merged.at[row_idx, "EntrySpread"])) * args.point
            exit_spread = max(0.0, float(m1_spread.iloc[xi])) * args.point
            # Assumes OHLC are bid prices and MT5 Spread is quoted in points.
            gross = (exit_bid - entry) if sig > 0 else (entry - exit_bid)
            costs = entry_spread if sig > 0 else exit_spread
            # Buy enters ask and exits bid; sell enters bid and exits ask.
            net = gross - (entry_spread if sig > 0 else exit_spread)
            records.append({
                "decision_time": merged.at[row_idx, "DecisionAt"],
                "entry_time": entry_time,
                "exit_time": exit_time + pd.Timedelta(minutes=1),
                "horizon_minutes": horizon,
                "signal": sig,
                "bull_votes": int(merged.at[row_idx, "bull_votes"]),
                "bear_votes": int(merged.at[row_idx, "bear_votes"]),
                "entry_open_bid": entry,
                "exit_close_bid": exit_bid,
                "gross_move_price": gross,
                "estimated_spread_cost_price": costs,
                "net_move_price": net,
                "net_win": bool(net > 0),
            })
        pred = pd.DataFrame.from_records(records)
        if not pred.empty:
            pred.insert(0, "horizon_minutes", horizon)
            all_predictions.append(pred)
            summaries.append({
                "horizon_minutes": horizon,
                "signals": int(len(pred)),
                "buy_signals": int((pred["signal"] == 1).sum()),
                "sell_signals": int((pred["signal"] == -1).sum()),
                "coverage_pct_of_m1_decisions": round(100 * len(pred) / max(1, len(merged)), 4),
                "net_win_rate_pct": round(100 * pred["net_win"].mean(), 4),
                "mean_gross_move_price": float(pred["gross_move_price"].mean()),
                "mean_estimated_spread_cost_price": float(pred["estimated_spread_cost_price"].mean()),
                "mean_net_move_price": float(pred["net_move_price"].mean()),
                "median_net_move_price": float(pred["net_move_price"].median()),
            })
        else:
            summaries.append({"horizon_minutes": horizon, "signals": 0})
    summary = {
        "research_only": True,
        "strategy": "EMA20 trend consensus across closed M5/M15/H1/H4 bars; signal if at least min_votes TFs agree",
        "data_dir": str(root),
        "symbol": "XAUUSD",
        "point_price_unit": args.point,
        "spread_assumption": "MT5 Spread values are points; OHLC treated as bid; spread charged once at entry for buys or exit for sells",
        "min_votes": args.min_votes,
        "input_rows": {tf: int(len(df)) for tf, df in bars.items()},
        "input_start": {tf: str(df["Time"].iloc[0]) for tf, df in bars.items()},
        "input_end": {tf: str(df["Time"].iloc[-1]) for tf, df in bars.items()},
        "results": summaries,
        "limitations": [
            "This is a simple research proxy, not a replay of GoldPro SMC structure/POI/liquidity modules.",
            "No commission, slippage, swaps, order rejection, or intrabar execution modeling.",
            "Timestamp timezone does not affect same-file alignment, but session-based features are not included.",
            "Forward windows crossing missing M1 minutes are excluded.",
            "Overlapping forecast observations are not an independent-trade equity curve.",
        ],
    }
    if all_predictions:
        pd.concat(all_predictions, ignore_index=True).to_csv(out_dir / "predictions.csv", index=False)
    pd.DataFrame(summaries).to_csv(out_dir / "summary.csv", index=False)
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", required=True, help="Folder containing XAUUSD_M1.csv etc.")
    parser.add_argument("--out-dir", default=r"D:\GoldProResearch\results")
    parser.add_argument("--point", type=float, required=True, help="MT5 XAUUSD SYMBOL_POINT as price, e.g. 0.01 (check Specification)")
    parser.add_argument("--horizons", type=int, nargs="+", default=[15, 30, 60])
    parser.add_argument("--min-votes", type=int, choices=[3, 4], default=3)
    args = parser.parse_args()
    if args.point <= 0 or any(h <= 0 for h in args.horizons):
        parser.error("--point and horizons must be positive")
    try:
        result = run(args)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    print("\nRESEARCH BASELINE COMPLETE (not GoldPro production/strategy validation)")
    for item in result["results"]:
        print(item)
    print(f"\nOutputs: {args.out_dir}")
    print("Review summary.json limitations before interpreting results.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
