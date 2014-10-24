#!/usr/bin/perl -w -I./t
# $Id: 07bind.t 15438 2012-10-08 21:07:54Z mjevans $

use Test::More;

$| = 1;
my $has_test_nowarnings = 1;
eval "require Test::NoWarnings";
$has_test_nowarnings = undef if $@;
my $tests = 25;
$tests += 1 if $has_test_nowarnings;
plan tests => $tests;


# use_ok('DBI', qw(:sql_types));
# can't seem to get the imports right this way
use DBI qw(:sql_types);
use_ok('ODBCTEST');

BEGIN {
   if (!defined $ENV{DBI_DSN}) {
      plan skip_all => "DBI_DSN is undefined";
   }
}
END {
    Test::NoWarnings::had_no_warnings()
          if ($has_test_nowarnings);
}

my $dbh = DBI->connect();
unless($dbh) {
   BAIL_OUT("Unable to connect to the database $DBI::errstr\nTests skipped.\n");
   exit 0;
}


$rc =
ok(ODBCTEST::tab_create($dbh), "Create tables");

my @data = (
	[ 1, 'foo', 'foo varchar', "1998-05-13", "1998-05-13 00:01:00" ],
	[ 2, 'bar', 'bar varchar', "1998-05-14", "1998-05-14 00:01:00" ],
	[ 3, 'bletch', 'bletch varchar', "1998-05-15", "1998-05-15 00:01:00" ],
	[ 4, 'bletch4', 'bletch varchar', "1998-05-15", "1998-05-15 00:01:00.1" ],
	[ 5, 'bletch5', undef, "1998-05-15", "1998-05-15 00:01:00.23" ],
	[ 6, '', '', "1998-05-15", "1998-05-15 00:01:00.233" ],
);
my $longstr = "This is a test of a string that is longer than 80 characters.  It will be checked for truncation and compared with itself.";
my $longstr2 = $longstr . "  " . $longstr;
my $longstr3 = $longstr2 . "  " . $longstr2;
my @data_long = (
	[ 10, 'foo2', $longstr, "2000-05-13", "2000-05-13 00:01:00" ],
	[ 11, 'bar2', $longstr2, "2000-05-14", "2000-05-14 00:01:00" ],
	[ 12, 'bletch2', $longstr3, "2000-05-15", "2000-05-15 00:01:00" ],
);
my $tab_insert_ok = 1;
$rc = ODBCTEST::tab_insert_bind($dbh, \@data, 1);
ok($rc, "Table insert test");
unless ($rc) {
	diag("Test 4 is known to fail often. It is not a major concern.  It *may* be an indication of being unable to bind datetime values correctly.\n");
	$tab_insert_ok = 0;
	# print "not "
}

$dbh->{LongReadLen} = 2000;
is($dbh->{LongReadLen}, 2000, "Ensure long readlen set correctly");

$rc = tab_select($dbh, \@data);
ok($rc, "Select tests");

$rc = ODBCTEST::tab_insert_bind($dbh, \@data_long, 1);
ok($rc, "Insert with bind tests");
unless ($rc) {
   if ($tab_insert_ok) {
      diag("Since test #4 succeeded, this could be indicative of a problem with long inserting, with binding parameters.\n");
   } else {
      diag("Since test #4 failed, this could be indicative of a problem with date time binding, as per #4 above.\n");
   }
}


$rc = tab_select($dbh, \@data_long);
ok($rc, "select long test data");

$rc = tab_update_long($dbh, \@data_long);
ok($rc, "update long test data");

$rc = tab_select($dbh, \@data_long);
ok($rc, "select long test data again");

# clean up!
$rc = ODBCTEST::tab_delete($dbh);

# test param values!
my $sth = $dbh->prepare("insert into $ODBCTEST::table_name (COL_A, COL_C) values (?, ?)");
$sth->bind_param(1, 1, SQL_INTEGER);
$sth->bind_param(2, "test", SQL_LONGVARCHAR);
my $ref = $sth->{ParamValues};
is(ref($ref), 'HASH', 'ParamValues returns a hash ref');

is($ref->{1}, 1, "ParamValues test integer");
is($ref->{2}, "test", "Paramvalues test string");

