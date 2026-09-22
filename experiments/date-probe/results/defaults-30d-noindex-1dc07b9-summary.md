# DATE probe: variant `defaults-30d-noindex` @ 1dc07b9

run_id `defaults-30d-noindex-1dc07b9-20260922T010622Z`, scale `small`, TimescaleDB 2.31.0-dev on PostgreSQL 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1), started 2026-09-22 01:06 UTC

| days | devices | rows/device/day | rows | chunk interval | default indexes | compress_orderby | column order | date range |
|---|---|---|---|---|---|---|---|---|
| 400 | 200 | 24 | 1920000 | 30 days | f | (default) | default | 2025-08-19 .. 2026-09-22 |

## Queries, median of three runs

| query | table | exec ms | plan ms | chunks in plan | excluded at startup | vectorized filter | top rows | rows scanned | workers | shared hit | shared read |
|---|---|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|
| Q1 | metrics_date | 23.27 | 1.02 | 14 | 0 | f | 1 | 144000 | 2 | 2691 | 0 |
| Q1 | metrics_tstz | 15.44 | 0.31 | 2 | 0 | t | 1 | 144000 | 2 | 2636 | 0 |
| Q1-np | metrics_date | 13.03 | 0.88 | 14 | 0 | f | 1 | 144000 | 0 | 2592 | 0 |
| Q1-np | metrics_tstz | 5.03 | 0.35 | 2 | 0 | t | 1 | 144000 | 0 | 2589 | 0 |
| Q2 | metrics_date | 20.55 | 0.97 | 2 | 12 | t | 1 | 148800 | 2 | 2532 | 0 |
| Q2 | metrics_tstz | 17.82 | 1.09 | 2 | 12 | t | 1 | 148800 | 2 | 2589 | 0 |
| Q2-np | metrics_date | 4.85 | 0.72 | 2 | 12 | t | 1 | 148800 | 0 | 2532 | 0 |
| Q2-np | metrics_tstz | 4.97 | 0.89 | 2 | 12 | t | 1 | 148800 | 0 | 2589 | 0 |
| Q3 | metrics_date | 6.41 | 0.28 | 2 | 0 | t | 1 | 148800 | 0 | 2613 | 0 |
| Q3 | metrics_tstz | 6.62 | 0.32 | 2 | 0 | t | 1 | 148800 | 0 | 2618 | 0 |
| Q3-np | metrics_date | 5.89 | 0.21 | 2 | 0 | t | 1 | 148800 | 0 | 2613 | 0 |
| Q3-np | metrics_tstz | 6.04 | 0.23 | 2 | 0 | t | 1 | 148800 | 0 | 2618 | 0 |
| Q4 | metrics_date | 21.53 | 0.33 | 2 | 0 | t | 1000 | 148800 | 0 | 4000 | 0 |
| Q4 | metrics_tstz | 21.45 | 0.41 | 2 | 0 | t | 1000 | 148800 | 0 | 4030 | 0 |
| Q4-np | metrics_date | 21.53 | 0.32 | 2 | 0 | t | 1000 | 148800 | 0 | 4000 | 0 |
| Q4-np | metrics_tstz | 16.78 | 0.29 | 2 | 0 | t | 1000 | 148800 | 0 | 4030 | 0 |
| Q5 | metrics_date | 0.06 | 0.14 | 1 | 0 | t | 24 | 24 | 0 | 24 | 0 |
| Q5 | metrics_tstz | 0.06 | 0.16 | 1 | 0 | t | 24 | 24 | 0 | 24 | 0 |
| Q5-np | metrics_date | 0.06 | 0.15 | 1 | 0 | t | 24 | 24 | 0 | 24 | 0 |
| Q5-np | metrics_tstz | 0.06 | 0.17 | 1 | 0 | t | 24 | 24 | 0 | 24 | 0 |

## Chunk index usage over the query set

`idx_scan` summed over the indexes of the chunks, sampled before and
after Q1..Q5. A zero delta on scope `chunk` means no query touched the
default time index.

| table | scope | indexes | index bytes | idx_scan before | after Q1-Q5 | delta | after Q1-np..Q5-np | delta |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| metrics_date | chunk | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| metrics_date | compressed | 14 | 229376 | 0 | 3 | 3 | 6 | 3 |
| metrics_tstz | chunk | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| metrics_tstz | compressed | 14 | 229376 | 0 | 3 | 3 | 6 | 3 |

## Load, compression and continuous aggregate

