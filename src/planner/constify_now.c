/*
 * This file and its contents are licensed under the Apache License 2.0.
 * Please see the included NOTICE for copyright information and
 * LICENSE-APACHE for a copy of the license.
 */

#include <postgres.h>
#include <access/xact.h>
#include <catalog/pg_namespace.h>
#include <catalog/pg_type.h>
#include <common/int.h>
#include <datatype/timestamp.h>
#include <nodes/makefuncs.h>
#include <optimizer/optimizer.h>
#include <utils/date.h>
#include <utils/fmgroids.h>
#include <utils/fmgrprotos.h>
#include <utils/lsyscache.h>

#include "cache.h"
#include "dimension.h"
#include "hypertable.h"
#include "hypertable_cache.h"
#include "planner.h"
#include "utils.h"

/*
 * This implements an optimization to allow now() expression to be
 * used during plan time chunk exclusions. Since now() is stable it
 * would not normally be considered for plan time chunk exclusion.
 * To enable this behaviour we convert `column > now()` expressions
 * into `column > const AND column > now()`. Assuming that times
 * always moves forward this is safe even for prepared statements.
 *
 * We consider the following expressions valid for this optimization
 * on a TIMESTAMPTZ dimension:
 * - Var > now()
 * - Var >= now()
 * - Var > now() - Interval
 * - Var > now() + Interval
 * - Var >= now() - Interval
 * - Var >= now() + Interval
 *
 * Interval needs to be Const in those expressions.
 *
 * On a DATE dimension the same shapes are accepted through the cross-type
 * DATE > TIMESTAMPTZ operators, plus the DATE-typed spellings of the
 * current date, again only for lower bounds:
 * - Var > or >= now() [+|- Interval]              (cross-type comparison)
 * - Var > or >= (now() [+|- Interval])::date
 * - Var > or >= CURRENT_DATE [+|- Integer]
 *
 * The DATE constant added for those shapes is derived from the UTC calendar
 * date of the clock value (with the interval or integer offset applied) and
 * does not depend on the session timezone, see constify_date_expr() for the
 * argument why that is safe even when the timezone changes between planning
 * and execution.
 */
static const Dimension *
get_hypertable_dimension(Oid relid, int flags)
{
	Hypertable *ht = ts_planner_get_hypertable(relid, flags);
	if (!ht)
	{
		return NULL;
	}
	return hyperspace_get_open_dimension(ht->space, 0);
}

bool
is_valid_now_func(Node *node)
{
	if (IsA(node, FuncExpr) && castNode(FuncExpr, node)->funcid == F_NOW)
	{
		return true;
	}

	if (IsA(node, SQLValueFunction) &&
		castNode(SQLValueFunction, node)->type == SVFOP_CURRENT_TIMESTAMP)
	{
		return true;
	}

	return false;
}

/*
 * now() or CURRENT_TIMESTAMP, the same instant spelled two ways. DATE
 * dimensions use this predicate; TIMESTAMPTZ dimensions keep using
 * is_valid_now_func() above.
 *
 * Only the spelling without a precision qualifies: CURRENT_TIMESTAMP(n)
 * rounds the clock value to n fractional digits and can therefore be up to
 * half a unit below now(), which would make a constant taken from now() too
 * strict.
 */
static bool
is_clock_func(Node *node)
{
	if (IsA(node, FuncExpr) && castNode(FuncExpr, node)->funcid == F_NOW)
	{
		return true;
	}

	return IsA(node, SQLValueFunction) &&
		   castNode(SQLValueFunction, node)->op == SVFOP_CURRENT_TIMESTAMP;
}

static bool
is_current_date_func(Node *node)
{
	return IsA(node, SQLValueFunction) &&
		   castNode(SQLValueFunction, node)->op == SVFOP_CURRENT_DATE;
}

/*
 * now() or now() +|- Const interval, a TIMESTAMPTZ expression. With
 * accept_current_timestamp the CURRENT_TIMESTAMP spelling of now() is
 * accepted as well.
 */
