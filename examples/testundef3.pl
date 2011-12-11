#!perl -w
# $Id: testundef3.pl 93 2004-02-19 19:28:16Z jurl $

use strict;
use DBI qw(:sql_types);
my $dbh=DBI->connect() or die "Can't connect";

eval {$dbh->do("DROP TABLE table1");};
eval {$dbh->do("CREATE TABLE table1 (str VARCHAR(10))");};

unlink("dbitrace.log") if (-e "dbitrace.log") ;
$dbh->trace(8, "dbitrace.log");
my $sth = $dbh->prepare ("INSERT INTO table1 (str) VALUES (?)");
$sth->bind_param (1, undef, SQL_VARCHAR);
$sth->execute();
$sth->bind_param (1, "abcde", SQL_VARCHAR);
$sth->execute();

my $sth2 = $dbh->prepare("select * from table1");
$sth2->execute;
my @row;
my $i = 0;
while (@row = $sth2->fetchrow_array) {
   $i++;
   print "$i: ", join(', ', @row), "\n";
}
$dbh->disconnect;
