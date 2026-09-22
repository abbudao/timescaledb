# DATE probe: variant `int-after` @ ac62b98

run_id `int-after-ac62b98-20260922T115004Z`, scale `small`, TimescaleDB 2.31.0-dev on PostgreSQL 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1), started 2026-09-22 11:50 UTC

| days | devices | rows/device/day | rows | chunk interval | default indexes | compress_orderby | column order | date range |
|---|---|---|---|---|---|---|---|---|
| 400 | 200 | 24 | 1920000 | 7 days | t | (default) | default | 2025-08-19 .. 2026-09-22 |

## Queries, median of three runs

| query | table | exec ms | plan ms | chunks in plan | excluded at startup | vectorized filter | top rows | rows scanned | workers | shared hit | shared read |
|---|---|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|
| Q1 | metrics_date | 6.16 | 1.10 | 5 | 0 | t | 1 | 144000 | 0 | 6025 | 0 |
| Q1 | metrics_tstz | 6.16 | 0.50 | 5 | 0 | t | 1 | 144000 | 0 | 6025 | 0 |
| Q1-np | metrics_date | 6.33 | 0.63 | 5 | 0 | t | 1 | 144000 | 0 | 6025 | 0 |
| Q1-np | metrics_tstz | 5.77 | 0.52 | 5 | 0 | t | 1 | 144000 | 0 | 6025 | 0 |
| Q2 | metrics_date | 5.66 | 0.41 | 5 | 0 | t | 1 | 148800 | 0 | 6025 | 0 |
| Q2 | metrics_tstz | 17.35 | 4.54 | 5 | 53 | t | 1 | 148800 | 2 | 6025 | 0 |
| Q2-np | metrics_date | 5.72 | 0.39 | 5 | 0 | t | 1 | 148800 | 0 | 6025 | 0 |
| Q2-np | metrics_tstz | 6.50 | 4.06 | 5 | 53 | t | 1 | 148800 | 0 | 6025 | 0 |
| Q3 | metrics_date | 5.02 | 0.37 | 5 | 0 | t | 1 | 148800 | 0 | 4225 | 0 |
| Q3 | metrics_tstz | 4.82 | 0.37 | 5 | 0 | t | 1 | 148800 | 0 | 4225 | 0 |
| Q3-np | metrics_date | 5.20 | 0.56 | 5 | 0 | t | 1 | 148800 | 0 | 4225 | 0 |
| Q3-np | metrics_tstz | 5.09 | 0.42 | 5 | 0 | t | 1 | 148800 | 0 | 4225 | 0 |
| Q4 | metrics_date | 22.89 | 0.57 | 5 | 0 | t | 1000 | 148800 | 0 | 9025 | 0 |
| Q4 | metrics_tstz | 16.65 | 0.62 | 5 | 0 | t | 1000 | 148800 | 0 | 9025 | 0 |
| Q4-np | metrics_date | 22.35 | 0.54 | 5 | 0 | t | 1000 | 148800 | 0 | 9025 | 0 |
| Q4-np | metrics_tstz | 16.60 | 0.55 | 5 | 0 | t | 1000 | 148800 | 0 | 9025 | 0 |
| Q5 | metrics_date | 0.06 | 0.15 | 1 | 0 | t | 24 | 24 | 0 | 23 | 0 |
| Q5 | metrics_tstz | 0.04 | 0.16 | 1 | 0 | t | 24 | 24 | 0 | 23 | 0 |
| Q5-np | metrics_date | 0.04 | 0.22 | 1 | 0 | t | 24 | 24 | 0 | 23 | 0 |
| Q5-np | metrics_tstz | 0.04 | 0.15 | 1 | 0 | t | 24 | 24 | 0 | 23 | 0 |

## Chunk index usage over the query set

`idx_scan` summed over the indexes of the chunks, sampled before and
after Q1..Q5. A zero delta on scope `chunk` means no query touched the
default time index.