static bool
is_valid_now_or_offset_expr(Node *node, bool accept_current_timestamp)
{
	bool (*is_now)(Node *) = accept_current_timestamp ? is_clock_func : is_valid_now_func;

	if (is_now(node))
	{
		return true;
	}

	if (!IsA(node, OpExpr))
	{
		return false;
	}

	OpExpr *op_inner = castNode(OpExpr, node);
	if ((op_inner->opfuncid != F_TIMESTAMPTZ_MI_INTERVAL &&
		 op_inner->opfuncid != F_TIMESTAMPTZ_PL_INTERVAL) ||
		!is_now(linitial(op_inner->args)) || !IsA(lsecond(op_inner->args), Const))
	{
		return false;
	}

	/*
	 * The consttype check should not be necessary since the
	 * operators we whitelist above already mandates it.
	 */
	Const *c = lsecond_node(Const, op_inner->args);
	Assert(c->consttype == INTERVALOID);
	if (c->constisnull || c->consttype != INTERVALOID)
	{
		return false;
	}

	return true;
}

/*
 * CURRENT_DATE or CURRENT_DATE +|- Const integer, a DATE expression.
 */
static bool
is_valid_current_date_expr(Node *node)
{
	if (is_current_date_func(node))
	{
		return true;
	}

	if (!IsA(node, OpExpr))
	{
		return false;
	}

	OpExpr *op_inner = castNode(OpExpr, node);
	if ((op_inner->opfuncid != F_DATE_PLI && op_inner->opfuncid != F_DATE_MII) ||
		!is_current_date_func(linitial(op_inner->args)) || !IsA(lsecond(op_inner->args), Const))
	{
		return false;
	}

	Const *c = lsecond_node(Const, op_inner->args);
	Assert(c->consttype == INT4OID);
	if (c->constisnull || c->consttype != INT4OID)
	{
		return false;
	}

	return true;
}

/*
 * (now() [+|- Const interval])::date, a DATE expression.
 */
static bool
is_valid_now_cast_expr(Node *node)
{
	if (!IsA(node, FuncExpr))
	{
		return false;
	}

	FuncExpr *cast = castNode(FuncExpr, node);
	if (cast->funcid != F_DATE_TIMESTAMPTZ || list_length(cast->args) != 1)
	{
		return false;
	}

	return is_valid_now_or_offset_expr(linitial(cast->args), true);
}

static bool
is_valid_now_expr(OpExpr *op, List *rtable)
{
	int flags = CACHE_FLAG_MISSING_OK | CACHE_FLAG_NOCREATE;

	/* Var > or Var >= */
	switch (op->opfuncid)
	{
		case F_TIMESTAMPTZ_GT:
		case F_TIMESTAMPTZ_GE:
		case F_DATE_GT:
		case F_DATE_GE:
		case F_DATE_GT_TIMESTAMPTZ:
		case F_DATE_GE_TIMESTAMPTZ:
			break;
		default:
			return false;
	}

	if (!IsA(linitial(op->args), Var))
	{
		return false;
	}

	/*
	 * Check that the constraint is actually on a partitioning
	 * column. We only check for match on first open dimension
	 * because that will be the time column.
	 */
	Var *var = linitial_node(Var, op->args);
	if (var->varlevelsup != 0)
	{
		return false;
	}
	Assert((int) var->varno <= list_length(rtable));
	RangeTblEntry *rte = list_nth(rtable, var->varno - 1);

	/*
	 * If this query on a view we might have a subquery here
	 * and need to peek into the subquery range table to check
	 * if the constraints are on a hypertable.
	 *
	 * We use a loop to handle multiple levels of subquery nesting,
	 * such as continuous aggregate views which have the structure:
	 * outer query -> UNION subquery -> materialization/raw subqueries.
	 */
	while (rte->rtekind == RTE_SUBQUERY)
	{
		/*
		 * Unfortunately the mechanism used to warm up the
		 * hypertable cache does not apply to hypertables
		 * referenced indirectly eg through VIEWs. So we
		 * have to do the lookup for this hypertable without
		 * CACHE_FLAG_NOCREATE flag.
		 */
		flags = CACHE_FLAG_MISSING_OK;
		TargetEntry *tle = list_nth(rte->subquery->targetList, var->varattno - 1);
		if (!IsA(tle->expr, Var))
		{
			return false;
		}
		var = castNode(Var, tle->expr);
		if (var->varlevelsup != 0)
		{
			return false;
		}
#if PG18_GE
		/* PG18 introduced RTEs for group clauses so
		 * we can use rtable to look up GROUP BY expressions.
		 *
		 * https://github.com/postgres/postgres/commit/247dea89
		 */
		RangeTblEntry *group_rte = list_nth(rte->subquery->rtable, var->varno - 1);
		if (group_rte->rtekind == RTE_GROUP)
		{
			Assert(var->varattno > 0);
			Expr *node = list_nth(group_rte->groupexprs, var->varattno - 1);
			if (!IsA(node, Var))
			{
				return false;
			}
			var = castNode(Var, node);
			Assert(var->varno > 0);
			if (var->varlevelsup != 0)
			{
				return false;
			}
		}
#endif
		rte = list_nth(rte->subquery->rtable, var->varno - 1);
	}

	const Dimension *dim = get_hypertable_dimension(rte->relid, flags);
	if (!dim || dim->column_attno != var->varattno)
	{
		return false;
	}

	Node *rhs = lsecond(op->args);
	switch (dim->fd.column_type)
	{
		case TIMESTAMPTZOID:
			/* Var >|>= now() [+|- Const] */
			if (op->opfuncid != F_TIMESTAMPTZ_GT && op->opfuncid != F_TIMESTAMPTZ_GE)
			{
				return false;
			}
			return is_valid_now_or_offset_expr(rhs, false);
		case DATEOID:
			switch (op->opfuncid)
			{
				case F_DATE_GT_TIMESTAMPTZ:
				case F_DATE_GE_TIMESTAMPTZ:
					/* Var >|>= now() [+|- Const] */
					return is_valid_now_or_offset_expr(rhs, true);
				case F_DATE_GT:
				case F_DATE_GE:
					/* Var >|>= CURRENT_DATE [+|- Const] or (now() [+|- Const])::date */
					return is_valid_current_date_expr(rhs) || is_valid_now_cast_expr(rhs);
				default:
					return false;
			}
		default:
			return false;
	}
}

