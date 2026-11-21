"""Download and split the food photos for FoodClassifier.mlmodel.

Data: SohlHealth/enhanced-indian-food-classification on Hugging Face
(CC BY 4.0, 15,404 real photos, 43 Indian dishes). The commit sha used is
recorded in split.json.

The published splits don't cover every class (the test split has 22 of 43)
and repeat some photos across splits, so this pools them, groups exact and
near-duplicate photos (64-bit dHash, Hamming distance <= 4) and makes a
fresh 70 / 15 / 15 train / val / test split by group. No photo, or a resized
copy of it, lands in two splits.

    python3 -I tools/foodvision/prepare.py [cache dir]   # default tools/foodvision/data (git-ignored)

Needs pyarrow and Pillow. Writes <cache>/{train,val,test}/<label>/<sha1>.jpg
and <cache>/split.json.
"""
import hashlib
import io
import json
import random
import sys
import urllib.request
from collections import defaultdict
from pathlib import Path

import pyarrow.parquet as pq
from PIL import Image, ImageOps

REPO = "SohlHealth/enhanced-indian-food-classification"
FILES = [
    "test-00000-of-00001",
    "validation-00000-of-00001",
    "train-00000-of-00003",
    "train-00001-of-00003",
    "train-00002-of-00003",
]


def resolve_revision():
    with urllib.request.urlopen(f"https://huggingface.co/api/datasets/{REPO}") as r:
        return json.load(r)["sha"]


def download(raw, sha):
    raw.mkdir(parents=True, exist_ok=True)
    for name in FILES:
        path = raw / f"{name}.parquet"
        if path.exists():
            continue
        url = f"https://huggingface.co/datasets/{REPO}/resolve/{sha}/data/{name}.parquet"
        print("downloading", url)
        urllib.request.urlretrieve(url, path.with_suffix(".part"))
        path.with_suffix(".part").rename(path)


def dhash(img):
    g = img.convert("L").resize((9, 8), Image.Resampling.LANCZOS)
    px = g.tobytes()
    bits = 0
    for y in range(8):
        for x in range(8):
            bits = bits << 1 | (px[y * 9 + x] > px[y * 9 + x + 1])
    return bits


def normalise(data):
    """(RGB JPEG bytes, dHash), or None for unreadable or tiny photos."""
    try:
        img = Image.open(io.BytesIO(data))
        img.load()
    except Exception:
        return None
    if min(img.size) < 64:
        return None
    # Create ML / Vision choke on PNG / CMYK / huge files: store every photo as
    # an RGB JPEG, longest side <= 1024 (the feature print sees 384 px anyway).
    img = ImageOps.exif_transpose(img).convert("RGB")
    img.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=90)
    return buf.getvalue(), dhash(img)


def split_and_write(cache, photos):
    """photos: sha1 -> (label, jpeg bytes, dhash). Writes <cache>/<split>/<label>/
    and returns {label: {split: count}}."""
    print(len(photos), "unique photos")

    # Group near-duplicates with union-find over 16-bit dHash buckets (any two
    # hashes within distance 4 share at least one of the four 16-bit chunks).
    parent = {k: k for k in photos}

    def find(k):
        while parent[k] != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    buckets = defaultdict(list)
    for k, (_, _, h) in photos.items():
        for i in range(4):
            buckets[(i, h >> (16 * i) & 0xFFFF)].append(k)
    for keys in buckets.values():
        for a in range(len(keys)):
            for b in range(a + 1, len(keys)):
                if bin(photos[keys[a]][2] ^ photos[keys[b]][2]).count("1") <= 4:
                    parent[find(keys[a])] = find(keys[b])

    groups = defaultdict(list)
    for k in photos:
        groups[find(k)].append(k)
    conflicting = 0
    by_label = defaultdict(list)
    for members in groups.values():
        labels = {photos[k][0] for k in members}
        if len(labels) > 1:
            conflicting += 1  # same photo filed under two dishes: drop it
            continue
        by_label[labels.pop()].append(members)
    print(len(groups), "groups,", conflicting, "dropped for conflicting labels")

    rng = random.Random(7)
    counts = {}
    for label, label_groups in sorted(by_label.items()):
        label_groups.sort()
        rng.shuffle(label_groups)
        n = sum(len(g) for g in label_groups)
        done = 0
        counts[label] = defaultdict(int)
        for g in label_groups:
            # Fill test first, then val, then train, by photo count.
            split = "test" if done < 0.15 * n else "val" if done < 0.30 * n else "train"
            for k in g:
                out = cache / split / label / f"{k}.jpg"
                for other in {"train", "val", "test"} - {split}:  # an earlier run may have put it elsewhere
                    (cache / other / label / f"{k}.jpg").unlink(missing_ok=True)
                out.parent.mkdir(parents=True, exist_ok=True)
                if not out.exists():
                    out.write_bytes(photos[k][1])
                counts[label][split] += 1
            done += len(g)
    for label, c in counts.items():
        print(f"{label:16} train {c['train']:4}  val {c['val']:4}  test {c['test']:4}")
    return counts


def main():
    cache = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).parent / "data")
    sha = resolve_revision()
    download(cache / "raw", sha)

    photos = {}  # sha1 -> (label, bytes, dhash)
    for name in FILES:
        table = pq.read_table(cache / "raw" / f"{name}.parquet")
        for row in table.to_pylist():
            data = row["image"]["bytes"]
            key = hashlib.sha1(data).hexdigest()
            if key not in photos and (photo := normalise(data)):
                photos[key] = (row["label"], *photo)
    counts = split_and_write(cache, photos)
    (cache / "split.json").write_text(json.dumps({"repo": REPO, "revision": sha, "counts": counts}, indent=1))


if __name__ == "__main__":
    main()
