#!/usr/bin/env bash
# Regenera la tabla "Current Versions" del README a partir de GitHub Releases
# y hace commit+push si hay cambios. Uso: ./scripts/sync-readme-versions.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$REPO_ROOT/README.md"
FULL_REPO="mlmateos/texstudio-qt6-builds"

[[ -f "$README" ]] || { echo "❌ README.md no encontrado"; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "❌ gh no instalado"; exit 1; }

STABLE_VER=$(gh release list --repo "$FULL_REPO" --exclude-pre-releases --limit 1 \
    --json tagName --jq '.[0].tagName' 2>/dev/null | sed 's/^v//')
DEV_VER=$(gh release list --repo "$FULL_REPO" --limit 15 \
    --json tagName,isPrerelease,createdAt \
    --jq '[.[] | select(.isPrerelease)] | sort_by(.createdAt) | .[-1].tagName' 2>/dev/null | sed 's/^v//')

[[ -n "$STABLE_VER" ]] || STABLE_VER="4.9.6"

# Solo mostrar dev si su serie es más nueva que la estable
if [[ -n "$DEV_VER" ]]; then
    SB=$(echo "$STABLE_VER" | grep -oE '^[0-9]+(\.[0-9]+)+')
    DB=$(echo "$DEV_VER"    | grep -oE '^[0-9]+(\.[0-9]+)+')
    HIGHEST=$(printf '%s\n%s\n' "$SB" "$DB" | sort -V | tail -n1)
    [[ "$HIGHEST" == "$DB" && "$DB" != "$SB" ]] || DEV_VER=""
fi

python3 - "$README" "$STABLE_VER" "${DEV_VER:-}" << 'PYEOF'
import sys
path, stable, dev = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path, encoding='utf-8').read().split('\n')
block = ["| Type | Version | Branch |",
         "| --- | --- | --- |",
         f"| 🟢 **Stable** | **{stable}** | `stable`, `alpha` |"]
if dev:
    block.append(f"| 🟡 Development | {dev} | `alpha` |")
out, i, n, found = [], 0, len(lines), False
while i < n:
    if '<!-- AUTO-VERSIONS:START -->' in lines[i]:
        found = True
        out.append(lines[i]); out.extend(block); i += 1
        while i < n and '<!-- AUTO-VERSIONS:END -->' not in lines[i]:
            i += 1
        if i < n: out.append(lines[i])
    else:
        out.append(lines[i])
    i += 1
if found:
    open(path, 'w', encoding='utf-8').write('\n'.join(out))
    print("✅ Tabla 'Current Versions' regenerada")
else:
    print("⚠️ Marcadores AUTO-VERSIONS no encontrados; README sin cambios")
PYEOF

if ! git -C "$REPO_ROOT" diff --quiet -- README.md; then
    git -C "$REPO_ROOT" add README.md
    git -C "$REPO_ROOT" commit -m "docs: auto-update Current Versions (stable $STABLE_VER${DEV_VER:+, dev $DEV_VER})"
    git -C "$REPO_ROOT" push origin master
    echo "✅ README sincronizado y pusheado"
else
    echo "ℹ️ README ya al día"
fi
