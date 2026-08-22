#!/usr/bin/env python3
"""Wait for the newest phone build to finish processing, then put it in front of
the internal testers. Run with no arguments after an upload."""
import json
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc import BASE, token  # noqa: E402

BUNDLE = "com.kasparov.dshstudio.phone"
TESTER = "kasparovabi@gmail.com"
GROUP = "Ekip"


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(BASE + path, data=data, method=method)
    request.add_header("Authorization", f"Bearer {token()}")
    request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read()
            return response.status, json.loads(raw or b"{}")
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            return error.code, json.loads(raw or b"{}")
        except json.JSONDecodeError:
            return error.code, {"raw": raw.decode(errors="replace")}


def app_id():
    _, data = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")
    items = data.get("data") or []
    return items[0]["id"] if items else None


def newest_build(app, want=None):
    query = f"&filter[version]={want}" if want else ""
    _, data = call(
        "GET",
        f"/v1/builds?filter[app]={app}&sort=-version&limit=1{query}"
        "&fields[builds]=version,processingState,expired",
    )
    items = data.get("data") or []
    return items[0] if items else None


def main() -> int:  # noqa: C901
    app = app_id()
    if not app:
        print("app record missing")
        return 1
    print("app", app)

    want = sys.argv[1] if len(sys.argv) > 1 else None
    build = None
    for attempt in range(60):
        build = newest_build(app, want)
        state = build["attributes"]["processingState"] if build else "no build yet"
        print(f"[{attempt}] {state}")
        if build and state == "VALID":
            break
        if build and state in {"INVALID", "FAILED"}:
            print("processing failed")
            return 1
        time.sleep(30)
    if not build or build["attributes"]["processingState"] != "VALID":
        print("still processing, run again later")
        return 1

    build_id = build["id"]
    print("build", build["attributes"]["version"], build_id)

    _, data = call("GET", f"/v1/apps/{app}/betaGroups?fields[betaGroups]=name,isInternalGroup")
    group = next((g["id"] for g in data.get("data", []) if g["attributes"].get("isInternalGroup")), None)
    if not group:
        status, data = call("POST", "/v1/betaGroups", {
            "data": {
                "type": "betaGroups",
                "attributes": {"name": GROUP, "isInternalGroup": True},
                "relationships": {"app": {"data": {"type": "apps", "id": app}}},
            }
        })
        print("group create", status)
        group = data.get("data", {}).get("id")
    print("group", group)

    status, data = call("POST", f"/v1/betaGroups/{group}/relationships/builds", {
        "data": [{"type": "builds", "id": build_id}]
    })
    print("build to group", status, json.dumps(data)[:200])

    status, data = call("POST", "/v1/betaTesters", {
        "data": {
            "type": "betaTesters",
            "attributes": {"email": TESTER, "firstName": "DSH", "lastName": "Tester"},
            "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group}]}},
        }
    })
    print("tester", status, json.dumps(data)[:200])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
