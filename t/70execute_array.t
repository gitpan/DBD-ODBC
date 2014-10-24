#!/usr/bin/perl -w -I./t
# $Id: 70execute_array.t 15166 2012-02-16 21:01:43Z mjevans $
# loads of execute_array and execute_for_fetch tests

use Test::More;
use strict;
use Data::Dumper;

$| = 1;

my $has_test_nowarnings = 1;
eval "require Test::NoWarnings";
$has_test_nowarnings = undef if $@;

my $table = 'PERL_DBD_execute_array';
my $table2 = 'PERL_DBD_execute_array2';
my @captured_error;                  # values captured in error handler
my $dbh;
my @p1 = (1,2,3,4,5);
my @p2 = qw(one two three four five);
my $fetch_row = 0;

use DBI qw(:sql_types);
#use_ok('ODBCTEST');
use_ok('Data::Dumper');

BEGIN {
    plan skip_all => "DBI_DSN is undefined"
        if (!defined $ENV{DBI_DSN});
}
END {
    if ($dbh) {
        drop_table($dbh);
        $dbh->disconnect();
    }
    Test::NoWarnings::had_no_warnings()
          if ($has_test_nowarnings);
    done_testing();
}

sub error_handler
{
    @captured_error = @_;
    note("***** error handler called *****");
    0;                          # pass errors on
}

sub create_table
{
    my $dbh = shift;

    eval {
        $dbh->do(qq/create table $table (a integer primary key, b char(20))/);
    };
    if ($@) {
        diag("Failed to create test table $table - $@");
        return 0;
    }
    eval {
        $dbh->do(qq/create table $table2 (a integer primary key, b char(20))/);
    };
    if ($@) {
        diag("Failed to create test table $table2 - $@");
        return 0;
    }
    my $sth = $dbh->prepare(qq/insert into $table2 values(?,?)/);
    for (my $row = 0; $row < @p1; $row++) {
        $sth->execute($p1[$row], $p2[$row]);
    }
    1;
}

sub drop_table
{
    my $dbh = shift;

    eval {
        local $dbh->{PrintError} = 0;
        local $dbh->{PrintWarn} = 0;
        $dbh->do(qq/drop table $table/);
        $dbh->do(qq/drop table $table2/);
    };
    note("Table dropped");
}

# clear the named table of rows
sub clear_table
{
    $_[0]->do(qq/delete from $_[1]/);
}

# check $table contains the data in $c1, $c2 which are arrayrefs of values
sub check_data
{
    my ($dbh, $c1, $c2) = @_;

    my $data = $dbh->selectall_arrayref(qq/select * from $table order by a/);
    my $row = 0;
    foreach (@$data) {
        is($_->[0], $c1->[$row], "row $row p1 data");
        is($_->[1], $c2->[$row], "row $row p2 data");
        $row++;
    }
}

sub check_tuple_status
{
    my ($tsts, $expected) = @_;

    note(Data::Dumper->Dump([$tsts], [qw(ArrayTupleStatus)]));
    my $row = 0;
    foreach my $s (@$tsts) {
        if (ref($expected->[$row])) {
            is(ref($s), 'ARRAY', 'array in array tuple status');
            is(scalar(@$s), 3, '3 elements in array tuple status error');
        } else {
            if ($s == -1) {
                pass("row $row tuple status unknown");
            } else {
                is($s, $expected->[$row], "row $row tuple status");
            }
        }
        $row++
    }
}

