/*
 * This file and its contents are licensed under the Apache License 2.0.
 * Please see the included NOTICE for copyright information and
 * LICENSE-APACHE for a copy of the license.
 */
#include <postgres.h>
#include <access/stratnum.h>
#include <catalog/pg_namespace.h>
#include <catalog/pg_type.h>
#include <nodes/makefuncs.h>
#include <nodes/nodeFuncs.h>
#include <utils/fmgroids.h>

#include "planner/date_bounds.h"
#include "utils.h"

/*
 * Comparing a DATE column d against a TIMESTAMPTZ value T.
 *
 * PostgreSQL evaluates "d OP T" as "d::timestamptz OP T", where the cast
 * turns d into the local midnight of that day in the session timezone. The
 * cross-type operators are therefore STABLE and cannot be used for chunk
 * exclusion directly. Since local midnight is strictly increasing in d, every
 * comparison can be rewritten into a same-type DATE comparison against a
 * DATE-typed bound derived from T:
 *
 *   floor(T) = T::date
 *   ceil(T)  = CASE WHEN floor(T)::timestamptz = T THEN floor(T)
 *                   ELSE floor(T) + 1 END
 *
 *   d >  T  <=>  d >  floor(T)
 *   d <= T  <=>  d <= floor(T)
 *   d >= T  <=>  d >= ceil(T)
 *   d <  T  <=>  d <  ceil(T)
 *   d =  T  <=>  d =  floor(T) AND floor(T)::timestamptz = T
 *
 * On DST transition days local midnight may not exist or may be ambiguous.
 * PostgreSQL resolves that inside the date-to-timestamptz cast, so the bounds
 * are built exclusively out of PostgreSQL's own cast functions and evaluate to
 * exactly what the original comparison would have used.
 *
 * The expressions contain only STABLE functions, which estimate_expression_value
 * folds at executor startup. That makes the rewritten clause usable for
 * ChunkAppend startup exclusion and, on compressed chunks, for the same-type
 * vectorized predicates.
 */

static Expr *
make_cast_expr(Expr *arg, Oid source_type, Oid target_type)
{
	Oid cast_oid = ts_get_cast_func(source_type, target_type);

	if (!OidIsValid(cast_oid))
	{
		return NULL;
	}

	return (Expr *) makeFuncExpr(cast_oid,
								 target_type,
								 list_make1(arg),
								 InvalidOid,
								 InvalidOid,
								 COERCE_EXPLICIT_CALL);
}

/*
 * floor(T) = T::date, the local date of T in the session timezone.
 */
Expr *
ts_make_date_floor_expr(Expr *tstz_expr)
{
	if (exprType((Node *) tstz_expr) != TIMESTAMPTZOID)
	{
		return NULL;
	}

	return make_cast_expr(copyObject(tstz_expr), TIMESTAMPTZOID, DATEOID);
}

/*
 * floor(T)::timestamptz = T, true when T is exactly the local midnight of its
 * own day, i.e. when T is the image of a DATE under the date-to-timestamptz
 * cast.
 */
Expr *
ts_make_date_is_midnight_expr(Expr *tstz_expr)
{
	Expr *floor = ts_make_date_floor_expr(tstz_expr);
	Expr *midnight;
	Oid eq_opno;

	if (floor == NULL)
	{
		return NULL;
	}

	midnight = make_cast_expr(floor, DATEOID, TIMESTAMPTZOID);
	eq_opno = ts_get_operator("=", PG_CATALOG_NAMESPACE, TIMESTAMPTZOID, TIMESTAMPTZOID);

	if (midnight == NULL || !OidIsValid(eq_opno))
	{
		return NULL;
	}

	return make_opclause(eq_opno,
						 BOOLOID,
						 false,
						 midnight,
						 copyObject(tstz_expr),
						 InvalidOid,
						 InvalidOid);
}

/*
 * ceil(T), the smallest DATE whose local midnight is at or after T.
 */
Expr *
ts_make_date_ceil_expr(Expr *tstz_expr)
{
	Expr *is_midnight = ts_make_date_is_midnight_expr(tstz_expr);
	Expr *floor = ts_make_date_floor_expr(tstz_expr);
	Expr *floor_plus_one;
	Const *one;
	CaseWhen *when;
	CaseExpr *caseexpr;

	if (is_midnight == NULL || floor == NULL)
	{
		return NULL;
	}

	one = makeConst(INT4OID, -1, InvalidOid, sizeof(int32), Int32GetDatum(1), false, true);
	floor_plus_one = (Expr *) makeFuncExpr(F_DATE_PLI,
										   DATEOID,
										   list_make2(ts_make_date_floor_expr(tstz_expr), one),
										   InvalidOid,
										   InvalidOid,
										   COERCE_EXPLICIT_CALL);

	when = makeNode(CaseWhen);
	when->expr = is_midnight;
	when->result = floor;
	when->location = -1;

	caseexpr = makeNode(CaseExpr);
	caseexpr->casetype = DATEOID;
	caseexpr->casecollid = InvalidOid;
	caseexpr->arg = NULL;
	caseexpr->args = list_make1(when);
	caseexpr->defresult = floor_plus_one;
	caseexpr->location = -1;

	return (Expr *) caseexpr;
}

/*
 * Return the DATE-typed bound B such that "d STRATEGY T" is equivalent to
 * "d STRATEGY B" for a DATE column d, with the strategy seen from the DATE
 * side of the comparison.
 *
 * For BTEqualStrategyNumber only the necessary condition "d = floor(T)" can be
 * expressed as a single bound; *exact is set to false and the caller has to
 * AND in ts_make_date_is_midnight_expr() to get an equivalent clause. For all
 * other supported strategies *exact is set to true.
 *
 * Returns NULL if the strategy is not supported or the expression is not of
 * type TIMESTAMPTZ.
 */
Expr *
ts_make_date_bound_expr(Expr *tstz_expr, StrategyNumber strategy, bool *exact)
{
	if (exprType((Node *) tstz_expr) != TIMESTAMPTZOID)
	{
		return NULL;
	}

	switch (strategy)
	{
		case BTGreaterStrategyNumber:
		case BTLessEqualStrategyNumber:
			if (exact != NULL)
			{
				*exact = true;
			}
			return ts_make_date_floor_expr(tstz_expr);
		case BTGreaterEqualStrategyNumber:
		case BTLessStrategyNumber:
			if (exact != NULL)
			{
				*exact = true;
			}
			return ts_make_date_ceil_expr(tstz_expr);
		case BTEqualStrategyNumber:
			if (exact != NULL)
			{
				*exact = false;
			}
			return ts_make_date_floor_expr(tstz_expr);
		default:
			return NULL;
	}
}
