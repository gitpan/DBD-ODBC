/* $Id: dbdimp.c,v 1.5 1997/07/18 16:28:06 timbo Exp $
 * 
 * portions Copyright (c) 1994,1995,1996,1997  Tim Bunce
 * portions Copyright (c) 1997 Thomas K. Wenrich
 * portions Copyright (c) 1997 Jeff Urlwin
 *
 * You may distribute under the terms of either the GNU General Public
 * License or the Artistic License, as specified in the Perl README file.
 *
 */

#include "ODBC.h"

static const char *S_SqlTypeToString (SWORD sqltype);
static const char *S_SqlCTypeToString (SWORD sqltype);
static const char *cSqlTables = "SQLTables(%s)";

static void odbc_error _((SV *h, RETCODE badrc, char *what));

DBISTATE_DECLARE;

void
dbd_init(dbistate)
    dbistate_t *dbistate;
{
    DBIS = dbistate;
}

void
dbd_db_destroy(dbh, imp_dbh)
    SV *dbh;
    imp_dbh_t *imp_dbh;
{
    if (DBIc_ACTIVE(imp_dbh))
	dbd_db_disconnect(dbh, imp_dbh);
    /* Nothing in imp_dbh to be freed	*/

    DBIc_IMPSET_off(imp_dbh);
}

/*------------------------------------------------------------
  connecting to a data source.
  Allocates henv and hdbc.
------------------------------------------------------------*/
int
dbd_db_login(dbh, imp_dbh, dbname, uid, pwd)
    SV *dbh;
    imp_dbh_t *imp_dbh;
    char *dbname;
    char *uid;
    char *pwd;
{
    D_imp_drh_from_dbh;
    int ret;

    RETCODE rc;

    if (!imp_drh->connects) {
	rc = SQLAllocEnv(&imp_drh->henv);
	odbc_error(dbh, rc, "db_login/SQLAllocEnv");
	if (!SQL_ok(rc))
	    return 0;
    }

    rc = SQLAllocConnect(imp_drh->henv, &imp_dbh->hdbc);
    odbc_error(dbh, rc, "db_login/SQLAllocConnect");
    if (!SQL_ok(rc)) {
	if (imp_drh->connects == 0) {
	    SQLFreeEnv(imp_drh->henv);
	    imp_drh->henv = SQL_NULL_HENV;
	}
	return 0;
    }

    if (dbis->debug >= 2)
	fprintf(DBILOGFP, "connect '%s', '%s', '%s'", dbname, uid, pwd);

    rc = SQLConnect(imp_dbh->hdbc,
		    dbname, strlen(dbname),
		    uid, strlen(uid),
		    pwd, strlen(pwd));
    odbc_error(dbh, rc, "db_login/SQLConnect");
    if (!SQL_ok(rc)) {
	SQLFreeConnect(imp_dbh->hdbc);
	if (imp_drh->connects == 0) {
	    SQLFreeEnv(imp_drh->henv);
	    imp_drh->henv = SQL_NULL_HENV;
	}
	return 0;
    }
    imp_dbh->henv = imp_drh->henv;

    /* DBI spec requires AutoCommit on */
    rc = SQLSetConnectOption(imp_dbh->hdbc,
                   SQL_AUTOCOMMIT, SQL_AUTOCOMMIT_ON);
    if (!SQL_ok(rc)) {
	odbc_error(dbh, rc, "dbd_db_login/SQLSetConnectOption");
	SQLFreeConnect(imp_dbh->hdbc);
	if (imp_drh->connects == 0) {
	    SQLFreeEnv(imp_drh->henv);
	    imp_drh->henv = SQL_NULL_HENV;
	}
	return 0;
    }
    DBIc_set(imp_dbh,DBIcf_AutoCommit, 1);

    imp_drh->connects++;
    DBIc_IMPSET_on(imp_dbh);	/* imp_dbh set up now			*/
    DBIc_ACTIVE_on(imp_dbh);	/* call disconnect before freeing	*/
    return 1;
}


int
dbd_db_disconnect(dbh, imp_dbh)
    SV *dbh;
    imp_dbh_t *imp_dbh;
{
    RETCODE rc;
    D_imp_drh_from_dbh;

    /* We assume that disconnect will always work	*/
    /* since most errors imply already disconnected.	*/
    DBIc_ACTIVE_off(imp_dbh);

    rc = SQLDisconnect(imp_dbh->hdbc);
    if (!SQL_ok(rc)) {
	odbc_error(dbh, rc, "db_disconnect/SQLDisconnect");
	return 0;	/* XXX */
    }

    SQLFreeConnect(imp_dbh->hdbc);
    imp_dbh->hdbc = SQL_NULL_HDBC;
    imp_drh->connects--;
    if (imp_drh->connects == 0) {
	SQLFreeEnv(imp_drh->henv);
    }
    /* We don't free imp_dbh since a reference still exists	*/
    /* The DESTROY method is the only one to 'free' memory.	*/
    /* Note that statement objects may still exists for this dbh!	*/

    return 1;
}


int
dbd_db_commit(dbh, imp_dbh)
    SV *dbh;
    imp_dbh_t *imp_dbh;
{
    RETCODE rc;

    rc = SQLTransact(imp_dbh->henv, imp_dbh->hdbc, SQL_COMMIT);
    if (!SQL_ok(rc)) {
	odbc_error(dbh, rc, "db_commit/SQLTransact");
	return 0;
    }
    return 1;
}

int
dbd_db_rollback(dbh, imp_dbh)
    SV *dbh;
    imp_dbh_t *imp_dbh;
{
    RETCODE rc;

    rc = SQLTransact(imp_dbh->henv, imp_dbh->hdbc, SQL_ROLLBACK);
    if (!SQL_ok(rc)) {
	odbc_error(dbh, rc, "db_rollback/SQLTransact");
	return 0;
    }
    return 1;
}


