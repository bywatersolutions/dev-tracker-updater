#!/usr/bin/env perl

use Modern::Perl;

use BZ::Client::REST;
use Carp::Always;
use Data::Dumper;
use Getopt::Long::Descriptive;
use JSON qw(to_json);
use LWP::UserAgent;
use RT::Client::REST;
use Term::ANSIColor;
use Try::Tiny;

my ( $opt, $usage ) = describe_options(
    'tracker-updater.pl',
    [ "rt-url=s",      "BWS RT URL",      { required => 1, default => $ENV{RT_URL} } ],
    [ "rt-username=s", "BWS RT username", { required => 1, default => $ENV{RT_USER} } ],
    [ "rt-password=s", "BWS RT password", { required => 1, default => $ENV{RT_PW} } ],
    [],
    [ "dev-url=s",      "BWS tracker URL",      { required => 1, default => $ENV{BWS_URL} } ],
    [ "dev-username=s", "BWS tracker username", { required => 1, default => $ENV{BWS_USER} } ],
    [ "dev-password=s", "BWS tracker password", { required => 1, default => $ENV{BWS_PW} } ],
    [],
    [ "community-url=s",      "Community tracker URL",      { required => 1, default => $ENV{KOHA_URL} } ],
    [ "community-username=s", "Community tracker username", { required => 1, default => $ENV{KOHA_USER} } ],
    [ "community-password=s", "Community tracker password", { required => 1, default => $ENV{KOHA_PW} } ],
    [],
    [ "action|a=s",    "Optional action to perform ( create-track )" ],
    [ "bug|b=s",       "Bug to perform action on" ],
    [ "dev-track|d=s", "Track to perform action on" ],
    [ "ticket|t=s",    "RT Ticket to perform action on" ],
    [],
    [ 'slack|s=s', "Slack webhook URL", { required => 1, default => $ENV{SLACK_URL} } ],
    [],
    [ "force|f", "Get pushy" ],
    [ 'verbose|v+', "Print extra stuff", { required => 1, default => 0 } ],
    [ 'help|h', "Print usage message and exit", { shortcircuit => 1 } ],
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

my $ua = LWP::UserAgent->new;
$ua->post(
    $opt->slack,
    Content_Type => 'application/json',
    Content => to_json( { text => "Running dev tracker updater!" } ),
) if $opt->slack;

if ( $opt->action ) {
    if ( $opt->action eq 'create-track' ) {
        my $bug_id = $opt->bug;

        my $results =
          $tracker_client->search_bugs( { cf_community_bug => $bug_id } );
        my $track_id;
        foreach my $r (@$results) {
            if ( $r->{status} ne 'RESOLVED' ) {
                $track_id = $r->{id};
                last;
            }
        }

        if ( $track_id && !$opt->force ) {
            say 'Track '
              . colored( $track_id, 'red' )
              . ' already exists for bug '
              . colored( $bug_id, 'cyan' );

        }
        else {
            my $bug = $koha_client->get_bug($bug_id);

            my $track_data = {
                product             => 'Koha',
                component           => 'General',
                version             => 'unspecified',
                assigned_to         => $bz_tracker_user,
                summary             => $bug->{summary},
                op_sys              => 'All',
                rep_platform        => 'All',
                cf_community_bug    => $bug_id,
                cf_community_status => $bug->{status},
                bug_status          => 'Submitted to Community',
            };

            my $track_id = $tracker_client->create_bug($track_data);

            say 'Created track '
              . colored( $track_id, 'green' )
              . ' for bug '
              . colored( $bug_id, 'cyan' );

            $ua->post(
                $opt->slack,
                Content_Type => 'application/json',
                Content => to_json( { text => "Created <$bz_tracker_url/show_bug.cgi?id=$track_id|Track $track_id> for <$bz_koha_url/show_bug.cgi?id=$bug_id|Bug $bug_id>" } ),
            ) if $opt->slack;
        }
    }
    exit 0;
}

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
        bug_status   => 'Ready for Development'
    };

    my $track_id = $tracker_client->create_bug($track_data);
    say 'Created track: ' . colored( $track_id, 'green' );

    $ua->post(
        $opt->slack,
        Content_Type => 'application/json',
        Content => to_json( { text => "Created <$bz_tracker_url/show_bug.cgi?id=$track_id|Track $track_id> for <$rt_url/Ticket/Display.html?id=$t->{id}|Ticket $t->{id}>" } ),
    ) if $opt->slack;

    $rt->edit(
        type => 'ticket',
        id   => $t->{id},
        set  => { "CF.{Dev Tracker}" => $track_id }
    );
}

