#!/usr/bin/env python3
"""Scrub a JSONL transcript into a fixture: keep structure and numbers, replace strings.

Strings in known-safe key positions (type, role, model, id-ish keys, timestamps,
cwd leaf, entrypoint, enums) are kept. Every other string becomes "x" * min(len, 8).
Usage: scrub-fixture.py <in.jsonl> <out.jsonl> [--keep N]
"""
import json, sys, re

KEEP_KEYS = {
    "type", "subtype", "role", "model", "id", "uuid", "parentUuid", "sessionId",
    "session_id", "requestId", "timestamp", "_audit_timestamp", "entrypoint",
    "version", "service_tier", "stop_reason", "name", "status", "kind",
    "limit_id", "limit_name", "plan_type", "model_provider", "originator",
    "source", "cwd", "projectHash", "startTime", "lastUpdated", "speed",
    "inference_geo", "rateLimitType", "payload_type", "event_type", "ttl",
}
ISO = re.compile(r"^\d{4}-\d{2}-\d{2}T")

def scrub(obj, key=None):
    if isinstance(obj, dict):
        return {k: scrub(v, k) for k, v in obj.items()}
    if isinstance(obj, list):
        return [scrub(v, key) for v in obj]
    if isinstance(obj, str):
        if key in KEEP_KEYS or ISO.match(obj):
            if key == "cwd":
                return "/Users/fixture/REPOS/" + obj.rstrip("/").split("/")[-1]
            return obj
        return "x" * min(len(obj), 8)
    return obj

def main():
    src, dst = sys.argv[1], sys.argv[2]
    keep = int(sys.argv[sys.argv.index("--keep") + 1]) if "--keep" in sys.argv else None
    out = []
    with open(src) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.dumps(scrub(json.loads(line)), separators=(",", ":")))
            except json.JSONDecodeError:
                continue
            if keep and len(out) >= keep:
                break
    with open(dst, "w") as f:
        f.write("\n".join(out) + "\n")
    print(f"{len(out)} lines -> {dst}")

if __name__ == "__main__":
    main()
