#!/usr/bin/perl

use strict;
use warnings;

use RT::Extension::NHD::Test tests => 18;
my $test = 'RT::Extension::NHD::Test';
use Digest::SHA1 qw(sha1_hex);

my $org = 'Cool Company Sharing Tickets';
RT->Config->Set(NHD_Name => $org);

$test->started_ok;
my $m = $test->new_agent;
$m->login;

my $remote_url = 'http://hoster.example.com/sharing';

{
    $test->set_next_remote_response(201);

    $m->get_ok('/Admin/Tools/NHD/');
    $m->follow_link_ok({text => 'Create Agreement', url_regex => qr{/NHD/}});
    $m->form_name('CreateAgreement');
    $m->field( Name => 'Evil Hosting We Use' );
    $m->field( Receiver => $remote_url );
    $m->click( 'Create' );

    my $agreement = last_agreement();
    ok( $agreement && $agreement->id, 'loaded agreement' );
    is $agreement->Name, 'Evil Hosting We Use';
    is $agreement->ForJSON->{name}, $org;

    my @requests = $test->remote_requests;
    is scalar @requests, 1, 'one outgoing request';
    is $requests[0]->uri, "$remote_url/agreements/". $agreement->UUID;
    is $requests[0]->method, "POST";
    is $requests[0]->header('X-Ticket-Sharing-Version'), 1;
    is $requests[0]->header('X-Ticket-Sharing-Token'),
        $agreement->UUID .':'. $agreement->AccessKey;
    is lc $requests[0]->header('Content-Type'), 'text/x-json; charset="utf-8"';
    is_deeply(
        RT::Extension::NHD->FromJSON( $requests[0]->content ),
        $agreement->ForJSON,
    );
}

sub last_agreement {
    my $agreements = RT::NHD::Agreements->new( RT->SystemUser );
    $agreements->UnLimit;
    $agreements->OrderBy(FIELD => 'id', ORDER => 'DESC');
    return $agreements->First;
}
