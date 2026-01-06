from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Tuple

import joblib
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, classification_report
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MODELS_DIR = PROJECT_ROOT / "models"
REPORTS_DIR = PROJECT_ROOT / "reports"


def _generate_synthetic_transactions(n: int = 50000, seed: int = 42) -> pd.DataFrame:
    """
    Generates a synthetic fraud dataset with imbalanced labels.
    This is used to start from scratch and keep the project runnable without external datasets.
    You can later swap in a real dataset without changing the service contract.
    """
    rng = np.random.default_rng(seed)

    amount = rng.lognormal(mean=4.0, sigma=0.8, size=n)  # heavy tail amounts
    amount = np.clip(amount, 1, 5000)

    currency = rng.choice(["CAD", "USD"], size=n, p=[0.85, 0.15])
    merchant_category = rng.choice(
        ["grocery", "electronics", "fuel", "travel", "restaurants", "online_services"],
        size=n,
        p=[0.25, 0.15, 0.2, 0.08, 0.2, 0.12],
    )
    channel = rng.choice(
        ["card_present", "card_not_present", "online", "atm", "transfer"],
        size=n,
        p=[0.45, 0.15, 0.25, 0.08, 0.07],
    )
    country = rng.choice(["CA", "US", "MX", "GB"], size=n, p=[0.82, 0.12, 0.03, 0.03])

    customer_age = rng.integers(18, 80, size=n)
    account_age_days = rng.integers(0, 3650, size=n)

    transactions_last_24h = rng.poisson(lam=3, size=n)
    avg_amount_last_7d = rng.lognormal(mean=3.4, sigma=0.6, size=n)
    avg_amount_last_7d = np.clip(avg_amount_last_7d, 1, 2000)

    is_international = (country != "CA")

    # Fraud probability model (synthetic):
    # More likely when: high amount, international, new accounts, many txns, online/channel risk, electronics/travel
    risk = (
        0.0025 * (amount - 50)
        + 0.9 * is_international.astype(int)
        + 0.6 * (account_age_days < 60).astype(int)
        + 0.12 * np.clip(transactions_last_24h - 3, 0, None)
        + 0.35 * np.isin(channel, ["online", "transfer"]).astype(int)
        + 0.35 * np.isin(merchant_category, ["electronics", "travel", "online_services"]).astype(int)
        + 0.12 * (currency == "USD").astype(int)
    )

    # Convert risk to probability and sample labels with strong imbalance
    logits = -6.5 + risk  # controls base rate
    prob = 1 / (1 + np.exp(-logits))
    y = rng.binomial(1, prob, size=n)

    df = pd.DataFrame(
        {
            "amount": amount,
            "currency": currency,
            "merchant_category": merchant_category,
            "channel": channel,
            "country": country,
            "customer_age": customer_age,
            "account_age_days": account_age_days,
            "transactions_last_24h": transactions_last_24h,
            "avg_amount_last_7d": avg_amount_last_7d,
            "is_international": is_international.astype(bool),
            "is_fraud": y.astype(int),
        }
    )
    return df


def _build_pipeline() -> Tuple[Pipeline, Dict[str, list]]:
    numeric_features = [
        "amount",
        "customer_age",
        "account_age_days",
        "transactions_last_24h",
        "avg_amount_last_7d",
    ]
    categorical_features = ["currency", "merchant_category", "channel", "country", "is_international"]

    preprocessor = ColumnTransformer(
        transformers=[
            ("num", StandardScaler(), numeric_features),
            ("cat", OneHotEncoder(handle_unknown="ignore"), categorical_features),
        ]
    )

    clf = LogisticRegression(max_iter=2000, class_weight="balanced")
    pipeline = Pipeline(steps=[("preprocess", preprocessor), ("model", clf)])

    feature_spec = {"numeric": numeric_features, "categorical": categorical_features}
    return pipeline, feature_spec


def main() -> None:
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)

    df = _generate_synthetic_transactions(n=60000, seed=7)
    y = df["is_fraud"]
    X = df.drop(columns=["is_fraud"])

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    pipeline, feature_spec = _build_pipeline()
    pipeline.fit(X_train, y_train)

    proba = pipeline.predict_proba(X_test)[:, 1]
    ap = float(average_precision_score(y_test, proba))

    # Default threshold 0.5; we’ll tune later
    preds = (proba >= 0.5).astype(int)
    report = classification_report(y_test, preds, output_dict=True)

    model_version = datetime.now(timezone.utc).strftime("%Y-%m-%d_%H%M%S")
    model_path = MODELS_DIR / f"fraud_model_pipeline_{model_version}.joblib"
    latest_path = MODELS_DIR / "fraud_model_pipeline_latest.joblib"

    joblib.dump(
        {
            "model_version": model_version,
            "decision_threshold": 0.5,
            "feature_spec": feature_spec,
            "pipeline": pipeline,
        },
        model_path,
    )
    joblib.dump(
        {
            "model_version": model_version,
            "decision_threshold": 0.5,
            "feature_spec": feature_spec,
            "pipeline": pipeline,
        },
        latest_path,
    )

    metrics = {
        "model_version": model_version,
        "average_precision_pr_auc": ap,
        "classification_report_at_threshold_0_5": report,
        "label_rate": float(y.mean()),
    }
    (REPORTS_DIR / "training_metrics_latest.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    print("Saved model:", model_path)
    print("Saved latest model:", latest_path)
    print("PR-AUC (Average Precision):", round(ap, 4))
    print("Fraud rate in dataset:", round(float(y.mean()), 5))


if __name__ == "__main__":
    main()
