package Libki::Controller::API::Client::v1_0;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use Libki::SIP qw( authenticate_via_sip );
use DBI;


=head1 NAME

Libki::Controller::API::Client::v1_0 - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index

=cut

sub index : Path : Args(0) {
    my ( $self, $c ) = @_;

    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
      localtime(time);
    my $now = sprintf(
        "%04d-%02d-%02d %02d:%02d:%02d",
        $year + 1900,
        $mon + 1, $mday, $hour, $min, $sec
    );

    my $action = $c->request->params->{'action'};

    if ( $action eq 'register_node' ) {

        my $client = $c->model('DB::Client')->update_or_create(
            {
                name            => $c->request->params->{'node_name'},
                location        => $c->request->params->{'location'},
                last_registered => $now,
            }
        );

        my $reservation = $client->reservation || undef;
        if ($reservation) {
	    my $masked_reserved_for = '....'. substr $reservation->user->username(), -4;
            $c->stash( reserved_for => $masked_reserved_for );
        }

        $c->stash(
            registered     => !!$client,
            ClientBehavior => $c->stash->{'Settings'}->{'ClientBehavior'},
            ReservationShowUsername =>
              $c->stash->{'Settings'}->{'ReservationShowUsername'},

            BannerTopURL    => $c->stash->{'Settings'}->{'BannerTopURL'},
            BannerTopWidth  => $c->stash->{'Settings'}->{'BannerTopWidth'},
            BannerTopHeight => $c->stash->{'Settings'}->{'BannerTopHeight'},

            BannerBottomURL   => $c->stash->{'Settings'}->{'BannerBottomURL'},
            BannerBottomWidth => $c->stash->{'Settings'}->{'BannerBottomWidth'},
            BannerBottomHeight =>
              $c->stash->{'Settings'}->{'BannerBottomHeight'},
        );
    }
    elsif ( $action eq 'acknowledge_reservation' ) {
        my $client_name  = $c->request->params->{'node'};
        my $reserved_for = $c->request->params->{'reserved_for'};

        my $reservation =
          $c->model('DB::Reservation')
          ->search( {},
            { 'username' => $reserved_for, 'name' => $client_name } )->next();

        unless ( $reservation->expiration() ) {
            $reservation->expiration(
                DateTime::Format::MySQL->format_datetime(
                    DateTime->now( time_zone => 'local' )->add_duration(
                        DateTime::Duration->new(
                            minutes =>
                              $c->stash->{'Settings'}->{'ReservationTimeout'}
                        )
                    )
                )
            );
            $reservation->update();
        }
    }
    else {
	# Populate scalers with CGI param values
        my $username        = $c->request->params->{'username'};
	$username =~ s/^\s+|\s+$//g;
        my $password        = $c->request->params->{'password'};
        my $client_name     = $c->request->params->{'node'};
        my $client_location = $c->request->params->{'location'};

	# Initialize some additional variables
	my ($user,$barcode,$name,$eg_success,$eg_error,$eg_usrname);
	my $juve = 'no';

        if ($username !~ /^guest/i) {
	   ## Deal with EG usrname or barcode entered
	   if ($username !~ /^[0-9]+$/){ # we have an EG usrname
		$eg_usrname = $username;
		$user = $c->model('DB::User')->single( { message => $eg_usrname } );
		if (! $user) {
			( $eg_success, $eg_error, $barcode, $name, $juve ) =
				Libki::SIP::authenticate_via_sip( $c, $client_name, $username, $password );
			$username=$barcode;
			$user = $c->model('DB::User')->single( { username => $username } );
			if ($user) {
				$user->message($eg_usrname);
				$user->update();
			}
		} else {
			$username = $user->username(); # because the username column always contains the barcode
		}
	   } else { # we have an EG barcode
		$user = $c->model('DB::User')->single( { username => $username } );
		if ($user && (!$user->notes || !$user->message)) { # populate notes field if empty
			( $eg_success, $eg_error, $barcode, $name, $juve, $eg_usrname ) =
                                Libki::SIP::authenticate_via_sip( $c, $client_name, $username, $password );
			$user->notes($name);
                	$user->message($eg_usrname);
                	$user->update();
		}
		if (! $user) { 
                        ( $eg_success, $eg_error, $barcode, $name, $juve, $eg_usrname ) =
                                Libki::SIP::authenticate_via_sip( $c, $client_name, $username, $password );
                }

	   } 

	} else {  
		# Must be a guest user, we'll fetch that user info
		$user = $c->model('DB::User')->single( { username => $username } );
        } 

        if ( $action eq 'login' ) {
  	    ## cut down branch time on initial login
	    if ($user){
	   	if ( ($client_location !~ /^GRM|^XXX|^YS|^HIS/) && ($user->minutes() > 60) ) {
            		$user->minutes(60);
            		my $success = $user->update();
            		$success &&= 1;
            		$c->stash( message_cleared => $success );
		}
 	    }

	    my ( $success, $error ) = ( 1, undef );
            ## Don't hit EG twice or for guest account
            if ($username =~ /^guest/i ) {$name='override';}
	    if (!$name && !$eg_error) {
		( $eg_success, $eg_error, $barcode, $name, $juve ) =
                                Libki::SIP::authenticate_via_sip( $c, $client_name, $username, $password );
		$juve = ucfirst($juve);
		$user->is_troublemaker($juve);  # expedient hack to indicate juvenile in the (unused by GRPL) troublemaker field
		$user->update();

	    }
	
            ## Process client requests
            if ($eg_success || ($username =~ /^guest/i ) ) {
                if ( $c->authenticate( { username => $username, password => $password } ) ) {
                    $c->stash( units => $user->minutes );

                    if ( $user->session ) {
                        #$c->stash( error => 'ACCOUNT_IN_USE' );
            		my $success = $user->session->delete();
            		$success &&= 1;
            		#$c->stash( logged_out => $success );

            		$c->model('DB::Statistic')->create(
                	{
                    		username    => $username,
                    		client_name => $client_name,
                    		action      => 'LOGOUT'
                    		# when        => $now
                	}
            		);
			cleanUpISM($c,$client_name);
                    }
                    elsif ( $user->status eq 'disabled' ) {
                        $c->stash( error => 'ACCOUNT_DISABLED' );
                    }
                    elsif ( $user->minutes < 1 ) {
                        $c->stash( error => 'NO_TIME' );
                    }
                    else {
                        my $client =
                          $c->model('DB::Client')
                          ->search( { name => $client_name } )->next();

			## delete any existing session here
    			if ( defined($client) && defined( $client->session ) ) {
        			if ( $client->session->delete() ) {
            			   $success = 1;
        			}
    			}

                        if ($client) {
                            my $reservation = $client->reservation;

                            if ( !$reservation && !( $c->stash->{'Settings'}->{'ClientBehavior'} =~ 'FCFS') ){
                                $c->stash( error => 'RESERVATION_REQUIRED' );
                            }
                            elsif ( !$reservation || $reservation->user_id() == $user->id() ) {
				# If this is "the" user, delete reservation
                                $reservation->delete() if $reservation;
				$user->reservation->delete() if $user->reservation;

                                my $session = $c->model('DB::Session')->create(
                                    {
                                        user_id   => $user->id,
                                        client_id => $client->id,
                                        status    => 'active'
                                    }
                                );
                                $c->stash( authenticated => $session && 1 );
                                $c->model('DB::Statistic')->create(
                                    {
                                        username        => $username,
                                        client_name     => $client_name,
                                        client_location => $client_location,
                                        action          => 'LOGIN'
                                        # when            => $now
                                    }
                                );
                            }
                            else {
                                $c->stash( error => 'RESERVED_FOR_OTHER' );
                            }
                        }
                        else {
                            $c->stash( error => 'INVALID_CLIENT' );
                        }
                    }
                } # End sucessful auth
                else {  
		      # here we must have a new user
                      if ($username !~ /^guest/i) {

		          # GRPL - if SIP authenticates, but they're not local, go ahead and add them
			  my $min = 120;
			  if ($username =~ /^555/) { $min = 30; }

			  my $existinguser = $c->model('DB::User')->single( { message => $eg_usrname } );
			  if($existinguser){
				$min = $existinguser->minutes;
				$existinguser->delete();
			  }
			
			  my $user = $c->model('DB::User')->update_or_create(
        		    {
            			username          => $username,
            			password          => $password,
            			minutes		  => $min,
            			status            => 'enabled',
				notes		  => $name || '',
				message		  => $eg_usrname || $username,
                                is_troublemaker   => $juve || 'No',
        		    }
    			  );

                        $c->stash( error => 'NEW_USER_ADDED' );
                    }
                }
            } # end ---  if ($eg_success || ($username =~ /^guest/i ) )
            else {
                $c->stash( error => $error || $eg_error );
            }
        } # end "if $action eq 'login'" 

        elsif ( $action eq 'clear_message' ) {
            $user->message('');
            my $success = $user->update();
            $success &&= 1;
            $c->stash( message_cleared => $success );
        }
        elsif ( $action eq 'get_user_data' ) {

            my $status;
	    my $client_name = $c->request->params->{'node'};
	    my $dbh=DBI->connect("dbi:mysql:libki","libki","dfw44");
	    my $sth = $dbh->prepare("select name from sessions join clients on sessions.client_id = clients.id where name = '$client_name'");
	    $sth->execute();
	    my $sc =$sth->fetchrow_hashref;

            if ( ($user->session) && ($client_name eq $$sc{name} ) ){
                $status = 'Logged in';
		my $newTime = $c->model('DB::Client')->search({},{select => [{getTime => $client_location,$username}], as => [qw/ newTime /], } );
            }
            elsif ( $user->status eq 'disabled' ) {
                $status = 'Kicked';
            }
            else {
                $status = 'Logged out';
            }

            $c->stash(
                message => $user->message,
                units   => $user->minutes,
                status  => $status,
            );

        }
        elsif ( $action eq 'logout' ) {

	    # Go review the queue to see if we should create a reservation
	    
            my $success = $user->session->delete();
            $success &&= 1;
            $c->stash( logged_out => $success );

            $c->model('DB::Statistic')->create(
                {
                    username    => $username,
                    client_name => $client_name,
                    action      => 'LOGOUT'
                    # when        => $now
                }
            );
	    cleanUpISM($c,$client_name);
        }
    }
    delete( $c->stash->{'Settings'} );
    $c->forward( $c->view('JSON') );
}

sub cleanUpISM {
	my ($obj,$cname) = @_;
        # GRPL - put an ssh call here to handle any iptables issues on ISM
        my $host = $obj->config->{Remote_Script}->{host};
        my $script = $obj->config->{Remote_Script}->{script};
        system ("/usr/bin/ssh $host '$script $cname x'");
}


=head1 AUTHOR

Kyle M Hall <kyle@kylehall.info> 

=cut

=head1 LICENSE

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of 
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the  
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.   

=cut

__PACKAGE__->meta->make_immutable;

1;
