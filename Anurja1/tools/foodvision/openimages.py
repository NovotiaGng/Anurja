"""Global dishes and drinks from Open Images V7 for FoodClassifier.mlmodel.

Photos: Flickr thumbnails, CC BY 2.0 (author, license and page per photo in
tools/foodvision/openimages_credits.csv). Photos since deleted from Flickr are skipped.
Labels: human-verified image-level labels, CC BY 4.0, Google.

    python3 -I tools/foodvision/openimages.py count      # verified photos per class
    python3 -I tools/foodvision/openimages.py fetch      # download, then split like prepare.py

Only photos a person verified as showing the class (Confidence 1) are used,
and a photo verified for two of these classes is dropped (it is a mixed plate,
not a clean example of either).
"""
import csv
import hashlib
import json
import random
import subprocess
import sys
import urllib.request
from collections import defaultdict
from pathlib import Path

BASE = "https://storage.googleapis.com/openimages"
HERE = Path(__file__).resolve().parent
DATA = HERE / "data"
OI = DATA / "openimages"

# Open Images display name -> our label. Indian dishes already come from
# prepare.py's dataset; Open Images adds the rest of the world.
CLASSES = {
    # Mexican
    "Taco": "taco", "Burrito": "burrito", "Enchilada": "enchilada", "Quesadilla": "quesadilla",
    "Nachos": "nachos", "Guacamole": "guacamole", "Tamale": "tamale", "Churro": "churro", "Fajita": "fajita",
    # Chinese
    "Dim sum": "dim_sum", "Dumpling": "dumpling", "Spring roll": "spring_roll", "Chow mein": "chow_mein",
    "Peking duck": "peking_duck", "Kung pao chicken": "kung_pao_chicken", "Mapo doufu": "mapo_tofu",
    "Wonton": "wonton", "Baozi": "baozi", "Hot pot": "hot_pot", "Sweet and sour pork": "sweet_sour_pork",
    "Char siu": "char_siu", "Congee": "congee", "Lo mein": "lo_mein",
    # Korean
    "Bibimbap": "bibimbap", "Bulgogi": "bulgogi", "Kimchi": "kimchi",
    "Japchae": "japchae", "Gimbap": "gimbap", "Samgyeopsal": "samgyeopsal",
    # Japanese
    "Sushi": "sushi", "Sashimi": "sashimi", "Ramen": "ramen", "Udon": "udon", "Tempura": "tempura",
    "Takoyaki": "takoyaki", "Jiaozi": "jiaozi", "Okonomiyaki": "okonomiyaki",
    "Miso soup": "miso_soup", "Donburi": "donburi", "Tonkatsu": "tonkatsu", "Yakitori": "yakitori",
    # Thai / Vietnamese / SE Asian
    "Pad thai": "pad_thai", "Pho": "pho", "Bánh mì": "banh_mi", "Satay": "satay",
    "Green curry": "green_curry", "Nasi goreng": "nasi_goreng", "Laksa": "laksa",
    # Western / Middle Eastern
    "Pizza": "pizza", "Hamburger": "burger", "Hot dog": "hot_dog", "Sandwich": "sandwich",
    "Submarine sandwich": "sandwich", "French fries": "french_fries", "Spaghetti": "spaghetti",
    "Lasagne": "lasagne", "Pasta": "pasta", "Salad": "salad", "Caesar salad": "caesar_salad", "Steak": "steak",
    "Fried chicken": "fried_chicken", "Fish and chips": "fish_and_chips", "Pancake": "pancake", "Waffle": "waffle",
    "Omelette": "omelette", "Scrambled eggs": "scrambled_eggs", "Croissant": "croissant", "Bagel": "bagel",
    "Doughnut": "doughnut", "Muffin": "muffin", "Cake": "cake", "Cookie": "cookie", "Ice cream": "ice_cream",
    "Paella": "paella", "Risotto": "risotto", "Falafel": "falafel", "Hummus": "hummus", "Kebab": "kebab",
    "Shawarma": "shawarma", "Toast": "toast", "Oatmeal": "oatmeal", "Breakfast cereal": "cereal",
    "Soup": "soup", "Fried rice": "fried_rice", "Noodle": "noodles", "Curry": "curry",
    # Coffee, tea and drinks
    "Coffee (drink)": "coffee", "Espresso": "espresso", "Cappuccino": "cappuccino", "Latte": "latte",
    "Iced coffee": "iced_coffee", "Caffè macchiato": "macchiato",
    "Caffè americano": "americano", "Flat white": "flat_white", "Tea": "chai",
    "Smoothie": "smoothie", "Milkshake": "milkshake", "Juice": "juice",
    # Fruit
    "Apple": "apple", "Banana": "banana", "Orange (fruit)": "orange", "Mango": "mango", "Grape": "grape",
    "Strawberry": "strawberry", "Watermelon": "watermelon", "Papaya": "papaya", "Guava": "guava",
}

SPLITS = {"train": "train", "val": "validation", "test": "test"}  # label file -> image folder


def fetch_file(name):
    path = OI / Path(name).name
    if not path.exists():
        print("downloading", name)
        urllib.request.urlretrieve(f"{BASE}/{name}", path.with_suffix(".part"))
        path.with_suffix(".part").rename(path)
    return path


