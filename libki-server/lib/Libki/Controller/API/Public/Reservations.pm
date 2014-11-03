package Libki::Controller::API::Public::Reservations;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

Libki::Controller::API::Public::Reservations - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 create

=cut

sub create : Local : Args(0) {
    my ( $self, $c ) = @_;

    my $username  = $c->request->params->{'username'};
    my $password  = $c->request->params->{'password'};
    my $client_id = $c->request->params->{'id'};
    my $barcode;
    my $name;

    my $user =
      $c->model('DB::User')->single( { username => $username } );

    my ( $success, $error_code, $details ) = ( 1, undef, undef ); # Defaults for non-sip using systems
    #( $success, $error_code, $details ) = Libki::SIP::authenticate_via_sip( $c, $user, $username, $password )
    ( $success, $error_code, $barcode, $name ) = Libki::SIP::authenticate_via_sip( $c, $user, $username, $password )
        if $c->config->{SIP}->{enable};

    if ($username =~ /^guest/ ) {$success=1;$barcode=$username;$name='override';}
    $username=$barcode;
    $user = $c->model('DB::User')->single( { username => $username } );

    if (
        $success && 
        $c->authenticate(
            {
                username => $username,
                password => $password
            }
        )
      )
    {

        if ( $c->model('DB::Reservation')
            ->search( { user_id => $user->id(), client_id => $client_id } )
            ->next() )
        {
            $c->stash(
                'success' => 0,
                'reason'  => 'CLIENT_USER_ALREADY_RESERVED'
            );
        }
        elsif (
            $c->model('DB::Reservation')->search( { client_id => $client_id } )
            ->next() )
        {
            $c->stash( 'success' => 0, 'reason' => 'CLIENT_ALREADY_RESERVED' );
        }
        elsif (
            $c->model('DB::Reservation')->search( { user_id => $user->id() } )
            ->next() )
        {
            $c->stash( 'success' => 0, 'reason' => 'USER_ALREADY_RESERVED' );
        }
	elsif ( $user->minutes < 1 ) {
	    $c->stash( 'success' => 0, 'reason' => 'NO_TIME' ); 
	}
        else {
            if ( $c->model('DB::Reservation')
                ->create( { user_id => $user->id(), client_id => $client_id } )
              )
            {
# Record reservation in statistics table
#        my $schema->resultset('Statistic')->create(
		$c->model('DB::Statistic')->create(
            {
                username    => $username,
                client_name => $client_id,
                action      => 'RESERVATION',
                when =>
                  DateTime::Format::MySQL->format_datetime( DateTime->now() ),
            }
        );
                $c->stash( 'success' => 1 );
            } else {
                $c->stash( 'success' => 0, 'reason' => 'UNKNOWN' );
            }
	}
    } else {

	if ($success) {
                    # GRPL - if SIP authenticates, but they're not local, go ahead and add them
                    unless ($username =~ /^guest/){
                        my $min = 60;
                        if ($username =~ /^555/) { $min = 30; }

                        my $user = $c->model('DB::User')->update_or_create(
                        {
                                username          => $username,
                                password          => $password,
                                minutes_allotment => $min,
                                status            => 'enabled',
                                notes             => $name,
                        }
                        );
			 $c->stash( 'success' => 0, 'reason' => 'NEW_USER_ADDED' );
                    }
  	}else{
        	$c->stash( 'success' => 0, 'reason' => $error_code, details => $details );
	}
    }

    $c->logout();

    $c->forward( $c->view('JSON') );
}

=head2 delete

=cut

sub delete : Local : Args(0) {
    my ( $self, $c ) = @_;

    my $password  = $c->request->params->{'password'};
    my $client_id = $c->request->params->{'id'};

    my $user = $c->model('DB::Client')->find($client_id)->reservation->user;

    if (
        $c->authenticate(
            {
                username => $user->username,
                password => $password
            }
        )
      )
    {

        if ( $c->model('DB::Reservation')
            ->search( { user_id => $user->id(), client_id => $client_id } )
            ->next()->delete() )
        {
# Record reservation delete in statistics table
#        my $schema->resultset('Statistic')->create(
                $c->model('DB::Statistic')->create(
            {
               username    => $user->username,
               client_name => $client_id,
               action      => 'RESERVATION_DELETED',
               when =>
                  DateTime::Format::MySQL->format_datetime( DateTime->now() ),
            }
        );
            $c->stash( 'success' => 1, );
        }
        else {
            $c->stash( 'success' => 0, 'reason' => 'UNKNOWN' );
        }
    }

    $c->logout();

    $c->forward( $c->view('JSON') );
}

=head1 AUTHOR

libki,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
