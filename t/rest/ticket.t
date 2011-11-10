#!/usr/bin/perl

use strict;
use warnings;

use RT::Extension::NetworkedHelpDesk::Test tests => 13;
my $test = 'RT::Extension::NetworkedHelpDesk::Test';
use Digest::SHA1 qw(sha1_hex);

BEGIN { $ENV{TZ} = 'GMT' };
RT->Config->Set('Timezone' => 'GMT');

$test->started_ok;

my $m = $test->new_agent;

my $queue = RT::Test->load_or_create_queue( Name => 'General' );

my $i = 0;
my $auuid = sha1_hex( ''. ++$i );
my $access_key = sha1_hex( ''. ++$i );

{
    my $response = $m->json_request(
        POST => '/agreements/'. $auuid,
        Headers => {
            'X-Ticket-Sharing-Token' => "$auuid:$access_key",
        },
        Data => {
            uuid => $auuid,
            name => 'Test Company',
            status => 'pending',
            sender_url => 'http://hoster.example.com/sharing',
            receiver_url => RT->Config->Get('NHD_WebURL'),
            access_key => $access_key,
        },
    );
    is( $response->code, 201, 'created' );

    DBIx::SearchBuilder::Record::Cachable::FlushCache();
    my $agreement = RT::NHD::Agreement->new( RT->SystemUser );
    $agreement->Load( $auuid );
    ok( $agreement->id, 'loaded agreement' );

    $test->set_next_remote_response(200);

    my ($status, $msg) = $agreement->Update( Queue => $queue->id, Status => 'accepted' );
    ok $status, "accepted agreement" or diag "error: $msg";
}

{
    my $uuid = sha1_hex( ''. ++$i );
    my $response = $m->json_request(
        POST => '/tickets/'. $uuid,
        Headers => {
            'X-Ticket-Sharing-Token' => "$auuid:$access_key",
        },
        Data => {
            uuid => $uuid,
            subject => 'test ticket',
            requested_at => "2010-11-24 14:13:54 -0800",
            status => 'open',
            requester => {
                uuid => sha1_hex( ''. ++$i ),
                name => 'John Doe',
            },
        },
    );
    is( $response->code, 201, 'created' );

    my $ticket = $test->last_ticket;
    ok $ticket && $ticket->id, 'created a ticket';
    is $ticket->Subject, 'test ticket';
    is $ticket->Status, 'open';

    $response = $m->json_request(
        PUT => '/tickets/'. $uuid,
        Headers => {
            'X-Ticket-Sharing-Token' => "$auuid:$access_key",
        },
        Data => {
            uuid => $uuid,
            subject => 'another test ticket',
            status => 'pending',
        },
    );
    is( $response->code, 200, 'updated' );

    my $ticket = $test->last_ticket;
    ok $ticket && $ticket->id, 'created a ticket';
    is $ticket->Subject, 'another test ticket';
    is $ticket->Status, 'stalled';

    $response = $m->json_request(
        GET => '/tickets/'. $uuid,
        Headers => {
            'X-Ticket-Sharing-Token' => "$auuid:$access_key",
        },
    );

    diag $response->content;
    my $json = RT::Extension::NetworkedHelpDesk->FromJSON( $response->content );
    is_deeply(
        $json,
        {
            uuid => $uuid,
            subject => 'test ticket',
            requested_at => "2010-11-24 22:13:54 +0000",
            status => 'open',
            requester => {
                uuid => sha1_hex( ''. $i ),
                name => 'John Doe',
            },
        },
    );
}

