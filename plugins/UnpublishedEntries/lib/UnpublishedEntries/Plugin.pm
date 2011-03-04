package UnpublishedEntries::Plugin;
use strict;

use MT;
use MT::Plugin;
use MT::Log;

use CGI;
use DBI;
use Data::Dumper;

#logging
use Log::Log4perl;

use constant MT_CONF_FILE => "/var/www/vhosts/gwiz/cgi-bin/mt/mt-config.cgi";

sub databaseConnect {

    my $config_file = MT_CONF_FILE;
    my $errMsg;
    my $conf_hashref;
    my ($db_user,$db_pwd,$database,$db_port);
    my ($key, $value);

    my $logger = MT::Log->get_logger();

    # Open MT comments database table
    if (! open (CONF, $config_file)) {
        $errMsg = "Can't open $config_file: $!\n";
        $errMsg .= "ENV:\n" . Dumper(%ENV) . "\n";
        $logger->fatal($errMsg);
        exit;
    }

    while (<CONF>) {
        next if (/^#/);
        chomp;
        ($key, $value) = split /\W+/, $_;
        $conf_hashref->{$key} = $value; 
    }
    close CONF;
    $db_user = $conf_hashref->{'DBUser'};
    $db_pwd = $conf_hashref->{'DBPassword'};
    $database = $conf_hashref->{'Database'};
    $db_port = $conf_hashref->{'DBPort'};

    return ($db_user,$db_pwd,$database,$db_port);
}
sub getUnpublished: {
    my $lastn = $_[0];
    my $blog_id = $_[1];
    my ($db_user,$db_pwd,$database,$db_port);
    my $dbh;
    my $errMsg;
    my $sql;
    my $sth;
    my $ra_results;
    my @entries;
    my $rh_row;
    my $col;

    my $logger = MT::Log->get_logger();

    # Database connection
    ($db_user,$db_pwd,$database,$db_port) = databaseConnect();
    $logger->debug("Connecting to db: dbi:Oracle:$database.gene.com:$db_port as $db_user\n");
    $dbh = DBI->connect("dbi:Oracle:$database.gene.com:$db_port", $db_user, $db_pwd);
    if (!$dbh) {
        $errMsg = "can't connect to database: $?\n";
        $logger->fatal($errMsg);
        exit;
    }

    $dbh->{LongReadLen} = 512 * 1024; #set this before our prepare so that we can fetch a clob from the db
    $dbh->{LongTruncOk} = 1;    ### We're happy to truncate any excess

    # Get list of desired entries
    $sql = getEntrySQL();

    $sth = $dbh->prepare($sql);
    $sth->bind_param( 1, $blog_id );
    $sth->bind_param( 2, $lastn );
    if (!$sth) {
        my $errMsg = "can't prepare query:\n\t$sql\n\t". $dbh->errstr;
        $logger->fatal($errMsg);
        exit;
    }
    $logger->debug("Prepared\n");
    if (! $sth->execute()) {
        my $errMsg = "Can't execute sql:\n\t$sql\n\t: ".$dbh->errstr;
        $logger->fatal($errMsg);
        exit;
    }
    $logger->debug("Executed\n");


    use Data::Dumper;
    # get all entries
    while ($rh_row = $sth->fetchrow_hashref()) {
        # $logger->debug("Row:\n\t" . Dumper($rh_row));
        my $rh_entry = {};
        push @entries, $rh_entry;
        foreach $col (keys %$rh_row) {
            $logger->debug("col $col\n");
            $rh_entry->{lc $col} = $rh_row->{$col};
        }
    }

    return @entries;
}

sub UnpublishedEntries {
    my ($ctx, $args, $cond) = @_;
    my $out = "";
    my @unpublishedEntries;
    my $rh_entry;
    my $res = '';
    my $builder = $ctx->stash('builder');
    my $tokens = $ctx->stash('tokens');
    my $entry_id;
    my $lastn = $args->{lastn};
    my $blog_id = $args->{blog_id};

    my $logger = MT::Log->get_logger();
    $logger->debug("lastn=".$lastn . "\n");
    @unpublishedEntries = getUnpublished($lastn,$blog_id);

    my $obj_type = 'entry';
    my $class = "MT::\u$obj_type";
    foreach $rh_entry (@unpublishedEntries) {
        $entry_id = $rh_entry->{entry_id};
        $logger->info("Fetching entry for entry_id: $entry_id\n");
        if (my $temp_obj = $class->load($entry_id)) {
            $ctx->stash($obj_type, $temp_obj);
            defined(my $out = $builder->build($ctx, $tokens))
                or return $ctx->error($builder->errstr);
            $res .= $out;
        } else {
            # $_->remove;
        }
    }
    use Data::Dumper;
    $logger->debug(Dumper($res) . "\n");
    $res;
}

sub getEntrySQL {

    my $sql;
    my $logger = MT::Log->get_logger();

    $sql =
<<"ENTRY_SQL";
SELECT 
  A.ENTRY_ID, 
  A.ENTRY_AUTHORED_ON
FROM 
  (SELECT e.entry_id, e.entry_authored_on
  FROM mt_entry e
  WHERE e.entry_blog_id = ?
  ORDER BY E.ENTRY_AUTHORED_ON DESC ) A
WHERE ROWNUM <= ?
ENTRY_SQL
    
    return $sql;
} # End get_entry_sql

#main: {
#    print getDbConf();
#    print "\n";
#}

1;
