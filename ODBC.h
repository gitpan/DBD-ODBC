/*
 * $Id: ODBC.h,v 1.6 1998/07/01 23:42:24 timbo Exp $
 * Copyright (c) 1994,1995,1996,1997  Tim Bunce
 *
 * You may distribute under the terms of either the GNU General Public
 * License or the Artistic License, as specified in the Perl README file.
 */

#include "mysql.h"	/* Get SQL_* defs *before* loading DBIXS.h	*/

#define NEED_DBIXS_VERSION 9

#include <DBIXS.h>	/* from DBI. Load this after mysql.h */

#include "dbdimp.h"

#include <dbd_xsh.h>	/* from DBI. Load this after mysql.h */

SV      *odbc_get_info _((SV *dbh, int ftype));
int      odbc_get_type_info _((SV *dbh, SV *sth, int ftype));
SV	*odbc_col_attributes _((SV *sth, int colno, int desctype));
int	 odbc_describe_col _((SV *sth, int colno,
	    SQLCHAR *ColumnName, SQLSMALLINT BufferLength, SQLSMALLINT *NameLength,
	    SQLSMALLINT *DataType, SQLUINTEGER *ColumnSize,
	    SQLSMALLINT *DecimalDigits, SQLSMALLINT *Nullable));
int	 odbc_db_columns _((SV *dbh, SV *sth,
	    char *catalog, char *schema, char *table, char *column));

/* end of ODBC.h */
