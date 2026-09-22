-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.


-- This function return a jsonb with the following keys:
-- - columns: an array of column names that shold be used for segment by
-- - confidence: a number between 0 and 10 (most confident) indicating how sure we are.
-- - message: a message that should be displayed to the user to evaluate the result.
CREATE OR REPLACE FUNCTION _timescaledb_functions.get_segmentby_defaults(
    relation regclass
)
    RETURNS JSONB LANGUAGE PLPGSQL AS
$BODY$
DECLARE
    _table_name NAME;
    _schema_name NAME;
    _hypertable_row _timescaledb_catalog.hypertable;
    _segmentby NAME;
    _cnt int;
BEGIN
    SELECT n.nspname, c.relname INTO STRICT _schema_name, _table_name
    FROM pg_class c
    INNER JOIN pg_namespace n ON (n.oid = c.relnamespace)
    WHERE c.oid = relation;

    SELECT * INTO STRICT _hypertable_row FROM _timescaledb_catalog.hypertable h WHERE h.table_name = _table_name AND h.schema_name = _schema_name;

    --STEP 1 if column stats exist use unique indexes.
    --Pick the column that comes first in any such indexes
    --Select the column such that tuples are segmented evenly across distinct values.
    --Note: this will only pick a column that is NOT unique in a multi-column unique index.
    with index_attr as (
      SELECT
        a.attnum, min(a.pos) as pos
      FROM (
        SELECT indkey, indnkeyatts
        FROM pg_catalog.pg_index
        WHERE indisunique AND indrelid = relation
      ) i
      INNER JOIN LATERAL (
        SELECT * FROM unnest(i.indkey) WITH ORDINALITY
      ) a(attnum, pos) ON TRUE
      WHERE a.pos <= i.indnkeyatts
      GROUP BY a.attnum
    ),
    stats_with_stddev as (
      SELECT
        a.attname,
        i.pos,
        ROUND(stddev_pop(freqs)::numeric, 5) as freq_stddev
      FROM index_attr i
      INNER JOIN pg_attribute a ON a.attnum = i.attnum AND a.attrelid = relation
      INNER JOIN pg_type t ON t.oid = a.atttypid
      INNER JOIN pg_stats s ON s.attname = a.attname
                            AND s.schemaname = _schema_name
                            AND s.tablename = _table_name
                            AND s.inherited = true
      LEFT JOIN LATERAL unnest(s.most_common_freqs) as freqs ON TRUE
      WHERE a.attname NOT IN (
        SELECT column_name
        FROM _timescaledb_catalog.dimension d
        WHERE d.hypertable_id = _hypertable_row.id
      )
      AND s.n_distinct > 1
      -- exclude date/time type category
      AND t.typcategory NOT IN ('D')
      GROUP BY a.attname, i.pos
    )
    SELECT attname
    INTO _segmentby
    FROM stats_with_stddev
    ORDER BY pos ASC, freq_stddev ASC NULLS LAST
    LIMIT 1;

    IF FOUND THEN
        return json_build_object('columns', json_build_array(_segmentby), 'confidence', 10);
    END IF;


    --STEP 2 if column stats exist and no unique indexes use non-unique indexes.
    --Pick the column that comes first in any such indexes
    --Select the column such that tuples are segmented evenly across distinct values.
    with index_attr as (
        SELECT
        a.attnum, min(a.pos) as pos
        FROM
            (select indkey, indnkeyatts from pg_catalog.pg_index where NOT indisunique and indrelid = relation) i
        INNER JOIN LATERAL
            (select * from unnest(i.indkey) with ordinality) a(attnum, pos) ON (TRUE)
        WHERE a.pos <= i.indnkeyatts
        GROUP BY 1
    ),
    stats_with_stddev as (
      SELECT
        a.attname,
        i.pos,
        ROUND(stddev_pop(freqs)::numeric, 5) as freq_stddev
      FROM index_attr i
      INNER JOIN pg_attribute a ON a.attnum = i.attnum AND a.attrelid = relation
      INNER JOIN pg_type t ON t.oid = a.atttypid
      INNER JOIN pg_stats s ON s.attname = a.attname
                            AND s.schemaname = _schema_name
                            AND s.tablename = _table_name
                            AND s.inherited = true
      LEFT JOIN LATERAL unnest(s.most_common_freqs) as freqs ON TRUE
      WHERE a.attname NOT IN (
        SELECT column_name
        FROM _timescaledb_catalog.dimension d
        WHERE d.hypertable_id = _hypertable_row.id
      )
      AND s.n_distinct > 1
      AND t.typcategory NOT IN ('D')
      GROUP BY a.attname, i.pos
    )
    SELECT attname
    INTO _segmentby
    FROM stats_with_stddev
    ORDER BY pos ASC, freq_stddev ASC NULLS LAST
    LIMIT 1;

    IF FOUND THEN
        return json_build_object('columns', json_build_array(_segmentby), 'confidence', 8);
    END IF;

    --STEP 3 if column stats exist but there are no indexes
    --Select the column such that tuples are segmented evenly across distinct values.
    with stats_with_stddev as (
      SELECT
        a.attname,
        ROUND(stddev_pop(freqs)::numeric, 5) as freq_stddev
      FROM pg_attribute a
      INNER JOIN pg_type t ON t.oid = a.atttypid
      INNER JOIN pg_stats s ON s.attname = a.attname
                            AND s.schemaname = _schema_name
                            AND s.tablename = _table_name
                            AND s.inherited = true
      LEFT JOIN LATERAL unnest(s.most_common_freqs) as freqs ON TRUE
      WHERE a.attrelid = relation
        AND a.attname NOT IN (
          SELECT column_name
          FROM _timescaledb_catalog.dimension d
          WHERE d.hypertable_id = _hypertable_row.id
        )
      AND s.n_distinct > 1
      AND t.typcategory NOT IN ('D')
      GROUP BY a.attname
    )
    SELECT attname
    INTO _segmentby
    FROM stats_with_stddev
    ORDER BY freq_stddev ASC NULLS LAST
    LIMIT 1;

    IF FOUND THEN
        return json_build_object('columns', json_build_array(_segmentby), 'confidence', 7);
    END IF;

    --STEP 4 if column stats do not exist use non-unique indexes. Pick the column that comes first in any such indexes. Ties are broken arbitrarily.
    with index_attr as (
        SELECT
        a.attnum, min(a.pos) as pos
        FROM
            (select indkey, indnkeyatts from pg_catalog.pg_index where NOT indisunique and indrelid = relation) i
        INNER JOIN LATERAL
            (select * from unnest(i.indkey) with ordinality) a(attnum, pos) ON (TRUE)
        WHERE a.pos <= i.indnkeyatts
        GROUP BY 1
    )
    SELECT
      a.attname INTO _segmentby
    FROM
      index_attr i
    INNER JOIN
      pg_attribute a on (a.attnum = i.attnum AND a.attrelid = relation)
    INNER JOIN
      pg_type t ON t.oid = a.atttypid
    LEFT JOIN
      pg_catalog.pg_attrdef ad ON (ad.adrelid = relation AND ad.adnum = a.attnum)
    LEFT JOIN pg_stats s ON s.attname = a.attname
                          AND s.schemaname = _schema_name
                          AND s.tablename = _table_name
                          AND s.inherited = true
    WHERE
      a.attname NOT IN (SELECT column_name FROM _timescaledb_catalog.dimension d WHERE d.hypertable_id = _hypertable_row.id)
      AND s.n_distinct is null
      AND a.attidentity = '' AND (ad.adbin IS NULL OR pg_get_expr(adbin, adrelid) not like 'nextval%')
      AND t.typcategory NOT IN ('D')
    ORDER BY i.pos
    LIMIT 1;

    IF FOUND THEN
        return json_build_object(
            'columns', json_build_array(_segmentby),
            'confidence', 5,
            'message',  'Please make sure '|| _segmentby||' is not a unique column and appropriate for a segment by');
    END IF;

    --STEP 5 if column stats do not exist and no non-unique indexes, use unique indexes. Pick the column that comes first in any such indexes. Ties are broken arbitrarily.
    with index_attr as (
        SELECT
        a.attnum, min(a.pos) as pos
        FROM
            (select indkey, indnkeyatts from pg_catalog.pg_index where indisunique and indrelid = relation) i
        INNER JOIN LATERAL
            (select * from unnest(i.indkey) with ordinality) a(attnum, pos) ON (TRUE)
        WHERE a.pos <= i.indnkeyatts
        GROUP BY 1
    )
    SELECT
      a.attname INTO _segmentby
    FROM
      index_attr i
    INNER JOIN
      pg_attribute a on (a.attnum = i.attnum AND a.attrelid = relation)
    INNER JOIN
      pg_type t ON t.oid = a.atttypid
    LEFT JOIN
      pg_catalog.pg_attrdef ad ON (ad.adrelid = relation AND ad.adnum = a.attnum)
    LEFT JOIN pg_stats s ON s.attname = a.attname
                          AND s.schemaname = _schema_name
                          AND s.tablename = _table_name
                          AND s.inherited = true
    WHERE
      a.attname NOT IN (SELECT column_name FROM _timescaledb_catalog.dimension d WHERE d.hypertable_id = _hypertable_row.id)
      AND s.n_distinct is null
      AND a.attidentity = '' AND (ad.adbin IS NULL OR pg_get_expr(adbin, adrelid) not like 'nextval%')
      AND t.typcategory NOT IN ('D')
    ORDER BY i.pos
    LIMIT 1;

    IF FOUND THEN
            return json_build_object(
            'columns', json_build_array(_segmentby),
            'confidence', 5,
            'message',  'Please make sure '|| _segmentby||' is not a unique column and appropriate for a segment by');
    END IF;


    --are there any indexed columns that are not dimemsions and are not serial/identity?
    with index_attr as (
        SELECT
        a.attnum, min(a.pos) as pos
        FROM
            (select indkey, indnkeyatts from pg_catalog.pg_index where indisunique and indrelid = relation) i
        INNER JOIN LATERAL
            (select * from unnest(i.indkey) with ordinality) a(attnum, pos) ON (TRUE)
        WHERE a.pos <= i.indnkeyatts
        GROUP BY 1
    )
    SELECT
      count(*) INTO STRICT _cnt
    FROM
      index_attr i
    INNER JOIN
      pg_attribute a on (a.attnum = i.attnum AND a.attrelid = relation)
    INNER JOIN
      pg_type t ON t.oid = a.atttypid
    LEFT JOIN
      pg_catalog.pg_attrdef ad ON (ad.adrelid = relation AND ad.adnum = a.attnum)
    WHERE
      a.attname NOT IN (SELECT column_name FROM _timescaledb_catalog.dimension d WHERE d.hypertable_id = _hypertable_row.id)
      AND a.attidentity = '' AND (ad.adbin IS NULL OR pg_get_expr(adbin, adrelid) not like 'nextval%')
      AND t.typcategory NOT IN ('D');

    IF _cnt > 0 THEN
        --there are many potential candidates. We do not have enough information to choose one.
        return json_build_object(
            'columns', json_build_array(),
            'confidence', 0,
            'message',  'Several columns are potential segment by candidates and we do not have enough information to choose one. Please use the segment_by option to explicitly specify the segment_by column');
    ELSE
        --there are no potential candidates. There is a good chance no segment by is the correct choice.
        return json_build_object(
            'columns', json_build_array(),
            'confidence', 5,
            'message',  'You do not have any indexes on columns that can be used for segment_by and thus we are not using segment_by for converting to columnstore. Please make sure you are not missing any indexes');
    END IF;
