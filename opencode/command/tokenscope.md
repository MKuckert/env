---
description: Analyze token usage across the current session with detailed breakdowns by category
agent: build
# TODO(#113): "google/fast-cheap" is a V1 model alias; pin the real V2
# model ID after verifying against the host's provider catalog.
model: google/fast-cheap
---

Call the tokenscope tool directly without delegating to other agents.
Then tell the user the token-usage-output.txt has been generated. DON'T DO ANYTHING ELSE WITH THE OUTPUT OR FILE.