# insert might return 'mas' which means the caller said the test
# required Multiple Active Statements and the driver appeared to not
# support MAS.
sub insert
{
    my ($dbh, $sth, $ref) = @_;

    die "need hashref arg" if (!$ref || (ref($ref) ne 'HASH'));
    note("insert " . join(", ", map {"$_ = ". DBI::neat($ref->{$_})} keys %$ref ));
    # DBD::Oracle supports MAS don't compensate for it not
    if ($ref->{requires_mas} && $dbh->{Driver}->{Name} eq 'Oracle') {
        delete $ref->{requires_mas};
    }
    @captured_error = ();

    if ($ref->{raise}) {
        $sth->{RaiseError} = 1;
    } else {
        $sth->{RaiseError} = 0;
    }

    my (@tuple_status, $sts, $total_affected);
    $sts = 999999;              # to ensure it is overwritten
    $total_affected = 999998;
    if ($ref->{array_context}) {
        eval {
            if ($ref->{params}) {
                ($sts, $total_affected) =
                    $sth->execute_array({ArrayTupleStatus => \@tuple_status},
                                        @{$ref->{params}});
            } elsif ($ref->{fetch}) {
                ($sts, $total_affected) =
                    $sth->execute_array(
                        {ArrayTupleStatus => \@tuple_status,
                         ArrayTupleFetch => $ref->{fetch}});
            } else {
                ($sts, $total_affected) =
                    $sth->execute_array({ArrayTupleStatus => \@tuple_status});
            }
        };
    } else {
        eval {
            if ($ref->{params}) {
                $sts =
                    $sth->execute_array({ArrayTupleStatus => \@tuple_status},
                                        @{$ref->{params}});
            } else {
                $sts =
                    $sth->execute_array({ArrayTupleStatus => \@tuple_status});
            }
        };
    }
    if ($ref->{error} && $ref->{raise}) {
        ok($@, 'error in execute_array eval');
    } else {
        if ($ref->{requires_mas} && $@) {
            diag("\nThis test died with $@");
            diag("It requires multiple active statement support in the driver and I cannot easily determine if your driver supports MAS. Ignoring the rest of this test.");
            foreach (@tuple_status) {
                if (ref($_)) {
                    diag(join(",", @$_));
                }
            }
            return 'mas';
        }
        ok(!$@, 'no error in execute_array eval') or note($@);
    }
    $dbh->commit if $ref->{commit};

    if (!$ref->{raise} || ($ref->{error} == 0)) {
        if (exists($ref->{sts})) {
            is($sts, $ref->{sts},
               "execute_array returned " . DBI::neat($sts) . " rows executed");
        }
        if (exists($ref->{affected}) && $ref->{array_context}) {
            is($total_affected, $ref->{affected},
               "total affected " . DBI::neat($total_affected))
        }
    }
    if ($ref->{raise}) {
        if ($ref->{error}) {
            ok(scalar(@captured_error) > 0, "error captured");
        } else {
            is(scalar(@captured_error), 0, "no error captured");
        }
    }
    if ($ref->{sts}) {
        is(scalar(@tuple_status), (($ref->{sts} eq '0E0') ? 0 : $ref->{sts}),
           "$ref->{sts} rows in tuple_status");
    }
    if ($ref->{tuple}) {
        check_tuple_status(\@tuple_status, $ref->{tuple});
    }
    return;
}
# simple test on ensure execute_array with no errors:
# o checks returned status and affected is correct
# o checks ArrayTupleStatus is correct
# o checks no error is raised
# o checks rows are inserted
# o run twice with AutoCommit on/off
# o checks if less values are specified for one parameter the right number
#   of rows are still inserted and NULLs are placed in the missing rows
# checks binding via bind_param_array and adding params to execute_array
# checks binding no parameters at all
sub simple
{
    my ($dbh, $ref) = @_;

    note('simple tests ' . join(", ", map {"$_ = $ref->{$_}"} keys %$ref ));

    note("  all param arrays the same size");
    foreach my $commit (1,0) {
        note("    Autocommit: $commit");
        clear_table($dbh, $table);
        $dbh->begin_work if !$commit;

        my $sth = $dbh->prepare(qq/insert into $table values(?,?)/);
        $sth->bind_param_array(1, \@p1);
        $sth->bind_param_array(2, \@p2);
        insert($dbh, $sth,
               { commit => !$commit, error => 0, sts => 5, affected => 5,
                 tuple => [1, 1, 1, 1, 1], %$ref});
        check_data($dbh, \@p1, \@p2);
    }

    note "  Not all param arrays the same size";
    clear_table($dbh, $table);
    my $sth = $dbh->prepare(qq/insert into $table values(?,?)/);

    $sth->bind_param_array(1, \@p1);
    $sth->bind_param_array(2, [qw(one)]);
    insert($dbh, $sth, {commit => 0, error => 0,
                        raise => 1, sts => 5, affected => 5,
                        tuple => [1, 1, 1, 1, 1], %$ref});
    check_data($dbh, \@p1, ['one', undef, undef, undef, undef]);

    note "  Not all param arrays the same size with bind on execute_array";
    clear_table($dbh, $table);
    $sth = $dbh->prepare(qq/insert into $table values(?,?)/);

    insert($dbh, $sth, {commit => 0, error => 0,
                        raise => 1, sts => 5, affected => 5,
                        tuple => [1, 1, 1, 1, 1], %$ref,
                        params => [\@p1, [qw(one)]]});
    check_data($dbh, \@p1, ['one', undef, undef, undef, undef]);

    note "  no parameters";
    clear_table($dbh, $table);
    $sth = $dbh->prepare(qq/insert into $table values(?,?)/);

    insert($dbh, $sth, {commit => 0, error => 0,
                        raise => 1, sts => '0E0', affected => 0,
                        tuple => [], %$ref,
                        params => [[], []]});
    check_data($dbh, \@p1, ['one', undef, undef, undef, undef]);
}

