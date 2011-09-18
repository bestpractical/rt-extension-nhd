use strict;
use warnings;

### after: use lib qw(@RT_LIB_PATH@);
use lib qw(/opt/rt4/local/lib /opt/rt4/lib);

package RT::Extension::NHD::Test;
use base 'RT::Test';

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
}

sub new_agent {
    my $self = shift;
    require RT::Extension::NHD::Test::Web;
    return  RT::Extension::NHD::Test::Web->new_agent( @_ );
}

1;
