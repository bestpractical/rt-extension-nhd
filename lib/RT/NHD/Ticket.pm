use strict;
use warnings;

package RT::NHD::Ticket;
use base 'RT::Base';

use Digest::SHA1 qw(sha1_hex);

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

    return ($id, $msg);
}

sub id { (shift)->Ticket->id }

our %FIELDS_MAP = (
    Subject     => 'subject',
    Status      => 'status',
    UUID        => 'uuid',
    Created     => 'requested_at',
    Requestor   => 'requester',
    Creator     => 'author',
    Content     => 'body',
    Created     => 'authored_at',
    Corresponds => 'comments',
    Name        => 'name',
);

sub ForJSON {
    my $self = shift;

    my %res;
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
            if ( $k eq 'Created' ) {
                my $date = RT::Date->new( RT->SystemUser );
                $date->Set( Format => 'unknown', Value => $res->{ $k } );
                $res->{ $k } = $date;
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
    return ($user, 'Created');
}

1;
