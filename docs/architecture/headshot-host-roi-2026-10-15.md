# Headshot event ROI per host

Generated 2026-10-15 14:49 UTC against `d4c7q2h3ed4nvs` (latest order 2026-10-14 23:04 UTC), insgt-api `unknown` (release v649, `master` b7b2de9f; the slug carries no `.git`, so the sha is recorded by hand). Reproduce: `bin/rails marketing_events:host_roi`. Read-only; nothing is persisted. Contract: docs/architecture/account-classification.md §5.5.

## Rules

- An attendee is an active account, not typed internal, with a delivered headshot event order. Each attendee is counted once, under one host.
- A convert is an attendee with an event order before its first paid listing shoot. It counts under the host of the latest such order (the one event attribution credits); when that event has no host, under No host, never under another host.
- An already customer bought its first paid listing before any event it attended. It counts under the host of its latest delivered event order and is never a convert.
- An attendee with no paid listing counts under the host of its latest delivered event order.
- Events are every event the host has held, whatever its status. Converts' lifetime value is `account_metrics.lifetime_value_cents`.
- Headshot media is held back from release for a few days after most events. An account whose event orders are all pending release is not yet an attendee; it is counted once delivered, by the next run. An attendee sits under its latest delivered event's host until a pending order releases, so this table is a point-in-time read.

## Hosts

| Host | Source | Events | Attendees | Converts | Conversion | Already customers | Converts' lifetime value |
| :-- | :-- | --: | --: | --: | --: | --: | --: |
| PSAR | psar_event | 56 | 809 | 14 | 1.7% | 12 | $6,575.00 |
| NSDCR | nsdcr_event | 53 | 636 | 71 | 11.2% | 66 | $79,974.00 |
| SDAR | sdar_event | 23 | 320 | 12 | 3.8% | 13 | $8,875.00 |
| RE/MAX Tidal | none | 3 | 36 | 11 | 30.6% | 6 | $18,410.00 |
| Coldwell Banker Realty - Vista | none | 2 | 29 | 5 | 17.2% | 5 | $5,058.00 |
| ROA California Inc. | none | 1 | 27 | 0 | 0.0% | 6 | $0.00 |
| Fairway Mortgage | none | 1 | 25 | 1 | 4.0% | 1 | $495.00 |
| Century 21 | none | 2 | 24 | 4 | 16.7% | 1 | $1,320.00 |
| Realty Executives | none | 1 | 24 | 1 | 4.2% | 2 | $1,720.00 |
| Title365 | none | 2 | 23 | 5 | 21.7% | 0 | $910.00 |
| Carrington Real Estate Services | none | 1 | 20 | 4 | 20.0% | 1 | $2,210.00 |
| Sea Coast Exclusive Properties | none | 1 | 19 | 6 | 31.6% | 9 | $3,820.00 |
| Windermere Homes & Estates-Rancho Bernardo | none | 1 | 19 | 9 | 47.4% | 0 | $58,473.00 |
| New Palace Realty | none | 3 | 18 | 8 | 44.4% | 4 | $8,465.00 |
| RE/MAX | none | 1 | 17 | 4 | 23.5% | 2 | $17,005.00 |
| Harcourts | none | 2 | 16 | 3 | 18.8% | 1 | $2,450.00 |
| Guild Mortgage | none | 3 | 15 | 2 | 13.3% | 0 | $2,970.00 |
| Coastal Premier Properties | none | 1 | 14 | 0 | 0.0% | 0 | $0.00 |
| San Diego Castles Realty | none | 1 | 14 | 2 | 14.3% | 6 | $2,505.00 |
| Home Solutions Realty | none | 1 | 13 | 4 | 30.8% | 0 | $1,654.00 |
| Plaza Real Estate | none | 2 | 12 | 2 | 16.7% | 1 | $3,145.00 |
| Sunshine Properties RealEstate | none | 1 | 12 | 1 | 8.3% | 0 | $305.00 |
| Foundation Escrow | none | 1 | 11 | 0 | 0.0% | 0 | $0.00 |
| Harcourts Prime Properties | none | 1 | 11 | 6 | 54.5% | 1 | $25,544.00 |
| Windermere Real Estate | none | 2 | 11 | 2 | 18.2% | 1 | $24,290.00 |
| YPN | none | 1 | 11 | 1 | 9.1% | 1 | $475.00 |
| Pacific Sotheby's International Realty | none | 1 | 10 | 6 | 60.0% | 1 | $53,357.00 |
| Windermere Homes & Estates-Escondido | none | 1 | 10 | 1 | 10.0% | 0 | $165.00 |
| Coastal Pacific | none | 1 | 8 | 0 | 0.0% | 0 | $0.00 |
| Corner Escrow | none | 1 | 8 | 3 | 37.5% | 1 | $7,713.00 |
| Silva Coast Realty | none | 2 | 8 | 1 | 12.5% | 1 | $5,085.00 |
| United Real Estate | none | 1 | 8 | 2 | 25.0% | 1 | $2,844.00 |
| Burke Real Estate Consultants, Inc. | none | 2 | 7 | 1 | 14.3% | 0 | $1,764.00 |
| Coldwell Banker Realty-Carmel Valley | none | 1 | 6 | 0 | 0.0% | 1 | $0.00 |
| Devine Fog Realty | none | 1 | 6 | 0 | 0.0% | 0 | $0.00 |
| Pacific Sotheby's International Realty - Carlsbad | none | 1 | 6 | 1 | 16.7% | 0 | $584.00 |
| RE/MAX Home Center | none | 1 | 6 | 1 | 16.7% | 1 | $1,000.00 |
| ELITE Homes San Diego | none | 1 | 5 | 0 | 0.0% | 1 | $0.00 |
| Wells Fargo | none | 1 | 4 | 0 | 0.0% | 0 | $0.00 |
| iServe Lending | none | 1 | 4 | 0 | 0.0% | 0 | $0.00 |
| Windermere Homes & Estates-Aviara/South Carlsbad | none | 1 | 3 | 0 | 0.0% | 0 | $0.00 |
| American Portfolio Mortgage | none | 1 | 2 | 0 | 0.0% | 0 | $0.00 |
| Shay Realtors | none | 1 | 2 | 0 | 0.0% | 0 | $0.00 |
| Ken May Team | none | 1 | 1 | 0 | 0.0% | 1 | $0.00 |
| Lily Field Realty | none | 1 | 1 | 0 | 0.0% | 1 | $0.00 |
| No host | none | 10 | 51 | 9 | 17.6% | 3 | $5,540.00 |
| **Total** |  | 198 | 2,342 | 203 | 8.7% | 151 | $354,700.00 |

Totals check: hosts plus the no-host row = 2,342 distinct attendees — OK

## Pending release

Accounts with media not yet released, and no delivered event order: 1. Each event below rolls into the table once released.

- 1 on event 1333 (SDAR), 1 not yet an attendee
