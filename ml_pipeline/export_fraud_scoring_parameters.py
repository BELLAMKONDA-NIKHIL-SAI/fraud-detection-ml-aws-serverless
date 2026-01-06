from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List

import joblib
import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MODELS_DIR = PROJECT_ROOT / "models"
REPORTS_DIR = PROJECT_ROOT / "reports"


def main() -> None:
    latest_model_path = MODELS_DIR / "fraud_model_pipeline_latest.joblib"
    if not latest_model_path.exists():
        raise FileNotFoundError(f"Missing {latest_model_path}. Run: python ml_pipeline/train_fraud_model.py")

    artifact: Dict[str, Any] = joblib.load(latest_model_path)
    pipeline = artifact["pipeline"]
    model_version = artifact["model_version"]
    threshold = float(artifact["decision_threshold"])
    feature_spec = artifact["feature_spec"]

    preprocess = pipeline.named_steps["preprocess"]
    model = pipeline.named_steps["model"]

    # ColumnTransformer parts
    num_transformer = preprocess.named_transformers_["num"]
    cat_transformer = preprocess.named_transformers_["cat"]

    numeric_features: List[str] = feature_spec["numeric"]
    categorical_features: List[str] = feature_spec["categorical"]

    # StandardScaler parameters
    num_mean = num_transformer.mean_.tolist()
    num_scale = num_transformer.scale_.tolist()

    # OneHotEncoder categories (list per categorical feature)
    categories = [list(map(lambda x: bool(x) if isinstance(x, (np.bool_, bool)) else x, cats))
                  for cats in cat_transformer.categories_]

    # Model coefficients
    coef = model.coef_.ravel().tolist()
    intercept = float(model.intercept_[0])

    export = {
        "model_version": model_version,
        "decision_threshold": threshold,
        "exported_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "numeric_features": numeric_features,
        "categorical_features": categorical_features,
        "numeric_scaler": {
            "mean": num_mean,
            "scale": num_scale
        },
        "one_hot_categories": {
            feat: cats for feat, cats in zip(categorical_features, categories)
        },
        "logistic_regression": {
            "coefficients": coef,
            "intercept": intercept
        }
    }

    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    out_path = REPORTS_DIR / "fraud_scoring_parameters_latest.json"
    out_path.write_text(json.dumps(export, indent=2), encoding="utf-8")
    print("Saved:", out_path)


if __name__ == "__main__":
    main()
