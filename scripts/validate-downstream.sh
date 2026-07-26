#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

required=(
  ".github/downstream-config-manifest.yml"
  ".github/workflows/main.yml"
  ".github/workflows/repository-validation.yml"
  ".github/workflows/upstream-sync.yml"
  "README.md"
  "Sileo/depiction.json"
)
for path in "${required[@]}"; do
  [[ -f "${ROOT}/${path}" ]] || {
    printf 'FAIL missing required path: %s\n' "$path" >&2
    exit 1
  }
done

python3 - "$ROOT" <<'PY'
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
json.loads((root / "Sileo/depiction.json").read_text())
localizations = sorted((root / "Localizations").glob("*.lproj/Localizable.strings"))
assert localizations, "no localization files found"
for path in localizations:
    path.read_text(encoding="utf-8")
workflow = (root / ".github/workflows/main.yml").read_text()
assert "workflow_dispatch:" in workflow
assert "action-hide-sensitive-inputs@" in workflow
assert "softprops/action-gh-release@" in workflow
PY

if command -v actionlint >/dev/null 2>&1; then
  actionlint "${ROOT}/.github/workflows/"*.yml
fi

printf 'PASS Glow downstream workflow and asset contract\n'
