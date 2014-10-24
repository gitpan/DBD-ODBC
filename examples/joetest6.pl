#!perl -w
# $Id: joetest6.pl 11680 2008-08-28 08:23:27Z mjevans $


use strict;
use DBI;

my $dbh1 = DBI->connect() or die "Can't connect 1\n$DBI::errstr\n";

my $dbh2 = DBI->connect() or die "Can't connect 2\n$DBI::errstr\n";

$dbh1->disconnect;
$dbh2->disconnect;