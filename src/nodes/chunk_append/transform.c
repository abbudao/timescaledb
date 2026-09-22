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
#include <optimizer/optimizer.h>
#include <utils/lsyscache.h>
#include <utils/typcache.h>

#include "nodes/chunk_append/transform.h"
#include "planner/date_bounds.h"
#include "utils.h"

#define DATATYPE_PAIR(left, right, type1, type2)                                                   \
	(((left) == (type1) && (right) == (type2)) || ((left) == (type2) && (right) == (type1)))

/*
 * Strategy of the commuted comparison, i.e. of "b OP a" given the strategy
 * of "a OP b".
 */
static StrategyNumber
commute_strategy(StrategyNumber strategy)
{
	switch (strategy)
	{
		case BTLessStrategyNumber:
			return BTGreaterStrategyNumber;
		case BTLessEqualStrategyNumber:
			return BTGreaterEqualStrategyNumber;
		case BTGreaterEqualStrategyNumber:
			return BTLessEqualStrategyNumber;
		case BTGreaterStrategyNumber:
			return BTLessStrategyNumber;
		default:
			return strategy;
	}
}

/*
 * Build "date_arg OP bound" (or "bound OP date_arg" when the Var was on the
 * right) with the DATE-versus-DATE operator named opname. The operator name
 * is given as seen from the DATE side; it is commuted when the bound goes to
 * the left. Returns NULL if the operator is not found.
 */
static Expr *
make_date_comparison(const char *opname_from_date_side, Expr *date_arg, Expr *bound,
					 bool date_on_left)
{
	const char *opname = opname_from_date_side;
	Oid opno;

	if (!date_on_left)
	{
		if (strcmp(opname, ">=") == 0)
		{
			opname = "<=";
		}
		else if (strcmp(opname, "<=") == 0)
		{
			opname = ">=";
		}
		else if (strcmp(opname, ">") == 0)
		{
			opname = "<";
		}
		else if (strcmp(opname, "<") == 0)
		{
			opname = ">";
		}
	}

	opno = ts_get_operator(opname, PG_CATALOG_NAMESPACE, DATEOID, DATEOID);
	if (!OidIsValid(opno))
	{
		return NULL;
	}

	if (date_on_left)
	{
		return make_opclause(opno,
							 BOOLOID,
							 false,
							 copyObject(date_arg),
							 bound,
							 InvalidOid,
							 InvalidOid);
	}

	return make_opclause(opno, BOOLOID, false, bound, copyObject(date_arg), InvalidOid, InvalidOid);
}

/*
 * DATE OP TIMESTAMPTZ (or TIMESTAMPTZ OP DATE) with the Var on the DATE side.
 *
 * Casting the TIMESTAMPTZ side down to DATE rounds it down to local midnight,
 * which keeps "date > value" and "date <= value" equivalent. For ">=" and "<"
 * the bound has to be rounded up instead. "d = T" holds exactly when the
 * local midnight of d is T, which is the range "d >= ceil(T) AND d <= floor(T)":
 * one day wide when T is a local midnight and empty otherwise. The bounds are
 * built by planner/date_bounds.c out of PostgreSQL's own cast functions, so
 * DST resolution is identical to the original comparison by construction.
 *
 * Every rewrite is exactly equivalent to the original clause, which the
 * vectorized qual path of ColumnarScan relies on: there the rewritten clause
 * replaces the executed filter. The original argument order is preserved so
 * the TIMESTAMPTZ side is replaced in place.
 */
static Expr *
transform_date_timestamptz_comparison(OpExpr *op, bool date_on_left)
{
	TypeCacheEntry *tce = lookup_type_cache(TIMESTAMPTZOID, TYPECACHE_BTREE_OPFAMILY);
	StrategyNumber strategy = get_op_opfamily_strategy(op->opno, tce->btree_opf);
	Expr *date_arg = date_on_left ? linitial(op->args) : lsecond(op->args);
	Expr *tstz_arg = date_on_left ? lsecond(op->args) : linitial(op->args);
	Expr *bound;
	Expr *result;
	bool exact = false;

	/* express the strategy as seen from the DATE side */
	if (!date_on_left)
	{
		strategy = commute_strategy(strategy);
	}

	if (strategy == BTEqualStrategyNumber)
	{
		Expr *ceil = ts_make_date_ceil_expr(tstz_arg);
		Expr *floor = ts_make_date_floor_expr(tstz_arg);
		Expr *lower;
		Expr *upper;

		if (ceil == NULL || floor == NULL)
		{
			return (Expr *) op;
		}

		lower = make_date_comparison(">=", date_arg, ceil, date_on_left);
		upper = make_date_comparison("<=", date_arg, floor, date_on_left);
		if (lower == NULL || upper == NULL)
		{
			return (Expr *) op;
		}

		return make_andclause(list_make2(lower, upper));
	}

	bound = ts_make_date_bound_expr(tstz_arg, strategy, &exact);
	if (bound == NULL || !exact)
	{
		return (Expr *) op;
	}

	/* same operator name on both sides of the rewrite, so no commuting here */
	result = make_date_comparison(get_opname(op->opno), date_arg, bound, true);
	if (result == NULL)
	{
		return (Expr *) op;
	}

	if (!date_on_left)
	{
		/* restore the original argument order: bound OP date */
		OpExpr *opexpr = castNode(OpExpr, result);

		opexpr->args = list_make2(lsecond(opexpr->args), linitial(opexpr->args));
	}

	return result;
}

