#!perl.exe -w
use strict;
use DBI;

my ($instance, $user, $password, $db) = 
				       ('gaccardo\test', 'sa', 'gaccardo', 'testdb');

my $dbh = DBI->connect($ENV{DBI_DSN}, $ENV{DBI_USER}, $ENV{DBI_PASS}, {RaiseError => 1, PrintError => 0})
       or die "\n\nCannot connect.\n\n$DBI::errstr\n";
$dbh->{LongReadLen} = 65536;

unlink 'dbitrace.log' if (-e 'dbitrace.log') ;
DBI->trace(9, 'dbitrace.log');
	
my $sth = $dbh->prepare("exec sp_depends \@objname = ?");
$sth->bind_param(1, '[users].[perl_dbd_test]');
$sth->execute();
do {
   my @query_results;
   while (@query_results = $sth->fetchrow_array) {
      print join (', ', @query_results) . "\n";
   }
} while ( $sth->{odbc_more_results} );

if ($DBI::err) {
   print "\n$DBI::errstr\n "
}
