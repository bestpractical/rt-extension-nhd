use strict;
use warnings;

package RT::NHD::Agreements;
use base 'RT::SearchBuilder';

use RT::NHD::Agreement;

sub Table { 'NHDAgreements' }

RT::Base->_ImportOverlays();

1;
