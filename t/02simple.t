#!/usr/bin/perl -I./t
$| = 1;
print "1..$tests\n";

use DBI;

print "ok 1\n";

print " Test 2: connecting to the database\n";
#DBI->trace(2);
my $dbh = DBI->connect() || die "Connect failed: $DBI::errstr\n";
$dbh->{AutoCommit} = 1;

print "ok 2\n";


#### testing a simple select

print " Test 3: create test table\n";
$rc = tab_create($dbh);
print "not " unless($rc);
print "ok 3\n";

print " Test 4: check existance of test table\n";
my $rc = 0;
$rc = tab_exists($dbh);
print "not " unless($rc >= 0);
print "ok 4\n";

print " Test 5: insert test data\n";
$rc = tab_insert($dbh);
print "not " unless($rc);
print "ok 5\n";

print " Test 6: select test data\n";
$rc = tab_select($dbh);
print "not " unless($rc);
print "ok 6\n";

$rc = tab_delete($dbh);

BEGIN {$tests = 6;}
exit(0);

sub tab_select
    {
    my $dbh = shift;
    my @row;

    my $sth = $dbh->prepare("SELECT * FROM perl_dbd_test")
    	or return undef;
    $sth->execute();
    while (@row = $sth->fetchrow())
    	{
	print "$row[0]|$row[1]|$row[2]|\n";
	}
    $sth->finish();
    return 1;
    }

#
# show various ways of inserting data without binding parameters.
# Note, these are not necessarily GOOD ways to
# show this...
#
sub tab_insert {
    my $dbh = shift;

    # qeDBF needs a space after the table name!
    my $stmt = "INSERT INTO perl_dbd_test (a, b, c) VALUES ("
	    . join(", ", 3, $dbh->quote("bletch"), $dbh->quote("bletch varchar")). ")";
    my $sth = $dbh->prepare($stmt) || die "prepare: $stmt: $DBI::errstr";
    $sth->execute || die "execute: $stmt: $DBI::errstr";
    $sth->finish;

    $dbh->do(q{INSERT INTO perl_dbd_test (a, b, c) VALUES (1, 'foo', 'foo varchar')});
    $dbh->do(q{INSERT INTO perl_dbd_test (a, b, c) VALUES (2, 'bar', 'bar varchar')});
}

sub tab_create {
    my $dbh = shift;
    $dbh->{PrintError} = 0;	# Umm, need a better (croak safe) way!
    $dbh->do("DROP TABLE perl_dbd_test");
    $dbh->{PrintError} = 1;

    my $fields = "A INTEGER, B CHAR(20), C VARCHAR(100)";
    if ($^O eq 'solaris') {	# Assume Dbf driver. Sad and tacky.
	$fields = "A FLOAT(10,0), B CHAR(20), C MEMO";
    }
    $dbh->do("CREATE TABLE perl_dbd_test ($fields)");
}

sub tab_delete {
    $dbh->do("DELETE FROM perl_dbd_test");
}

#
sub tab_exists {
    my $dbh = shift;
    my (@rows, @row, $rc);

    $rc = -1;

	unless ($sth = $dbh->tables()) {
		print "Can't list tables\n";
		return -1;
	}
	# TABLE_QUALIFIER,TABLE_OWNER,TABLE_NAME,TABLE_TYPE,REMARKS
	while ($row = $sth->fetchrow_hashref()) {
		# XXX not fully true.  The "owner" could be different.  Need to check!
		# In Oracle, testing $user against $row[1] works, but does NOT in SQL Server.
		# SQL server returns the device and something else I haven't quite taken the time
		# to figure it out, since I'm not a SQL server expert.  Anyone out there?
		# (mine returns "dbo" for the owner on ALL my tables.  This is obviously something
		# significant for SQL Server...one of these days I'll dig...
		if (("PERL_DBD_TEST" eq uc($row->{TABLE_NAME}))) {
									# and (uc($user) eq uc($row[1]))) 
			# qeDBF driver returns null for TABLE_OWNER
			my $owner = $row->{TABLE_OWNER} || '(unknown owner)';
			print "$owner.$row->{TABLE_NAME}\n";
			$rc = 1;
			last;
		}
	}
	$sth->finish();
	$rc;
}
	

__END__

if ($sth && $sth->execute())
    {
    @row = $sth->execute();
    
    while (@row = $sth->execute())
	{
	push(@rows, [ @row ]);
	}
    print "not ok 3" if ($DBI::errstr);
    $sth->finish() || print "not ok 3";
    }
else
    {
    print "not ok 3\n";
    }

my $sth = $dbh->prepare(<<"/");
CREATE TABLE perl_dbd_test(
	A integer,
	B char(20),
	C timestamp)
/
print STDERR $DBI::errstr unless($sth);


BEGIN {$tests = 3;}
exit(0);

__END__
######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):




$DBI::dbi_debug = 2;
my $dbh = DBI->connect('', 'system', 'manager', 'Solid');
print STDERR $DBI::errstr, "\n" unless $dbh;
print "not " unless $dbh;
print "ok 2\n";


my $sth = $dbh->prepare('select table_name, table_type from tables');
print STDERR $DBI::errstr, "\n" unless $sth;
print "not " unless $sth;
print "ok 3\n";

my $h = $sth->execute();
print STDERR $DBI::errstr, "\n" unless $h;
print "not " unless $h;
print "ok 4\n";

my @row;
my $rc = 0;
while ((@row = $sth->fetchrow()) && $rc < 3)
    {
    print $DBI::errstr, "\n" if ($DBI::errstr); 
    print $row[0], " ", $row[1], "\n";
    $rc++;
    }

$sth->finish();

$sth = $dbh->prepare(<<"/");
select table_name from tables
where table_type = :1
  and table_schema = :2
/
print $DBI::errstr, "\n" unless($sth);

$rc = $sth->execute('BASE TABLE', 'TOM');
print $DBI::errstr, "\n" unless($rc);

while (@row = $sth->fetchrow())
    {
    print $row[0], " ", $row[1], "\n";
    }
print $DBI::errstr, "\n" if ($DBI::errstr); 
$sth->finish();
$dbh->disconnect();

$dbh=DBI->connect('', 'tom', 'pinga', 'Solid');

print "TESTING integer parameter\n";

$sth = $dbh->prepare('select a,b from nix where a = :1');
print $DBI::errstr, "\n" unless($sth);

$rc = $sth->execute('1');
print $DBI::errstr, "\n" unless($rc);

while (@row = $sth->fetchrow())
    {
    print $row[0], " ", $row[1], "\n";
    }
print $DBI::errstr, "\n" if ($DBI::errstr); 
$sth->finish();


$dbh->disconnect();