| table | scope | indexes | index bytes | idx_scan before | after Q1-Q5 | delta | after Q1-np..Q5-np | delta |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| metrics_date | chunk | 58 | 475136 | 119 | 119 | 0 | 119 | 0 |
| metrics_date | compressed | 58 | 950272 | 0 | 3 | 3 | 6 | 3 |
| metrics_tstz | chunk | 58 | 475136 | 119 | 119 | 0 | 119 | 0 |
| metrics_tstz | compressed | 58 | 950272 | 0 | 3 | 3 | 6 | 3 |

## Load, compression and continuous aggregate

| table | phase | seconds | rows | rows/sec |
|---|---|---:|---:|---:|
| metrics_date | cagg_refresh | 0.94 | 80000 | 85488 |
| metrics_tstz | cagg_refresh | 0.88 | 80000 | 90607 |
| metrics_date | compress | 2.30 | 1920000 | 833106 |
| metrics_tstz | compress | 2.58 | 1920000 | 745486 |
| metrics_date | load | 4.00 | 1920000 | 479885 |
| metrics_tstz | load | 4.97 | 1920000 | 386095 |

## Storage, whole table

| table | rows | heap before | index before | total before | bytes/row before | total after | bytes/row after | ratio |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| metrics_date | 1920000 | 152 MB | 13 MB | 166 MB | 90.72 | 53 MB | 28.73 | 3.16 |
| metrics_tstz | 1920000 | 152 MB | 13 MB | 166 MB | 90.72 | 56 MB | 30.37 | 2.99 |

## Storage per column

| table | column | type | uncompressed bytes | bytes/row | compressed bytes | bytes/row | ratio | batches | avg batch rows |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| metrics_date | day | date | 7680000 | 4.000 | 1059400 | 0.552 | 7.25 | 11600 | 165.5 |
| metrics_date | device_id | integer | 7680000 | 4.000 | 46400 | 0.024 | 165.52 | 11600 | 165.5 |
| metrics_date | region_id | integer | 7680000 | 4.000 | 594120 | 0.309 | 12.93 | 11600 | 165.5 |
| metrics_date | seq | bigint | 15360000 | 8.000 | 2322376 | 1.210 | 6.61 | 11600 | 165.5 |
| metrics_date | status | text | 8960266 | 4.667 | 1314600 | 0.685 | 6.82 | 11600 | 165.5 |
| metrics_date | v1 | double precision | 15360000 | 8.000 | 13350888 | 6.954 | 1.15 | 11600 | 165.5 |
| metrics_date | v2 | double precision | 15360000 | 8.000 | 14836664 | 7.727 | 1.04 | 11600 | 165.5 |
| metrics_date | v3 | integer | 7680000 | 4.000 | 2657888 | 1.384 | 2.89 | 11600 | 165.5 |
| metrics_date | (columns) |  | 85760266 | 44.667 | 36182336 | 18.845 | 2.37 |  |  |
| metrics_date | (heap) |  | 159637504 | 83.145 | 6160384 | 3.209 | 25.91 |  |  |
| metrics_date | (index) |  | 14057472 | 7.322 | 950272 | 0.495 | 14.79 |  |  |
| metrics_date | (toast) |  | 475136 | 0.247 | 48054272 | 25.028 | 0.01 |  |  |
| metrics_date | (total) |  | 174170112 | 90.714 | 55164928 | 28.732 | 3.16 |  |  |
| metrics_tstz | device_id | integer | 7680000 | 4.000 | 46400 | 0.024 | 165.52 | 11600 | 165.5 |
| metrics_tstz | region_id | integer | 7680000 | 4.000 | 594120 | 0.309 | 12.93 | 11600 | 165.5 |
| metrics_tstz | seq | bigint | 15360000 | 8.000 | 2322376 | 1.210 | 6.61 | 11600 | 165.5 |
| metrics_tstz | status | text | 8960266 | 4.667 | 1314600 | 0.685 | 6.82 | 11600 | 165.5 |
| metrics_tstz | ts | timestamp with time zone | 15360000 | 8.000 | 2976200 | 1.550 | 5.16 | 11600 | 165.5 |
| metrics_tstz | v1 | double precision | 15360000 | 8.000 | 13350888 | 6.954 | 1.15 | 11600 | 165.5 |
| metrics_tstz | v2 | double precision | 15360000 | 8.000 | 14836664 | 7.727 | 1.04 | 11600 | 165.5 |
| metrics_tstz | v3 | integer | 7680000 | 4.000 | 2657888 | 1.384 | 2.89 | 11600 | 165.5 |
| metrics_tstz | (columns) |  | 93440266 | 48.667 | 38099136 | 19.843 | 2.45 |  |  |
| metrics_tstz | (heap) |  | 159637504 | 83.145 | 6160384 | 3.209 | 25.91 |  |  |
| metrics_tstz | (index) |  | 14057472 | 7.322 | 950272 | 0.495 | 14.79 |  |  |
| metrics_tstz | (toast) |  | 475136 | 0.247 | 51208192 | 26.671 | 0.01 |  |  |
| metrics_tstz | (total) |  | 174170112 | 90.714 | 58318848 | 30.374 | 2.99 |  |  |