# Update tracks from community bugs
say colored( 'Updating Tracks from Community Bugs', 'green' );
my $results = $tracker_client->search_bugs(
    {
        status => [
            'Submitted to Community',
            'In Development',
            'Ready for Development',
        ]
    }
);
foreach my $track ( @$results ) {
    next if $track->{component} eq 'Plugin'; # Plugins exist outside community process
    next if $track->{product} ne 'Koha'; # Community process is only used for Koha
    $track->{cf_community_bug}    ||= q{};
    $track->{cf_koha_version}     ||= q{};
    $track->{cf_community_status} ||= q{};

    ( $track->{cf_community_bug} ) = split( / /, $track->{cf_community_bug} ); # Only use leftmost bug if multiple bugs are associated with track

    next unless $track->{cf_community_bug};

    say "Found track: " . colored( $track->{id}, 'cyan' ) if $opt->verbose;

    my $bug = $koha_client->get_bug( $track->{cf_community_bug} );
    say "Bug data: " . Data::Dumper::Dumper( $bug ) if $opt->verbose > 2;
    $bug->{status} ||= q{};

    if ( $track->{cf_community_status} ne $bug->{status} ) {
        $tracker_client->update_bug( $track->{id}, { cf_community_status => $bug->{status} } );

        my $json_data = {
            "attachments" => [
                {
                    title => "Updated <$bz_tracker_url/show_bug.cgi?id=$track->{id}|Track $track->{id}>",
                    #pretext => "Pretext _supports_ mrkdwn",
                    text => "<$bz_koha_url/show_bug.cgi?id=$bug->{id}|Boog $bug->{id}: $bug->{summary}>",
                    fields => [
                        {
                            title => "From",
                            value => $track->{cf_community_status},
                            short => JSON::true,
                        },
                        {
                            title => "To",
                            value => $bug->{status},
                            short => JSON::true,
                        }
                    ],
                    mrkdwn_in => [ "text", "pretext", "fields" ],
                }
            ]
        };
        my $json_text = to_json( $json_data );

        say 'Updated track ' . colored( $track->{id}, 'cyan' ) . ': ' . colored( $track->{cf_community_status}, 'red' ) . ' => ' . colored( $bug->{status}, 'green' );
        $ua->post(
            $opt->slack,
            Content_Type => 'application/json',
            Content      => $json_text,
        ) if $opt->slack;
    }

    my @tickets = split( / /, $track->{cf_rt_ticket} );
    foreach my $ticket (@tickets) {
	next unless $ticket;

	say "Updating ticket " . colored( $ticket, 'magenta' ) . " for track " . colored( $track->{id}, 'cyan' ) if $opt->verbose > 1;

        try {
            $rt->edit(
                type => 'ticket',
                id   => $ticket,
                set  => {
                    "CF.{Community Status}" => $track->{cf_community_status},
                }
            );
        };

        try {
            $rt->edit(
                type => 'ticket',
                id   => $ticket,
                set  => {
                    "CF.{Koha Version}" => $track->{cf_koha_version},
                }
            );
        };

        try {
            $rt->edit(
                type => 'ticket',
                id   => $ticket,
                set  => {
                    "CF.{Dev Tracker}" => $track->{id},
                }
            );
        }
    };

    sleep(5);    # pause for 10 second between requests so we don't kill RT and/or Bugzilla
}

$ua->post(
    $opt->slack,
    Content_Type => 'application/json',
    Content => to_json( { text => "Dev tracker updater has finished running!" } ),
) if $opt->slack;
say colored( 'Finished!', 'green' );
