/*
 * $Id: ODBC.h,v 1.4 1997/07/16 19:26:20 timbo Exp $
 * Copyright (c) 1994,1995,1996,1997  Tim Bunce
 *
 * You may distribute under the terms of either the GNU General Public
 * License or the Artistic License, as specified in the Perl README file.
 */

#include "mysql.h"	/* Get SQL_* defs *before* loading DBIXS.h	*/

#define NEED_DBIXS_VERSION 9

#include <DBIXS.h>	/* from DBI. Load this after mysql.h */

#include "dbdimp.h"

#include <DBDXSI.h>	/* from DBI. Load this after mysql.h */

/* end of ODBC.h */
