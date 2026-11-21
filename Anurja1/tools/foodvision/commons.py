"""Mexican, Chinese, Korean, Japanese, SE Asian dishes and coffee drinks from
Wikimedia Commons, for the cuisines Open Images has almost no verified photos of.

    ANURJA_COMMONS_CONTACT="https://your.site or you@example.com" python3 -I tools/foodvision/commons.py

Not part of the current model: Wikimedia throttles clients whose User-Agent
has no contact (https://meta.wikimedia.org/wiki/User-Agent_policy), so set
ANURJA_COMMONS_CONTACT to yours before running. Then extract features and
retrain as in README.md.

Every file is checked for its own free license (CC0, public domain, CC BY,
CC BY-SA); author, license and source page go to data/commons/credits.csv.
Labels come from the Commons category (and its subcategories two levels down,
minus ones about restaurants, shops, packaging and so on), so they are noisier
than Open Images' verified labels; the held-out test numbers include that noise.
The crawler waits 2 s between API calls (Wikimedia rate limits).
"""
import csv
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA = HERE / "data"
OUT = DATA / "commons"
API = "https://commons.wikimedia.org/w/api.php"
CONTACT = os.environ.get("ANURJA_COMMONS_CONTACT", "")
AGENT = f"AnurjaFoodDataset/0.1 ({CONTACT}) python-urllib"
MAX_PHOTOS = 400
MIN_PHOTOS = 80

# our label -> Commons categories
CLASSES = {
    # Korean
    "bibimbap": ["Bibimbap"], "bulgogi": ["Bulgogi"], "kimchi": ["Kimchi"], "tteokbokki": ["Tteokbokki"],
    "japchae": ["Japchae"], "gimbap": ["Gimbap"], "samgyeopsal": ["Samgyeopsal"],
    "korean_fried_chicken": ["Korean fried chicken"], "naengmyeon": ["Naengmyeon"], "jjigae": ["Jjigae"],
    # Japanese
    "sushi": ["Sushi"], "sashimi": ["Sashimi"], "ramen": ["Ramen"], "udon": ["Udon"], "soba": ["Soba"],
    "tempura": ["Tempura"], "onigiri": ["Onigiri"], "takoyaki": ["Takoyaki"], "gyoza": ["Gyoza"],
    "okonomiyaki": ["Okonomiyaki"], "miso_soup": ["Miso soup"], "tonkatsu": ["Tonkatsu"], "yakitori": ["Yakitori"],
    "donburi": ["Donburi"], "curry_rice": ["Japanese curry"],
    # Chinese
    "dim_sum": ["Dim sum"], "jiaozi": ["Jiaozi"], "xiaolongbao": ["Xiaolongbao"], "baozi": ["Baozi"],
    "chow_mein": ["Chow mein"], "fried_rice": ["Fried rice"], "peking_duck": ["Peking duck"],
    "mapo_tofu": ["Mapo doufu"], "wonton": ["Wonton"], "hot_pot": ["Hot pot"], "kung_pao_chicken": ["Kung Pao chicken"],
    "char_siu": ["Char siu"], "congee": ["Congee"], "spring_roll": ["Spring rolls"],
    # Mexican
    "taco": ["Tacos"], "burrito": ["Burritos"], "enchilada": ["Enchiladas"], "quesadilla": ["Quesadillas"],
    "nachos": ["Nachos"], "tamale": ["Tamales"], "churro": ["Churros"], "pozole": ["Pozole"],
    "chilaquiles": ["Chilaquiles"], "elote": ["Elote"], "guacamole": ["Guacamole"],
    # Thai / Vietnamese / SE Asian
    "pad_thai": ["Pad thai"], "pho": ["Phở"], "banh_mi": ["Bánh mì"], "tom_yum": ["Tom yum"], "satay": ["Satay"],
    "nasi_goreng": ["Nasi goreng"], "laksa": ["Laksa"], "green_curry": ["Green curry"], "som_tam": ["Som tam"],
    # Western / Middle Eastern
    "spaghetti": ["Spaghetti dishes"], "lasagne": ["Lasagne"], "steak": ["Steaks"], "fish_and_chips": ["Fish and chips"],
    "omelette": ["Omelettes"], "paella": ["Paella"], "risotto": ["Risotto"], "falafel": ["Falafel"],
    "hummus": ["Hummus"], "shawarma": ["Shawarma"], "fried_chicken": ["Fried chicken"],
    # Coffee and tea drinks
    "espresso": ["Espresso"], "cappuccino": ["Cappuccino"], "latte": ["Caffè latte", "Latte art"],
    "iced_coffee": ["Iced coffee"], "bubble_tea": ["Bubble tea"], "turkish_coffee": ["Turkish coffee"],
    "filter_coffee": ["Indian filter coffee"], "flat_white": ["Flat white"], "americano": ["Caffè Americano"],
    "macchiato": ["Caffè macchiato"], "mocha": ["Caffè mocha"], "matcha": ["Matcha"],
}
SKIP_SUBCATS = re.compile(
    r"restaurant|shop|store|stall|stand|truck|market|sign|logo|advert|packag|instant|vending|festival|museum|"
    r"people|chef|menu|map|drawing|illustration|art\b|icon|machine|maker|factory|brand|company|bar\b|caf[eé]s\b|"
    r"video|audio|text|book|poster|stamp|statue|sculpture|model|replica|toy|plastic|wax|"
    r"ingredient|preparation|cooking|making|plant|tree|field|farm", re.I)
