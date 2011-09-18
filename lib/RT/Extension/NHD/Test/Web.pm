use strict;
use warnings;

package RT::Extension::NHD::Test::Web;
use base qw(RT::Test::Web);

require RT::Extension::NHD::Test;
require Test::More;

sub new_agent {
    my $self = shift;

    my $res = $self->new;
    require HTTP::Cookies;
    $res->cookie_jar( HTTP::Cookies->new );
    return $res;
}

sub json_request {
    my $self = shift;
    my ($method, $uri, %args) = @_;
    $uri = $self->rt_base_url .'NoAuth/NHD/1.0'. $uri;
    my $data;
    $data = RT::Extension::NHD->ToJSON( delete $args{'data'} )
        unless $method eq 'GET';
    my %headers = %{ $args{'headers'}||{}};
    %headers = (
        %headers,
        'X-Ticket-Sharing-Version' => '1',
    );
    my $request = HTTP::Request->new( $method, $uri, [%headers], $data );
    return $self->request( $request );
}

1;