BEGIN { $| = 1; print "1..12\n"; }
END {print "not ok 1\n" unless $loaded;}

use SWF::Element;
use SWF::File;
use SWF::Parser;

$loaded=1;

eval{
    $new = SWF::File->new('test.swf');
};
print "not " if $@;
print "ok 1\n";

eval {
    $new->Version(5);
    $new->FrameSize(0, 0, 6400, 4800);
    $new->FrameRate(20);
};
print "not " if $@;
print "ok 2\n";

eval {
  SWF::Element::Tag::BackgroundColor->new(
    BackgroundColor => SWF::Element::RGB->new(
        Red => 255,
        Green => 255,
        Blue => 255,
    ),
)->pack($new);

  SWF::Element::Tag::DefineShape3->new(
    ShapeID => 1,
    ShapeBounds => SWF::Element::RECT->new(
        Xmin => -1373,
        Ymin => -1273,
        Xmax => 1313,
        Ymax => 1333,
    ),
    Shapes => SWF::Element::SHAPEWITHSTYLE3->new(
        FillStyles => SWF::Element::Array::FILLSTYLEARRAY3->new([
            SWF::Element::FILLSTYLE3->new(
                FillStyleType => 0,
                Color => SWF::Element::RGBA->new(
                    Red => 255,
                    Green => 0,
                    Blue => 0,
                    Alpha => 255,
                ),
            ),
        ]),
        ShapeRecords => SWF::Element::Array::SHAPERECARRAY3->new([
            SWF::Element::SHAPEREC3::NEWSHAPE->new(
                MoveX => -30,
                MoveY => -1240,
                Fill0Style => 1,
            ),
            SWF::Element::SHAPERECn::CURVEDEDGE->new(
                ControlX => 512,
                ControlY => -1240,
                AnchorX => 896,
                AnchorY => -868,
            ),
            SWF::Element::SHAPERECn::CURVEDEDGE->new(
                ControlX => 1280,
                ControlY => -496,
                AnchorX => 1280,
                AnchorY => 30,
            ),
            SWF::Element::SHAPERECn::CURVEDEDGE->new(
                ControlX => 1280,
                ControlY => 556,
                AnchorX => 896,
                AnchorY => 928,
            ),
            SWF::Element::SHAPERECn::CURVEDEDGE->new(
                ControlX => 512,
                ControlY => 1300,
                AnchorX => -30,
                AnchorY => 1300,
            ),
            SWF::Element::SHAPERECn::CURVEDEDGE->new(
                ControlX => -572,
                ControlY => 1300,
                AnchorX => -956,
                AnchorY => 928,
            ),
            SWF::Element::SHAPERECn::CURVEDEDGE->new(
                ControlX => -1340,
                ControlY => 556,
                AnchorX => -1340,
                AnchorY => 30,
            ),
            SWF::Element::SHAPERECn::CURVEDEDGE->new(
                ControlX => -1340,
                ControlY => -496,
                AnchorX => -956,
                AnchorY => -868,
            ),
            SWF::Element::SHAPERECn::CURVEDEDGE->new(
                ControlX => -572,
                ControlY => -1240,
                AnchorX => -30,
                AnchorY => -1240,
            ),
        ]),
    ),
)->pack($new);

  SWF::Element::Tag::FrameLabel->new(
    Label => 'TEST SWF',
)->pack($new);

  SWF::Element::Tag::PlaceObject2->new(
    Flags => 6,
    Depth => 2,
    CharacterID => 1,
    Matrix => SWF::Element::MATRIX->new(
        ScaleX => 1,
        ScaleY => 1,
        RotateSkew0 => 0,
        RotateSkew1 => 0,
        TranslateX => 3200,
        TranslateY => 2400,
    ),
)->pack($new);
# Tag No.: 3
  SWF::Element::Tag::ShowFrame->new(
)->pack($new);
# Tag No.: 4
  SWF::Element::Tag::End->new(
)->pack($new);

    $new->close;
};

print "not " if $@;
print "ok 3\n";

eval {
    $p = SWF::Parser->new( 'header-callback' =>\&header, 'tag-callback' =>\&tag );
};
print "not " if $@;
print "ok 4\n";

$tagtest=6;
$labelf=0;
$p->parse_file('test.swf');

print "not " unless $labelf;
print "ok $tagtest\n";

unlink 'test.swf';

sub header {
    my ($self, $signature, $version, $length, $xmin, $ymin, $xmax, $ymax, $framerate, $framecount ) = @_;

    print "not " if $signature ne 'FWS' or $version != 5 or $framerate != 20;
    print "ok 5\n";
}

sub tag {
    my ($self, $tagno, $length, $datastream ) = @_;

    my $element=SWF::Element::Tag->new(Tag=>$tagno, Length=>$length);
    eval {
	$element->unpack($datastream);
    };
    print "not " if ($@);
    print "ok $tagtest\n";
    $tagtest++;
    $labelf=1 if (ref($element) =~/FrameLabel/ and $element->Label eq 'TEST SWF');
}
