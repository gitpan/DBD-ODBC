#!/usr/bin/perl -I./t
$|=1;
print "1..$tests\n";

use DBI;

my @row;

print "ok 1\n";

my $dbh = DBI->connect() || die "Connect failed: $DBI::errstr\n";
print "ok 2\n";

#### testing set/get of connection attributes

$dbh->{'AutoCommit'} = 1;
$rc = commitTest($dbh);
print " ", $DBI->errstr, "" if ($rc < 0);
print "not" unless ($rc == 1);
print "ok 3\n";

print "not " unless($dbh->{AutoCommit});
print "ok 4\n";

$dbh->{'AutoCommit'} = 0;
$rc = commitTest($dbh);
print $DBI->errstr, "\n" if ($rc < 0);
print "not" unless ($rc == 0);
print "ok 5\n";

# ------------------------------------------------------------

my $rows = 0;
# TBD: Check for tables function working.  
#if ($sth = $dbh->tables())
#    {
#    while (@row = $sth->fetchrow())
#        {
#        $rows++;
#        }
#    $sth->finish();
#    }
#print "not " unless $rows;
print "ok 6\n";


BEGIN { $tests = 6; }
$dbh->disconnect();

# ------------------------------------------------------------
# returns true when a row remains inserted after a rollback.
# this means that autocommit is ON. 
# ------------------------------------------------------------
sub commitTest {
    my $dbh = shift;
    my @row;
    my $rc;
    my $sth;

    $dbh->do('delete from perl_dbd_test where a = 100') or return undef;

    { # suppress the "commit ineffective" warning
      local($SIG{__WARN__}) = sub { };
      $dbh->commit();
    }

    $dbh->do("insert into perl_dbd_test values(100, 'x', 'y')");
    { # suppress the "rollback ineffective" warning
	  local($SIG{__WARN__}) = sub { };
      $dbh->rollback();
    }
    $sth = $dbh->prepare('SELECT a FROM perl_dbd_test WHERE a = 100');
    $sth->execute();
    if (@row = $sth->fetchrow()) {
        $rc = 1;
    }
    else {
	$rc = 0;
    }
    $sth->finish();
    return $rc;
}

# ------------------------------------------------------------

