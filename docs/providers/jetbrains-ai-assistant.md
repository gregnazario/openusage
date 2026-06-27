# JetBrains AI Assistant

OpenUsage tracks JetBrains AI Assistant quota from the local IDE quota cache.

## What It Reads

OpenUsage scans JetBrains IDE config folders under `~/Library/Application Support/JetBrains` and reads each IDE's `options/AIAssistantQuotaManager2.xml`.

## Metrics

- Quota: used percentage
- Used: used quota amount
- Remaining: remaining quota amount when available

When JetBrains stores quota in internal fine-grained units, OpenUsage displays the values as credits. If multiple IDEs have quota files, OpenUsage uses the freshest quota window.
