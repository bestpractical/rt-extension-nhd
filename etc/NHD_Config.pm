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

=back

=cut

1;
