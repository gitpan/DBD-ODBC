use DBI;
# $Id$

use DBI::Const;

$\ = "\n";
$, = ": ";

my $dbh = DBI->connect or die $DBI::errstr;
$dbh->{ RaiseError } = 1;
$dbh->{ PrintError } = 1;

for ( @ARGV ? @ARGV : sort keys %DBI::Const::GetInfo )
{
   my $Val = $dbh->get_info( $DBI::Const::GetInfo{$_} );
   printf " %-35s%s\n", $_, $Val if defined $Val;
}
