"""Builds 'Anurja - app preview.html' from tools/preview_template.html with the
trained model weights and the food library baked in.
Run from Anurja1/:  python tools/build_preview.py"""
import json
from pathlib import Path

import joblib

ROOT = Path(__file__).resolve().parent.parent
BACKEND = ROOT.parent / "backend"
models = {}
for name in ("rise", "activity"):
    pipe = joblib.load(BACKEND / "models" / f"{name}.joblib")
    sc, m = pipe.named_steps["scale"], pipe.named_steps["model"]
    models[name] = {"mean": sc.mean_.round(6).tolist(), "scale": sc.scale_.round(6).tolist(),
                    "w1": m.coefs_[0].round(6).tolist(), "b1": m.intercepts_[0].round(6).tolist(),
                    "w2": m.coefs_[1].round(6).tolist(), "b2": m.intercepts_[1].round(6).tolist()}
foods = json.loads((BACKEND / "data" / "foods.json").read_text(encoding="utf-8"))
html = (ROOT / "tools" / "preview_template.html").read_text(encoding="utf-8")
html = html.replace("/*MODELS*/null", json.dumps(models, separators=(",", ":")))
html = html.replace("/*FOODS*/null", json.dumps(foods, separators=(",", ":"), ensure_ascii=False))
html = html.replace('"../Anurja/Assets.xcassets', '"Anurja/Assets.xcassets')
out = ROOT / "Anurja - app preview.html"
out.write_text(html, encoding="utf-8", newline="\n")
print("wrote", out)
