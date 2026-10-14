# Account classification — event attribution (APPLIED at 2026-10-14T12:30:56.771630Z)

Generated 2026-10-14 12:30 UTC against `d4c7q2h3ed4nvs` (latest order 2026-10-14 04:41 UTC), insgt-api `unknown`. Reproduce: `bin/rails account_classification:attribute_event_hosts [APPLY=true] [OUT=<memo.md>] [CSV=<rows.csv>]`. Contract: docs/architecture/account-classification.md §5.5.

## Rules

- The universe: active accounts, not typed internal, with no `marketing_source_id`, that have an active event order.
- The crediting order: the latest event order dated strictly before the account's first paid listing shoot (`Order.qualifying_parents` with `paid_at`). Both are dated by `Order.shoot_date_sql`; an event order's is its delivery date, because the headshot flow sets no `scheduled_at`. Ties among event orders go to the later-created order. An undelivered event order (NULL date) is dropped.
- Written when that order's event has a host and the host has a marketing source. Last touch has no fallback: an earlier hosted event does not stand in for an unhosted or unsourced latest one.
- Written once, never over a value: `updated_by_id = 1` (User.system) and one batch `updated_at`, in one transaction with two self-checks; `marketing_source_other` is cleared; a source keyed `other` is never written.

## Funnel

| Population | Accounts |
| :-- | --: |
| active, not internal, with an active event order | 2,343 |
| already carrying a source (never written) | 28 |
| no source: the universe | 2,315 |
| no paid listing | 1,967 |
| attended only after the first paid listing | 149 |
| only undelivered event orders before buying | 0 |
| credited (an event order before the first paid listing) | 199 |
| credited, to write | 94 |
| credited, host is not a marketing source | 96 |
| credited, latest event has no host | 9 |

Internal accounts with an event order (not in the universe): 1. Undelivered event orders (NULL shoot date, dropped before ranking): 13.

## Writes, by host → source (94)

| Host | Source | Accounts | Lifetime value |
| :-- | :-- | --: | --: |
| NSDCR | nsdcr_event | 70 | $79,629.00 |
| PSAR | psar_event | 13 | $6,380.00 |
| SDAR | sdar_event | 11 | $8,250.00 |

Accounts to write that carry `marketing_source_other` text, which the write clears: 0.

### nsdcr_event (70)

