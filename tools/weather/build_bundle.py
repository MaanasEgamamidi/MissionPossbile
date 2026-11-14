"""Build the game's weather-data bundle from the downloaded archive files (Python 3 standard library only).

    py -I tools/weather/build_bundle.py             # data/weather/raw -> data/weather/bundle (offline)
    py -I tools/weather/build_bundle.py --fixture   # writes tests/fixtures/weather_bundle_min (synthetic test data)

Nothing here goes to the network. The raw files in data/weather/raw were downloaded once (raw/downloads.json lists
every URL, byte count, sha256, ETag, Last-Modified and retrieval time) and are only read here. Rebuilding from the
same raw files gives byte-identical output (built_utc is the time of the newest raw download, not the clock).

Bundle format: SPEC_P09.md "The bundle format" and docs/WEATHER_DATA.md. Every product file is a small CSV with a
header row of column names (the keys of the manifest's "columns"), one row per time step, numbers in the declared
units and MISSING (-999.0) for gaps. The first column (manifest "time_column", always "sol") is the time axis and
strictly increases.
"""
from __future__ import annotations

import csv
import hashlib
import json
import math
import struct
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "data" / "weather" / "raw"
BUNDLE = ROOT / "data" / "weather" / "bundle"
FIXTURE = ROOT / "tests" / "fixtures" / "weather_bundle_min"

FORMAT = "mars_colony_weather_bundle"
SCHEMA = 1
BUNDLE_ID = "jezero-meda-lmd-my36-v1"
BUNDLE_VERSION = "1"
MISSING = -999.0
UNITS_OK = ["Pa", "K", "m/s", "deg", "1"]
CURVE_STEP_SOL = 0.25

# Approximate Perseverance landing-site coordinates as given in SPEC_P09 (planetocentric latitude, east longitude).
# Not read from a downloaded file: rover positions are in MEDA DER_ANCILLARY files, which were not downloaded.
JEZERO_LAT = 18.44
JEZERO_LON = 77.45

# MEDA: bins of 1/144 sol (10 Mars minutes of local mean solar time).
BINS_PER_SOL = 144
MEDA_INVALID = 1.0e8          # readme: "may be set to an invalid value (9999999999)"; files use 999999999
ATS_RSM_COLUMNS = ["ATS_LOCAL_TEMP1", "ATS_LOCAL_TEMP2", "ATS_LOCAL_TEMP3"]

# LMD dust scenario: visible-equivalent optical depth = 2.6 x 9.3 um absorption CDOD (LMD dust climatology page,
# "Important notes"). Episodes: excess over the seasonal background.
VIS_PER_IR_ABS = 2.6
EPISODE_THRESHOLD = 0.35      # visible tau above the background that opens an episode
EPISODE_EDGE = 0.175          # an episode extends while the excess stays at or above this
EPISODE_MERGE_GAP_SOLS = 2    # episodes separated by at most this many sols are merged
BACKGROUND_STEP_LS = 10.0
BACKGROUND_HALF_WINDOW_LS = 15.0
BACKGROUND_PERCENTILE = 0.25

# The game's power model (docs/MODEL_P07.md): atmosphere term exp(-0.6 x (tau - 0.5)). Game balance, not measured.
GAME_DUST_TAU_FACTOR = 0.6
GAME_DUST_TAU_DEFAULT = 0.5

MEDA_PRODUCTS = [
    # id, raw file stem, kind, register id
    ("meda_ps_sol0289", "WE__0289___________DER_PS__________________P01", "pressure", "W01"),
    ("meda_ws_sol0289", "WE__0289___________DER_WS__________________P02", "wind", "W02"),
    ("meda_ats_sol0289", "WE__0289___________CAL_ATS_________________P01", "air_temperature", "W03"),
    ("meda_ps_sol0313", "WE__0313___________DER_PS__________________P03", "pressure", "W04"),
    ("meda_ws_sol0313", "WE__0313___________DER_WS__________________P02", "wind", "W05"),
    ("meda_ps_sol0317", "WE__0317___________DER_PS__________________P01", "pressure", "W06"),
    ("meda_ats_sol0317", "WE__0317___________CAL_ATS_________________P01", "air_temperature", "W07"),
    ("meda_ps_sol0579", "WE__0579___________DER_PS__________________P01", "pressure", "W08"),
]
LMD_PRODUCTS = [
    ("lmd_cdod_my35", "lmd_dustscenario_MY35_v2-5", 35, "W09"),
    ("lmd_cdod_my36", "lmd_dustscenario_MY36_v2-5", 36, "W10"),
]
QUIET_SOL = 289

MEDA_LICENSE = ("NASA Planetary Data System archive data (public). The PDS Atmospheres Node MEDA page asks users to cite: "
                "\"J.A. Rodriguez-Manfredi et al. (2021), The Mars Environmental Dynamics Analyzer, MEDA, NASA Planetary "
                "Data System, DOI 10.17189/1522849\". No other licence text was found on the pages read.")
LMD_LICENSE = ("Creative Commons Attribution-ShareAlike 3.0 Unported (the file's 'copyright' attribute and the LMD page: "
               "\"publicly available with open access, under Creative Commons Attribution-ShareAlike 3.0 Unported "
               "License\"). Credit: Montabone et al. (2015, 2020), LMD Mars dust climatology. Changes made: values "
               "interpolated to Jezero and converted as listed in 'transform'.")


# ---------------------------------------------------------------- small helpers

def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fmt(value, decimals: int) -> str:
    """A number for a CSV cell; MISSING for None/NaN."""
    if value is None or (isinstance(value, float) and (math.isnan(value) or math.isinf(value))):
        return "%.1f" % MISSING
    return ("%." + str(decimals) + "f") % value


def write_csv(path: Path, header: list[str], rows: list[list[str]]) -> bytes:
    """Writes header + rows with '\n' line endings; returns the bytes written. Also writes the Godot import file that
    keeps the CSV as a plain file (Godot would otherwise import every .csv as a translation table)."""
    lines = [",".join(header)] + [",".join(r) for r in rows]
    data = ("\n".join(lines) + "\n").encode("ascii")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    write_keep_import(path)
    return data


