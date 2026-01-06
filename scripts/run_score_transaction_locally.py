import json
import sys
from pathlib import Path

sys.path.append(str(Path(__file__).resolve().parents[1] / "services" / "transaction_scoring_service"))
from score_transaction_payload import score_transaction_request  # noqa: E402


def main():
    sample_path = Path("scripts/sample_requests/score_transaction_example.json")
    payload = json.loads(sample_path.read_text(encoding="utf-8"))
    result = score_transaction_request(payload)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
