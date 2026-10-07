# Marketing event host audit: the host of every headshot event

**Date:** 2026-10-07 · **Contract:** `docs/architecture/account-classification.md` v9 §3.2, §3.5 ("Dan maps each token to an `organization_id`") · **Plan:** `docs/plans/account-classification-slice-6.md` G3–G5, OQ3, OQ4, OQ8, OQ11 · **Repo:** `apps/insgt-api` branch `feat/account-classification-slice-6-hosts` (0e71d2b, 53a6108, a85b694), deployed to production as slice 6 event 1 · **Task:** `rake marketing_events:audit_hosts` (`lib/tasks/marketing_events.rake`). Read-only; nothing was persisted.

Evidence conventions: the read-out in §5 is the **production** run, captured on a one-off dyno on 2026-10-07 (`heroku run --no-tty --exit-code rake marketing_events:audit_hosts -a insgtapi`). It is compared against the dev run on the 2026-10-02 restore. Organization ids and names come from the dev restore and match production line for line in the read-out's section 3. **This document is the input to migration 3** (`backfill_marketing_event_hosts`, slice 6 event 2): its `HOSTS`, `HOST_BY_EVENT_ID` and `SOURCE_BY_HOST` are transcribed from §2–§3.

---

## 1. What the production run says

- **196 events, all active, none with a host.** Production equals the restore: `diff` of the two runs from line 4 on is empty (500 lines each). No event was created after the survey; the newest is 1401 (2026-09-09).
- **`MAP_CUTOFF = 2026-10-07T12:30:10.007557Z`.** Migration 3 raises for any event created before this instant that the map misses, and leaves later events NULL (OQ8). The read-out's section 6, run with `MAP_CUTOFF=` set, lists those later events after the backfill.
- **The draft acronym parse** (section 2): PSAR 55, NSDCAR 41, NSDCR 11, SDAR 21, SDREA 1, YPN 1, no acronym 66 — identical to the survey's M3. The parse is a survey aid; the map is keyed by event id.
- **Rows to judge by hand** (sections 4–5): eight name-only candidates (2, 14, 29, 31, 35, 56, 73, 147); five events with no active orders (2, 14, 31, 35, 51); three with no `scheduled_at` (14, 31, 35); five container-order accounts, none of them a host signal (§4.2's organization-proxy accounts).

## 2. Rules the map follows

| Rule | Source |
| :-- | :-- |
| NSDCAR and NSDCR are one organization, **"NSDCR"**, sourced `nsdcr_event` | OQ3 |
| Only **PSAR → `psar_event`, NSDCR → `nsdcr_event`, SDAR → `sdar_event`** carry a source; every other host keeps `marketing_source_id` NULL | OQ4 |
| Boards and associations are typed **`association` (9)** | OQ2 |
| A brokerage host maps to an **existing** organization where one exists: the **office row** when the event name names a location that matches one, otherwise the **franchise row** | OQ11; office-vs-franchise rule, Dan 2026-10-07 |
| A host with no organization gets a **new** row: `brokerage` (2) or `lender` (3), or `agent` (5, agent team) where Dan named a team. Title and escrow companies are typed `lender` | OQ11; Dan 2026-10-07 |
| **No host (NULL)** for Insight's own rows: 2 Test, 14 Marketing, 31 Aerial Marketing, 35 Glen Oaks Escrow Booth, 73 Misc., 147 Maha Staging / Scripps Ranch Caravan | OQ11 |
| **No host (NULL)** also for 3 Stagers Luncheon, 7 Abriendo Puertas, 10 Double peak and 139 Tour 702 Carmel Valley: no outside host is recorded for them. Stored the same way as Insight-hosted | Dan, 2026-10-07 |
| **29 "Expo 2016-06-16" → NSDCR**; 56 "NSDCAR Expo" → NSDCR by its acronym | OQ11 |
| **22 "SDREA" → SDAR**: the name is a typo for SDAR; there is no SDREA organization | Dan, 2026-10-07 |
| Location tokens are ignored: one PSAR, one NSDCR, one SDAR | §3.5 |

**Resolution is by name *and* type, not by name alone.** Three names are each held by an active franchise row and an active brokerage row: Coldwell Banker Realty (142 franchise, 670 brokerage), Pacific Sotheby's International Realty (30, 472) and Windermere Real Estate (61, 647). The model's uniqueness is scoped to `[status_type, type_of]` (`organization.rb:29–31`), so this is legal, and a name-only lookup would resolve to two rows and raise. Each `HOSTS` entry therefore carries `type_of`, and migration 3 resolves an entry to the one active organization with that name and type. It creates a row only when **no** active row has the name under any type, and raises when the name exists only under a different type. Of the three, the map uses only 30 (Pacific Sotheby's, franchise) and 61 (Windermere Real Estate, franchise).

## 3. The map

### 3.1 Association hosts (created, `association` 9) — 131 events

| Host | Source | Events | Event ids |
| :-- | :-- | --: | :-- |
| PSAR | `psar_event` | 55 | 142, 143, 144, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 163, 164, 165, 166, 167, 169, 171, 172, 173, 174, 176, 177, 178, 211, 244, 277, 343, 376, 442, 475, 508, 541, 574, 607, 640, 739, 838, 905, 1003, 1036, 1070, 1135, 1137, 1169, 1234, 1267, 1301, 1366, 1400 |
| NSDCR | `nsdcr_event` | 53 | NSDCAR (41): 40, 42, 43, 46, 48, 52, 53, 56, 59, 62, 65, 67, 69, 70, 71, 72, 74, 75, 77, 78, 79, 80, 82, 83, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 130, 134, 137, 138 · NSDCR (11): 141, 145, 146, 162, 168, 170, 175, 409, 673, 1037, 1136 · **29** (Expo) |
| SDAR | `sdar_event` | 22 | **22** ("SDREA", a typo for SDAR) · 28, 68, 129, 131, 132, 706, 772, 805, 904, 937, 970, 1038, 1069, 1102, 1168, 1235, 1237, 1300, 1333, 1399, 1401 |
| YPN | none | 1 | 25 |

### 3.2 Brokerage, lender and agent team hosts — 55 events

**Existing organizations** (office row where the name names a matching location; franchise row otherwise):

| Event | Name | Host (id, type) | Basis |
| --: | :-- | :-- | :-- |
| 1 | Windermere Homes & Estates / Rancho Bernardo | 167 Windermere Homes & Estates-Rancho Bernardo (brokerage) | office |
| 5 | Windermere Homes & Estates Aviara Sept 10 | 165 Windermere Homes & Estates-Aviara/South Carlsbad (brokerage) | office |
| 11 | Century 21 Nov 6 | 141 Century 21 (franchise) | franchise |
| 12 | Carrington Dec 2 | 14 Carrington Real Estate Services (franchise) | franchise |
| 15 | Harcourts Prime Properties Headshot Event | 215 Harcourts Prime Properties (brokerage) | exact brokerage |
| 16 | Burke WebPortraits | 92 Burke Real Estate Consultants, Inc. (brokerage) | only row |
| 17 | ELITE Homes San Diego Web Portraits | 47 ELITE Homes San Diego (brokerage) | only row |
| 19 | Burke WebPortraits March 3, 2016 | 92 Burke Real Estate Consultants, Inc. | only row |
| 21 | Harcourts WebPortraits March 16, 2016 | 178 Harcourts (franchise) | franchise |
| 24 | Harcourts Encinitas 2016-04-11 | 178 Harcourts (franchise) | no Encinitas office row |
| 26 | Windermere 2016-04-12 | 61 Windermere Real Estate (franchise) | franchise |
| 30 | Remax 2016-06-16 | 13 RE/MAX (franchise) | franchise |
| 32 | Windermere 2016-06-16 | 61 Windermere Real Estate (franchise) | franchise |
| 33 | Windermere Escondido 2016-07-22 | 4 Windermere Homes & Estates-Escondido (brokerage) | office |
| 34 | Silva 2016-08-01 | 117 Silva Coast Realty (brokerage) | only row |
| 36 | Solutions 2016-10-10 | 334 Home Solutions Realty (brokerage) | Dan 2026-10-07 |
| 37 | Trevor Smith headshots 2016-11-22 | 1753 Lily Field Realty (brokerage) | Dan 2026-10-07 (his brokerage) |
| 38 | Century21 2016-12-07 | 141 Century 21 (franchise) | franchise |
| 39 | Sunshine Properties Headshots | 100 Sunshine Properties RealEstate (brokerage) | only row |
| 44 | Coldwell Banker Vista | 145 Coldwell Banker Realty - Vista (brokerage) | office |
| 45 | Sothebys Carlsbad 2017-03-21 | 170 Pacific Sotheby's International Realty - Carlsbad (brokerage) | office |
| 49 | New Palace Realty Headshots 2017-04-18 | 138 New Palace Realty (brokerage) | only row |
| 50 | Realty Executives Headshot Event | 196 Realty Executives (franchise) | franchise |
| 51 | New Palace Group headshots | 138 New Palace Realty | only row |
| 54 | Ray Shay headshot event 2017-06-02 | 62 Shay Realtors (brokerage) | survey M5f |
| 55 | Silva Headshots 2017-03-25 | 117 Silva Coast Realty | only row |
| 58 | Sea Coast 7/19/2017 | 157 Sea Coast Exclusive Properties (franchise) | only row |
| 60 | Tidal 2017-08-10 | 240 RE/MAX Tidal (brokerage) | only row |
| 61 | United Real Estate 2017-08-03 | 221 United Real Estate (franchise) | franchise |
| 63 | Plaza Real Estate Headshots | 127 Plaza Real Estate (brokerage) | exact |
| 64 | Coastal Premiere Headshots 2017-09-29 | 38 Coastal Premier Properties (franchise) | franchise |
| 66 | Plaza Real Estate 2017-11-06 | 127 Plaza Real Estate | exact |
| 76 | Pacific Sotheby's 2018-04-10 | 30 Pacific Sotheby's International Realty (franchise) | franchise |
| 81 | RE/MAX Home Center 2018-08-28 | 53 RE/MAX Home Center (brokerage) | office |
| 133 | Tidal Realty 2019-12-12 | 240 RE/MAX Tidal | only row |
| 135 | Tidal Realty 2019-12-19 | 240 RE/MAX Tidal | only row |
| 136 | New Palace Realty 1/9/2020 | 138 New Palace Realty | only row |
| 140 | Coldwell Banker Carmel Valley 3/10/20 | 272 Coldwell Banker Realty-Carmel Valley (brokerage) | office |
| 148 | 2022-04-05 Coldwell Banker Realty-Vista Headshots | 145 Coldwell Banker Realty - Vista | office |
| 310 | San Diego Castles Realty Master Mind Retreat 2024 | 629 San Diego Castles Realty (brokerage) | only row |
| 871 | Devine Fog Realty | 2814 Devine Fog Realty (brokerage) | only row |
| 1201 | Women of ROA | 2017 ROA California Inc. (brokerage) | survey M5f |

**New organizations** (no active row with the name, checked 2026-10-07; the migration sets `url` where one is given):

| Event | Name | Host to create | Type | `url` |
| --: | :-- | :-- | :-- | :-- |
| 4 | First American Title and Guild Mortgage | Guild Mortgage | lender | https://branches.guildmortgage.com/ca/sandiego/ |
| 6 | Guild Mortage Free WebPortrait | Guild Mortgage | lender | (same row) |
| 8 | Guild Mortgage Oct 21 | Guild Mortgage | lender | (same row) |
| 9 | Wells Fargo | Wells Fargo | lender | — |
| 13 | Corner Escrow Dec 16 | Corner Escrow | lender (escrow) | — |
| 18 | Coastal Pacific Web Portrait Event | Coastal Pacific | brokerage | https://coastalpacificre.com/ |
| 20 | Ken May WebPortraits March 3, 2016 | Ken May Team | agent team | https://www.compass.com/agents/ken-may/ |
| 23 | iServeLending 2016-04 | iServe Lending | lender | — |
| 27 | American Portfolio Mortgage | American Portfolio Mortgage | lender | — |
| 41 | Title365 headshots 2017-01-23 | Title365 | lender (title) | — |
| 47 | Title365 Headshots 2017-03-28 | Title365 | lender (title) | — |
| 57 | Fairway Mortgage 2017-07-13 | Fairway Mortgage | lender | — |
| 1236 | The Real Producer Metro Event | Foundation Escrow | lender (escrow) | https://foundationescrow.com/ |

Ten organizations are created here: Guild Mortgage, Wells Fargo, Corner Escrow, Coastal Pacific, Ken May Team, iServe Lending, American Portfolio Mortgage, Title365, Fairway Mortgage, Foundation Escrow.

The ten events that needed a decision were settled by Dan on 2026-10-07: 4 → Guild Mortgage; 18 → Coastal Pacific; 20 → Ken May Team; 36 → 334; 37 → 1753; 1236 → Foundation Escrow; 3, 7, 10 and 139 → no host. None of them affects the 6b write: only PSAR, NSDCR and SDAR carry a source (OQ4), so these hosts change which row a credited account is listed under in the memo and the ROI read-out, not whether its source is written.

### 3.3 No host (NULL) — 10 events

2 Test Marketing Event · 14 Marketing · 31 Aerial Marketing · 35 Glen Oaks Escrow Booth · 73 Misc. Headshots 2017-02-12 · 147 Maha Staging / Scripps Ranch Caravan (OQ11) · 3 Stagers Luncheon / Carlsbad · 7 Abriendo Puertas Free WebPortraits · 10 Double peak · 139 Tour 702 Carmel Valley 2020-02-04 (Dan, 2026-10-07).

### 3.4 Totals the post-backfill read-out must reproduce (event 2 invariant 4)

| Host | Events |
| :-- | --: |
| PSAR | 55 |
| NSDCR | 53 |
| SDAR | 22 |
| YPN | 1 |
| Brokerage, lender and agent team hosts | 55 (42 existing organizations, 13 events on 10 new ones) |
| No host | 10 |
| **Total** | **196** |

Organizations created: 14 — 4 associations (PSAR, NSDCR, SDAR, YPN) and the 10 in §3.2. Organizations with a source: 3.

**What event 22 → SDAR does to the 6b estimate (ESTIMATE, from the survey's M7b; the 6b dry run is the authority).** The survey credited 4 accounts through the SDREA token under the shoot-date rule, and event 22 is SDREA's only event. Those 4 now land on a host with a source instead of the "host without a source" list. The plan's figures move accordingly: first write 91 → **95**; `SDAR event` 7 → 15 becomes 7 → **19**; `attributed_accounts` 178 → 269 becomes 178 → **273**; credited accounts whose host has no source 107 → **103**. The plan (`docs/plans/account-classification-slice-6.md`, "Derived" under Measurements) still carries the old figures; 6b's Phase 0 re-baseline replaces them.

## 4. The draft token table (survey M3, 2026-10-02)

| Token | Events | Note |
| :-- | --: | :-- |
| PSAR | 55 | locations Chula Vista, El Cajon, San Diego ignored |
| NSDCAR | 41 | 2017–2020; the association's former name (OQ3) |
| NSDCR | 11 | 2021 on |
| SDAR | 21 | |
| SDREA | 1 | a typo for SDAR (event 22); mapped to SDAR |
| YPN | 1 | |
| (no acronym) | 66 | brokerages, lenders, title and escrow companies, a stager, and Insight's own rows |

## 5. The production run (2026-10-07, verbatim)

```text
Marketing event host audit — 196 events (196 active), 0 with a host
Generated at 2026-10-07 12:30:10.007557 UTC. Read-only; nothing is persisted. VERBOSE=true lists ids.
MAP_CUTOFF for this run: 2026-10-07T12:30:10.007557Z

1. Every event (id, scheduled date in UTC, active orders, order types, name)
       1  2015-07-15     21  free_web_portrait     Windermere Homes & Estates / Rancho Bernardo
       2  2015-07-01      0  —                     Test Marketing Event
       3  2015-07-21     15  free_web_portrait     Stagers Luncheon / Carlsbad
       4  2015-08-20      5  free_web_portrait     First American Title and Guild Mortgage
       5  2015-09-10      3  free_web_portrait     Windermere Homes & Estates Aviara Sept 10
       6  2015-09-26     10  free_web_portrait     Guild Mortage Free WebPortrait
       7  2015-10-07      5  free_web_portrait     Abriendo Puertas Free WebPortraits
       8  2015-10-21      1  free_web_portrait     Guild Mortgage Oct 21
       9  2015-10-30      6  free_web_portrait     Wells Fargo
      10  2015-11-06     12  free_web_portrait     Double peak
      11  2015-11-06     12  free_web_portrait     Century 21 Nov 6
      12  2015-12-02     22  free_web_portrait     Carrington Dec 2
      13  2015-12-16     11  free_web_portrait     Corner Escrow Dec 16
      14  —               0  —                     Marketing
      15  2016-01-19     12  free_web_portrait     Harcourts Prime Properties Headshot Event
      16  2016-02-03      7  free_web_portrait     Burke WebPortraits
      17  2016-02-18      5  free_web_portrait     ELITE Homes San Diego Web Portraits
      18  2016-02-19      8  free_web_portrait     Coastal Pacific Web Portrait Event
      19  2016-03-02      4  free_web_portrait     Burke WebPortraits March 3, 2016
      20  2016-03-03      1  free_web_portrait     Ken May WebPortraits March 3, 2016
      21  2016-03-16     15  free_web_portrait     Harcourts WebPortraits March 16, 2016
      22  2016-04-01     25  free_web_portrait     SDREA
      23  2016-04-06      6  free_web_portrait     iServeLending 2016-04
      24  2016-04-11      5  free_web_portrait     Harcourts Encinitas 2016-04-11
      25  2016-04-11     15  free_web_portrait     YPN 2016-04-11
      26  2016-04-12     11  free_web_portrait     Windermere 2016-04-12
      27  2016-05-09      2  free_web_portrait     American Portfolio Mortgage
      28  2016-05-20      9  free_web_portrait     SDAR 2016-05-20
      29  2016-06-16     79  free_web_portrait     Expo 2016-06-16
      30  2016-06-16     19  free_web_portrait     Remax 2016-06-16
      31  —               0  —                     Aerial Marketing
      32  2016-06-16      3  free_web_portrait     Windermere 2016-06-16
      33  2016-07-22     11  free_web_portrait     Windermere Escondido 2016-07-22
      34  2016-08-01      5  free_web_portrait     Silva 2016-08-01
      35  —               0  —                     Glen Oaks Escrow Booth
      36  2016-10-10     16  free_web_portrait     Solutions 2016-10-10
      37  2016-11-22      1  free_web_portrait     Trevor Smith headshots 2016-11-22
      38  2016-12-07     15  free_web_portrait     Century21 2016-12-07
      39  2017-01-20     13  free_web_portrait     Sunshine Properties Headshots
      40  2017-01-19      9  free_web_portrait     NSDCAR 2017-01-19
      41  2017-01-23     13  free_web_portrait     Title365 headshots 2017-01-23
      42  2017-02-03      9  free_web_portrait     NSDCAR 2017-02-03
      43  2017-02-27      7  free_web_portrait     NSDCAR Headshots 2017-02-27
      44  2017-03-21     22  free_web_portrait     Coldwell Banker Vista
      45  2017-03-21      6  free_web_portrait     Sothebys Carlsbad 2017-03-21
      46  2017-03-27      8  free_web_portrait     NSDCAR 2017-03-27
      47  2017-03-28     11  free_web_portrait     Title365 Headshots 2017-03-28
      48  2017-04-10      4  free_web_portrait     NSDCAR 2017-04-10 Headshots
      49  2017-04-18      9  free_web_portrait     New Palace Realty Headshots 2017-04-18
      50  2017-05-04     27  free_web_portrait     Realty Executives Headshot Event
      51  2017-05-11      0  —                     New Palace Group headshots
      52  2017-05-13      2  free_web_portrait     NSDCAR 2017-05-13 Headshots
      53  2017-05-22      5  free_web_portrait     NSDCAR 2017-05-22
      54  2017-06-02      3  free_web_portrait     Ray Shay headshot event 2017-06-02
      55  2017-03-25      5  free_web_portrait     Silva Headshots 2017-03-25
      56  2017-06-09     50  free_web_portrait     NSDCAR Expo 2017-06-09
      57  2017-07-13     25  free_web_portrait     Fairway Mortgage 2017-07-13
      58  2017-07-19     22  free_web_portrait     Sea Coast 7/19/2017
      59  2017-07-31      8  free_web_portrait     NSDCAR 2017-07-31
      60  2017-08-10     13  free_web_portrait     Tidal 2017-08-10
      61  2017-08-03      8  free_web_portrait     United Real Estate 2017-08-03
      62  2017-09-26     31  free_web_portrait     NSDCAR Vista 2017-09-26
      63  2017-10-12      1  free_web_portrait     Plaza Real Estate Headshots
      64  2017-09-29     16  free_web_portrait     Coastal Premiere Headshots 2017-09-29
      65  2017-10-23      5  free_web_portrait     NSDCAR 2017-10-23
      66  2017-11-06     12  free_web_portrait     Plaza Real Estate 2017-11-06
      67  2017-11-08     15  free_web_portrait     NSDCAR 2017-11-08
      68  2017-11-29      8  free_web_portrait     SDAR 2017-11-29
      69  2018-01-10      1  free_web_portrait     NSDCAR 2018-01-10
      70  2018-01-13     14  free_web_portrait     NSDCAR 2018-01-13
      71  2018-01-30     37  free_web_portrait     NSDCAR 2018-01-30
      72  2018-02-07      8  free_web_portrait     NSDCAR 2018-02-07
      73  2018-02-12      5  free_web_portrait     Misc. Headshots 2017-02-12
      74  2018-03-15     13  free_web_portrait     NSDCAR 2018-03-15
      75  2018-04-04     17  free_web_portrait     NSDCAR 2018-04-04
      76  2018-04-10     10  free_web_portrait     Pacific Sotheby's 2018-04-10
      77  2018-05-18     20  free_web_portrait     NSDCAR 2018-05-18
      78  2018-06-01      4  free_web_portrait     NSDCAR 2018-06-01
      79  2018-07-11     17  free_web_portrait     NSDCAR Vista 2018-07-11
      80  2018-08-06     11  free_web_portrait     NSDCAR 2018-08-06
      81  2018-08-28      8  free_web_portrait     RE/MAX Home Center 2018-08-28
      82  2018-09-13     10  free_web_portrait     NSDCAR 2018-09-13
      83  2018-10-03     13  free_web_portrait     NSDCAR 2018-10-03
     116  2018-12-05      6  free_web_portrait     NSDCAR Vista 2018-12-05
     117  2019-01-09      6  free_web_portrait     NSDCAR Vista 2019-01-09
     118  2019-02-25     20  free_web_portrait     NSDCAR Vista 2019-02-25
     119  2019-03-13      4  free_web_portrait     NSDCAR 2019-03-13
     120  2019-04-18     16  free_web_portrait     NSDCAR 2019-04-18
     121  2019-04-24      7  free_web_portrait     NSDCAR 2019-04-24
     122  2019-05-13      4  free_web_portrait     NSDCAR Vista 2019-05-13
     123  2019-06-13      5  free_web_portrait     NSDCAR Vista 2019-06-13
     124  2019-06-25     27  free_web_portrait     NSDCAR Escondido 2019-06-26
     125  2019-07-10      5  free_web_portrait     NSDCAR 2019-07-10
     126  2019-08-12     11  free_web_portrait     NSDCAR 2019-08-12
     127  2019-09-10     13  free_web_portrait     NSDCAR 2019-09-10
     128  2019-10-02      7  free_web_portrait     NSDCAR Vista 2019-10-02
     129  2019-11-06      9  free_web_portrait     SDAR Lunch and Learn Chula Vista
     130  2019-11-08     12  free_web_portrait     NSDCAR 2019-11-08
     131  2019-11-07      4  free_web_portrait     SDAR Lunch & Learn Carlsbad
     132  2019-11-13      5  free_web_portrait     SDAR Lunch & Learn / San Diego
     133  2019-12-12     24  free_web_portrait     Tidal Realty 2019-12-12
     134  2019-12-17      6  free_web_portrait     NSDCAR Vista 2019-12-17
     135  2019-12-19      9  free_web_portrait     Tidal Realty 2019-12-19
     136  2020-01-09     13  free_web_portrait     New Palace Realty 1/9/2020
     137  2020-01-13     17  free_web_portrait     NSDCAR Vista 1/13/2020
     138  2020-02-03      7  free_web_portrait     NSDCAR Vista 2/3/2020
     139  2020-02-04      8  free_web_portrait     Tour 702 Carmel Valley 2020-02-04
     140  2020-03-10      6  free_web_portrait     Coldwell Banker Carmel Valley 3/10/20
     141  2021-07-28      3  free_web_portrait     NSDCR Hub Grand Opening
     142  2021-10-22     13  free_web_portrait     PSAR 2021-10-22
     143  2021-11-12     17  free_web_portrait     PSAR 2021-11-12
     144  2021-12-10     16  free_web_portrait     PSAR San Diego Headshots 2012-12-10
     145  2022-01-13      1  free_web_portrait     NSDCR Branding Event 2022-01-13
     146  2022-01-27      1  free_web_portrait     NSDCR - Grand Opening Carlsbad
     147  2022-03-22     14  free_web_portrait     Maha Staging / Scripps Ranch Caravan
     148  2022-04-05     13  free_web_portrait     2022-04-05 Coldwell Banker Realty-Vista Headshots
     149  2022-04-08     11  free_web_portrait     2022-04-08 PSAR Chula Vista-Headshots
     150  2022-05-13     16  free_web_portrait     PSAR Chula Vista 2022-05-13
     151  2022-06-10     14  free_web_portrait     PSAR San Diego Headshots 2022-06-10
     152  2022-07-08     20  free_web_portrait     PSAR Chula Vista 2022-07-08
     153  2022-08-12     14  free_web_portrait     2022-08-12 PSAR Chula Vista Headshots
     154  2022-09-09     20  free_web_portrait     2022-09-09 PSAR San Diego Headshots
     155  2022-10-14     11  free_web_portrait     2022-10-14 PSAR Chula Vista Headshots
     156  2022-11-04     15  free_web_portrait     2022-11-4 PSAR El Cajon
     157  2023-02-10     16  free_web_portrait     PSAR Chula Vista 2023-02-10
     158  2023-03-10     18  free_web_portrait     PSAR San Diego 2023-03-10
     159  2023-04-11     10  free_web_portrait     2023-04-11 PSAR El Cajon Headshots
     160  2023-05-12     13  free_web_portrait     PSAR Chula Vista 2023-05-12
     161  2023-06-09     13  free_web_portrait     2023-06-09 PSAR San Diego Headshots
     162  2023-06-22     45  free_web_portrait     NSDCR Headshots Carlsbad 2023-06-22
     163  2023-06-23     30  free_web_portrait     2023-06-23 PSAR Portraits
     164  2023-07-11      5  free_web_portrait     2023-07-11 PSAR El Cajon
     165  2023-08-11      8  free_web_portrait     2023-08-11 PSAR Chula Vista Headshots
     166  2023-09-08     16  free_web_portrait     2023-09-08 PSAR Headshots
     167  2023-10-10     12  free_web_portrait     2023-10-10 PSAR Headshots El Cajon
     168  2023-10-26     10  free_web_portrait     NSDCR Board Headshots
     169  2023-11-03     25  free_web_portrait     2023-11-03 PSAR Headshots
     170  2023-11-07     29  free_web_portrait     NSDCR Headshots 2023-11-07
     171  2023-12-09      7  free_web_portrait     2023-12-09 PSAR Headshots
     172  2024-01-09     16  free_web_portrait     PSAR Headshots El Cajon 2024-01-09
     173  2024-02-09     26  free_web_portrait     PSAR Chula Vista Headshots 2-24-02-09
     174  2024-03-08     15  free_web_portrait     PSAR San Diego 2024-03-08
     175  2024-03-26     20  free_web_portrait     2024-03-26 NSDCR Headshots
     176  2024-04-09     10  free_web_portrait     PSAR El Cajon Headshots
     177  2024-05-10      7  free_web_portrait     PSAR Headshots 2024-05-10
     178  2024-06-14     16  free_web_portrait     2024-06-14 PSAR Headshots San Diego
     211  2024-07-09     10  free_web_portrait     2024-07-09 PSAR El Cajon
     244  2024-08-09     13  free_web_portrait     PSAR Headshots Chula Vista 2024-08-09  [container order 21678: InsightPhotos]
     277  2024-09-13     13  free_web_portrait     PSAR Headshots - 2024-09-13  [container order 21679: InsightPhotos]
     310  2024-09-16     14  free_web_portrait     San Diego Castles Realty Master Mind Retreat 2024  [container order 37525: InsightPhotos]
     343  2024-10-08     16  free_web_portrait     PSAR Headshots El Cajon 2024-10-8  [container order 21680: InsightPhotos]
     376  2024-11-08     21  free_web_portrait     2024-11-08 PSAR Headshots Chula Vista  [container order 21681: InsightPhotos]
     409  2024-12-04     34  free_web_portrait     2024-12-04 NSDCR Headshots  [container order 44021: InsightPhotos]
     442  2024-12-13     13  free_web_portrait     2024-12-13 PSAR headshots  [container order 21682: InsightPhotos]
     475  2025-01-10     19  free_web_portrait     2025-01-10 PSAR Chula Vista  [container order 48277: InsightPhotos]
     508  2025-02-14     17  free_web_portrait     2025-02-14 PSAR Headshots  [container order 48280: PSAR]
     541  2025-03-11     15  free_web_portrait     2025-03-12 PSAR Headshots El Cajon  [container order 48282: InsightPhotos]
     574  2025-04-11     20  free_web_portrait     PSAR Chula Vista Heashots 4/11/25  [container order 48284: InsightPhotos]
     607  2025-05-09     14  free_web_portrait     PSAR San Diego Headshots 2025-05-09  [container order 48285: InsightPhotos]
     640  2025-06-10     15  free_web_portrait     2025-06-10 PSAR Headshots El Cajon  [container order 48287: InsightPhotos]
     673  2025-06-19     43  free_web_portrait     2025-06-19 NSDCR Headshots  [container order 67417: NSDCR NSDCR]
     706  2025-07-07     12  free_web_portrait     SDAR Headshots 2025-07-07  [container order 72780: Tony Escalante]
     739  2025-07-11     20  free_web_portrait     2025-07-11 PSAR Chula Vista Headshots  [container order 72467: InsightPhotos]
     772  2025-07-21      7  free_web_portrait     SDAR Candidate Headshots  [container order 72873: Tony Escalante]
     805  2025-08-04      8  free_web_portrait     SDAR Lunch Break Headshots  [container order 73075: InsightPhotos]
     838  2025-08-08     21  free_web_portrait     2025-08-08 PSAR Headshots  [container order 73019: InsightPhotos]
     871  2025-08-26      6  free_web_portrait     Devine Fog Realty  [container order 73343: InsightPhotos]
     904  2025-09-08     19  free_web_portrait     2025-09-08 SDAR Orientation Headshots  [container order 73246: InsightPhotos]
     905  2025-09-09     16  free_web_portrait     2025-09-09 PSAR El Cajon  [container order 73020: InsightPhotos]
     937  2025-09-24     89  free_web_portrait     2025-09-24 SDAR Headshots  [container order 73887: InsightPhotos]
     970  2025-10-06     14  free_web_portrait     2025-10-06 SDAR  [container order 73837: InsightPhotos]
    1003  2025-10-10     15  free_web_portrait     2025-10-10 PSAR Chula Vista  [container order 73021: InsightPhotos]
    1036  2025-11-14     10  free_web_portrait     2025-11-14 PSAR Headshots  [container order 73024: InsightPhotos]
    1037  2025-11-25     24  free_web_portrait     2025-11-25 NSDCR Headshots  [container order 74140: NSDCR NSDCR]
    1038  2025-12-01     11  free_web_portrait     2025-12-05 SDAR Headshots  [container order 74356: InsightPhotos]
    1069  2026-01-06      7  free_web_portrait     SDAR Headshots 2026-01-06  [container order 74678: InsightPhotos]
    1070  2026-01-09     16  free_web_portrait     PSAR Headshots Jan 9th  [container order 74581: InsightPhotos]
    1102  2026-02-03     12  free_web_portrait     2026-02-05 SDAR Headshots  [container order 74974: InsightPhotos]
    1135  2026-02-13     28  free_web_portrait     2/13 PSAR Headshots  [container order 74656: InsightPhotos]
    1136  2026-03-12      9  free_web_portrait     2026-03-12 NSDCR  [container order 75309: NSDCR NSDCR]
    1137  2026-03-13     18  free_web_portrait     2026-03-13 PSAR  [container order 75310: InsightPhotos]
    1168  2026-04-07      9  free_web_portrait     4-7 SDAR Headshots  [container order 75486: InsightPhotos]
    1169  2026-04-10     11  free_web_portrait     4-10 PSAR Headshots  [container order 74725: InsightPhotos]
    1201  2026-05-01     28  free_web_portrait     Women of ROA  [container order 76167: InsightPhotos]
    1234  2026-05-05      5  free_web_portrait     PSAR Headshots  [container order 76094: InsightPhotos]
    1235  2026-05-05      7  free_web_portrait     SDAR Headshots  [container order 75947: InsightPhotos]
    1236  2026-05-21     11  free_web_portrait     The Real Producer Metro Event  [container order 76256: Cathy Ginder]
    1237  2026-06-02     11  free_web_portrait     6-2 SDAR Headshots  [container order 76158: InsightPhotos]
    1267  2026-06-09     18  free_web_portrait     2026-06-06 PSAR Headshots  [container order 76118: InsightPhotos]
    1300  2026-07-07      7  free_web_portrait     7-6 SDAR headshots  [container order 76762: InsightPhotos]
    1301  2026-07-10     28  free_web_portrait     7-10 PSAR Headshots  [container order 76763: InsightPhotos]
    1333  2026-08-04      8  free_web_portrait     2026-08-04 SDAR Headshots  [container order 76798: InsightPhotos]
    1366  2026-08-11     23  free_web_portrait     PSAR Headshots  [container order 75565: InsightPhotos]
    1399  2026-09-01      8  free_web_portrait     9-1 SDAR headshot  [container order 77223: InsightPhotos]
    1400  2026-09-08     13  free_web_portrait     PSAR Headshot El Cajon  [container order 76120: InsightPhotos]
    1401  2026-09-09     59  free_web_portrait     SDAR Appreciation Day  [container order 76571: InsightPhotos]

2. Draft acronym parse (a survey aid; the backfill is keyed by event id)
  PSAR            55
  NSDCAR          41
  NSDCR           11
  SDAR            21
  SDREA            1
  YPN              1
  (no acronym)    66
         1  Windermere Homes & Estates / Rancho Bernardo        → Windermere
         2  Test Marketing Event                                → Test
         3  Stagers Luncheon / Carlsbad                         → Stagers
         4  First American Title and Guild Mortgage             → First American
         5  Windermere Homes & Estates Aviara Sept 10           → Windermere
         6  Guild Mortage Free WebPortrait                      → Guild
         7  Abriendo Puertas Free WebPortraits                  → Abriendo
         8  Guild Mortgage Oct 21                               → Guild
         9  Wells Fargo                                         → Wells
        10  Double peak                                         → Double
        11  Century 21 Nov 6                                    → Century
        12  Carrington Dec 2                                    → Carrington
        13  Corner Escrow Dec 16                                → Corner
        14  Marketing                                           → Marketing
        15  Harcourts Prime Properties Headshot Event           → Harcourts
        16  Burke WebPortraits                                  → Burke
        17  ELITE Homes San Diego Web Portraits                 → ELITE
        18  Coastal Pacific Web Portrait Event                  → Coastal Pacific
        19  Burke WebPortraits March 3, 2016                    → Burke
        20  Ken May WebPortraits March 3, 2016                  → Ken
        21  Harcourts WebPortraits March 16, 2016               → Harcourts
        23  iServeLending 2016-04                               → iServeLending
        24  Harcourts Encinitas 2016-04-11                      → Harcourts
        26  Windermere 2016-04-12                               → Windermere
        27  American Portfolio Mortgage                         → American
        29  Expo 2016-06-16                                     → Expo
        30  Remax 2016-06-16                                    → Remax
        31  Aerial Marketing                                    → Aerial
        32  Windermere 2016-06-16                               → Windermere
        33  Windermere Escondido 2016-07-22                     → Windermere
        34  Silva 2016-08-01                                    → Silva
        35  Glen Oaks Escrow Booth                              → Glen
        36  Solutions 2016-10-10                                → Solutions
        37  Trevor Smith headshots 2016-11-22                   → Trevor
        38  Century21 2016-12-07                                → Century21
        39  Sunshine Properties Headshots                       → Sunshine
        41  Title365 headshots 2017-01-23                       → Title365
        44  Coldwell Banker Vista                               → Coldwell
        45  Sothebys Carlsbad 2017-03-21                        → Sothebys
        47  Title365 Headshots 2017-03-28                       → Title365
        49  New Palace Realty Headshots 2017-04-18              → New Palace
        50  Realty Executives Headshot Event                    → Realty Executives
        51  New Palace Group headshots                          → New Palace
        54  Ray Shay headshot event 2017-06-02                  → Ray
        55  Silva Headshots 2017-03-25                          → Silva
        57  Fairway Mortgage 2017-07-13                         → Fairway
        58  Sea Coast 7/19/2017                                 → Sea Coast
        60  Tidal 2017-08-10                                    → Tidal
        61  United Real Estate 2017-08-03                       → United Real
        63  Plaza Real Estate Headshots                         → Plaza
        64  Coastal Premiere Headshots 2017-09-29               → Coastal Premiere
        66  Plaza Real Estate 2017-11-06                        → Plaza
        73  Misc. Headshots 2017-02-12                          → Misc
        76  Pacific Sotheby's 2018-04-10                        → Pacific
        81  RE/MAX Home Center 2018-08-28                       → RE/MAX
       133  Tidal Realty 2019-12-12                             → Tidal
       135  Tidal Realty 2019-12-19                             → Tidal
       136  New Palace Realty 1/9/2020                          → New Palace
       139  Tour 702 Carmel Valley 2020-02-04                   → Tour
       140  Coldwell Banker Carmel Valley 3/10/20               → Coldwell
       147  Maha Staging / Scripps Ranch Caravan                → Maha
       148  2022-04-05 Coldwell Banker Realty-Vista Headshots   → Coldwell
       310  San Diego Castles Realty Master Mind Retreat 2024   → San Diego
       871  Devine Fog Realty                                   → Devine
      1201  Women of ROA                                        → ROA
      1236  The Real Producer Metro Event                       → Real Producer

3. Active organizations whose name contains each drafted token
  Windermere (5 events)
       281  Kohler House Real Estate Group/Windermere Homes & Estates  Agent team
       165  Windermere Homes & Estates-Aviara/South Carlsbad    Brokerage
       310  Windermere Homes & Estates-Carlsbad Village         Brokerage
       166  Windermere Homes & Estates-Del Mar                  Brokerage
         4  Windermere Homes & Estates-Escondido                Brokerage
       244  Windermere Homes & Estates-La Jolla                 Brokerage
       423  Windermere Homes & Estates - La Quinta              Brokerage
       167  Windermere Homes & Estates-Rancho Bernardo          Brokerage
       304  Windermere Homes & Estates-San Diego Downtown       Brokerage
       168  Windermere Homes & Estates-Scripps Ranch            Brokerage
      … and 2 more
  Test (1 event)
      no active organization
  Stagers (1 event)
      no active organization
  First American (1 event)
      no active organization
  Guild (2 events)
      no active organization
  Abriendo (1 event)
      no active organization
  Wells (1 event)
       502  Pacific Sotheby's International Realty - Indian Wells  Brokerage
  Double (1 event)
      no active organization
  Century (1 event)
       141  Century 21                                          Franchise
       479  CENTURY 21 Adams & Barnes                           Brokerage
       228  Century 21 Affiliated - Carlsbad                    Brokerage
        20  Century 21 Affiliated - Chula Vista                 Brokerage
       551  Century 21 Affiliated-Ramona                        Brokerage
       688  CENTURY 21 Affiliated - San Clemente                Brokerage
      3238  Century 21 Affiliated - San Diego                   Brokerage
       646  Century 21 Fine Homes & Estates                     Brokerage
       624  Century 21 Full Realty Services                     Brokerage
       664  CENTURY 21 Masters                                  Brokerage
      … and 3 more
  Carrington (1 event)
        14  Carrington Real Estate Services                     Franchise
       153  Carrington Real Estate Services (CA), Inc. - Carlsbad  Brokerage
       154  Carrington Real Estate Services (CA), Inc. - Del Mar  Brokerage
       155  Carrington Real Estate Services (CA), Inc. - Escondido  Brokerage
       156  Carrington Real Estate Services (CA), LLC - Downtown  Brokerage
  Corner (1 event)
       409  RE/MAX Cornerstone                                  Brokerage
       559  Seller's Corner Real Estate                         Brokerage
  Marketing (1 event)
      no active organization
  Harcourts (3 events)
       178  Harcourts                                           Franchise
       122  Harcourts Advantage                                 Brokerage
       270  Harcourts Jade Properties                           Brokerage
      3208  Harcourts One - San Diego                           Brokerage
       103  Harcourts Pacific Realty                            Brokerage
       215  Harcourts Prime Properties                          Brokerage
       214  Harcourts Prime Properties - Aliso Viejo            Brokerage
         8  Harcourts Prime Properties - Carlsbad               Brokerage
       332  Harcourts Prime Properties-Pacific Beach            Brokerage
        72  Harcourts Ranch & Coast                             Brokerage
      … and 1 more
  Burke (2 events)
        92  Burke Real Estate Consultants, Inc.                 Brokerage
  ELITE (1 event)
       355  Berkshire Hathaway HomeServices-The Elite HomeGroup  Brokerage
        47  ELITE Homes San Diego                               Brokerage
       318  RealtyOne Group San Diego-The Elite HomeGroup       Brokerage
       464  Re/Max Elite Properties                             Brokerage
  Coastal Pacific (1 event)
      no active organization
  Ken (1 event)
      no active organization
  iServeLending (1 event)
      no active organization
  American (1 event)
       661  American Dreams Real Estate                         Brokerage
      2813  Senior American Funding. Inc.                       Brokerage
  Expo (1 event)
      no active organization
  Remax (1 event)
      no active organization
  Aerial (1 event)
      no active organization
  Silva (2 events)
       117  Silva Coast Realty                                  Brokerage
  Glen (1 event)
      1225  Glenn D. Mitchel Realtors                           Brokerage
  Solutions (1 event)
       334  Home Solutions Realty                               Brokerage
        98  J & M Investment Solutions Inc                      Brokerage
  Trevor (1 event)
      no active organization
  Century21 (1 event)
      no active organization
  Sunshine (1 event)
       100  Sunshine Properties RealEstate                      Brokerage
  Title365 (2 events)
      no active organization
  Coldwell (3 events)
       466  Coldwell Banker Blackstone Realty                   Brokerage
       641  Coldwell Banker Home Source                         Brokerage
        42  Coldwell Banker Previews International              Brokerage
       142  Coldwell Banker Realty                              Franchise
       670  Coldwell Banker Realty                              Brokerage
       143  Coldwell Banker Realty - Carlsbad                   Brokerage
       272  Coldwell Banker Realty-Carmel Valley                Brokerage
       763  Coldwell Banker Realty-Dana Point/San Clemente      Brokerage
       144  Coldwell Banker Realty - Del Mar                    Brokerage
       146  Coldwell Banker Realty - Encinitas/La Costa         Brokerage
      … and 19 more
  Sothebys (1 event)
      no active organization
  New Palace (3 events)
       138  New Palace Realty                                   Brokerage
  Realty Executives (1 event)
       196  Realty Executives                                   Franchise
       328  Realty Executives - Carlsbad                        Brokerage
        77  Realty Executives- Premiere Properties              Brokerage
       628  Realty Executives - Temecula                        Brokerage
        73  Realty Executives / The AON Group                   Brokerage
       277  Realty Executives - Vista                           Brokerage
  Ray (1 event)
      no active organization
  Fairway (1 event)
      no active organization
  Sea Coast (1 event)
       157  Sea Coast Exclusive Properties                      Franchise
  Tidal (3 events)
       240  RE/MAX Tidal                                        Brokerage
  United Real (1 event)
       221  United Real Estate                                  Franchise
       222  United Real Estate - San Diego                      Brokerage
       360  United Realty Team, Inc                             Brokerage
  Plaza (2 events)
       127  Plaza Real Estate                                   Brokerage
      1885  Plaza Realty & Mortgage                             Brokerage
  Coastal Premiere (1 event)
      no active organization
  Misc (1 event)
      no active organization
  Pacific (1 event)
       349  Chase Pacific Property Management                   Brokerage
       422  Coldwell Banker Realty - Pacific Beach              Brokerage
      3273  Dunn Realtors Park Pacific Properties               Brokerage
       564  Golden Pacific Real Estate                          Brokerage
      3240  Grand Pacific Realty                                Brokerage
       103  Harcourts Pacific Realty                            Brokerage
       332  Harcourts Prime Properties-Pacific Beach            Brokerage
       276  Horizon Pacific Realty                              Brokerage
       225  Keller Williams Pacific Estates                     Brokerage
       555  Monarch Pacific Realty Inc.                         Brokerage
      … and 27 more
  RE/MAX (1 event)
        13  RE/MAX                                              Franchise
        55  RE/MAX Associates                                   Brokerage
       312  RE/MAX Associates-La Jolla                          Brokerage
       152  RE/MAX Associates/Rancho Bernardo                   Brokerage
       107  RE/MAX At The Coast                                 Brokerage
        48  RE/MAX By The Sea                                   Brokerage
       418  RE/MAX City Real Estate                             Brokerage
       282  RE/MAX Clarity                                      Brokerage
       313  RE/MAX Connections                                  Brokerage
       409  RE/MAX Cornerstone                                  Brokerage
      … and 15 more
  Tour (1 event)
      no active organization
  Maha (1 event)
      no active organization
  San Diego (1 event)
       198  Berkshire Hathaway HomeServices - San Diego         Brokerage
       199  Berkshire Hathaway HomeServices - San Diego (5th Ave)  Brokerage
      3238  Century 21 Affiliated - San Diego                   Brokerage
       204  Coastal Premier Properties - San Diego              Brokerage
        21  Coldwell Banker Realty-San Diego                    Brokerage
       548  Coldwell Banker West-San Diego                      Brokerage
       682  eHomes San Diego                                    Brokerage
        47  ELITE Homes San Diego                               Brokerage
      3208  Harcourts One - San Diego                           Brokerage
       183  Keller Williams Realty-San Diego Metro              Brokerage
      … and 13 more
  Devine (1 event)
      2814  Devine Fog Realty                                   Brokerage
  ROA (1 event)
       192  Broadpoint Properties                               Franchise
         6  Broadpoint Properties - Encinitas                   Brokerage
       193  Broadpoint Properties - Escondido                   Brokerage
       169  Broadwater Realty                                   Brokerage
      2017  ROA California Inc.                                 Brokerage
       635  The Broadmoor RE Group Inc.                         Brokerage
  Real Producer (1 event)
      no active organization

4. Insight's own or not a hosted headshot event, by name only: 8
       2  Test Marketing Event
      14  Marketing
      29  Expo 2016-06-16
      31  Aerial Marketing
      35  Glen Oaks Escrow Booth
      56  NSDCAR Expo 2017-06-09
      73  Misc. Headshots 2017-02-12
     147  Maha Staging / Scripps Ranch Caravan

5. Events to look at by hand
  No active orders: 5
         2  Test Marketing Event                                (4 soft-deleted)
        14  Marketing                                           (no orders)
        31  Aerial Marketing                                    (no orders)
        35  Glen Oaks Escrow Booth                              (no orders)
        51  New Palace Group headshots                          (no orders)
  No scheduled_at: 3
        14  Marketing
        31  Aerial Marketing
        35  Glen Oaks Escrow Booth
  Container-order accounts: 5
         2  InsightPhotos                             42 events
      2275  NSDCR NSDCR                               3 events
     11058  Tony Escalante                            2 events
      2836  PSAR                                      1 event
     11649  Cathy Ginder                              1 event

6. Hosts (after the backfill)
  No event has a host yet — the backfill has not run.
```