/*
 * Cross datatype comparisons between DATE/TIMESTAMP/TIMESTAMPTZ
 * are not immutable which prevents their usage for chunk exclusion.
 * Unfortunately estimate_expression_value will not estimate those
 * expressions which makes them unusable for execution time chunk
 * exclusion with constraint aware append.
 * To circumvent this we inject casts and use an operator
 * with the same datatype on both sides when constifying
 * restrictinfo. This allows estimate_expression_value
 * to evaluate those expressions and makes them accessible for
 * execution time chunk exclusion.
 *
 * The following transformations are done:
 * TIMESTAMP OP TIMESTAMPTZ => TIMESTAMP OP (TIMESTAMPTZ::TIMESTAMP)
 * TIMESTAMPTZ OP DATE => TIMESTAMPTZ OP (DATE::TIMESTAMPTZ)
 * DATE OP TIMESTAMPTZ => DATE OP <DATE bound>, see
 * transform_date_timestamptz_comparison() and planner/date_bounds.c
 *
 * No transformation is required for TIMESTAMP OP DATE because
 * those operators are marked immutable.
 */
Expr *
ts_transform_cross_datatype_comparison(Expr *clause)
{
	if (!IsA(clause, OpExpr) || list_length(castNode(OpExpr, clause)->args) != 2)
	{
		return clause;
	}

	OpExpr *op = castNode(OpExpr, clause);
	Oid left_type = exprType(linitial(op->args));
	Oid right_type = exprType(lsecond(op->args));

	/*
	 * Postgres doesn't allow non-bool or set returning functions in the WHERE
	 * clause.
	 */
	Assert(op->opresulttype == BOOLOID && !op->opretset);

	if (!IsA(linitial(op->args), Var) && !IsA(lsecond(op->args), Var))
	{
		return clause;
	}

	if (DATATYPE_PAIR(left_type, right_type, TIMESTAMPOID, TIMESTAMPTZOID) ||
		DATATYPE_PAIR(left_type, right_type, TIMESTAMPTZOID, DATEOID))
	{
		char *opname = get_opname(op->opno);
		Oid source_type, target_type, opno, cast_oid;

		/*
		 * if Var is on left side we put cast on right side otherwise
		 * it will be left
		 */
		if (IsA(linitial(op->args), Var))
		{
			source_type = right_type;
			target_type = left_type;
		}
		else
		{
			source_type = left_type;
			target_type = right_type;
		}

		/*
		 * The DATE side is the Var: a plain cast is not equivalent for every
		 * operator, so the bound is chosen per operator.
		 */
		if (target_type == DATEOID)
		{
			return transform_date_timestamptz_comparison(op, IsA(linitial(op->args), Var));
		}

		opno = ts_get_operator(opname, PG_CATALOG_NAMESPACE, target_type, target_type);
		cast_oid = ts_get_cast_func(source_type, target_type);

		if (OidIsValid(opno) && OidIsValid(cast_oid))
		{
			Expr *left = copyObject(linitial(op->args));
			Expr *right = copyObject(lsecond(op->args));

			if (source_type == left_type)
			{
				left = (Expr *) makeFuncExpr(cast_oid,
											 target_type,
											 list_make1(left),
											 InvalidOid,
											 InvalidOid,
											 0);
			}
			else
			{
				right = (Expr *) makeFuncExpr(cast_oid,
											  target_type,
											  list_make1(right),
											  InvalidOid,
											  InvalidOid,
											  0);
			}

			return make_opclause(opno, BOOLOID, false, left, right, InvalidOid, InvalidOid);
		}
	}
	return clause;
}
