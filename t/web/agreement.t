#!/usr/bin/perl

use strict;
use warnings;

use RT::Extension::NHD::Test tests => 18;
my $test = 'RT::Extension::NHD::Test';
use Digest::SHA1 qw(sha1_hex);

$test->started_ok;
my $m = $test->new_agent;
$m->login;

my $remote_url = 'http://hoster.example.com/sharing';

{
    $test->set_next_remote_response(201);

    $m->get_ok('/Admin/Tools/NHD/');
    $m->follow_link_ok({text => 'Create Agreement', url_regex => qr{/NHD/}});
    $m->form_name('CreateAgreement');
    $m->field( Name => 'Test' );
    $m->field( Receiver => $remote_url );
    $m->click( 'Create' );
}
