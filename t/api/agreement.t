#!/usr/bin/perl

use strict;
use warnings;

use RT::Extension::NHD::Test tests => 25;
use Digest::SHA1 qw(sha1_hex);

{
    my $agreement = RT::NHD::Agreement->new( RT->SystemUser );
    isa_ok($agreement, 'RT::NHD::Agreement');
    isa_ok($agreement, 'RT::Record');
}

my $i = 0;

{
    my $uuid = sha1_hex( ''. ++$i );

    my $agreement = RT::NHD::Agreement->new( RT->SystemUser );
    my ($id, $msg) = $agreement->Create(
        UUID => $uuid,
        Name => 'Test Company',
        Status => 'pending',
        Sender => 'http://hoster.example.com/sharing',
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
    is( $agreement->Sender, 'http://hoster.example.com/sharing', 'correct value' );
    is( $agreement->Receiver, RT->Config->Get('NHD_WebURL'), 'correct value' );
    like( $agreement->AccessKey, qr{^[0-9a-f]{40}$}i, 'correct value' );
}

# bad status
{
    my $agreement = RT::NHD::Agreement->new( RT->SystemUser );
    my $uuid = sha1_hex( ''. ++$i );
    my ($id, $msg) = $agreement->Create(
        UUID => $uuid,
        Name => 'Test Company',
        Status => 'booo',
        Sender => 'http://hoster.example.com/sharing',
        Receiver => RT->Config->Get('NHD_WebURL'),
        AccessKey => sha1_hex( ''. ++$i ),
    );
    ok(!$id, "Couldn't create an agreement $uuid: $msg");
}

# can only be created with pending status
{
    my $agreement = RT::NHD::Agreement->new( RT->SystemUser );
    my $uuid = sha1_hex( ''. ++$i );
    my ($id, $msg) = $agreement->Create(
        UUID => $uuid,
        Name => 'Test Company',
        Status => 'accepted',
        Sender => 'http://hoster.example.com/sharing',
        Receiver => RT->Config->Get('NHD_WebURL'),
        AccessKey => sha1_hex( ''. ++$i ),
    );
    ok(!$id, "Couldn't create an agreement $uuid: $msg");
}

