use strict;
use warnings;

package RT::NHD::Agreements;
use base 'RT::SearchBuilder';

use RT::NHD::Agreement;

sub Table { 'NHDAgreements' }

sub NewItem {
    my $self = shift;
    return RT::NHD::Agreement->new( $self->CurrentUser );
}

RT::Base->_ImportOverlays();

1;
