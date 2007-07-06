#!perl -w
# $Id: testdisc.pl 93 2004-02-19 19:28:16Z jurl $


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