/*------------------------------------------------------------
  replacement for ora_error.
  empties entire ODBC error queue.
------------------------------------------------------------*/
static void
odbc_error(h, badrc, what)
    SV *h;
    RETCODE badrc;
    char *what;
{
    D_imp_xxh(h);

    struct imp_dbh_st *imp_dbh = NULL;
    struct imp_sth_st *imp_sth = NULL;
    HENV henv = SQL_NULL_HENV;
    HDBC hdbc = SQL_NULL_HDBC;
    HSTMT hstmt = SQL_NULL_HSTMT;
    SV *errstr;
    int i;

    if (badrc == SQL_SUCCESS && dbis->debug<4)	/* nothing to do */
	return;

    switch(DBIc_TYPE(imp_xxh)) {
    case DBIt_ST:
	imp_sth = (struct imp_sth_st *)(imp_xxh);
	imp_dbh = (struct imp_dbh_st *)(DBIc_PARENT_COM(imp_sth));
	hstmt = imp_sth->hstmt;
	break;
    case DBIt_DB:
	imp_dbh = (struct imp_dbh_st *)(imp_xxh);
	break;
    default:
	croak("panic odbc_error on bad handle type");
    }
    hdbc = imp_dbh->hdbc;
    henv = imp_dbh->henv;

    errstr = DBIc_ERRSTR(imp_xxh);
    sv_setpvn(errstr, "", 0);
    sv_setiv(DBIc_ERR(imp_xxh), (IV)badrc);
    /* sqlstate isn't set for SQL_NO_DATA returns  */
    sv_setpvn(DBIc_STATE(imp_xxh), "00000", 5);
    
    while(henv != SQL_NULL_HENV) {
	UCHAR sqlstate[10];
	UCHAR ErrorMsg[SQL_MAX_MESSAGE_LENGTH*2];
	SWORD ErrorMsgLen;
	SDWORD NativeError;
	RETCODE rc = 0;

	if (dbis->debug >= 3)
	    fprintf(DBILOGFP, "odbc_error: badrc=%d rc=%d i=%d s/d/e: %d/%d/%d\n", 
	       badrc, rc, i, hstmt,hdbc,henv);

	while( (rc=SQLError(henv, hdbc, hstmt,
			  sqlstate, &NativeError,
			  ErrorMsg, sizeof(ErrorMsg)-1, &ErrorMsgLen
		)) == SQL_SUCCESS || rc == SQL_SUCCESS_WITH_INFO
	) {
	    sv_setpvn(DBIc_STATE(imp_xxh), sqlstate, 5);
	    if (SvCUR(errstr) > 0)
		sv_catpv(errstr, "\n");
	    sv_catpvn(errstr, ErrorMsg, ErrorMsgLen);
	    sv_catpv(errstr, " (SQL-");
	    sv_catpv(errstr, sqlstate);
	    sv_catpv(errstr, ")");
	    if (dbis->debug >= 3)
		fprintf(DBILOGFP, 
		    "odbc_error: SQL-%s (native %d): %s\n",
			sqlstate, NativeError, SvPVX(errstr));
	}

	/* climb up the tree each time round the loop		*/
	if      (hstmt != SQL_NULL_HSTMT) hstmt = SQL_NULL_HSTMT;
	else if (hdbc  != SQL_NULL_HDBC)  hdbc  = SQL_NULL_HDBC;
	else henv = SQL_NULL_HENV;	/* done the top		*/
    }

    if (badrc != SQL_SUCCESS) {
	if (what) {
	    char buf[10];
	    sprintf(buf, " err=%d", badrc);
	    sv_catpv(errstr, "(DBD: ");
	    sv_catpv(errstr, what);
	    sv_catpv(errstr, buf);
	    sv_catpv(errstr, ")");
	}
	DBIh_EVENT2(h, ERROR_event, DBIc_ERR(imp_xxh), errstr);
	if (dbis->debug >= 2)
	    fprintf(DBILOGFP, "%s error %d recorded: %s\n",
		    what, badrc, SvPV(errstr,na));
    }
}


/*-------------------------------------------------------------------------
  dbd_preparse: 
     - scan for placeholders (? and :xx style) and convert them to ?.
     - builds translation table to convert positional parameters of the 
       execute() call to :nn type placeholders.
  We need two data structures to translate this stuff:
     - a hash to convert positional parameters to placeholders
     - an array, representing the actual '?' query parameters.
     %param = (name1=>plh1, name2=>plh2, ..., name_n=>plh_n)   #
     @qm_param = (\$param{'name1'}, \$param{'name2'}, ...) 
-------------------------------------------------------------------------*/
void
dbd_preparse(imp_sth, statement)
    imp_sth_t *imp_sth;
    char *statement;
{
    bool in_literal = FALSE;
    char *src, *start, *dest;
    phs_t phs_tpl, *phs;
    SV *phs_sv;
    int idx=0, style=0, laststyle=0;
    int param = 0;
    STRLEN namelen;
    char name[256];
    SV **svpp;
    char ch;

    /* allocate room for copy of statement with spare capacity	*/
    /* for editing '?' or ':1' into ':p1' so we can use obndrv.	*/
    imp_sth->statement = (char*)safemalloc(strlen(statement)*2);

    /* initialize phs ready to be cloned per placeholder	*/
    memset(&phs_tpl, 0, sizeof(phs_tpl));
    phs_tpl.ftype = 1;	/* VARCHAR2 */
    phs_tpl.sv = &sv_undef;

    src  = statement;
    dest = imp_sth->statement;
    while(*src) {
	if (*src == '\'')
	    in_literal = ~in_literal;
	if ((*src != ':' && *src != '?') || in_literal) {
	    *dest++ = *src++;
	    continue;
	}
	start = dest;			/* save name inc colon	*/ 
	ch = *src++;
	if (ch == '?') {                /* X/Open standard	*/ 
	    idx++;
	    sprintf(name, "%d", idx);
	    *dest++ = ch;
	    style = 3;
	}
	else if (isDIGIT(*src)) {       /* ':1'		*/
	    char *p = name;
	    *dest++ = '?';
	    idx = atoi(src);
	    if (idx <= 0)
		croak("Placeholder :%d must be a positive number", idx);
	    while(isDIGIT(*src))
		*p++ = *src++;
	    *p = 0;
	    style = 1;
	} 
	else if (isALNUM(*src)) {       /* ':foo'	*/
	    char *p = name;
	    *dest++ = '?';

	    while(isALNUM(*src))	/* includes '_'	*/
		*p++ = *src++;
	    *p = 0;
	    style = 2;
	} 
	else {			/* perhaps ':=' PL/SQL construct */
	    *dest++ = ch;
	    continue;
	}
	*dest = '\0';			/* handy for debugging	*/
	if (laststyle && style != laststyle)
	    croak("Can't mix placeholder styles (%d/%d)",style,laststyle);
	laststyle = style;

	if (imp_sth->all_params_hv == NULL)
	    imp_sth->all_params_hv = newHV();
	namelen = strlen(name);

	svpp = hv_fetch(imp_sth->all_params_hv, name, namelen, 0);
	if (svpp == NULL) {
	    /* create SV holding the placeholder */
	    phs_sv = newSVpv((char*)&phs_tpl, sizeof(phs_tpl)+namelen+1);
	    phs = (phs_t*)SvPVX(phs_sv);
	    strcpy(phs->name, name);
	    phs->idx = idx;

	    /* store placeholder to all_params_hv */
	    svpp = hv_store(imp_sth->all_params_hv, name, namelen, phs_sv, 0);
	}
    }
    *dest = '\0';
    if (imp_sth->all_params_hv) {
	DBIc_NUM_PARAMS(imp_sth) = (int)HvKEYS(imp_sth->all_params_hv);
	if (dbis->debug >= 2)
	    fprintf(DBILOGFP, "    dbd_preparse scanned %d distinct placeholders\n",
		(int)DBIc_NUM_PARAMS(imp_sth));
    }
}


