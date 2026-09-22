/*
 * This file and its contents are licensed under the Apache License 2.0.
 * Please see the included NOTICE for copyright information and
 * LICENSE-APACHE for a copy of the license.
 */
#pragma once

#include <postgres.h>
#include <access/stratnum.h>
#include <nodes/primnodes.h>

#include "export.h"

/*
 * DATE-typed bounds for comparing a DATE column against a TIMESTAMPTZ
 * expression. See date_bounds.c for the semantics.
 */
extern TSDLLEXPORT Expr *ts_make_date_floor_expr(Expr *tstz_expr);
extern TSDLLEXPORT Expr *ts_make_date_ceil_expr(Expr *tstz_expr);
extern TSDLLEXPORT Expr *ts_make_date_is_midnight_expr(Expr *tstz_expr);
extern TSDLLEXPORT Expr *ts_make_date_bound_expr(Expr *tstz_expr, StrategyNumber strategy,
												 bool *exact);
