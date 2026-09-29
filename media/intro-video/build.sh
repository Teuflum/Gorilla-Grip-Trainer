#!/usr/bin/env bash
# Rebuilds gorilla-grip-trainer-intro.mp4. Needs Python 3 (kokoro-onnx, soundfile,
# numpy, scipy), Node.js, and ffmpeg. Set KOKORO_DIR to a folder holding
# kokoro-v1.0.int8.onnx and voices-v1.0.bin (github.com/thewh1teagle/kokoro-onnx
# releases), CHROMIUM to a Chromium binary if Playwright has none, and FF to ffmpeg
# if it is not on PATH. Frames are rendered with WebGL; without a GPU Chromium falls
# back to SwiftShader, which takes around 2 s per frame. Everything generated goes to build/.
set -euo pipefail
cd "$(dirname "$0")"
HERE=$PWD
FF=${FF:-ffmpeg}; export FF
mkdir -p build/web/fonts build/web/emoji build/web/lib
cp web/*.html web/*.js build/web/
cp script.py tts.py audio.py render.js build/
cd build
[ -d node_modules ] || npm install --no-save --silent playwright three@0.170 @fontsource/russo-one @fontsource/inter \
  @fontsource/jetbrains-mono @fontsource/anton @fontsource/inter-tight @fontsource/fredoka
cp node_modules/three/build/three.module.js web/lib/
rm -rf web/lib/jsm && cp -r node_modules/three/examples/jsm web/lib/jsm
F=node_modules/@fontsource
cp $F/russo-one/files/russo-one-latin-400-normal.woff2 $F/anton/files/anton-latin-400-normal.woff2 \
   $F/inter/files/inter-latin-{500,700,800,900}-normal.woff2 \
   $F/jetbrains-mono/files/jetbrains-mono-latin-{500,700}-normal.woff2 \
   $F/inter-tight/files/inter-tight-latin-{700,800,900}-{normal,italic}.woff2 \
   $F/fredoka/files/fredoka-latin-{600,700}-normal.woff2 web/fonts/
EMOJI=../../../plugin/assets/emoji
for set in noto twemoji fluent-3d; do
  for f in "$EMOJI/$set"/*.png; do cp "$f" "web/emoji/$set-$(basename "$f")"; done
done
KOKORO_DIR=${KOKORO_DIR:-$HERE/voices} python3 tts.py
cp timeline.json web/
python3 -m http.server 8123 --bind 127.0.0.1 --directory web >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER' EXIT
sleep 1
WORKERS=${WORKERS:-4}
PIDS=()
for i in $(seq 0 $((WORKERS - 1))); do node render.js "$i" "$WORKERS" & PIDS+=($!); done
wait "${PIDS[@]}"
python3 audio.py
for i in $(seq 0 $((WORKERS - 1))); do echo "file 'seg$i.mp4'"; done > segs.txt
"$FF" -y -loglevel error -f concat -safe 0 -i segs.txt -i mix.wav -c:v libx264 -preset slow -tune animation -crf 23 \
  -pix_fmt yuv420p -c:a aac -b:a 160k \
  -movflags +faststart -shortest "$HERE/gorilla-grip-trainer-intro.mp4"
echo "wrote $HERE/gorilla-grip-trainer-intro.mp4"
