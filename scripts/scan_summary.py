#!/usr/bin/env python3
"""Collapse every scanner's report into one small JSON the app shows on its dashboard.

Also used as a gate:  scan_summary.py --gate zap   -> exit 1 if ZAP found any High-risk alert.
"""
import argparse
import json
import pathlib
import sys
from collections import Counter


def load(path):
    try:
        return json.loads(pathlib.Path(path).read_text())
    except (OSError, ValueError):
        return None


def gitleaks(d):
    return {"leaks": len(load(d / "gitleaks.json") or [])}


def tfsec(d):
    data = load(d / "tfsec.json") or {}
    sev = Counter(r.get("severity", "").upper() for r in data.get("results") or [])
    return sev


def checkov(d):
    data = load(d / "results_json.json")
    if data is None:
        return 0
    runs = data if isinstance(data, list) else [data]
    return sum(r.get("summary", {}).get("failed", 0) for r in runs)


def trivy(d):
    data = load(d / "trivy-image.json") or {}
    sev = Counter()
    for res in data.get("Results") or []:
        for v in res.get("Vulnerabilities") or []:
            sev[v.get("Severity", "UNKNOWN")] += 1
    return {k: sev.get(k, 0) for k in ("CRITICAL", "HIGH", "MEDIUM", "LOW")}


def zap(d):
    data = load(d / "zap.json") or {}
    risk = Counter()
    for site in data.get("site") or []:
        for a in site.get("alerts") or []:
            risk[{"3": "high", "2": "medium", "1": "low"}.get(str(a.get("riskcode")), "info")] += 1
    return {k: risk.get(k, 0) for k in ("high", "medium", "low", "info")}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--reports", default="reports")
    p.add_argument("--build", default="local")
    p.add_argument("--commit", default="")
    p.add_argument("--sonar", default="UNKNOWN", help="Quality Gate status from Jenkins")
    p.add_argument("--out")
    p.add_argument("--gate", choices=["zap"])
    a = p.parse_args()
    d = pathlib.Path(a.reports)

    if a.gate == "zap":
        z = zap(d)
        print(f"ZAP alerts: {z}")
        if z["high"] > 0:
            print("FAIL: ZAP found High-risk alerts", file=sys.stderr)
            return 1
        return 0

    tf = tfsec(d)
    summary = {
        "source": "pipeline",
        "build": a.build,
        "commit": a.commit[:12],
        "gitleaks": gitleaks(d),
        "sonar": {"qualityGate": a.sonar},
        "iac": {
            "failedHighCritical": tf.get("HIGH", 0) + tf.get("CRITICAL", 0),
            "tfsecMediumLow": tf.get("MEDIUM", 0) + tf.get("LOW", 0),
            "checkovFailed": checkov(d),
        },
        "trivy": trivy(d),
        "zap": zap(d),
    }
    text = json.dumps(summary, indent=2)
    if a.out:
        pathlib.Path(a.out).write_text(text)
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
