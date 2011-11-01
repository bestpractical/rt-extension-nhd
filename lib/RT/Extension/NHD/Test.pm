use strict;
use warnings;

### after: use lib qw(@RT_LIB_PATH@);
use lib qw(/opt/rt4/local/lib /opt/rt4/lib);

package RT::Extension::NHD::Test;
use base 'RT::Test';

my (@requests, @responses);

sub import {
    my $class = shift;
    my %args  = @_;

    $args{'requires'} ||= [];
    if ( $args{'testing'} ) {
        unshift @{ $args{'requires'} }, 'RT::Extension::NHD';
    } else {
        $args{'testing'} = 'RT::Extension::NHD';
    }

    $class->SUPER::import( %args );
    $class->export_to_level(1);

    no strict 'subs';
    *RT::Extension::NHD::SendRequest = sub {
        my $self = shift;
        push @requests, shift;
        return shift @responses;
    };
}

sub new_agent {
    my $self = shift;
    require RT::Extension::NHD::Test::Web;
    return  RT::Extension::NHD::Test::Web->new_agent( @_ );
}

sub remote_requests { return splice @requests }

sub set_next_remote_response {
    my $self = shift;
    my $code = shift;
    my %args = @_;

    my $msg = $args{'Message'} || $RT::Extension::NHD::HTTP_MESSAGE{ $code }
        || die "no message for code $code";

    my %headers = %{ $args{'Headers'} || {} };
    %headers = (
        %headers,
        'X-Ticket-Sharing-Version' => '1',
    );
    my $content = $args{'Data'};
    $content = RT::Extension::NHD->ToJSON( $content )
        if ref $content;
    push @responses, HTTP::Response->new(
        $code, $msg, [%headers], $content,
    );
}

1;
