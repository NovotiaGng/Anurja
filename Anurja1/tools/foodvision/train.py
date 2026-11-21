"""Train Anurja/FoodModels/FoodClassifier.mlmodel on Vision feature prints.

    python3 -I tools/foodvision/prepare.py                  # Indian dishes -> data/{train,val,test}
    python3 -I tools/foodvision/openimages.py fetch         # world dishes, fruit, drinks -> same folders
    swiftc -O -o /tmp/food-features tools/foodvision/ExtractFeatures.swift && /tmp/food-features
    uv run -p 3.12 --with coremltools==9.0 --with scikit-learn==1.5.2 python -I tools/foodvision/train.py

Fits a softmax classifier and a one-hidden-layer MLP on the 768-float feature
prints, keeps whichever is more accurate on val, picks the app's confidence
threshold on val, then reports top-1 / top-3 per dish on the held-out test
photos (tools/foodvision/report.json). The .mlmodel takes the feature print
("featurePrint", 768 floats) and returns "classLabel" and "classLabelProbs".

(Create ML's MLImageClassifier would be simpler, but on macOS 27 it fails on
the full set with "Failed to create CVPixelBufferPool".)
"""
import json
import sys
from pathlib import Path

import coremltools as ct
import numpy as np
from coremltools.models import datatypes
from coremltools.models.neural_network import NeuralNetworkBuilder
from sklearn.linear_model import LogisticRegression
from sklearn.neural_network import MLPClassifier

HERE = Path(__file__).resolve().parent
DATA = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "data"
OUT = HERE.parent.parent / "Anurja/FoodModels/FoodClassifier.mlmodel"
TARGET_PRECISION = 0.95  # accepted val photos must be right this often


def load(split):
    x = np.fromfile(DATA / f"{split}.f32", dtype=np.float32).reshape(-1, 768)
    y = np.array((DATA / f"{split}.labels").read_text().split("\n"))
    return x, y


def layers(model):
    """(weights, biases) per dense layer, as numpy arrays (in x out)."""
    if isinstance(model, LogisticRegression):
        return [(model.coef_.T, model.intercept_)]
    return list(zip(model.coefs_, model.intercepts_))


def export(model, mean, std, classes, threshold, meta):
    dense = layers(model)
    # Fold the standardisation into the first layer: W' = W / std, b' = b - mean/std @ W.
    w0, b0 = dense[0]
    dense[0] = (w0 / std[:, None], b0 - (mean / std) @ w0)
    builder = NeuralNetworkBuilder(
        [("featurePrint", datatypes.Array(768))], [("classLabelProbs", datatypes.Array(len(classes)))],
        mode="classifier")
    name = "featurePrint"
    for i, (w, b) in enumerate(dense):
        builder.add_inner_product(f"dense{i}", W=w.T.astype(np.float32), b=b.astype(np.float32),
                                  input_channels=w.shape[0], output_channels=w.shape[1], has_bias=True,
                                  input_name=name, output_name=f"dense{i}_out")
        name = f"dense{i}_out"
        if i < len(dense) - 1:
            builder.add_activation(f"relu{i}", "RELU", name, f"relu{i}_out")
            name = f"relu{i}_out"
    builder.add_softmax("softmax", name, "classLabelProbs")
    builder.set_class_labels(list(classes), predicted_feature_name="classLabel",
                             prediction_blob="classLabelProbs")
    mlmodel = ct.models.MLModel(builder.spec)
    mlmodel.short_description = meta["description"]
    mlmodel.license = meta["license"]
    mlmodel.author = "Anurja"
    mlmodel.version = "1"
    # FoodRecognizer reads this: lowest top-label confidence the app trusts.
    mlmodel.user_defined_metadata["threshold"] = str(threshold)
    mlmodel.input_description["featurePrint"] = "VNGenerateImageFeaturePrintRequest revision 2 of the photo"
    OUT.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(OUT))
    return mlmodel