int
dbd_st_tables(dbh, sth, qualifier, table_type)
    SV *dbh;
    SV *sth;
    char *qualifier;
    char *table_type;
{
    D_imp_dbh(dbh);
    D_imp_sth(sth);
    RETCODE rc;
    SV **svp;
    char cname[128];					/* cursorname */

    imp_sth->done_desc = 0;
    rc = SQLAllocStmt(imp_dbh->hdbc, &imp_sth->hstmt);
    if (rc != SQL_SUCCESS) {
	odbc_error(sth, rc, "st_tables/SQLAllocStmt");
	return 0;
    }

    /* just for sanity, later.  Any internals that may rely on this (including */
    /* debugging) will have valid data */
    imp_sth->statement = (char *)safemalloc(strlen(cSqlTables)+strlen(qualifier)+1);
    sprintf(imp_sth->statement, cSqlTables, qualifier);

    rc = SQLTables(imp_sth->hstmt,
	   0, SQL_NTS,			/* qualifier */
	   0, SQL_NTS,			/* schema/user */
	   0, SQL_NTS,			/* table name */
	   table_type, SQL_NTS	/* type (view, table, etc) */
    );
    
    odbc_error(sth, rc, "st_tables/SQLTables");
    if (!SQL_ok(rc)) {
	SQLFreeStmt(imp_sth->hstmt, SQL_DROP);
	imp_sth->hstmt = SQL_NULL_HSTMT;
	return 0;
    }

	/* XXX Way too much duplicated code here */

    if (dbis->debug >= 2)
	fprintf(DBILOGFP, "    dbd_st_tables sql f%d\n\t%s\n",
			imp_sth->hstmt, imp_sth->statement);
    
    /* init sth pointers */
    imp_sth->henv = imp_dbh->henv;
    imp_sth->hdbc = imp_dbh->hdbc;
    imp_sth->fbh = NULL;
    imp_sth->ColNames = NULL;
    imp_sth->RowBuffer = NULL;
    imp_sth->RowCount = -1;
    imp_sth->eod = -1;

    if (!dbd_describe(sth, imp_sth))
    {
	    SQLFreeStmt(imp_sth->hstmt, SQL_DROP);
	    imp_sth->hstmt = SQL_NULL_HSTMT;
	    return 0; /* dbd_describe already called ora_error()	*/
    }

    if (dbd_describe(sth, imp_sth) <= 0)
	return 0;

    DBIc_IMPSET_on(imp_sth);

    imp_sth->RowCount = -1;
    rc = SQLRowCount(imp_sth->hstmt, &imp_sth->RowCount);
    odbc_error(sth, rc, "st_execute/SQLRowCount");
    if (rc != SQL_SUCCESS) {
	return -1;
    }

    DBIc_ACTIVE_on(imp_sth); /* XXX should only set for select ?	*/
    imp_sth->eod = SQL_SUCCESS;
    return 1;
}


int
dbd_st_prepare(sth, imp_sth, statement, attribs)
    SV *sth;
    imp_sth_t *imp_sth;
    char *statement;
    SV *attribs;
{
    D_imp_dbh_from_sth;
    RETCODE rc;
    SV **svp;
    char cname[128];		/* cursorname */

    imp_sth->done_desc = 0;

    rc = SQLAllocStmt(imp_dbh->hdbc, &imp_sth->hstmt);
    if (!SQL_ok(rc)) {
	odbc_error(sth, rc, "st_prepare/SQLAllocStmt");
	return 0;
    }

    /* scan statement for '?', ':1' and/or ':foo' style placeholders	*/
    dbd_preparse(imp_sth, statement);

    /* parse the (possibly edited) SQL statement */
    rc = SQLPrepare(imp_sth->hstmt, 
		    imp_sth->statement, strlen(imp_sth->statement));
    if (!SQL_ok(rc)) {
	odbc_error(sth, rc, "st_prepare/SQLPrepare");
	SQLFreeStmt(imp_sth->hstmt, SQL_DROP);
	imp_sth->hstmt = SQL_NULL_HSTMT;
	return 0;
    }

    if (dbis->debug >= 2)
	fprintf(DBILOGFP, "    dbd_st_prepare'd sql f%d\n\t%s\n",
		imp_sth->hstmt, imp_sth->statement);

    /* init sth pointers */
    imp_sth->henv = imp_dbh->henv;
    imp_sth->hdbc = imp_dbh->hdbc;
    imp_sth->fbh = NULL;
    imp_sth->ColNames = NULL;
    imp_sth->RowBuffer = NULL;
    imp_sth->RowCount = -1;
    imp_sth->eod = -1;

    DBIc_IMPSET_on(imp_sth);
    return 1;
}


int 
dbtype_is_string(int bind_type)
{
    switch(bind_type) {
    case SQL_C_CHAR:
    case SQL_C_BINARY:
	return 1;
    }
    return 0;
}    


static const char *
S_SqlTypeToString (SWORD sqltype)
{
    switch(sqltype) {
    case SQL_CHAR:	return "CHAR";
    case SQL_NUMERIC:	return "NUMERIC";
    case SQL_DECIMAL:	return "DECIMAL";
    case SQL_INTEGER:	return "INTEGER";
    case SQL_SMALLINT:	return "SMALLINT";
    case SQL_FLOAT:	return "FLOAT";
    case SQL_REAL:	return "REAL";
    case SQL_DOUBLE:	return "DOUBLE";
    case SQL_VARCHAR:	return "VARCHAR";
    case SQL_DATE:	return "DATE";
    case SQL_TIME:	return "TIME";
    case SQL_TIMESTAMP:	return "TIMESTAMP";
    case SQL_LONGVARCHAR: return "LONG VARCHAR";
    case SQL_BINARY:	return "BINARY";
    case SQL_VARBINARY: return "VARBINARY";
    case SQL_LONGVARBINARY: return "LONG VARBINARY";
    case SQL_BIGINT:	return "BIGINT";
    case SQL_TINYINT:	return "TINYINT";
    case SQL_BIT:	return "BIT";
    }
    return "unknown";
}


