=head1 Networked Help Desk configuration file

=cut

package RT;

=head2 Basics

=over 4

=item C<$NHD_WebURL>

=cut

Set( $NHD_WebURL, RT->Config->Get('WebURL') . 'NoAuth/NHD/1.0' );

=item C<$NHD_Name>

=cut

Set( $NHD_Name, RT->Config->Get('Organization') );

=item C<$NHD_StatusMap>

=cut

Set( %NHD_StatusMap,
    'NHD -> default' => {
        open     => 'open',
        pending  => 'stalled',
        closed   => 'resolved',
    },
    'default -> NHD' => {
        new      => 'open',
        open     => 'open',
        stalled  => 'pending',
        resolved => 'closed',
        rejected => 'closed',
        deleted  => 'closed',
    },
);

=back

=cut

1;