# test param types
$ref = $sth->{ParamTypes};
is(ref($ref), 'HASH', 'ParamValues returns a hash ref');
ok(exists($ref->{1}), 'p1 exists');
ok(exists($ref->{1}), 'p2 exists');
is(ref($ref->{1}), 'HASH', 'p1 is a hash reference');
is(ref($ref->{2}), 'HASH', 'p2 is a hash reference');
ok(exists($ref->{1}->{TYPE}), 'p1 TYPE exists');
ok(exists($ref->{2}->{TYPE}), 'p2 TYPE exists');
like($ref->{1}->{TYPE}, qr/^-?\d+$/, 'numeric SQL type on p1');
like($ref->{2}->{TYPE}, qr/^-?\d+$/, 'numeric SQL type on p2');

# test numbered parameters
eval {
    $dbh->do("delete from $ODBCTEST::table_name");
    $sth = $dbh->prepare(
        "insert into $ODBCTEST::table_name(COL_A, COL_C) values (:1, :2)");
    $sth->bind_param("1", 1);
    $sth->bind_param("2", 2);
    $sth->execute;
};
my $ev = $@;
diag($ev) if $ev;
ok(!$ev, 'insert with numbered placeholders');
is($sth->rows, 1, '...inserted one row');

# test named parameters
eval {
    $dbh->do("delete from $ODBCTEST::table_name");
    $sth = $dbh->prepare(
        "insert into $ODBCTEST::table_name(COL_A, COL_C) values (:three, :four)");
    $sth->bind_param("three", 3);
    $sth->bind_param("four", 4);
    $sth->execute;
};
$ev = $@;
diag($ev) if $ev;
ok(!$ev, 'insert with named placeholders');
is($sth->rows, 1, '...inserted one row');

# how to test "sticky" bind_param?
# how about setting ODBC default bind_param to some number
# then
# clean up!
$rc = ODBCTEST::tab_delete($dbh);

exit(0);
print $DBI::errstr;

sub tab_select {
    my $dbh = shift;
    my $dref = shift;
    my @data = @{$dref};
    my @row;

    my $dbname;
    $dbname = $dbh->get_info(17); # SQL_DBMS_NAME
    my $sth = $dbh->prepare("SELECT COL_A,COL_B,COL_C,COL_D FROM $ODBCTEST::table_name WHERE COL_A = ?")
		or return undef;
    my $bind_val;
    foreach (@data) {
        $bind_val = $_->[0];
        $sth->bind_param(1, $bind_val, SQL_INTEGER);
        $sth->execute;
        while (@row = $sth->fetchrow()) {
            # print "$row[0]|$row[1]|$row[2]|\n";
            if ($row[0] != $bind_val) {
                print "Bind value failed! bind value = $bind_val, returned value = $row[0]\n";
                return undef;
            }
            if (!defined($row[2]) && !defined($_->[2])) {
                # ok...
            } else {
                if (!defined($row[2] && $dbname =~ /Oracle/)) {
                    # Oracle typically treats empty blanks as NULL in varchar, so that's what we should
                    # expect!
                    $row[2] = "";
                }
                if ($row[2] ne $_->[2]) {
                    print "Column C value failed! bind value = $bind_val, returned values = $row[0]|$row[1]|$row[2]|$row[3]\n";
                    return undef;
                }
            }
        }
    }
    return 1;
}

sub tab_update_long {
    my $dbh = shift;
    my $dref = shift;
    my @data = @{$dref};

    my $sth = $dbh->prepare(<<"/");
UPDATE $ODBCTEST::table_name SET COL_C = ? WHERE COL_A = ?
/
    unless ($sth) {
	warn $DBI::errstr;
	return 0;
    }
    $sth->{PrintError} = 1;
    foreach (@data) {
	# change the data...
	$_->[2] .= "  " . $_->[2];
	my $row = ODBCTEST::get_type_for_column($dbh, 'COL_C');
	$sth->bind_param(1, $_->[2], { TYPE => $row->{DATA_TYPE} });
	$row = ODBCTEST::get_type_for_column($dbh, 'COL_A');
	$sth->bind_param(2, $_->[0], { TYPE => $row->{DATA_TYPE} });

	return 0 unless $sth->execute;
    }
    1;
}

__END__

