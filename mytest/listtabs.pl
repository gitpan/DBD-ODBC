#!/usr/bin/perl -I./t

require DBI;
use DBD::ODBC::Const qw(:sql_types);
use testenv;

my (@row);

my ($dsn, $user, $pass) = soluser();

my $dbh = DBI->connect($dsn, $user, $pass, 'ODBC')
    or exit(0);
# ------------------------------------------------------------

my $rows = 0;
if ($sth = $dbh->tables())
    {
    while (@row = $sth->fetchrow())
        {
		$rows++;
		print "@row\n";
        }
    $sth->finish();
    }

$dbh->disconnect();

