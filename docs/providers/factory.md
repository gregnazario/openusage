# Factory

OpenUsage tracks Factory Droid subscription usage from Factory's organization usage API.

## What It Reads

OpenUsage looks for Droid auth in this order:

- `~/.factory/auth.v2.file` plus `~/.factory/auth.v2.key`
- `~/.factory/auth.encrypted`
- `~/.factory/auth.json`
- Factory/Droid macOS Keychain entries

If the access token is near expiry, OpenUsage refreshes it through WorkOS and writes the refreshed token back to the same source when possible.

## Metrics

- Standard: organization standard tokens used out of allowance
- Premium: premium tokens used out of allowance, when the plan includes premium tokens

The plan label is inferred from the standard allowance: Basic, Pro, or Max.
