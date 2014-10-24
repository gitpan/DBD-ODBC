#!/usr/bin/perl -I./t
# $Id: 03dbatt.t 484 2004-10-11 19:20:51Z jurl $

my $tests;

$|=1;

# to help ActiveState's build process along by behaving (somewhat) if a dsn is not provided
BEGIN {
   unless (defined $ENV{DBI_DSN}) {
      print "1..0 # Skipped: DBI_DSN is undefined\n";
      exit;
   }
}

{
    my $numTest = 0;
    sub Test($;$) {
	my $result = shift; my $str = shift || '';
	printf("%sok %d%s\n", ($result ? "" : "not "), ++$numTest, $str);
	$result;
    }
}

print "1..$tests\n";

use DBI;
use ODBCTEST;
# use strict;

my @row;

Test(1);	# loaded DBI ok.

my $dbh = DBI->connect() || die "Connect failed: $DBI::errstr\n";
$dbh->{LongReadLen} = 1000;
my $dbname = $dbh->{odbc_SQL_DBMS_NAME};
Test(1);	 # connected ok

#### testing set/get of connection attributes
$dbh->{RaiseError} = 0;
$dbh->{'AutoCommit'} = 1;
my $rc = commitTest($dbh);
print " ", $dbh->errstr, "" if ($rc < -1);
if ($rc == -1) {
    Test(1, " # skipped due to lack of transaction support.");
} else {
    Test($rc == 1); # print "not " unless ($rc == 1);
}

Test($dbh->{AutoCommit});

$dbh->{'AutoCommit'} = 0;
$rc = commitTest($dbh);
print $dbh->errstr, "\n" if ($rc < -1);
if ($rc == -1) {
    Test(1, " # skipped due to lack of transaction support.");
} else {
    Test($rc == 0);
}
Test($dbname eq $dbh->{odbc_SQL_DBMS_NAME});

$dbh->{'AutoCommit'} = 1;

# ------------------------------------------------------------

my $rows = 0;
# Check for tables function working.
my $sth;

my @table_info_cols = (
		       'TABLE_CAT',
		       'TABLE_SCHEM',
		       'TABLE_NAME',
		       'TABLE_TYPE',
		       'REMARKS',
		      );
if ($sth = $dbh->table_info()) {
    my $cols = $sth->{NAME};
    for (my $i = 0; $i < @$cols; $i++) {
       # print ${$cols}[$i], ": ", $sth->func($i+1, 3, ColAttributes),
       # "\n";
       Test(${$cols}[$i] eq $table_info_cols[$i]);
    }
    while (@row = $sth->fetchrow()) {
        $rows++;
    }
    $sth->finish();
} else {
   for (my $i = 0; $i < @table_info_cols; $i++) {
      Test(1, " # skipped due to table_info not successful\n");
   }
}
Test($rows > 0);
Test($dbname eq $dbh->{odbc_SQL_DBMS_NAME});

$rows = 0;
$dbh->{PrintError} = 0;
my @tables = $dbh->tables;

Test($#tables > 0); # 7
$rows = 0;
if ($sth = $dbh->column_info(undef, undef, $ODBCTEST::table_name, undef)) {
    while (@row = $sth->fetchrow()) {
        $rows++;
    }
    $sth->finish();
}
Test($rows > 0);

$rows = 0;

if ($sth = $dbh->primary_key_info(undef, undef, $ODBCTEST::table_name, undef)) {
    while (@row = $sth->fetchrow()) {
        $rows++;
    }
    $sth->finish();
}
# my $dbname = $dbh->get_info(17); # DBI::SQL_DBMS_NAME
if ($dbname =~ /Access/i) {
   Test(1, " # Skipped: Primary Key Known to fail using MS Access through 2000");
} else {
   Test($rows > 0);
}

# test $sth->{NAME} when using non-select statements
$sth = $dbh->prepare("update $ODBCTEST::table_name set COL_A = 100 WHERE COL_A = 100");
Test(@{$sth->{NAME}}==0);
$sth->execute;
Test(@{$sth->{NAME}}==0);

Test($dbname eq $dbh->{odbc_SQL_DBMS_NAME});

$dbh->{odbc_query_timeout} = 30;
Test($dbh->{odbc_query_timeout} == 30);

my $sth_timeout = $dbh->prepare("select COL_A from $ODBCTEST::table_name");
Test($sth_timeout->{odbc_query_timeout} == 30);
$sth_timeout->{odbc_query_timeout} = 1;
Test($sth_timeout->{odbc_query_timeout} == 1);
BEGIN { $tests = 17 + 5; } # num tests + one for each table_info column (5)
$dbh->disconnect;
# print STDERR $dbh->{odbc_SQL_DRIVER_ODBC_VER}, "\n";

# ------------------------------------------------------------
# returns true when a row remains inserted after a rollback.
# this means that autocommit is ON. 
# ------------------------------------------------------------
sub commitTest {
    my $dbh = shift;
    my @row;
    my $rc = -2;
    my $sth;

    # since this test deletes the record, we should do it regardless
    # of whether or not it the db supports transactions.
    $dbh->do("DELETE FROM $ODBCTEST::table_name WHERE COL_A = 100") or return undef;

    { # suppress the "commit ineffective" warning
      local($SIG{__WARN__}) = sub { };
      $dbh->commit();
    }

    my $supported = $dbh->get_info(46); # SQL_TXN_CAPABLE 
    print "Transactions supported: $supported\n";
    if (!$supported) {
	return -1;
    }

    @row = ODBCTEST::get_type_for_column($dbh, 'COL_D');
    my $dateval;
    if (ODBCTEST::isDateType($row[1])) {
       $dateval = "{d '1997-01-01'}";
    } else {
       $dateval = "{ts '1997-01-01 00:00:00'}";
    }
    $dbh->do("insert into $ODBCTEST::table_name values(100, 'x', 'y', $dateval)");
    { # suppress the "rollback ineffective" warning
	  local($SIG{__WARN__}) = sub { };
      $dbh->rollback();
    }
    $sth = $dbh->prepare("SELECT COL_A FROM $ODBCTEST::table_name WHERE COL_A = 100");
    $sth->execute();
    if (@row = $sth->fetchrow()) {
        $rc = 1;
    }
    else {
	$rc = 0;
    }
    # in case not all rows have been returned..there shouldn't be more than one.
    $sth->finish(); 
    $rc;
}

# ------------------------------------------------------------