| table | phase | seconds | rows | rows/sec |
|---|---|---:|---:|---:|
| metrics_date | cagg_refresh | 1.24 | 80000 | 64263 |
| metrics_tstz | cagg_refresh | 0.95 | 80000 | 84326 |
| metrics_date | compress | 1.33 | 1920000 | 1440889 |
| metrics_tstz | compress | 1.78 | 1920000 | 1081403 |
| metrics_date | load | 1.85 | 1920000 | 1036756 |
| metrics_tstz | load | 2.76 | 1920000 | 695279 |

## Storage, whole table

| table | rows | heap before | index before | total before | bytes/row before | total after | bytes/row after | ratio |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| metrics_date | 1920000 | 151 MB | 0 bytes | 151 MB | 82.29 | 36 MB | 19.78 | 4.16 |
| metrics_tstz | 1920000 | 151 MB | 0 bytes | 151 MB | 82.29 | 38 MB | 20.96 | 3.93 |

## Storage per column

| table | column | type | uncompressed bytes | bytes/row | compressed bytes | bytes/row | ratio | batches | avg batch rows |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| metrics_date | day | date | 7680000 | 4.000 | 635200 | 0.331 | 12.09 | 2800 | 685.7 |
| metrics_date | device_id | integer | 7680000 | 4.000 | 11200 | 0.006 | 685.71 | 2800 | 685.7 |
| metrics_date | region_id | integer | 7680000 | 4.000 | 143360 | 0.075 | 53.57 | 2800 | 685.7 |
| metrics_date | seq | bigint | 15360000 | 8.000 | 2095456 | 1.091 | 7.33 | 2800 | 685.7 |
| metrics_date | status | text | 8958633 | 4.666 | 695200 | 0.362 | 12.89 | 2800 | 685.7 |
| metrics_date | v1 | double precision | 15360000 | 8.000 | 12557352 | 6.540 | 1.22 | 2800 | 685.7 |
| metrics_date | v2 | double precision | 15360000 | 8.000 | 13941704 | 7.261 | 1.10 | 2800 | 685.7 |
| metrics_date | v3 | integer | 7680000 | 4.000 | 2347816 | 1.223 | 3.27 | 2800 | 685.7 |
| metrics_date | (columns) |  | 85758633 | 44.666 | 32427288 | 16.889 | 2.64 |  |  |
| metrics_date | (heap) |  | 157868032 | 82.223 | 1376256 | 0.717 | 114.71 |  |  |
| metrics_date | (index) |  | 0 | 0.000 | 229376 | 0.119 | 0.00 |  |  |
| metrics_date | (toast) |  | 114688 | 0.060 | 36372480 | 18.944 | 0.00 |  |  |
| metrics_date | (total) |  | 157982720 | 82.283 | 37978112 | 19.780 | 4.16 |  |  |
| metrics_tstz | device_id | integer | 7680000 | 4.000 | 11200 | 0.006 | 685.71 | 2800 | 685.7 |
| metrics_tstz | region_id | integer | 7680000 | 4.000 | 143360 | 0.075 | 53.57 | 2800 | 685.7 |
| metrics_tstz | seq | bigint | 15360000 | 8.000 | 2095456 | 1.091 | 7.33 | 2800 | 685.7 |
| metrics_tstz | status | text | 8958633 | 4.666 | 695200 | 0.362 | 12.89 | 2800 | 685.7 |
| metrics_tstz | ts | timestamp with time zone | 15360000 | 8.000 | 2787200 | 1.452 | 5.51 | 2800 | 685.7 |
| metrics_tstz | v1 | double precision | 15360000 | 8.000 | 12557352 | 6.540 | 1.22 | 2800 | 685.7 |
| metrics_tstz | v2 | double precision | 15360000 | 8.000 | 13941704 | 7.261 | 1.10 | 2800 | 685.7 |
| metrics_tstz | v3 | integer | 7680000 | 4.000 | 2347816 | 1.223 | 3.27 | 2800 | 685.7 |
| metrics_tstz | (columns) |  | 93438633 | 48.666 | 34579288 | 18.010 | 2.70 |  |  |
| metrics_tstz | (heap) |  | 157868032 | 82.223 | 1376256 | 0.717 | 114.71 |  |  |
| metrics_tstz | (index) |  | 0 | 0.000 | 229376 | 0.119 | 0.00 |  |  |
| metrics_tstz | (toast) |  | 114688 | 0.060 | 38641664 | 20.126 | 0.00 |  |  |
| metrics_tstz | (total) |  | 157982720 | 82.283 | 40247296 | 20.962 | 3.93 |  |  |

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
