#!/usr/bin/perl -I./t
$| = 1;
print "1..$tests\n";

use DBI;

print "ok 1\n";

print " Test 2: connecting to the database\n";
my $dbh = DBI->connect() || die "Connect failed: $DBI::errstr\n";

print "ok 2\n";


#### testing a simple select

print " Test 3: create test table\n";
$rc = tab_create($dbh);
print "not " unless($rc);
print "ok 3\n";

print " Test 4: insert test data\n";
my @data = 
    ( [ 1, 'foo', 'foo varchar' ],
      [ 2, 'bar', 'bar varchar' ],
	  [ 3, 'bletch', 'bletch varchar' ],
    );
$rc = tab_insert($dbh, \@data);
print "not " unless($rc);
print "ok 4\n";

print " Test 5: select test data\n";
$rc = tab_select($dbh, \@data);
print "not " unless($rc);
print "ok 5\n";

$rc = tab_delete($dbh);

BEGIN {$tests = 5;}
exit(0);

sub tab_select
    {
    my $dbh = shift;
    my $dref = shift;
    my @data = @{$dref};
    my @row;

    my $sth = $dbh->prepare("SELECT * FROM perl_dbd_test WHERE a = :1")
    	or return undef;
    $sth->execute(1);
    while (@row = $sth->fetchrow())
    	{
	print "$row[0]|$row[1]|$row[2]|\n";
	}
    $sth->finish();
    return 1;
    }

sub tab_insert {
    my $dbh = shift;
    my $dref = shift;
    my @data = @{$dref};
    my $sth = $dbh->prepare(<<"/");
INSERT INTO perl_dbd_test (a, b, c)
VALUES (:1, :2, :3)
/
    unless ($sth)
    	{
	print STDERR $DBI::errstr, "\n";
	return 0;
	}

    foreach (@data)
        {
	unless ($sth->execute(@{$_}))
	    {
	    print STDERR $DBI::errstr, "\n";
	    return 0;
	    }
	$sth->finish();
	}
    unless ($dbh->commit())
        {
	print STDERR $DBI::errstr, "\n";
	return 0;
	}
1;
}

sub tab_create {
	$dbh->do(<<"/");
DROP TABLE perl_dbd_test
/
    my $fields = "A INTEGER, B CHAR(20), C VARCHAR(100)";
    if ($^O eq 'solaris') {	# Assume Dbf driver. Sad and tacky.
	$fields = "A FLOAT(10,0), B CHAR(20), C GENERAL";
    }
    $dbh->do("CREATE TABLE perl_dbd_test ($fields)");
}

sub tab_delete {
    $dbh->do(<<"/");
DELETE FROM perl_dbd_test
/
}

__END__

