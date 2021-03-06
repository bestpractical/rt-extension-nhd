use strict;
use warnings;

package RT::NHD::Agreement;
use base 'RT::Record';

use RT::NHD::Agreements;
use Digest::SHA1 qw(sha1_hex);

our @STATUSES = qw(pending accepted declined inactive);

sub Table {'NHDAgreements'}

sub Load {
    my $self = shift;
    my $value = shift;
    if ( RT::Extension::NetworkedHelpDesk->CheckUUID($value) ) {
        return $self->LoadByCols( @_, UUID => $value );
    }
    return $self->SUPER::Load( $value, @_ );
}

sub Create {
    my $self = shift;
    my %args = @_;

    my $we_are = $self->WhoWeAre( %args );
    unless ( $we_are ) {
        return (undef, "Either sender or receiver should be '". RT->Config->Get('NHD_WebURL') ."'");
    }

    my $by = $self->WhoIsCurrentUser( %args );
    unless ( $by ) {
        return (0, "Current user is not a sender or receiver");
    }

    if ( $we_are eq 'Sender' ) {
        $args{'AccessKey'} ||= sha1_hex(join '',
            @args{qw(Sender Receiver Name)},
            $$, rand(1),
        );

        $args{'UUID'} ||= sha1_hex(join '', @args{qw(AccessKey Sender Receiver Name)});
    }

    $args{'Status'} ||= 'pending';
    unless ( $args{'Status'} eq 'pending' ) {
        return (undef, "New agreement must have 'pending' status");
    }

    $RT::Handle->BeginTransaction;

    my @rv = $self->SUPER::Create( %args );
    return $self->RollbackTransaction( "Couldn't create agreement record: $rv[1]" )
        unless $rv[0];

    if ( $we_are eq $by ) {
        my ($status, $msg) = $self->Send( 'create' );
        return $self->RollbackTransaction( "Couldn't send update to remote host: $msg" )
            unless $status;
    }

    $RT::Handle->Commit;

    return @rv;
}

sub Update {
    my $self = shift;
    my %args = @_;

    my $by = $self->WhoIsCurrentUser;
    unless ( $by ) {
        return (0, "Current user is not a sender or reciever");
    }

    my $we_are = $self->WhoWeAre;

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
    if ( $by eq $we_are ) {
        my ($status, $msg) = $self->Send( update => Fields => [keys %args] );
        return $self->RollbackTransaction( "Couldn't send update to remote host: $msg" )
            unless $status;
    }
    $RT::Handle->Commit;

    return (1, 'Updated');
}

my %INVERT_ROLE = ( Receiver => 'Sender', Sender => 'Receiver' );

sub Send {
    my $self = shift;
    my $action = shift;
    my %args = @_;

    my $recipient = $self->RemoteIs;
    return (0, 'We are neither sender nor receiver')
        unless $recipient;

    my $method = RT::Extension::NetworkedHelpDesk->ActionToWebMethod( $action );
    return (0, "Unknown action '$action'")
        unless $method;

    my $response = RT::Extension::NetworkedHelpDesk->JSONRequest(
        $method => $self->$recipient() .'/agreements/'. $self->UUID,
        Headers => {
            'X-Ticket-Sharing-Token' => $self->UUID .':'. $self->AccessKey,
        },
        Data => $self->ForJSON( %args ),
    );

    unless ( $response && $response->is_success ) {
        return (0, 'No response', $response) unless $response;
        return (0, 'Request was not successful', $response);
    }

    return (1, 'Updated remote host', $response);
}

sub WhoWeAre {
    my $self = shift;
    my %args = @_;

    my $our_url = RT->Config->Get('NHD_WebURL');

    my $res;
    if ( ($self->Sender || $args{'Sender'}) eq $our_url ) {
        $res = 'Sender';
    }
    elsif ( ($self->Receiver || $args{'Receiver'} || '') eq $our_url ) {
        $res = 'Receiver';
    }
    return $res;
}

sub RemoteIs { return $INVERT_ROLE{ (shift)->WhoWeAre } }

sub WhoIsCurrentUser {
    my $self = shift;
    my %args = @_;

    my $user_url = $self->CurrentUser->UserObj->Name;
    if ( ($self->Sender || $args{'Sender'} || '') eq $user_url ) {
        return 'Sender';
    }
    elsif ( ($self->Receiver || $args{'Receiver'} || '') eq $user_url ) {
        return 'Receiver';
    }
    return $self->WhoWeAre( %args );
}

sub LoadOrCreateUser {
    my $self = shift;
    my %args = @_;

    my $our_url = RT->Config->Get('NHD_WebURL');

    my $url;
    if ( ($self->Sender || $args{'Sender'}) eq $our_url ) {
        $url = $self->Receiver || $args{'Receiver'} || '';
    }
    elsif ( ($self->Receiver || $args{'Receiver'} || '') eq $our_url ) {
        $url = $self->Sender || $args{'Sender'} || '';
    }
    else {
        return (undef, "Either sender or receiver should be '$our_url'");
    }
    unless ( $url ) {
        return (undef, "Undefined URL");
    }
    my $user = RT::User->new( RT->SystemUser );
    $user->Load( $url );
    return ($user, 'Loaded') if $user->id;

    my ($status, $msg) = $user->Create(
        Name => $url,
        Privileged => 0,
        Disabled => 0,
        Comments => "Auto created on submitting Networked HelpDesk Agreement",
    );
    return ($status, $msg) unless $status;

    return ($user, 'Created');
}

sub ValidateUUID { return RT::Extension::NetworkedHelpDesk->CheckUUID( $_[1] ) }
sub ValidateAccessKey { return RT::Extension::NetworkedHelpDesk->CheckUUID( $_[1] ) }

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

our %FIELDS_MAP = (
    UUID => 'uuid',
    Name => 'name',
    Status => 'status',
    Sender => 'sender_url',
    Receiver => 'receiver_url',
    AccessKey => 'access_key',
    DeactivatedBy => 'deactivated_by',
);

sub FromJSON {
    my $self = shift;
    my ($args) = @_;

    my %res;
    while ( my ($k, $v) = each %FIELDS_MAP ) {
        next unless exists $args->{$v};
        $res{ $k } = $args->{$v};
    };

    return \%res;
}

sub ForJSON {
    my $self = shift;
    my %args = @_;

    my @fields = $args{'Fields'} ? @{$args{'Fields'}} : keys %FIELDS_MAP;

    my %res;
    $res{ $FIELDS_MAP{$_} } = $self->$_() foreach grep exists $FIELDS_MAP{$_}, @fields;
    if ( exists $res{'name'} && $self->WhoWeAre eq 'Sender' ) {
        $res{'name'} = RT->Config->Get('NHD_Name');
    }
    return \%res;
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

    $RT::Handle->Rollback if $self->_Handle->TransactionDepth;

    $self->LoadByCols( id => $self->id );

    return (0, $msg);
}

sub _CoreAccessible { return {
    id =>
    { read => 1, sql_type => 4, length => 11, is_blob => 0, is_numeric => 1, type => 'int(11)' },
    Queue =>
    {read => 1, write => 1, sql_type => 4, length => 11, is_blob => 0, is_numeric => 1, type => 'int(11)', default => 0},
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
