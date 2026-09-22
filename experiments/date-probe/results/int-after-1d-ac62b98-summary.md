# DATE probe: variant `int-after-1d` @ ac62b98

run_id `int-after-1d-ac62b98-20260922T115100Z`, scale `small`, TimescaleDB 2.31.0-dev on PostgreSQL 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1), started 2026-09-22 11:51 UTC

| days | devices | rows/device/day | rows | chunk interval | default indexes | compress_orderby | column order | date range |
|---|---|---|---|---|---|---|---|---|
| 400 | 200 | 24 | 1920000 | 1 day | t | (default) | default | 2025-08-19 .. 2026-09-22 |

## Queries, median of three runs

| query | table | exec ms | plan ms | chunks in plan | excluded at startup | vectorized filter | top rows | rows scanned | workers | shared hit | shared read |
|---|---|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|
| Q1 | metrics_date | 12.10 | 2.27 | 30 | 1 | t | 1 | 144000 | 0 | 690 | 0 |
| Q1 | metrics_tstz | 14.66 | 2.73 | 31 | 0 | t | 1 | 144000 | 0 | 751 | 0 |
| Q1-np | metrics_date | 13.52 | 5.06 | 30 | 1 | t | 1 | 144000 | 0 | 690 | 0 |
| Q1-np | metrics_tstz | 13.23 | 2.09 | 31 | 0 | t | 1 | 144000 | 0 | 751 | 0 |
| Q2 | metrics_date | 11.18 | 2.08 | 31 | 1 | t | 1 | 148800 | 0 | 713 | 0 |
| Q2 | metrics_tstz | 17.19 | 44.89 | 31 | 369 | t | 1 | 148800 | 0 | 775 | 0 |
| Q2-np | metrics_date | 12.33 | 2.60 | 31 | 1 | t | 1 | 148800 | 0 | 713 | 0 |
| Q2-np | metrics_tstz | 17.51 | 41.49 | 31 | 369 | t | 1 | 148800 | 0 | 775 | 0 |
| Q3 | metrics_date | 8.25 | 1.17 | 31 | 0 | f | 1 | 148800 | 0 | 713 | 0 |
| Q3 | metrics_tstz | 9.57 | 1.55 | 31 | 0 | f | 1 | 148800 | 0 | 775 | 0 |
| Q3-np | metrics_date | 9.81 | 1.41 | 31 | 0 | f | 1 | 148800 | 0 | 713 | 0 |
| Q3-np | metrics_tstz | 9.07 | 1.75 | 31 | 0 | f | 1 | 148800 | 0 | 775 | 0 |
| Q4 | metrics_date | 33.48 | 2.19 | 31 | 0 | f | 1000 | 148800 | 0 | 713 | 0 |
| Q4 | metrics_tstz | 28.91 | 2.15 | 31 | 0 | f | 1000 | 148800 | 0 | 775 | 0 |
| Q4-np | metrics_date | 35.55 | 2.57 | 31 | 0 | f | 1000 | 148800 | 0 | 713 | 0 |
| Q4-np | metrics_tstz | 30.39 | 2.32 | 31 | 0 | f | 1000 | 148800 | 0 | 775 | 0 |
| Q5 | metrics_date | 0.03 | 0.18 | 1 | 0 | t | 24 | 24 | 0 | 2 | 0 |
| Q5 | metrics_tstz | 0.03 | 0.22 | 1 | 0 | t | 24 | 24 | 0 | 2 | 0 |
| Q5-np | metrics_date | 0.03 | 0.19 | 1 | 0 | t | 24 | 24 | 0 | 2 | 0 |
| Q5-np | metrics_tstz | 0.02 | 0.17 | 1 | 0 | t | 24 | 24 | 0 | 2 | 0 |

## Chunk index usage over the query set

`idx_scan` summed over the indexes of the chunks, sampled before and
after Q1..Q5. A zero delta on scope `chunk` means no query touched the
default time index.

| table | scope | indexes | index bytes | idx_scan before | after Q1-Q5 | delta | after Q1-np..Q5-np | delta |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| metrics_date | chunk | 400 | 3276800 | 269 | 269 | 0 | 269 | 0 |
| metrics_date | compressed | 400 | 6553600 | 0 | 3 | 3 | 6 | 3 |
| metrics_tstz | chunk | 400 | 3276800 | 269 | 269 | 0 | 269 | 0 |
| metrics_tstz | compressed | 400 | 6553600 | 0 | 6 | 6 | 12 | 6 |

## Load, compression and continuous aggregate

