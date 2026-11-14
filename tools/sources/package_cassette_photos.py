"""Retrieve the six manually verified NASA photographs; gameplay never runs this tool.

NASA serves bounded-width JPEGs. Full aspect ratio is retained; no crop, compositing,
generation, or local image alteration occurs. Pillow only verifies decoding/dimensions.
"""
from concurrent.futures import ThreadPoolExecutor
from hashlib import sha256
from io import BytesIO
import json
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import Request, urlopen
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "data/cassette_photos.json"


def retrieve(photo):
    host = urlparse(photo["download_url"]).hostname or ""
    if host != "nasa.gov" and not host.endswith(".nasa.gov"):
        raise ValueError("Only verified official NASA assets are allowed")
    request = Request(photo["download_url"], headers={"User-Agent": "MarsColony-SourcePackaging/1.0"})
    with urlopen(request, timeout=45) as response:
        data = response.read()
    with Image.open(BytesIO(data)) as image:
        image.verify()
    with Image.open(BytesIO(data)) as image:
        dimensions = list(image.size)
    if min(dimensions) < 600:
        raise ValueError(f"Insufficient photograph resolution: {photo['room_id']} {dimensions}")
    target = ROOT / photo["local_path"].removeprefix("res://")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    photo.update(sha256=sha256(data).hexdigest(), bytes=len(data), dimensions=dimensions,
                 processing="NASA-served bounded-width JPEG; full frame, no local image edits")
    return photo


def main():
    document = json.loads(MANIFEST.read_text(encoding="utf-8"))
    with ThreadPoolExecutor(max_workers=6) as pool:
        document["photos"] = list(pool.map(retrieve, document["photos"]))
    MANIFEST.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    for photo in document["photos"]:
        print(photo["room_id"], photo["image_id"], photo["dimensions"], photo["bytes"], photo["sha256"])


if __name__ == "__main__":
    main()