# error test to ensure correct behavior for execute_array when it errors:
# o execute_array of 5 inserts with last one failing
#  o check it raises an error
#  o check caught error is passed on from handler for eval
#  o check returned status and affected rows
#  o check ArrayTupleStatus
#  o check valid inserts are inserted
#  o execute_array of 5 inserts with 2nd last one failing
#  o check it raises an error
#  o check caught error is passed on from handler for eval
#  o check returned status and affected rows
#  o check ArrayTupleStatus
#  o check valid inserts are inserted
sub error
{
    my ($dbh, $ref) = @_;

    die "need hashref arg" if (!$ref || (ref($ref) ne 'HASH'));

    note('error tests ' . join(", ", map {"$_ = $ref->{$_}"} keys %$ref ));
    {
        note("Last row in error");

        clear_table($dbh, $table);
        my $sth = $dbh->prepare(qq/insert into $table values(?,?)/);
        my @pe1 = @p1;
        $pe1[-1] = 1;
        $sth->bind_param_array(1, \@pe1);
        $sth->bind_param_array(2, \@p2);
        insert($dbh, $sth, {commit => 0, error => 1, sts => undef,
                            affected => undef, tuple => [1, 1, 1, 1, []],
                            %$ref});
        check_data($dbh, [@pe1[0..4]], [@p2[0..4]]);
    }

    {
        note("2nd last row in error");
        clear_table($dbh, $table);
        my $sth = $dbh->prepare(qq/insert into $table values(?,?)/);
        my @pe1 = @p1;
        $pe1[-2] = 1;
        $sth->bind_param_array(1, \@pe1);
        $sth->bind_param_array(2, \@p2);
        insert($dbh, $sth, {commit => 0, error => 1, sts => undef,
                            affected => undef, tuple => [1, 1, 1, [], 1], %$ref});
        check_data($dbh, [@pe1[0..2],$pe1[4]], [@p2[0..2], $p2[4]]);
    }
}

sub fetch_sub
{
    note("fetch_sub $fetch_row");
    if ($fetch_row == @p1) {
        note('returning undef');
        $fetch_row = 0;
        return;
    }

    return [$p1[$fetch_row], $p2[$fetch_row++]];
}

# test insertion via execute_array and ArrayTupleFetch
sub row_wise
{
    my ($dbh, $ref) = @_;

    note("row_size via execute_for_fetch");

    # Populate the first table via a ArrayTupleFetch which points to a sub
    # returning rows
    $fetch_row = 0;             # reset fetch_sub to start with first row
    clear_table($dbh, $table);
    my $sth = $dbh->prepare(qq/insert into $table values(?,?)/);
    insert($dbh, $sth,
           {commit => 0, error => 0, sts => 5, affected => 5,
            tuple => [1, 1, 1, 1, 1], %$ref,
            fetch => \&fetch_sub});

    # NOTE: The following test requires Multiple Active Statements. Although
    # I can find ODBC drivers which do this it is not easy (if at all possible)
    # to know if an ODBC driver can handle MAS or not. If it errors the
    # driver probably does not have MAS so the error is ignored and a
    # diagnostic is output. Exceptions are DBD::Oracle which definitely does
    # support MAS.
    # The data pushed into the first table is retrieved via ArrayTupleFetch
    # from the second table by passing an executed select statement handle into
    # execute_array.
    note("row_size via select");
    clear_table($dbh, $table);
    $sth = $dbh->prepare(qq/insert into $table values(?,?)/);
    my $sth2 = $dbh->prepare(qq/select * from $table2/);
    # some drivers issue warnings when mas fails and this causes
    # Test::NoWarnings to output something when we already found
    # the test failed and captured it.
    # e.g., some ODBC drivers cannot do MAS and this test is then expected to
    # fail but we ignore the failure. Unfortunately in failing DBD::ODBC will
    # issue a warning in addition to the fail
    $sth->{Warn} = 0;
    $sth->{Warn} = 0;
    ok($sth2->execute, 'execute on second table') or diag($sth2->errstr);
    ok($sth2->{Executed}, 'second statement is in executed state');
    my $res = insert($dbh, $sth,
           {commit => 0, error => 0, sts => 5, affected => 5,
            tuple => [1, 1, 1, 1, 1], %$ref,
            fetch => $sth2, requires_mas => 1});
    return if $res && $res eq 'mas'; # aborted , does not seem to support MAS
    check_data($dbh, \@p1, \@p2);
}