| Account | Host | Event | Delivered | First paid listing | Lifetime value |
| :-- | :-- | --: | :-- | :-- | --: |
| 77 Kim Glynn | NSDCR | 138 | 2020-02-04 | 2020-07-25 | $185.00 |
| 214 Maria Lopez | NSDCR | 118 | 2019-02-27 | 2022-11-21 | $340.00 |
| 513 Jackie Camacho | NSDCR | 71 | 2018-02-07 | 2025-08-22 | $495.00 |
| 610 Thessy Onyenedum | NSDCR | 29 | 2016-07-05 | 2016-08-13 | $165.00 |
| 612 Rada Labe | NSDCR | 29 | 2016-07-05 | 2017-02-14 | $254.00 |
| 618 Joe Green | NSDCR | 29 | 2016-07-05 | 2016-07-08 | $20,906.00 |
| 619 Jerry Glaser | NSDCR | 59 | 2017-08-10 | 2019-09-09 | $1,355.00 |
| 625 Susan Lowe | NSDCR | 29 | 2016-07-05 | 2016-08-04 | $640.00 |
| 654 Mary Wagner | NSDCR | 29 | 2016-07-05 | 2023-06-29 | $165.00 |
| 666 Bette Curtis | NSDCR | 29 | 2016-07-05 | 2025-05-02 | $165.00 |
| 671 Sharon Heyden | NSDCR | 29 | 2016-07-05 | 2023-06-19 | $810.00 |
| 676 Cheryl Collins | NSDCR | 29 | 2016-07-05 | 2023-09-13 | $1,165.00 |
| 805 Letty Perez | NSDCR | 70 | 2018-01-15 | 2018-07-10 | $155.00 |
| 960 Lazaro Castillo | NSDCR | 42 | 2017-02-09 | 2022-03-10 | $1,255.00 |
| 1059 Elena Thompson | NSDCR | 48 | 2017-04-19 | 2017-05-19 | $3,554.00 |
| 1137 Michael Carunchio | NSDCR | 53 | 2017-06-08 | 2017-06-23 | $290.00 |
| 1138 Nena Jo Haskins | NSDCR | 53 | 2017-06-08 | 2020-09-06 | $155.00 |
| 1152 Seth Surnamer | NSDCR | 29 | 2016-07-05 | 2017-06-22 | $495.00 |
| 1195 Devon Camilleri | NSDCR | 56 | 2017-07-05 | 2017-10-19 | $280.00 |
| 1204 Nila Esposito | NSDCR | 56 | 2017-07-05 | 2018-07-02 | $155.00 |
| 1263 Bob Pahlke | NSDCR | 59 | 2017-08-10 | 2017-08-15 | $685.00 |
| 1320 Oralia Castellanos | NSDCR | 62 | 2017-10-10 | 2019-06-22 | $155.00 |
| 1321 Eric Reaves | NSDCR | 62 | 2017-10-10 | 2018-06-09 | $740.00 |
| 1322 Riga Moore | NSDCR | 124 | 2019-06-26 | 2024-06-10 | $195.00 |
| 1377 Scott Olson | NSDCR | 65 | 2017-11-01 | 2021-12-20 | $2,285.00 |
| 1402 Rebecca Monge | NSDCR | 409 | 2024-12-07 | 2025-07-26 | $0.00 |
| 1452 Sander Harth | NSDCR | 70 | 2018-01-15 | 2018-05-23 | $3,370.00 |
| 1478 Bernard Maki | NSDCR | 71 | 2018-02-07 | 2020-11-04 | $320.00 |
| 1539 Eduardo Ruvalcaba | NSDCR | 74 | 2018-03-22 | 2018-04-06 | $145.00 |
| 1541 Charlotte Reed | NSDCR | 175 | 2024-03-27 | 2024-06-12 | $865.00 |
| 1598 Nancy Chodur | NSDCR | 75 | 2018-04-12 | 2018-09-10 | $310.00 |
| 1655 Lucy Wilborn | NSDCR | 77 | 2018-05-29 | 2019-02-27 | $145.00 |
| 1656 Susan Sanavi | NSDCR | 77 | 2018-05-29 | 2021-09-15 | $155.00 |
| 1757 Linda Shreve | NSDCR | 80 | 2018-08-15 | 2018-11-27 | $155.00 |
| 1760 Rolando Salazar | NSDCR | 79 | 2018-07-23 | 2023-02-19 | $495.00 |
| 1828 Jill Drawbridge | NSDCR | 82 | 2018-09-20 | 2019-09-26 | $505.00 |
| 1854 Zohra Emery | NSDCR | 124 | 2019-06-26 | 2021-08-13 | $4,555.00 |
| 1936 Brett Johnson | NSDCR | 117 | 2019-01-14 | 2019-05-18 | $5,790.00 |
| 2004 Gina Arias | NSDCR | 118 | 2019-02-27 | 2019-06-14 | $715.00 |
| 2009 Tom Metier | NSDCR | 128 | 2019-10-03 | 2019-10-18 | $300.00 |
| 2052 Sharon & Bob Parry | NSDCR | 29 | 2016-07-05 | 2017-05-11 | $3,425.00 |
| 2073 Tim Ryan | NSDCR | 121 | 2019-04-25 | 2019-08-09 | $645.00 |
| 2075 Tim Petlock | NSDCR | 121 | 2019-04-25 | 2019-05-02 | $230.00 |
| 2165 Jane Fabrizio | NSDCR | 124 | 2019-06-26 | 2022-08-23 | $165.00 |
| 2169 Mike Rush | NSDCR | 124 | 2019-06-26 | 2026-02-05 | $195.00 |
| 2179 Melody Dorman | NSDCR | 125 | 2019-07-11 | 2025-10-24 | $645.00 |
| 2196 Wendy Jones | NSDCR | 126 | 2019-08-14 | 2019-08-29 | $175.00 |
| 2271 Sheryl & Bob Chase | NSDCR | 128 | 2019-10-03 | 2023-09-19 | $195.00 |
| 2332 Tyler Phillips | NSDCR | 130 | 2019-11-09 | 2021-03-01 | $280.00 |
| 2336 Rebecca Rigaud | NSDCR | 141 | 2021-07-29 | 2021-07-30 | $265.00 |
| 2406 Bonnie Summers | NSDCR | 170 | 2023-11-09 | 2026-05-08 | $215.00 |
| 2411 Helen Dalziel | NSDCR | 137 | 2020-01-16 | 2020-03-16 | $1,635.00 |
| 2418 Sue Davis | NSDCR | 62 | 2017-10-10 | 2020-02-04 | $700.00 |
| 2425 Tiffany Boyd | NSDCR | 138 | 2020-02-04 | 2025-09-17 | $300.00 |
| 3028 Trudy Kranz Whitney | NSDCR | 137 | 2020-01-16 | 2022-06-13 | $6,830.00 |
| 3318 Michele Barnes | NSDCR | 162 | 2023-06-23 | 2025-04-07 | $465.00 |
| 3323 Gregg Alexander | NSDCR | 162 | 2023-06-23 | 2025-08-14 | $195.00 |
| 3330 Rosielinda Briceno | NSDCR | 162 | 2023-06-23 | 2024-12-09 | $165.00 |
| 3331 Lenore Wilkas | NSDCR | 168 | 2023-10-27 | 2024-08-29 | $1,750.00 |
| 3335 Stacy Gardner | NSDCR | 409 | 2024-12-07 | 2025-06-07 | $0.00 |
| 3336 Jeanne O'Leary | NSDCR | 162 | 2023-06-23 | 2023-07-28 | $3,435.00 |
| 3339 Linda Callahan | NSDCR | 170 | 2023-11-09 | 2024-06-25 | $460.00 |
| 3448 Annie Chavarria | NSDCR | 168 | 2023-10-27 | 2024-09-06 | $165.00 |
| 3628 Angela J Lee | NSDCR | 175 | 2024-03-27 | 2026-06-16 | $265.00 |
| 3638 Audrey Azzeh | NSDCR | 175 | 2024-03-27 | 2025-08-16 | $475.00 |
| 3640 Mollie Licosati | NSDCR | 175 | 2024-03-27 | 2026-03-28 | $250.00 |
| 3642 Lisa Mastracci | NSDCR | 175 | 2024-03-27 | 2024-08-14 | $0.00 |
| 11179 Alma Plancarte | NSDCR | 124 | 2019-06-26 | 2025-08-19 | $550.00 |
| 11604 Ken & Jean Tritle | NSDCR | 1037 | 2025-12-02 | 2026-03-05 | $490.00 |
| 11824 Phil Valverde | NSDCR | 1136 | 2026-03-18 | 2026-04-01 | $195.00 |

