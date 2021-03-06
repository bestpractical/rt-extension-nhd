#!/usr/bin/perl

use strict;
use warnings;

use RT::Extension::NetworkedHelpDesk::Test tests => 58;
my $test = 'RT::Extension::NetworkedHelpDesk::Test';

use Digest::SHA1 qw(sha1_hex);

use_ok 'RT::Extension::NetworkedHelpDesk';

{
    my $agreement = RT::NHD::Agreement->new( RT->SystemUser );
    isa_ok($agreement, 'RT::NHD::Agreement');
    isa_ok($agreement, 'RT::Record');
}

my $remote_url = 'http://hoster.example.com/sharing';
my $remote_user;
{
    $remote_user = RT::User->new( RT->SystemUser );
    my ($status, $msg) = $remote_user->Create(
        Name => $remote_url,
        Privileged => 0,
        Disabled => 0,
    );
    ok $status, "created an user";
}

my $i = 0;

{
    my $uuid = sha1_hex( ''. ++$i );

    my $agreement = RT::NHD::Agreement->new( RT::CurrentUser->new( $remote_user ) );
    my ($id, $msg) = $agreement->Create(
        UUID => $uuid,
        Name => 'Test Company',
        Status => 'pending',
        Sender => $remote_url,
        Receiver => RT->Config->Get('NHD_WebURL'),
        AccessKey => sha1_hex( ''. ++$i ),
    );
    ok($id, "Created an agreement $uuid");

    $agreement = RT::NHD::Agreement->new( RT->SystemUser );
    $agreement->Load( $uuid );
    ok( $agreement->id, 'loaded agreement' );

    is( $agreement->UUID, $uuid, 'correct value' );
    is( $agreement->Name, 'Test Company', 'correct value' );
    is( $agreement->Status, 'pending', 'correct value' );
    is( $agreement->Sender, $remote_url, 'correct value' );
    is( $agreement->Receiver, RT->Config->Get('NHD_WebURL'), 'correct value' );
    like( $agreement->AccessKey, qr{^[0-9a-f]{40}$}i, 'correct value' );

    ok !scalar $test->remote_requests, 'no outgoing requests';
}

# bad status
{
    my $agreement = RT::NHD::Agreement->new( RT::CurrentUser->new( $remote_user ) );
    my $uuid = sha1_hex( ''. ++$i );
    my ($id, $msg) = $agreement->Create(
        UUID => $uuid,
        Name => 'Test Company',
        Status => 'booo',
        Sender => $remote_url,
        Receiver => RT->Config->Get('NHD_WebURL'),
        AccessKey => sha1_hex( ''. ++$i ),
    );
    ok(!$id, "Couldn't create an agreement $uuid: $msg");
    ok !scalar $test->remote_requests, 'no outgoing requests';
}

# can only be created with pending status
{
    my $agreement = RT::NHD::Agreement->new( RT::CurrentUser->new( $remote_user ) );
    my $uuid = sha1_hex( ''. ++$i );
    my ($id, $msg) = $agreement->Create(
        UUID => $uuid,
        Name => 'Test Company',
        Status => 'accepted',
        Sender => $remote_url,
        Receiver => RT->Config->Get('NHD_WebURL'),
        AccessKey => sha1_hex( ''. ++$i ),
    );
    ok(!$id, "Couldn't create an agreement $uuid: $msg");
    ok !scalar $test->remote_requests, 'no outgoing requests';
}

# simple update by sender we are receiver
{
    my $agreement = RT::NHD::Agreement->new( RT::CurrentUser->new( $remote_user ) );
    my $uuid = sha1_hex( ''. ++$i );
    my ($id, $msg) = $agreement->Create(
        UUID => $uuid,
        Name => 'Test Company',
        Status => 'pending',
        Sender => $remote_url,
        Receiver => RT->Config->Get('NHD_WebURL'),
        AccessKey => sha1_hex( ''. ++$i ),
    );
    ok($id, "Created an agreement") or diag "error: $msg";

    (my $status, $msg) = $agreement->Update(
        Name => 'Correct Test Company',
        AccessKey => sha1_hex( ''. ++$i ),
    );
    ok $status, 'updated URL of the sender by sender';
    is( $agreement->Name, 'Correct Test Company', 'correct value' );
    is( $agreement->AccessKey, sha1_hex( ''. $i ), 'correct value' );
    ok !scalar $test->remote_requests, 'no outgoing requests';
}

