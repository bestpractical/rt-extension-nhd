use strict;
use warnings;

package RT::NHD::Ticket;
use base 'RT::Base';

use Digest::SHA1 qw(sha1_hex);

our @STATUSES = qw(open pending solved);
our %STATUS_NHD2RT = ( open => 'open', pending => 'stalled', solved => 'resolved' );

sub new {
    my $proto = shift;
    my $self = bless {}, ref($proto) || $proto;
    $self->_Init( @_ );
    return $self;
}

sub _Init { return (shift)->CurrentUser(@_) }

sub Ticket {
    my $self = shift;
    $self->{ticket} = shift if @_;
    return $self->{'ticket'} || RT::Ticket->new( $self->CurrentUser );
}

sub Load {
    my $self = shift;
    my $value = shift;

    unless ( RT::Extension::NetworkedHelpDesk->CheckUUID($value) ) {
        $RT::Logger->error("Doesn't look like UUID");
        return;
    }

    my $tickets = RT::Tickets->new( $self->CurrentUser );
    my $alias = $tickets->Join(
        ALIAS1 => 'main',
        FIELD1 => 'id',
        TABLE2 => 'Attributes',
        FIELD2 => 'ObjectId',
    );
    $tickets->_SQLLimit(
        ALIAS           => $alias,
        FIELD           => 'ObjectType',
        VALUE           => 'RT::Ticket',
    );
    $tickets->_SQLLimit(
        ALIAS           => $alias,
        FIELD           => 'Name',
        VALUE           => 'NHDUUID',
    );
    $tickets->_SQLLimit(
        ALIAS           => $alias,
        FIELD           => 'Content',
        VALUE           => $value,
    );
    my $ticket = $self->Ticket( $tickets->First );
    return $ticket->id;
}

sub Create {
    my $self = shift;
    my %args = @_;

    my $agreement = $args{'Agreement'}
        or return (0, "No agreement");
    unless ( $agreement->Status eq 'accepted' ) {
        return (0, "Agreement is not accepted");
    }

    my $queue = RT::Queue->new( $self->CurrentUser );
    $queue->Load( $agreement->Queue );
    unless ( $queue->id ) {
        return (0, "Agreement has no queue defined");
    }

    ($args{'Status'}, my $msg) = $self->ConvertRemoteStatus(
        Status => $args{'Status'}, Queue => $queue,
    );
    return (0, "Couldn't convert status: $msg")
        unless $args{'Status'};

    if ( ref $args{'Requestor'} eq 'HASH') {
        my ($user, $msg) = $self->LoadOrCreateUser(
            %{ $args{'Requestor'} },
            Agreement => $agreement,
        );
        return (0, "Couldn't create a user: $msg")
            unless $user;

        $args{'Requestor'} = $user->id;
    }

    my $corresponds = delete $args{'Corresponds'};

    my $ticket = RT::Ticket->new( $self->CurrentUser );
    (my $id, undef, $msg) = $ticket->Create(
        %args,
        Queue => $queue,
    );
    $self->Ticket( $ticket );

    (my $status, $msg) = $self->AddAttributes(
        Object    => $ticket,
        UUID      => $args{'UUID'},
        Agreement => $agreement,
    );
    return ($status, "Couldn't add attribute: $msg")
        unless $status;

    return ($id, $msg);
}

sub Update {
    my $self = shift;
    my %args = @_;

    my $corresponds = delete $args{'Corresponds'};
    my $actor = delete $args{'UpdatedBy'};

    my $ticket = $self->Ticket;

    if ( exists $args{'Status'} ) {
        ($args{'Status'}, my $msg) = $self->ConvertRemoteStatus(
            Status => $args{'Status'}
        );
        return $self->RollbackTransaction("Couldn't convert status: $msg")
            unless $args{'Status'};
    }
    foreach my $field ( qw(Status Subject) ) {
        next unless exists $args{ $field };

        my $cur = $ticket->$field();
        my $new = $args{ $field };
        next if (defined $new && !defined $cur)
            || (!defined $new && defined $cur)
            || $new ne $cur;

        delete $args{ $field };
    }

    $RT::Handle->BeginTransaction;
    foreach my $field ( qw(Status Subject) ) {
        next unless exists $args{ $field };

        my $method = "Set$field";
        my ($status, $msg) = $ticket->$method( $args{ $field } );
        return $self->RollbackTransaction( "Couldn't update $field: $msg" )
            unless $status;
    }
    $RT::Handle->Commit;

    return (1, 'Updated');
}


sub id { (shift)->Ticket->id }

sub UUID {
    my $self = shift;
    my $agreement = shift;
    return RT::Extension::NetworkedHelpDesk->ObjectUUID(
        $self->Ticket, Agreement => $agreement,
    );
}

our %FIELDS_MAP = (
    Subject     => 'subject',
    Status      => 'status',
    UUID        => 'uuid',
    Created     => 'requested_at',
    Requestor   => 'requester',
    Creator     => 'author',
    Content     => 'body',
    Updated     => 'authored_at',
    Corresponds => 'comments',
    Name        => 'name',
    UpdatedBy   => 'current_actor',
);

sub ForJSON {
    my $self = shift;
    my %args = @_;

    my $ticket = $self->Ticket;

    my %res;
    $res{'uuid'} = $self->UUID( $args{'Agreement'} );
    $res{'subject'} = $ticket->Subject;
    $res{'requested_at'} = $ticket->CreatedObj->NHD;
    $res{'status'} = $self->ConvertLocalStatus;

    if ( my $requestor = $ticket->Requestors->UserMembersObj->First ) {
        $res{'requester'} = $self->PresentUser(
            User => $requestor, Agreement => $args{'Agreement'},
        );
    }

    return \%res;
}