## Query texts

- **Q1** on `metrics_date`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_date WHERE day >= now() - interval '30 days'`
- **Q1** on `metrics_tstz`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_tstz WHERE ts >= now() - interval '30 days'`
- **Q1-np** on `metrics_date`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_date WHERE day >= now() - interval '30 days'`
- **Q1-np** on `metrics_tstz`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_tstz WHERE ts >= now() - interval '30 days'`
- **Q2** on `metrics_date`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_date WHERE day >= current_date - 30`
- **Q2** on `metrics_tstz`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_tstz WHERE ts >= date_trunc('day', now()) - interval '30 days'`
- **Q2-np** on `metrics_date`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_date WHERE day >= current_date - 30`
- **Q2-np** on `metrics_tstz`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_tstz WHERE ts >= date_trunc('day', now()) - interval '30 days'`
- **Q3** on `metrics_date`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_date WHERE day >= '2026-02-20' AND day < '2026-03-23'`
- **Q3** on `metrics_tstz`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_tstz WHERE ts >= '2026-02-20' AND ts < '2026-03-23'`
- **Q3-np** on `metrics_date`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_date WHERE day >= '2026-02-20' AND day < '2026-03-23'`
- **Q3-np** on `metrics_tstz`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_tstz WHERE ts >= '2026-02-20' AND ts < '2026-03-23'`
- **Q4** on `metrics_date`: `SELECT time_bucket(interval '7 days', day) AS bucket, device_id, avg(v1) AS avg_v1, max(v2) AS max_v2 FROM metrics_date WHERE day >= '2026-02-20' AND day < '2026-03-23' GROUP BY 1, 2`
- **Q4** on `metrics_tstz`: `SELECT time_bucket(interval '7 days', ts) AS bucket, device_id, avg(v1) AS avg_v1, max(v2) AS max_v2 FROM metrics_tstz WHERE ts >= '2026-02-20' AND ts < '2026-03-23' GROUP BY 1, 2`
- **Q4-np** on `metrics_date`: `SELECT time_bucket(interval '7 days', day) AS bucket, device_id, avg(v1) AS avg_v1, max(v2) AS max_v2 FROM metrics_date WHERE day >= '2026-02-20' AND day < '2026-03-23' GROUP BY 1, 2`
- **Q4-np** on `metrics_tstz`: `SELECT time_bucket(interval '7 days', ts) AS bucket, device_id, avg(v1) AS avg_v1, max(v2) AS max_v2 FROM metrics_tstz WHERE ts >= '2026-02-20' AND ts < '2026-03-23' GROUP BY 1, 2`
- **Q5** on `metrics_date`: `SELECT * FROM metrics_date WHERE device_id = 17 AND day = '2026-03-07'`
- **Q5** on `metrics_tstz`: `SELECT * FROM metrics_tstz WHERE device_id = 17 AND ts = '2026-03-07'`
- **Q5-np** on `metrics_date`: `SELECT * FROM metrics_date WHERE device_id = 17 AND day = '2026-03-07'`
- **Q5-np** on `metrics_tstz`: `SELECT * FROM metrics_tstz WHERE device_id = 17 AND ts = '2026-03-07'`