static const char *
S_SqlCTypeToString (SWORD sqltype)
{
    static char s_buf[100];
#define s_c(x) case x: return #x
    switch(sqltype) {
    s_c(SQL_C_CHAR);
    s_c(SQL_C_BIT);
    s_c(SQL_C_STINYINT);
    s_c(SQL_C_UTINYINT);
    s_c(SQL_C_SSHORT);
    s_c(SQL_C_USHORT);
    s_c(SQL_C_FLOAT);
    s_c(SQL_C_DOUBLE);
    s_c(SQL_C_BINARY);
    s_c(SQL_C_DATE);
    s_c(SQL_C_TIME);
    s_c(SQL_C_TIMESTAMP);
    }
#undef s_c
    sprintf(s_buf, "(unknown CType %d)", sqltype);
    return s_buf;
}


/*
 * describes the output variables of a query,
 * allocates buffers for result rows,
 * and binds this buffers to the statement.
 */
int
dbd_describe(h, imp_sth)
    SV *h;
    imp_sth_t *imp_sth;
{
    RETCODE rc;

    UCHAR *cbuf_ptr;		
    UCHAR *rbuf_ptr;		

    int t_cbufl=0;		/* length of all column names */
    int i;
    imp_fbh_t *fbh;
    int t_dbsize = 0;		/* size of native type */
    int t_dsize = 0;		/* display size */
    SWORD num_fields;

    if (imp_sth->done_desc)
	return 1;	/* success, already done it */
    imp_sth->done_desc = 1;

    rc = SQLNumResultCols(imp_sth->hstmt, &num_fields);
    if (!SQL_ok(rc)) {
	odbc_error(h, rc, "dbd_describe/SQLNumResultCols");
	return 0;
    }

    if (dbis->debug >= 2)
	fprintf(DBILOGFP, "    dbd_describe sql %d: num_fields=%d\n",
		imp_sth->hstmt, num_fields);

    DBIc_NUM_FIELDS(imp_sth) = num_fields;

    if (num_fields == 0) {
	if (dbis->debug >= 2)
	    fprintf(DBILOGFP, "    dbd_describe skipped (no result cols) (sql f%d)\n",
		    imp_sth->hstmt);
	return 1;
    }

    /* allocate field buffers				*/
    Newz(42, imp_sth->fbh, num_fields, imp_fbh_t);

    /* Pass 1: Get space needed for field names, display buffer and dbuf */
    for (fbh=imp_sth->fbh, i=0; i < num_fields; i++, fbh++)
    {
	UCHAR ColName[256];

	rc = SQLDescribeCol(imp_sth->hstmt, 
			    i+1, 
			    ColName, sizeof(ColName)-1,
			    &fbh->ColNameLen,
			    &fbh->ColSqlType,
			    &fbh->ColDef,
			    &fbh->ColScale,
			    &fbh->ColNullable);
        if (!SQL_ok(rc)) {	/* should never fail */
	    odbc_error(h, rc, "describe/SQLDescribeCol");
	    break;
	}

	ColName[fbh->ColNameLen] = 0;

	t_cbufl  += fbh->ColNameLen;

#ifdef SQL_COLUMN_DISPLAY_SIZE
	rc = SQLColAttributes(imp_sth->hstmt,i+1,SQL_COLUMN_DISPLAY_SIZE,
                                NULL, 0, NULL ,&fbh->ColDisplaySize);
        if (!SQL_ok(rc)) {
	    odbc_error(h, rc, "describe/SQLColAttributes/SQL_COLUMN_DISPLAY_SIZE");
	    break;
	}
	fbh->ColDisplaySize += 1; /* add terminator */
#else
	fbh->ColDisplaySize = 100; /* XXX! */
#endif

#ifdef SQL_COLUMN_LENGTH
	rc = SQLColAttributes(imp_sth->hstmt,i+1,SQL_COLUMN_LENGTH,
                                NULL, 0, NULL ,&fbh->ColLength);
        if (!SQL_ok(rc)) {
	    odbc_error(h, rc, "describe/SQLColAttributes/SQL_COLUMN_LENGTH");
	    break;
	}
#else
	fbh->ColLength = 100;	/* XXX! */
#endif

	/* change fetched size for some types
	 */
	fbh->ftype = SQL_C_CHAR;
	switch(fbh->ColSqlType)
	{
	case SQL_LONGVARBINARY:
	    fbh->ftype = SQL_C_BINARY;
	    fbh->ColDisplaySize = DBIc_LongReadLen(imp_sth);
	    break;
	case SQL_LONGVARCHAR:
	    fbh->ColDisplaySize = DBIc_LongReadLen(imp_sth)+1;
	    break;
#ifdef TIMESTAMP_STRUCT	/* XXX! */
	case SQL_TIMESTAMP:
	    fbh->ftype = SQL_C_TIMESTAMP;
	    fbh->ColDisplaySize = sizeof(TIMESTAMP_STRUCT);
	    break;
#endif
	}
	if (fbh->ftype != SQL_C_CHAR) {
	    t_dbsize += t_dbsize % sizeof(int);     /* alignment */
	}
	t_dbsize += fbh->ColDisplaySize;

	if (dbis->debug >= 2)
	    fprintf(DBILOGFP, 
	    "    dbd_describe: col %d: %s, len=%d disp=%d, prec=%d scale=%d\n", 
		    i+1, S_SqlTypeToString(fbh->ColSqlType),
		    fbh->ColLength, fbh->ColDisplaySize,
		    fbh->ColDef, fbh->ColScale
	    );
    }
    if (!SQL_ok(rc)) {
	/* odbc_error called above */
	Safefree(imp_sth->fbh);
	return 0;
    }

    /* allocate a buffer to hold all the column names	*/
    Newz(42, imp_sth->ColNames, t_cbufl + num_fields, UCHAR);
    /* allocate Row memory */
    Newz(42, imp_sth->RowBuffer, t_dbsize + num_fields, UCHAR);

    /* Second pass:
       - get column names
       - bind column output
     */

    cbuf_ptr = imp_sth->ColNames;
    rbuf_ptr = imp_sth->RowBuffer;

    for(i=0, fbh = imp_sth->fbh;
	i < num_fields && SQL_ok(rc);
	i++, fbh++)
    {
	switch(fbh->ftype)
	{
	case SQL_C_BINARY:
	case SQL_C_TIMESTAMP:
	    rbuf_ptr += (rbuf_ptr - imp_sth->RowBuffer) % sizeof(int);
	    break;
	}

	rc = SQLDescribeCol(imp_sth->hstmt, 
		i+1, 
		cbuf_ptr, 255,
		&fbh->ColNameLen, &fbh->ColSqlType,
		&fbh->ColDef, &fbh->ColScale, &fbh->ColNullable
	);
        if (!SQL_ok(rc)) {	/* should never fail */
	    odbc_error(h, rc, "describe/SQLDescribeCol");
	    break;
	}
	
	fbh->ColName = cbuf_ptr;
	cbuf_ptr[fbh->ColNameLen] = 0;
	cbuf_ptr += fbh->ColNameLen+1;

	fbh->data = rbuf_ptr;
	rbuf_ptr += fbh->ColDisplaySize;

	/* Bind output column variables */
	rc = SQLBindCol(imp_sth->hstmt,
		i+1,
		fbh->ftype, fbh->data,
		fbh->ColDisplaySize, &fbh->datalen
	);
	if (dbis->debug >= 2)
	    fprintf(DBILOGFP, 
		"    describe: col %d-%s: sqltype=%s, ctype=%s, maxlen=%d\n",
		    i+1, fbh->ColName,
		    S_SqlTypeToString(fbh->ColSqlType),
		    S_SqlCTypeToString(fbh->ftype),
		    fbh->ColDisplaySize
	    );
	if (!SQL_ok(rc)) {
	    odbc_error(h, rc, "describe/SQLBindCol");
	    break;
	}
    } /* end pass 2 */

    if (!SQL_ok(rc)) {
	/* odbc_error called above */
	Safefree(imp_sth->fbh);
	return 0;
    }

    return 1;
}


