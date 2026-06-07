#!/usr/bin/env bash
# Brings an installed @howells/claudestatus to the corrected state (idempotent).
# Re-run after npm (re)installs the package.
#
# This is the authoritative re-patcher. It mirrors the fresh-install injection in
# distro_config/install_coding_lib/ai_clients.sh::_claudestatus_patch_display —
# KEEP THE TWO IN SYNC (the api.js billing block + classifyPlan + display.js here
# must match what the installer injects).
#
# What it does to dist/api.js:
#   - Inserts classifyPlan() (max/pro/team/free/unknown) if missing.
#   - Rewrites both usage-path plan snippets to call classifyPlan().
#   - Replaces the billing block with the API-first version: plan + paid/free come
#     from the JSON API (no Cloudflare); the renewal date is a best-effort,
#     Portuguese-aware page scrape that NEVER persists storageState (a degraded
#     billing load would clobber the session → false "Session expired").
# What it does to dist/display.js:
#   - Overwrites it with the plan-aware usage table (Free shown as unusable and
#     excluded from the recommendation) + the Account/Plan/Paid/Renewal/Auto-Renew
#     billing table.

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
DISPLAY_JS="$DIST_DIR/display.js"

if [[ ! -f "$API_JS" ]]; then
    echo "❌  api.js not found at $API_JS" >&2
    exit 1
fi

CURRENT_VERSION=$(python3 -c "import json; print(json.load(open('$DIST_DIR/../package.json'))['version'])" 2>/dev/null || echo "unknown")
echo "Patching @howells/claudestatus v${CURRENT_VERSION} at $DIST_DIR ..."

# ── api.js: classifyPlan + plan snippets + API-first billing ─────────────────
python3 - "$API_JS" <<'PYEOF'
import re, sys, pathlib

path = pathlib.Path(sys.argv[1])
src = path.read_text()
original = src

CLASSIFIER = r'''
// Map claude.ai org capabilities to a plan tier. Order matters: a paid org keeps
// its "chat" capability, so the paid markers must be checked before bare "chat".
//   claude_max -> max, claude_pro -> pro, raven -> team (Team/Enterprise),
//   chat only  -> free (no paid capability), else unknown.
function classifyPlan(capabilities) {
    const c = capabilities || [];
    if (c.includes("claude_max")) return "max";
    if (c.includes("claude_pro")) return "pro";
    if (c.includes("raven")) return "team";
    if (c.includes("chat")) return "free";
    return "unknown";
}
'''

# 1) Insert classifyPlan once, right after getProfileDir().
anchor = (
    "function getProfileDir(name) {\n"
    "    return path.join(getAccountsDir(), `profile-${name}`);\n"
    "}\n"
)
if "function classifyPlan(" not in src and anchor in src:
    src = src.replace(anchor, anchor + CLASSIFIER, 1)

# 2) Rewrite both usage-path plan snippets to call classifyPlan().
old_plan = (
    "        const plan = org.capabilities.includes(\"claude_max\")\n"
    "            ? \"max\"\n"
    "            : org.capabilities.includes(\"chat\")\n"
    "                ? \"pro\"\n"
    "                : \"unknown\";"
)
src = src.replace(old_plan, "        const plan = classifyPlan(org.capabilities);")

