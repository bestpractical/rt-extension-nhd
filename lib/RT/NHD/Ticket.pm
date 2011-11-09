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
    my ($id, $txn, $msg) = $ticket->Create(
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
        return $self->RollbackTransaction("Invalid status value")
            unless grep $_ eq lc($args{'Status'}), @STATUSES;
        $args{'Status'} = $STATUS_NHD2RT{ lc $args{'Status'} };
        delete $args{'Status'} if $ticket->Status eq $args{'Status'};
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
    my ($info) = $self->Ticket->Attributes->Named('NHD');
    return undef unless $info;
    return $info->{ $agreement->UUID } || $info->{''};
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
    $res{'requested_at'} = $ticket->CreatedObj->XMLSchema;
    $res{'status'} = $ticket->Status; # XXX: convert it

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
                my $date = RT::Date->new( RT->SystemUser );
                $date->Set( Format => 'unknown', Value => $res->{ $k } );
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
    my $info = ($user->Attributes->Named('NHD'))[0] || {};
    my $uuid = $info->{ $args{'Agreement'}->UUID } || $info->{''};
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
            Name => 'NHDUUID', Value => $args{'UUID'},
        );
        return ($status, $msg) unless $status;

        return $args{'Object'}->AddAttribute(
            Name => 'NHD',
            Value => { $args{'Agreement'}->UUID => $args{'UUID'} },
        );
    } else {
        my ($status, $msg) = $args{'Object'}->AddAttribute(
            Name => 'NHDUUID', Value => $args{'UUID'},
        );
        return ($status, $msg) unless $status;

        my ($info) = $args{'Object'}->Attributes->Named('NHD');
        $info->{''} = $args{'UUID'};
        return $args{'Object'}->SetAttribute( Name => 'NHD', Value => $info );
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
