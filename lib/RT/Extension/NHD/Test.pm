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

1;