FREE = re.compile(r"^(cc0|public domain|pd\b|pd-|cc[ -]by(-sa)?[ -]\d|cc-by(-sa)?-\d|attribution)", re.I)

_last = 0.0


def api(**params):
    global _last
    wait = 2.0 - (time.time() - _last)
    if wait > 0:
        time.sleep(wait)
    params |= {"format": "json", "maxlag": "5"}
    request = urllib.request.Request(f"{API}?{urllib.parse.urlencode(params)}", headers={"User-Agent": AGENT})
    while True:  # Wikimedia throttles bursts with 429 + Retry-After; wait it out
        try:
            with urllib.request.urlopen(request, timeout=60) as r:
                _last = time.time()
                body = json.load(r)
            if body.get("error", {}).get("code") == "maxlag":
                time.sleep(10)
                continue
            return body
        except urllib.error.HTTPError as error:
            _last = time.time()
            time.sleep(int(error.headers.get("Retry-After") or 30) + 2)
        except Exception as error:
            print("retry", error)
            time.sleep(30)


def members(category, kind):
    out, cont = [], {}
    while True:
        body = api(action="query", list="categorymembers", cmtitle=f"Category:{category}", cmtype=kind,
                   cmlimit="500", **cont)
        out += [m["title"] for m in body["query"]["categorymembers"]]
        if "continue" not in body:
            return out
        cont = {"cmcontinue": body["continue"]["cmcontinue"]}


def files_under(category, depth=2, seen=None):
    seen = seen if seen is not None else set()
    if category in seen:
        return []
    seen.add(category)
    files = [f for f in members(category, "file") if f.lower().endswith((".jpg", ".jpeg", ".png", ".webp"))]
    if depth:
        for sub in members(category, "subcat"):
            name = sub.removeprefix("Category:")
            if not SKIP_SUBCATS.search(name):
                files += files_under(name, depth - 1, seen)
    return files


def image_info(titles):
    """title -> (thumb url, license, artist, page) for freely licensed files."""
    info = {}
    for i in range(0, len(titles), 50):
        body = api(action="query", prop="imageinfo", titles="|".join(titles[i:i + 50]),
                   iiprop="url|extmetadata", iiurlwidth="500", iiextmetadatafilter="LicenseShortName|Artist")
        for page in body["query"].get("pages", {}).values():
            ii = (page.get("imageinfo") or [{}])[0]
            meta = ii.get("extmetadata", {})
            license = meta.get("LicenseShortName", {}).get("value", "")
            if "thumburl" in ii and FREE.search(license.strip()):
                artist = re.sub(r"<[^>]+>", "", meta.get("Artist", {}).get("value", "")).strip()
                info[page["title"]] = (ii["thumburl"], license, artist, ii.get("descriptionurl", ""))
    return info


def download(url):
    path = OUT / "photos" / (hashlib.sha1(url.encode()).hexdigest() + ".img")
    if not path.exists():
        request = urllib.request.Request(url, headers={"User-Agent": AGENT})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(request, timeout=60) as r:
                    path.write_bytes(r.read())
                break
            except Exception:
                time.sleep(5 * (attempt + 1))
        else:
            return None
    return path.read_bytes()


def main():
    if not CONTACT:
        sys.exit("Set ANURJA_COMMONS_CONTACT (URL or email) first: Wikimedia's User-Agent policy needs it.")
    sys.path.insert(0, str(HERE))  # our own prepare.py (python -I leaves the script dir out)
    from prepare import normalise, split_and_write

    (OUT / "photos").mkdir(parents=True, exist_ok=True)
    index_path = OUT / "index.json"
    index = json.loads(index_path.read_text()) if index_path.exists() else {}
    for label, categories in CLASSES.items():
        if label in index:
            continue
        titles = []
        for category in categories:
            titles += [t for t in files_under(category) if t not in titles]
        info = image_info(titles[: MAX_PHOTOS * 2])
        index[label] = [[t, *info[t]] for t in titles if t in info][:MAX_PHOTOS]
        index_path.write_text(json.dumps(index))
        print(f"{label:22} {len(index[label])} free photos")

    # A file filed under two of our dishes is ambiguous: drop it.
    owners = {}
    for label, rows in index.items():
        for row in rows:
            owners.setdefault(row[0], set()).add(label)
    jobs = [(label, row) for label, rows in index.items() if len(rows) >= MIN_PHOTOS
            for row in rows if len(owners[row[0]]) == 1]
    photos = {}
    with ThreadPoolExecutor(2) as pool:
        for (label, row), data in zip(jobs, pool.map(lambda j: download(j[1][1]), jobs)):
            if data and (photo := normalise(data)):
                photos[hashlib.sha1(data).hexdigest()] = (label, *photo)
    counts = split_and_write(DATA, photos)
    (OUT / "split.json").write_text(json.dumps({"source": "Wikimedia Commons, freely licensed files", "counts": counts}, indent=1))
    with open(OUT / "credits.csv", "w", newline="", encoding="utf-8") as f:
        out = csv.writer(f)
        out.writerow(["label", "file", "license", "author", "source"])
        for label, row in jobs:
            out.writerow([label, row[0], row[2], row[3], row[4]])


if __name__ == "__main__":
    main()
