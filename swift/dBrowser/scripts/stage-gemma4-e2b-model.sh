#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${1:-/Users/johansellstrom/dev/advatar/Broom/diskspace-gemma/models/gemma-4-e2b-it-4bit-mlx}"
DEST_DIR="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/dBrowser/Gemma4E2B4BitMLX}"

for required in config.json tokenizer.json model.safetensors; do
  if [[ ! -f "${SOURCE_DIR}/${required}" ]]; then
    echo "Missing ${required} in ${SOURCE_DIR}" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "${DEST_DIR}")"
rsync -a --delete "${SOURCE_DIR}/" "${DEST_DIR}/"

echo "Staged Gemma 4 E2B MLX bundle at ${DEST_DIR}"
