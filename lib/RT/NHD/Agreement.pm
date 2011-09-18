use strict;
use warnings;

package RT::NHD::Agreement;
use base 'RT::Record';

use RT::NHD::Agreements;

our @STATUSES = qw(pending accepted declined inactive);

sub Table {'NHDAgreements'}

sub Load {
    my $self = shift;
    my $value = shift;
    if ( $value && $value =~ /^[0-9a-f]{40}$/i ) {
        return $self->LoadByCols( @_, UUID => $value );
    }
    return $self->SUPER::Load( $value, @_ );
}

sub ValidateUUID { return RT::Extension::NHD->CheckUUID( $_[1] ) }
sub ValidateAccessKey { return RT::Extension::NHD->CheckUUID( $_[1] ) }

sub ValidateStatus {
    my $self = shift;
    my $value = shift;

    return 0 unless $value;
    return 0 unless grep $_ eq lc $value, @STATUSES;
    return 1;
}

sub ValidateSender { return (shift)->_ValidateURI( @_ ) }
sub ValidateReceiver { return (shift)->_ValidateURI( @_ ) }

sub _ValidateURI {
    my $self = shift;
    my $value = shift;

    return 0 unless $value;
    return 0 unless URI->new( $value );
    return 1;
}

sub FromJSON {
    my $self = shift;
    my ($args) = @_;

    return {
        UUID => $args->{'uuid'},
        Name => $args->{'name'},
        Status => $args->{'status'},
        Sender => $args->{'sender_url'},
        Receiver => $args->{'receiver_url'},
        AccessKey => $args->{'access_key'},
    };
}

sub ForJSON {
    my $self = shift;
    return {
        uuid => $self->UUID,
        name => $self->Name,
        status => $self->Status,
        sender_url => $self->Sender,
        receiver_url => $self->Receiver,
        access_key => $self->AccessKey,
    };
}

sub _CoreAccessible { return {
    id =>
    { read => 1, sql_type => 4, length => 11, is_blob => 0, is_numeric => 1, type => 'int(11)' },
    UUID =>
    {read => 1, write => 0, sql_type => 12, length => 40, is_blob => 0, is_numeric => 0, type => 'varchar(40)', default => ''},
    Name =>
    {read => 1, write => 1, sql_type => 12, length => 200, is_blob => 0, is_numeric => 0, type => 'varchar(200)', default => ''},
    Status =>
    {read => 1, write => 1, sql_type => 12, length => 64, is_blob => 0, is_numeric => 0, type => 'varchar(64)', default => ''},
    Sender =>
    {read => 1, write => 1, sql_type => 12, length => 240, is_blob => 0, is_numeric => 0, type => 'varchar(240)', default => ''},
    Receiver =>
    {read => 1, write => 1, sql_type => 12, length => 240, is_blob => 0, is_numeric => 0, type => 'varchar(240)', default => ''},
    AccessKey =>
    {read => 1, write => 1, sql_type => 12, length => 40, is_blob => 0, is_numeric => 0, type => 'varchar(40)', default => ''},
} }

RT::Base->_ImportOverlays();

1;
