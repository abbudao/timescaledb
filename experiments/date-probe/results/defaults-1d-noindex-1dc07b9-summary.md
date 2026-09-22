# DATE probe: variant `defaults-1d-noindex` @ 1dc07b9

run_id `defaults-1d-noindex-1dc07b9-20260922T010357Z`, scale `small`, TimescaleDB 2.31.0-dev on PostgreSQL 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1), started 2026-09-22 01:03 UTC

| days | devices | rows/device/day | rows | chunk interval | default indexes | compress_orderby | column order | date range |
|---|---|---|---|---|---|---|---|---|
| 400 | 200 | 24 | 1920000 | 1 day | f | (default) | default | 2025-08-19 .. 2026-09-22 |

## Queries, median of three runs

| query | table | exec ms | plan ms | chunks in plan | excluded at startup | vectorized filter | top rows | rows scanned | workers | shared hit | shared read |
|---|---|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|
| Q1 | metrics_date | 97.82 | 31.93 | 400 | 0 | f | 1 | 144000 | 2 | 9200 | 0 |
| Q1 | metrics_tstz | 11.95 | 1.84 | 31 | 1 | t | 1 | 144000 | 0 | 751 | 0 |
| Q1-np | metrics_date | 56.71 | 31.15 | 400 | 0 | f | 1 | 144000 | 0 | 9200 | 0 |
| Q1-np | metrics_tstz | 12.36 | 1.81 | 31 | 1 | t | 1 | 144000 | 0 | 751 | 0 |
| Q2 | metrics_date | 12.87 | 32.06 | 31 | 369 | t | 1 | 148800 | 0 | 713 | 0 |
| Q2 | metrics_tstz | 16.36 | 36.52 | 31 | 369 | t | 1 | 148800 | 0 | 775 | 0 |
| Q2-np | metrics_date | 12.75 | 30.05 | 31 | 369 | t | 1 | 148800 | 0 | 713 | 0 |
| Q2-np | metrics_tstz | 16.63 | 35.97 | 31 | 369 | t | 1 | 148800 | 0 | 775 | 0 |
| Q3 | metrics_date | 7.63 | 1.22 | 31 | 0 | f | 1 | 148800 | 0 | 713 | 0 |
| Q3 | metrics_tstz | 7.88 | 0.93 | 31 | 0 | f | 1 | 148800 | 0 | 775 | 0 |
| Q3-np | metrics_date | 7.71 | 0.99 | 31 | 0 | f | 1 | 148800 | 0 | 713 | 0 |
| Q3-np | metrics_tstz | 7.88 | 1.06 | 31 | 0 | f | 1 | 148800 | 0 | 775 | 0 |
| Q4 | metrics_date | 31.93 | 1.54 | 31 | 0 | f | 1000 | 148800 | 0 | 713 | 0 |
| Q4 | metrics_tstz | 26.87 | 1.83 | 31 | 0 | f | 1000 | 148800 | 0 | 775 | 0 |
| Q4-np | metrics_date | 31.97 | 1.49 | 31 | 0 | f | 1000 | 148800 | 0 | 713 | 0 |
| Q4-np | metrics_tstz | 27.85 | 1.84 | 31 | 0 | f | 1000 | 148800 | 0 | 775 | 0 |
| Q5 | metrics_date | 0.02 | 0.16 | 1 | 0 | t | 24 | 24 | 0 | 2 | 0 |
| Q5 | metrics_tstz | 0.03 | 0.14 | 1 | 0 | t | 24 | 24 | 0 | 2 | 0 |
| Q5-np | metrics_date | 0.03 | 0.15 | 1 | 0 | t | 24 | 24 | 0 | 2 | 0 |
| Q5-np | metrics_tstz | 0.02 | 0.16 | 1 | 0 | t | 24 | 24 | 0 | 2 | 0 |

## Chunk index usage over the query set

`idx_scan` summed over the indexes of the chunks, sampled before and
after Q1..Q5. A zero delta on scope `chunk` means no query touched the
default time index.

| table | scope | indexes | index bytes | idx_scan before | after Q1-Q5 | delta | after Q1-np..Q5-np | delta |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| metrics_date | chunk | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| metrics_date | compressed | 400 | 6553600 | 0 | 3 | 3 | 6 | 3 |
| metrics_tstz | chunk | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| metrics_tstz | compressed | 400 | 6553600 | 0 | 6 | 6 | 12 | 6 |

## Load, compression and continuous aggregate