# 3) Replace the billing block with the API-first version (only if the old block
#    is present and not already upgraded).
NEW_BILLING = r'''const PT_MONTHS = { jan: 0, fev: 1, mar: 2, abr: 3, mai: 4, jun: 5, jul: 6, ago: 7, set: 8, out: 9, nov: 10, dez: 11 };
const EN_MONTHS = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11 };
function parseBillingDate(day, monthStr, year, locale) {
    const table = locale === "pt" ? PT_MONTHS : EN_MONTHS;
    const m = table[monthStr.slice(0, 3).toLowerCase()];
    if (m === undefined)
        return null;
    return new Date(parseInt(year, 10), m, parseInt(day, 10));
}
function parseBillingText(text) {
    let period = "unknown";
    let autoRenew = null;
    let billingDate = null;
    let daysLeft = null;
    // Relative day counters from the plan banner (PT: "termina em 12 dias").
    const relPt = text.match(/termina em (\d+)\s+dias?/i);
    if (relPt)
        daysLeft = parseInt(relPt[1], 10);
    const relEn = text.match(/ends?\s+in\s+(\d+)\s+days?/i);
    if (daysLeft === null && relEn)
        daysLeft = parseInt(relEn[1], 10);
    // Auto-renew signals. "Reassinar" / "Fazer Upgrade" mean the plan is lapsing.
    if (/reassinar|fazer upgrade|resubscribe/i.test(text))
        autoRenew = false;
    else if (/renova(?:ção)?\s+autom|renews automatically|próxima cobran|next billing/i.test(text))
        autoRenew = true;
    if (/mensal|monthly/i.test(text))
        period = "monthly";
    else if (/anual|annual|yearly/i.test(text))
        period = "annual";
    // Absolute-date fallbacks.
    const cancelPt = text.match(/será cancelada em (\d+) de (\w+)\.?\s*de (\d{4})/i);
    const renewPt = text.match(/(?:será renovada(?: automaticamente)?|próxima cobrança)\s+em\s+(\d+) de (\w+)\.?\s*de (\d{4})/i);
    const cancelEn = text.match(/(?:will\s+be\s+cancell?ed|(?:subscription\s+)?cancels)\s+on\s+(\w+)\s+(\d{1,2}),?\s+(\d{4})/i);
    const renewEn = text.match(/(?:(?:will\s+)?renews?(?: automatically)?|next\s+(?:billing|renewal))\s+(?:on\s+)?(\w+)\s+(\d{1,2}),?\s+(\d{4})/i);
    if (cancelPt) {
        autoRenew = false;
        billingDate = parseBillingDate(cancelPt[1], cancelPt[2], cancelPt[3], "pt");
    }
    else if (renewPt) {
        if (autoRenew === null)
            autoRenew = true;
        billingDate = parseBillingDate(renewPt[1], renewPt[2], renewPt[3], "pt");
    }
    else if (cancelEn) {
        autoRenew = false;
        billingDate = parseBillingDate(cancelEn[2], cancelEn[1], cancelEn[3], "en");
    }
    else if (renewEn) {
        if (autoRenew === null)
            autoRenew = true;
        billingDate = parseBillingDate(renewEn[2], renewEn[1], renewEn[3], "en");
    }
    if (!billingDate && daysLeft !== null)
        billingDate = new Date(Date.now() + daysLeft * 86400000);
    return { period, autoRenew, billingDate, daysLeft };
}
// Cloudflare-free: read plan + paid status straight from the JSON API.
async function fetchBillingMetaViaApi(storagePath) {
    if (!fs.existsSync(storagePath))
        return { plan: "unknown", paid: null };
    const api = await request.newContext({
        baseURL: CLAUDE_URL,
        storageState: storagePath,
        extraHTTPHeaders: { "User-Agent": USER_AGENT, Accept: "application/json" },
    });
    try {
        const orgsRes = await api.get("/api/organizations");
        if (!orgsRes.ok())
            return { plan: "unknown", paid: null };
        const orgs = await orgsRes.json();
        const org = orgs.find((o) => o.capabilities?.includes("chat")) || orgs[0];
        const plan = classifyPlan(org?.capabilities);
        let paid = plan === "free" ? false : null;
        if (org?.uuid) {
            const detail = await api.get(`/api/organizations/${org.uuid}`);
            if (detail.ok()) {
                const d = await detail.json();
                if (typeof d.billing_type === "string")
                    paid = d.billing_type !== "none";
            }
        }
        return { plan, paid };
    }
    catch {
        return { plan: "unknown", paid: null };
    }
    finally {
        await api.dispose();
    }
}
export async function fetchBillingForAccount(name) {
    const profileDir = getProfileDir(name);
    const storagePath = getStorageStatePath(name);
    if (!fs.existsSync(profileDir) && !fs.existsSync(storagePath)) {
        return { plan: "unknown", paid: null, period: "unknown", autoRenew: null, billingDate: null, daysLeft: null };
    }
    // 1) API-first (no Cloudflare): plan + paid/free.
    const meta = await fetchBillingMetaViaApi(storagePath);
    const base = { plan: meta.plan, paid: meta.paid, period: "unknown", autoRenew: null, billingDate: null, daysLeft: null };
    // Free accounts have no subscription to scrape — done, no browser needed.
    if (meta.plan === "free" || meta.paid === false) {
        return { ...base, paid: false, period: "free" };
    }
    // 2) Best-effort: scrape the plan banner for the renewal date (PT-aware). On a
    //    Cloudflare/parse failure, return the API plan + paid so the row shows the
    //    plan instead of a bare "Cloudflare block".
    const contextOpts = {
        headless: false,
        channel: "chrome",
        args: [
            "--disable-blink-features=AutomationControlled",
            "--disable-extensions",
            "--window-size=800,600",
            "--window-position=-32000,-32000",
        ],
        ignoreDefaultArgs: ["--enable-automation"],
        viewport: { width: 800, height: 600 },
    };
    if (fs.existsSync(storagePath))
        contextOpts.storageState = storagePath;
    const context = await chromium.launchPersistentContext(profileDir, contextOpts);
    const page = context.pages()[0] || (await context.newPage());
    try {
        await page.goto(CLAUDE_URL, { waitUntil: "domcontentloaded", timeout: 30000 });
        await page.waitForTimeout(2000);
        await page.goto(`${CLAUDE_URL}/settings/billing`, { waitUntil: "domcontentloaded", timeout: 30000 });
        try {
            await page.getByRole("button", { name: /reject all|accept all/i }).first().click({ timeout: 3000 });
        }
        catch {
            // No cookie banner shown.
        }
        try {
            await page.waitForFunction(() => {
                const t = document.body.innerText || "";
                if (/just a moment/i.test(t))
                    return false;
                if (/^\s*loading/i.test(t))
                    return false;
                return /(termina em|renova|próxima cobran|reassinar|monthly|annual|mensal|anual|renew|cancel|plano|plan)/i.test(t);
            }, { timeout: 20000 });
        }
        catch {
            // Timed out — parse whatever rendered below.
        }
        const text = await page.evaluate(() => document.body.innerText);
        // Read-only flow — never persist storageState (would clobber the session).
        await context.close();
        const parsed = parseBillingText(text);
        if (parsed.billingDate || parsed.daysLeft !== null || parsed.period !== "unknown" || parsed.autoRenew !== null) {
            return { ...base, ...parsed, paid: true };
        }
        fs.writeFileSync(`/tmp/claudestatus_billing_${name}.txt`, text);
        return { ...base, paid: true };
    }
    catch {
        await context.close().catch(() => { });
        // Cloudflare / navigation error — still report the API-derived plan + paid.
        return { ...base, paid: meta.paid === null ? true : meta.paid };
    }
}
export async function fetchAllBilling(accountNames) {
    const results = [];
    for (const name of accountNames) {
        process.stdout.write(`  Billing ${name}...`);
        const billing = await fetchBillingForAccount(name);
        console.log(" done");
        results.push({ name, ...billing });
    }
    return results;
}
'''

