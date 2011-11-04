use 5.008003;
use strict;
use warnings;

package RT::Extension::NetworkedHelpDesk;
our $VERSION = '0.01';

=head1 NAME

RT::Extension::NetworkedHelpDesk - Networked Help Desk protocol for Request Tracker

=head1 DESCRIPTION

=cut

use RT::NHD::Agreements;
use JSON::Any;
use LWP::UserAgent;
use HTTP::Request;

sub ProcessRequest {
    my $self = shift;
    my %args = @_;

    my ($object, $action, $data) = @args{qw(Object Action Data)};
    if ( $object->id ) {
        if ( $action eq 'show' ) {
            return $self->WebSendJSON( $object->ForJSON );
        }
        elsif ( $action eq 'update' ) {
            my ($status, $msg) = $object->Update( %$data );
            unless ( $status ) {
                RT->Logger->error("Couldn't update ". ref($object) .": $msg");
                return $self->BadWebRequest('Unprocessable Entity');
            }
            return $self->GoodWebRequest;
        }
    }
    else {
        my ($status, $msg) = $object->Create( %$data );
        unless ( $status ) {
            RT->Logger->error("Couldn't create ". ref($object) .": $msg");
            return $self->BadWebRequest('Unprocessable Entity');
        }
        return $self->GoodWebRequest('Created');
    }
    return $self->BadWebRequest;
}

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

sub JSONRequest {
    my $self = shift;
    my ($method, $uri, %args) = @_;

    my $data;
    $data = RT::Extension::NetworkedHelpDesk->ToJSON( delete $args{'Data'} )
        unless uc($method) eq 'GET';
    my %headers = %{ delete $args{'Headers'} || {} };
    %headers = (
        'X-Ticket-Sharing-Version' => '1',
        'Content-Type' => 'text/x-json; charset="UTF-8"',
        %headers,
    );
    my $request = HTTP::Request->new( $method, $uri, [%headers], $data );
    return $self->SendRequest( $request );
}

sub SendRequest {
    my $self = shift;
    return LWP::UserAgent->new->request( shift );
}

our %HTTP_CODE = (
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
our %HTTP_MESSAGE = reverse %HTTP_CODE;

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

    my $r = $HTML::Mason::Commands::r;
    $r->headers_out->{'Status'} = "$code $info";
    if ( $code == 401 ) {
        $r->headers_out->{'WWW-Authenticate'} = 'X-Ticket-Sharing';
    }

    if ( $code =~ /^2..$/ ) {
        $HTML::Mason::Commands::m->abort( $code );
    } else {
        $HTML::Mason::Commands::m->clear_and_abort( $code );
    }
}

my %METHOD_TO_ACTION = ( GET => 'show', POST => 'create', PUT => 'update' );
my %ACTION_TO_METHOD = reverse %METHOD_TO_ACTION;
sub ActionToWebMethod { return $ACTION_TO_METHOD{ lc $_[1] } };
sub WebRequestAction {
    return $METHOD_TO_ACTION{ uc $HTML::Mason::Commands::r->method };
}

sub WebSendJSON {
    my $self = shift;
    my $data = shift;
    my $status = shift || 'OK';

    $HTML::Mason::Commands::r->content_type( "text/x-json; charset=UTF-8" );
    $HTML::Mason::Commands::m->out( $self->ToJSON( $data ) ) if $data;
    return $self->GoodWebRequest( $status );
}

=head1 AUTHOR

Ruslan Zakirov E<lt>ruz@bestpractical.comE<gt>

=head1 LICENSE

GPL version 2.

=cut

1;