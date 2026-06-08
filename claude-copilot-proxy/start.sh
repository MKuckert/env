#!/usr/bin/env bash
~/env/background-run/backgrounded.sh start copilot-proxy bunx copilot-api start -a business -p 11500
trap "~/env/background-run/backgrounded.sh stop copilot-proxy" EXIT

export ANTHROPIC_BASE_URL=http://localhost:11500 ANTHROPIC_AUTH_TOKEN=dummy ANTHROPIC_MODEL=claude-sonnet-4.6 ANTHROPIC_DEFAULT_SONNET_MODEL=claude-sonnet-4.6 ANTHROPIC_SMALL_FAST_MODEL=claude-haiku-4.5 ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-haiku-4.5 DISABLE_NON_ESSENTIAL_MODEL_CALLS=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 && claude
