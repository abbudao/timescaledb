# DATE probe: variant `int-baseline-customer` @ 59db144

run_id `int-baseline-customer-59db144-20260922T120853Z`, scale `customer`, TimescaleDB 2.31.0-dev on PostgreSQL 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1), started 2026-09-22 12:08 UTC

| days | devices | rows/device/day | rows | chunk interval | default indexes | compress_orderby | column order | date range |
|---|---|---|---|---|---|---|---|---|
| 1095 | 2000 | 24 | 52560000 | 7 days | t | (default) | default | 2023-09-24 .. 2026-09-22 |

## Queries, median of three runs

| query | table | exec ms | plan ms | chunks in plan | excluded at startup | vectorized filter | top rows | rows scanned | workers | shared hit | shared read |
|---|---|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|
| Q1 | metrics_date | 442.67 | 12.71 | 157 | 0 | f | 1 | 1440000 | 2 | 67611 | 0 |
| Q1 | metrics_tstz | 33.92 | 1.51 | 5 | 0 | t | 1 | 1440000 | 2 | 60446 | 0 |
| Q1-np | metrics_date | 531.61 | 12.76 | 157 | 0 | f | 1 | 1440000 | 0 | 67479 | 0 |
| Q1-np | metrics_tstz | 63.25 | 0.57 | 5 | 0 | t | 1 | 1440000 | 0 | 60250 | 0 |
| Q2 | metrics_date | 56.90 | 12.24 | 5 | 152 | t | 1 | 1488000 | 2 | 60370 | 0 |
| Q2 | metrics_tstz | 61.02 | 14.76 | 5 | 152 | t | 1 | 1488000 | 2 | 60445 | 0 |
| Q2-np | metrics_date | 65.85 | 11.23 | 5 | 152 | t | 1 | 1488000 | 0 | 60225 | 0 |
| Q2-np | metrics_tstz | 68.64 | 17.07 | 5 | 152 | t | 1 | 1488000 | 0 | 60250 | 0 |
| Q3 | metrics_date | 42.33 | 0.60 | 5 | 0 | t | 1 | 1488000 | 2 | 42362 | 0 |
| Q3 | metrics_tstz | 30.25 | 0.56 | 5 | 0 | t | 1 | 1488000 | 2 | 42451 | 0 |
| Q3-np | metrics_date | 52.91 | 0.67 | 5 | 0 | t | 1 | 1488000 | 0 | 42234 | 0 |
| Q3-np | metrics_tstz | 51.61 | 0.54 | 5 | 0 | t | 1 | 1488000 | 0 | 42261 | 0 |
| Q4 | metrics_date | 135.44 | 0.83 | 5 | 0 | t | 12000 | 1488000 | 2 | 90411 | 0 |
| Q4 | metrics_tstz | 113.69 | 0.68 | 5 | 0 | t | 12000 | 1488000 | 2 | 90426 | 0 |
| Q4-np | metrics_date | 258.15 | 0.68 | 5 | 0 | t | 12000 | 1488000 | 0 | 90234 | 0 |
| Q4-np | metrics_tstz | 183.56 | 0.79 | 5 | 0 | t | 12000 | 1488000 | 0 | 90261 | 0 |
| Q5 | metrics_date | 0.04 | 0.22 | 1 | 0 | t | 24 | 24 | 0 | 24 | 0 |
| Q5 | metrics_tstz | 0.04 | 0.23 | 1 | 0 | t | 24 | 24 | 0 | 24 | 0 |
| Q5-np | metrics_date | 0.06 | 0.24 | 1 | 0 | t | 24 | 24 | 0 | 24 | 0 |
| Q5-np | metrics_tstz | 0.06 | 0.27 | 1 | 0 | t | 24 | 24 | 0 | 24 | 0 |

## Chunk index usage over the query set

`idx_scan` summed over the indexes of the chunks, sampled before and
after Q1..Q5. A zero delta on scope `chunk` means no query touched the
default time index.

