#!/usr/bin/env python3
"""Retrieve deployed Merk of Duty Pages files, not the original Git repository.

Without --api-token this downloads the known gameplay modules and crawls their
literal asset references. With a Cloudflare API token authorized for Pages read,
this retrieves the exact deployment file list (1,374 paths on Sep 22 2026).

Usage:
  python3 recover_pages.py
  python3 recover_pages.py --api-token "$CLOUDFLARE_API_TOKEN"
  python3 recover_pages.py --manifest paths.json
"""

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
from pathlib import Path
import re
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlparse
from urllib.request import Request, urlopen

ACCOUNT = "4849dbcd8936affb36d171c65063d746"
PROJECT = "merk-of-duty"
DEPLOYMENT = "56538cf3-a994-4f0f-9379-368a18d207ff"
BASE = "https://56538cf3.merk-of-duty.pages.dev"
CORE = """
/index.html
/asset-catalog.js /asset-runtime.js /collision-world.js /destructibles.js
/enemy-system.js /enemy-tactics.js /free-for-all-match.js /frontend.js
/graphics-renderer.js /graphics-settings.js /grenades.js /gunplay.js
/hosted-assets.js /hud.js /light-probes.js /lighting.js /load-gltf.js
/loadout-attachments.js /lobby.js /maps.js /medals.js /merk-shell.js
/movement-settings.js /mystery-box.js /navigation.js /normal-modes.js
/notetracks.js /play-counter.js /player-controller.js /player-health.js
/ranked-ui.js /ranked.js /ray-gun.js /realtime-client.js
/scene-optimizer.js /settings-runtime.js /skins.js /sw.js
/team-deathmatch-match.js /touch-controls.js /view-bob.js /viewmodel.js
/weapon-ballistics.js /weapon-controller.js /weapon-effects.js
/weapons.js /world-audio.js /zombies.js
/lobby.css /touch-controls.css
/nuketown_2020_optimized.glb /nuketown_2020_optimized.buffer-0.bin
/nuketown_2020_optimized.buffer-1.bin
/nuketown_2020.navmesh.bin /nuketown_2020.navmesh.json
/nuketown_2020_collision_bvh.bin /nuketown_2020_collision_bvh.json
/nuketown_2020_probes.bin /nuketown_2020_probes.json
/hijacked.navmesh.json /hijacked_collision_bvh.json
/crash.navmesh.json /crash_collision_bvh.json
/firing_range.navmesh.json /firing_range_collision_bvh.json
/killhouse.navmesh.json /killhouse_collision_bvh.json
""".split()

# Matches explicit asset filenames in JavaScript, CSS and HTML. Generated paths
# or directory-wide sprite collections are not guaranteed to be discovered.
REFERENCES = re.compile(r"(?P<path>[./\w~@-]+\.(?:js|css|html|json|png|webp|jpg|jpeg|glb|bin|wav|flac|mp3|ogg))\b", re.I)
PARSE_SUFFIXES = {".js", ".html", ".css", ".json"}


def download(url, token=None):
    headers = {"User-Agent": "MerkOfDutySourceRecovery/1.0"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    for attempt in range(3):
        try:
            with urlopen(Request(url, headers=headers), timeout=40) as res:
                return res.read(), res.headers.get("Content-Type", "")
        except (HTTPError, URLError, TimeoutError) as exc:
            if attempt == 2:
                raise exc
            time.sleep(1 + attempt * 2)


def cloudflare_manifest(token):
    url = ("https://api.cloudflare.com/client/v4/accounts/" + ACCOUNT
           + "/pages/projects/" + PROJECT + "/deployments/" + DEPLOYMENT)
    payload, _ = download(url, token)
    data = json.loads(payload)
    if not data.get("success"):
        raise RuntimeError("Cloudflare deployment manifest was not returned")
    return sorted(data["result"]["files"].keys())


def normalize(path):
    path = path.lstrip("./").lstrip("/")
    if ".." in Path(path).parts or not path or ":" in path or "?" in path or "#" in path:
        return None
    return "/" + path


def fetch_one(path, target):
    rel = normalize(path)
    if not rel:
        return path, None, "invalid filename"
    url = BASE + quote(rel, safe="/~@-._")
    try:
        data, mime = download(url)
        ext = Path(rel).suffix.lower()
        if ext in {".js", ".json", ".css", ".html"} and mime.lower().startswith("text/html") and ext != ".html":
            if data[:100].lstrip().lower().startswith(b"<!doctype html"):
                raise ValueError("HTML fallback instead of expected asset")
        out = target / rel.lstrip("/")
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(data)
        return rel, len(data), None
    except (HTTPError, URLError, TimeoutError, ValueError) as exc:
        return rel, None, str(exc)


def extract_links(content):
    found = set()
    for match in REFERENCES.finditer(content):
        path = normalize(match.group("path"))
        if path:
            found.add(path)
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--api-token", help="Cloudflare API token with Pages read access")
    ap.add_argument("--manifest", help="Optional JSON list of deployed file paths")
    ap.add_argument("--out", default="recovered-pages", help="Directory to save files into")
    ap.add_argument("--workers", default=6, type=int)
    args = ap.parse_args()
    target = Path(args.out)
    if args.manifest:
        paths = set(json.loads(Path(args.manifest).read_text()))
        mode = "full supplied manifest"
    elif args.api_token:
        paths = set(cloudflare_manifest(args.api_token))
        mode = "full Cloudflare deployment manifest"
    else:
        paths = set(CORE)
        mode = "core files + discovered literal references (not guaranteed complete)"
    visited, errors = set(), {}
    for depth in range(4):
        todo = sorted(paths - visited)
        if not todo:
            break
        print(f"Pass {depth + 1}: retrieving {len(todo)} files", flush=True)
        with ThreadPoolExecutor(max_workers=max(1, min(12, args.workers))) as pool:
            future = {pool.submit(fetch_one, p, target): p for p in todo}
            for f in as_completed(future):
                name, size, err = f.result()
                visited.add(future[f])
                if err:
                    errors[name] = err
                    continue
                if Path(name).suffix.lower() in PARSE_SUFFIXES and depth < 3 and not args.api_token and not args.manifest:
                    try:
                        text = (target / name.lstrip("/")).read_text(errors="ignore")
                        paths.update(extract_links(text))
                    except OSError:
                        pass
        if args.api_token or args.manifest:
            break
    target.mkdir(parents=True, exist_ok=True)
    status = {"mode": mode, "project": PROJECT, "deployment": DEPLOYMENT,
              "retrieved": len(visited) - len(errors), "attempted": len(visited), "errors": errors}
    (target / "recovery-report.json").write_text(json.dumps(status, indent=2))
    print(json.dumps({k:v for k,v in status.items() if k != 'errors'}, indent=2))
    if errors:
        print(f"{len(errors)} failures. See recovery-report.json")
    print("NOTE: deployed assets are not the full original GitHub project/build tooling.")


if __name__ == '__main__':
    main()
