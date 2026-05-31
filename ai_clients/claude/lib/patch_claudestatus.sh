#!/usr/bin/env bash
# Patches @howells/claudestatus billing fixes after npm (re)installs.
#
# Fixes:
#   1. renewEn regex — broader pattern: "will renew [on]", "next renewal", optional "on"
#   2. cancelEn regex — safer pattern: won't false-match "Cancel on <date>" button text
#   3. Post-parse null check — writes page text to /tmp for debugging when no pattern matches
#   4. Silent catch{} — surfaces exception messages instead of blank billing rows

set -euo pipefail

# asdf shims are shell scripts, not symlinks — realpath returns the shim itself.
# Use `asdf which` to get the real versioned binary, then follow that symlink.
if command -v asdf >/dev/null 2>&1 && asdf which claudestatus >/dev/null 2>&1; then
    CLAUDESTATUS_BIN=$(asdf which claudestatus)
else
    CLAUDESTATUS_BIN=$(command -v claudestatus 2>/dev/null || true)
fi

if [[ -z "$CLAUDESTATUS_BIN" ]]; then
    echo "❌  claudestatus not found — install it first (npm install -g @howells/claudestatus)." >&2
    exit 1
fi

REAL_BIN=$(realpath "$CLAUDESTATUS_BIN")
DIST_DIR=$(dirname "$REAL_BIN")
API_JS="$DIST_DIR/api.js"

if [[ ! -f "$API_JS" ]]; then
    echo "❌  api.js not found at $API_JS" >&2
    exit 1
fi

CURRENT_VERSION=$(python3 -c "import json; print(json.load(open('$DIST_DIR/../package.json'))['version'])" 2>/dev/null || echo "unknown")
echo "Patching @howells/claudestatus v${CURRENT_VERSION} at $API_JS ..."

python3 - "$API_JS" <<'PYEOF'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
src = path.read_text()
original = src

# ── Patch 1: renewEn — broader pattern ───────────────────────────────────────
src = src.replace(
    '    // EN auto-renew: "renews automatically on Month DD" or "next billing on..."\n'
    '    const renewEn = text.match(/(?:renews(?: automatically)?|next billing)\\s+on\\s+(\\w+)\\s+(\\d+),?\\s+(\\d{4})/i);',
    '    // EN auto-renew: "renews [automatically] [on] Month DD", "will renew [on] ...", "next billing/renewal [on] ..."\n'
    '    const renewEn = text.match(/(?:(?:will\\s+)?renews?(?: automatically)?|next\\s+(?:billing|renewal))\\s+(?:on\\s+)?(\\w+)\\s+(\\d{1,2}),?\\s+(\\d{4})/i);',
    1
)

# ── Patch 2: cancelEn — safe pattern (won't match "Cancel on <date>" buttons) ─
# Matches "will be cancelled/canceled on" or "subscription cancels on",
# but NOT a bare "cancel on" that appears on UI buttons for active subscriptions.
src = src.replace(
    '    // EN cancellation: "will be cancelled on Month DD, YYYY"\n'
    '    const cancelEn = text.match(/(?:will be cancelled|cancels)\\s+on\\s+(\\w+)\\s+(\\d+),?\\s+(\\d{4})/i);',
    '    // EN cancellation: "will be cancelled/canceled on Month DD" or "subscription cancels on"\n'
    '    const cancelEn = text.match(/(?:will\\s+be\\s+cancell?ed|(?:subscription\\s+)?cancels)\\s+on\\s+(\\w+)\\s+(\\d{1,2}),?\\s+(\\d{4})/i);',
    1
)

# ── Patch 3: surface parse failures + debug file + exception messages ─────────
src = src.replace(
    '        const text = await page.evaluate(() => document.body.innerText);\n'
    '        await context.storageState({ path: storagePath });\n'
    '        await context.close();\n'
    '        return parseBillingText(text);\n'
    '    }\n'
    '    catch {\n'
    '        await context.close();\n'
    '        return { period: "unknown", autoRenew: null, billingDate: null };\n'
    '    }',
    '        const text = await page.evaluate(() => document.body.innerText);\n'
    '        await context.storageState({ path: storagePath });\n'
    '        await context.close();\n'
    '        const parsed = parseBillingText(text);\n'
    '        if (!parsed.billingDate && parsed.period === "unknown" && parsed.autoRenew === null) {\n'
    '            const debugPath = `/tmp/claudestatus_billing_${name}.txt`;\n'
    '            fs.writeFileSync(debugPath, text);\n'
    '            return { ...parsed, error: `Could not parse — debug: ${debugPath}` };\n'
    '        }\n'
    '        return parsed;\n'
    '    }\n'
    '    catch (err) {\n'
    '        await context.close();\n'
    '        const msg = err instanceof Error ? err.message : String(err);\n'
    '        return { period: "unknown", autoRenew: null, billingDate: null, error: msg };\n'
    '    }',
    1
)

if src != original:
    path.write_text(src)
    print("  ✓ patches applied")
else:
    print("  ⚠  no changes — already patched or version changed")
PYEOF

echo ""
echo "✅  claudestatus patch complete."
echo "    Run 'claudestatus' to verify."
echo "    If billing shows 'Could not parse', read /tmp/claudestatus_billing_<name>.txt"
echo "    to see the raw page text and identify the missing regex pattern."
