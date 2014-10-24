#!perl -w
# $Id: identity.pl 93 2004-02-19 19:28:16Z jurl $


use strict;
use DBI;

my $dbh = DBI->connect("DBI:ODBC:PERL_TEST_SQLSERVER",,, {RaiseError => 1});

# create a temp table with an identity property on a column:
my $sql = qq{CREATE TABLE #TEMP1 (MyCol INT NOT NULL IDENTITY)};
$dbh->do($sql);

# Set the identity insert property for this table on
# this should allow me to explicitly give a value to be inserted into the # identity column:

$sql = qq{SET IDENTITY_INSERT #TEMP1 ON};
$dbh->do($sql);		# Added by JLU
# now try to insert an explicit value into this identity column:

$sql = qq{INSERT INTO #TEMP1 (MyCol) VALUES (1)};
$dbh->do($sql);

$dbh->disconnect;
