use 5.008003;
use strict;
use warnings;

package RT::Extension::NHD;
our $VERSION = '0.01';

=head1 NAME

RT::Extension::NHD - Networked Help Desk protocol for Request Tracker

=head1 DESCRIPTION

=cut

use RT::NHD::Agreement;
use JSON::Any;

sub FromJSON {
    return JSON::Any->new->from_json( $_[1] );
}

sub ToJSON {
    return JSON::Any->new->to_json( $_[1] );
}

sub CheckUUID {
    my $self = shift;
    my $value = shift;

    return 0 unless $value && $value =~ /^[0-9a-f]{40}$/i;
    return 1;
}

my %HTTP_CODE = (
    'OK' => 200,
    'Created' => 201,

    'Bad Request' => 400,
    'Unauthorized' => 401,
    'Forbidden' => 403,
    'Not Found' => 404,
    'Method Not Allowed' => 405,
    'Precondition Failed' => 412,
    'Unprocessable Entity' => 422,
);

sub BadWebRequest {
    my $self = shift;
    my $info = shift || 'Bad Request';
    return $self->StopWebRequest( $info );
}

sub GoodWebRequest {
    my $self = shift;
    my $info = shift || 'OK';
    return $self->StopWebRequest( $info );
}

sub StopWebRequest {
    my $self = shift;
    my $info = shift;
    my $code = $HTTP_CODE{ $info } or die "Bad status $info";
    $HTML::Mason::Commands::r->headers_out->{'Status'} = "$code $info";
    if ( $code =~ /^2..$/ ) {
        $HTML::Mason::Commands::m->abort( $code );
    } else {
        $HTML::Mason::Commands::m->clear_and_abort( $code );
    }
}

my %METHOD_TO_ACTION = ( GET => 'show', POST => 'create', PUT => 'update' );
sub WebRequestAction {
    return $METHOD_TO_ACTION{ uc $HTML::Mason::Commands::r->method };
}

sub WebSendJSON {
    my $self = shift;
    my $data = shift;
    my $status = shift || 'OK';

    $HTML::Mason::Commands::r->content_type( "text/x-json; charset=UTF-8" );
    return $self->GoodWebRequest( $status );
}

=head1 AUTHOR

Ruslan Zakirov E<lt>ruz@bestpractical.comE<gt>

=head1 LICENSE

GPL version 2.

=cut

1;