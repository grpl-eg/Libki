package Libki::SIP;

#use Socket qw(:crlf);
#use IO::Socket::INET;
use LWP::UserAgent;
use XML::Simple;

sub authenticate_via_sip {
    my ( $c, $client, $username, $password ) = @_;

        my $name;
	my %patronapi;

        ## III PATRONAPI
        my $ua=LWP::UserAgent->new();
        $ua->timeout(40);
        my $authn_url = "http://catalog.grpl.org/cgi-bin/papupass.cgi?barcode=$username&password=$password&client=$client";
        my $res=$ua->get($authn_url);
        if ($res->is_success) {
                my $c = $res->content;
                unless ($c =~ "Someone attempted to retrieve a user" ){
                        my $xs = XML::Simple->new();
                        %patronapi = %{$xs->XMLin($c)};
                        $name = $patronapi{name};
                }else{
			return ( 0, 'INVALID_USER' );
		}
        }else{
	
		return ( 0, 'CONNECTION_FAILURE' );
	}	
        if ( $patronapi{money_owed} > 40.00 ) {
                return ( 0, 'FEE_LIMIT', { fee_limit => $patronapi{money_owed} } );
        }

        if ( $patronapi{expired} eq 't' ) {
                return ( 0, 'ACCOUNT_EXPIRED' );
        }

	if ($name) {

	    if ($patronapi{block_inet}){
		return (0, 'ACCOUNT_BLOCKED' );
	    }else{
        	return (1,'',$patronapi{card}{barcode},$name,$patronapi{juvenile});
	    }
	}else{
		return ( 0, 'INVALID_PASSWORD' );
	}

}

1;