static Const *
make_now_const()
{
	return makeConst(TIMESTAMPTZOID,
					 -1,
					 InvalidOid,
					 sizeof(TimestampTz),
#ifdef TS_DEBUG
					 ts_get_mock_time_or_current_time(),
#else
					 TimestampTzGetDatum(GetCurrentTransactionStartTimestamp()),
#endif
					 false,
					 FLOAT8PASSBYVAL);
}

/*
 * Turn now() or now() +|- Const interval into a TIMESTAMPTZ Const holding the
 * plan time clock value with the offset applied. Returns NULL if the
 * expression could not be folded to a Const.
 */
static Const *
constify_now_value(PlannerInfo *root, Node *now_expr)
{
	if (is_clock_func(now_expr))
	{
		return make_now_const();
	}

	OpExpr *op_inner = copyObject(castNode(OpExpr, now_expr));
	Const *const_offset = lsecond_node(Const, op_inner->args);
	Assert(const_offset->consttype == INTERVALOID);
	Interval *offset = DatumGetIntervalP(const_offset->constvalue);
	/*
	 * Sanity check that this is a supported expression. We should never
	 * end here if it isn't since this is checked in is_valid_now_expr.
	 */
	Assert(is_clock_func(linitial(op_inner->args)));
	Const *now = make_now_const();
	linitial(op_inner->args) = now;

	/*
	 * If the interval has a day component then the calculation needs
	 * to take into account daylight saving time switches and thereby a
	 * day would not always be exactly 24 hours. We mitigate this by
	 * adding a safety buffer to account for these dst switches when
	 * dealing with intervals with day component. These calculations
	 * will be repeated with exact values during execution.
	 * Since dst switches seem to range between -1 and 2 hours we set
	 * the safety buffer to 4 hours.
	 * When dealing with Intervals with month component timezone changes
	 * can result in multiple day differences in the outcome of these
	 * calculations due to different month lengths. When dealing with
	 * months we add a 7 day safety buffer.
	 * For all these calculations it is fine if we exclude less chunks
	 * than strictly required for the operation, additional exclusion
	 * with exact values will happen in the executor. But under no
	 * circumstances must we exclude too much cause there would be
	 * no way for the executor to get those chunks back.
	 */
	if (offset->day != 0 || offset->month != 0)
	{
		TimestampTz now_value = DatumGetTimestampTz(now->constvalue);
		if (offset->month != 0)
		{
			now_value -= 7 * USECS_PER_DAY;
		}
		if (offset->day != 0)
		{
			now_value -= 4 * USECS_PER_HOUR;
		}

		now->constvalue = TimestampTzGetDatum(now_value);
	}

	/*
	 * Normally estimate_expression_value is not safe to use during planning
	 * since it also evaluates stable expressions. Since we only allow a
	 * very limited subset of expressions for this optimization it is safe
	 * for those expressions we allowed earlier.
	 * estimate_expression_value should always be able to completely constify
	 * the expression due to the restrictions we impose on the expressions
	 * supported.
	 */
	Node *result = estimate_expression_value(root, (Node *) op_inner);
	Assert(IsA(result, Const));
	if (!IsA(result, Const))
	{
		return NULL;
	}

	return castNode(Const, result);
}

