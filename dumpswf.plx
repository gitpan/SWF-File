#!/usr/bin/perl

use SWF::Parser;
use SWF::Element;
use SWF::BinStream::File;

my $count = 0;

if (@ARGV==0) {
    print STDERR <<USAGE;
dumpswf.plx - Parse SWF file and dump it as a perl script.
  perl dumpswf.plx swfname [saveto]
USAGE

    exit(1);
} elsif (@ARGV==2) {
    open(F, ">$ARGV[1]") or die "Can't open $ARGV[1]";
    select F;
}

print <<START;
use SWF::Element;
use SWF::File;

die "This script creates '$ARGV[0]' SWF file. A new file name is needed.\\n" unless \$ARGV[0];
\$new = SWF::File->new("\$ARGV[0].swf");

# $ARGV[0]  SWF header

START

my $p=SWF::Parser->new('header-callback' => \&header, 'tag-callback' => \&data);
$p->parse_file($ARGV[0]);

print <<END;

\$new->close;
END


sub header {
    my ($self, $signature, $version, $length, $xmin, $ymin, $xmax, $ymax, $rate, $count)=@_;
    print STDERR <<HEADER;
Header:
SIGNATURE = $signature
VERSION = $version
File length = $length
Rect size = ($xmin, $ymin)-($xmax, $ymax)
Frame rate = $rate
Frame count = $count

HEADER
    print <<HEADER2;
\$new->Version($version);
\$new->FrameSize($xmin, $ymin, $xmax, $ymax);
\$new->FrameRate($rate);
#\$new->FrameCount($count);

# $ARGV[0]  SWF tags

HEADER2
}

sub data {
    my ($self, $tag, $length, $stream)=@_;
    my $t = SWF::Element::Tag->new(Tag=>$tag, Length=>$length);
    my ($tagname) = ref($t)=~/:([^:]+)$/;
 
    print STDERR <<BLOCK;
Data block:$count
Tag ID = $tag
Tag Name = $tagname
Length = $length
BLOCK
    print "# Tag No.: $count\n";
    $count++;
    my $element=SWF::Element::Tag->new(Tag=>$tag, Length=>$length);
    eval {
	$element->unpack($stream);
    };
    if ($@) {
	my $mes = $@;
	$element->dumper;
	die $mes;
    }
    $element->dumper;
    print "->pack(\$new);\n";
}