if "fetchBillingMetaViaApi" not in src:
    pat = re.compile(r"const PT_MONTHS = \{.*?\n(?=async function waitForLoginSignal)", re.S)
    if pat.search(src):
        src = pat.sub(lambda m: NEW_BILLING + "\n", src, count=1)

if src != original:
    path.write_text(src)
    print("  ✓ api.js patched")
else:
    print("  ⚠  api.js already up to date")
PYEOF

# ── display.js: plan-aware usage table + Account/Plan/Paid/Renewal billing ───
cat > "$DISPLAY_JS" <<'DISPLAY_EOF'
import chalk from "chalk";
import Table from "cli-table3";

function formatResetTime(isoString) {
    const date = new Date(isoString);
    const now = new Date();
    const diffMs = date.getTime() - now.getTime();
    if (diffMs < 0) return "now";
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMins / 60);
    const diffDays = Math.floor(diffHours / 24);
    if (diffMins < 60) {
        return `${diffMins}m`;
    } else if (diffHours < 24) {
        const mins = diffMins % 60;
        return mins > 0 ? `${diffHours}h ${mins}m` : `${diffHours}h`;
    } else {
        const hours = diffHours % 24;
        return hours > 0 ? `${diffDays}d ${hours}h` : `${diffDays}d`;
    }
}