/*
 * op will be OpExpr with Var > now() - Expr on a TIMESTAMPTZ dimension.
 * Returns a copy of the expression with the now() call constified.
 */
static OpExpr *
constify_now_expr(PlannerInfo *root, OpExpr *op)
{
	Const *now = constify_now_value(root, lsecond(op->args));

	if (now == NULL)
	{
		return NULL;
	}

	op = copyObject(op);
	lsecond(op->args) = now;
	op->location = PLANNER_LOCATION_MAGIC;
	return op;
}

/*
 * Add days to a DATE at plan time. Returns false instead of raising an
 * error when the input is infinite or the result would be out of range, so
 * that the caller skips the optimization and leaves any error to the
 * execution of the original expression, exactly as without this code.
 */
static bool
date_add_days(DateADT date, int32 days, DateADT *result)
{
	int32 sum;

	if (DATE_NOT_FINITE(date) || pg_add_s32_overflow(date, days, &sum) || !IS_VALID_DATE(sum))
	{
		return false;
	}

	*result = sum;
	return true;
}

/*
 * The UTC calendar date of a TIMESTAMPTZ clock value.
 */
static bool
clock_utc_date(Const *clock, DateADT *utc_date)
{
	if (clock->constisnull || TIMESTAMP_NOT_FINITE(DatumGetTimestampTz(clock->constvalue)))
	{
		return false;
	}

	/*
	 * timestamp_date reads its argument as a timezone-free TIMESTAMP. TIMESTAMP
	 * and TIMESTAMPTZ share the int64 representation, microseconds since the
	 * epoch in UTC, so this yields the UTC date of the instant without touching
	 * the session timezone.
	 */
	*utc_date = DatumGetDateADT(DirectFunctionCall1(timestamp_date, clock->constvalue));

	return !DATE_NOT_FINITE(*utc_date);
}

/*
 * op will be OpExpr with Var > or >= on a DATE dimension, in one of the shapes
 * is_valid_now_expr accepts. Returns a same-type DATE comparison against a
 * constant lower bound, or NULL if no constant can be built.
 *
 * The bound must never be above what the original expression evaluates to at
 * execution time, in any session timezone, because the executor cannot get
 * back a chunk excluded at plan time. Two things move between plan time and
 * execution time: the clock, which only moves forward, and the session
 * timezone, which can be set to anything. The bound is therefore derived from
 * the UTC date of the plan time clock value, using only that every timezone
 * offset is smaller than a day. With T the clock value with the interval
 * applied, F = the UTC date of T and D = any date:
 *
 * - Var >|>= T (cross-type, T = now() [+|- Interval]): PostgreSQL evaluates
 *   this as Var::timestamptz >|>= T, where the cast yields the local midnight
 *   of Var in the session timezone, i.e. midnight UTC of that day shifted by
 *   the timezone offset. For every D < F the local midnight of D is below
 *   D + 1 day at midnight UTC, which is at most F at midnight UTC, which is
 *   at most T. So Var > T and Var >= T both imply Var >= F, and the added
 *   clause is Var >= F for both operators. The interval is applied to the
 *   clock the same way as for TIMESTAMPTZ dimensions, including the safety
 *   buffers for intervals with day or month components.
 * - Var >|>= (T)::date: the cast yields the local date of T, which is within
 *   one day of F in any timezone, so the added clause keeps the operator and
 *   uses F - 1 as bound.
 * - Var >|>= CURRENT_DATE [+|- Integer]: CURRENT_DATE is the local date of
 *   the clock, again within one day of F; the added clause keeps the operator
 *   and uses F - 1 with the integer offset applied.
 *
 * The price of not depending on the session timezone is that the bound can
 * be below the exact value: by one day in UTC (none for Var >= T when T is a
 * midnight), by up to two days in timezones east of UTC, so at most two extra
 * days of chunks stay in the plan. Those are still excluded at executor
 * startup by the original expression.
 */
