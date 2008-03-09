package WWW::PhpfiCom::Retrieve;

use warnings;
use strict;

our $VERSION = '0.001';

use Carp;
use URI;
use LWP::UserAgent;
use HTML::TokeParser::Simple;
use HTML::Entities;
use base 'Class::Data::Accessor';
__PACKAGE__->mk_classaccessors qw(
    ua
    id
    uri
    error
    results
);

sub new {
    my $class = shift;
    croak "Must have even number of arguments to new()"
        if @_ & 1;

    my %args = @_;
    $args{ +lc } = delete $args{ $_ } for keys %args;

    $args{timeout} ||= 30;
    $args{ua} ||= LWP::UserAgent->new(
        timeout => $args{timeout},
        agent   => 'Mozilla/5.0 (X11; U; Linux x86_64; en-US; rv:1.8.1.12)'
                    .' Gecko/20080207 Ubuntu/7.10 (gutsy) Firefox/2.0.0.12',
    );

    my $self = bless {}, $class;
    $self->ua( $args{ua} );

    return $self;
}

sub retrieve {
    my ( $self, $id ) = @_;

    $self->$_(undef) for qw(error uri id results);
    
    return $self->_set_error('Missing or empty paste ID or URI')
        unless defined $id and length $id;

    $id =~ s{ ^\s+ | (?:http://)? (?:www\.)? phpfi\.com/(?=\d+) | \s+$ }{}xi;

    return $self->_set_error(
        q|Doesn't look like a correct ID or URI to the paste|
    ) if $id =~ /\D/;

    $self->id( $id );
    
    my $uri = $self->uri( URI->new("http://phpfi.com/$id") );
    my $ua = $self->ua;
    my $response = $ua->get( $uri );
    if ( $response->is_success ) {

        my $results_ref = $self->_parse( $response->content );
        return
            unless defined $results_ref;

        my $content_uri = $uri->clone;
        $content_uri->query_form( download => 1 );
        my $content_response = $ua->get( $content_uri );
        if ( $content_response->is_success ) {
            $results_ref->{content} = $content_response->content;
            return $self->results( $results_ref );
        }
        else {
            return $self->_set_error(
                'Network error: ' . $content_response->status_line
            );
        }
    }
    else {
        return $self->_set_error('Network error: ' . $response->status_line);
    }
}

sub _parse {
    my ( $self, $content ) = @_;

    my $parser = HTML::TokeParser::Simple->new( \$content );

    my %data;
    my %nav = (
        content => '',
        map { $_ => 0 }
            qw(get_info  level  get_lang  is_success  get_content  check_404)
    );
    while ( my $t = $parser->get_token ) {
        if ( $t->is_start_tag('td') ) {
            $nav{get_info}++;
            $nav{check_404}++;
            $nav{level} = 1;
        }
        elsif ( $nav{check_404} == 1 and $t->is_end_tag('td') ) {
            $nav{check_404} = 2;
            $nav{level} = 10;
        }
        elsif ( $nav{check_404} and $t->is_start_tag('b') ) {
            return $self->_set_error('This paste does not seem to exist');
        }
        elsif ( $nav{get_info} == 1 and $t->is_text ) {
            my $text = $t->as_is;
            $text =~ s/&nbsp;/ /g;

            @data{ qw(age name hits) } = $text
            =~ /
                created \s+
                ( .+? (?:\s+ago)? ) # stupid timestaps
                (?: \s+ by \s+ (.+?) )? # name might be missing
                ,\s+ (\d+) \s+ hits?
            /xi;

            $data{name} = 'N/A'
                unless defined $data{name};

            @nav{ qw(get_info level) } = (2, 2);
        }
        elsif ( $t->is_start_tag('select')
            and defined $t->get_attr('name')
            and $t->get_attr('name') eq 'lang'
        ) {
            $nav{get_lang}++;
            $nav{level} = 3;
        }
        elsif ( $t->is_start_tag('div')
            and defined $t->get_attr('id')
            and $t->get_attr('id') eq 'content'
        ) {
            @nav{ qw(get_content level) } = (1, 4);
        }
        elsif ( $nav{get_content} and $t->is_end_tag('div') ) {
            @nav{ qw(get_content level) } = (0, 5);
        }
        elsif ( $nav{get_content} and $t->is_text ) {
            $nav{content} .= $t->as_is;
            $nav{level} = 6;
        }
        elsif ( $nav{get_lang} == 1
            and $t->is_start_tag('option')
            and defined $t->get_attr('selected')
            and defined $t->get_attr('value')
        ) {
            $data{lang} = $t->get_attr('value');
            $nav{is_success} = 1;
            last;
        }
    }

    return $self->_set_error('This paste does not seem to exist')
        if $nav{content} =~ /entry \d+ not found/i;

    return $self->_set_error("Parser error! Level == $nav{level}")
        unless $nav{is_success};

    $data{ $_ } = decode_entities( delete $data{ $_ } )
        for grep { $_ ne 'content' } keys %data;

    return \%data;
}

sub _set_error {
    my ( $self, $error ) = @_;
    $self->error( $error );
    return;
}


1;
__END__

=head1 NAME

WWW::PhpfiCom::Retrieve - retrieve pastes from http://phpfi.com

=head1 SYNOPSIS

    use strict;
    use warnings;

    use WWW::PhpfiCom::Retrieve;

    my $paster = WWW::PhpfiCom::Retrieve->new;

    my $results_ref = $paster->retrieve('http://phpfi.com/301425')
        or die $paster->error;

    printf "Paste %s was posted %s ago by %s, it is written in %s "
                . "and was viewed %s time(s)\n%s\n",
                $paster->uri, @$results_ref{ qw(age name lang hits content) };

=head1 DESCRIPTION

The module provides interface to retrieve pastes from
L<http://www.phpfi.com> from Perl

=head1 CONSTRUCTOR

=head2 new

    my $paster = WWW::PhpfiCom::Retrieve->new;

    my $paster = WWW::PhpfiCom::Retrieve->new(
        timeout => 10,
    );

    my $paster = WWW::PhpfiCom::Retrieve->new(
        ua => LWP::UserAgent->new(
            timeout => 10,
            agent   => 'PasterUA',
        ),
    );

Constructs and returns a brand new yummy juicy WWW::PhpfiCom::Retrieve
object. Takes two arguments, both are I<optional>. Possible arguments are
as follows:

=head3 timeout

    ->new( timeout => 10 );

B<Optional>. Specifies the C<timeout> argument of L<LWP::UserAgent>'s
constructor, which is used for retrieving. B<Defaults to:> C<30> seconds.

=head3 ua

    ->new( ua => LWP::UserAgent->new( agent => 'Foos!' ) );

B<Optional>. If the C<timeout> argument is not enough for your needs
of mutilating the L<LWP::UserAgent> object used for retrieving, feel free
to specify the C<ua> argument which takes an L<LWP::UserAgent> object
as a value. B<Note:> the C<timeout> argument to the constructor will
not do anything if you specify the C<ua> argument as well. B<Defaults to:>
plain boring default L<LWP::UserAgent> object with C<timeout> argument
set to whatever C<WWW::PhpfiCom::Retrieve>'s C<timeout> argument is
set to as well as C<agent> argument is set to mimic Firefox.

=head1 METHODS

=head2 retrieve

    my $results_ref = $paster->retrieve('http://phpfi.com/301425')
        or die $paster->error;

    my $results_ref = $paster->retrieve('301425')
        or die $paster->error;

Instructs the object to retrieve a paste specified in the argument. Takes
one mandatory argument which can be either a full URI to the paste you
want to retrieve or just its numeric ID.
On failure returns either C<undef> or an empty list depending on the context
and the reason for the error will be available via C<error()> method.
On success returns a hashref with the following keys/values:

    $VAR1 = {
        'hits' => '0',
        'lang' => 'perl',
        'content' => '{ test => \'yes\' }',
        'name' => 'Zoffix',
        'age' => '7 hours and 41 minutes'
    };

=head3 content

    { 'content' => '{ test => \'yes\' }' }

The C<content> kew will contain the actual content of the paste.

=head3 lang

    { 'lang' => 'perl' }

The C<lang> key will contain the (computer) language of the paste
(as was specified by the poster).

=head3 name

    { 'name' => 'Zoffix' }

The C<name> key will contain the name of the poster who created the paste.

=head3 hits

    { 'hits' => '0' }

The C<hits> key will contain the number of times the paste was viewed.

=head3 age

    { 'age' => '7 hours and 41 minutes ago' }

The C<age> key will contain the "age" of the paste, i.e. how long ago
it was created. B<Note:> if the paste is old enough the C<age> will contain
the date/time of the post instead of "foo bar ago".

=head2 error

    $paster->retrieve('301425')
        or die $paster->error;

On failure C<retrieve()> returns either C<undef> or an empty list depending
on the context and the reason for the error will be available via C<error()>
method. Takes no arguments, returns an error message explaining the failure.

=head2 id

    my $paste_id = $paster->id;

Must be called after a successfull call to C<retrieve()>. Takes no arguments,
returns a paste ID number of the last retrieved paste irrelevant of whether
an ID or a URI was given to C<retrieve()>

=head2 uri

    my $paste_uri = $paster->uri;

Must be called after a successfull call to C<retrieve()>. Takes no arguments,
returns a L<URI> object with the URI pointing to the last retrieved paste
irrelevant of whether an ID or a URI was given to C<retrieve()>

=head2 results

    my $last_results_ref = $paster->results;

Must be called after a successfull call to C<retrieve()>. Takes no arguments,
returns the exact same hashref the last call to C<retrieve()> returned.
See C<retrieve()> method for more information.

=head2 ua

    my $old_LWP_UA_obj = $paster->ua;

    $paster->ua( LWP::UserAgent->new( timeout => 10, agent => 'foos' );

Returns a currently used L<LWP::UserAgent> object used for retrieving
pastes. Takes one optional argument which must be an L<LWP::UserAgent>
object, and the object you specify will be used in any subsequent calls
to C<retrieve()>.

=head1 SEE ALSO

L<LWP::UserAgent>, L<URI>

=head1 AUTHOR

Zoffix Znet, C<< <zoffix at cpan.org> >>
(L<http://zoffix.com>, L<http://haslayout.net>)

=head1 BUGS

Please report any bugs or feature requests to C<bug-www-phpficom-retrieve at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=WWW-PhpfiCom-Retrieve>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::PhpfiCom::Retrieve

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=WWW-PhpfiCom-Retrieve>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/WWW-PhpfiCom-Retrieve>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/WWW-PhpfiCom-Retrieve>

=item * Search CPAN

L<http://search.cpan.org/dist/WWW-PhpfiCom-Retrieve>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2008 Zoffix Znet, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