| table | phase | seconds | rows | rows/sec |
|---|---|---:|---:|---:|
| metrics_date | cagg_refresh | 1.08 | 80000 | 74302 |
| metrics_tstz | cagg_refresh | 1.02 | 80000 | 78735 |
| metrics_date | compress | 4.84 | 1920000 | 396581 |
| metrics_tstz | compress | 5.12 | 1920000 | 374840 |
| metrics_date | load | 2.57 | 1920000 | 746250 |
| metrics_tstz | load | 3.38 | 1920000 | 567817 |

## Storage, whole table

| table | rows | heap before | index before | total before | bytes/row before | total after | bytes/row after | ratio |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| metrics_date | 1920000 | 164 MB | 0 bytes | 168 MB | 91.55 | 122 MB | 66.56 | 1.38 |
| metrics_tstz | 1920000 | 164 MB | 0 bytes | 168 MB | 91.55 | 122 MB | 66.56 | 1.38 |

## Storage per column

| table | column | type | uncompressed bytes | bytes/row | compressed bytes | bytes/row | ratio | batches | avg batch rows |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| metrics_date | day | date | 7680000 | 4.000 | 4240000 | 2.208 | 1.81 | 80000 | 24.0 |
| metrics_date | device_id | integer | 7680000 | 4.000 | 320000 | 0.167 | 24.00 | 80000 | 24.0 |
| metrics_date | region_id | integer | 7680000 | 4.000 | 4112000 | 2.142 | 1.87 | 80000 | 24.0 |
| metrics_date | seq | bigint | 15360000 | 8.000 | 4239992 | 2.208 | 3.62 | 80000 | 24.0 |
| metrics_date | status | text | 8958986 | 4.666 | 5999921 | 3.125 | 1.49 | 80000 | 24.0 |
| metrics_date | v1 | double precision | 15360000 | 8.000 | 20252280 | 10.548 | 0.76 | 80000 | 24.0 |
| metrics_date | v2 | double precision | 15360000 | 8.000 | 22170328 | 11.547 | 0.69 | 80000 | 24.0 |
| metrics_date | v3 | integer | 7680000 | 4.000 | 5329384 | 2.776 | 1.44 | 80000 | 24.0 |
| metrics_date | (columns) |  | 85758986 | 44.666 | 66663905 | 34.721 | 1.29 |  |  |
| metrics_date | (heap) |  | 172482560 | 89.835 | 117964800 | 61.440 | 1.46 |  |  |
| metrics_date | (index) |  | 0 | 0.000 | 6553600 | 3.413 | 0.00 |  |  |
| metrics_date | (toast) |  | 3276800 | 1.707 | 3276800 | 1.707 | 1.00 |  |  |
| metrics_date | (total) |  | 175759360 | 91.541 | 127795200 | 66.560 | 1.38 |  |  |
| metrics_tstz | device_id | integer | 7680000 | 4.000 | 320000 | 0.167 | 24.00 | 80000 | 24.0 |
| metrics_tstz | region_id | integer | 7680000 | 4.000 | 4112000 | 2.142 | 1.87 | 80000 | 24.0 |
| metrics_tstz | seq | bigint | 15360000 | 8.000 | 4239992 | 2.208 | 3.62 | 80000 | 24.0 |
| metrics_tstz | status | text | 8958986 | 4.666 | 5999921 | 3.125 | 1.49 | 80000 | 24.0 |
| metrics_tstz | ts | timestamp with time zone | 15360000 | 8.000 | 4880000 | 2.542 | 3.15 | 80000 | 24.0 |
| metrics_tstz | v1 | double precision | 15360000 | 8.000 | 20252280 | 10.548 | 0.76 | 80000 | 24.0 |
| metrics_tstz | v2 | double precision | 15360000 | 8.000 | 22170328 | 11.547 | 0.69 | 80000 | 24.0 |
| metrics_tstz | v3 | integer | 7680000 | 4.000 | 5329384 | 2.776 | 1.44 | 80000 | 24.0 |
| metrics_tstz | (columns) |  | 93438986 | 48.666 | 67303905 | 35.054 | 1.39 |  |  |
| metrics_tstz | (heap) |  | 172482560 | 89.835 | 117964800 | 61.440 | 1.46 |  |  |
| metrics_tstz | (index) |  | 0 | 0.000 | 6553600 | 3.413 | 0.00 |  |  |
| metrics_tstz | (toast) |  | 3276800 | 1.707 | 3276800 | 1.707 | 1.00 |  |  |
| metrics_tstz | (total) |  | 175759360 | 91.541 | 127795200 | 66.560 | 1.38 |  |  |

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