def write_keep_import(path: Path) -> None:
    """<file>.import with importer "keep": Godot exports the file as is and makes no translation resource."""
    (path.parent / (path.name + ".import")).write_text('[remap]\n\nimporter="keep"\n', encoding="ascii")
    for stale in path.parent.glob(path.stem + ".*.translation"):
        stale.unlink()


def write_json(path: Path, obj: object) -> bytes:
    data = (json.dumps(obj, indent=1, ensure_ascii=False) + "\n").encode("utf-8")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return data


def mjd_to_iso(mjd: float) -> str:
    t = datetime(1858, 11, 17, tzinfo=timezone.utc) + timedelta(days=mjd)
    return t.replace(microsecond=0).isoformat().replace("+00:00", "Z")


def mjd_to_date(mjd: float) -> str:
    return mjd_to_iso(mjd)[:10]


def percentile(values: list[float], q: float) -> float:
    xs = sorted(values)
    k = (len(xs) - 1) * q
    f = int(math.floor(k))
    c = min(f + 1, len(xs) - 1)
    return xs[f] + (xs[c] - xs[f]) * (k - f)


def mean(values: list[float]):
    return sum(values) / len(values) if values else None


class BuildError(Exception):
    pass


# ---------------------------------------------------------------- raw file register

def load_downloads() -> dict:
    doc = json.loads((RAW / "downloads.json").read_text(encoding="utf-8"))
    by_file = {}
    for entry in doc["files"]:
        path = RAW / entry["file"]
        data = path.read_bytes()
        if len(data) != entry["bytes"] or sha256_bytes(data) != entry["sha256"]:
            raise BuildError("raw file changed since download: " + entry["file"])
        by_file[entry["file"]] = entry
    return by_file


# ---------------------------------------------------------------- MEDA (PDS4 label + CSV)

PDS = "{http://pds.nasa.gov/pds4/pds/v1}"
M2020 = "{http://pds.nasa.gov/pds4/mission/mars2020/v1}"


def read_label(path: Path) -> dict:
    root = ET.parse(path).getroot()

    def text(tag: str) -> str:
        el = root.find(".//" + tag)
        return el.text.strip() if el is not None and el.text else ""

    fields = []
    for fd in root.iter(PDS + "Field_Delimited"):
        unit = fd.find(PDS + "unit")
        fields.append({"name": fd.find(PDS + "name").text.strip(), "unit": unit.text.strip() if unit is not None else ""})
    return {
        "lid": text(PDS + "logical_identifier"), "version": text(PDS + "version_id"), "title": text(PDS + "title"),
        "start_utc": text(PDS + "start_date_time"), "stop_utc": text(PDS + "stop_date_time"),
        "sol_start": int(text(M2020 + "start_sol_number")), "sol_end": int(text(M2020 + "stop_sol_number")),
        "ls_start": float(text(M2020 + "start_solar_longitude")), "ls_end": float(text(M2020 + "stop_solar_longitude")),
        "file_name": text(PDS + "file_name"), "file_size": int(text(PDS + "file_size")),
        "md5": text(PDS + "md5_checksum"), "records": int(text(PDS + "records")),
        "processing_level": text(PDS + "processing_level"), "fields": fields,
    }


def lmst_sol(value: str) -> float:
    """'00289M13:05:06.542' -> 289.5452... (sol + fraction of the local mean solar day)."""
    sol_part, clock = value.strip().split("M")
    h, m, s = clock.split(":")
    return int(sol_part) + (int(h) * 3600 + int(m) * 60 + float(s)) / 86400.0


def number(cell: str):
    """A float from a CSV cell, or None for empty / invalid (>= 1e8) cells."""
    cell = cell.strip()
    if cell == "":
        return None
    try:
        v = float(cell)
    except ValueError:
        return None
    if math.isnan(v) or abs(v) >= MEDA_INVALID:
        return None
    return v


def read_meda(stem: str) -> tuple[dict, list[dict], bytes]:
    label = read_label(RAW / "meda" / (stem + ".xml"))
    data = (RAW / "meda" / (stem + ".CSV")).read_bytes()
    if len(data) != label["file_size"] or hashlib.md5(data).hexdigest() != label["md5"]:
        raise BuildError(stem + ": file does not match the md5_checksum / file_size in its PDS4 label")
    if label["file_name"] != stem + ".CSV":
        raise BuildError(stem + ": label names another file " + label["file_name"])
    rows = list(csv.DictReader(data.decode("ascii").splitlines()))
    names = [f["name"].replace(" ", "_") for f in label["fields"]]  # one label writes "PRESSURE UNCERTAINTY"
    if list(rows[0].keys()) != names:
        raise BuildError(stem + ": CSV header differs from the label fields")
    if len(rows) + 1 != label["records"]:
        raise BuildError(stem + ": record count differs from the label")
    return label, rows, data


def bin_rows(sol: int, samples: list[tuple[float, tuple]]) -> list[list]:
    """samples: (fractional sol, values...) -> one list of value tuples per bin of the sol."""
    bins: list[list] = [[] for _ in range(BINS_PER_SOL)]
    for t, vals in samples:
        k = int(math.floor((t - sol) * BINS_PER_SOL))
        if 0 <= k < BINS_PER_SOL:
            bins[k].append(vals)
    return bins


def bin_time(sol: int, k: int) -> float:
    return sol + (k + 0.5) / BINS_PER_SOL


