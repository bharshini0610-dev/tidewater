"""Replay the settle alert rules against Grafana CSV exports (Task E4).

Grafana "Export CSV" gives a Time column plus one column per series. Point each alert at
the CSV/column that holds its signal; the script prints the first minute the condition held
for the alert's `for` duration.

  python scripts/replay_alerts.py \
     --csv error_ratio=incident-2026-08-14/grafana/api_5xx_ratio.csv \
     --csv restarts=incident-2026-08-14/grafana/pod_restarts.csv \
     --csv pg_conn_ratio=incident-2026-08-14/grafana/pg_connections.csv \
     --detected "2026-08-15 09:30"

Column is the first numeric column unless given as name=path:column. Values are summed across
columns when the series is split per pod (restarts).
"""

import argparse
import csv
from datetime import datetime, timedelta

RULES = {
    # name: (signal, comparison, threshold, for_minutes, description)
    "SettleApiErrorBudgetBurn": ("error_ratio", ">", 0.072, 2, "5xx/slow ratio > 14.4x budget"),
    "SettlePodsRestarting": ("restarts_10m", ">", 2, 1, "restarts in 10 min > 2"),
    "SettlePostgresConnectionsHigh": ("pg_conn_ratio", ">", 0.8, 2, "connections > 80% of max"),
    "SettleDuplicatePayout": ("duplicates", ">", 0, 0, "duplicate payouts > 0"),
    "SettleSettlementsStale": ("oldest_job_age", ">", 900, 5, "oldest job > 15 min"),
}


def parse_time(s: str) -> datetime:
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%dT%H:%M:%SZ"):
        try:
            return datetime.strptime(s.strip(), fmt)
        except ValueError:
            pass
    return datetime.fromtimestamp(float(s) / (1000 if float(s) > 1e11 else 1))


def load(spec: str) -> tuple[str, list[tuple[datetime, float]]]:
    name, _, rest = spec.partition("=")
    path, _, col = rest.partition(":")
    rows = list(csv.DictReader(open(path, newline="")))
    tcol = next(k for k in rows[0] if k.lower() in ("time", "timestamp", "date"))
    cols = [col] if col else [k for k in rows[0] if k != tcol]
    out = []
    for r in rows:
        vals = [float(r[c]) for c in cols if r.get(c) not in (None, "", "null", "NaN")]
        if vals:
            out.append((parse_time(r[tcol]), sum(vals)))
    return name, sorted(out)


def restarts_window(series, minutes=10):
    """Turn a cumulative restart counter into increase over the last N minutes."""
    out = []
    for t, v in series:
        past = [pv for pt, pv in series if t - timedelta(minutes=minutes) <= pt <= t]
        out.append((t, v - min(past)))
    return out


def first_firing(series, op, thr, for_min):
    start = None
    for t, v in series:
        ok = v > thr if op == ">" else v < thr
        if ok:
            start = start or t
            if t - start >= timedelta(minutes=for_min):
                return t
        else:
            start = None
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", action="append", default=[], help="signal=path[:column]")
    ap.add_argument("--detected", help="actual detection time (YYYY-mm-dd HH:MM)")
    a = ap.parse_args()
    signals = dict(load(s) for s in a.csv)
    if "restarts" in signals:
        signals["restarts_10m"] = restarts_window(signals["restarts"])
    detected = parse_time(a.detected) if a.detected else None
    print(f"{'alert':32} {'fires at':20} {'earlier than detection':>24}")
    for alert, (sig, op, thr, for_min, desc) in RULES.items():
        if sig not in signals:
            print(f"{alert:32} {'(no data: ' + sig + ')':20}")
            continue
        t = first_firing(signals[sig], op, thr, for_min)
        early = f"{(detected - t).total_seconds() / 60:.0f} min" if (t and detected) else "-"
        print(f"{alert:32} {str(t or 'never'):20} {early:>24}   # {desc}")


if __name__ == "__main__":
    main()
