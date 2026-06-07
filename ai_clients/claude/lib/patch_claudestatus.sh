#!/usr/bin/env bash
# Patches @howells/claudestatus billing fixes after npm (re)installs.
#
# Fixes:
#   1. renewEn regex — broader pattern: "will renew [on]", "next renewal", optional "on"
#   2. cancelEn regex — safer pattern: won't false-match "Cancel on <date>" button text
#   3. Post-parse null check — writes page text to /tmp for debugging when no pattern matches
#   4. Silent catch{} — surfaces exception messages instead of blank billing rows
#   5. No storageState save on the billing flow (ROOT-CAUSE FIX) — billing is
#      read-only, but the page can load degraded (Cloudflare / "Loading…" /
#      cookie-rotation). Saving that state overwrote the good session cookie and
#      bricked accounts into a false "Session expired" in the usage table.
#   6. Cookie-consent banner dismissal — it overlaid the billing panel, so its text
#      ("We use cookies…") was scraped instead of the real billing content.
#   7. Wait for rendered billing content instead of a fixed 4s timeout — fixes empty
#      / "Could not parse" rows and lets the headed-browser Cloudflare challenge
#      auto-clear before we decide the account is blocked.

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

# ── Patch 4: dismiss cookie banner + wait for real content (not a fixed timeout) ─
# Replaces the fixed `waitForTimeout(4000)` race. The old code captured the page
# while it still said "Loading…" behind the cookie-consent banner, producing empty
# / "Could not parse" rows. Waiting for actual billing keywords also gives the
# headed-browser Cloudflare challenge time to auto-clear before we flag a block.
src = src.replace(
    '        await page.waitForTimeout(4000);\n'
    '        const content = await page.content();\n'
    '        if (content.includes("Just a moment") ||\n'
    '            content.includes("challenge-platform") ||\n'
    '            content.includes("cf-turnstile")) {\n'
    '            await context.close();\n'
    '            return { period: "unknown", autoRenew: null, billingDate: null, error: "Cloudflare block — run: claudestatus refresh " + name };\n'
    '        }\n',
    '        // Dismiss the cookie-consent banner — it overlays the billing panel and\n'
    '        // its text was being scraped instead of the real billing content.\n'
    '        try {\n'
    '            await page.getByRole("button", { name: /reject all|accept all/i }).first().click({ timeout: 3000 });\n'
    '        }\n'
    '        catch {\n'
    '            // No banner shown — nothing to dismiss.\n'
    '        }\n'
    '        // Wait for the SPA to render real billing content instead of "Loading…".\n'
    '        // A headed real-Chrome session also lets Cloudflare\'s challenge auto-clear\n'
    '        // within this window, so we no longer false-positive on a transient block.\n'
    '        try {\n'
    '            await page.waitForFunction(() => {\n'
    '                const t = document.body.innerText || "";\n'
    '                if (/just a moment/i.test(t)) return false;\n'
    '                if (/^\\s*loading/i.test(t)) return false;\n'
    '                return /(monthly|annual|mensal|anual|renew|renova|cancel|cobran|billing|plan|subscription)/i.test(t);\n'
    '            }, { timeout: 25000 });\n'
    '        }\n'
    '        catch {\n'
    '            // Timed out — fall through; the Cloudflare / parse checks below report why.\n'
    '        }\n'
    '        const content = await page.content();\n'
    '        if (content.includes("Just a moment") ||\n'
    '            content.includes("challenge-platform") ||\n'
    '            content.includes("cf-turnstile")) {\n'
    '            await context.close();\n'
    '            return { period: "unknown", autoRenew: null, billingDate: null, error: "Cloudflare block — run: claudestatus refresh " + name };\n'
    '        }\n',
    1
)

# ── Patch 5: ROOT-CAUSE — stop the billing flow from clobbering the session ──────
# The billing page is read-only, but it can load degraded (Cloudflare / "Loading…"
# / mid-cookie-rotation). Saving storageState from that state overwrote the good
# session cookie on disk, so the next usage fetch returned 401 and the dashboard
# showed a FALSE "Session expired" — the bug that nearly triggered a needless
# re-subscribe. Anchored on the parseBillingText() line so it targets the BILLING
# save only (the addAccount / usage saves are kept — they run on confirmed auth).
src = src.replace(
    '        const text = await page.evaluate(() => document.body.innerText);\n'
    '        await context.storageState({ path: storagePath });\n'
    '        await context.close();\n'
    '        const parsed = parseBillingText(text);\n',
    '        const text = await page.evaluate(() => document.body.innerText);\n'
    '        // Do NOT persist storageState here: a degraded/unauthenticated billing\n'
    '        // load would overwrite the good session cookie and brick the account\n'
    '        // into a false "Session expired". Billing is read-only — never save.\n'
    '        await context.close();\n'
    '        const parsed = parseBillingText(text);\n',
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
