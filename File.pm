package SWF::File;

use strict;
use vars qw($VERSION @ISA);

use SWF::Element;
use SWF::BinStream::File;

{
    my $s=SWF::Element::Tag::ShowFrame->new;
    *{SWF::Element::Tag::ShowFrame::pack_orig} = $s->can('pack');
    *{SWF::Element::Tag::ShowFrame::pack} = sub {
	$_[1]->{_header_FrameCount}++ if $_[1]->isa('SWF::File');
	&SWF::Element::Tag::ShowFrame::pack_orig;
    }
}

$VERSION = '0.01';
@ISA = ('SWF::BinStream::Write::SubStream');

sub new {
    my ($class, $file, %header) = @_;
    my $stream = SWF::BinStream::File::Write->new($file);
    my $self = $stream->sub_stream;

    bless $self, ref($class)||$class;

    $self->Version  ( $header{Version}   || 5  );
    $self->FrameRate( $header{FrameRate} || 12 );
    $self->FrameSize( $header{FrameSize} || [0, 0, 12800, 9600] );
    $self;
}

sub Version {
    $_[0]->{_header_Version} = $_[1] if defined $_[1];
    $_[0]->{_header_Version};
}

sub FrameRate {
    $_[0]->{_header_FrameRate} = $_[1] if defined $_[1];
    $_[0]->{_header_FrameRate};
}

sub FrameCount {
    $_[0]->{_header_FrameCount} = $_[1] if defined $_[1];
    $_[0]->{_header_FrameCount};
}


sub FrameSize {
    my $self = shift;

    return $self->{_header_FrameSize} if @_==0;

    if (eval{$_[0]->isa('SWF::Element::RECT')}) {
	$self->{_header_FrameSize} = $_[0]->clone;
    } else {
	my @param;

	if (ref($_[0]) eq 'ARRAY') {
	    @param = @{$_[0]};
	} else {
	    @param = @_;
	}
	@param = map {(qw/Xmin Ymin Xmax Ymax/)[$_], $param[$_]} (0..3) if (@param == 4);
	$self->{_header_FrameSize} = SWF::Element::RECT->new(@param);
    }
}

sub close {
    my $self = shift;
    my $file_stream = $self->{_parent};

    $file_stream->set_string('FWS');
    $file_stream->set_UI8($self->Version);
    my $temp = $file_stream->sub_stream;
    $self->FrameSize->pack($temp);
    $file_stream->set_UI32( 3+1+4+ $temp->tell +2+2+ $self->tell);  # Total File Length
    $temp->flush_stream;
    $file_stream->set_UI16($self->FrameRate * 256);
    $file_stream->set_UI16($self->FrameCount);
    $self->SUPER::flush_stream;
    $file_stream->close;
}

sub flush_stream {}

1;
__END__

=head1 NAME

SWF::File - Create SWF file.

=head1 SYNOPSIS

  use SWF::File;

  $swf = SWF::File->new('movie.swf');
  # set header data
  $swf->Version(4);
  $swf->FrameSize( 0, 0, 1000, 1000);
  $swf->FrameRate(12);
  # set tags
  $tag = SWF::Element::Tag->new( .... )
  $tag->pack($swf);
  ....
  # save SWF and close
  $swf->close;

=head1 DESCRIPTION

I<SWF::File> module can be used to make SWF (Macromedia Flash(R)) movie.
I<SWF::File> is a subclass of I<SWF::BinStream::Write>, so you can pack
I<SWF::Element::Tag>s in it.

=head2 METHODS

=over 4

=item SWF::File->new( $filename )

Creates a new SWF file.

=item $swf->Version( [$version] )

Sets and gets SWF version number. Default is 5.
You should set it to default if you don't know which version the SWF tags 
you use are supported with. Neither I<SWF::File> nor I<SWF::Element> support 
the version control of the specific tags.

=item $swf->FrameRate( [$framerate] )

Sets and gets the frame rate of the movie (frames per second).
Default is 12.

=item $swf->FrameSize( [$x1, $y1, $x2, $y2] )

Sets the bounding box size of the movie frame in TWIPs (1 TWIP = 1/20 pixel),
and gets the size as I<SWF::Element::RECT> object.
Default is (0, 0, 12800, 9600).

=item $swf->FrameCount( [$count] )

Sets and gets the frame count of the movie.
Usually you don't need to set because I<SWF::File> object automatically count
the I<ShowFrame> tags. If you want to set the different value, you should set
it just before I<$swf-E<gt>close>.

=item $swf->close

Saves SWF to the file and closes it.

=back

=head1 COPYRIGHT

Copyright 2001 Yasuhiro Sasama (ySas), <ysas@nmt.ne.jp>

This library is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<SWF::BinStream>, L<SWF::Element>

SWF file format and SWF file reference in SWF SDK.

=cut
