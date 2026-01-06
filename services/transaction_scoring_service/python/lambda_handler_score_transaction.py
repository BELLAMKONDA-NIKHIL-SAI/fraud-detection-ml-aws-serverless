from __future__ import annotations

import json
from typing import Any, Dict

from score_transaction_payload import score_transaction_request


def _response(status_code: int, body: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    try:
        if "body" in event and isinstance(event["body"], str):
            payload = json.loads(event["body"])
        else:
            payload = event
    except Exception:
        return _response(400, {"error": "Invalid JSON body"})

    result = score_transaction_request(payload)
    status = 200 if result.get("error") is None else 400
    return _response(status, result)
