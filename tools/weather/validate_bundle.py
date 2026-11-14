"""Check a weather-data bundle and print a report (Python 3 standard library only).

    py -I tools/weather/validate_bundle.py                    # the shipped bundle and the test fixture
    py -I tools/weather/validate_bundle.py path/to/bundle ...  # any bundle directories

Checks: every manifest field and its type, sha256 and byte size of every file, units in the allowed set, CSV header
equal to the declared columns, every cell a number, missing values, the time column strictly increasing and never
missing, plausible ranges, episodes (fields, curve length, peak, product references) and refresh entries.
Exit code 0 only when every bundle passes.
"""
from __future__ import annotations

import hashlib
import json
import math
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DIRS = [ROOT / "data" / "weather" / "bundle", ROOT / "tests" / "fixtures" / "weather_bundle_min"]

FORMAT = "mars_colony_weather_bundle"
ALLOWED_UNITS = {"Pa", "K", "m/s", "deg", "1"}
KINDS = {"pressure", "air_temperature", "wind", "dust_opacity", "humidity", "ground_temperature", "radiation"}
PRODUCT_FIELDS = {
    "id": str, "kind": str, "file": str, "sha256": str, "bytes": int, "source_id": str, "pds_lid": str, "version": str,
    "mission": str, "instrument": str, "site": str, "lat": (int, float), "lon": (int, float),
    "observation_start_utc": str, "observation_end_utc": str, "sol_start": int, "sol_end": int,
    "ls_start": (int, float), "ls_end": (int, float), "columns": dict, "units_ok": list, "missing_value": (int, float),
    "quality": str, "license": str, "source_url": str, "etag": str, "last_modified": str, "retrieved_utc": str,
    "transform": list,
}
EPISODE_FIELDS = {
    "id": str, "source_product_ids": list, "observed": str, "duration_sols": (int, float), "peak_tau": (int, float),
    "tau_curve": list, "wind_ms_mean": (int, float), "solar_factor_at_peak": (int, float), "notes": str,
}
# Plausible values per unit (and for some dimensionless columns by name).
RANGES_BY_UNIT = {"Pa": (100.0, 1500.0), "K": (100.0, 350.0), "m/s": (0.0, 100.0), "deg": (-360.0, 360.0)}
RANGES_BY_NAME = {"tau": (0.0, 20.0), "tau_vis": (0.0, 20.0), "cdod610": (0.0, 10.0), "cdodtot": (0.0, 10.0),
                  "reliability": (0.0, 1.0), "samples": (0.0, 100000.0), "ls": (0.0, 360.0), "wind_dir": (0.0, 360.0)}


def is_type(value, t) -> bool:
    if isinstance(value, bool):
        return False
    if t is int or t == (int,):
        return isinstance(value, int)
    return isinstance(value, t)


def parse_utc(text: str):
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None


class Report:
    def __init__(self, name: str):
        self.name = name
        self.problems: list[str] = []
        self.lines: list[str] = []

    def bad(self, text: str) -> None:
        self.problems.append(text)

    def info(self, text: str) -> None:
        self.lines.append(text)


def check_csv(rep: Report, path: Path, p: dict) -> None:
    text = path.read_text(encoding="ascii")
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]
    header = lines[0].split(",")
    columns = p["columns"]
    if header != list(columns.keys()):
        rep.bad("%s: header %s differs from columns %s" % (p["id"], header, list(columns.keys())))
        return
    tcol = p.get("time_column", header[0])
    if tcol not in header:
        rep.bad("%s: time column %s not in header" % (p["id"], tcol))
        return
    ti = header.index(tcol)
    missing = float(p["missing_value"])
    stats = {c: {"n": 0, "missing": 0, "min": math.inf, "max": -math.inf} for c in header}
    last_t = -math.inf
    for n, line in enumerate(lines[1:], start=2):
        cells = line.split(",")
        if len(cells) != len(header):
            rep.bad("%s line %d: %d cells, expected %d" % (p["id"], n, len(cells), len(header)))
            continue
        for c, cell in zip(header, cells):
            try:
                v = float(cell)
            except ValueError:
                rep.bad("%s line %d: '%s' in %s is not a number" % (p["id"], n, cell, c))
                continue
            if not math.isfinite(v):
                rep.bad("%s line %d: %s is not finite" % (p["id"], n, c))
                continue
            st = stats[c]
            st["n"] += 1
            if v == missing:
                st["missing"] += 1
                if c == tcol:
                    rep.bad("%s line %d: time is missing" % (p["id"], n))
                continue
            st["min"] = min(st["min"], v)
            st["max"] = max(st["max"], v)
            lo_hi = RANGES_BY_NAME.get(c) or RANGES_BY_UNIT.get(columns[c])
            if lo_hi and not (lo_hi[0] <= v <= lo_hi[1]):
                rep.bad("%s line %d: %s = %g outside the plausible range %s" % (p["id"], n, c, v, lo_hi))
        try:
            t = float(cells[ti])
        except ValueError:
            continue
        if t <= last_t:
            rep.bad("%s line %d: time %s does not increase" % (p["id"], n, cells[ti]))
        last_t = t
    rows = len(lines) - 1
    if rows < 2:
        rep.bad("%s: fewer than 2 rows" % p["id"])
    t_lo, t_hi = stats[tcol]["min"], stats[tcol]["max"]
    if not (p["sol_start"] - 1 <= t_lo and t_hi <= p["sol_end"] + 1):
        rep.bad("%s: time column %g..%g outside sol_start..sol_end %d..%d" % (p["id"], t_lo, t_hi, p["sol_start"], p["sol_end"]))
    parts = []
    for c in header:
        st = stats[c]
        rng = "%g..%g" % (st["min"], st["max"]) if st["min"] <= st["max"] else "-"
        parts.append("%s[%s] %s missing %d" % (c, columns[c], rng, st["missing"]))
    rep.info("  %-18s %-15s %4d rows  %s" % (p["id"], p["kind"], rows, "; ".join(parts)))


