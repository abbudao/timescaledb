# DATE probe: variant `int-after-customer` @ 59db144

run_id `int-after-customer-59db144-20260922T115408Z`, scale `customer`, TimescaleDB 2.31.0-dev on PostgreSQL 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1), started 2026-09-22 11:54 UTC

| days | devices | rows/device/day | rows | chunk interval | default indexes | compress_orderby | column order | date range |
|---|---|---|---|---|---|---|---|---|
| 1095 | 2000 | 24 | 52560000 | 7 days | t | (default) | default | 2023-09-24 .. 2026-09-22 |

## Queries, median of three runs

| query | table | exec ms | plan ms | chunks in plan | excluded at startup | vectorized filter | top rows | rows scanned | workers | shared hit | shared read |
|---|---|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|
| Q1 | metrics_date | 39.31 | 0.62 | 5 | 0 | t | 1 | 1440000 | 2 | 60420 | 0 |
| Q1 | metrics_tstz | 30.31 | 0.54 | 5 | 0 | t | 1 | 1440000 | 2 | 60446 | 0 |
| Q1-np | metrics_date | 61.92 | 0.58 | 5 | 0 | t | 1 | 1440000 | 0 | 60225 | 0 |
| Q1-np | metrics_tstz | 61.43 | 0.56 | 5 | 0 | t | 1 | 1440000 | 0 | 60250 | 0 |
| Q2 | metrics_date | 32.75 | 0.59 | 5 | 0 | t | 1 | 1488000 | 2 | 60420 | 0 |
| Q2 | metrics_tstz | 46.81 | 13.97 | 5 | 152 | t | 1 | 1488000 | 2 | 60445 | 0 |
| Q2-np | metrics_date | 60.04 | 0.47 | 5 | 0 | t | 1 | 1488000 | 0 | 60225 | 0 |
| Q2-np | metrics_tstz | 61.83 | 14.32 | 5 | 152 | t | 1 | 1488000 | 0 | 60250 | 0 |
| Q3 | metrics_date | 34.34 | 0.57 | 5 | 0 | t | 1 | 1488000 | 2 | 42411 | 0 |
| Q3 | metrics_tstz | 32.78 | 0.55 | 5 | 0 | t | 1 | 1488000 | 2 | 42451 | 0 |
| Q3-np | metrics_date | 49.46 | 0.57 | 5 | 0 | t | 1 | 1488000 | 0 | 42234 | 0 |
| Q3-np | metrics_tstz | 50.78 | 0.54 | 5 | 0 | t | 1 | 1488000 | 0 | 42261 | 0 |
| Q4 | metrics_date | 126.91 | 0.60 | 5 | 0 | t | 12000 | 1488000 | 2 | 90436 | 0 |
| Q4 | metrics_tstz | 93.63 | 0.64 | 5 | 0 | t | 12000 | 1488000 | 2 | 90426 | 0 |
| Q4-np | metrics_date | 235.42 | 0.59 | 5 | 0 | t | 12000 | 1488000 | 0 | 90234 | 0 |
| Q4-np | metrics_tstz | 191.67 | 0.76 | 5 | 0 | t | 12000 | 1488000 | 0 | 90261 | 0 |
| Q5 | metrics_date | 0.07 | 0.17 | 1 | 0 | t | 24 | 24 | 0 | 24 | 0 |
| Q5 | metrics_tstz | 0.04 | 0.16 | 1 | 0 | t | 24 | 24 | 0 | 24 | 0 |
| Q5-np | metrics_date | 0.06 | 0.16 | 1 | 0 | t | 24 | 24 | 0 | 24 | 0 |
| Q5-np | metrics_tstz | 0.07 | 0.16 | 1 | 0 | t | 24 | 24 | 0 | 24 | 0 |

## Chunk index usage over the query set

`idx_scan` summed over the indexes of the chunks, sampled before and
after Q1..Q5. A zero delta on scope `chunk` means no query touched the
default time index.

| table | scope | indexes | index bytes | idx_scan before | after Q1-Q5 | delta | after Q1-np..Q5-np | delta |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| metrics_date | chunk | 157 | 1286144 | 316 | 316 | 0 | 316 | 0 |
| metrics_date | compressed | 157 | 12861440 | 0 | 9 | 9 | 18 | 9 |
| metrics_tstz | chunk | 157 | 1286144 | 317 | 317 | 0 | 317 | 0 |
| metrics_tstz | compressed | 157 | 15433728 | 0 | 3 | 3 | 12 | 9 |

## Load, compression and continuous aggregate