### psar_event (13)

| Account | Host | Event | Delivered | First paid listing | Lifetime value |
| :-- | :-- | --: | :-- | :-- | --: |
| 3039 Suzi Smith | PSAR | 152 | 2022-07-09 | 2022-07-15 | $390.00 |
| 3043 Mark Chavez | PSAR | 152 | 2022-07-09 | 2022-07-19 | $340.00 |
| 3056 Rick Torres | PSAR | 163 | 2023-06-26 | 2024-08-15 | $145.00 |
| 3223 Gina Pellegrino | PSAR | 158 | 2023-03-12 | 2023-05-22 | $310.00 |
| 3421 Shuzo Wakita | PSAR | 166 | 2023-09-11 | 2023-11-29 | $2,750.00 |
| 3647 Catherine Iacometti | PSAR | 176 | 2024-04-11 | 2024-06-11 | $695.00 |
| 3648 Olga Solovyeva | PSAR | 176 | 2024-04-11 | 2024-10-02 | $505.00 |
| 3822 Sam Prom-Chiem | PSAR | 178 | 2024-06-17 | 2024-09-06 | $195.00 |
| 3828 Rolando Rosal | PSAR | 178 | 2024-06-17 | 2024-09-25 | $145.00 |
| 3832 Michael Rai | PSAR | 178 | 2024-06-17 | 2024-11-18 | $145.00 |
| 6564 Richard Arroyo | PSAR | 376 | 2024-11-10 | 2025-03-25 | $175.00 |
| 7456 Vincent Huerta | PSAR | 508 | 2025-02-18 | 2025-04-28 | $195.00 |
| 11473 Cara Brave | PSAR | 1003 | 2025-10-15 | 2025-10-21 | $390.00 |

### sdar_event (11)

| Account | Host | Event | Delivered | First paid listing | Lifetime value |
| :-- | :-- | --: | :-- | :-- | --: |
| 374 Linda Drylie | SDAR | 22 | 2016-04-06 | 2016-10-19 | $135.00 |
| 469 Todd Busch | SDAR | 22 | 2016-04-06 | 2017-06-24 | $155.00 |
| 470 Chuck Rogers | SDAR | 22 | 2016-04-06 | 2016-07-24 | $1,145.00 |
| 483 Portia Metras | SDAR | 22 | 2016-04-06 | 2018-11-02 | $2,505.00 |
| 572 Serena Alexander | SDAR | 28 | 2016-05-24 | 2018-07-11 | $270.00 |
| 1423 Kathy Fitzgerald | SDAR | 68 | 2017-12-07 | 2026-03-02 | $1,735.00 |
| 6071 Yvanka Mussert | SDAR | 805 | 2025-08-06 | 2026-04-03 | $275.00 |
| 11186 Shelby Laabs | SDAR | 1102 | 2026-02-07 | 2026-03-20 | $1,090.00 |
| 11244 Stephanie Guyton | SDAR | 904 | 2025-09-11 | 2025-09-24 | $195.00 |
| 11324 Tina Hack | SDAR | 937 | 2025-09-29 | 2025-10-24 | $175.00 |
| 11364 Shari Sayers | SDAR | 937 | 2025-09-29 | 2026-07-06 | $570.00 |

