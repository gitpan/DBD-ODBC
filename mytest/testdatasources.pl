use DBI;
# $Id: testdatasources.pl 93 2004-02-19 19:28:16Z jurl $

print join(', ', DBI->data_sources("ODBC")), "\n";
print $DBI::errstr;
print "\n";
