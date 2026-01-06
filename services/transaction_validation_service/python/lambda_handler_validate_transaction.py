from __future__ import annotations

import json
from typing import Any, Dict

from validate_transaction_payload import validate_request


def _response(status_code: int, body: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda entrypoint.
    Supports API Gateway proxy integration where JSON is in event["body"].
    """
    try:
        if "body" in event and isinstance(event["body"], str):
            payload = json.loads(event["body"])
        else:
            payload = event  # allow direct invoke with dict payload
    except Exception:
        return _response(
            400,
            {
                "request_id": None,
                "is_valid": False,
                "normalized_transaction": None,
                "validation_errors": [{"field": "request", "message": "Invalid JSON body"}],
            },
        )

    result = validate_request(payload)
    status = 200 if result["is_valid"] else 400
    return _response(status, result)
