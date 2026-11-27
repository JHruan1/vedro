#!/usr/bin/env python3
"""Enforceable Architecture Guard for Vedro.

Executed automatically by `scripts/verify-all.sh` and GitHub Actions CI.
Enforces:
  1. Zero Dart import cycles across `app/lib/`.
  2. Strict Flutter unidirectional layer DAG:
       core/ <- state/ <- widgets/ <- screens/ <- main.dart
  3. Strict Rust workspace crate DAG (zero cycles, leaf crates stay leaf).
  4. Dart <-> Rust RPC contract parity (every `core.invoke('<name>')` in `app/lib/`
     must have a matching handler in `core/vedro-ffi/src/`).
  5. Exact 8 required C-ABI `pub extern "C" fn vedro_*` exports.
  6. Hard product & security invariants (max volume <= 150%, zero Android
     REQUEST_INSTALL_PACKAGES, zero full-screen ColorFilter beauty veil,
     Bilibili public-API rate limiter intact).
  7. Monolith file-size ratchets (tightened after each governance round so
     decomposed modules cannot silently regress back into god-files).
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP_LIB = ROOT / "app" / "lib"
CORE_DIR = ROOT / "core"

REQUIRED_C_ABI_SYMBOLS = {
    "vedro_init",
    "vedro_destroy",
    "vedro_invoke",
    "vedro_poll_events",
    "vedro_proxy_speed_bps",
    "vedro_free_string",
    "vedro_version",
    "vedro_last_init_error",
}

# File-size ratchets (lines). Updated downwards as each governance round completes.
FILE_LINE_LIMITS: dict[str, int] = {
    "app/lib/widgets/beauty_filter.dart": 600,
    "app/lib/widgets/danmaku_engine.dart": 350,
    "app/lib/core/services/danmaku_parser.dart": 150,
    "app/lib/core/utils/artwork_signal.dart": 60,
    "app/lib/core/utils/error_formatter.dart": 120,
    "app/lib/core/utils/formatters.dart": 150,
}

errors: list[str] = []


def fail(msg: str) -> None:
    errors.append(msg)


def check_dart_imports_and_layers() -> None:
    dart_files = sorted(APP_LIB.rglob("*.dart"))
    rel_of = lambda p: str(p.relative_to(APP_LIB)).replace("\\", "/")
    graph: dict[str, list[str]] = {}

    def layer_of(rel: str) -> str:
        return rel.split("/")[0]

    for f in dart_files:
        rel = rel_of(f)
        src = f.read_text(encoding="utf-8")
        # Track both `import` and `export` edges for cycle & layer enforcement
        refs = re.findall(r"""(?:import|export)\s+['"]([^'"]+)['"]""", src)
        deps: set[str] = set()
        for ref in refs:
            if ref.startswith("dart:"):
                continue
            if ref.startswith("package:"):
                if ref.startswith("package:vedro/"):
                    deps.add(ref[len("package:vedro/") :])
                continue
            resolved = (f.parent / ref).resolve()
            try:
                deps.add(rel_of(resolved))
            except ValueError:
                pass
        graph[rel] = sorted(deps)

        src_layer = layer_of(rel)
        for dep in graph[rel]:
            dst_layer = layer_of(dep)
            if src_layer == "core" and dst_layer in ("state", "widgets", "screens", "main.dart"):
                fail(f"[Layer] core must not depend on {dst_layer}: {rel} -> {dep}")
            elif src_layer == "state" and dst_layer in ("widgets", "screens", "main.dart"):
                fail(f"[Layer] state must not depend on {dst_layer}: {rel} -> {dep}")
            elif src_layer == "widgets" and dst_layer in ("screens", "main.dart"):
                fail(f"[Layer] widgets must not depend on {dst_layer}: {rel} -> {dep}")

    visited: dict[str, int] = {}
    stack: list[str] = []

    def dfs(u: str) -> None:
        visited[u] = 1
        stack.append(u)
        for v in graph.get(u, []):
            st = visited.get(v, 0)
            if st == 1:
                idx = stack.index(v)
                cycle = " -> ".join(stack[idx:] + [v])
                fail(f"[Cycle] Circular Dart dependency detected: {cycle}")
            elif st == 0:
                dfs(v)
        stack.pop()
        visited[u] = 2

    for node in graph:
        if visited.get(node, 0) == 0:
            dfs(node)


def check_rust_crate_dag() -> None:
    allowed: dict[str, set[str]] = {
        "vedro-protocol": set(),
        "vedro-storage": set(),
        "vedro-stream": set(),
        "vedro-playback": {"vedro-stream"},
        "vedro-ffi": {"vedro-protocol", "vedro-stream", "vedro-playback", "vedro-storage"},
        "vedro-cli": {"vedro-ffi", "vedro-playback", "vedro-stream", "vedro-protocol"},
    }
    for toml in sorted(CORE_DIR.glob("*/Cargo.toml")):
        crate_dir = toml.parent.name
        txt = toml.read_text(encoding="utf-8")
        deps = set(re.findall(r"^(vedro-[a-z0-9_-]+)\s*=", txt, re.M))
        if crate_dir not in allowed:
            continue
        unexpected = deps - allowed[crate_dir]
        if unexpected:
            fail(f"[Rust DAG] {crate_dir} has disallowed workspace deps: {sorted(unexpected)}")


def check_rpc_contract_and_c_abi() -> None:
    ffi_sources = sorted((CORE_DIR / "vedro-ffi" / "src").rglob("*.rs"))
    combined_ffi = "\n".join(p.read_text(encoding="utf-8") for p in ffi_sources)

    # Extract all string-literal match arm keys inside vedro-ffi sources
    rust_arms: set[str] = set()
    for m in re.finditer(r'^\s*((?:"[a-z0-9_]+"(?:\s*\|\s*)?)+)\s*=>', combined_ffi, re.M):
        for name in re.findall(r'"([a-z0-9_]+)"', m.group(1)):
            rust_arms.add(name)

    for f in sorted(APP_LIB.rglob("*.dart")):
        txt = f.read_text(encoding="utf-8")
        for m in re.finditer(r"""\.invoke\(\s*['"]([a-z0-9_]+)['"]""", txt):
            rpc = m.group(1)
            if rpc not in rust_arms:
                rel = f.relative_to(ROOT)
                fail(f"[RPC Parity] {rel} calls core.invoke('{rpc}') which has no Rust handler in vedro-ffi")

    exported = set(
        re.findall(r'pub\s+(?:unsafe\s+)?extern\s+"C"\s+fn\s+(vedro_[a-z0-9_]+)', combined_ffi)
    )
    missing = REQUIRED_C_ABI_SYMBOLS - exported
    if missing:
        fail(f"[C-ABI] Missing required exported symbols in vedro-ffi: {sorted(missing)}")

    if "BilibiliRateLimiter" not in combined_ffi:
        fail("[Invariant] BilibiliRateLimiter missing from vedro-ffi")


def check_product_invariants() -> None:
    manifest = (ROOT / "app/android/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
    if "REQUEST_INSTALL_PACKAGES" in manifest:
        fail("[Security/PlayProtect] REQUEST_INSTALL_PACKAGES must not be declared in AndroidManifest.xml")

    player_sources = "\n".join(
        p.read_text(encoding="utf-8")
        for p in sorted((APP_LIB / "screens").rglob("player*.dart"))
    )
    if "ColorFilter.matrix" in player_sources:
        fail("[Invariant] Whole-screen ColorFilter.matrix beauty veil must not exist in player screens")

    if ".clamp(100.0, 150.0)" not in player_sources:
        fail("[Invariant] Max volume boost cap (.clamp(100.0, 150.0)) missing from player screens")

    # Ensure single canonical transfer speed formatter (no duplicate _fmtNetSpeed / _fmtSpeed(int bps))
    for f in sorted(APP_LIB.rglob("*.dart")):
        rel = str(f.relative_to(ROOT)).replace("\\", "/")
        if rel == "app/lib/core/utils/formatters.dart":
            continue
        txt = f.read_text(encoding="utf-8")
        if re.search(r"String\s+_?fmt(?:Net)?Speed\s*\(\s*int\s+", txt):
            fail(f"[SSOT] Duplicate transfer-speed formatter in {rel}; use fmtTransferSpeed from core/utils/formatters.dart")

    # Ensure local_asr_engine stays in core/services/, never back in widgets/
    if (APP_LIB / "widgets" / "local_asr_engine.dart").exists():
        fail("[SSOT] widgets/local_asr_engine.dart must stay in core/services/local_asr_engine.dart")


def check_file_size_ratchets() -> None:
    for rel, max_lines in FILE_LINE_LIMITS.items():
        path = ROOT / rel
        if not path.exists():
            continue
        lines = len(path.read_text(encoding="utf-8").splitlines())
        if lines > max_lines:
            fail(f"[Complexity Ratchet] {rel} is {lines} lines (limit {max_lines})")


def main() -> int:
    check_dart_imports_and_layers()
    check_rust_crate_dag()
    check_rpc_contract_and_c_abi()
    check_product_invariants()
    check_file_size_ratchets()

    if errors:
        print("ARCHITECTURE CHECK FAILED:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    print("architecture-check OK (0 cycles, strict Dart/Rust DAG, RPC parity, C-ABI 8/8, invariants OK)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