static OpExpr *
constify_date_expr(PlannerInfo *root, OpExpr *op)
{
	Node *rhs = lsecond(op->args);
	Const *clock;
	DateADT bound;
	int32 offset_days = -1;
	OpExpr *result;

	switch (op->opfuncid)
	{
		case F_DATE_GT_TIMESTAMPTZ:
		case F_DATE_GE_TIMESTAMPTZ:
			/* Var >|>= now() [+|- Const], the bound is F for both operators */
			clock = constify_now_value(root, rhs);
			offset_days = 0;
			break;
		case F_DATE_GT:
		case F_DATE_GE:
			if (IsA(rhs, FuncExpr))
			{
				/* Var >|>= (now() [+|- Const])::date */
				clock = constify_now_value(root, linitial(castNode(FuncExpr, rhs)->args));
			}
			else
			{
				/* Var >|>= CURRENT_DATE [+|- Const] */
				if (IsA(rhs, OpExpr))
				{
					OpExpr *op_inner = castNode(OpExpr, rhs);
					int32 days = DatumGetInt32(lsecond_node(Const, op_inner->args)->constvalue);

					if (op_inner->opfuncid == F_DATE_PLI)
					{
						if (pg_add_s32_overflow(offset_days, days, &offset_days))
						{
							return NULL;
						}
					}
					else if (pg_sub_s32_overflow(offset_days, days, &offset_days))
					{
						return NULL;
					}
				}
				clock = make_now_const();
			}
			break;
		default:
			return NULL;
	}

	if (clock == NULL || !clock_utc_date(clock, &bound) ||
		!date_add_days(bound, offset_days, &bound))
	{
		return NULL;
	}

	Const *bound_const =
		makeConst(DATEOID, -1, InvalidOid, sizeof(DateADT), DateADTGetDatum(bound), false, true);

	if (op->opfuncid == F_DATE_GT || op->opfuncid == F_DATE_GE)
	{
		/* already a DATE vs DATE comparison, keep the operator */
		result = copyObject(op);
		lsecond(result->args) = bound_const;
	}
	else
	{
		/* cross-type comparison, the added clause is Var >= F */
		Oid opno = ts_get_operator(">=", PG_CATALOG_NAMESPACE, DATEOID, DATEOID);

		if (!OidIsValid(opno))
		{
			return NULL;
		}

		result = (OpExpr *) make_opclause(opno,
										  BOOLOID,
										  false,
										  copyObject(linitial(op->args)),
										  (Expr *) bound_const,
										  InvalidOid,
										  InvalidOid);
		result->opfuncid = get_opcode(opno);
	}

	result->location = PLANNER_LOCATION_MAGIC;
	return result;
}

/*
 * Returns the constified copy of an expression accepted by is_valid_now_expr,
 * marked with PLANNER_LOCATION_MAGIC so it is removed again after chunk
 * exclusion, or NULL if no constant could be built.
 */
static OpExpr *
constify_expr(PlannerInfo *root, OpExpr *op)
{
	switch (op->opfuncid)
	{
		case F_TIMESTAMPTZ_GT:
		case F_TIMESTAMPTZ_GE:
			return constify_now_expr(root, op);
		default:
			return constify_date_expr(root, op);
	}
}

Node *
ts_constify_now(PlannerInfo *root, List *rtable, Node *node)
{
	Assert(node);

	switch (nodeTag(node))
	{
		case T_OpExpr:
			if (is_valid_now_expr(castNode(OpExpr, node), rtable))
			{
				OpExpr *constified = constify_expr(root, castNode(OpExpr, node));

				if (constified != NULL)
				{
					List *args = list_make2(copyObject(node), constified);
					return (Node *) makeBoolExpr(AND_EXPR, args, -1);
				}
			}
			break;
		case T_BoolExpr:
		{
			List *additions = NIL;
			ListCell *lc;
			BoolExpr *be = castNode(BoolExpr, node);

			/* We only look for top-level AND */
			if (be->boolop != AND_EXPR)
			{
				return node;
			}

			foreach (lc, be->args)
			{
				additions = lappend(additions, ts_constify_now(root, rtable, (Node *) lfirst(lc)));
			}

			if (additions)
			{
				be->args = additions;
			}

			break;
		}
		default:
			break;
	}

	return node;
}
