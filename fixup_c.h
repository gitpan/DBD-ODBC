
/* fix up constants and other fundamentals that some driver managers	*/
/* don't define (basically iODBC)										*/

#if !defined(WIN32) && !defined(HWND)
/* HWND is typically a typedef, not a #define. Since we can't tell	*/
/* if a typedef has been defined, we define our own so the compiler	*/
/* will complain if it doesn't match.								*/
typedef void *HWND;		/* change to #define if it causes problems */
#endif

#ifndef SQL_MAX_COLUMN_NAME_LEN
#define SQL_MAX_COLUMN_NAME_LEN 16	/* XXX conservative guess */
#endif

#ifndef SQL_SQLSTATE_SIZE
#define SQL_SQLSTATE_SIZE	5
#endif