def validate(directory: Path) -> Report:
    rep = Report(str(directory))
    mpath = directory / "manifest.json"
    if not mpath.exists():
        rep.bad("no manifest.json")
        return rep
    try:
        m = json.loads(mpath.read_text(encoding="utf-8"))
    except ValueError as e:
        rep.bad("manifest.json is not JSON: %s" % e)
        return rep
    if m.get("format") != FORMAT:
        rep.bad("format is %r" % m.get("format"))
    if m.get("schema") != 1:
        rep.bad("schema is %r" % m.get("schema"))
    for f, t in (("bundle_id", str), ("built_utc", str), ("products", list), ("episodes_file", str),
                 ("episodes_sha256", str), ("refresh", list)):
        if not is_type(m.get(f), t):
            rep.bad("manifest field %s missing or not %s" % (f, t.__name__))
    if rep.problems:
        return rep
    if parse_utc(m["built_utc"]) is None:
        rep.bad("built_utc is not an ISO time")
    rep.info("bundle %s (version %s), built %s, %d products" % (m["bundle_id"], m.get("version", "?"), m["built_utc"],
                                                               len(m["products"])))
    ids = set()
    for p in m["products"]:
        pid = p.get("id", "?")
        bad_fields = [f for f, t in PRODUCT_FIELDS.items() if not is_type(p.get(f), t)]
        if bad_fields:
            rep.bad("%s: fields missing or of the wrong type: %s" % (pid, ", ".join(bad_fields)))
            continue
        if pid in ids:
            rep.bad("duplicate product id " + pid)
        ids.add(pid)
        if p["kind"] not in KINDS:
            rep.bad("%s: unknown kind %s" % (pid, p["kind"]))
        if not set(p["units_ok"]) <= ALLOWED_UNITS:
            rep.bad("%s: units_ok %s goes beyond %s" % (pid, p["units_ok"], sorted(ALLOWED_UNITS)))
        for c, u in p["columns"].items():
            if u not in p["units_ok"] or u not in ALLOWED_UNITS:
                rep.bad("%s: column %s has unit %r, not in the allowed set" % (pid, c, u))
        if not (-90 <= p["lat"] <= 90 and -180 <= p["lon"] <= 360):
            rep.bad("%s: lat/lon out of range" % pid)
        if not (0 <= p["ls_start"] < 360 and 0 <= p["ls_end"] < 360):
            rep.bad("%s: Ls out of range" % pid)
        t0, t1 = parse_utc(p["observation_start_utc"]), parse_utc(p["observation_end_utc"])
        if t0 is None or t1 is None or t0 > t1:
            rep.bad("%s: observation times missing or reversed" % pid)
        if parse_utc(p["retrieved_utc"]) is None:
            rep.bad("%s: retrieved_utc is not an ISO time" % pid)
        if p["sol_start"] > p["sol_end"]:
            rep.bad("%s: sol_start after sol_end" % pid)
        if not p["source_url"].startswith("https://"):
            rep.bad("%s: source_url is not https" % pid)
        if not p["transform"] or not all(isinstance(s, str) and s for s in p["transform"]):
            rep.bad("%s: transform must list the steps" % pid)
        path = directory / p["file"]
        if "/" in p["file"] or "\\" in p["file"] or not path.exists():
            rep.bad("%s: file %s missing or not a plain file name" % (pid, p["file"]))
            continue
        data = path.read_bytes()
        if len(data) != p["bytes"]:
            rep.bad("%s: %d bytes, manifest says %d" % (pid, len(data), p["bytes"]))
        if hashlib.sha256(data).hexdigest() != p["sha256"]:
            rep.bad("%s: sha256 differs" % pid)
        check_csv(rep, path, p)
    epath = directory / m["episodes_file"]
    if not epath.exists():
        rep.bad("episodes file missing")
        return rep
    edata = epath.read_bytes()
    if hashlib.sha256(edata).hexdigest() != m["episodes_sha256"]:
        rep.bad("episodes sha256 differs")
    e = json.loads(edata.decode("utf-8"))
    step = float(e.get("curve_step_sol", 0.25))
    eps = e.get("episodes", [])
    if not isinstance(eps, list) or not eps:
        rep.bad("no episodes")
        eps = []
    missing_values = {float(p["missing_value"]) for p in m["products"] if "missing_value" in p}
    eids = set()
    for ep in eps:
        eid = ep.get("id", "?")
        bad_fields = [f for f, t in EPISODE_FIELDS.items() if not is_type(ep.get(f), t)]
        if bad_fields:
            rep.bad("episode %s: fields missing or of the wrong type: %s" % (eid, ", ".join(bad_fields)))
            continue
        if eid in eids:
            rep.bad("duplicate episode id " + eid)
        eids.add(eid)
        unknown = [x for x in ep["source_product_ids"] if x not in ids]
        if unknown or not ep["source_product_ids"]:
            rep.bad("episode %s: unknown or no source products %s" % (eid, unknown))
        curve = ep["tau_curve"]
        want = int(round(ep["duration_sols"] / step)) + 1
        if len(curve) != want:
            rep.bad("episode %s: %d curve points, expected %d" % (eid, len(curve), want))
        if not all(isinstance(x, (int, float)) and math.isfinite(x) and 0 <= x <= 20 for x in curve):
            rep.bad("episode %s: curve values out of range" % eid)
        elif abs(max(curve) - ep["peak_tau"]) > 1e-3:
            rep.bad("episode %s: peak_tau %g is not the curve maximum %g" % (eid, ep["peak_tau"], max(curve)))
        if ep["wind_ms_mean"] not in missing_values and not (0 <= ep["wind_ms_mean"] <= 60):
            rep.bad("episode %s: wind_ms_mean %g implausible" % (eid, ep["wind_ms_mean"]))
        if not (0 < ep["solar_factor_at_peak"] <= 1.5):
            rep.bad("episode %s: solar_factor_at_peak %g implausible" % (eid, ep["solar_factor_at_peak"]))
        rep.info("  episode %-20s %5.1f sols  peak %.2f  wind %s  %s" % (eid, ep["duration_sols"], ep["peak_tau"],
                 "not measured" if ep["wind_ms_mean"] in missing_values else "%.2f m/s" % ep["wind_ms_mean"], ep["observed"]))
    bg = e.get("background", {}).get("tau_by_ls")
    if not isinstance(bg, list) or len(bg) < 2:
        rep.bad("background.tau_by_ls missing")
    else:
        last = -1.0
        for pair in bg:
            if not (isinstance(pair, list) and len(pair) == 2 and all(isinstance(x, (int, float)) for x in pair)):
                rep.bad("background pair %r malformed" % (pair,))
                break
            if pair[0] <= last or not (0 <= pair[0] <= 360) or not (0 <= pair[1] <= 20):
                rep.bad("background pair %r out of order or range" % (pair,))
                break
            last = pair[0]
        rep.info("  background: %d points, Ls %g..%g, tau %g..%g" % (len(bg), bg[0][0], bg[-1][0],
                 min(x[1] for x in bg), max(x[1] for x in bg)))
    for r in m["refresh"]:
        if r.get("product_id") not in ids:
            rep.bad("refresh entry for unknown product %r" % r.get("product_id"))
        if not str(r.get("url", "")).startswith("https://"):
            rep.bad("refresh url not https: %r" % r.get("url"))
        if not (is_type(r.get("max_bytes"), int) and r["max_bytes"] > 0):
            rep.bad("refresh max_bytes must be a positive integer")
        if not (isinstance(r.get("timeout_s"), (int, float)) and r["timeout_s"] > 0):
            rep.bad("refresh timeout_s must be positive")
    rep.info("  %d refresh entries" % len(m["refresh"]))
    return rep


def main(argv: list[str]) -> int:
    dirs = [Path(a) for a in argv] if argv else DEFAULT_DIRS
    ok = True
    for d in dirs:
        rep = validate(d)
        print("== " + rep.name)
        for line in rep.lines:
            print(line)
        if rep.problems:
            ok = False
            print("INVALID: %d problem(s)" % len(rep.problems))
            for p in rep.problems[:50]:
                print("  - " + p)
        else:
            print("VALID")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
