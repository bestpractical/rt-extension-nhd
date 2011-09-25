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
    if ( RT::Extension::NHD->CheckUUID($value) ) {
        return $self->LoadByCols( @_, UUID => $value );
    }
    return $self->SUPER::Load( $value, @_ );
}

sub Create {
    my $self = shift;
    my %args = @_;

    unless ( ($args{'Status'}||'') eq 'pending' ) {
        return (undef, "New agreement must have 'pending' status");
    }
    my $our_url = RT->Config->Get('NHD_WebURL');
    if ( ($args{'Sender'}||'') ne $our_url && ($args{'Receiver'}||'') ne $our_url ) {
        return (undef, "Either sender or receiver should be '$our_url'");
    }
    return $self->SUPER::Create( %args );
}

sub Update {
    my $self = shift;
    my $by = shift;
    my %args = @_;

    unless ( $by eq 'Receiver' || $by eq 'Sender' ) {
        return (0, "First argument should be either 'Sender' or 'Receiver'");
    }

    # filter out repeated values even if spec says update should only
    # enlist new values
    foreach my $field ( grep $_ ne 'id', keys %{ $self->TableAttributes } ) {
        next unless exists $args{ $field };

        my $cur = $self->$field();
        my $new = $args{ $field };
        next if (defined $new && !defined $cur)
            || (!defined $new && defined $cur)
            || $new ne $cur;

        delete $args{ $field };
    }

    return (0, 'UUID can not be changed') if exists $args{'UUID'};

    if ( $by eq 'Sender' ) {
        return (0, 'Only receiver may change its URL')
            if exists $args{'Receiver'};
    } else {
        return (0, 'Only sender may change Name')
            if exists $args{'Name'};
        return (0, 'Only sender may change its URL')
            if exists $args{'Sender'};
    }

    if ( exists $args{'Status'} ) {
        my $cur = $self->Status;
        my $new = $args{'Status'} || '';

        # XXX: not yet implemented
    }

    if ( exists $args{'DeactivatedBy'} ) {
        return (0, 'DeactivatedBy can be changed only with Status')
            unless exists $args{'Status'};

        if ( $args{'Status'} eq 'inactive' ) {
            return (0, "Inactivating agreement, DeactivatedBy should be \L$by")
                unless lc $args{'DeactivatedBy'} eq lc $by;
        }
        elsif ( $self->Status eq 'inactive' ) {
            return (0, "Re-activating agreement, DeactivatedBy should be set to empty")
                if $args{'DeactivatedBy'};
        }
        else {
            return (0, "Can not set DeactivatedBy when change status from '". $self->Status ."' to '$args{'Status'}'");
        }
    }


    $RT::Handle->BeginTransaction;
    foreach my $field ( grep $_ ne 'id', keys %{ $self->TableAttributes } ) {
        next unless exists $args{ $field };

        my $method = "Set$field";
        my ($status, $msg) = $self->$method( $args{ $field } );
        return $self->RollbackTransaction( "Couldn't update $field: $msg" )
            unless $status;
    }
    $RT::Handle->Commit;
    return (1, 'Updated');
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

sub ValidateDeactivatedBy {
    my $self = shift;
    my $value = shift;

    return 1 unless $value;
    return 0 unless grep $_ eq lc $value, 'sender', 'receiver';
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
        DeactivatedBy => $args->{'deactivated_by'},
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
        deactivated_by => $self->DeactivatedBy,
    };
}

sub TableAttributes {
    my $self = shift;
    my $class = ref($self) || $self;
    $self->_BuildTableAttributes unless $RT::Record::_TABLE_ATTR->{ $class };
    return $RT::Record::_TABLE_ATTR->{ $class };
}

sub RollbackTransaction {
    my $self = shift;
    my $msg = shift;

    $RT::Handle->Rollback;

    $self->LoadByCols( id => $self->id );

    return (0, $msg);
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
    DeactivatedBy =>
    {read => 1, write => 1, sql_type => 10, length => 15, is_blob => 0, is_numeric => 0, type => 'varchar(10)', default => ''},
} }

RT::Base->_ImportOverlays();

1;
