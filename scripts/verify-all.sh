#!/usr/bin/env bash
set -euo pipefail

export PATH="/root/.cargo/bin:/opt/flutter/bin:/usr/local/go/bin:$PATH"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "=== [1/4] Rust format, clippy & unit tests ==="
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo build --release -p prism-ffi -p prism-cli

echo "=== [2/4] Flutter analyze & widget + live Rust dart:ffi tests ==="
(cd "$ROOT_DIR/app" && flutter analyze && flutter test --reporter expanded)

echo "=== [3/4] Prism CLI platform profile matrix check ==="
"$ROOT_DIR/target/release/prism-cli" profile-matrix >/dev/null
echo "profile-matrix OK"

if [ -d /root/embygo-dev ]; then
  echo "=== [4/4] Live End-to-End Integration Test against real isolated embygo ==="
  TMP_DIR="$(mktemp -d /tmp/prism-embygo-e2e.XXXXXX)"
  EMBYGO_PID=""
  cleanup() {
    if [ -n "$EMBYGO_PID" ]; then kill "$EMBYGO_PID" 2>/dev/null || true; fi
    rm -rf "$TMP_DIR"
  }
  trap cleanup EXIT

  mkdir -p "$TMP_DIR/media/movies/Dune Part Two (2024)" "$TMP_DIR/data"

  # Generate a real valid 3-second H.264 + AAC MKV sample + NFO + sidecar SRT subtitle
  ffmpeg -y -v error \
    -f lavfi -i testsrc2=duration=3:size=1280x720:rate=24 \
    -f lavfi -i sine=frequency=440:duration=3 \
    -c:v libx264 -pix_fmt yuv420p -c:a aac \
    "$TMP_DIR/media/movies/Dune Part Two (2024)/Dune.Part.Two.2024.2160p.DV.Atmos.mkv"

  cat > "$TMP_DIR/media/movies/Dune Part Two (2024)/Dune.Part.Two.2024.2160p.DV.Atmos.nfo" <<'EOF'
<movie>
  <title>Dune: Part Two</title>
  <originaltitle>Dune: Part Two</originaltitle>
  <year>2024</year>
  <rating>8.8</rating>
  <plot>Paul Atreides unites with Chani and the Fremen while seeking revenge.</plot>
  <genre>Sci-Fi</genre>
  <genre>Adventure</genre>
  <tmdbid>693134</tmdbid>
</movie>
EOF

  cat > "$TMP_DIR/media/movies/Dune Part Two (2024)/Dune.Part.Two.2024.2160p.DV.Atmos.zh.default.srt" <<'EOF'
1
00:00:00,200 --> 00:00:02,500
Prism Player embygo 端到端实测字幕
EOF

  # Build isolated embygo binary from /root/embygo-dev
  (cd /root/embygo-dev && go build -o "$TMP_DIR/embygo-test" ./cmd/embygo)

  # Pick an unused ephemeral loopback port (never touches 8096 or production embygo!)
  TEST_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); p=s.getsockname()[1]; s.close(); print(p)')"
  PW_HASH="$(printf '%s' 'prism-e2e-pass' | "$TMP_DIR/embygo-test" -hash-password)"

  cat > "$TMP_DIR/embygo.json" <<EOF
{
  "listen": "127.0.0.1:${TEST_PORT}",
  "server_name": "Prism Test EmbyGo",
  "data_dir": "${TMP_DIR}/data",
  "scan_interval": "15m",
  "stream_ticket_ttl": "10m",
  "libraries": [
    {
      "id": "movies-1",
      "name": "Movies",
      "kind": "movies",
      "root": "${TMP_DIR}/media/movies",
      "source": "local",
      "priority": 100
    }
  ],
  "users": [
    {
      "id": "u-admin",
      "name": "admin",
      "password_pbkdf2": "${PW_HASH}",
      "admin": true,
      "hidden": false
    }
  ]
}
EOF

  "$TMP_DIR/embygo-test" -config "$TMP_DIR/embygo.json" >"$TMP_DIR/embygo.log" 2>&1 &
  EMBYGO_PID=$!

  READY=0
  for _ in $(seq 1 40); do
    if curl -fsS "http://127.0.0.1:${TEST_PORT}/System/Ping" >/dev/null 2>&1; then
      READY=1
      break
    fi
    sleep 0.25
  done
  if [ "$READY" -ne 1 ]; then
    echo "embygo-test failed to start; log:"
    cat "$TMP_DIR/embygo.log"
    exit 1
  fi

  "$ROOT_DIR/target/release/prism-cli" e2e-embygo "http://127.0.0.1:${TEST_PORT}" "admin" "prism-e2e-pass"
fi

echo "=== ALL VERIFICATION CHECKS PASSED ==="
