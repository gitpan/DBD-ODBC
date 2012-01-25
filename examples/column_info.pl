# $Id$
# column_info
use DBI;
use strict;
use warnings;

my $h = DBI->connect;

eval {$h->do(q{drop table martin})};

my $table = << 'EOT';
create table martin (a int default NULL,
                     b int default 1,
                     c char(20) default 'fred',
                     d varchar(30) default current_user,
                     e int)
EOT

$h->do($table);

DBI::dump_results($h->column_info(undef, undef, 'martin', undef));