| table | scope | indexes | index bytes | idx_scan before | after Q1-Q5 | delta | after Q1-np..Q5-np | delta |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| metrics_date | chunk | 157 | 1286144 | 316 | 316 | 0 | 316 | 0 |
| metrics_date | compressed | 157 | 12861440 | 0 | 13 | 13 | 22 | 9 |
| metrics_tstz | chunk | 157 | 1286144 | 317 | 317 | 0 | 317 | 0 |
| metrics_tstz | compressed | 157 | 15433728 | 0 | 3 | 3 | 12 | 9 |

## Load, compression and continuous aggregate

| table | phase | seconds | rows | rows/sec |
|---|---|---:|---:|---:|
| metrics_date | cagg_refresh | 21.13 | 2190000 | 103643 |
| metrics_tstz | cagg_refresh | 18.92 | 2190000 | 115780 |
| metrics_date | compress | 46.24 | 52560000 | 1136631 |
| metrics_tstz | compress | 54.77 | 52560000 | 959698 |
| metrics_date | load | 128.40 | 52560000 | 409355 |
| metrics_tstz | load | 155.36 | 52560000 | 338312 |

## Storage, whole table

| table | rows | heap before | index before | total before | bytes/row before | total after | bytes/row after | ratio |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| metrics_date | 52560000 | 4114 MB | 328 MB | 4442 MB | 88.62 | 1166 MB | 23.26 | 3.81 |
| metrics_tstz | 52560000 | 4114 MB | 328 MB | 4442 MB | 88.62 | 1373 MB | 27.40 | 3.23 |

## Storage per column

| table | column | type | uncompressed bytes | bytes/row | compressed bytes | bytes/row | ratio | batches | avg batch rows |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| metrics_date | day | date | 210240000 | 4.000 | 28825721 | 0.548 | 7.29 | 314000 | 167.4 |
| metrics_date | device_id | integer | 210240000 | 4.000 | 1256000 | 0.024 | 167.39 | 314000 | 167.4 |
| metrics_date | region_id | integer | 210240000 | 4.000 | 16078521 | 0.306 | 13.08 | 314000 | 167.4 |
| metrics_date | seq | bigint | 420480000 | 8.000 | 61478301 | 1.170 | 6.84 | 314000 | 167.4 |
| metrics_date | status | text | 245290928 | 4.667 | 35733721 | 0.680 | 6.86 | 314000 | 167.4 |
| metrics_date | v1 | double precision | 420480000 | 8.000 | 344148580 | 6.548 | 1.22 | 314000 | 167.4 |
| metrics_date | v2 | double precision | 420480000 | 8.000 | 405812028 | 7.721 | 1.04 | 314000 | 167.4 |
| metrics_date | v3 | integer | 210240000 | 4.000 | 72640908 | 1.382 | 2.89 | 314000 | 167.4 |
| metrics_date | (columns) |  | 2347690928 | 44.667 | 965973780 | 18.378 | 2.43 |  |  |
| metrics_date | (heap) |  | 4313382912 | 82.066 | 91127808 | 1.734 | 47.33 |  |  |
| metrics_date | (index) |  | 343441408 | 6.534 | 12861440 | 0.245 | 26.70 |  |  |
| metrics_date | (toast) |  | 1286144 | 0.024 | 1118797824 | 21.286 | 0.00 |  |  |
| metrics_date | (total) |  | 4658110464 | 88.625 | 1222787072 | 23.265 | 3.81 |  |  |
| metrics_tstz | device_id | integer | 210240000 | 4.000 | 1256000 | 0.024 | 167.39 | 314000 | 167.4 |
| metrics_tstz | region_id | integer | 210240000 | 4.000 | 16076800 | 0.306 | 13.08 | 314000 | 167.4 |
| metrics_tstz | seq | bigint | 420480000 | 8.000 | 61475752 | 1.170 | 6.84 | 314000 | 167.4 |
| metrics_tstz | status | text | 245290928 | 4.667 | 35732000 | 0.680 | 6.86 | 314000 | 167.4 |
| metrics_tstz | ts | timestamp with time zone | 420480000 | 8.000 | 81368000 | 1.548 | 5.17 | 314000 | 167.4 |
| metrics_tstz | v1 | double precision | 420480000 | 8.000 | 344141696 | 6.548 | 1.22 | 314000 | 167.4 |
| metrics_tstz | v2 | double precision | 420480000 | 8.000 | 405805144 | 7.721 | 1.04 | 314000 | 167.4 |
| metrics_tstz | v3 | integer | 210240000 | 4.000 | 72634024 | 1.382 | 2.89 | 314000 | 167.4 |
| metrics_tstz | (columns) |  | 2557930928 | 48.667 | 1018489416 | 19.378 | 2.51 |  |  |
| metrics_tstz | (heap) |  | 4313382912 | 82.066 | 87457792 | 1.664 | 49.32 |  |  |
| metrics_tstz | (index) |  | 343441408 | 6.534 | 15433728 | 0.294 | 22.25 |  |  |
| metrics_tstz | (toast) |  | 1286144 | 0.024 | 1337294848 | 25.443 | 0.00 |  |  |
| metrics_tstz | (total) |  | 4658110464 | 88.625 | 1440186368 | 27.401 | 3.23 |  |  |

