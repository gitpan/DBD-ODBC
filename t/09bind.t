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
my $longstr = "This is a test of a string that is longer than 80 characters.  It will be checked for truncation and compared with itself.";
my $longstr2 = $longstr . "  " . $longstr;
my $longstr3 = $longstr2 . "  " . $longstr2;
my @data_long = (
	[ 4, 'foo2', $longstr, "{d '2000-05-13'}", "{ts '2000-05-13 00:01:00'}" ],
	[ 5, 'bar2', $longstr2, "{d '2000-05-14'}", "{ts '2000-05-14 00:01:00'}" ],
	[ 6, 'bletch2', $longstr3, "{d '2000-05-15'}", "{ts '2000-05-15 00:01:00'}" ],
);
my $tab_insert_ok = 1;
$rc = tab_insert($dbh, \@data, 1);
unless ($rc) {
	warn "Test 4 is known to fail often. It is not a major concern.  It *may* be an indication of being unable to bind datetime values correctly.\n";
	$tab_insert_ok = 0;
	print "not "
}
print "ok 4\n";

$dbh->{LongReadLen} = 2000;
print " Test 5: select test data\n";
$rc = tab_select($dbh, \@data);
print "not " unless($rc);
print "ok 5\n";

print " Test 6: insert long test data\n";
$rc = tab_insert($dbh, \@data_long, 1);
unless ($rc) {
	if ($tab_insert_ok) {
	    warn "Since test #4 succeeded, this could be indicative of a problem with long inserting, with binding parameters.\n";
	} else {
	    warn "Since test #4 failed, this could be indicative of a problem with date time binding, as per #4 above.\n";
	}
	print "not ";
}
print "ok 6\n";

print " Test 7: check long test data\n";
$rc = tab_select($dbh, \@data_long);
print "not " unless($rc);
print "ok 7\n";

print " Test 8: update long test data\n";
$rc = tab_update_long($dbh, \@data_long);
print "not " unless($rc);
print "ok 8\n";

print " Test 9: check long test data\n";
$rc = tab_select($dbh, \@data_long);
print "not " unless($rc);
print "ok 9\n";

print " Test 10: insert various test data, without having this test tell the driver the type\n";
print "          that is being bound to a column.  This tests the use of SQLDescribeParam to obtain \n";
print "          the column type on the insert.  This is experimental and will most likely fail.\n";

# turn off default binding of varchar to test this!
$dbh->{odbc_default_bind_type} = 0;
$rc = tab_insert($dbh, \@data_long, 0);
unless ($rc) {
	if ($tab_insert_ok) {
	    warn "Since test #4 succeeded, this could be indicative of a problem with long inserting, with binding parameters where the column type is detected by DBD::ODBC.  This is not a big issue as this is experimental, anyway\n";
	} else {
	    warn "Since test #4 failed, this could be indicative of a problem with date time binding, as per #4 above.\n";
	}
	print "not ";
}
print "ok 10\n";

# clean up!
$rc = ODBCTEST::tab_delete($dbh);

BEGIN {$tests = 10;}
exit(0);

sub tab_select {
    my $dbh = shift;
    my $dref = shift;
    my @data = @{$dref};
    my @row;

    my $sth = $dbh->prepare("SELECT A,B,C,D FROM $ODBCTEST::table_name WHERE A = ?")
		or return undef;
    my $bind_val;
    foreach (@data) {
	$bind_val = $_->[0];
	$sth->bind_param(1, $bind_val, SQL_INTEGER);
	$sth->execute;
	while (@row = $sth->fetchrow()) {
	    print "$row[0]|$row[1]|$row[2]|\n";
	    if ($row[0] != $bind_val) {
		print "Bind value failed! bind value = $bind_val, returned value = $row[0]\n";
		return undef;
	    }
	    if ($row[2] ne $_->[2]) {
		print "Column C value failed! bind value = $bind_val, returned values = $row[0]|$row[1]|$row[2]|$row[3]\n";
		return undef;
	    }
	}
    }
    return 1;
}	

sub tab_insert {
    my $dbh = shift;
    my $dref = shift;
    my $handle_column_type = shift;
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
	if ($handle_column_type) {
	   @row = ODBCTEST::get_type_for_column($dbh, 'A');
	   print "Binding the value: $_->[0] type = $row[1]\n";
	   $sth->bind_param(1, $_->[0], { TYPE => $row[1] });
	} else {
	   $sth->bind_param(1, $_->[0]);
	}
	if ($handle_column_type) {
	   @row = ODBCTEST::get_type_for_column($dbh, 'B');
	   $sth->bind_param(2, $_->[1], { TYPE => $row[1] });
	} else {
	   $sth->bind_param(2, $_->[1]);
	}
	if ($handle_column_type) {
	   @row = ODBCTEST::get_type_for_column($dbh, 'C');
	   $sth->bind_param(3, $_->[2], { TYPE => $row[1] });
	} else {
	   $sth->bind_param(3, $_->[2]);
	}

	print "SQL_DATE = ", SQL_DATE, " SQL_TIMESTAMP = ", SQL_TIMESTAMP, "\n";
	@row = ODBCTEST::get_type_for_column($dbh, 'D');
	print "TYPE FOUND = $row[1]\n";
	print "Binding the date value: \"$_->[$row[1] == SQL_DATE ? 3 : 4]\"\n";
	if ($handle_column_type) {
	   $sth->bind_param(4, $_->[$row[1] == SQL_DATE ? 3 : 4], { TYPE => $row[1] });
	} else {
	   $sth->bind_param(4, $_->[$row[1] == SQL_DATE ? 3 : 4]);
	}
	return 0 unless $sth->execute;
    }
    1;
}

sub tab_update_long {
    my $dbh = shift;
    my $dref = shift;
    my @data = @{$dref};

    my $sth = $dbh->prepare(<<"/");
UPDATE $ODBCTEST::table_name SET C = ? WHERE A = ?
/
    unless ($sth) {
	warn $DBI::errstr;
	return 0;
    }
    $sth->{PrintError} = 1;
    foreach (@data) {
	# change the data...
	$_->[2] .= "  " . $_->[2];
	@row = ODBCTEST::get_type_for_column($dbh, 'C');
	$sth->bind_param(1, $_->[2], { TYPE => $row[1] });
	@row = ODBCTEST::get_type_for_column($dbh, 'A');
	$sth->bind_param(2, $_->[0], { TYPE => $row[1] });

	return 0 unless $sth->execute;
    }
    1;
}

__END__

