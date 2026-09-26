#!/bin/bash
# Downloads the MyScript math recognition assets (iink 4.5, "math2") into the
# iPad app bundle folder. The certificate MyCertificate.c must be placed in
# MathClass/MyScript/ separately (developer.myscript.com > Getting started > iOS).
set -euo pipefail
cd "$(dirname "$0")/.."
dest="MathClass/MyScript/MyScriptAssets.bundle"
mkdir -p "$dest"
tmp=$(mktemp -d)
curl -sSfL -o "$tmp/math2.zip" https://download.myscript.com/iink/recognitionAssets_iink_4.5/myscript-iink-recognition-math2.zip
unzip -q -o "$tmp/math2.zip" -d "$tmp/math2"
rm -rf "$dest/recognition-assets"
cp -R "$tmp/math2/recognition-assets" "$dest/"
rm -rf "$tmp"
echo "MyScript math2 assets installed in $dest"
