package SWF::Parser;

use strict;
use vars qw($VERSION);

$VERSION = '0.03';

use SWF::BinStream;
use Carp;

sub new {
    my $class = shift;
    my %param = @_;
    my $self = { _header          => {},
		 _tag             => {},
	     };
    my $a;

    foreach $a(qw(header-callback tag-callback)) {
	$self->{"_$a"}=$param{$a}||(sub{0});
    }
    $self->{'_stream'}=$param{'stream'}||(SWF::BinStream::Read->new('', sub{ die "The stream ran short by $_[0] bytes."}));


    bless $self, $class;
}

sub parse {
    my $self = shift;
    my $stream = $self->{'_stream'};

#    unless (defined $_[0]) {
#	if (my $bytes=$stream->Length) {
#	    carp "Data remains $bytes bytes in the stream.";
#	}
#	return $self;
#    }
    $stream->add_stream($_[0]);
    eval {
	unless (exists $self->{'_header'}) {
	    $self->parsetag while $stream->Length;
	} else {
	    $self->parseheader;
	}
    };
    if ($@) {
	return $self if ($@=~/^The stream ran short by/);
	die $@;
    }
    $self;
}

sub parse_file {
    my($self, $file) = @_;
    no strict 'refs';  # so that a symbol ref as $file works
    local(*F);
    unless (ref($file) || $file =~ /^\*[\w:]+$/) {
	# Assume $file is a filename
	open(F, $file) || die "Can't open $file: $!";
	$file = *F;
    }
    binmode($file);
    my $chunk = '';
    while(read($file, $chunk, 512)) {
	$self->parse($chunk);
    }
    close($file);
    $self->eof;
}

sub eof
{
    shift->parse(undef);
}

sub parseheader {
    my $self = shift;
    my $stream = $self->{'_stream'};
    my $header = $self->{'_header'};
    $header->{'signature'} = $stream->get_string(3) unless exists $header->{'signature'};
    $header->{'version'} = $stream->get_UI8 unless exists $header->{'version'};
    $header->{'filelen'} = $stream->get_UI32 unless exists $header->{'filelen'};
    $header->{'nbits'} = $stream->get_bits(5) unless exists $header->{'nbits'};
    my ($nbits)=$header->{'nbits'};
    $header->{'xmin'} = $stream->get_sbits($nbits) unless exists $header->{'xmin'};
    $header->{'xmax'} = $stream->get_sbits($nbits) unless exists $header->{'xmax'};
    $header->{'ymin'} = $stream->get_sbits($nbits) unless exists $header->{'ymin'};
    $header->{'ymax'} = $stream->get_sbits($nbits) unless exists $header->{'ymax'};
    $header->{'rate'} = $stream->get_UI16 / 256 unless exists $header->{'rate'};
    $header->{'count'} = $stream->get_UI16 unless exists $header->{'count'};
    $self->header(@{$header}{qw(signature version filelen xmin ymin xmax ymax rate count)});
    delete $self->{'_header'};
}

sub parsetag {
    my $self = shift;
    my $tag = $self->{'_tag'};
    my $stream = $self->{'_stream'};
    $tag->{'header'}=$stream->get_UI16 unless exists $tag->{'header'};
    unless (exists $tag->{'length'}) {
	my $length = ($tag->{'header'} & 0x3f);
	$length=$stream->get_UI32 if ($length == 0x3f);
	$tag->{'length'}=$length;
    }
    unless (exists $tag->{'data'}) {
	my $data=$stream->get_string($tag->{'length'});
	$tag->{'data'}=SWF::BinStream::Read->new($data, sub{die 'Short!'});
    }
    $self->tag($tag->{'header'} >> 6, $tag->{'length'}, $tag->{'data'});
    $self->{'_tag'}={};
}

sub header {
#    my ($self, $signature, $version, $length, $xmin, $ymin, $xmax, $ymax, $rate, $count)=@_;

    $_[0]->{'_header-callback'}->(@_);
}

sub tag {
#    my ($self, $tag, $length, $stream)=@_;

    $_[0]->{'_tag-callback'}->(@_);
}

1;

__END__

=head1 NAME

SWF::Parser - Parse SWF file.

=head1 SYNOPSIS

  use SWF::Parser;

  $parser = SWF::Parser->new( header-callback => \&header, tag-callback => \&tag);
  # parse binary data
  $parser->parse( $data );
  # or parse SWF file
  $parser->parse_file( 'flash.swf' );

=head1 DESCRIPTION

I<SWF::Parser> module provides a parser for SWF (Macromedia Flash(R))
file. It splits SWF into a header and tags and calls user subroutines.

=head2 METHODS

=over 4

=item SWF::Parser->new( header-callback => \&headersub, tag-callback => \&tagsub [, stream => $stream])

Creates a parser.
The parser calls user subroutines when find SWF header and tags.
You can set I<SWF::BinStream::Read> object as the read stream.
If not, internal stream is used.

=item &headersub( $self, $signature, $version, $length, $xmin, $ymin, $xmax, $ymax, $framerate, $framecount )

You should define a I<header-callback> subroutine in your script.
It is called with the following arguments:

  $self:       Parser object itself.
  $signature:  Always 'FWS'.
  $version:    SWF version No.
  $length:     File length.
  $xmin, $ymin, $xmax, $ymax:
     Boundary rectangle size of frames, ($xmin,$ymin)-($xmax, $ymax), in TWIPS(1/20 pixels).
  $framerate:  The number of frames per seconds.
  $framecount: Total number of frames in the SWF.

=item &tagsub( $self, $tagno, $length, $datastream )

You should define a I<tag-callback> subroutine in your script.
It is called with the following arguments:

  $self:       Parser object itself.
  $tagno:      The ID number of the tag.
  $length:     Length of tag.
  $datastream: The SWF::BinStream::Read object that can be read the rest of tag data.


=item $parser->parse( $data )

parses the data block as a SWF.
Can be called multiple times.

=item $parser->parse_file( $file );

parses a SWF file.
The argument can be a filename or an already opened file handle.

=item $parser->parseheader;

parses a SWF header and calls I<&headersub>.
You don't need to call this method specifically because 
this method is usually called from I<parse> method.

=item $parser->parsetag;

parses SWF tags and calls I<&tagsub>.
You don't need to call this method specifically because 
this method is usually called from I<parse> method.
You can use this method to re-parse I<MiniFileStructure> of I<DefineSprite>.

=back

=head1 COPYRIGHT

Copyright 2000 Yasuhiro Sasama (ySas), <ysas@nmt.ne.jp>

This library is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<SWF::BinStream>, L<SWF::Element>

SWF file format and SWF file reference in SWF SDK.


=cut