int
dbd_st_execute(sth, imp_sth)	/* <= -2:error, >=0:ok row count, (-1=unknown count) */
    SV *sth;
    imp_sth_t *imp_sth;
{
    RETCODE rc;
    int debug = dbis->debug;

    if (!imp_sth->done_desc) {
	/* describe and allocate storage for results (if any needed)	*/
	if (!dbd_describe(sth, imp_sth))
	    return -2; /* dbd_describe already called ora_error()	*/
    }

    /* bind input parameters */

    if (debug >= 2)
	fprintf(DBILOGFP,
	    "    dbd_st_execute (for sql f%d after)...\n",
			imp_sth->hstmt);

    rc = SQLExecute(imp_sth->hstmt);
    if (!SQL_ok(rc)) {
	odbc_error(sth, rc, "st_execute/SQLExecute");
	return -2;
    }

    rc = SQLRowCount(imp_sth->hstmt, &imp_sth->RowCount);
    if (!SQL_ok(rc)) {
	odbc_error(sth, rc, "st_execute/SQLRowCount");
	imp_sth->RowCount = -1;
	/* return -1; XXX */
    }

    DBIc_ACTIVE_on(imp_sth);	/* XXX should only set for select ?	*/
    imp_sth->eod = SQL_SUCCESS;
    return imp_sth->RowCount;
}


/*----------------------------------------
 * running $sth->fetch()
 *----------------------------------------
 */
AV *
dbd_st_fetch(sth, imp_sth)
    SV *	sth;
    imp_sth_t *imp_sth;
{
    int debug = dbis->debug;
    int i;
    AV *av;
    RETCODE rc;
    int num_fields;
    char cvbuf[512];
    int ChopBlanks;

    /* Check that execute() was executed sucessfully. This also implies	*/
    /* that dbd_describe() executed sucessfuly so the memory buffers	*/
    /* are allocated and bound.						*/
    if ( !DBIc_ACTIVE(imp_sth) ) {
	odbc_error(sth, SQL_ERROR, "no statement executing");
	return Nullav;
    }
    
    rc = SQLFetch(imp_sth->hstmt);
    if (dbis->debug >= 2)
	fprintf(DBILOGFP, "SQLFetch rc %d\n", rc);
    imp_sth->eod = rc;
    if (!SQL_ok(rc)) {
	if (rc != SQL_NO_DATA_FOUND)
	    odbc_error(sth, rc, "st_fetch/SQLFetch");
	return Nullav;
    }

    if (imp_sth->RowCount == -1)
	imp_sth->RowCount = 0;
    imp_sth->RowCount++;

    av = DBIS->get_fbav(imp_sth);
    num_fields = AvFILL(av)+1;

    ChopBlanks = DBIc_has(imp_sth, DBIcf_ChopBlanks);

    for(i=0; i < num_fields; ++i) {
	imp_fbh_t *fbh = &imp_sth->fbh[i];
	SV *sv = AvARRAY(av)[i]; /* Note: we (re)use the SV in the AV	*/

        if (dbis->debug >= 4)
	    fprintf(DBILOGFP, "fetch col#%d %s datalen=%d displ=%d\n",
		i, fbh->ColName, fbh->datalen, fbh->ColDisplaySize);

	if (fbh->datalen == SQL_NULL_DATA) {	/* NULL value		*/
	    SvOK_off(sv);
	    continue;
	}

	if (fbh->datalen > fbh->ColDisplaySize) { 
	    /* truncated LONG ??? DBIcf_LongTruncOk() */
	    sv_setpvn(sv, (char*)fbh->data, fbh->ColDisplaySize);
	}
	else switch(fbh->ftype) {
#ifdef TIMESTAMP_STRUCT /* iODBC doesn't define this */
	    TIMESTAMP_STRUCT *ts;
	case SQL_C_TIMESTAMP:
	    ts = (TIMESTAMP_STRUCT *)fbh->data;
	    sprintf(cvbuf, "%04d-%02d-%02d %02d:%02d:%02d",
		    ts->year, ts->month, ts->day, 
		    ts->hour, ts->minute, ts->second,
		    ts->fraction);
	    sv_setpv(sv, cvbuf);
	    break;
#endif
	default:
	    if (ChopBlanks && fbh->ColSqlType == SQL_CHAR && fbh->datalen > 0) {
		char *p = ((char*)fbh->data) + fbh->datalen;
		while(p[fbh->datalen]==' ' && fbh->datalen)
		    --fbh->datalen;
	    }
	    sv_setpvn(sv, (char*)fbh->data, fbh->datalen);
	}
    }
    return av;
}


int
dbd_st_finish(sth, imp_sth)
    SV *sth;
    imp_sth_t *imp_sth;
{
    D_imp_dbh_from_sth;
    RETCODE rc;
    int ret = 0;

    /* Cancel further fetches from this cursor.                 */
    /* We don't close the cursor till DESTROY (dbd_st_destroy). */
    /* The application may re execute(...) it.                  */

/* XXX semantics of finish (eg oracle vs odbc) need more thought */
    if (DBIc_ACTIVE(imp_sth) && imp_dbh->hdbc != SQL_NULL_HDBC) {
	rc = SQLFreeStmt(imp_sth->hstmt, SQL_CLOSE);
	if (!SQL_ok(rc)) {
	    odbc_error(sth, rc, "finish/SQLFreeStmt(SQL_CLOSE)");
	    return 0;
	}
    }
    DBIc_ACTIVE_off(imp_sth);
    return 1;
}