def main():
    xtr, ytr = load("train")
    xva, yva = load("val")
    xte, yte = load("test")
    mean, std = xtr.mean(0), xtr.std(0) + 1e-6
    norm = lambda x: (x - mean) / std

    candidates = []
    for c in (0.01, 0.03, 0.1):
        candidates.append((f"logistic C={c}", LogisticRegression(C=c, max_iter=10000)))
    for h in (512,):
        candidates.append((f"mlp {h}", MLPClassifier(hidden_layer_sizes=(h,), alpha=1e-3, early_stopping=True,
                                                     max_iter=200, random_state=7)))
    best = None
    for name, model in candidates:
        model.fit(norm(xtr), ytr)
        acc = (model.predict(norm(xva)) == yva).mean()
        print(f"{name:16} val top-1 {acc:.3f}")
        if best is None or acc > best[2]:
            best = (name, model, acc)
    name, model, _ = best
    classes = model.classes_
    print("keeping", name)

    # Confidence threshold on val.
    pva = model.predict_proba(norm(xva))
    top, conf = classes[pva.argmax(1)], pva.max(1)
    threshold = 0.95
    for t in np.arange(0.05, 0.96, 0.01):
        keep = conf >= t
        if keep.any() and (top[keep] == yva[keep]).mean() >= TARGET_PRECISION:
            threshold = round(float(t), 2)
            break

    revision = json.loads((DATA / "split.json").read_text())["revision"]
    mlmodel = export(model, mean, std, classes, threshold, {
        "description": f"Dish, fruit and drink classifier ({len(classes)} classes) on Vision feature prints. Labels map onto FoodLibrary in FoodLibrary.swift.",
        "license": f"Trained on SohlHealth/enhanced-indian-food-classification (CC BY 4.0, revision {revision}) and Open Images V7 verified labels (CC BY 4.0) on Flickr photos (CC BY 2.0, credits in tools/foodvision/openimages_credits.csv).",
    })

    # Evaluate the saved .mlmodel itself (Core ML), not the sklearn object.
    rows = [mlmodel.predict({"featurePrint": x.astype(np.float32)})["classLabelProbs"] for x in xte]
    ranked = [sorted(r, key=r.get, reverse=True) for r in rows]
    confs = np.array([r[k[0]] for r, k in zip(rows, ranked)])
    top1 = np.array([k[0] == y for k, y in zip(ranked, yte)])
    top3 = np.array([y in k[:3] for k, y in zip(ranked, yte)])
    keep = confs >= threshold
    per_dish = []
    for dish in sorted(set(yte)):
        m = yte == dish
        per_dish.append({"dish": dish, "photos": int(m.sum()),
                         "top1": round(float(top1[m].mean()), 3), "top3": round(float(top3[m].mean()), 3)})
        print(f"{dish:16} n={m.sum():3}  top-1 {100 * top1[m].mean():5.1f}%  top-3 {100 * top3[m].mean():5.1f}%")
    report = {
        "dataset": "SohlHealth/enhanced-indian-food-classification (CC BY 4.0) + Open Images V7 verified labels (Flickr, CC BY 2.0)",
        "revision": revision,
        "model": name,
        "test_photos": int(len(yte)),
        "top1": round(float(top1.mean()), 3),
        "top3": round(float(top3.mean()), 3),
        "threshold": threshold,
        "threshold_coverage": round(float(keep.mean()), 3),
        "threshold_precision": round(float(top1[keep].mean()), 3),
        "per_dish": per_dish,
    }
    (HERE / "report.json").write_text(json.dumps(report, indent=1) + "\n")
    print(f"test top-1 {top1.mean():.3f}  top-3 {top3.mean():.3f}  threshold {threshold} keeps "
          f"{keep.mean():.3f} at precision {top1[keep].mean():.3f}")


if __name__ == "__main__":
    main()
