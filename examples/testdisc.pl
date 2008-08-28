#!perl -w
# $Id: testdisc.pl 11680 2008-08-28 08:23:27Z mjevans $


use strict;

use DBI;

my $dbh = DBI->connect();

$dbh->disconnect;

eval {
   my $sth = $dbh->tables();
};
eval {
   my $sth2 = $dbh->prepare("select sysdate from dual");
};