## Marketing-source KPI, predicted (MarketingSourceMetricsService)

- attributed_accounts: 189 → 283 of 4,153 (4.6% → 6.8%); total_accounts unchanged.

| Source | Accounts before | After |
| :-- | --: | --: |
| NSDCR event | 6 | 76 |
| PSAR event | 20 | 33 |
| SDAR event | 9 | 20 |

## Credited, host is not a marketing source — not written (96)

| Host | Accounts | Lifetime value |
| :-- | --: | --: |
| RE/MAX Tidal | 11 | $18,410.00 |
| Windermere Homes & Estates-Rancho Bernardo | 9 | $58,473.00 |
| New Palace Realty | 8 | $8,465.00 |
| Harcourts Prime Properties | 6 | $25,544.00 |
| Pacific Sotheby's International Realty | 6 | $53,357.00 |
| Sea Coast Exclusive Properties | 6 | $3,820.00 |
| Coldwell Banker Realty - Vista | 5 | $5,058.00 |
| Title365 | 5 | $910.00 |
| Carrington Real Estate Services | 4 | $2,210.00 |
| Century 21 | 4 | $1,320.00 |
| RE/MAX | 4 | $17,005.00 |
| Corner Escrow | 3 | $7,713.00 |
| Harcourts | 3 | $2,450.00 |
| Home Solutions Realty | 3 | $1,009.00 |
| Guild Mortgage | 2 | $2,970.00 |
| Plaza Real Estate | 2 | $3,145.00 |
| San Diego Castles Realty | 2 | $2,505.00 |
| United Real Estate | 2 | $2,844.00 |
| Windermere Real Estate | 2 | $24,290.00 |
| Burke Real Estate Consultants, Inc. | 1 | $1,764.00 |
| Fairway Mortgage | 1 | $495.00 |
| Pacific Sotheby's International Realty - Carlsbad | 1 | $584.00 |
| RE/MAX Home Center | 1 | $1,000.00 |
| Realty Executives | 1 | $1,720.00 |
| Silva Coast Realty | 1 | $5,085.00 |
| Sunshine Properties RealEstate | 1 | $305.00 |
| Windermere Homes & Estates-Escondido | 1 | $165.00 |
| YPN | 1 | $475.00 |

## Credited, latest event has no host — not written (9)

| Account | Host | Event | Delivered | First paid listing | Lifetime value |
| :-- | :-- | --: | :-- | :-- | --: |
| 238 Metamery Simon | — | 10 | 2015-11-09 | 2019-03-30 | $965.00 |
| 248 Sherry Adams | — | 10 | 2015-11-09 | 2016-03-31 | $155.00 |
| 252 Laura Kohani | — | 10 | 2015-11-09 | 2016-09-08 | $430.00 |
| 254 Danny Power | — | 10 | 2015-11-09 | 2021-10-09 | $1,910.00 |
| 255 John Humphrey | — | 10 | 2015-11-09 | 2023-04-21 | $330.00 |
| 256 Rebecca Negard | — | 10 | 2015-11-09 | 2016-01-15 | $825.00 |
| 2432 Megan Gonzalez | — | 139 | 2020-02-06 | 2025-11-16 | $440.00 |
| 2918 Manny Behar | — | 147 | 2022-03-23 | 2025-07-17 | $155.00 |
| 2969 Tracee L Denby | — | 147 | 2022-03-23 | 2022-04-29 | $330.00 |

Of the credited accounts not written, 3 would be written under "the latest event whose host has a source". Last touch has no fallback, so they stay NULL.

## Credited only under the event date — not written (3)

Attended before the first paid listing by the event date, but the headshot was delivered after it, so the contract's delivery date reads them as buying first. Until the headshot flow stamps the event date on its orders, every fast convert lands here.

| Account | Host | Source | Event | Delivered | First paid listing |
| :-- | :-- | :-- | :-- | :-- | :-- |
| 996 Hector Rodriguez | Coldwell Banker Realty - Vista | none | 2017-03-21 | 2017-03-28 | 2017-03-22 |
| 1467 Giovanni Ruiz | NSDCR | nsdcr_event | 2018-01-30 | 2018-02-07 | 2018-02-02 |
| 1516 Russell Coats | NSDCR | nsdcr_event | 2018-03-15 | 2018-03-22 | 2018-03-20 |