void
dbd_st_destroy(sth, imp_sth)
    SV *sth;
    imp_sth_t *imp_sth;
{
    D_imp_dbh_from_sth;
    RETCODE rc;

    /* SQLxxx functions dump core when no connection exists. This happens
     * when the db was disconnected before perl ending.
     */
    if (imp_dbh->hdbc != SQL_NULL_HDBC) {
	rc = SQLFreeStmt(imp_sth->hstmt, SQL_DROP);
	if (!SQL_ok(rc)) {
	    odbc_error(sth, rc, "st_destroy/SQLFreeStmt(SQL_DROP)");
	    /* return 0; */
	}
    }

    /* Free contents of imp_sth	*/

    Safefree(imp_sth->fbh);
    Safefree(imp_sth->ColNames);
    Safefree(imp_sth->RowBuffer);
    Safefree(imp_sth->statement);

    if (imp_sth->out_params_av)
	sv_free((SV*)imp_sth->out_params_av);

    if (imp_sth->all_params_hv) {
	HV *hv = imp_sth->all_params_hv;
	SV *sv;
	char *key;
	I32 retlen;
	hv_iterinit(hv);
	while( (sv = hv_iternextsv(hv, &key, &retlen)) != NULL ) {
	    if (sv != &sv_undef) {
		phs_t *phs_tpl = (phs_t*)(void*)SvPVX(sv);
		sv_free(phs_tpl->sv);
	    }
	}
	sv_free((SV*)imp_sth->all_params_hv);
    }

    DBIc_IMPSET_off(imp_sth);		/* let DBI know we've done it	*/
}


/*------------------------------------------------------------
 * bind placeholder.
 *  Is called from ODBC.xs execute()
 *  AND from ODBC.xs bind_param()
 */
int
dbd_bind_ph(sth, imp_sth, ph_namesv, newvalue, attribs, is_inout, maxlen)
    SV *sth;
    imp_sth_t *imp_sth;
    SV *ph_namesv;		/* index of execute() parameter 1..n */
    SV *newvalue;
    SV *attribs;		/* may be set by Solid.xs bind_param call */
    int is_inout;		/* inout for procedure calls only */
    IV maxlen;			/* ??? */
{
    SV **phs_svp;
    STRLEN name_len;
    char *name;
    char namebuf[30];
    phs_t *phs;

    if (SvNIOK(ph_namesv) ) {	/* passed as a number	*/
	name = namebuf;
	sprintf(name, "%d", (int)SvIV(ph_namesv));
	name_len = strlen(name);
    } 
    else {
	name = SvPV(ph_namesv, name_len);
    }

    if (dbis->debug >= 2)
	fprintf(DBILOGFP, "bind %s <== '%.200s' (attribs: %s)\n",
		name, SvPV(newvalue,na), attribs ? SvPV(attribs,na) : "" );

    phs_svp = hv_fetch(imp_sth->all_params_hv, name, name_len, 0);
    if (phs_svp == NULL)
	croak("Can't bind unknown placeholder '%s'", name);
    phs = (phs_t*)SvPVX(*phs_svp);	/* placeholder struct	*/

    if (phs->sv == &sv_undef) {	/* first bind for this placeholder	*/
	phs->ftype = SQL_C_CHAR;  /* our default type VARCHAR2	*/
	phs->sv = newSV(0);
    }

    if (attribs) {  /* only look for ora_type on first bind of var  */
	SV **svp;
	/* Setup / Clear attributes as defined by attribs.          */
	/* XXX If attribs is EMPTY then reset attribs to default?   */
	if ( (svp=hv_fetch((HV*)SvRV(attribs), "sol_type",8, 0)) != NULL) {
	    int sol_type = SvIV(*svp);
	    if (!dbtype_is_string(sol_type))        /* mean but safe */
		croak("Can't bind %s, sol_type %d not a simple string type",                            phs->name, sol_type);
	    phs->ftype = sol_type;
	}
    }
 
    /* At the moment we always do sv_setsv() and rebind.	*/
    /* Later we may optimise this so that more often we can	*/
    /* just copy the value & length over and not rebind.	*/

    if (!SvOK(newvalue)) {	/* undef == NULL		*/
	phs->isnull = 1;
    }
    else {
	sv_setsv(phs->sv, newvalue);
    }
    return _dbd_rebind_ph(sth, imp_sth, phs, maxlen);
}


/* XXX probably warrants recoding to match the new DBD::Oracle version */
int 
_dbd_rebind_ph(sth, imp_sth, phs, maxlen) 
    SV *sth;
    imp_sth_t *imp_sth;
    phs_t *phs;
    int maxlen;
{
    int n_qm;			/* number of '?' parameters */

    RETCODE rc;

    /* args of SQLBindParameter() call */
    SWORD fParamType;
    SWORD fCType;
    SWORD fSqlType;
    UDWORD cbColDef;
    SWORD ibScale;
    UCHAR *rgbValue;
    SDWORD cbValueMax;
    SDWORD *pcbValue;
    SWORD fNullable;


    /* XXX
	This will fail (IM001) on drivers which don't support it.
	We need to check for this and bind the param as varchars.
	This will work on many drivers and databases.
	If the database won't convert a varchar to an int (for example)
	the user will get an error at execute time
	but can add an explicit conversion to the SQL:
		"... where num_field > int(?) ..."
    */
	
    rc = SQLDescribeParam(imp_sth->hstmt,
	  phs->idx, &fSqlType, &cbColDef, &ibScale, &fNullable
    );
    if (!SQL_ok(rc)) {
	odbc_error(sth, rc, "_rebind_ph/SQLDescribeParam");
	return 0;
    }

    fParamType = SQL_PARAM_INPUT;
    fCType = phs->ftype;

    /* When we fill a LONGVARBINARY, the CTYPE must be set 
     * to SQL_C_BINARY.
     */
    if (fCType == SQL_C_CHAR) {	/* could be changed by bind_plh */
	switch(fSqlType) {
	case SQL_LONGVARBINARY:
	    fCType = SQL_C_BINARY;
	    break;
	case SQL_LONGVARCHAR:
	    break;
	case SQL_TIMESTAMP:
	case SQL_DATE:
	case SQL_TIME:
	    fSqlType = SQL_VARCHAR;
	    break;
	default:
	    break;
	}
    }
    pcbValue = &phs->cbValue;
    if (phs->isnull) {
	rgbValue = NULL;
	*pcbValue = SQL_NULL_DATA;
    }
    else {
	STRLEN len;
	rgbValue = (UCHAR *)SvPV(phs->sv, len);
	*pcbValue = (UDWORD) len;
    }
    cbValueMax = 0;

    if (dbis->debug >=2)
	fprintf(DBILOGFP, "    bind %s: CType=%d, SqlType=%s, ColDef=%d\n",
		phs->name, fCType, S_SqlTypeToString(fSqlType), cbColDef);

    rc = SQLBindParameter(imp_sth->hstmt,
	  phs->idx, fParamType, fCType, fSqlType,
	  cbColDef, ibScale, rgbValue, cbValueMax, pcbValue
    );
    if (!SQL_ok(rc)) {
	odbc_error(sth, rc, "_rebind_ph/SQLBindParameter");
	return 0;
    }

    return 1;
}


