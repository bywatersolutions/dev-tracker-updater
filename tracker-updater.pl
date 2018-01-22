#!/usr/bin/perl

use Modern::Perl;

use Try::Tiny;
use RT::Client::REST;
use BZ::Client::REST;
use JSON;
use Term::ANSIColor;
use Data::Dumper;
use Getopt::Long::Descriptive;

my ( $opt, $usage ) = describe_options(
    'tracker-updater.pl',
    [ "rt-url=s",      "BWS RT URL",      { required => 1 } ],
    [ "rt-username=s", "BWS RT username", { required => 1 } ],
    [ "rt-password=s", "BWS RT password", { required => 1 } ],
    [],
    [ "dev-url=s",      "BWS tracker URL",      { required => 1 } ],
    [ "dev-username=s", "BWS tracker username", { required => 1 } ],
    [ "dev-password=s", "BWS tracker password", { required => 1 } ],
    [],
    [ "community-url=s",      "Community tracker URL",      { required => 1 } ],
    [ "community-username=s", "Community tracker username", { required => 1 } ],
    [ "community-password=s", "Community tracker password", { required => 1 } ],
    [],
    [ 'verbose|v', "print extra stuff" ],
    [ 'help', "print usage message and exit", { shortcircuit => 1 } ],
);

print( $usage->text ), exit if $opt->help;

my $rt_url  = $opt->rt_url;
my $rt_user = $opt->rt_username;
my $rt_pass = $opt->rt_password;

my $bz_tracker_url  = $opt->dev_url;
my $bz_tracker_user = $opt->dev_username;
my $bz_tracker_pass = $opt->dev_password;

my $bz_koha_url  = $opt->community_url;
my $bz_koha_user = $opt->community_username;
my $bz_koha_pass = $opt->community_password;

my $tracker_client = BZ::Client::REST->new(
    {
        user     => $bz_tracker_user,
        password => $bz_tracker_pass,
        url      => $bz_tracker_url,
    }
);

my $koha_client = BZ::Client::REST->new(
    {
        user     => $bz_koha_user,
        password => $bz_koha_pass,
        url      => $bz_koha_url,
    }
);

my $rt = RT::Client::REST->new(
    server  => $rt_url,
    timeout => 30,
);
try {
    $rt->login( username => $rt_user, password => $rt_pass );
}
catch {
    die "problem logging in: ", shift->message;
};

# Create tracks
say colored( 'Creating Tracks', 'green' );
my $rt_query =
"Queue = 'Development' AND CF.{Workflow} LIKE 'In Development' AND 'CF.{Work to be done}' IS NOT NULL AND 'CF.{Dev Tracker}' IS NULL";
my @ids = $rt->search(
    type    => 'ticket',
    query   => $rt_query,
    orderby => '-id',
);

my @tickets_needing_tracks;

foreach my $id (@ids) {
    sleep(1);    # pause for 1 second between requests so we don't kill RT
    my $ticket = $rt->show( type => 'ticket', id => $id );
    $ticket->{id} = $id;
    push( @tickets_needing_tracks, $ticket );
    say "Found ticket: " . colored( $id, 'cyan' );
}

foreach my $t (@tickets_needing_tracks) {
    next if !$t->{'CF.{Work to be done}'};
    next if $t->{'CF.{Dev Tracker}'};

    my $product =
      $t->{'CF.{Development Type}'} eq 'LibKi'    # Mis-capitalized in RT
      ? 'Libki'
      : 'Koha';
    my $component =
        $t->{'CF.{Development Type}'} eq 'Koha'  ? 'General'
      : $t->{'CF.{Development Type}'} eq 'LibKi' ? 'General'
      :   $t->{'CF.{Development Type}'};
    my $version =
      $t->{'CF.{Development Type}'} eq 'LibKi'
      ? 'Libki 2'
      : 'unspecified';

    my $track_data = {
        product      => $product,
        component    => $component,
        version      => $version,
        assigned_to  => 'jesse@bywatersolutions.com',
        summary      => $t->{'Subject'},
        description  => $t->{'CF.{Work to be done}'},
        op_sys       => 'All',
        rep_platform => 'All',
        cf_rt_ticket => $t->{id},
        bug_status   => 'In Development'
    };

    my $track_id = $tracker_client->create_bug($track_data);
    say 'Created track: ' . colored( $track_id, 'green' );

    $rt->edit(
        type => 'ticket',
        id   => $t->{id},
        set  => { "CF.{Dev Tracker}" => $track_id }
    );
}

# Create Community Bugs
say colored( 'Creating Community Bugs', 'green' );
my $results = $koha_client->search_bugs( { status => 'In Development' } );

