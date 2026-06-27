# OpenCode Go

OpenUsage tracks observed OpenCode Go usage from local OpenCode data on this Mac.

## What It Reads

- Auth detection from `~/.local/share/opencode/auth.json`
- Usage history from `~/.local/share/opencode/opencode.db`

The provider appears when either OpenCode Go auth exists or local history already contains OpenCode Go assistant messages with numeric cost.

## Metrics

- Session: last 5 hours of observed local spend against the current Go session limit
- Weekly: UTC Monday-to-Monday observed local spend
- Monthly: observed local spend in a month window anchored to the earliest local OpenCode Go usage

If OpenCode Go is detected but SQLite cannot be read, OpenUsage keeps the provider visible and shows `No Usage Data`.