function usageBar(percent, width = 8) {
    const filled = Math.round((percent / 100) * width);
    const empty = width - filled;
    let color = chalk.green;
    if (percent >= 90) color = chalk.red;
    else if (percent >= 70) color = chalk.yellow;
    return color("█".repeat(filled)) + chalk.gray("░".repeat(empty));
}

function formatUsageCell(limit) {
    if (!limit) return chalk.gray("—");
    const bar = usageBar(limit.utilization);
    const pct = limit.utilization.toString().padStart(3) + "%";
    const reset = chalk.gray(" ↻" + formatResetTime(limit.resets_at));
    return `${bar} ${pct}${reset}`;
}

function planLabel(plan) {
    if (plan === "max") return chalk.magenta("Max");
    if (plan === "team") return chalk.blue("Team");
    if (plan === "free") return chalk.red("Free");
    if (plan === "pro") return chalk.cyan("Pro");
    return chalk.gray("—");
}

function formatStatusCell(account) {
    if (account.error) return chalk.red("✗ Error");
    if (account.plan === "free") return chalk.red("✗ Free");
    if (account.plan === "unknown") return chalk.yellow("? Unknown");
    return chalk.green("✓ Active");
}

function getAvailability(account) {
    if (account.error) {
        return { status: "error", waitLabel: account.error, waitMs: Number.POSITIVE_INFINITY, reason: "none" };
    }
    // A Free account cannot run Claude Code work — never recommend it.
    if (account.plan === "free") {
        return { status: "unusable", waitLabel: "Upgrade", waitMs: Number.POSITIVE_INFINITY, reason: "free" };
    }
    const weekly = account.usage.seven_day;
    const session = account.usage.five_hour;
    if (weekly && weekly.utilization >= 100) {
        const waitMs = Math.max(0, new Date(weekly.resets_at).getTime() - Date.now());
        return { status: waitMs <= 0 ? "available" : "wait", waitLabel: formatResetTime(weekly.resets_at), waitMs, reason: "weekly" };
    }
    if (session && session.utilization >= 100) {
        const waitMs = Math.max(0, new Date(session.resets_at).getTime() - Date.now());
        return { status: waitMs <= 0 ? "available" : "wait", waitLabel: formatResetTime(session.resets_at), waitMs, reason: "session" };
    }
    return { status: "available", waitLabel: "now", waitMs: 0, reason: "none" };
}

function formatNextUseLabel(availability) {
    if (availability.status === "unusable") return chalk.red("Upgrade req.");
    if (availability.status === "available" || availability.waitLabel === "now") return chalk.green("Use now");
    if (availability.reason === "weekly") return chalk.yellow(`Wait until ${availability.waitLabel}`);
    return chalk.yellow(`Wait ${availability.waitLabel}`);
}

function pickNextAccount(accounts) {
    // Exclude error rows and Free accounts (Free cannot be used for Pro work).
    const available = accounts.filter((a) => !a.error && a.plan !== "free");
    if (available.length === 0) return null;
    const scored = available.map((account) => ({
        account,
        availability: getAvailability(account),
        score: (account.usage.five_hour?.utilization ?? 0) + (account.usage.seven_day?.utilization ?? 0),
    }));
    const usable = scored.filter((entry) => entry.availability.status === "available");
    if (usable.length > 0) return usable.reduce((a, b) => (a.score <= b.score ? a : b));
    return scored.reduce((a, b) => {
        if (a.availability.waitMs === b.availability.waitMs) return a.score <= b.score ? a : b;
        return a.availability.waitMs <= b.availability.waitMs ? a : b;
    });
}

