#!/usr/bin/env python3
"""Audit the FULL transitive pub dependency tree against a policy ban list.

Usage (from the repo / workspace root):
    dart pub deps --json > /tmp/deps.json
    python3 audit_deps.py /tmp/deps.json

Exit 0 = clean. Exit 1 = a banned package ships in the binary, directly or
transitively. Exit 2 = usage/parse error. Direct-only inspection of pubspec.yaml
cannot find transitive hits; that is the entire point of walking the resolved
graph.

EDIT THE `BANNED` AND `ALLOW` LISTS BELOW to encode YOUR project's policy. The
defaults suit a no-network / no-telemetry app; a normal networked app should
delete the network-client and identifier entries it legitimately uses.
"""

import json
import re
import sys

# --- EDIT ME: substring/regex patterns matched against package names ---------
# case-insensitive. Each entry: (pattern, why it is refused).
BANNED = [
    (r"^firebase", "Firebase — its core registers device/usage data categories"),
    (r"^cloud_fire", "Firebase (Firestore) — same core"),
    (r"crashlytics", "crash reporting = telemetry"),
    (r"sentry", "crash reporting = telemetry"),
    (r"analytics", "analytics of any kind is refused by policy"),
    (r"^posthog|^mixpanel|^amplitude|^segment", "product analytics"),
    (r"^google_mobile_ads|^appsflyer|^adjust", "ads/attribution SDK — network + identifiers"),
    (r"^http$|^dio$|^web_socket|^grpc$|^socket_io", "a network client (policy: no network path)"),
    (r"^googleapis|^google_sign_in|^firebase_auth", "accounts + network"),
    (r"^device_info_plus|^package_info_plus", "device identifiers with no shipped use (allow if you ship one)"),
]

# --- EDIT ME: names that match a BANNED pattern but are deliberately kept -----
# Add a name here ONLY with a written justification: WHY the reachable-but-inert
# dependency is acceptable and what the real, enforced gate is instead.
ALLOW: set[str] = {
    # e.g. "http",  # reaches the tree only via <platform-interface>; the app
    #                # declares no INTERNET permission so the socket is inert.
    #                # Real gate: test/policy/no_internet_permission_test.
}

USAGE = """usage: audit_deps.py <deps.json>

Generate the input first (from the repo / workspace root):
    dart pub deps --json > deps.json

Flags any banned package in the resolved tree and says whether it arrived
directly or transitively. Exits 1 on a shipping hit so it can gate CI."""


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] in ("-h", "--help"):
        print(USAGE, file=sys.stderr)
        return 2
    try:
        with open(sys.argv[1]) as f:
            data = json.load(f)
    except OSError as e:
        print(f"audit_deps: cannot read {sys.argv[1]}: {e}", file=sys.stderr)
        return 2
    except json.JSONDecodeError as e:
        print(f"audit_deps: {sys.argv[1]} is not valid JSON: {e}", file=sys.stderr)
        print("  (expected the output of: dart pub deps --json)", file=sys.stderr)
        return 2

    pkgs = {p["name"]: p for p in data.get("packages", [])}
    names = {n for n, p in pkgs.items() if p.get("kind") != "root"}

    def reachable(kind: str) -> set[str]:
        """Everything pulled in transitively by one class of declared dependency."""
        seen: set[str] = set()
        stack = [n for n, p in pkgs.items() if p.get("kind") == kind]
        while stack:
            n = stack.pop()
            if n in seen or n not in pkgs:
                continue
            seen.add(n)
            stack.extend(pkgs[n].get("dependencies", []))
        return seen

    # What ships is what `dependencies:` drags in. `dev_dependencies:` (build_runner,
    # codegen, the test framework) never reach the binary, so a banned package that is
    # ONLY dev-reachable is not a shipping defect — build_runner legitimately pulls a
    # local HTTP server for watch mode. A gate that fails on that gets switched off.
    ships = reachable("direct")
    dev_only = reachable("dev") - ships

    def banned_in(pool: set[str]) -> list[tuple[str, str]]:
        found = []
        for name in sorted(pool):
            if name in ALLOW:
                continue
            for pattern, why in BANNED:
                if re.search(pattern, name, re.IGNORECASE):
                    found.append((name, why))
                    break
        return found

    hits = banned_in(ships)
    noise = banned_in(dev_only)
    direct_names = {n for n, p in pkgs.items() if p.get("kind") == "direct"}

    print(f"{len(names)} resolved · {len(ships)} ship in the binary · {len(dev_only)} build/test only")
    for name, why in hits:
        how = "direct" if name in direct_names else "TRANSITIVE"
        print(f"BANNED  {name}  [{how}]\n        {why}")

    if noise:
        print("\nBuild/test only — not in the binary, not a defect:")
        for name, _ in noise:
            print(f"  {name}")

    if hits:
        print("\nRefuse the dependency, or find one that does not pull these in.")
        print("To see who pulls a package in:  dart pub deps | grep -B4 <name>")
        return 1

    print("\nClean: nothing banned reaches the binary.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
