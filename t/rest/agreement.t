#!/usr/bin/perl

use strict;
use warnings;

use RT::Extension::NHD::Test tests => 18;
use Digest::SHA1 qw(sha1_hex);

RT::Extension::NHD::Test->started_ok;

my $m = RT::Extension::NHD::Test->new_agent;

my $i = 0;
{
    my $uuid = sha1_hex( ''. ++$i );
    my $access_key = sha1_hex( ''. ++$i );

    my $response = $m->json_request(
        POST => '/agreements/'. $uuid,
        Headers => {
            'X-Ticket-Sharing-Token' => "$uuid:$access_key",
        },
        Data => {
            uuid => $uuid,
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
    $agreement->Load( $uuid );
    ok( $agreement->id, 'loaded agreement' );

    is( $agreement->UUID, $uuid, 'correct value' );
    is( $agreement->Name, 'Test Company', 'correct value' );
    is( $agreement->Status, 'pending', 'correct value' );
    is( $agreement->Sender, 'http://hoster.example.com/sharing', 'correct value' );
    is( $agreement->Receiver, RT->Config->Get('NHD_WebURL'), 'correct value' );
    like( $agreement->AccessKey, qr{^[0-9a-f]{40}$}i, 'correct value' );

    $response = $m->json_request( GET => '/agreements/'. $uuid );
    is( $response->code, 401, 'auth required' );
    like(
        $response->header('WWW-Authenticate'),
        qr/\bX-Ticket-Sharing\b/,
        'WWW-Authenticate header is there'
    );

    $response = $m->json_request(
        GET => '/agreements/'. $uuid,
        Headers => {
            'X-Ticket-Sharing-Token' => "$uuid:$access_key",
        },
    );
    is( $response->code, 200, 'got agreement' );
    is_deeply(
        RT::Extension::NHD->FromJSON( $response->content ),
        {
            uuid => $uuid,
            name => 'Test Company',
            status => 'pending',
            sender_url => 'http://hoster.example.com/sharing',
            receiver_url => RT->Config->Get('NHD_WebURL'),
            access_key => $access_key,
        },
        'correct agreement',
    );
}
