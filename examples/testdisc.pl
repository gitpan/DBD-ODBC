#!perl -w
# $Id: testdisc.pl 14631 2011-01-03 16:48:35Z mjevans $


use strict;

use DBI;

my $dbh = DBI->connect() or die "connect";

$dbh->disconnect;

eval {
   my $sth = $dbh->tables();
};
eval {
   my $sth2 = $dbh->prepare("select sysdate from dual");
};