## Already sourced — never written (28)

| Account | Own source | Derived host | Derived source | Rule's outcome |
| :-- | :-- | :-- | :-- | :-- |
| 823 Adam Nobert | nsdcr_event | Home Solutions Realty | — | skip_host_no_source |
| 3076 Victor Herrera | psar_event | — | — | skip_no_paid_listing |
| 8906 Brody Woehl | psar_event | — | — | skip_no_paid_listing |
| 11093 Jacquelynn Garcia | sdar_event | — | — | skip_no_paid_listing |
| 11230 Steve Brant | psar_event | — | — | skip_after_buying |
| 11349 Kay Merg | other | SDAR | sdar_event | write |
| 11650 Susan Phillips | sdar_event | — | — | skip_no_paid_listing |
| 11651 Lissana Route | sdar_event | — | — | skip_no_paid_listing |
| 11652 Mash  Moghei | sdar_event | — | — | skip_no_paid_listing |
| 11653 Victoria Wolven | sdar_event | — | — | skip_no_paid_listing |
| 11654 Margarita  Hernandez | sdar_event | — | — | skip_no_paid_listing |
| 11655 Paul Brice | sdar_event | — | — | skip_no_paid_listing |
| 11656 Tusa Enriquez | sdar_event | — | — | skip_no_paid_listing |
| 11657 Pat Crisafulli | psar_event | — | — | skip_no_paid_listing |
| 11658 Jaime Mora | psar_event | — | — | skip_no_paid_listing |
| 11659 Emily Santana | psar_event | — | — | skip_no_paid_listing |
| 11660 Annabel Bianes | psar_event | — | — | skip_no_paid_listing |
| 11661 Denise Brown | psar_event | — | — | skip_no_paid_listing |
| 11662 Brian Finney | psar_event | — | — | skip_no_paid_listing |
| 11664 Chelsea  McCray | psar_event | — | — | skip_no_paid_listing |
| 11665 Emerald  Trejo | psar_event | — | — | skip_no_paid_listing |
| 11666 Olga Castro | psar_event | — | — | skip_no_paid_listing |
| 11667 David  Murphy | psar_event | PSAR | psar_event | write |
| 11668 Agustin Richardson | psar_event | — | — | skip_no_paid_listing |
| 11669 Veronica Al-Sonna | psar_event | — | — | skip_no_paid_listing |
| 11670 Alma Coogan | psar_event | — | — | skip_no_paid_listing |
| 11821 Kevin Williamson | nsdcr_event | NSDCR | nsdcr_event | write |
| 11944 Tina Balch - San Diego Realtor | other | — | — | skip_after_buying |

## Events with no host (10)

| Event | Name | Date | Active orders | Created after the host map |
| --: | :-- | :-- | --: | :-- |
| 2 | Test Marketing Event | 2015-07-01 | 0 | no |
| 3 | Stagers Luncheon / Carlsbad | 2015-07-21 | 15 | no |
| 7 | Abriendo Puertas Free WebPortraits | 2015-10-07 | 5 | no |
| 10 | Double peak | 2015-11-06 | 12 | no |
| 14 | Marketing | — | 0 | no |
| 31 | Aerial Marketing | — | 0 | no |
| 35 | Glen Oaks Escrow Booth | — | 0 | no |
| 73 | Misc. Headshots 2017-02-12 | 2018-02-12 | 5 | no |
| 139 | Tour 702 Carmel Valley 2020-02-04 | 2020-02-04 | 8 | no |
| 147 | Maha Staging / Scripps Ranch Caravan | 2022-03-22 | 14 | no |

## After

- Applied at 2026-10-14T12:30:56.771630Z by user 1 (User.system). Every written row carries `updated_by_id = 1 AND updated_at = '2026-10-14T12:30:56.771630Z'`.
- Written: nsdcr_event 70 · psar_event 13 · sdar_event 11
- Self-check 1 (planned = written): OK — nsdcr_event 70 = 70 · psar_event 13 = 13 · sdar_event 11 = 11
- Self-check 2 (pre-sourced rows unchanged): OK — 192 rows re-read identical
- Active accounts with no source: 3,974 → 3,880
- Reversal, if ever wanted, keyed on the pair: `Account.where(updated_by_id: 1, updated_at: Time.zone.parse('2026-10-14T12:30:56.771630Z')).update_all(marketing_source_id: nil, updated_at: Time.current)`
