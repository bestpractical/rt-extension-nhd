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

    no strict 'subs';
    my $orig = \&RT::Extension::NHD::SendRequest;
    *RT::Extension::NHD::SendRequest = sub {
        return $orig->(@_) if $_[1] && $_[1]->uri =~ RT->Config->Get('WebDomain');

        my $self = shift;
        return RT::Extension::NHD::Test->push_object_into_file( 'requests', shift );
        return RT::Extension::NHD::Test->get_object_from_file( 'responses' );
    };
}

sub new_agent {
    my $self = shift;
    require RT::Extension::NHD::Test::Web;
    return  RT::Extension::NHD::Test::Web->new_agent( @_ );
}

sub remote_requests { return RT::Extension::NHD::Test->get_objects_from_file('requests') }

sub set_next_remote_response {
    my $self = shift;
    my $code = shift;
    my %args = @_;

    my $msg = $args{'Message'} || $RT::Extension::NHD::HTTP_MESSAGE{ $code }
        || die "no message for code $code";

    my %headers = %{ $args{'Headers'} || {} };
    %headers = (
        %headers,
        'X-Ticket-Sharing-Version' => '1',
    );
    my $content = $args{'Data'};
    $content = RT::Extension::NHD->ToJSON( $content )
        if ref $content;
    RT::Extension::NHD::Test->push_object_into_file( responses => HTTP::Response->new(
        $code, $msg, [%headers], $content,
    ) );
    return;
}

my $magic_string = "\nvery magic string that probably will work just fine\n";
sub push_object_into_file {
    my $self = shift;
    my $type = shift;
    open my $fh, '>>', $self->temp_directory ."/nhd-${type}-file"
        or die $!;
    print $fh $_."$magic_string" foreach map Storable::nfreeze($_), @_;
    close $fh;
}
sub get_object_from_file {
    my $self = shift;
    my $type = shift;

    my @list = $self->get_objects_from_file( $type );

    my $res = shift @list;
    $self->push_object_into_file( $type, @list );
    return $res;
}
sub get_objects_from_file {
    my $self = shift;
    my $type = shift;

    my $data = $self->file_content(
        [$self->temp_directory, "nhd-${type}-file"],
        unlink => 1
    );
    return map Storable::thaw($_), split /\Q$magic_string/, $data;
}

1;
