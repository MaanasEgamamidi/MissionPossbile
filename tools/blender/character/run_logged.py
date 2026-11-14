"""Runs another Blender Python script and writes its printed output and any traceback to a log file (blender-launcher.exe
does not pass the console through).
  blender -b ... --python run_logged.py -- <log.txt> <script.py> <script args...>
"""
import sys, traceback, io, contextlib
i = sys.argv.index("--")
LOG, SCRIPT = sys.argv[i + 1], sys.argv[i + 2]
sys.argv = sys.argv[:i + 1] + sys.argv[i + 3:]
buf = io.StringIO()
ok = True
try:
    with contextlib.redirect_stdout(buf):
        exec(compile(open(SCRIPT, encoding="utf-8-sig").read(), SCRIPT, "exec"), {"__name__": "__main__", "__file__": SCRIPT})
except Exception:
    ok = False
    buf.write("\n" + traceback.format_exc())
buf.write("\nRESULT: " + ("OK" if ok else "FAILED") + "\n")
open(LOG, "w", encoding="utf-8").write(buf.getvalue())