END
$BODY$ SET search_path TO pg_catalog, pg_temp;

-- This function return a jsonb with the following keys:
-- - clauses: an array of column names and sort order key words that shold be used for order by.
-- - confidence: a number between 0 and 10 (most confident) indicating how sure we are.
-- - message: a message that should be shown to the user to evaluate the result.
CREATE OR REPLACE FUNCTION _timescaledb_functions.get_orderby_defaults(
    relation regclass, segment_by_cols text[]
)
    RETURNS JSONB LANGUAGE PLPGSQL AS
$BODY$
DECLARE
    _table_name NAME;
    _schema_name NAME;
    _hypertable_row _timescaledb_catalog.hypertable;
    _orderby_names NAME[];
    _dimension_names NAME[];
    _first_index_attrs NAME[];
    _orderby_clauses text[];
    _confidence int;
    _is_date_dimension bool;
    _tiebreaker NAME;
    _tiebreaker_rule int;
    _tiebreaker_rows float8;
    _message text;
BEGIN
    SELECT n.nspname, c.relname INTO STRICT _schema_name, _table_name
    FROM pg_class c
    INNER JOIN pg_namespace n ON (n.oid = c.relnamespace)
    WHERE c.oid = relation;

    SELECT * INTO STRICT _hypertable_row FROM _timescaledb_catalog.hypertable h WHERE h.table_name = _table_name AND h.schema_name = _schema_name;

    --start with the unique index columns minus the segment by columns
    with index_attr as (
        SELECT
        a.attnum, min(a.pos) as pos
        FROM
             --is there a better way to pick the right unique index if there are multiple?
            (select indkey, indnkeyatts from pg_catalog.pg_index where indisunique and indrelid = relation limit 1) i
        INNER JOIN LATERAL
            (select * from unnest(i.indkey) with ordinality) a(attnum, pos) ON (TRUE)
        WHERE a.pos <= i.indnkeyatts
        GROUP BY 1
    )
    SELECT
      array_agg(a.attname ORDER BY i.pos) INTO _orderby_names
    FROM
      index_attr i
    INNER JOIN
      pg_attribute a on (a.attnum = i.attnum AND a.attrelid = relation)
    WHERE
      NOT(a.attname::text = ANY (segment_by_cols));

    if _orderby_names is null then
        _orderby_names := array[]::name[];
        _confidence := 5;
    else
        _confidence := 8;
    end if;

    --add dimension colomns to the end. A dimension column like time should probably always be part of the order by.
    SELECT
      array_agg(d.column_name) INTO _dimension_names
    FROM _timescaledb_catalog.dimension d
    WHERE
      d.hypertable_id = _hypertable_row.id
      AND NOT(d.column_name::text = ANY (_orderby_names))
      AND NOT(d.column_name::text = ANY (segment_by_cols));
    _orderby_names := _orderby_names || _dimension_names;

    --add the first attribute of any index
    with index_attr as (
        SELECT
        a.attnum, min(a.pos) as pos
        FROM
            (select indkey, indnkeyatts from pg_catalog.pg_index where indrelid = relation) i
        INNER JOIN LATERAL
            (select * from unnest(i.indkey) with ordinality) a(attnum, pos) ON (TRUE)
        WHERE a.pos = 1
        GROUP BY 1
    )
    SELECT
      array_agg(a.attname ORDER BY i.pos) INTO _first_index_attrs
    FROM
      index_attr i
    INNER JOIN
      pg_attribute a on (a.attnum = i.attnum AND a.attrelid = relation)
    WHERE
          NOT(a.attname::text = ANY (_orderby_names))
      AND NOT(a.attname::text = ANY (segment_by_cols));

    _orderby_names := _orderby_names || _first_index_attrs;

    --A DATE dimension has at most one distinct value per day, so a segment with
    --many rows per day leaves the rows inside a compressed batch in arbitrary
    --order and every other column loses the temporal locality that deltadelta
    --and gorilla rely on. When the leading order by column is an open (time)
    --dimension of type date, look for one extra column to break the tie.
    SELECT EXISTS (
      SELECT 1
      FROM _timescaledb_catalog.dimension d
      WHERE d.hypertable_id = _hypertable_row.id
        AND d.column_name = _orderby_names[1]
        --open (time) dimensions use interval_length, closed ones num_slices
        AND d.interval_length IS NOT NULL
        AND d.column_type = 'date'::regtype
    ) INTO STRICT _is_date_dimension;

    IF _is_date_dimension THEN
        --rule 1: a column of any unique index that is not already used.
        --Unlike the block above this looks at every unique index and also at
        --its INCLUDE columns, since any of them is a deliberate part of a
        --uniqueness definition on this table.
        with index_attr as (
            SELECT
            a.attnum, min(a.pos) as pos
            FROM
                (select indkey from pg_catalog.pg_index where indisunique and indrelid = relation) i
            INNER JOIN LATERAL
                (select * from unnest(i.indkey) with ordinality) a(attnum, pos) ON (TRUE)
            GROUP BY 1
        )
        SELECT
          a.attname INTO _tiebreaker
        FROM
          index_attr i
        INNER JOIN
          pg_attribute a on (a.attnum = i.attnum AND a.attrelid = relation)
        WHERE
              NOT a.attisdropped
          AND NOT(a.attname::text = ANY (_orderby_names))
          AND NOT(a.attname::text = ANY (segment_by_cols))
        ORDER BY i.pos, a.attnum
        LIMIT 1;

        IF _tiebreaker IS NOT NULL THEN
            _tiebreaker_rule := 1;
        END IF;

        --rule 2: a column of a monotonic-looking type whose name looks like a
        --sequence, an identifier or a finer-grained timestamp.
        IF _tiebreaker IS NULL THEN
            SELECT
              a.attname INTO _tiebreaker
            FROM
              pg_attribute a
            INNER JOIN
              (VALUES ('seq', 1), ('id', 2), ('ts', 3), ('time', 4), ('created_at', 5), ('updated_at', 6))
                AS p(pattern, prio) ON (a.attname::text ~* ('(^|_)' || p.pattern || '(_|$)'))
            WHERE
                  a.attrelid = relation
              AND a.attnum > 0
              AND NOT a.attisdropped
              AND a.atttypid IN ('bigint'::regtype, 'int'::regtype, 'timestamptz'::regtype, 'timestamp'::regtype)
              AND NOT(a.attname::text = ANY (_orderby_names))
              AND NOT(a.attname::text = ANY (segment_by_cols))
            ORDER BY (a.attname::text = p.pattern) DESC, p.prio, a.attnum
            LIMIT 1;

            IF _tiebreaker IS NOT NULL THEN
                _tiebreaker_rule := 2;
            END IF;
        END IF;

        --rule 3: when statistics exist, the column with the most distinct
        --values. n_distinct is negative when it is a fraction of the row
        --count, so scale it back to a count before comparing.
        IF _tiebreaker IS NULL THEN
            SELECT
              coalesce(sum(c.reltuples), 0) INTO _tiebreaker_rows
            FROM pg_catalog.pg_inherits inh
            INNER JOIN pg_catalog.pg_class c ON (c.oid = inh.inhrelid)
            WHERE inh.inhparent = relation;

            SELECT
              s.attname INTO _tiebreaker
            FROM
              pg_stats s
            INNER JOIN
              pg_attribute a on (a.attrelid = relation AND a.attname = s.attname
                                 AND a.attnum > 0 AND NOT a.attisdropped)
            WHERE
                  s.schemaname = _schema_name
              AND s.tablename = _table_name
              AND s.inherited = true
              AND NOT(s.attname::text = ANY (_orderby_names))
              AND NOT(s.attname::text = ANY (segment_by_cols))
              AND CASE WHEN s.n_distinct < 0 THEN -s.n_distinct * greatest(_tiebreaker_rows, 1) ELSE s.n_distinct END > 1
            ORDER BY CASE WHEN s.n_distinct < 0 THEN -s.n_distinct * greatest(_tiebreaker_rows, 1) ELSE s.n_distinct END DESC, a.attnum
            LIMIT 1;

            IF _tiebreaker IS NOT NULL THEN
                _tiebreaker_rule := 3;
            END IF;
        END IF;
        --rule 4 is "leave the order by alone" and needs no code
    END IF;

    --add DESC to any dimensions
    SELECT
      coalesce(array_agg(
      CASE WHEN d.column_name IS NULL THEN
        format('%I', a.colname)
      ELSE
        format('%I DESC', a.colname)
      END ORDER BY pos), array[]::text[]) INTO STRICT _orderby_clauses
    FROM unnest(_orderby_names) WITH ORDINALITY as a(colname, pos)
    LEFT JOIN _timescaledb_catalog.dimension d ON (d.column_name = a.colname AND d.hypertable_id = _hypertable_row.id);

    --the tiebreaker follows the direction of the date dimension it refines
    IF _tiebreaker IS NOT NULL THEN
        _orderby_clauses := _orderby_clauses || format('%I DESC', _tiebreaker);

        IF _tiebreaker_rule > 1 THEN
            _confidence := greatest(_confidence - 1, 0);
            _message := format('Column "%s" was appended to the default order by as a tiebreaker for the date dimension "%s". Please make sure it increases within a day, otherwise specify order_by explicitly.', _tiebreaker, _orderby_names[1]);
        END IF;
    END IF;

    IF _message IS NULL THEN
        return json_build_object('clauses', _orderby_clauses, 'confidence', _confidence);
    ELSE
        return json_build_object('clauses', _orderby_clauses, 'confidence', _confidence, 'message', _message);
    END IF;
END
$BODY$ SET search_path TO pg_catalog, pg_temp;
