#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 18;

my $ID = '301425';
my $VAR1 = {
    "lang" => "perl",
    "content" => "{\r\ntest => 'yes'\r\n}",
    "name" => "Zoffix",
};


BEGIN {
    use_ok('Carp');
    use_ok('URI');
    use_ok('LWP::UserAgent');
    use_ok('HTML::TokeParser::Simple');
    use_ok('HTML::Entities');
    use_ok('Class::Data::Accessor');
	use_ok('WWW::PhpfiCom::Retrieve');
}

diag( "Testing WWW::PhpfiCom::Retrieve $WWW::PhpfiCom::Retrieve::VERSION, Perl $], $^X" );

use WWW::PhpfiCom::Retrieve;
my $o = WWW::PhpfiCom::Retrieve->new(timeout => 10);
isa_ok($o, 'WWW::PhpfiCom::Retrieve');
can_ok($o, qw(new
    retrieve
    error
    id
    uri
    results
    ua
    _parse
    _set_error));

SKIP: {
    my $results_ref = $o->retrieve($ID);

    unless ( defined $results_ref ) {
        diag "Got error " . $o->error . " on request with ID ($ID)";
        ok( (defined $o->error and length $o->error ), '->error()' );
        skip "Got some error on ->retrieve()", 8;
    }

    SKIP: {
        my $results_ref2 = $o->retrieve("http://phpfi.com/$ID");
        unless ( defined $results_ref2 ) {
            diag "Got error " . $o->error . " on request with URI ($ID)";
            ok( (defined $o->error and length $o->error ), '->error()' );
        }
        is_deeply( $results_ref, $results_ref2, 'ID and URI retrieve()s');
    }

    is_deeply( $results_ref, $o->results, '->results()' );
    ok((defined $results_ref->{age} and length $results_ref->{age}), '{age}');
    like( $results_ref->{hits}, qr/^\d+$/, '{hits}');
    
    delete @$results_ref{ qw(age hits) };
    
    is_deeply( $results_ref, $VAR1, 'checking with dump');

    isa_ok( $o->uri, 'URI::http', '->uri');
    isa_ok( $o->ua, 'LWP::UserAgent', '->ua');
    is( $o->id, $ID, '->id');
    is( $o->error, undef, '->error must be undefined');
}


