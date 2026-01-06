from __future__ import annotations

import re
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple


@dataclass(frozen=True)
class ValidationErrorItem:
    field: str
    message: str


_ALLOWED_CHANNELS = {"card_present", "card_not_present", "online", "atm", "transfer"}
_CURRENCY_RE = re.compile(r"^[A-Z]{3}$")
_COUNTRY_RE = re.compile(r"^[A-Z]{2}$")


_REQUIRED_TRANSACTION_FIELDS = [
    "transaction_id",
    "event_time_utc",
    "amount",
    "currency",
    "merchant_category",
    "channel",
    "country",
    "customer_age",
    "account_age_days",
    "transactions_last_24h",
    "avg_amount_last_7d",
    "is_international",
]


def _parse_utc_datetime(value: str) -> Optional[str]:
    try:
        if value.endswith("Z"):
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        else:
            dt = datetime.fromisoformat(value)

        dt_utc = dt.astimezone(timezone.utc)
        return dt_utc.replace(microsecond=0).isoformat().replace("+00:00", "Z")
    except Exception:
        return None


def _validate_top_level(payload: Dict[str, Any]) -> List[ValidationErrorItem]:
    errors: List[ValidationErrorItem] = []

    if not isinstance(payload, dict):
        return [ValidationErrorItem("request", "request must be a JSON object")]

    if "transaction" not in payload:
        errors.append(ValidationErrorItem("transaction", "Missing required field: transaction"))
        return errors

    if not isinstance(payload["transaction"], dict):
        errors.append(ValidationErrorItem("transaction", "transaction must be an object"))
        return errors

    return errors


def _normalize_and_validate_transaction(txn: Dict[str, Any]) -> Tuple[Optional[Dict[str, Any]], List[ValidationErrorItem]]:
    errors: List[ValidationErrorItem] = []
    normalized = dict(txn)

    # Required fields presence
    for f in _REQUIRED_TRANSACTION_FIELDS:
        if f not in normalized:
            errors.append(ValidationErrorItem(f"transaction.{f}", f"Missing required field: {f}"))

    if errors:
        return None, errors

    # transaction_id
    if not isinstance(normalized["transaction_id"], str) or not normalized["transaction_id"].strip():
        errors.append(ValidationErrorItem("transaction.transaction_id", "transaction_id must be a non-empty string"))
    else:
        normalized["transaction_id"] = normalized["transaction_id"].strip()

    # event_time_utc
    if not isinstance(normalized["event_time_utc"], str):
        errors.append(ValidationErrorItem("transaction.event_time_utc", "event_time_utc must be a string"))
    else:
        parsed = _parse_utc_datetime(normalized["event_time_utc"].strip())
        if parsed is None:
            errors.append(ValidationErrorItem("transaction.event_time_utc", "event_time_utc must be ISO 8601 (e.g., 2026-01-05T21:15:00Z)"))
        else:
            normalized["event_time_utc"] = parsed

    # amount
    if not isinstance(normalized["amount"], (int, float)):
        errors.append(ValidationErrorItem("transaction.amount", "amount must be a number"))
    else:
        if float(normalized["amount"]) <= 0:
            errors.append(ValidationErrorItem("transaction.amount", "amount must be > 0"))
        normalized["amount"] = float(normalized["amount"])

    # currency
    if not isinstance(normalized["currency"], str):
        errors.append(ValidationErrorItem("transaction.currency", "currency must be a string"))
    else:
        normalized["currency"] = normalized["currency"].strip().upper()
        if not _CURRENCY_RE.match(normalized["currency"]):
            errors.append(ValidationErrorItem("transaction.currency", "currency must be a 3-letter uppercase code (e.g., CAD)"))

    # merchant_category
    if not isinstance(normalized["merchant_category"], str):
        errors.append(ValidationErrorItem("transaction.merchant_category", "merchant_category must be a string"))
    else:
        normalized["merchant_category"] = normalized["merchant_category"].strip().lower()
        if not normalized["merchant_category"]:
            errors.append(ValidationErrorItem("transaction.merchant_category", "merchant_category must not be empty"))

    # channel
    if not isinstance(normalized["channel"], str):
        errors.append(ValidationErrorItem("transaction.channel", "channel must be a string"))
    else:
        normalized["channel"] = normalized["channel"].strip().lower()
        if normalized["channel"] not in _ALLOWED_CHANNELS:
            errors.append(ValidationErrorItem("transaction.channel", f"channel must be one of: {sorted(_ALLOWED_CHANNELS)}"))

    # country
    if not isinstance(normalized["country"], str):
        errors.append(ValidationErrorItem("transaction.country", "country must be a string"))
    else:
        normalized["country"] = normalized["country"].strip().upper()
        if not _COUNTRY_RE.match(normalized["country"]):
            errors.append(ValidationErrorItem("transaction.country", "country must be a 2-letter uppercase code (e.g., CA)"))

    # customer_age
    if not isinstance(normalized["customer_age"], int):
        errors.append(ValidationErrorItem("transaction.customer_age", "customer_age must be an integer"))
    else:
        if not (13 <= normalized["customer_age"] <= 120):
            errors.append(ValidationErrorItem("transaction.customer_age", "customer_age must be between 13 and 120"))

    # account_age_days
    if not isinstance(normalized["account_age_days"], int):
        errors.append(ValidationErrorItem("transaction.account_age_days", "account_age_days must be an integer"))
    else:
        if normalized["account_age_days"] < 0:
            errors.append(ValidationErrorItem("transaction.account_age_days", "account_age_days must be >= 0"))

    # transactions_last_24h
    if not isinstance(normalized["transactions_last_24h"], int):
        errors.append(ValidationErrorItem("transaction.transactions_last_24h", "transactions_last_24h must be an integer"))
    else:
        if normalized["transactions_last_24h"] < 0:
            errors.append(ValidationErrorItem("transaction.transactions_last_24h", "transactions_last_24h must be >= 0"))

    # avg_amount_last_7d
    if not isinstance(normalized["avg_amount_last_7d"], (int, float)):
        errors.append(ValidationErrorItem("transaction.avg_amount_last_7d", "avg_amount_last_7d must be a number"))
    else:
        if float(normalized["avg_amount_last_7d"]) < 0:
            errors.append(ValidationErrorItem("transaction.avg_amount_last_7d", "avg_amount_last_7d must be >= 0"))
        normalized["avg_amount_last_7d"] = float(normalized["avg_amount_last_7d"])

    # is_international
    if not isinstance(normalized["is_international"], bool):
        errors.append(ValidationErrorItem("transaction.is_international", "is_international must be a boolean"))

    return (normalized if not errors else None), errors


def validate_request(payload: Dict[str, Any]) -> Dict[str, Any]:
    req_id = payload.get("request_id") if isinstance(payload.get("request_id"), str) else None
    request_id = req_id or str(uuid.uuid4())

    top_errors = _validate_top_level(payload)
    if top_errors:
        return {
            "request_id": request_id,
            "is_valid": False,
            "normalized_transaction": None,
            "validation_errors": [{"field": e.field, "message": e.message} for e in top_errors],
        }

    txn = payload["transaction"]
    normalized_txn, txn_errors = _normalize_and_validate_transaction(txn)

    is_valid = normalized_txn is not None and not txn_errors
    return {
        "request_id": request_id,
        "is_valid": is_valid,
        "normalized_transaction": normalized_txn if is_valid else None,
        "validation_errors": [{"field": e.field, "message": e.message} for e in txn_errors],
    }