## Query texts

- **Q1** on `metrics_date`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_date WHERE day >= now() - interval '30 days'`
- **Q1** on `metrics_tstz`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_tstz WHERE ts >= now() - interval '30 days'`
- **Q1-np** on `metrics_date`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_date WHERE day >= now() - interval '30 days'`
- **Q1-np** on `metrics_tstz`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_tstz WHERE ts >= now() - interval '30 days'`
- **Q2** on `metrics_date`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_date WHERE day >= current_date - 30`
- **Q2** on `metrics_tstz`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_tstz WHERE ts >= date_trunc('day', now()) - interval '30 days'`
- **Q2-np** on `metrics_date`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_date WHERE day >= current_date - 30`
- **Q2-np** on `metrics_tstz`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_tstz WHERE ts >= date_trunc('day', now()) - interval '30 days'`
- **Q3** on `metrics_date`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_date WHERE day >= '2025-03-09' AND day < '2025-04-09'`
- **Q3** on `metrics_tstz`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_tstz WHERE ts >= '2025-03-09' AND ts < '2025-04-09'`
- **Q3-np** on `metrics_date`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_date WHERE day >= '2025-03-09' AND day < '2025-04-09'`
- **Q3-np** on `metrics_tstz`: `SELECT count(*) AS n, avg(v1) AS avg_v1 FROM metrics_tstz WHERE ts >= '2025-03-09' AND ts < '2025-04-09'`
- **Q4** on `metrics_date`: `SELECT time_bucket(interval '7 days', day) AS bucket, device_id, avg(v1) AS avg_v1, max(v2) AS max_v2 FROM metrics_date WHERE day >= '2025-03-09' AND day < '2025-04-09' GROUP BY 1, 2`
- **Q4** on `metrics_tstz`: `SELECT time_bucket(interval '7 days', ts) AS bucket, device_id, avg(v1) AS avg_v1, max(v2) AS max_v2 FROM metrics_tstz WHERE ts >= '2025-03-09' AND ts < '2025-04-09' GROUP BY 1, 2`
- **Q4-np** on `metrics_date`: `SELECT time_bucket(interval '7 days', day) AS bucket, device_id, avg(v1) AS avg_v1, max(v2) AS max_v2 FROM metrics_date WHERE day >= '2025-03-09' AND day < '2025-04-09' GROUP BY 1, 2`
- **Q4-np** on `metrics_tstz`: `SELECT time_bucket(interval '7 days', ts) AS bucket, device_id, avg(v1) AS avg_v1, max(v2) AS max_v2 FROM metrics_tstz WHERE ts >= '2025-03-09' AND ts < '2025-04-09' GROUP BY 1, 2`
- **Q5** on `metrics_date`: `SELECT * FROM metrics_date WHERE device_id = 17 AND day = '2025-03-24'`
- **Q5** on `metrics_tstz`: `SELECT * FROM metrics_tstz WHERE device_id = 17 AND ts = '2025-03-24'`
- **Q5-np** on `metrics_date`: `SELECT * FROM metrics_date WHERE device_id = 17 AND day = '2025-03-24'`
- **Q5-np** on `metrics_tstz`: `SELECT * FROM metrics_tstz WHERE device_id = 17 AND ts = '2025-03-24'`