export function displayUsageTable(accounts) {
    console.log();
    console.log(chalk.bold("  Claude Usage Dashboard"));
    console.log(chalk.gray("  Note: 'Days left' shows rate-limit window resets, not billing renewal dates."));
    console.log();
    const table = new Table({
        head: [chalk.bold("Account"), chalk.bold("Plan"), chalk.bold("Status"), chalk.bold("Session (5h)"), chalk.bold("Weekly (7d)"), chalk.bold("Next Use")],
        style: { head: [], border: [] },
        colWidths: [14, 6, 12, 22, 22, 20],
    });
    for (const account of accounts) {
        const availability = getAvailability(account);
        if (account.error) {
            table.push([chalk.yellow(account.name), chalk.gray("—"), chalk.red("✗ Error"), chalk.gray("—"), chalk.gray("—"), chalk.red(account.error.split(".")[0])]);
            continue;
        }
        table.push([
            account.name,
            planLabel(account.plan),
            formatStatusCell(account),
            formatUsageCell(account.usage.five_hour),
            formatUsageCell(account.usage.seven_day),
            formatNextUseLabel(availability),
        ]);
    }
    console.log(table.toString());
    console.log();
    const next = pickNextAccount(accounts);
    if (next) {
        const nextUseLabel = next.availability.status === "available" ? "Use now" : `Wait ${next.availability.waitLabel}`;
        console.log(chalk.cyan("  💡 Recommendation: ") + chalk.bold(next.account.name) + chalk.gray(` (${nextUseLabel})`));
        console.log();
    }
}

export function displayBillingTable(billingData) {
    console.log(chalk.bold("  Billing Status"));
    console.log();
    const table = new Table({
        head: [chalk.bold("Account"), chalk.bold("Plan"), chalk.bold("Paid"), chalk.bold("Renewal"), chalk.bold("Auto-Renew")],
        style: { head: [], border: [] },
        colWidths: [14, 8, 9, 21, 13],
    });
    for (const b of billingData) {
        const paidLabel = b.paid === true ? chalk.green("✓ Paid") : b.paid === false ? chalk.gray("Free") : chalk.gray("—");
        let renewal = chalk.gray("—");
        if (b.billingDate) {
            const d = new Date(b.billingDate);
            const days = b.daysLeft != null ? b.daysLeft : Math.ceil((d.getTime() - Date.now()) / 86400000);
            const dateStr = d.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
            renewal = `${days <= 0 ? chalk.red("expired") : days + "d"} · ${dateStr}`;
        } else if (b.daysLeft != null) {
            renewal = b.daysLeft <= 0 ? chalk.red("expired") : `~${b.daysLeft}d`;
        } else if (b.error) {
            renewal = chalk.yellow(b.error.split("—")[0].trim());
        }
        const autoRenewLabel = b.autoRenew === true ? chalk.green("✓ Auto") : b.autoRenew === false ? chalk.red("✗ Expires") : chalk.gray("—");
        table.push([b.name, planLabel(b.plan), paidLabel, renewal, autoRenewLabel]);
    }
    console.log(table.toString());
    console.log();
}

export function displayQuickRecommendation(accounts) {
    const next = pickNextAccount(accounts);
    if (!next) {
        console.log(chalk.red("No accounts available. Run: claudestatus add <name>"));
        return;
    }
    const nextUseLabel = next.availability.status === "available" ? "Use now" : `Wait ${next.availability.waitLabel}`;
    console.log(`${next.account.name} (${nextUseLabel})`);
}
DISPLAY_EOF

echo ""
echo "✅  claudestatus patch complete (api.js + display.js)."
echo "    Run 'claudestatus' to verify."
echo "    Plan/paid come from the API (no Cloudflare); renewal dates are a"
echo "    best-effort scrape. Free accounts are flagged unusable and excluded"
echo "    from the recommendation."
