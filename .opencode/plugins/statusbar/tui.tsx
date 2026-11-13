/**
 * opencode-plugin-statusbar (OpenCode V2 port)
 *
 * Shows per-session token usage and cost in the prompt footer status area.
 * Ported from the V1 npm package `opencode-plugin-statusbar` for issue #113
 * (V1 → V2 migration).
 *
 * V2 API mapping:
 *   - V1 slot `app_bottom` (via api.slots.register) -> ui.slot append on
 *     "prompt.footer.status" (the assistant footer status area; the slot
 *     input carries the current sessionID reactively)
 *   - V1 `api.state.session.messages(id)` (role: "assistant") ->
 *     context.data.session.message.list(id) (type: "assistant")
 *   - V1 `api.theme.current().textMuted/.text` -> context.theme.text.muted/.base
 *   - V1 `api.route.current.params.sessionID` -> slot input.sessionID
 */
import { Plugin } from "@opencode/plugin/tui"
import { createMemo, Show } from "solid-js"

const fmtTokens = (value: number) => {
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`
  if (value >= 1_000) return `${(value / 1_000).toFixed(1)}k`
  return `${value}`
}

const fmtCost = (value: number) => {
  if (!value) return "$0"
  if (value < 0.01) return `$${value.toFixed(4)}`
  return `$${value.toFixed(2)}`
}

interface Totals {
  input: number
  output: number
  reasoning: number
  cacheRead: number
  cacheWrite: number
  cost: number
}

const View = (props: { context: Plugin.Context; sessionID?: string }) => {
  const totals = createMemo<Totals | undefined>(() => {
    const id = props.sessionID
    if (!id) return undefined
    let input = 0
    let output = 0
    let reasoning = 0
    let cacheRead = 0
    let cacheWrite = 0
    let cost = 0
    for (const message of props.context.data.session.message.list(id)) {
      if (message.type !== "assistant") continue
      const tokens = message.tokens
      if (!tokens) continue
      input += tokens.input
      output += tokens.output
      reasoning += tokens.reasoning
      cacheRead += tokens.cache.read
      cacheWrite += tokens.cache.write
      cost += message.cost ?? 0
    }
    return { input, output, reasoning, cacheRead, cacheWrite, cost }
  })

  return (
    <Show when={totals()} fallback={null}>
      {(t: () => Totals) => (
        <box flexDirection="row" justifyContent="flex-end" gap={2} paddingRight={2}>
          <text fg={props.context.theme.text.muted}>in {fmtTokens(t().input)}</text>
          <text fg={props.context.theme.text.muted}>out {fmtTokens(t().output)}</text>
          <Show when={t().reasoning > 0}>
            <text fg={props.context.theme.text.muted}>r {fmtTokens(t().reasoning)}</text>
          </Show>
          <Show when={t().cacheRead > 0 || t().cacheWrite > 0}>
            <text fg={props.context.theme.text.muted}>
              cache {fmtTokens(t().cacheRead)}/{fmtTokens(t().cacheWrite)}
            </text>
          </Show>
          <text fg={props.context.theme.text.base}>
            <b>{fmtCost(t().cost)}</b>
          </text>
        </box>
      )}
    </Show>
  )
}

export default Plugin.define({
  id: "statusbar.tokens",
  setup(context) {
    // Additive claim on the assistant footer status area (where the built-in
    // TPS readout lives). The slot input's sessionID is reactive, so the
    // totals follow the active session.
    return context.ui.slot({
      append: "prompt.footer.status",
      render: (input) => <View context={context} sessionID={input.sessionID} />,
    })
  },
})
