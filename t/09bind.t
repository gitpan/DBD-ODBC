#!/usr/bin/perl -I./t
$| = 1;
print "1..$tests\n";

use DBI qw(:sql_types);
use ODBCTEST;

print "ok 1\n";

print " Test 2: connecting to the database\n";
my $dbh = DBI->connect() || die "Connect failed: $DBI::errstr\n";

print "ok 2\n";


#### testing a simple select"

print " Test 3: create test table\n";
$rc = ODBCTEST::tab_create($dbh);
print "not " unless($rc);
print "ok 3\n";

print " Test 4: insert test data\n";
my @data = (
	[ 1, 'foo', 'foo varchar', "{d '1998-05-13'}", "{ts '1998-05-13 00:01:00'}" ],
	[ 2, 'bar', 'bar varchar', "{d '1998-05-14'}", "{ts '1998-05-14 00:01:00'}" ],
	[ 3, 'bletch', 'bletch varchar', "{d '1998-05-15'}", "{ts '1998-05-15 00:01:00'}" ],
);
$rc = tab_insert($dbh, \@data);
unless ($rc) {
	warn "Test 4 is known to fail often. It is not a major concern.  It *may* be an indication of being unable to bind datetime values correctly.\n";
	print "not "
}
print "ok 4\n";

print " Test 5: select test data\n";
$rc = tab_select($dbh, \@data);
print "not " unless($rc);
print "ok 5\n";

$rc = ODBCTEST::tab_delete($dbh);

BEGIN {$tests = 5;}
exit(0);

sub tab_select {
	my $dbh = shift;
    my $dref = shift;
    my @data = @{$dref};
    my @row;

    my $sth = $dbh->prepare("SELECT A,B,C,D FROM $ODBCTEST::table_name WHERE a = ?")
		or return undef;
	my @bind_vals = (1, 3);
	my $bind_val;
	foreach $bind_val (@bind_vals) {
		$sth->bind_param(1, $bind_val, SQL_INTEGER);
		$sth->execute;
		while (@row = $sth->fetchrow()) {
			print "$row[0]|$row[1]|$row[2]|\n";
			if ($row[0] != $bind_val) {
				print "Bind value failed! bind value = $bind_val, returned value = $row[0]\n";
				return undef;
			}
		}
    }
	return 1;
}

sub tab_insert {
    my $dbh = shift;
    my $dref = shift;
    my @data = @{$dref};

    my $sth = $dbh->prepare(<<"/");
INSERT INTO $ODBCTEST::table_name (A, B, C, D)
VALUES (?, ?, ?, ?)
/
    unless ($sth) {
	warn $DBI::errstr;
	return 0;
    }
    $sth->{PrintError} = 1;
    foreach (@data) {
	my @row;
	@row = ODBCTEST::get_type_for_column($dbh, 'A');
	$sth->bind_param(1, $_->[0], { TYPE => $row[1] });
	@row = ODBCTEST::get_type_for_column($dbh, 'B');
	$sth->bind_param(2, $_->[1], { TYPE => $row[1] });
	@row = ODBCTEST::get_type_for_column($dbh, 'C');
	$sth->bind_param(3, $_->[2], { TYPE => $row[1] });

	print "SQL_DATE = ", SQL_DATE, " SQL_TIMESTAMP = ", SQL_TIMESTAMP, "\n";
	@row = ODBCTEST::get_type_for_column($dbh, 'D');
	print "TYPE FOUND = $row[1]\n";
	print "Binding the date value: \"$_->[$row[1] == SQL_DATE ? 3 : 4]\"\n";
	$sth->bind_param(4, $_->[$row[1] == SQL_DATE ? 3 : 4], { TYPE => $row[1] });
	return 0 unless $sth->execute;
    }
    1;
}

__END__

