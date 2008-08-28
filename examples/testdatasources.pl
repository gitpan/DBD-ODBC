use DBI;
# $Id: testdatasources.pl 11680 2008-08-28 08:23:27Z mjevans $

print join(', ', DBI->data_sources("ODBC")), "\n";
print $DBI::errstr;
print "\n";
