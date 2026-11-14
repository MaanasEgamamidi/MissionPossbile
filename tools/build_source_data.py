"""Builds data/sources.json from the development source register (docs/source_register.md).

Python 3 standard library only. Run from the project folder:

    py -I tools\\build_source_data.py           (writes data/sources.json)
    py -I tools\\build_source_data.py --check   (only checks; writes nothing)

What it does:
- Reads every table row whose first cell is an S, T, M or L id (S01, T03, M02, L01 ...).
- Takes the title, publisher, URL, status, date, kind, evidence category, what was read and what it supports
  from the row's cells. The URL is the first https:// address in the row, exactly as written in the register.
- Adds the few fields the register gives only in its notes (mission and site, observation dates, units) from the
  HAND_EDITS table below. Every hand edit repeats words found in the register; nothing new is invented.
- Afterwards it checks that data/claims.json, data/explanations.json and data/credits.json only name source ids
  that exist.
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGISTER = os.path.join(ROOT, "docs", "source_register.md")
OUT = os.path.join(ROOT, "data", "sources.json")

ID_RE = re.compile(r"^[STML]\d\d$")
URL_RE = re.compile(r"https://[^\s|`<>()]+")
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")
STATUS_WORDS = ["SEARCH-ONLY", "VERIFIED", "PARTIAL", "FAILED"]

# Evidence category words in the register -> the category names used by the game.
# The first matching phrase wins, so the more specific phrases come first.
CATEGORY_RULES = [
    ("technology demonstration", "technology"),
    ("technology study", "technology"),
    ("requirements and study", "technology"),
    ("iss analog", "analog"),
    ("analog only", "analog"),
    ("lunar hardware", "analog"),
    ("measured and derived", "measured"),
    ("measured mars data", "measured"),
    ("measured spacecraft telemetry", "measured"),
    ("modelled", "modelled"),
    ("derived", "modelled"),
    ("reference value", "measured"),
    ("fictional", "fiction"),
    ("game tuning", "tuning"),
]

# Fields the register gives in notes or other columns rather than in a cell of its own.
# Each value repeats the register's own words for that entry.
HAND_EDITS = {
    "S01": {"mission_site": "Whole planet (global values, not one site)",
            "units": "m/s², W/m², h, mb, K, °C, % by volume"},
    "S02": {"mission_site": "Whole planet", "units": "h, min, s"},
    "S03": {"mission_site": "Curiosity rover, REMS weather station; Gale crater (named in the register, not on the page)",
            "observation_dates": "7 Aug 2012 (sol 1) to 22 March 2025 (sol 4488), marked ongoing; the volume links are labelled sols 1–4843",
            "units": ""},
    "S04": {"mission_site": "Perseverance rover, MEDA weather station; Jezero crater (named in the register, not on the page)",
            "observation_dates": "From 19 Feb 2021, marked ongoing", "units": "GB (collection sizes)"},
    "S05": {"mission_site": "InSight lander, TWINS and pressure sensor; site name not on the page",
            "observation_dates": "Sol 1 (2018-11-30) to sol 1188 (2022-03-29)"},
    "S06": {"mission_site": "Curiosity rover (MSL), CheMin instrument; Gale crater",
            "observation_dates": "MSL Release 42 (3 August 2026) adds sols 4710–4843"},
    "S07": {"mission_site": "Curiosity rover (MSL), SAM instrument"},
    "S08": {"mission_site": "International Space Station (ISS)", "units": "percent"},
    "S09": {"mission_site": "MOXIE on Mars", "units": "g, g per hour, %"},
    "S10": {"title": "MOXIE results paper (title, authors and year not read)", "publisher": "Science Advances"},
    "S11": {"mission_site": "International Space Station (ISS): Veggie and the Advanced Plant Habitat"},
    "S12": {"mission_site": "International Space Station (ISS): Veggie"},
    "S13": {"mission_site": "International Space Station (ISS): Veggie"},
    "S14": {"mission_site": "International Space Station (ISS): Veggie"},
    "S15": {"publisher": "NASA", "title": "Earth–Mars signal delay pages", "units": "minutes"},
    "S16": {"mission_site": "Apollo, the Moon (not Mars)", "units": "kg, V, Ah"},
    "S17": {"publisher": "NASA"},
    "S18": {"publisher": "NASA/JPL", "title": "News releases on InSight power and dust",
            "mission_site": "InSight lander", "units": "Wh per sol"},
    "S19": {"mission_site": "International Space Station (ISS)"},
    "T09": {"title": "TwoVoip (goatchurchprime/two-voip-godot-4)", "publisher": "GitHub repository"},
}


def clean(text):
    """Removes Markdown marks the game cannot show."""
    text = text.replace("**", "").replace("`", "").strip()
    return re.sub(r"\s+", " ", text)


def split_row(line):
    cells = line.strip().strip("|").split("|")
    return [c.strip() for c in cells]


def first_url(text):
    m = URL_RE.search(text)
    if not m:
        return ""
    return m.group(0).rstrip(".,;:")


def title_and_publisher(source_cell):
    """'NASA NSSDCA, *Mars Fact Sheet*, D. R. Williams. https://...' -> ('Mars Fact Sheet', 'NASA NSSDCA')."""
    before_url = URL_RE.split(source_cell)[0].strip()
    if "*" in before_url:
        first = before_url.index("*")
        last = before_url.rindex("*")
        title = before_url[first:last + 1].replace("*", "")
        publisher = before_url[:first].strip().rstrip(",")
        return clean(title), clean(publisher)
    text = before_url.rstrip(". ")
    if "," in text:
        publisher, title = text.split(",", 1)
        return clean(title), clean(publisher)
    return clean(text), ""


def parse_status(cell):
    text = clean(cell)
    status = ""
    for word in STATUS_WORDS:
        if text.upper().startswith(word):
            status = word
            break
    date = DATE_RE.search(text)
    checked_on = date.group(0) if (date and status in ("VERIFIED", "PARTIAL")) else ""
    note = text[len(status):].strip() if status else text
    if checked_on:
        note = note.replace(checked_on, "", 1)
    note = note.strip(" .")
    return status, checked_on, note


def category_of(text):
    low = text.lower()
    for phrase, cat in CATEGORY_RULES:
        if phrase in low:
            return cat
    return ""


def empty_entry(sid):
    return {"id": sid, "title": "", "publisher": "", "url": "", "status": "", "checked_on": "", "kind": "",
            "category": "", "values_read": "", "supports": "", "mission_site": "", "observation_dates": "",
            "units": "", "pack_id": "", "section": "", "note": ""}


def parse_register(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    entries = []
    header = []
    section = ""
    for line in lines:
        if line.startswith("## ") or line.startswith("### "):
            section = line.lstrip("#").strip()
            header = []
            continue
        if not line.startswith("|"):
            header = []
            continue
        cells = split_row(line)
        if cells and set(cells[0]) <= set("- "):
            continue
        if not ID_RE.match(cells[0]):
            header = [c.lower() for c in cells]
            continue
        row = dict(zip(header, cells))
        sid = cells[0]
        e = empty_entry(sid)
        e["section"] = section
        e["url"] = first_url(line)
        if sid[0] in "ST":
            e["title"], e["publisher"] = title_and_publisher(row.get("source", ""))
            e["pack_id"] = clean(row.get("pack id", "")).replace("—", "")
            e["status"], e["checked_on"], e["note"] = parse_status(row.get("status", ""))
            read = row.get("values read") or row.get("what was read") or row.get("leads") or ""
            e["values_read"] = "" if clean(read) == "—" else clean(read)
            e["supports"] = clean(row.get("supports") or row.get("supports and gaps") or row.get("used for") or "")
            if sid[0] == "S":
                e["kind"] = clean(row.get("kind", ""))
                evidence = clean(row.get("evidence category", ""))
                e["category"] = category_of(evidence)
                if evidence and evidence != "—":
                    e["note"] = (e["note"] + ". " if e["note"] else "") + "Evidence: " + evidence
            else:
                e["kind"] = "Engine or tool documentation"
                e["category"] = "engine"
        elif sid[0] == "M":
            e["title"] = clean(row.get("finding", ""))
            e["publisher"] = "This project (local test with Godot 4.7.2 on the development computer)"
            e["kind"] = "Engine behaviour measured in this project"
            e["category"] = "engine"
            # Local test results, not a fetched page: shown as partly checked ("may not hold elsewhere").
            e["status"] = "PARTIAL"
            e["values_read"] = clean(row.get("how it was measured", ""))
            e["note"] = "Local test result; not documentation and may not hold elsewhere. Evidence: " + clean(row.get("evidence", ""))
        elif sid[0] == "L":
            e["title"] = clean(row.get("asset", ""))
            e["kind"] = "Asset or dependency licence"
            e["category"] = "engine"
            evidence = clean(row.get("licence evidence", ""))
            e["values_read"] = evidence
            e["note"] = clean(row.get("status", ""))
            # Licence not looked at -> not yet checked; licence text read but unresolved -> partly checked.
            e["status"] = "SEARCH-ONLY" if evidence.lower().startswith("not checked") else "PARTIAL"
        for key, value in HAND_EDITS.get(sid, {}).items():
            e[key] = value
        entries.append(e)
    return entries


def check_ids(sources):
    ids = {s["id"] for s in sources}
    problems = []
    data = os.path.join(ROOT, "data")
    claims_path = os.path.join(data, "claims.json")
    claim_ids = set()
    if os.path.exists(claims_path):
        with open(claims_path, encoding="utf-8") as f:
            claims = json.load(f).get("claims", [])
        claim_ids = {c.get("id") for c in claims}
        for c in claims:
            for sid in c.get("source_ids", []) + c.get("lead_ids", []):
                if sid not in ids:
                    problems.append("claim %s names unknown source %s" % (c.get("id"), sid))
    expl_path = os.path.join(data, "explanations.json")
    if os.path.exists(expl_path):
        with open(expl_path, encoding="utf-8") as f:
            expl = json.load(f)
        for key, e in expl.items():
            for sid in e.get("source_ids", []):
                if sid not in ids:
                    problems.append("explanation %s names unknown source %s" % (key, sid))
            for cid in e.get("claim_ids", []):
                if cid not in claim_ids:
                    problems.append("explanation %s names unknown claim %s" % (key, cid))
    credits_path = os.path.join(data, "credits.json")
    if os.path.exists(credits_path):
        with open(credits_path, encoding="utf-8") as f:
            credits = json.load(f).get("credits", [])
        for c in credits:
            for sid in c.get("source_ids", []):
                if sid not in ids:
                    problems.append("credit %s names unknown source %s" % (c.get("id"), sid))
    return problems


def main():
    sources = parse_register(REGISTER)
    missing_status = [s["id"] for s in sources if s["status"] not in STATUS_WORDS]
    out = {"schema": 1, "built_from": "docs/source_register.md", "sources": sources}
    problems = check_ids(sources) + ["%s has no status" % i for i in missing_status]
    if "--check" not in sys.argv:
        with open(OUT, "w", encoding="utf-8", newline="\n") as f:
            json.dump(out, f, ensure_ascii=False, indent=1)
            f.write("\n")
        print("wrote %s: %d entries" % (os.path.relpath(OUT, ROOT), len(sources)))
    counts = {}
    for s in sources:
        counts[s["status"]] = counts.get(s["status"], 0) + 1
    print("entries by status:", ", ".join("%s %d" % kv for kv in sorted(counts.items())))
    for p in problems:
        print("PROBLEM:", p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