| table | phase | seconds | rows | rows/sec |
|---|---|---:|---:|---:|
| metrics_date | cagg_refresh | 1.25 | 80000 | 64213 |
| metrics_tstz | cagg_refresh | 1.40 | 80000 | 56948 |
| metrics_date | compress | 6.70 | 1920000 | 286581 |
| metrics_tstz | compress | 5.78 | 1920000 | 331959 |
| metrics_date | load | 5.46 | 1920000 | 351346 |
| metrics_tstz | load | 6.19 | 1920000 | 310368 |

## Storage, whole table

| table | rows | heap before | index before | total before | bytes/row before | total after | bytes/row after | ratio |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| metrics_date | 1920000 | 165 MB | 19 MB | 186 MB | 101.85 | 122 MB | 66.56 | 1.53 |
| metrics_tstz | 1920000 | 165 MB | 19 MB | 186 MB | 101.85 | 122 MB | 66.56 | 1.53 |

## Storage per column

| table | column | type | uncompressed bytes | bytes/row | compressed bytes | bytes/row | ratio | batches | avg batch rows |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| metrics_date | day | date | 7680000 | 4.000 | 4240000 | 2.208 | 1.81 | 80000 | 24.0 |
| metrics_date | device_id | integer | 7680000 | 4.000 | 320000 | 0.167 | 24.00 | 80000 | 24.0 |
| metrics_date | region_id | integer | 7680000 | 4.000 | 4112000 | 2.142 | 1.87 | 80000 | 24.0 |
| metrics_date | seq | bigint | 15360000 | 8.000 | 4239992 | 2.208 | 3.62 | 80000 | 24.0 |
| metrics_date | status | text | 8957957 | 4.666 | 5999939 | 3.125 | 1.49 | 80000 | 24.0 |
| metrics_date | v1 | double precision | 15360000 | 8.000 | 20251784 | 10.548 | 0.76 | 80000 | 24.0 |
| metrics_date | v2 | double precision | 15360000 | 8.000 | 22167256 | 11.545 | 0.69 | 80000 | 24.0 |
| metrics_date | v3 | integer | 7680000 | 4.000 | 5327256 | 2.775 | 1.44 | 80000 | 24.0 |
| metrics_date | (columns) |  | 85757957 | 44.666 | 66658227 | 34.718 | 1.29 |  |  |
| metrics_date | (heap) |  | 172589056 | 89.890 | 117964800 | 61.440 | 1.46 |  |  |
| metrics_date | (index) |  | 19660800 | 10.240 | 6553600 | 3.413 | 3.00 |  |  |
| metrics_date | (toast) |  | 3276800 | 1.707 | 3276800 | 1.707 | 1.00 |  |  |
| metrics_date | (total) |  | 195526656 | 101.837 | 127795200 | 66.560 | 1.53 |  |  |
| metrics_tstz | device_id | integer | 7680000 | 4.000 | 320000 | 0.167 | 24.00 | 80000 | 24.0 |
| metrics_tstz | region_id | integer | 7680000 | 4.000 | 4112000 | 2.142 | 1.87 | 80000 | 24.0 |
| metrics_tstz | seq | bigint | 15360000 | 8.000 | 4239992 | 2.208 | 3.62 | 80000 | 24.0 |
| metrics_tstz | status | text | 8957957 | 4.666 | 5999939 | 3.125 | 1.49 | 80000 | 24.0 |
| metrics_tstz | ts | timestamp with time zone | 15360000 | 8.000 | 4880000 | 2.542 | 3.15 | 80000 | 24.0 |
| metrics_tstz | v1 | double precision | 15360000 | 8.000 | 20251784 | 10.548 | 0.76 | 80000 | 24.0 |
| metrics_tstz | v2 | double precision | 15360000 | 8.000 | 22167256 | 11.545 | 0.69 | 80000 | 24.0 |
| metrics_tstz | v3 | integer | 7680000 | 4.000 | 5327256 | 2.775 | 1.44 | 80000 | 24.0 |
| metrics_tstz | (columns) |  | 93437957 | 48.666 | 67298227 | 35.051 | 1.39 |  |  |
| metrics_tstz | (heap) |  | 172589056 | 89.890 | 117964800 | 61.440 | 1.46 |  |  |
| metrics_tstz | (index) |  | 19660800 | 10.240 | 6553600 | 3.413 | 3.00 |  |  |
| metrics_tstz | (toast) |  | 3276800 | 1.707 | 3276800 | 1.707 | 1.00 |  |  |
| metrics_tstz | (total) |  | 195526656 | 101.837 | 127795200 | 66.560 | 1.53 |  |  |

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
