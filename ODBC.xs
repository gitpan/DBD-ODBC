#include "ODBC.h"

DBISTATE_DECLARE;

MODULE = DBD::ODBC    PACKAGE = DBD::ODBC

INCLUDE: ODBC.xsi

MODULE = DBD::ODBC    PACKAGE = DBD::ODBC::st

void 
_ColAttributes(sth, colno, ftype)
	SV *	sth
	int		colno
	int		ftype
	CODE:
	ST(0) = odbc_col_attributes(sth, colno, ftype);

void
_tables(dbh, sth, qualifier)
	SV *	dbh
	SV *	sth
	char *	qualifier
	CODE:
	ST(0) = dbd_st_tables(dbh, sth, qualifier, "TABLE") ? &sv_yes : &sv_no;

void
DescribeCol(sth, colno)
	SV *sth
	int colno

	PPCODE:

	SQLCHAR ColumnName[SQL_MAX_COLUMN_NAME_LEN];
	SQLSMALLINT NameLength;
	SQLSMALLINT DataType;
	SQLUINTEGER ColumnSize;
	SQLSMALLINT DecimalDigits;
	SQLSMALLINT Nullable;
	int rc;

	rc = odbc_describe_col(sth, colno, ColumnName, sizeof(ColumnName), &NameLength,
			&DataType, &ColumnSize, &DecimalDigits, &Nullable);
	if (rc) {
		XPUSHs(newSVpv(ColumnName, 0));
		XPUSHs(newSViv(DataType));
		XPUSHs(newSViv(ColumnSize));
		XPUSHs(newSViv(DecimalDigits));
		XPUSHs(newSViv(Nullable));
	}

# ------------------------------------------------------------
# database level interface
# ------------------------------------------------------------
MODULE = DBD::ODBC    PACKAGE = DBD::ODBC::db

void
_columns(dbh, sth, catalog, schema, table, column)
	SV *	dbh
	SV *	sth
	char *	catalog
	char *	schema
	char *	table
	char *	column
	CODE:
	ST(0) = odbc_db_columns(dbh, sth, catalog, schema, table, column) ? &sv_yes : &sv_no;

void 
_GetInfo(dbh, ftype)
	SV *	dbh
	int		ftype
	CODE:
	ST(0) = odbc_get_info(dbh, ftype);

void
_GetTypeInfo(dbh, sth, ftype)
	SV *	dbh
	SV *	sth
	int		ftype
	CODE:
	ST(0) = odbc_get_type_info(dbh, sth, ftype) ? &sv_yes : &sv_no;

#
# Corresponds to ODBC 2.0.  3.0's SQL_API_ODBC3_ALL_FUNCTIONS will break this
# scheme
void
GetFunctions(dbh, func)
	SV *	dbh
	int		func
	PPCODE:
	UWORD pfExists[100];
	RETCODE rc;
	int i;
	D_imp_dbh(dbh);
	rc = SQLGetFunctions(imp_dbh->hdbc, func, pfExists);
	if (SQL_ok(rc)) {
		if (func == SQL_API_ALL_FUNCTIONS) {
			for (i = 0; (i < sizeof(pfExists)/sizeof(pfExists[0])); i++) {
				XPUSHs(pfExists[i] ? &sv_yes : &sv_no);
			}
		} else {
			XPUSHs(pfExists[0] ? &sv_yes : &sv_no);
		}
	}

MODULE = DBD::ODBC    PACKAGE = DBD::ODBC::db

