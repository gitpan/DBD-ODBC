/*
 * $Id: dbdimp.h,v 1.4 1997/07/16 19:26:20 timbo Exp $
 * Copyright (c) 1997 Jeff Urlwin
 * portions Copyright (c) 1997  Thomas K. Wenrich
 * portions Copyright (c) 1994,1995,1996  Tim Bunce
 *
 * You may distribute under the terms of either the GNU General Public
 * License or the Artistic License, as specified in the Perl README file.
 *
 */

typedef struct imp_fbh_st imp_fbh_t;

/* This holds global data of the driver itself.
 */
struct imp_drh_st {
    dbih_drc_t com;		/* MUST be first element in structure	*/
    HENV henv;
    int connects;		/* connect count */
};

/* Define dbh implementor data structure 
   This holds everything to describe the database connection.
 */
struct imp_dbh_st {
    dbih_dbc_t com;		/* MUST be first element in structure	*/
    HENV henv;			/* copy from imp_drh for speed		*/
    HDBC hdbc;
};


/* Define sth implementor data structure */
struct imp_sth_st {
    dbih_stc_t com;		/* MUST be first element in structure	*/

    HENV       henv;		/* copy for speed	*/
    HDBC       hdbc;		/* copy for speed	*/
    HSTMT      hstmt;

    int        done_desc;	/* have we described this sth yet ?	*/

    /* Input Details	*/
    char      *statement;	/* sql (see sth_scan)		*/
    HV        *all_params_hv;   /* all params, keyed by name    */
    AV        *out_params_av;   /* quick access to inout params */

    UCHAR    *ColNames;		/* holds all column names; is referenced
				 * by ptrs from within the fbh structures
				 */
    UCHAR    *RowBuffer;	/* holds row data; referenced from fbh */
    imp_fbh_t *fbh;		/* array of imp_fbh_t structs	*/

    SDWORD   RowCount;		/* Rows affected by insert, update, delete
				 * (unreliable for SELECT)
				 */
    int eod;			/* End of data seen */
};
#define IMP_STH_EXECUTING	0x0001


struct imp_fbh_st { 	/* field buffer EXPERIMENTAL */
    imp_sth_t *imp_sth;	/* 'parent' statement */
    /* field description - SQLDescribeCol() */
    UCHAR *ColName;		/* zero-terminated column name */
    SWORD ColNameLen;
    UDWORD ColDef;		/* precision */
    SWORD ColScale;
    SWORD ColSqlType;
    SWORD ColNullable;
    SDWORD ColLength;		/* SqlColAttributes(SQL_COLUMN_LENGTH) */
    SDWORD ColDisplaySize;	/* SqlColAttributes(SQL_COLUMN_DISPLAY_SIZE) */

    /* Our storage space for the field data as it's fetched	*/
    SWORD ftype;		/* external datatype we wish to get.
				 * Used as parameter to SQLBindCol().
				 */
    UCHAR *data;		/* points into sth->RowBuffer */
    SDWORD datalen;		/* length returned from fetch for single row. */
};


typedef struct phs_st phs_t;    /* scalar placeholder   */

struct phs_st {  	/* scalar placeholder EXPERIMENTAL	*/
    SWORD ftype;        /* external field type	       */
    int idx;		/* index number of this param 1, 2, ...	*/
    SV	*sv;		/* the scalar holding the value		*/
    int isnull;
    SDWORD cbValue;	/* length of returned value */
                        /* in Input: SQL_NULL_DATA */
    char name[1];	/* struct is malloc'd bigger as needed	*/
};


/* These defines avoid name clashes for multiple statically linked DBD's        */

#define dbd_init		odbc_init
#define dbd_db_login		odbc_db_login
#define dbd_db_do		odbc_db_do
#define dbd_db_commit		odbc_db_commit
#define dbd_db_rollback		odbc_db_rollback
#define dbd_db_disconnect	odbc_db_disconnect
#define dbd_db_destroy		odbc_db_destroy
#define dbd_db_STORE_attrib	odbc_db_STORE_attrib
#define dbd_db_FETCH_attrib	odbc_db_FETCH_attrib
#define dbd_st_prepare		odbc_st_prepare
#define dbd_st_rows		odbc_st_rows
#define dbd_st_execute		odbc_st_execute
#define dbd_st_fetch		odbc_st_fetch
#define dbd_st_finish		odbc_st_finish
#define dbd_st_destroy		odbc_st_destroy
#define dbd_st_blob_read	odbc_st_blob_read
#define dbd_st_STORE_attrib	odbc_st_STORE_attrib
#define dbd_st_FETCH_attrib	odbc_st_FETCH_attrib
#define dbd_describe		odbc_describe
#define dbd_bind_ph		odbc_bind_ph


/* end */
