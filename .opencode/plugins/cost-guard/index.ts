/**
 * opencode-cost-guard (OpenCode V2 port)
 *
 * Monitors session cost and triggers a warning or stop when a configurable
 * threshold is reached. Ported from the V1 npm package `opencode-cost-guard`
 * for issue #113 (V1 → V2 migration).
 *
 * V2 API mapping:
 *   - V1 `event` hook ("session.idle")        -> ctx.event.subscribe() loop
 *   - V1 `client.session.messages()` cost sum -> ctx.session.get().cost
 *     (V2 exposes the cumulative session cost directly on SessionInfo)
 *   - V1 `client.session.prompt({noReply})`   -> ctx.session.synthetic()
 *     (synthetic message: shown in the session, no model reply)
 *
 * Config is read from (first found wins):
 *   1. <project>/.opencode/cost-guard.config.json
 *   2. ~/.config/opencode/cost-guard.config.json
 *   3. Built-in defaults
 */
import { readFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { Plugin } from "@opencode/plugin";

// ─── Logging ──────────────────────────────────────────────────────────────────
/**
 * Verbose debug logging is opt-in via COST_GUARD_DEBUG=1.
 * Warnings and errors always print regardless of this flag.
 */
const DEBUG = process.env.COST_GUARD_DEBUG === "1";
const log = {
  /** Always printed — startup confirmation and real errors only. */
  info: (msg: string) => console.info(`[cost-guard] ${msg}`),
  /** Always printed — something the user should act on. */
  warn: (msg: string, err?: unknown) =>
    err ? console.warn(`[cost-guard] ${msg}`, err) : console.warn(`[cost-guard] ${msg}`),
  /** Always printed — unexpected failures. */
  error: (msg: string, err?: unknown) =>
    err ? console.error(`[cost-guard] ${msg}`, err) : console.error(`[cost-guard] ${msg}`),
  /** Printed only when COST_GUARD_DEBUG=1 — high-frequency / verbose lines. */
  debug: (msg: string) => {
    if (DEBUG) console.info(`[cost-guard] ${msg}`);
  },
};

// ─── Defaults ─────────────────────────────────────────────────────────────────
const DEFAULTS: CostGuardConfig = {
  maxCostUsd: 20.0,
  warnAtPercent: 80,
  mode: "warn",
};
const CONFIG_FILENAME = "cost-guard.config.json";

interface CostGuardConfig {
  maxCostUsd: number;
  warnAtPercent: number;
  mode: "warn" | "block";
}

// ─── Config loading ───────────────────────────────────────────────────────────
/**
 * Loads plugin config from disk.
 *
 * Priority order (first found wins):
 *   1. <location>/.opencode/cost-guard.config.json
 *   2. <project root>/.opencode/cost-guard.config.json (when different)
 *   3. ~/.config/opencode/cost-guard.config.json
 *   4. Built-in defaults
 */
function loadConfig(locationDirectory: string, projectDirectory?: string): CostGuardConfig {
  const candidates = [join(locationDirectory, ".opencode", CONFIG_FILENAME)];
  if (projectDirectory && projectDirectory !== locationDirectory) {
    candidates.push(join(projectDirectory, ".opencode", CONFIG_FILENAME));
  }
  candidates.push(join(homedir(), ".config", "opencode", CONFIG_FILENAME));

  for (const configPath of candidates) {
    if (!existsSync(configPath)) continue;
    try {
      const raw = readFileSync(configPath, "utf-8")
        .replace(/\/\/[^\n]*/g, "") // strip // line comments
        .replace(/\/\*[\s\S]*?\*\//g, ""); // strip /* block comments */
      const parsed = JSON.parse(raw) as Record<string, unknown>;
      const config: CostGuardConfig = { ...DEFAULTS };
      if (typeof parsed.maxCostUsd === "number" && parsed.maxCostUsd > 0) {
        config.maxCostUsd = parsed.maxCostUsd;
      }
      if (
        typeof parsed.warnAtPercent === "number" &&
        parsed.warnAtPercent >= 0 &&
        parsed.warnAtPercent <= 100
      ) {
        config.warnAtPercent = parsed.warnAtPercent;
      }
      if (parsed.mode === "warn" || parsed.mode === "block") {
        config.mode = parsed.mode;
      }
      log.debug(`Config loaded from: ${configPath}`);
      return config;
    } catch (err) {
      log.warn(`Failed to read ${configPath}:`, err);
    }
  }
  log.debug(`No config file found (checked: ${candidates.join(", ")}), using defaults.`);
  return { ...DEFAULTS };
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
const fmt = (usd: number) => `$${usd.toFixed(4)}`;
const pct = (cost: number, max: number) => Math.round((cost / max) * 100);

// ─── Plugin ───────────────────────────────────────────────────────────────────
export default Plugin.define({
  id: "opencode-cost-guard",

  async setup(ctx) {
    const cfg = loadConfig(ctx.location.directory, ctx.location.project.directory);

    // Always printed — one line at startup so the user can confirm active config.
    log.info(
      `Active — limit: ${fmt(cfg.maxCostUsd)} | warn at: ${cfg.warnAtPercent}% | mode: ${cfg.mode}` +
        (DEBUG ? " | debug: on" : ""),
    );

    // Track per-session state to avoid duplicate messages.
    const warnedSessions = new Set<string>();
    const blockedSessions = new Set<string>();

    // Subscribe to the session event stream for the lifetime of the plugin.
    const abort = new AbortController();
    void (async () => {
      for await (const event of ctx.event.subscribe({ signal: abort.signal })) {
        // Only act after the model has finished responding.
        if (event.type !== "session.idle") continue;
        const sessionId = event.data.sessionID;
        log.debug(`session.idle received — sessionId: ${sessionId ?? "(none)"}`);
        if (!sessionId || blockedSessions.has(sessionId)) continue;

        try {
          // V2 exposes the cumulative session cost directly (V1 summed
          // assistant message costs via client.session.messages()).
          const info = await ctx.session.get({ sessionID: sessionId });
          const cost = Number(info.cost ?? 0);
          log.debug(
            `session ${sessionId} — cost: ${fmt(cost)}, limit: ${fmt(cfg.maxCostUsd)}`,
          );

          const { maxCostUsd, warnAtPercent, mode } = cfg;
          const warnThreshold = maxCostUsd * (warnAtPercent / 100);

          // ── Limit reached ───────────────────────────────────────────────
          if (cost >= maxCostUsd) {
            blockedSessions.add(sessionId);
            const msg =
              mode === "block"
                ? [
                    `⛔ **COST LIMIT REACHED** — Session automatically stopped.`,
                    `Cost: ${fmt(cost)} / Limit: ${fmt(maxCostUsd)} (${pct(cost, maxCostUsd)}%)`,
                    ``,
                    `This session will no longer respond to new requests.`,
                    `Start a new session to continue working.`,
                  ].join("\n")
                : [
                    `⛔ **COST LIMIT REACHED** — Cost: ${fmt(cost)} / ${fmt(maxCostUsd)} (${pct(cost, maxCostUsd)}%)`,
                    ``,
                    `Configured limit reached. Consider starting a new session or`,
                    `update "maxCostUsd" in ${CONFIG_FILENAME}.`,
                  ].join("\n");
            // Synthetic message: injected into the session without a model reply.
            await ctx.session.synthetic({ sessionID: sessionId, text: msg });
          }

          // ── Early warning (fired once per session) ──────────────────────
          // else-if: a blocked session must not also receive the warning in
          // the same iteration; later events are skipped via blockedSessions.
          else if (warnAtPercent > 0 && cost >= warnThreshold && !warnedSessions.has(sessionId)) {
            warnedSessions.add(sessionId);
            await ctx.session.synthetic({
              sessionID: sessionId,
              text: [
                `⚠️  **COST WARNING** — ${pct(cost, maxCostUsd)}% of budget used.`,
                `Cost: ${fmt(cost)} — Limit: ${fmt(maxCostUsd)} — Remaining: ${fmt(maxCostUsd - cost)}`,
              ].join("\n"),
            });
          }
        } catch (err) {
          // Defensive catch — an unexpected error must not silence future events.
          log.error(`Unexpected error in event handler (session ${sessionId}):`, err);
        }
      }
    })();

    // Cleanup: stop the subscription when the plugin is unloaded.
    return () => abort.abort();
  },
});