sub FromJSON {
    my $self = shift;
    my $args = shift;

    my $turn_hash = sub {
        my ($args) = @_;
        my $res = {};
        while ( my ($k, $v) = each %FIELDS_MAP ) {
            next unless exists $args->{ $v };
            $res->{ $k } = $args->{ $v };
            if ( $k eq 'Created' || $k eq 'Updated' ) {
                my $shift;
                if ( $res->{ $k } =~ s/\s*(?:([+-])([0-9]{2}):?([0-9]{2})|Z)$//i && ($2||$3) ) {
                    $shift = ($2*60+$3)*60* ($1 eq '-'? -1 : 1);
                }
                my $date = RT::Date->new( RT->SystemUser );
                $date->Set( Format => 'ISO', Value => $res->{ $k } );
                $date->AddSeconds( -$shift ) if $shift;
                $res->{ $k } = $date->ISO;
            }
        };
        return $res;
    };

    my $res = $turn_hash->( $args );

    foreach my $e ( @{ $res->{'Corresponds'} || [] } ) {
        $e = $turn_hash->( $e );
    }
    foreach my $e ( $res->{'Requestor'} ) {
        $e = $turn_hash->( $e );
    }

    return $res;
}

sub ConvertRemoteStatus {
    my $self = shift;
    my %args = (
        Status => undef,
        Queue => undef,
        @_
    );
    return (undef, "no value") unless $args{'Status'};
    return (undef, "invalid value") unless grep $args{'Status'} eq $_, @STATUSES;

    my $queue = $self->id ? $self->Ticket->QueueObj : $args{'Queue'};
    my $map_name = 'NHD -> '. $queue->Lifecycle->Name;
    return $self->ConvertStatus( $map_name => $args{'Status'} );
}

sub ConvertLocalStatus {
    my $self = shift;
    my %args = (
        Status => undef,
        @_
    );
    my $ticket = $self->Ticket;
    $args{'Status'} ||= $ticket->Status;

    my $map_name = $ticket->QueueObj->Lifecycle->Name .' -> NHD';
    return $self->ConvertStatus( $map_name => $args{'Status'} );
}

sub ConvertStatus {
    my $self     = shift;
    my $map_name = shift;
    my $status   = shift;

    my $map = RT->Config->Get('NHD_StatusMap')->{ $map_name };
    return (undef, "no map in \%NHD_StatusMap for '$map_name'")
        unless $map;

    my $res = $map->{ $status };
    return (undef, "no mapping for '$status' in '$map_name' map")
        unless $res;
    return ($res);
}

sub LoadOrCreateUser {
    my $self = shift;
    my %args = @_;

    my $user = RT::User->new( RT->SystemUser );
    $user->Load( $args{'UUID'} );
    return ($user, 'Loaded') if $user->id;

    my ($status, $msg) = $user->Create(
        Name => $args{'UUID'},
        RealName => $args{'Name'},
        Privileged => 0,
        Disabled => 0,
        Comments => "Auto created by Networked Help Desk",
    );
    return ($status, $msg) unless $status;

    ($status, $msg) = $self->AddAttributes(
        Object => $user,
        UUID => $args{'UUID'},
        Agreement => $args{'Agreement'},
    );
    return ($status, "Couldn't add attribute: $msg") unless $status;

    return ($user, 'Created');
}

sub PresentUser {
    my $self = shift;
    my %args = @_%2? (User => @_) : @_;

    my $user = $args{'User'};
    my $uuid = RT::Extension::NetworkedHelpDesk->ObjectUUID(
        $user, Agreement => $args{'Agreement'},
    );
    unless ( $uuid ) {
        $uuid = sha1_hex(
            join '', 'users', $user->id, $user->Name, $user->EmailAddress
        );
        my ($status, $msg) = $self->AddAttributes(
            NewObject => 0,
            Object => $user,
            UUID => $uuid,
            Agreement => $args{'Agreement'},
        );
        $RT::Logger->error("Couldn't add attribute: $msg")
            unless $status;
    }

    return {
        uuid => $uuid,
        name => $user->RealName || $user->EmailAddress || $user->Name,
    };
}

sub AddAttributes {
    my $self = shift;
    my %args = (
        Object    => undef,
        UUID      => undef,
        Agreement => undef,
        NewObject => 1,
        @_
    );

    if ( $args{'NewObject'} ) {
        my ($status, $msg) = $args{'Object'}->AddAttribute(
            Name => 'NHDUUID', Content => $args{'UUID'},
        );
        return ($status, $msg) unless $status;

        return $args{'Object'}->AddAttribute(
            Name => 'NHD',
            Content => { $args{'Agreement'}->UUID => $args{'UUID'} },
        );
    } else {
        my ($status, $msg) = $args{'Object'}->AddAttribute(
            Name => 'NHDUUID', Content => $args{'UUID'},
        );
        return ($status, $msg) unless $status;

        my $attr = ($args{'Object'}->Attributes->Named('NHD'))[0];
        unless ( $attr ) {
            return $args{'Object'}->AddAttribute(
                Name => 'NHD',
                Content => { $args{'Agreement'}->UUID => $args{'UUID'} },
            );
        }
        my %info = %{ $attr->Content || {} };
        $info{''} = $args{'UUID'};
        return $args{'Object'}->SetAttribute( Name => 'NHD', Content => \%info );
    }
}

sub RollbackTransaction {
    my $self = shift;
    my $msg = shift;

    $RT::Handle->Rollback if $self->_Handle->TransactionDepth;

    $self->Ticket->Load( $self->id );

    return (0, $msg);
}

1;