# test updates
# updates are special as you can update more rows than there are parameter rows
sub update
{
    my ($dbh, $ref) = @_;

    note("update test");

    # populate the first table with the default 5 rows using a ArrayTupleFetch
    $fetch_row = 0;
    clear_table($dbh, $table);
    my $sth = $dbh->prepare(qq/insert into $table values(?,?)/);
    insert($dbh, $sth,
           {commit => 0, error => 0, sts => 5, affected => 5,
            tuple => [1, 1, 1, 1, 1], %$ref,
            fetch => \&fetch_sub});
    check_data($dbh, \@p1, \@p2);

    # update all rows b column to 'fred' checking rows affected is 5
    $sth = $dbh->prepare(qq/update $table set b = ? where a = ?/);
    # NOTE, this also checks you can pass a scalar to bind_param_array
    $sth->bind_param_array(1, 'fred');
    $sth->bind_param_array(2, \@p1);
    insert($dbh, $sth,
           {commit => 0, error => 0, sts => 5, affected => 5,
            tuple => [1, 1, 1, 1, 1], %$ref});
    check_data($dbh, \@p1, [qw(fred fred fred fred fred)]);

    # update 4 rows column b to 'dave' checking rows affected is 4
    $sth = $dbh->prepare(qq/update $table set b = ? where a = ?/);
    # NOTE, this also checks you can pass a scalar to bind_param_array
    $sth->bind_param_array(1, 'dave');
    my @pe1 = @p1;
    $pe1[-1] = 10;              # non-existant row
    $sth->bind_param_array(2, \@pe1);
    insert($dbh, $sth,
           {commit => 0, error => 0, sts => 5, affected => 4,
            tuple => [1, 1, 1, 1, '0E0'], %$ref});
    check_data($dbh, \@p1, [qw(dave dave dave dave fred)]);

    # now change all rows b column to 'pete' - this will change all 5
    # rows even though we have 2 rows of parameters so we can see if
    # the rows affected is > parameter rows
    $sth = $dbh->prepare(qq/update $table set b = ? where b like ?/);
    # NOTE, this also checks you can pass a scalar to bind_param_array
    $sth->bind_param_array(1, 'pete');
    $sth->bind_param_array(2, ['dave%', 'fred%']);
    insert($dbh, $sth,
           {commit => 0, error => 0, sts => 2, affected => 5,
            tuple => [4, 1], %$ref});
    check_data($dbh, \@p1, [qw(pete pete pete pete pete)]);


}

diag("\n\nNOTE: This is an experimental test. Originally it did not test anything in DBD::ODBC specifically but since DBD::ODBC added the execute_for_fetch method this is no longer true. If you fail this test and want to use DBI's execute_for_fetch or execute_array methods you should consider setting odbc_disable_array_operations to fall back to DBI's default handling of these methods. This is safer but not as quick. If it fails it should not stop you installing DBD::ODBC but if it fails with an error other than something indicating 'connection busy' it would be worth rerunning it with TEST_VERBOSE set or using prove and sending the results to the dbi-users mailing list.\n\n");
$dbh = DBI->connect();
unless($dbh) {
   BAIL_OUT("Unable to connect to the database $DBI::errstr\nTests skipped.\n");
   exit 0;
}
note("Using driver $dbh->{Driver}->{Name}");

# this test uses multiple active statements
# if we recognise the driver and it supports MAS enable it
my $driver_name = $dbh->get_info(6) || '';
if (($driver_name eq 'libessqlsrv.so') ||
    ($driver_name =~ /libsqlncli/)) {
    my $dsn = $ENV{DBI_DSN};
    if ($dsn !~ /^dbi:ODBC:DSN=/ && $dsn !~ /DRIVER=/i) {
        my @a = split(q/:/, $ENV{DBI_DSN});
        $dsn = join(q/:/, @a[0..($#a - 1)]) . ":DSN=" . $a[-1];
    }
    $dsn .= ";MARS_Connection=yes";
    $dbh->disconnect;
    $dbh = DBI->connect($dsn, $ENV{DBI_USER}, $ENV{DBI_PASS});
}

#$dbh->{ora_verbose} = 5;
$dbh->{RaiseError} = 1;
$dbh->{PrintError} = 0;
$dbh->{ChopBlanks} = 1;
$dbh->{HandleError} = \&error_handler;
$dbh->{AutoCommit} = 1;

drop_table($dbh);
ok(create_table($dbh), "create test table") or exit 1;
simple($dbh, {array_context => 1, raise => 1});
simple($dbh, {array_context => 0, raise => 1});
error($dbh, {array_context => 1, raise => 1});
error($dbh, {array_context => 0, raise => 1});
error($dbh, {array_context => 1, raise => 0});
error($dbh, {array_context => 0, raise => 0});

row_wise($dbh, {array_context => 1, raise => 1});

update($dbh, {array_context => 1, raise => 1});
