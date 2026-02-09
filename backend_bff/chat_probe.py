import argparse
import json
import os

import httpx
from dotenv import load_dotenv


def main() -> int:
    load_dotenv()

    parser = argparse.ArgumentParser(description="Send a prompt to the BFF /plan endpoint and print the reply")
    parser.add_argument("prompt", nargs="?", default="Plan a trip from Main Station to Central Park at 5pm with minimal transfers")
    parser.add_argument("--url", default=os.getenv("BFF_URL", "http://localhost:8001/plan"), help="BFF /plan URL")
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--max-tokens", type=int, default=160, dest="max_tokens")
    args = parser.parse_args()

    payload = {"prompt": args.prompt, "temperature": args.temperature, "max_tokens": args.max_tokens}

    print(f"POST {args.url}\nPayload: {json.dumps(payload)}\n")
    try:
        resp = httpx.post(args.url, json=payload, timeout=30)
    except Exception as exc:  # noqa: BLE001
        print(f"Request failed: {exc}")
        return 1

    print(f"Status: {resp.status_code}")
    try:
        body = resp.json()
    except Exception:  # noqa: BLE001
        body = resp.text
    print(f"Body: {body}")

    if resp.status_code != 200:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())