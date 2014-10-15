#!/usr/bin/perl

use strict;
use warnings;

use Env;
use Config::JFDI;
use DateTime::Format::MySQL;
use DateTime;
use DBI;

use FindBin;
use lib "$FindBin::Bin/../../lib";

use Libki::Schema::DB;

use Data::Dumper;

my $config = Config::JFDI->new(
    file          => "$FindBin::Bin/../../libki_local.conf",
    no_06_warning => 1
);
my $config_hash  = $config->get();
my $connect_info = $config_hash->{'Model::DB'}->{'connect_info'};

my $schema = Libki::Schema::DB->connect($connect_info)
  || die("Couldn't Connect to DB");

## Decrement time for logged in users.
my $session_rs = $schema->resultset('Session');
while ( my $session = $session_rs->next() ) {
    if ( $session->user->minutes() > 0 ) {
	my $ttc = timeToClose($session);
	if  ( ($session->user->minutes() == 5) && ($ttc > 5) && ($session->user->username() !~ /^555/) ){  #GRPL - if we're in our final 5 minutes, see if there are waiting reservations
	    if ($schema->resultset('Reservation')->search( { client_id => $session->client->id } )->next() ) { 
        	$session->user->decrease_minutes(1);
        	$session->user->update();
	    }else{ # if no reservations, see if the user has been around for 2 hours yet
		# if minutes since last LOGIN >= 115 minutes then decrease_minutes(1);
		my $length = timeSinceLogin($session);
		if ($length >= 115){
			$session->user->decrease_minutes(1);
			$session->user->update();
		  }else{
			next;
		}
	    }
	}else{
		$session->user->decrease_minutes(1);
                $session->user->update();
	}
    }
    else {
        ## If somehow a session exists with
        ## 0 or a negative number of minutes,
        ## we need to clean if out.
        $schema->resultset('Statistic')->create(
            {
                username    => $session->user->username(),
                client_name => $session->client->name(),
                action      => 'SESSION_DELETED',
                when =>
                  DateTime::Format::MySQL->format_datetime( DateTime->now() ),
            }
        );

        $session->delete();
	
    }
}

## Delete clients that haven't updated recently
my $post_crash_timeout =
  $schema->resultset('Setting')->find('PostCrashTimeout')->value;

my $timestamp = DateTime::Format::MySQL->format_datetime(
    DateTime->now( time_zone => 'local' )->subtract_duration(
        DateTime::Duration->new( minutes => $post_crash_timeout )
    )
);

$schema->resultset('Client')
  ->search( { last_registered => { '<', $timestamp } } )->delete();

## Clear out any expired reservations
$schema->resultset('Reservation')->search(
    {
        'expiration' => {
            '<',
            DateTime::Format::MySQL->format_datetime(
                DateTime->now( time_zone => 'local' )
            )
        }
    }
)->delete();

## Refill session minutes from allotted minutes for users not logged in to a client
my $default_time_allowance =
  $schema->resultset('Setting')->find('DefaultTimeAllowance')->value;
my $default_session_time_allowance =
  $schema->resultset('Setting')->find('DefaultSessionTimeAllowance')->value;

my $users_rs = $schema->resultset('User')->search(
    {
        minutes           => { '<' => $default_session_time_allowance },
        minutes_allotment => { '>' => 0 }
    }
);

while ( my $user = $users_rs->next() ) {
    unless ( $user->session() ) {
        while ($user->minutes() < $default_session_time_allowance
            && $user->minutes_allotment() > 0 )
        {
            $user->decrease_minutes_allotment(1);
            $user->increase_minutes(1);
        }
        $user->update();
    }
}

sub timeToClose()
{
my $sess=shift;
my $loc = $sess->client->location;
my $dbh=DBI->connect("dbi:mysql:libki","user","password");
my $sth=$dbh->prepare("select time_to_sec(timediff( (select close_time from closing_times where location=? and dow=dayofweek(now()) ), time(now()) ))/60");
$sth->execute($loc);
my $row = $sth->fetch;

return $$row[0];
}

sub timeSinceLogin()
{
my $sess=shift;
my $usr = $sess->user->username();
my $dbh=DBI->connect("dbi:mysql:libki","user","password");
my $sth=$dbh->prepare("SELECT TIMESTAMPDIFF(MINUTE,max(`when`),now()) FROM statistics WHERE action='LOGIN' AND username=?");
$sth->execute($usr);
my $row = $sth->fetch;

return $$row[0];
}



=head1 AUTHOR

Kyle M Hall <kyle@kylehall.info> 

=cut

=head1 LICENSE
This file is part of Libki.

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
