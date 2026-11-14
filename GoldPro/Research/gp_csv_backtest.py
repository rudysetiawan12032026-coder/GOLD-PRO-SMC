#!/usr/bin/env python3
"""GoldPro standalone CSV research baseline, v2 (not the live GoldPro logic).

Reads MT5-style OHLCV CSVs and evaluates a causal multi-timeframe EMA
consensus on M1 decision bars. No orders are sent. Signals use only bars whose
close time is at or before the decision time; simulated entry is the next M1
bar open. Output is diagnostic research, not a claim of a profitable strategy.

Changes vs v1:
  * --spread-price: fixed spread in price units overriding the Spread
    column (Dukascopy-derived CSVs have Spread = 0, which hides trading costs).
  * Entry only when the next M1 bar opens exactly at the decision time
    (no stale signals executed after a market closure).
  * Exit is time based: the last M1 bar closing at or before entry + horizon,
    skipped only if that price is older than --max-stale-min (market closure).
    Quiet minutes without a bar no longer discard the whole window.
  * --one-position: non-overlapping trades (one position at a time) plus
    profit factor, total net and max drawdown.
  * Vectorised: no per-row Python loops except one-position selection.
  * Inconsistent OHLC bars are dropped and counted instead of aborting.

Expected files: XAUUSD_M1.csv, XAUUSD_M5.csv, XAUUSD_M15.csv,
XAUUSD_H1.csv, XAUUSD_H4.csv.
Expected columns: Time,Open,High,Low,Close,TickVolume,Spread,RealVolume.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

TF_MINUTES = {"M1": 1, "M5": 5, "M15": 15, "H1": 60, "H4": 240}
VOTE_TFS = ["M5", "M15", "H1", "H4"]
REQUIRED = ("Time", "Open", "High", "Low", "Close", "Spread")
ONE_MIN = np.timedelta64(1, "m")


def load_bars(path: Path, tf: str) -> tuple[pd.DataFrame, int]:
    """Load one CSV. Returns (bars, number_of_dropped_inconsistent_bars)."""
    if not path.is_file():
        raise FileNotFoundError(f"Missing required data file: {path}")
    df = pd.read_csv(path)
    df.columns = [str(c).strip() for c in df.columns]
    missing = [c for c in REQUIRED if c not in df.columns]
    if missing:
        raise ValueError(f"{path.name}: missing columns {missing}; found {list(df.columns)}")
    df["Time"] = pd.to_datetime(df["Time"].astype(str).str.strip(),
                                format="%Y.%m.%d %H:%M", errors="coerce")
    if df["Time"].isna().any():
        bad = int(df["Time"].isna().sum())
        raise ValueError(f"{path.name}: {bad} timestamps did not match YYYY.MM.DD HH:MM")
    for col in ("Open", "High", "Low", "Close", "Spread"):
        df[col] = pd.to_numeric(df[col], errors="coerce")
    df = df.dropna(subset=["Open", "High", "Low", "Close", "Spread"])
    df = df.sort_values("Time").drop_duplicates("Time", keep="last").reset_index(drop=True)
    bad_ohlc = (df["High"] < df[["Open", "Close", "Low"]].max(axis=1)) | \
               (df["Low"] > df[["Open", "Close", "High"]].min(axis=1))
    n_bad = int(bad_ohlc.sum())
    if n_bad:
        df = df[~bad_ohlc].reset_index(drop=True)
    if df.empty:
        raise ValueError(f"{path.name}: no valid OHLC rows")
    # MT5 timestamps denote bar open. Signals become available only at bar close.
    df["AvailableAt"] = df["Time"] + pd.to_timedelta(TF_MINUTES[tf], unit="m")
    return df, n_bad


def make_tf_vote(df: pd.DataFrame, tf: str) -> pd.DataFrame:
    close = df["Close"]
    ema = close.ewm(span=20, adjust=False, min_periods=20).mean()
    prior = ema.shift(3)
    vote = np.where((close > ema) & (ema > prior), 1,
                    np.where((close < ema) & (ema < prior), -1, 0))
    return pd.DataFrame({"AvailableAt": df["AvailableAt"], f"vote_{tf}": vote})


def build_signals(bars: dict[str, pd.DataFrame], min_votes: int) -> pd.DataFrame:
    m1 = bars["M1"]
    merged = pd.DataFrame({"DecisionAt": m1["AvailableAt"]})
    for tf in VOTE_TFS:
        feature = make_tf_vote(bars[tf], tf).sort_values("AvailableAt")
        merged = pd.merge_asof(merged, feature, left_on="DecisionAt",
                               right_on="AvailableAt", direction="backward")
        merged = merged.drop(columns=["AvailableAt"])
    votes = merged[[f"vote_{tf}" for tf in VOTE_TFS]].fillna(0).to_numpy(dtype=int)
    merged["bull_votes"] = (votes == 1).sum(axis=1)
    merged["bear_votes"] = (votes == -1).sum(axis=1)
    merged["signal"] = np.where(merged["bull_votes"] >= min_votes, 1,
                                np.where(merged["bear_votes"] >= min_votes, -1, 0))
    return merged


def max_drawdown(net: np.ndarray) -> float:
    if len(net) == 0:
        return 0.0
    equity = np.concatenate(([0.0], np.cumsum(net)))
    return float((np.maximum.accumulate(equity) - equity).max())


def run(args: argparse.Namespace) -> dict:
    root = Path(args.data_dir)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    bars: dict[str, pd.DataFrame] = {}
    dropped: dict[str, int] = {}
    for tf in TF_MINUTES:
        bars[tf], dropped[tf] = load_bars(root / f"XAUUSD_{tf}.csv", tf)

    warnings: list[str] = []
    if args.spread_price is not None:
        sp_points = args.spread_price / args.point
        for df in bars.values():
            df["Spread"] = sp_points
        spread_note = f"fixed spread {args.spread_price} price units ({sp_points:g} points) overrides Spread column"
    else:
        spread_note = "Spread column from CSV (points)"
        if (bars["M1"]["Spread"] == 0).all():
            msg = ("Spread column is all zero: trading costs are NOT modelled. "
                   "Pass --spread-price (e.g. 0.25) for realistic results.")
            warnings.append(msg)
            print("WARNING: " + msg, file=sys.stderr)
    if any(dropped.values()):
        warnings.append(f"Dropped inconsistent OHLC bars: {dropped}")

    merged = build_signals(bars, args.min_votes)
    m1 = bars["M1"]
    n = len(m1)

    t_open = m1["Time"].to_numpy(dtype="datetime64[ns]")
    decision = merged["DecisionAt"].to_numpy(dtype="datetime64[ns]")
    open_ = m1["Open"].to_numpy(dtype=float)
    close_ = m1["Close"].to_numpy(dtype=float)
    spread_pts = m1["Spread"].to_numpy(dtype=float)
    signal = merged["signal"].to_numpy(dtype=int)
    bull = merged["bull_votes"].to_numpy(dtype=int)
    bear = merged["bear_votes"].to_numpy(dtype=int)
    last_close = t_open[-1] + ONE_MIN
    stale = np.timedelta64(int(args.max_stale_min), "m")

    # Decision on bar i (closed at decision[i]); entry on bar i+1, and only if
    # that bar opens exactly at the decision time (contiguous, no market gap).
    contiguous = t_open[1:] == decision[:-1]
    cand = np.flatnonzero((signal[:-1] != 0) & contiguous)
    ei = cand + 1
    sig = signal[cand]
    entry_t = t_open[ei]

    summaries = []
    all_trades = []
    for horizon in args.horizons:
        target = entry_t + np.timedelta64(int(horizon), "m")
        # Last M1 bar whose close time (open + 1 min) is <= target.
        xi = np.searchsorted(t_open, target - ONE_MIN, side="right") - 1
        safe_xi = np.clip(xi, 0, n - 1)
        close_t = t_open[safe_xi] + ONE_MIN
        valid = (target <= last_close) & ((target - close_t) <= stale) & (xi >= ei) & (xi >= 0)
        idx = np.flatnonzero(valid)
        skipped = int(len(cand) - len(idx))

        if args.one_position and len(idx):
            ent_ns = entry_t[idx].astype("int64")
            tgt_ns = target[idx].astype("int64")
            keep = []
            i = 0
            m = len(idx)
            while i < m:
                keep.append(i)
                i = int(np.searchsorted(ent_ns, tgt_ns[i], side="left"))
            idx = idx[np.array(keep, dtype=int)]

        if len(idx) == 0:
            summaries.append({"horizon_minutes": horizon, "signals": 0,
                              "candidates_skipped_gap_or_end": skipped})
            continue

        e_idx = ei[idx]
        x_idx = xi[idx]
        s = sig[idx]
        entry = open_[e_idx]
        exit_bid = close_[x_idx]
        entry_spread = np.maximum(spread_pts[e_idx], 0.0) * args.point
        exit_spread = np.maximum(spread_pts[x_idx], 0.0) * args.point
        gross = s * (exit_bid - entry)
        # Buy enters ask / exits bid; sell enters bid / exits ask (OHLC are bid).
        cost = np.where(s > 0, entry_spread, exit_spread)
        net = gross - cost

        gains = float(net[net > 0].sum())
        losses = float(-net[net < 0].sum())
        item = {
            "horizon_minutes": horizon,
            "signals": int(len(idx)),
            "buy_signals": int((s == 1).sum()),
            "sell_signals": int((s == -1).sum()),
            "candidates_skipped_gap_or_end": skipped,
            "coverage_pct_of_m1_decisions": round(100 * len(idx) / max(1, n), 4),
            "gross_win_rate_pct": round(100 * float((gross > 0).mean()), 4),
            "net_win_rate_pct": round(100 * float((net > 0).mean()), 4),
            "mean_gross_move_price": float(gross.mean()),
            "mean_estimated_spread_cost_price": float(cost.mean()),
            "mean_net_move_price": float(net.mean()),
            "median_net_move_price": float(np.median(net)),
            "profit_factor_net": (gains / losses) if losses > 0 else None,
        }
        if args.one_position:
            item["total_net_price"] = float(net.sum())
            item["max_drawdown_price"] = max_drawdown(net)
        summaries.append(item)

        if args.save_trades:
            all_trades.append(pd.DataFrame({
                "horizon_minutes": horizon,
                "decision_time": decision[cand[idx]],
                "entry_time": entry_t[idx],
                "exit_time": target[idx],
                "signal": s,
                "bull_votes": bull[cand[idx]],
                "bear_votes": bear[cand[idx]],
                "entry_open_bid": entry,
                "exit_close_bid": exit_bid,
                "gross_move_price": gross,
                "spread_cost_price": cost,
                "net_move_price": net,
            }))

    summary = {
        "research_only": True,
        "strategy": "EMA20 trend consensus across closed M5/M15/H1/H4 bars; signal if at least min_votes TFs agree",
        "mode": "one_position (non-overlapping trades)" if args.one_position else "overlapping observations (every M1 signal)",
        "data_dir": str(root),
        "symbol": "XAUUSD",
        "point_price_unit": args.point,
        "spread_assumption": spread_note + "; OHLC treated as bid; spread charged once at entry for buys or exit for sells",
        "max_stale_min": args.max_stale_min,
        "min_votes": args.min_votes,
        "warnings": warnings,
        "input_rows": {tf: int(len(df)) for tf, df in bars.items()},
        "input_start": {tf: str(df["Time"].iloc[0]) for tf, df in bars.items()},
        "input_end": {tf: str(df["Time"].iloc[-1]) for tf, df in bars.items()},
        "results": summaries,
        "limitations": [
            "This is a simple research proxy, not a replay of GoldPro SMC structure/POI/liquidity modules.",
            "No commission, slippage, swaps, order rejection, or intrabar execution modeling.",
            "Fixed (or CSV) spread only; real spread widens at news/rollover.",
            "Session-based features are not included.",
            "Windows that cross a market closure (price older than max_stale_min) are excluded.",
            "In overlapping mode observations are not independent trades; use --one-position.",
        ],
    }
    if all_trades:
        pd.concat(all_trades, ignore_index=True).to_csv(out_dir / "trades.csv", index=False)
    pd.DataFrame(summaries).to_csv(out_dir / "summary.csv", index=False)
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data-dir", required=True, help="Folder containing XAUUSD_M1.csv etc.")
    parser.add_argument("--out-dir", default=r"D:\GoldProResearch\results")
    parser.add_argument("--point", type=float, required=True,
                        help="Price value of one MT5 point, e.g. 0.001 for 3-digit data, 0.01 for 2-digit")
    parser.add_argument("--spread-price", type=float, default=None,
                        help="Fixed spread in price units (USD), e.g. 0.25; overrides the Spread column")
    parser.add_argument("--horizons", type=int, nargs="+", default=[15, 30, 60])
    parser.add_argument("--min-votes", type=int, choices=[3, 4], default=3)
    parser.add_argument("--one-position", action="store_true",
                        help="Non-overlapping trades: ignore signals while a position is open")
    parser.add_argument("--max-stale-min", type=int, default=5,
                        help="Max minutes between exit target and the last available M1 close (default 5)")
    parser.add_argument("--save-trades", action="store_true",
                        help="Write trades.csv (can be huge without --one-position)")
    args = parser.parse_args()
    if args.point <= 0 or any(h <= 0 for h in args.horizons):
        parser.error("--point and horizons must be positive")
    if args.spread_price is not None and args.spread_price < 0:
        parser.error("--spread-price must be >= 0")
    if args.max_stale_min < 0:
        parser.error("--max-stale-min must be >= 0")
    try:
        result = run(args)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    print("\nRESEARCH BASELINE COMPLETE (not GoldPro production/strategy validation)")
    print("Mode:", result["mode"])
    for item in result["results"]:
        print(item)
    print(f"\nOutputs: {args.out_dir}")
    print("Review summary.json limitations before interpreting results.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