int
dbd_st_rows(sth, imp_sth)
    SV *sth;
    imp_sth_t *imp_sth;
{
    return imp_sth->RowCount;
}


/*------------------------------------------------------------
 * blob_read:
 * read part of a BLOB from a table.
 * XXX needs more thought
 */
dbd_st_blob_read(sth, imp_sth, field, offset, len, destrv, destoffset)
    SV *sth;
    imp_sth_t *imp_sth;
    int field;
    long offset;
    long len;
    SV *destrv;
    long destoffset;
{
    SDWORD retl;
    SV *bufsv;
    RETCODE rc;

    bufsv = SvRV(destrv);
    sv_setpvn(bufsv,"",0);      /* ensure it's writable string  */
    SvGROW(bufsv, len+destoffset+1);    /* SvGROW doesn't do +1 */

    /* XXX for this to work be probably need to avoid calling SQLGetData in	*/
    /* fetch. The definition of SQLGetData doesn't work well with the DBI's	*/
    /* notion of how LongReadLen would work. Needs more thought.		*/

    rc = SQLGetData(imp_sth->hstmt, (UWORD)field+1,
	    SQL_C_BINARY,
	    ((UCHAR *)SvPVX(bufsv)) + destoffset, (SDWORD)len, &retl
    );
    if (dbis->debug >= 2)
	fprintf(DBILOGFP, "SQLGetData(...,off=%d, len=%d)->rc=%d,len=%d SvCUR=%d\n",
		destoffset, len, rc, retl, SvCUR(bufsv));

    if (!SQL_ok(rc)) {
	odbc_error(sth, rc, "dbd_st_blob_read/SQLGetData");
	return 0;
    }
    if (rc == SQL_SUCCESS_WITH_INFO) {	/* XXX should check for 01004 */
	retl = len;
    }

    if (retl == SQL_NULL_DATA) {	/* field is null	*/
	(void)SvOK_off(bufsv);
	return 1;
    }
#ifdef SQL_NO_TOTAL
    if (retl == SQL_NO_TOTAL) {		/* unknown length!	*/
	(void)SvOK_off(bufsv);
	return 0;
    }
#endif

    SvCUR_set(bufsv, destoffset+retl);
    *SvEND(bufsv) = '\0'; /* consistent with perl sv_setpvn etc */

    if (dbis->debug >= 2)
	fprintf(DBILOGFP, "blob_read: SvCUR=%d\n",
		SvCUR(bufsv));
 
    return 1;
}


/*----------------------------------------
 * db level interface
 * set connection attributes.
 *----------------------------------------
 */

typedef struct {
    const char *str;
    UWORD fOption;
    UDWORD true;
    UDWORD false;
} db_params;

static db_params S_db_storeOptions[] =  {
    { "AutoCommit", SQL_AUTOCOMMIT, SQL_AUTOCOMMIT_ON, SQL_AUTOCOMMIT_OFF },
#if 0 /* not defined by DBI/DBD specification */
    { "TRANSACTION", 
                 SQL_ACCESS_MODE, SQL_MODE_READ_ONLY, SQL_MODE_READ_WRITE },
    { "solid_trace", SQL_OPT_TRACE, SQL_OPT_TRACE_ON, SQL_OPT_TRACE_OFF },
    { "solid_timeout", SQL_LOGIN_TIMEOUT },
    { "ISOLATION", SQL_TXN_ISOLATION },
    { "solid_tracefile", SQL_OPT_TRACEFILE },
#endif
    { NULL },
};

static const db_params *
S_dbOption(const db_params *pars, char *key, STRLEN len)
{
    /* search option to set */
    while (pars->str != NULL) {
	if (strncmp(pars->str, key, len) == 0
		&& len == strlen(pars->str))
	    break;
        pars++;
    }
    if (pars->str == NULL)
	return NULL;
    return pars;
}
 
int
dbd_db_STORE_attrib(dbh, imp_dbh, keysv, valuesv)
    SV *dbh;
    imp_dbh_t *imp_dbh;
    SV *keysv;
    SV *valuesv;
{
    D_imp_drh_from_dbh;
    RETCODE rc;
    STRLEN kl;
    STRLEN plen;
    char *key = SvPV(keysv,kl);
    SV *cachesv = NULL;
    int on;
    UDWORD vParam;
    const db_params *pars;

    if ((pars = S_dbOption(S_db_storeOptions, key, kl)) == NULL)
	return FALSE;

    switch(pars->fOption)
	{
	case SQL_LOGIN_TIMEOUT:
	case SQL_TXN_ISOLATION:
	    vParam = SvIV(valuesv);
	    break;
	case SQL_OPT_TRACEFILE:
	    vParam = (UDWORD) SvPV(valuesv, plen);
	    break;
	default:
	    on = SvTRUE(valuesv);
	    vParam = on ? pars->true : pars->false;
	    break;
	}

    rc = SQLSetConnectOption(imp_dbh->hdbc, pars->fOption, vParam);
    if (!SQL_ok(rc)) {
	odbc_error(dbh, rc, "db_STORE/SQLSetConnectOption");
	return FALSE;
    }
    /* keep our flags in sync */
    if (kl == 10 && strEQ(key, "AutoCommit"))
	DBIc_set(imp_dbh, DBIcf_AutoCommit, SvTRUE(valuesv));
    return TRUE;
}


static db_params S_db_fetchOptions[] =  {
    { "AutoCommit", SQL_AUTOCOMMIT, SQL_AUTOCOMMIT_ON, SQL_AUTOCOMMIT_OFF },
#if 0 /* seems not supported by SOLID */
    { "sol_readonly", 
                 SQL_ACCESS_MODE, SQL_MODE_READ_ONLY, SQL_MODE_READ_WRITE },
    { "sol_trace", SQL_OPT_TRACE, SQL_OPT_TRACE_ON, SQL_OPT_TRACE_OFF },
    { "sol_timeout", SQL_LOGIN_TIMEOUT },
    { "sol_isolation", SQL_TXN_ISOLATION },
    { "sol_tracefile", SQL_OPT_TRACEFILE },
#endif
    { NULL }
};