# update with error
{
    my $agreement = RT::NHD::Agreement->new( RT::CurrentUser->new( $remote_user ) );
    my $uuid = sha1_hex( ''. ++$i );
    my ($id, $msg) = $agreement->Create(
        UUID => $uuid,
        Name => 'Test Company',
        Status => 'pending',
        Sender => $remote_url,
        Receiver => RT->Config->Get('NHD_WebURL'),
        AccessKey => sha1_hex( ''. ++$i ),
    );
    ok($id, "Created an agreement") or diag "error: $msg";

    (my $status, $msg) = $agreement->Update(
        Name => 'Correct Test Company',
        AccessKey => 'bad access key',
    );
    ok !$status, "updated failed: $msg";
    # make sure we're transactional
    is( $agreement->Name, 'Test Company', 'correct value' );
    is( $agreement->AccessKey, sha1_hex( ''. $i ), 'correct value' );
    ok !scalar $test->remote_requests, 'no outgoing requests';
}

# create with error
{
    my $agreement = RT::NHD::Agreement->new( RT::CurrentUser->new( $remote_user ) );
    my $uuid = sha1_hex( ''. ++$i );
    my ($id, $msg) = $agreement->Create(
        UUID => $uuid,
        Name => 'Test Company',
        Status => 'booo',
        Sender => $remote_url,
        Receiver => RT->Config->Get('NHD_WebURL'),
        AccessKey => sha1_hex( ''. ++$i ),
    );
    ok(!$id, "failed to create agreement");

    $agreement = RT::NHD::Agreement->new( RT->SystemUser );
    $agreement->Load($uuid);
    ok !$agreement->id, "no agreement in DB";
    ok !scalar $test->remote_requests, 'no outgoing requests';
}

# we are sending
{
    $test->set_next_remote_response(201);

    my $uuid = sha1_hex( ''. ++$i );

    my $agreement = RT::NHD::Agreement->new( RT->SystemUser );
    my ($id, $msg) = $agreement->Create(
        UUID => $uuid,
        Name => 'Test Company',
        Status => 'pending',
        Sender => RT->Config->Get('NHD_WebURL'),
        Receiver => $remote_url,
        AccessKey => sha1_hex( ''. ++$i ),
    );
    ok($id, "Created an agreement $uuid");

    $agreement = RT::NHD::Agreement->new( RT->SystemUser );
    $agreement->Load( $uuid );
    ok( $agreement->id, 'loaded agreement' );

    is( $agreement->UUID, $uuid, 'correct value' );
    is( $agreement->Name, 'Test Company', 'correct value' );
    is( $agreement->Status, 'pending', 'correct value' );
    is( $agreement->Receiver, $remote_url, 'correct value' );
    is( $agreement->Sender, RT->Config->Get('NHD_WebURL'), 'correct value' );
    like( $agreement->AccessKey, qr{^[0-9a-f]{40}$}i, 'correct value' );

    my @requests = $test->remote_requests;
    is scalar @requests, 1, 'one outgoing request';
    is $requests[0]->uri, "$remote_url/agreements/$uuid";
    is $requests[0]->method, "POST";
    is $requests[0]->header('X-Ticket-Sharing-Version'), 1;
    is $requests[0]->header('X-Ticket-Sharing-Token'),
        $agreement->UUID .':'. $agreement->AccessKey;
    is lc $requests[0]->header('Content-Type'), 'text/x-json; charset="utf-8"';
    is_deeply(
        RT::Extension::NetworkedHelpDesk->FromJSON( $requests[0]->content ),
        $agreement->ForJSON,
    );

    $test->set_next_remote_response(200);

    (my $status, $msg) = $agreement->Update(
        Name => 'Correct Test Company',
        AccessKey => sha1_hex( ''. ++$i ),
    );
    ok $status, 'updated URL of the sender by sender' or diag "error: $msg";
    is( $agreement->Name, 'Correct Test Company', 'correct value' );
    is( $agreement->AccessKey, sha1_hex( ''. $i ), 'correct value' );

    @requests = $test->remote_requests;
    is scalar @requests, 1, 'one outgoing request';
    is $requests[0]->uri, "$remote_url/agreements/$uuid";
    is $requests[0]->method, "PUT";
    is $requests[0]->header('X-Ticket-Sharing-Version'), 1;
    TODO: {
        local $TODO = "Updating access key doesn't work properly";
        is $requests[0]->header('X-Ticket-Sharing-Token'),
            $agreement->UUID .':'. sha1_hex( ''. ($i - 1) );
    };
    is lc $requests[0]->header('Content-Type'), 'text/x-json; charset="utf-8"';
    is_deeply(
        RT::Extension::NetworkedHelpDesk->FromJSON( $requests[0]->content ),
        $agreement->ForJSON( Fields => ['Name', 'AccessKey'] ),
    );
}

