#!perl -w

use strict;
use DBI qw(:sql_types);

my $dbh=DBI->connect() or die "Can't connect";

$dbh->{RaiseError} = 1;
$dbh->{LongReadLen} = 800;
eval {
   $dbh->do("drop table foo");
};
my $dbname = $dbh->get_info(17); # sql_dbms_name
my $txttype = "varchar(4000)";
$txttype = "TEXT" if ($dbname =~ /ACCESS/) ;
$dbh->do("Create table foo (id integer primary key, txt $txttype)");


my $sth = $dbh->prepare("INSERT INTO FOO (ID, TXT) values (?, ?)");
my $sth2 = $dbh->prepare("select txt from foo where id = ?");

my @txtinserted;

my @lengths = (
	       4,
	       4,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       12,
	       12,
	       12,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       88,
	       7,
	       7,
	       7,
	       100,
	       100,
	       12,
	       7,
	       183,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       7,
	       114,
	       251,
	       282,
	       281,
	       276,
	       131,
	       284,
	       144,
	       131,
	       144,
	       144,
	       131,
	       284,
	       144,
	       251,
	       284,
	       144,
	       284,
	       3,
	       284,
	       276,
	       284,
	       276,
	       3,
	       284,
	       144,
	       284,
	       7,
	       131,
	       144,
	       284,
	       284,
	       276,
	       131,
	       131,
	       114,
	       122
		     );

my $tmp;
my $longstr = "abcdefghijklmnopqrstuvwxyz";

my $i = 0;

while ($i < 10) {
   $longstr .= $longstr;
   $i++;
}
$i = 0;
# see if this resolves the execute issue??
$tmp = 'dummy';
$sth->bind_param(2, $tmp, SQL_LONGVARCHAR);
$tmp = 1;
# $sth->bind_param(1, $tmp, SQL_INTEGER);

while ($i <= $#lengths) {
   $tmp = substr($longstr, $i, $lengths[$i]);
   die "substr error? $tmp, $lengths[$i]\n" unless length($tmp) == $lengths[$i];
   push(@txtinserted, $tmp);
   if (0) {
      $sth->bind_param(1, $i, SQL_INTEGER);
      $sth->bind_param(2, $tmp, SQL_LONGVARCHAR);
      $sth->execute;
   } else {
      $sth->execute($i, $tmp);
   }
   # print "$i: $lengths[$i]\n";
   $i++;
}

print "Inserted $i records.\n";
$i = 0;

while ($i <= $#lengths) {
   if (length($txtinserted[$i]) != $lengths[$i]) {
      print "Test Mismatch @ $i, $txtinserted[$i] != $lengths[$i]\n";
   }

   $sth2->execute($i);
   my @row = $sth2->fetchrow_array();
   $sth2->finish;
   if ($txtinserted[$i] ne $row[0]) {
      print "Mismatch @ $i, ", length($txtinserted[$i]), " != ", length($row[0]), ": \n", $txtinserted[$i], "\n$row[0]\n";
   }
   # print "$i: $txtinserted[$i]\n";
   
   $i++;
}

print "Checked $i records\n";
$dbh->disconnect;