def class_ids():
    names = {}
    with open(fetch_file("v7/oidv7-class-descriptions.csv"), newline="", encoding="utf-8") as f:
        for mid, name in csv.reader(f):
            if name in CLASSES:
                names[mid] = CLASSES[name]
    missing = set(CLASSES.values()) - set(names.values())
    if missing:
        print("not in Open Images:", ", ".join(sorted(missing)))
    return names


def verified(ids):
    """image id -> set of our labels, from human-verified positives."""
    cache = OI / "verified.json"  # image -> Open Images class ids, so renaming CLASSES needs no re-scan
    if not cache.exists():
        images = defaultdict(set)
        for split, folder in SPLITS.items():
            path = fetch_file(f"v7/oidv7-{split}-annotations-human-imagelabels.csv")
            with open(path, newline="") as f:
                for row in csv.DictReader(f):
                    if row["Confidence"] == "1" and row["LabelName"] in ids:
                        images[f"{folder}/{row['ImageID']}"].add(row["LabelName"])
        cache.write_text(json.dumps({k: sorted(v) for k, v in images.items()}))
    return {k: {ids[m] for m in v if m in ids} for k, v in json.loads(cache.read_text()).items()}


def clean(images):
    """Photos verified for exactly one of our classes, by label."""
    by_label = defaultdict(list)
    for key, labels in images.items():
        if len(labels) == 1:
            by_label[next(iter(labels))].append(key)
    return by_label


def count():
    by_label = clean(verified(class_ids()))
    for label, keys in sorted(by_label.items(), key=lambda kv: -len(kv[1])):
        print(f"{label:22} {len(keys)}")


METADATA = {  # image folder -> file with each photo's Flickr thumbnail, author and license
    "train": "v6/oidv6-train-images-with-labels-with-rotation.csv",
    "validation": "2018_04/validation/validation-images-with-rotation.csv",
    "test": "2018_04/test/test-images-with-rotation.csv",
}


def metadata(keys):
    """key -> (thumbnail url, license url, author, Flickr page) for the chosen photos."""
    cache = OI / "metadata.json"
    if cache.exists():
        return json.loads(cache.read_text())
    wanted = set(keys)
    found = {}
    for folder, name in METADATA.items():
        with open(fetch_file(name), newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                key = f"{folder}/{row['ImageID']}"
                if key in wanted and row["Thumbnail300KURL"]:
                    found[key] = [row["Thumbnail300KURL"], row["License"], row["Author"], row["OriginalLandingURL"]]
    cache.write_text(json.dumps(found))
    return found


def download_photos(meta):
    """Fetch the ~640 px Flickr thumbnails with curl (parallel; photos already
    on disk are skipped; photos since deleted from Flickr just fail)."""
    todo = [k for k in meta if not photo_path(k).exists()]
    config = OI / "curl.txt"
    config.write_text("".join(f'url = "{meta[k][0]}"\noutput = "{photo_path(k)}"\n' for k in todo))
    print("downloading", len(todo), "photos")
    subprocess.run(["curl", "-sS", "--parallel", "--parallel-max", "16", "--retry", "2", "-m", "60",
                    "--fail", "-L", "-K", str(config)], check=False, stderr=subprocess.DEVNULL)


def photo_path(key):
    return OI / "photos" / f"{key.replace('/', '_')}.jpg"


def fetch():
    sys.path.insert(0, str(HERE))  # our own prepare.py (python -I leaves the script dir out)
    from prepare import normalise, split_and_write

    by_label = clean(verified(class_ids()))
    rng = random.Random(7)
    chosen = []
    for label, keys in sorted(by_label.items()):
        if len(keys) < MIN_PHOTOS or label in SKIP:
            continue
        keys = sorted(keys)
        rng.shuffle(keys)
        chosen += [(label, k) for k in keys[:MAX_PHOTOS]]
    print(len(chosen), "photos in", len({l for l, _ in chosen}), "classes")
    (OI / "photos").mkdir(exist_ok=True)
    meta = metadata([k for _, k in chosen])
    download_photos(meta)
    photos = {}
    for label, key in chosen:
        if photo_path(key).exists() and (photo := normalise(data := photo_path(key).read_bytes())):
            photos[hashlib.sha1(data).hexdigest()] = (label, *photo)
    counts = split_and_write(DATA, photos)
    (OI / "split.json").write_text(json.dumps({"source": "Open Images V7 human-verified image labels", "counts": counts}, indent=1))
    with open(HERE / "openimages_credits.csv", "w", newline="", encoding="utf-8") as f:
        out = csv.writer(f)
        out.writerow(["label", "open_images_id", "license", "author", "source"])
        for label, key in sorted(chosen):
            if key in meta and photo_path(key).exists():
                out.writerow([label, key, *meta[key][1:]])


# Classes need this many clean verified photos to be learnable; big classes are
# capped so cake (4,392) doesn't drown out bagel (102).
MIN_PHOTOS, MAX_PHOTOS = 100, 600
# "curry" in Open Images is any curry; the Indian set already splits curries by dish.
SKIP = {"curry"}

if __name__ == "__main__":
    OI.mkdir(parents=True, exist_ok=True)
    {"count": count, "fetch": fetch}[sys.argv[1] if len(sys.argv) > 1 else "count"]()
