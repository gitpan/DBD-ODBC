#!/usr/bin/perl -w -I./t
# $Id: 12blob.t 12710 2009-04-20 15:21:32Z mjevans $
#
# blob tests
# currently tests you can insert a clob with various odbc_putdata_start settings
#
use Test::More;
use strict;
$| = 1;

my $has_test_nowarnings = 1;
eval "require Test::NoWarnings";
$has_test_nowarnings = undef if $@;
my $tests = 24;
$tests += 1 if $has_test_nowarnings;
plan tests => $tests;

my $dbh;

# can't seem to get the imports right this way
use DBI qw(:sql_types);
use_ok('ODBCTEST');

sub tidyup {
    if ($dbh) {
        #diag "Tidying up\n";
        eval {
            local $dbh->{PrintWarn} = 0;
            local $dbh->{PrintError} = 0;
            $dbh->do(q/drop table DBD_ODBC_drop_me/);
        };
    }
}

BEGIN {
   if (!defined $ENV{DBI_DSN}) {
      plan skip_all => "DBI_DSN is undefined";
   }
}
END {
    tidyup();
    Test::NoWarnings::had_no_warnings()
          if ($has_test_nowarnings);
}

my $ev;

$dbh = DBI->connect();
unless($dbh) {
   BAIL_OUT("Unable to connect to the database $DBI::errstr\nTests skipped.\n");
   exit 0;
}
tidyup();

my $putdata_start = $dbh->{odbc_putdata_start};
is($putdata_start, 32768, 'default putdata_start');

my $sth = $dbh->func(SQL_ALL_TYPES, 'GetTypeInfo');
ok($sth, "GetTypeInfo");

my ($type_name, $type);

while (my @row = $sth->fetchrow) {
    #diag("$row[0], $row[1], $row[2]");
    next if (($row[1] != SQL_WLONGVARCHAR) && ($row[1] != SQL_LONGVARCHAR));
    if ($row[2] > 60000) {
        #diag("$row[0] $row[1] $row[2]");
        ($type_name, $type) = ($row[0], $row[1]);
        $sth->finish;
        last;
    }
}
SKIP: {
    skip "ODBC Driver/Database has not got a big enough type", 18
        if (!$type_name);

    #diag("Using type $type_name");
    eval { $dbh->do(qq/create table DBD_ODBC_drop_me(a $type_name)/); };
    $ev = $@;
    diag($ev) if $ev;
    ok(!$ev, "table DBD_ODBC_drop_me created");

  SKIP: {
        skip "Cannot create test table", 17 if $ev;

        my $bigval = "x" x 30000;
        test($dbh, $bigval);

        test($dbh, $bigval, 500);

        $bigval = 'x' x 60000;
        test($dbh, $bigval, 60001);
    };
};

sub test
{
    my ($dbh, $val, $putdata_start) = @_;
    my $rc;

    if ($putdata_start) {
        $dbh->{odbc_putdata_start} = $putdata_start;
        my $pds = $dbh->{odbc_putdata_start};
        is($pds, $putdata_start, "retrieved putdata_start = set value");
    }

    $sth = $dbh->prepare(q/insert into DBD_ODBC_drop_me values(?)/);
    ok($sth, "prepare for insert");
  SKIP: {
        skip "prepare failed", 3 unless $sth;

        $rc  = $sth->execute($val);
        ok($rc, "insert clob");

      SKIP: {
            skip "insert failed - skipping the retrieval test", 2 unless $rc;

            test_value($dbh, $val);
        };
    };
    $sth = undef;
    eval {$dbh->do(q/delete from DBD_ODBC_drop_me/); };
    $ev = $@;
    diag($ev) if $ev;
    ok(!$ev, 'delete records from test table');

    return;
}

sub test_value
{
    my ($dbh, $value) = @_;

    local $dbh->{RaiseError} = 1;
    my $max = 60001;
    $max = 120001 if ($type == SQL_WLONGVARCHAR);
    local $dbh->{LongReadLen} = $max;

    my $row = $dbh->selectall_arrayref(q/select a from DBD_ODBC_drop_me/);
    $ev = $@;
    diag($ev) if $ev;
    ok(!$ev, 'select test data back');

    my $rc = is(length($row->[0]->[0]), length($value),
                       "sizes of insert/select compare");
  SKIP: {
        skip "sizes do not match", 1 unless $rc;
        is($row->[0]->[0], $value, 'data read back compares');
    };

    return;
}
