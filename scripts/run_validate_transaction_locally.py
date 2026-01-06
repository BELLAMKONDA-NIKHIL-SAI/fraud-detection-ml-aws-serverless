import json
import sys
from pathlib import Path

# Import the validator directly from the service folder
sys.path.append(str(Path(__file__).resolve().parents[1] / "services" / "transaction_validation_service"))
from validate_transaction_payload import validate_request  # noqa: E402


def main():
    sample_path = Path("scripts/sample_requests/validate_transaction_example.json")
    payload = json.loads(sample_path.read_text(encoding="utf-8"))
    result = validate_request(payload)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
