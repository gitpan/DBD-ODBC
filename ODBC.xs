#include "ODBC.h"

DBISTATE_DECLARE;

MODULE = DBD::ODBC    PACKAGE = DBD::ODBC

INCLUDE: ODBC.xsi

MODULE = DBD::ODBC    PACKAGE = DBD::ODBC::st

void
_tables(dbh, sth, qualifier)
	SV *	dbh
	SV *	sth
	char *	qualifier
	CODE:
	ST(0) = dbd_st_tables(dbh, sth, qualifier, "TABLE") ? &sv_yes : &sv_no;

MODULE = DBD::ODBC    PACKAGE = DBD::ODBC::st

