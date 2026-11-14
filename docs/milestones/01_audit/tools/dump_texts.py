"""Dump the text datablocks stored inside the open .blend (read-only). Usage: ... --python dump_texts.py -- --out <dir> --label <label>"""
import bpy
import json
import os
import sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opts = dict(zip(argv[0::2], argv[1::2]))
out = {t.name: t.as_string() for t in bpy.data.texts}
with open(os.path.join(opts["--out"], opts["--label"] + ".texts.json"), "w", encoding="utf-8") as f:
    json.dump(out, f, indent=1)