SV *
dbd_db_FETCH_attrib(dbh, imp_dbh, keysv)
    SV *dbh;
    imp_dbh_t *imp_dbh;
    SV *keysv;
{
    D_imp_drh_from_dbh;
    RETCODE rc;
    STRLEN kl;
    STRLEN plen;
    char *key = SvPV(keysv,kl);
    int on;
    UDWORD vParam = 0;
    const db_params *pars;
    SV *retsv = NULL;

    /* checking pars we need FAST */

    if ((pars = S_dbOption(S_db_fetchOptions, key, kl)) == NULL)
	return Nullsv;

    /*
     * readonly, tracefile etc. isn't working yet. only AutoCommit supported.
     */

    rc = SQLGetConnectOption(imp_dbh->hdbc, pars->fOption, &vParam);
    odbc_error(dbh, rc, "db_FETCH/SQLGetConnectOption");
    if (!SQL_ok(rc)) {
	if (dbis->debug >= 1)
	    fprintf(DBILOGFP,
		    "SQLGetConnectOption returned %d in dbd_db_FETCH\n", rc);
	return Nullsv;
    }
    switch(pars->fOption) {
    case SQL_LOGIN_TIMEOUT:
    case SQL_TXN_ISOLATION:
	newSViv(vParam);
	break;
    case SQL_OPT_TRACEFILE:
	retsv = newSVpv((char *)vParam, 0);
	break;
    default:
	if (vParam == pars->true)
	    retsv = newSViv(1);
	else
	    retsv = newSViv(0);
	break;
    } /* switch */
    return sv_2mortal(retsv);
}

typedef struct {
    const char *str;
    unsigned len:8;
    unsigned array:1;
    unsigned filler:23;
} T_st_params;

#define s_A(str) { str, sizeof(str)-1 }
static T_st_params S_st_fetch_params[] = 
{
    s_A("NUM_OF_PARAMS"),	/* 0 */
    s_A("NUM_OF_FIELDS"),	/* 1 */
    s_A("NAME"),		/* 2 */
    s_A("NULLABLE"),		/* 3 */
    s_A("TYPE"),		/* 4 */
    s_A("PRECISION"),		/* 5 */
    s_A("SCALE"),		/* 6 */
    s_A("sol_type"),		/* 7 */
    s_A("sol_length"),		/* 8 */
    s_A("CursorName"),		/* 9 */
    s_A(""),			/* END */
};

static T_st_params S_st_store_params[] = 
{
    s_A(""),			/* END */
};
#undef s_A

/*----------------------------------------
 * dummy routines st_XXXX
 *----------------------------------------
 */
SV *
dbd_st_FETCH_attrib(sth, imp_sth, keysv)
    SV *sth;
    imp_sth_t *imp_sth;
    SV *keysv;
{
    STRLEN kl;
    char *key = SvPV(keysv,kl);
    int i;
    SV *retsv = NULL;
    T_st_params *par;
    int n_fields;
    imp_fbh_t *fbh;
    char cursor_name[256];
    SWORD cursor_name_len;
    RETCODE rc;

    for (par = S_st_fetch_params; par->len > 0; par++)
	if (par->len == kl && strEQ(key, par->str))
	    break;

    if (par->len <= 0)
	return Nullsv;

    if (!imp_sth->done_desc && !dbd_describe(sth, imp_sth)) 
	{
	/* dbd_describe has already called ora_error()          */
	/* we can't return Nullsv here because the xs code will */
	/* then just pass the attribute name to DBI for FETCH.  */
        croak("Describe failed during %s->FETCH(%s)",
                SvPV(sth,na), key);
	}

    i = DBIc_NUM_FIELDS(imp_sth);
 
    switch(par - S_st_fetch_params)
	{
	AV *av;

	case 0:			/* NUM_OF_PARAMS */
	    return Nullsv;	/* handled by DBI */
        case 1:			/* NUM_OF_FIELDS */
	    retsv = newSViv(i);
	    break;
	case 2: 			/* NAME */
	    av = newAV();
	    retsv = newRV(sv_2mortal((SV*)av));
	    while(--i >= 0)
		av_store(av, i, newSVpv(imp_sth->fbh[i].ColName, 0));
	    break;
	case 3:			/* NULLABLE */
	    av = newAV();
	    retsv = newRV(sv_2mortal((SV*)av));
	    while(--i >= 0)
		av_store(av, i,
		    (imp_sth->fbh[i].ColNullable == SQL_NO_NULLS)
			? &sv_no : &sv_yes);
	    break;
	case 4:			/* TYPE */
	    av = newAV();
	    retsv = newRV(sv_2mortal((SV*)av));
	    while(--i >= 0) 
		av_store(av, i, newSViv(imp_sth->fbh[i].ColSqlType));
	    break;
        case 5:			/* PRECISION */
	    av = newAV();
	    retsv = newRV(sv_2mortal((SV*)av));
	    while(--i >= 0) 
		av_store(av, i, newSViv(imp_sth->fbh[i].ColDef));
	    break;
	case 6:			/* SCALE */
	    av = newAV();
	    retsv = newRV(sv_2mortal((SV*)av));
	    while(--i >= 0) 
		av_store(av, i, newSViv(imp_sth->fbh[i].ColScale));
	    break;
	case 7:			/* sol_type */
	    av = newAV();
	    retsv = newRV(sv_2mortal((SV*)av));
	    while(--i >= 0) 
		av_store(av, i, newSViv(imp_sth->fbh[i].ColSqlType));
	    break;
	case 8:			/* sol_length */
	    av = newAV();
	    retsv = newRV(sv_2mortal((SV*)av));
	    while(--i >= 0) 
		av_store(av, i, newSViv(imp_sth->fbh[i].ColLength));
	    break;
	case 9:			/* CursorName */
	    rc = SQLGetCursorName(imp_sth->hstmt,
		      cursor_name, sizeof(cursor_name), &cursor_name_len);
	    if (!SQL_ok(rc)) {
		odbc_error(sth, rc, "st_FETCH/SQLGetCursorName");
		return Nullsv;
	    }
	    retsv = newSVpv(cursor_name, cursor_name_len);
	    break;
	case 10:
	    retsv = newSViv(DBIc_LongReadLen(imp_sth));
	    break;
	default:
	    return Nullsv;
	}

    return sv_2mortal(retsv);
}


int
dbd_st_STORE_attrib(sth, imp_sth, keysv, valuesv)
    SV *sth;
    imp_sth_t *imp_sth;
    SV *keysv;
    SV *valuesv;
{
    D_imp_dbh_from_sth;
    STRLEN kl;
    STRLEN vl;
    char *key = SvPV(keysv,kl);
    char *value = SvPV(valuesv, vl);
    T_st_params *par;
    RETCODE rc;
 
    for (par = S_st_store_params; par->len > 0; par++)
	if (par->len == kl && strEQ(key, par->str))
	    break;

    if (par->len <= 0)
	return FALSE;

    switch(par - S_st_store_params)
	{
	case 0:/*  */
	    return TRUE;
	}
    return FALSE;
}