| table | phase | seconds | rows | rows/sec |
|---|---|---:|---:|---:|
| metrics_date | cagg_refresh | 21.63 | 2190000 | 101234 |
| metrics_tstz | cagg_refresh | 19.36 | 2190000 | 113114 |
| metrics_date | compress | 46.53 | 52560000 | 1129558 |
| metrics_tstz | compress | 52.62 | 52560000 | 998845 |
| metrics_date | load | 128.58 | 52560000 | 408765 |
| metrics_tstz | load | 156.47 | 52560000 | 335919 |

## Storage, whole table

| table | rows | heap before | index before | total before | bytes/row before | total after | bytes/row after | ratio |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| metrics_date | 52560000 | 4114 MB | 328 MB | 4442 MB | 88.62 | 1166 MB | 23.26 | 3.81 |
| metrics_tstz | 52560000 | 4114 MB | 328 MB | 4442 MB | 88.62 | 1373 MB | 27.40 | 3.23 |

## Storage per column

| table | column | type | uncompressed bytes | bytes/row | compressed bytes | bytes/row | ratio | batches | avg batch rows |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| metrics_date | day | date | 210240000 | 4.000 | 28825723 | 0.548 | 7.29 | 314000 | 167.4 |
| metrics_date | device_id | integer | 210240000 | 4.000 | 1256000 | 0.024 | 167.39 | 314000 | 167.4 |
| metrics_date | region_id | integer | 210240000 | 4.000 | 16078523 | 0.306 | 13.08 | 314000 | 167.4 |
| metrics_date | seq | bigint | 420480000 | 8.000 | 61478282 | 1.170 | 6.84 | 314000 | 167.4 |
| metrics_date | status | text | 245278977 | 4.667 | 35733723 | 0.680 | 6.86 | 314000 | 167.4 |
| metrics_date | v1 | double precision | 420480000 | 8.000 | 344151132 | 6.548 | 1.22 | 314000 | 167.4 |
| metrics_date | v2 | double precision | 420480000 | 8.000 | 405806908 | 7.721 | 1.04 | 314000 | 167.4 |
| metrics_date | v3 | integer | 210240000 | 4.000 | 72637316 | 1.382 | 2.89 | 314000 | 167.4 |
| metrics_date | (columns) |  | 2347678977 | 44.667 | 965967607 | 18.378 | 2.43 |  |  |
| metrics_date | (heap) |  | 4313374720 | 82.066 | 91127808 | 1.734 | 47.33 |  |  |
| metrics_date | (index) |  | 343441408 | 6.534 | 12861440 | 0.245 | 26.70 |  |  |
| metrics_date | (toast) |  | 1286144 | 0.024 | 1118748672 | 21.285 | 0.00 |  |  |
| metrics_date | (total) |  | 4658102272 | 88.624 | 1222737920 | 23.264 | 3.81 |  |  |
| metrics_tstz | device_id | integer | 210240000 | 4.000 | 1256000 | 0.024 | 167.39 | 314000 | 167.4 |
| metrics_tstz | region_id | integer | 210240000 | 4.000 | 16076800 | 0.306 | 13.08 | 314000 | 167.4 |
| metrics_tstz | seq | bigint | 420480000 | 8.000 | 61475752 | 1.170 | 6.84 | 314000 | 167.4 |
| metrics_tstz | status | text | 245278977 | 4.667 | 35732000 | 0.680 | 6.86 | 314000 | 167.4 |
| metrics_tstz | ts | timestamp with time zone | 420480000 | 8.000 | 81368000 | 1.548 | 5.17 | 314000 | 167.4 |
| metrics_tstz | v1 | double precision | 420480000 | 8.000 | 344144240 | 6.548 | 1.22 | 314000 | 167.4 |
| metrics_tstz | v2 | double precision | 420480000 | 8.000 | 405800016 | 7.721 | 1.04 | 314000 | 167.4 |
| metrics_tstz | v3 | integer | 210240000 | 4.000 | 72630424 | 1.382 | 2.89 | 314000 | 167.4 |
| metrics_tstz | (columns) |  | 2557918977 | 48.667 | 1018483232 | 19.378 | 2.51 |  |  |
| metrics_tstz | (heap) |  | 4313374720 | 82.066 | 87457792 | 1.664 | 49.32 |  |  |
| metrics_tstz | (index) |  | 343441408 | 6.534 | 15433728 | 0.294 | 22.25 |  |  |
| metrics_tstz | (toast) |  | 1286144 | 0.024 | 1337237504 | 25.442 | 0.00 |  |  |
| metrics_tstz | (total) |  | 4658102272 | 88.624 | 1440129024 | 27.400 | 3.23 |  |  |

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