def build_meda_product(pid: str, stem: str, kind: str, source_id: str, downloads: dict) -> tuple[dict, dict]:
    label, rows, raw = read_meda(stem)
    sol = label["sol_start"]
    stats = {"rows": len(rows), "used": 0, "dropped": {}}

    def drop(reason: str) -> None:
        stats["dropped"][reason] = stats["dropped"].get(reason, 0) + 1

    samples = []
    for r in rows:
        t = lmst_sol(r["LMST"])
        if int(math.floor(t)) != sol:
            drop("LMST outside the file's sol")
            continue
        if kind == "pressure":
            p = number(r["PRESSURE"])
            if p is None:
                drop("empty or invalid PRESSURE")
                continue
            samples.append((t, (p,)))
        elif kind == "wind":
            v = number(r["HORIZONTAL_WIND_SPEED"])
            d = number(r["WIND_DIRECTION"])
            if r["ROVER_STILL"].strip() != "1":
                drop("ROVER_STILL is not 1 (rover moving or flag empty)")
                continue
            if v is None or d is None:
                drop("empty or invalid HORIZONTAL_WIND_SPEED / WIND_DIRECTION")
                continue
            samples.append((t, (v, d)))
        elif kind == "air_temperature":
            temps = [number(r[c]) for c in ATS_RSM_COLUMNS]
            temps = [x for x in temps if x is not None and 100.0 < x < 350.0]
            if len(temps) < 2:
                drop("fewer than two valid RSM air temperature sensors")
                continue
            temps.sort()
            med = temps[len(temps) // 2] if len(temps) % 2 == 1 else 0.5 * (temps[0] + temps[1])
            samples.append((t, (med,)))
        stats["used"] += 1
    bins = bin_rows(sol, samples)
    out_rows = []
    if kind == "pressure":
        header = ["sol", "pressure", "samples"]
        columns = {"sol": "1", "pressure": "Pa", "samples": "1"}
        for k, b in enumerate(bins):
            out_rows.append([fmt(bin_time(sol, k), 5), fmt(mean([x[0] for x in b]), 2), str(len(b))])
    elif kind == "wind":
        header = ["sol", "wind_speed", "wind_speed_max", "wind_dir", "samples"]
        columns = {"sol": "1", "wind_speed": "m/s", "wind_speed_max": "m/s", "wind_dir": "deg", "samples": "1"}
        for k, b in enumerate(bins):
            if b:
                sx = sum(math.sin(math.radians(x[1])) for x in b)
                cx = sum(math.cos(math.radians(x[1])) for x in b)
                direction = math.degrees(math.atan2(sx, cx)) % 360.0 if (sx * sx + cx * cx) > 1e-12 else None
                out_rows.append([fmt(bin_time(sol, k), 5), fmt(mean([x[0] for x in b]), 2),
                                 fmt(max(x[0] for x in b), 2), fmt(direction, 1), str(len(b))])
            else:
                out_rows.append([fmt(bin_time(sol, k), 5), fmt(None, 2), fmt(None, 2), fmt(None, 1), "0"])
    else:
        header = ["sol", "air_temperature", "samples"]
        columns = {"sol": "1", "air_temperature": "K", "samples": "1"}
        for k, b in enumerate(bins):
            out_rows.append([fmt(bin_time(sol, k), 5), fmt(mean([x[0] for x in b]), 2), str(len(b))])
    data = write_csv(BUNDLE / (pid + ".csv"), header, out_rows)
    covered = sum(1 for b in bins if b)
    raw_entry = downloads["meda/" + stem + ".CSV"]
    label_entry = downloads["meda/" + stem + ".xml"]
    instrument = {"pressure": "MEDA PS (Pressure Sensor), derived level",
                  "wind": "MEDA WS (Wind Sensor), derived level",
                  "air_temperature": "MEDA ATS (Air Temperature Sensor), calibrated level"}[kind]
    quality = {
        "pressure": "Derived pressure (the MEDA readme: derived pressure is based on barocap 3; derived is the "
                    "recommended level). Empty or invalid PRESSURE cells skipped. PRESSURE_UNCERTAINTY is empty in this "
                    "file and is not used (its label gives the unit as kelvin). TRANSDUCER (1/2) is not filtered.",
        "wind": "Derived wind (most appropriate boom chosen by the MEDA team, spurious data filtered at this level per the "
                "release notes). Samples kept only when ROVER_STILL = 1 and both HORIZONTAL_WIND_SPEED and "
                "WIND_DIRECTION are present and below the invalid value 999999999. BOTH_BOOMS_USED_FOR_RETRIEVAL is "
                "empty in these files and is not used. Wind before sol 36 and after sol 315 is not in the archive.",
        "air_temperature": "Calibrated ATS (MEDA publishes no derived ATS product). Per 1 Hz sample: median of the three "
                           "mast (RSM) sensors ATS_LOCAL_TEMP1-3 that read between 100 and 350 K, at least two needed. "
                           "The two rover-body (RFB) sensors ATS_LOCAL_TEMP4-5 are not used. The choice of the RSM "
                           "median is this project's processing, not a MEDA-defined quantity.",
    }[kind]
    if kind == "pressure" and sol == 313:
        quality += (" MEDA release notes: on sol 313 a drift-corrected barocap was used from 15:00:05.423 to "
                    "18:44:42.043 LMST.")
    transform = [
        "verified the raw CSV against the PDS4 label (file_size %d bytes, md5 %s, %d records)" % (
            label["file_size"], label["md5"], label["records"]),
        "time: LMST 'sssssMhh:mm:ss.sss' -> fractional sol = sol + seconds of the local mean solar day / 86400",
        "dropped rows: " + (", ".join("%s: %d" % kv for kv in sorted(stats["dropped"].items())) or "none"),
        "binned into %d bins of 1/%d sol (10 Mars minutes); row time = bin centre; value = mean of the kept 1 Hz "
        "samples in the bin; 'samples' = how many; bins with no samples hold %.1f" % (BINS_PER_SOL, BINS_PER_SOL, MISSING),
        "%d of %d bins have data (MEDA measures about 12 h per sol; the readme describes alternating hours)" % (
            covered, BINS_PER_SOL),
    ]
    if kind == "wind":
        transform.append("wind_speed_max = largest kept 1 Hz HORIZONTAL_WIND_SPEED in the bin; wind_dir = direction of "
                         "the mean unit vector of the kept WIND_DIRECTION values (degrees as in the label)")
    product = {
        "id": pid, "kind": kind, "file": pid + ".csv", "sha256": sha256_bytes(data), "bytes": len(data),
        "source_id": source_id, "pds_lid": label["lid"], "version": label["version"], "title": label["title"],
        "mission": "Mars 2020", "instrument": instrument, "processing_level": label["processing_level"],
        "site": "Jezero crater", "lat": JEZERO_LAT, "lon": JEZERO_LON,
        "site_note": "Perseverance rover, Jezero crater. lat/lon are the approximate landing site from SPEC_P09; the "
                     "rover's exact position on this sol is in the MEDA DER_ANCILLARY file, which was not downloaded.",
        "observation_start_utc": label["start_utc"], "observation_end_utc": label["stop_utc"],
        "sol_start": label["sol_start"], "sol_end": label["sol_end"], "sol_basis": "Mars 2020 mission sol",
        "ls_start": label["ls_start"], "ls_end": label["ls_end"],
        "time_column": "sol", "columns": columns, "units_ok": UNITS_OK, "missing_value": MISSING,
        "quality": quality, "license": MEDA_LICENSE,
        "source_url": raw_entry["url"], "source_bytes": raw_entry["bytes"], "source_md5": label["md5"],
        "label_url": label_entry["url"],
        "etag": raw_entry["etag"], "last_modified": raw_entry["last_modified"], "retrieved_utc": raw_entry["retrieved_utc"],
        "transform": transform,
    }
    summary = {"samples": samples, "label": label, "covered_bins": covered}
    return product, summary


# ---------------------------------------------------------------- LMD dust scenario (NetCDF classic, byte ranges)

NC_TYPES = {1: ("b", 1), 2: ("c", 1), 3: ("h", 2), 4: ("i", 4), 5: ("f", 4), 6: ("d", 8)}


def parse_netcdf_header(data: bytes) -> dict:
    """Minimal NetCDF classic (CDF-1/CDF-2) header reader."""
    if data[:3] != b"CDF" or data[3] not in (1, 2):
        raise BuildError("not a NetCDF classic header")
    version = data[3]
    pos = 4

    def i4() -> int:
        nonlocal pos
        v = struct.unpack(">i", data[pos:pos + 4])[0]
        pos += 4
        return v

    def offset() -> int:
        nonlocal pos
        if version == 1:
            return i4()
        v = struct.unpack(">q", data[pos:pos + 8])[0]
        pos += 8
        return v

    def name() -> str:
        nonlocal pos
        n = i4()
        s = data[pos:pos + n].decode("utf-8", "replace")
        pos += (n + 3) // 4 * 4
        return s

    def values(t: int, n: int):
        nonlocal pos
        code, size = NC_TYPES[t]
        raw = data[pos:pos + n * size]
        pos += (n * size + 3) // 4 * 4
        if t == 2:
            return raw.decode("utf-8", "replace").rstrip("\x00")
        return list(struct.unpack(">" + code * n, raw))

    def attributes() -> dict:
        i4()
        out = {}
        for _ in range(i4()):
            nm = name()
            t = i4()
            out[nm] = values(t, i4())
        return out

    numrecs = i4()
    i4()
    dims = [(name(), i4()) for _ in range(i4())]
    gatts = attributes()
    i4()
    variables = {}
    for _ in range(i4()):
        nm = name()
        ids = [i4() for _ in range(i4())]
        atts = attributes()
        t = i4()
        vsize = i4()
        variables[nm] = {"shape": [dims[i][1] for i in ids], "dims": [dims[i][0] for i in ids], "type": t,
                         "vsize": vsize, "begin": offset(), "atts": atts}
    return {"numrecs": numrecs, "dims": dict(dims), "gatts": gatts, "vars": variables}


def read_lmd(stem: str) -> dict:
    head = (RAW / "lmd" / (stem + ".head.bin")).read_bytes()
    blob = (RAW / "lmd" / (stem + ".jezero.bin")).read_bytes()
    index = json.loads((RAW / "lmd" / (stem + ".jezero.json")).read_text(encoding="utf-8"))
    if sha256_bytes(head) != index["head"]["sha256"] or sha256_bytes(blob) != index["ranges_sha256"]:
        raise BuildError(stem + ": raw bytes differ from the range index")
    h = parse_netcdf_header(head)
    v = h["vars"]

    def one_d(nm: str) -> list:
        var = v[nm]
        code, size = NC_TYPES[var["type"]]
        n = var["shape"][0]
        if var["begin"] + n * size > len(head):
            raise BuildError(stem + ": 1-D variable %s is not inside the downloaded header" % nm)
        return list(struct.unpack(">" + code * n, head[var["begin"]:var["begin"] + n * size]))

    lon = one_d("longitude")
    lat = one_d("latitude")
    g = index["grid"]
    i0, j0 = g["i0"], g["j0"]
    if [lon[i0], lon[i0 + 1]] != g["lon"] or [lat[j0], lat[j0 + 1]] != g["lat"]:
        raise BuildError(stem + ": grid indices do not match the file's coordinates")
    if not (lon[i0] <= JEZERO_LON <= lon[i0 + 1] and lat[j0] >= JEZERO_LAT >= lat[j0 + 1]):
        raise BuildError(stem + ": the downloaded cells do not surround Jezero")
    nlon = h["dims"]["longitude"]
    nlat = h["dims"]["latitude"]
    wx = (JEZERO_LON - lon[i0]) / (lon[i0 + 1] - lon[i0])
    wy = (lat[j0] - JEZERO_LAT) / (lat[j0] - lat[j0 + 1])
    cells: dict[str, list] = {}
    pos = 0
    for nm, t, off, length in index["ranges"]:
        var = v[nm]
        expected = var["begin"] + ((t * nlat + j0) * nlon + i0) * 4
        if off != expected or length != (nlon + 2) * 4:
            raise BuildError(stem + ": range for %s t=%d is not the Jezero neighbourhood" % (nm, t))
        f = struct.unpack(">%df" % (length // 4), blob[pos:pos + length])
        pos += length
        corners = [f[0], f[1], f[nlon], f[nlon + 1]]
        if any(not math.isfinite(c) or c < 0.0 for c in corners):
            val = None
        else:
            val = (1 - wy) * ((1 - wx) * corners[0] + wx * corners[1]) + wy * ((1 - wx) * corners[2] + wx * corners[3])
        cells.setdefault(nm, [None] * h["dims"]["Time"])[t] = val
    if pos != len(blob):
        raise BuildError(stem + ": unused bytes in the range file")
    return {"header": h, "index": index, "time": one_d("Time"), "soy": one_d("SOY"), "ls": one_d("Ls"),
            "min_mjd": one_d("minMJD"), "max_mjd": one_d("maxMJD"), "ave_mjd": one_d("aveMJD"),
            "cdod610": cells["cdod610"], "cdodtot": cells["cdodtot"], "rel": cells["cdodrel"],
            "weights": (wx, wy), "grid": g}


def build_lmd_product(pid: str, stem: str, mars_year: int, source_id: str, downloads: dict) -> tuple[dict, dict]:
    d = read_lmd(stem)
    tau = [None if c is None else VIS_PER_IR_ABS * c for c in d["cdodtot"]]
    rows = []
    for k in range(len(d["time"])):
        rows.append([fmt(d["time"][k], 1), fmt(d["ls"][k], 3), fmt(d["cdod610"][k], 4), fmt(d["cdodtot"][k], 4),
                     fmt(tau[k], 4), fmt(d["rel"][k], 3)])
    header = ["sol", "ls", "cdod610", "cdodtot", "tau_vis", "reliability"]
    data = write_csv(BUNDLE / (pid + ".csv"), header, rows)
    gatts = d["header"]["gatts"]
    entry = downloads["lmd/" + stem + ".head.bin"]
    wx, wy = d["weights"]
    g = d["grid"]
    product = {
        "id": pid, "kind": "dust_opacity", "file": pid + ".csv", "sha256": sha256_bytes(data), "bytes": len(data),
        "source_id": source_id,
        "pds_lid": "none (not a PDS product: LMD Mars dust climatology research archive)",
        "dataset_id": stem.replace("lmd_", "") + ".nc", "version": str(gatts.get("version", "")).replace("-", "."),
        "file_creation_date": gatts.get("creation_date", ""),
        "title": "Martian dust scenario MY%d (kriged daily maps of column dust optical depth), Montabone et al." % mars_year,
        "mission": "Mars Reconnaissance Orbiter (Mars Climate Sounder v5.2 retrievals, gridded and kriged at LMD)",
        "instrument": "MRO MCS column dust optical depth, LMD dust climatology v%s (Montabone et al. 2015, 2020)" %
                      str(gatts.get("version", "")).replace("-", "."),
        "site": "Jezero crater", "lat": JEZERO_LAT, "lon": JEZERO_LON,
        "site_note": "bilinear interpolation of the four 3 x 3 degree grid cells at %s N x %s E around the landing site"
                     % (g["lat"], g["lon"]),
        "observation_start_utc": mjd_to_iso(d["min_mjd"][0]), "observation_end_utc": mjd_to_iso(d["max_mjd"][-1]),
        "sol_start": int(d["soy"][0]), "sol_end": int(d["soy"][-1]), "sol_basis": "sol of Mars year %d (LMD calendar, "
                     "Montabone et al. 2015 appendix A); column 'sol' is the file's fractional Time" % mars_year,
        "mars_year": mars_year,
        "ls_start": round(d["ls"][0], 3), "ls_end": round(d["ls"][-1], 3),
        "time_column": "sol",
        "columns": {"sol": "1", "ls": "deg", "cdod610": "1", "cdodtot": "1", "tau_vis": "1", "reliability": "1"},
        "units_ok": UNITS_OK, "missing_value": MISSING,
        "quality": "Kriged (complete-coverage) maps, one per sol. 'reliability' is the file's cdodrel (kriged "
                   "reliability of the grid point). No values were dropped; a grid value that is not finite or below "
                   "zero would be written as %.1f (none occurred)." % MISSING,
        "license": LMD_LICENSE,
        "source_url": entry["url"], "source_bytes": entry["source_total_bytes"],
        "etag": entry["etag"], "last_modified": entry["last_modified"], "retrieved_utc": entry["retrieved_utc"],
        "transform": [
            "downloaded by HTTP byte ranges: the NetCDF header with all 1-D variables (%d bytes) and, for each of the "
            "%d maps and for cdodrel, cdod610 and cdodtot, the %d bytes from grid cell (lat %s, lon %s) to "
            "(lat %s, lon %s); the full file is %d bytes" % (
                len((RAW / "lmd" / (stem + ".head.bin")).read_bytes()), len(d["time"]), g["span_bytes"],
                g["lat"][0], g["lon"][0], g["lat"][1], g["lon"][1], entry["source_total_bytes"]),
            "bilinear interpolation to %.2f N, %.2f E (weights: %.4f towards %s E, %.4f towards %s N)" % (
                JEZERO_LAT, JEZERO_LON, wx, g["lon"][1], wy, g["lat"][1]),
            "cdod610: 9.3 um absorption column dust optical depth normalised to 610 Pa (file unit Pa/Pa, written as 1)",
            "cdodtot: 9.3 um absorption column dust optical depth of the total column down to the grid point surface",
            "tau_vis = %.1f x cdodtot: the LMD page's factor for an equivalent visible column optical depth" % VIS_PER_IR_ABS,
            "ls written as in the file (the first map of a year may carry Ls just below 360)",
        ],
    }
    return product, {"tau": tau, "time": d["time"], "ls": d["ls"], "ave_mjd": d["ave_mjd"], "soy": d["soy"],
                     "mars_year": mars_year, "pid": pid}


# ---------------------------------------------------------------- episodes

def build_background(series: list[dict]) -> list[list[float]]:
    pts = []
    for s in series:
        for k, tau in enumerate(s["tau"]):
            if tau is not None:
                pts.append((s["ls"][k] % 360.0, tau))
    out = []
    b = 0.0
    while b < 360.0 - 1e-9:
        window = [tau for ls, tau in pts if min(abs(ls - b), 360.0 - abs(ls - b)) <= BACKGROUND_HALF_WINDOW_LS]
        out.append([b, round(percentile(window, BACKGROUND_PERCENTILE), 4)])
        b += BACKGROUND_STEP_LS
    out.append([360.0, out[0][1]])
    return out


def background_at(bg: list[list[float]], ls: float) -> float:
    ls %= 360.0
    for k in range(len(bg) - 1):
        a, b = bg[k], bg[k + 1]
        if a[0] <= ls <= b[0]:
            return a[1] + (b[1] - a[1]) * (ls - a[0]) / (b[0] - a[0])
    return bg[-1][1]


def find_episodes(s: dict, bg: list) -> list[tuple[int, int]]:
    tau = s["tau"]
    n = len(tau)
    excess = [None if tau[k] is None else tau[k] - background_at(bg, s["ls"][k]) for k in range(n)]
    found = []
    k = 0
    while k < n:
        if excess[k] is not None and excess[k] >= EPISODE_THRESHOLD:
            a = k
            while a > 0 and excess[a - 1] is not None and excess[a - 1] >= EPISODE_EDGE:
                a -= 1
            z = k
            while z < n - 1 and excess[z + 1] is not None and excess[z + 1] >= EPISODE_EDGE:
                z += 1
            found.append([a, z])
            k = z + 1
        else:
            k += 1
    merged: list[list[int]] = []
    for a, z in found:
        if merged and a - merged[-1][1] - 1 <= EPISODE_MERGE_GAP_SOLS:
            merged[-1][1] = z
        else:
            merged.append([a, z])
    return [(a, z) for a, z in merged]


def mission_sol_offset(lmd36: dict, meda_labels: list[dict]) -> float:
    """LMD Time minus Mars 2020 mission sol, from the MEDA labels' Ls at the middle of each downloaded sol."""
    offsets = []
    for lab in meda_labels:
        ls_mid = 0.5 * (lab["ls_start"] + lab["ls_end"])
        for k in range(len(lmd36["ls"]) - 1):
            l0, l1 = lmd36["ls"][k], lmd36["ls"][k + 1]
            if l0 <= ls_mid <= l1:
                t = lmd36["time"][k] + (ls_mid - l0) / (l1 - l0) * (lmd36["time"][k + 1] - lmd36["time"][k])
                offsets.append(t - (lab["sol_start"] + 0.5))
                break
    return sum(offsets) / len(offsets)


def build_episodes(lmd: list[dict], meda: dict, bg: list) -> tuple[list[dict], dict]:
    lmd36 = next(s for s in lmd if s["mars_year"] == 36)
    labels = [m["label"] for m in meda.values()]
    offset = mission_sol_offset(lmd36, labels)
    episodes = []
    for s in lmd:
        for a, z in find_episodes(s, bg):
            lo = max(a - 1, 0)
            hi = min(z + 1, len(s["tau"]) - 1)
            times = s["time"][lo:hi + 1]
            taus = s["tau"][lo:hi + 1]
            if any(x is None for x in taus):
                continue
            duration = times[-1] - times[0]
            curve = []
            steps = int(round(duration / CURVE_STEP_SOL))
            for i in range(steps + 1):
                t = times[0] + i * CURVE_STEP_SOL
                j = min(int(math.floor(t - times[0])), len(times) - 2)
                f = (t - times[j]) / (times[j + 1] - times[j])
                curve.append(round(taus[j] + (taus[j + 1] - taus[j]) * f, 4))
            pk = max(range(a, z + 1), key=lambda k: s["tau"][k])
            peak = s["tau"][pk]
            bg_peak = background_at(bg, s["ls"][pk])
            mission = None
            source_ids = [s["pid"]]
            wind_vals: list[float] = []
            wind_ids: list[str] = []
            meda_seen = []
            if s["mars_year"] == 36:
                m0 = times[0] - offset
                m1 = times[-1] - offset
                mission = [int(math.floor(m0)), int(math.floor(m1))]
                for pid, m in sorted(meda.items()):
                    lab = m["label"]
                    if mission[0] <= lab["sol_start"] <= mission[1]:
                        source_ids.append(pid)
                        meda_seen.append(pid)
                        if m["kind"] == "wind":
                            wind_vals += [x[1][0] for x in m["samples"]]
                            wind_ids.append(pid)
            ls0, ls1 = s["ls"][lo], s["ls"][hi]
            d0, d1 = mjd_to_date(s["ave_mjd"][lo]), mjd_to_date(s["ave_mjd"][hi])
            words = "Mars year %d, Ls %.1f to %.1f degrees, %s to %s" % (s["mars_year"], ls0, ls1, d0, d1)
            if mission:
                words += " (Perseverance mission sols about %d to %d)" % (mission[0], mission[1])
            else:
                words += " (before Perseverance landed: orbital record only)"
            wind_mean = mean(wind_vals)
            ep = {
                "id": "jezero_my%d_ls%03d" % (s["mars_year"], int(round(s["ls"][pk]))),
                "source_product_ids": source_ids,
                "observed": words,
                "duration_sols": round(duration, 2),
                "peak_tau": round(peak, 4),
                "tau_curve": curve,
                "wind_ms_mean": round(wind_mean, 2) if wind_mean is not None else MISSING,
                "solar_factor_at_peak": round(math.exp(-GAME_DUST_TAU_FACTOR * (peak - GAME_DUST_TAU_DEFAULT)), 4),
                "notes": "",
                "mars_year": s["mars_year"], "ls_start": round(ls0, 2), "ls_peak": round(s["ls"][pk], 2),
                "ls_end": round(ls1, 2), "start_date": d0, "peak_date": mjd_to_date(s["ave_mjd"][pk]), "end_date": d1,
                "mission_sols": mission, "background_tau": round(bg_peak, 4),
                "excess_at_peak": round(peak - bg_peak, 4),
                "episode_sols": z - a + 1,  # daily maps from the episode's first to last sol (merged gaps included)
                "wind_source": ("mean of %d kept 1 Hz MEDA derived wind samples on %s" % (len(wind_vals), ", ".join(wind_ids))
                                if wind_vals else "not measured (MEDA derived wind data end at sol 315; %.1f = missing)" % MISSING),
                "meda_products_in_period": meda_seen,
            }
            notes = ["tau = visible-equivalent column dust optical depth at Jezero (2.6 x LMD cdodtot), one map per sol,"
                     " linearly interpolated to 0.25 sol steps from the sol before the episode to the sol after it",
                     "solar_factor_at_peak uses the game's power model exp(-0.6 x (tau - 0.5)) (balance, not measured)"]
            if wind_vals:
                notes.append("wind is from the first sol of the period only (the storm's arrival); MEDA wind data stop "
                             "at sol 315 because harsh weather damaged parts of the wind sensor (MEDA release notes)")
            ep["notes"] = "; ".join(notes)
            episodes.append(ep)
    return episodes, {"mission_sol_offset": round(offset, 3)}


def meda_summary(pid: str, m: dict) -> dict:
    vals = [x[1][0] for x in m["samples"]]
    return {"product_id": pid, "kind": m["kind"], "sol": m["label"]["sol_start"],
            "ls": [m["label"]["ls_start"], m["label"]["ls_end"]], "samples": len(vals),
            "mean": round(mean(vals), 2), "min": round(min(vals), 2), "max": round(max(vals), 2)}


# ---------------------------------------------------------------- the bundle

def build_bundle() -> int:
    downloads = load_downloads()
    BUNDLE.mkdir(parents=True, exist_ok=True)
    for pattern in ("*.csv", "*.csv.import", "*.translation", "episodes.json", "manifest.json"):
        for old in BUNDLE.glob(pattern):
            old.unlink()
    products = []
    meda = {}
    for pid, stem, kind, sid in MEDA_PRODUCTS:
        p, info = build_meda_product(pid, stem, kind, sid, downloads)
        info["kind"] = kind
        products.append(p)
        meda[pid] = info
    lmd = []
    for pid, stem, my, sid in LMD_PRODUCTS:
        p, info = build_lmd_product(pid, stem, my, sid, downloads)
        products.append(p)
        lmd.append(info)
    bg = build_background(lmd)
    episodes, extra = build_episodes(lmd, meda, bg)
    lmd36 = next(s for s in lmd if s["mars_year"] == 36)
    quiet_tau = None
    for k in range(len(lmd36["time"])):
        if abs((lmd36["time"][k] - extra["mission_sol_offset"]) - (QUIET_SOL + 0.5)) <= 0.5:
            quiet_tau = lmd36["tau"][k]
    quiet = {"mission_sol": QUIET_SOL, "tau": round(quiet_tau, 4) if quiet_tau is not None else MISSING,
             "meda": [meda_summary(pid, m) for pid, m in sorted(meda.items()) if m["label"]["sol_start"] == QUIET_SOL]}
    comparisons = [meda_summary(pid, m) for pid, m in sorted(meda.items()) if m["label"]["sol_start"] != QUIET_SOL]
    wind_quiet = next((x["mean"] for x in quiet["meda"] if x["kind"] == "wind"), MISSING)
    episodes_doc = {
        "curve_step_sol": CURVE_STEP_SOL,
        "tau_quantity": "visible-equivalent column dust optical depth at Jezero = 2.6 x LMD cdodtot",
        "derivation": [
            "tau at Jezero for every sol of Mars years 35 and 36 from the LMD kriged dust scenario (products "
            "lmd_cdod_my35, lmd_cdod_my36; column tau_vis)",
            "background: for Ls = 0, 10, ..., 350 the %d%% percentile of tau over both years within +-%g degrees of Ls; "
            "360 repeats 0; linear between points" % (int(BACKGROUND_PERCENTILE * 100), BACKGROUND_HALF_WINDOW_LS),
            "an episode opens on a sol whose tau exceeds the background by %.3f or more and extends to neighbouring sols "
            "while the excess is at least %.3f; episodes separated by %d sols or fewer are merged"
            % (EPISODE_THRESHOLD, EPISODE_EDGE, EPISODE_MERGE_GAP_SOLS),
            "tau_curve: the daily values from the sol before the episode to the sol after it, linearly interpolated "
            "every %.2f sol; duration_sols = the curve's length in sols; peak_tau = the largest daily value" % CURVE_STEP_SOL,
            "Mars year 36 sols are matched to Perseverance mission sols through Ls: LMD Time - mission sol = %.3f "
            "(mean over the downloaded MEDA labels)" % extra["mission_sol_offset"],
            "wind_ms_mean: mean of the kept MEDA derived 1 Hz wind samples on downloaded sols inside the period; "
            "%.1f when no MEDA wind exists for the period" % MISSING,
            "solar_factor_at_peak: the game's power model term exp(-0.6 x (peak_tau - 0.5)) from docs/MODEL_P07.md "
            "(game balance, not a measurement)",
        ],
        "episodes": episodes,
        "background": {"tau_by_ls": bg, "source_product_ids": [p[0] for p in LMD_PRODUCTS],
                       "wind_ms_mean_quiet": wind_quiet, "quiet_reference": quiet},
        "meda_storm_sols": comparisons,
        "mission_sol_offset": extra["mission_sol_offset"],
    }
    ep_bytes = write_json(BUNDLE / "episodes.json", episodes_doc)
    refresh = []
    for p in products:
        is_lmd = p["id"].startswith("lmd_")
        refresh.append({
            "product_id": p["id"], "url": p["source_url"],
            "max_bytes": 2000000 if is_lmd else int(math.ceil(p["source_bytes"] * 1.5 / 100000.0) * 100000),
            "timeout_s": 20, "etag": p["etag"], "last_modified": p["last_modified"],
            "note": ("Conditional GET of the archive file this product was built from. 304 = unchanged. A 200 answer "
                     "means the archive changed the file; the product is rebuilt only by tools/weather/build_bundle.py "
                     "(the transform is Python), so the game keeps its bundle and reports that an update was published."
                     + (" This NetCDF file is %d bytes, more than max_bytes: a changed file is expected to be refused "
                        "as oversize." % p["source_bytes"] if is_lmd else "")),
        })
    built = max(e["retrieved_utc"] for e in downloads.values() if e.get("retrieved_utc"))
    manifest = {
        "format": FORMAT, "schema": SCHEMA, "bundle_id": BUNDLE_ID, "version": BUNDLE_VERSION, "built_utc": built,
        "built_utc_note": "time of the newest raw download, so a rebuild from the same raw files is byte-identical",
        "built_by": "tools/weather/build_bundle.py",
        "site": "Jezero crater, Mars (Perseverance landing area). Not the fictional colony.",
        "notice": "Archived observations from Jezero crater (2019-2022), not live weather and not a forecast for the "
                  "colony. The game plays them faster and scales them; those changes are game transformation.",
        "products": products,
        "episodes_file": "episodes.json", "episodes_sha256": sha256_bytes(ep_bytes),
        "refresh": refresh,
    }
    write_json(BUNDLE / "manifest.json", manifest)
    print("bundle written: %s (%d products, %d episodes)" % (BUNDLE, len(products), len(episodes)))
    for ep in episodes:
        print("  %-20s %5.1f sols peak %.2f (bg %.2f) wind %s  %s" % (ep["id"], ep["duration_sols"], ep["peak_tau"],
              ep["background_tau"], ep["wind_ms_mean"], ep["observed"]))
    return 0


# ---------------------------------------------------------------- fixture (synthetic, for tests only)

def build_fixture(out: Path = FIXTURE) -> None:
    """A tiny valid bundle in the shipped format: 2 products, 2 episodes. Synthetic numbers for format tests only;
    they are NOT observations and must never be shown to players as Mars data."""
    out.mkdir(parents=True, exist_ok=True)
    for pattern in ("*.csv", "*.csv.import", "*.translation"):
        for old in out.glob(pattern):
            old.unlink()
    ps_rows = []
    ps_values = [610.0, 612.5, 615.0, None, 611.0, 606.5, 604.0]
    for i, v in enumerate(ps_values):
        ps_rows.append([fmt(100.0 + i * 0.125, 3), fmt(v, 2)])
    ps_bytes = write_csv(out / "fixture_ps.csv", ["sol", "pressure"], ps_rows)
    tau_rows = []
    tau_values = [0.50, 0.52, 0.80, 1.40, 1.10, 0.70, 0.55, 0.50]
    for i, v in enumerate(tau_values):
        tau_rows.append([fmt(100.0 + i, 3), fmt(150.0 + i * 0.55, 3), fmt(v, 4)])
    tau_bytes = write_csv(out / "fixture_tau.csv", ["sol", "ls", "tau"], tau_rows)
    episodes = {
        "note": "TEST FIXTURE: synthetic numbers for format tests only, not observations.",
        "curve_step_sol": CURVE_STEP_SOL,
        "episodes": [
            {"id": "fixture_minor", "source_product_ids": ["fixture_tau"],
             "observed": "synthetic test episode (fixture sols 101-103)", "duration_sols": 1.0, "peak_tau": 0.9,
             "background_tau": 0.5, "tau_curve": [0.5, 0.6, 0.9, 0.7, 0.5], "wind_ms_mean": 4.0,
             "solar_factor_at_peak": round(math.exp(-0.6 * (0.9 - 0.5)), 4),
             "notes": "Synthetic. Minor event for first-event tests."},
            {"id": "fixture_major", "source_product_ids": ["fixture_tau", "fixture_ps"],
             "observed": "synthetic test episode (fixture sols 102-106)", "duration_sols": 2.0, "peak_tau": 1.4,
             "background_tau": 0.5, "tau_curve": [0.5, 0.7, 0.95, 1.2, 1.4, 1.3, 1.1, 0.8, 0.5],
             "wind_ms_mean": 6.0, "solar_factor_at_peak": round(math.exp(-0.6 * (1.4 - 0.5)), 4),
             "notes": "Synthetic. Larger event for severity and scaling tests."},
        ],
        "background": {"tau_by_ls": [[0.0, 0.5], [90.0, 0.4], [180.0, 0.6], [270.0, 0.8], [360.0, 0.5]]},
    }
    ep_bytes = write_json(out / "episodes.json", episodes)
    common = {
        "source_id": "TEST", "pds_lid": "urn:nasa:pds:test_fixture:not_a_product", "version": "1.0",
        "mission": "Mars 2020", "site": "Jezero crater", "lat": JEZERO_LAT, "lon": JEZERO_LON,
        "units_ok": UNITS_OK, "missing_value": MISSING, "time_column": "sol",
        "quality": "TEST FIXTURE: synthetic values, no flags.",
        "license": "Test fixture written by tools/weather/build_bundle.py --fixture; not archive data.",
        "etag": "\"fixture-1\"", "last_modified": "Thu, 01 Jan 2026 00:00:00 GMT",
        "retrieved_utc": "2026-01-01T00:00:00Z", "transform": ["synthetic numbers written by build_fixture()"],
    }
    p1 = dict(common)
    p1.update({"id": "fixture_ps", "kind": "pressure", "file": "fixture_ps.csv", "sha256": sha256_bytes(ps_bytes),
               "bytes": len(ps_bytes), "instrument": "MEDA PS (fixture)",
               "observation_start_utc": "2022-01-01T00:00:00Z", "observation_end_utc": "2022-01-01T18:30:00Z",
               "sol_start": 100, "sol_end": 100, "ls_start": 150.0, "ls_end": 150.4,
               "columns": {"sol": "1", "pressure": "Pa"}, "source_url": "https://fixture.invalid/weather/fixture_ps.csv"})
    p2 = dict(common)
    p2.update({"id": "fixture_tau", "kind": "dust_opacity", "file": "fixture_tau.csv", "sha256": sha256_bytes(tau_bytes),
               "bytes": len(tau_bytes), "instrument": "orbital column dust optical depth (fixture)",
               "observation_start_utc": "2022-01-01T00:00:00Z", "observation_end_utc": "2022-01-08T05:00:00Z",
               "sol_start": 100, "sol_end": 107, "ls_start": 150.0, "ls_end": 153.85,
               "columns": {"sol": "1", "ls": "deg", "tau": "1"},
               "source_url": "https://fixture.invalid/weather/fixture_tau.csv"})
    manifest = {
        "format": FORMAT, "schema": SCHEMA, "bundle_id": "fixture-min-v1", "version": "1",
        "built_utc": "2026-01-01T00:00:00Z",
        "note": "TEST FIXTURE: synthetic numbers for format tests only, not observations.",
        "products": [p1, p2],
        "episodes_file": "episodes.json", "episodes_sha256": sha256_bytes(ep_bytes),
        "refresh": [{"product_id": "fixture_ps", "url": "https://fixture.invalid/weather/fixture_ps.csv",
                     "max_bytes": 200000, "timeout_s": 20}],
    }
    write_json(out / "manifest.json", manifest)
    print("fixture written:", out)


def main(argv: list[str]) -> int:
    if "--fixture" in argv:
        build_fixture()
        return 0
    try:
        return build_bundle()
    except BuildError as e:
        print("BUILD FAILED:", e)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
