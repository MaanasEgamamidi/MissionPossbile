"""Lists the files inside a Godot 4 .pck (format versions 2 and 3) with their sizes.
Usage: py -I tools/build/pck_list.py <file.pck> [--json out.json]"""
import json, struct, sys


def read_pck(path):
    with open(path, "rb") as f:
        if f.read(4) != b"GDPC":
            raise SystemExit("not a Godot pck")
        version, major, minor, patch = struct.unpack("<4I", f.read(16))
        flags = 0
        file_base = 0
        if version >= 2:
            flags, file_base = struct.unpack("<IQ", f.read(12))
        if version >= 3:
            (dir_offset,) = struct.unpack("<Q", f.read(8))
            f.seek(dir_offset)
        else:
            f.read(16 * 4)
        if flags & 1:
            raise SystemExit("encrypted directory")
        (count,) = struct.unpack("<I", f.read(4))
        files = []
        for _ in range(count):
            (n,) = struct.unpack("<I", f.read(4))
            name = f.read(n).rstrip(b"\0").decode("utf-8")
            offset, size = struct.unpack("<QQ", f.read(16))
            f.read(16)
            f.read(4)
            files.append({"path": name, "size": size})
        return {"version": version, "engine": "%d.%d.%d" % (major, minor, patch), "files": files}


if __name__ == "__main__":
    info = read_pck(sys.argv[1])
    if "--json" in sys.argv:
        with open(sys.argv[sys.argv.index("--json") + 1], "w", encoding="utf-8") as out:
            json.dump(info, out, indent=1)
    print("pck version", info["version"], "engine", info["engine"], "files", len(info["files"]),
          "bytes", sum(x["size"] for x in info["files"]))
