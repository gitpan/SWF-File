package SWF::Element;

require v5.6.0;

use strict;
use vars qw($VERSION @ISA);

use Carp;
use SWF::BinStream;

$VERSION = '0.23';

sub new {
    my $class = shift;
    my $self = [];

    $class=ref($class)||$class;

    bless $self, $class;
    $self->_init;
    $self->configure(@_) if @_;
    $self;
}

sub clone {
    my $source = shift;
    croak "Can't clone a class" unless ref($source);
    my $f = 0;
    my @attr = map {($f=($f==0)||not ref($_)) ? $_ : $_->clone} $source->configure;
    $source->new(@attr);
}

sub new_element {
    my $self = shift;
    my $name = shift;
    my $element;

    eval {$element = $self->element_type($name)->new(@_)};
    croak $@ if $@;
    $element;
}

sub element_type {
    no strict 'refs';
    return ${(ref($_[0])||$_[0]).'::_Element_Types'}{$_[1]};
}

sub element_names {
    no strict 'refs';
    return @{(ref($_[0])||$_[0]).'::_Element_Names'};
}

sub configure {
    my ($self, @param)=@_;
    @param = @{$param[0]} if (ref($param[0]) eq 'ARRAY');

    if (@param==0) {
	my @names=$self->element_names;
	my @result=();
	my $key;
	for $key (@names) {
	    push @result, $key, $self->$key();
	}
	return @result;
    } elsif (@param==1) {
	my $key = $param[0];
	return $self->$key();
    } else {
	my ($key, $value);
	while (($key, $value) = splice(@param, 0, 2)) {
	    $self->$key($value);
	}
	return $self;
    }
}

sub defined {
    my $self = shift;
    my @names=$self->element_names;
    my $d;

    for my $key (@names) {
	if ($self->element_type($key) !~ /^\$(.*)$/) {
	    $d = $self->$key->defined;
	    last if $d;
	} else {
	    $d = defined $self->$key;
	    last if $d;
	}
    }
    return $d;
}

sub dumper {
    my ($self, $outputsub, $indent)=@_;
    my @names=$self->element_names;

    $indent ||= 0;
    $outputsub||=\&_default_output;

    &$outputsub(ref($self)."->new(\n", 0);
    for my $key (@names) {
	no warnings 'uninitialized';
	if ($self->element_type($key) =~/^\$/) {
	    my $p = $self->$key;
	    $p = "\"$p\"" unless $p=~/^[-\d.]+$/;
	    &$outputsub("$key => $p,\n", $indent+1) if defined($self->$key);
	} elsif ($self->$key->defined) {
	    &$outputsub("$key => ", $indent+1);
	    $self->$key->dumper($outputsub, $indent+1);
	    &$outputsub(",\n", 0);
	}
    }
    &$outputsub(")", $indent);
}

sub _default_output {print ' ' x ($_[1] * 4), $_[0]};

# _init, pack and unpack need to be overridden in the subclass.

sub _init {   # set attributes, parameters, etc.
}

sub pack {   # pack to SWF binary block
    my $self = shift;
    my $stream = shift;

    for my $key ($self->element_names) {
	if ($self->element_type($key) !~ /^\$(.*)$/) {
	    $self->$key->pack($stream, @_);
	} else {
	    my $setsub = "set_$1";
	    $stream->$setsub($self->$key);
	}
    }
}

sub unpack { # unpack SWF binary block
    my $self = shift;
    my $stream = shift;

    for my $key ($self->element_names) {
	if ($self->element_type($key) !~ /^\$(.*)$/) {
	    $self->$key->unpack($stream, @_);
	} else {
	    my $getsub = "get_$1";
	    $self->$key($stream->$getsub);
	}
    }
}

# Utility sub to create subclass.

sub _create_class {
    no strict 'refs';

    my $classname = shift; 
    my $isa = shift;
    my $base = ((@_ % 2) ? pop : 0);

    $classname = "SWF::Element::$classname";

    my $element_names = \@{"${classname}::_Element_Names"};
    my $element_types = \%{"${classname}::_Element_Types"};

    $isa = [$isa] unless ref($isa) eq 'ARRAY';
    @{"${classname}::ISA"}=map {$_ ? "SWF::Element::$_" : "SWF::Element"} @$isa;
    while (@_) {
	my $k = shift;
	my $v = shift;
	my $base1 = $base;
	push @$element_names, $k;

	if ($v !~ /^\$/) {
	    my $type = $element_types->{$k} = "SWF::Element::$v";
	    *{"${classname}::$k"} = sub {
		my $self = shift;
		if (@_) {
		    my $p = $_[0];
		    if (UNIVERSAL::isa($p, $type) or not defined $p) {
			$self->[$base1] = $p;
		    } else {
			$self->[$base1] = $type->new unless defined $self->[$base1];
			$self->[$base1]->configure(@_);
		    }
		} else {
		    $self->[$base1] = $type->new unless defined $self->[$base1];
		}
		$self->[$base1];
	    };
	} else {
	    $element_types->{$k} = $v;
	    *{"${classname}::$k"} = sub {
		my ($self, $data) = @_;
		$self->[$base1] = $data if @_>=2;
		$self->[$base1];
	    };
	}

	$base++;
 
    }
}

sub _create_flag_accessor {
    no strict 'refs';
    my ($name, $flagfield, $bit, $len) = @_;
    my $pkg = (caller)[0];

    $len ||=1;
    my $field = (1<<$len - 1)<<$bit;

    *{"${pkg}::$name"} = sub {
	my ($self, $set) = @_;
	my $flags = $self->$flagfield;

	if (defined $set) {
	    $flags &= ~$field;
	    $flags |= $set<<$bit;
	    $self->$flagfield($flags);
	}
	return ($flags & $field) >> $bit;
    }
}

# Create subclasses.

_create_class('ID', 'Scalar');
_create_class('Depth', 'Scalar');
_create_class('BinData', 'Scalar');
_create_class('RGB', '',
	      Red   => '$UI8',
	      Green => '$UI8',
	      Blue  => '$UI8');
_create_class('RGBA', '',
	      Red   => '$UI8',
	      Green => '$UI8',
	      Blue  => '$UI8',
	      Alpha => '$UI8');
_create_class('RECT', '',
	      Xmin => '$', Ymin => '$',
	      Xmax => '$', Ymax => '$');
_create_class('MATRIX', '',
	      ScaleX      => '$', ScaleY      => '$',
	      RotateSkew0 => '$', RotateSkew1 => '$',
	      TranslateX  => '$', TranslateY  => '$');
_create_class('CXFORM', '',
	      RedMultTerm   => '$', 
	      GreenMultTerm => '$',
	      BlueMultTerm  => '$',
	      RedAddTerm    => '$',
	      GreenAddTerm  => '$',
	      BlueAddTerm   => '$');
_create_class('CXFORMWITHALPHA', 'CXFORM',
	      RedMultTerm   => '$', 
	      GreenMultTerm => '$',
	      BlueMultTerm  => '$',
	      AlphaMultTerm => '$',
	      RedAddTerm    => '$',
	      GreenAddTerm  => '$',
	      BlueAddTerm   => '$',
	      AlphaAddTerm  => '$');
_create_class('STRING', 'Scalar');
_create_class('PSTRING', 'STRING');
_create_class('FILLSTYLE1', '',
	      FillStyleType  => '$UI8',
	      Color          => 'RGB',
	      GradientMatrix => 'MATRIX',
	      Gradient       => 'Array::GRADIENT1',
	      BitmapID       => 'ID',
	      BitmapMatrix   => 'MATRIX');
_create_class('FILLSTYLE3', 'FILLSTYLE1',
	      FillStyleType  => '$UI8',
	      Color          => 'RGBA',
	      GradientMatrix => 'MATRIX',
	      Gradient       => 'Array::GRADIENT3',
	      BitmapID       => 'ID',
	      BitmapMatrix   => 'MATRIX');
_create_class('GRADRECORD1', '',
	      Ratio => '$UI8',
	      Color => 'RGB');
_create_class('GRADRECORD3', '',
	      Ratio => '$UI8',
	      Color => 'RGBA');
_create_class('LINESTYLE1', '',
	      Width => '$UI16',
	      Color => 'RGB');
_create_class('LINESTYLE3', '',
	      Width => '$UI16',
	      Color => 'RGBA');
_create_class('SHAPE', '',
	      ShapeRecords => 'Array::SHAPERECORDARRAY1');
_create_class('SHAPEWITHSTYLE1', 'SHAPE',
	      FillStyles   => 'Array::FILLSTYLEARRAY1',
	      LineStyles   => 'Array::LINESTYLEARRAY1',
	      ShapeRecords => 'Array::SHAPERECORDARRAY1');
_create_class('SHAPEWITHSTYLE2', 'SHAPEWITHSTYLE1',
	      FillStyles   => 'Array::FILLSTYLEARRAY2',
	      LineStyles   => 'Array::LINESTYLEARRAY2',
	      ShapeRecords => 'Array::SHAPERECORDARRAY2');
_create_class('SHAPEWITHSTYLE3', 'SHAPEWITHSTYLE2',
	      FillStyles   => 'Array::FILLSTYLEARRAY3',
	      LineStyles   => 'Array::LINESTYLEARRAY3',
	      ShapeRecords => 'Array::SHAPERECORDARRAY3');
_create_class('SHAPERECORD1', '');
_create_class('SHAPERECORD2', 'SHAPERECORD1');
_create_class('SHAPERECORD3', 'SHAPERECORD1');
_create_class('SHAPERECORD1::STYLECHANGERECORD', 'SHAPERECORD1',
	      MoveDeltaX => '$',
	      MoveDeltaY => '$',
	      FillStyle0 => '$',
	      FillStyle1 => '$',
	      LineStyle  => '$' );
_create_class('SHAPERECORD2::STYLECHANGERECORD', ['SHAPERECORD1::STYLECHANGERECORD', 'SHAPERECORD2'],
	      MoveDeltaX => '$',
	      MoveDeltaY => '$',
	      FillStyle0 => '$',
	      FillStyle1 => '$',
	      LineStyle  => '$',
	      FillStyles => 'Array::FILLSTYLEARRAY2',
	      LineStyles => 'Array::LINESTYLEARRAY2');
_create_class('SHAPERECORD3::STYLECHANGERECORD', ['SHAPERECORD2::STYLECHANGERECORD', 'SHAPERECORD3'],
	      MoveDeltaX => '$',
	      MoveDeltaY => '$',
	      FillStyle0 => '$',
	      FillStyle1 => '$',
	      LineStyle  => '$',
	      FillStyles => 'Array::FILLSTYLEARRAY3',
	      LineStyles => 'Array::LINESTYLEARRAY3');
_create_class('SHAPERECORDn::STRAIGHTEDGERECORD', ['SHAPERECORD1', 'SHAPERECORD2', 'SHAPERECORD3'],
	      DeltaX => '$', DeltaY => '$');
_create_class('SHAPERECORDn::CURVEDEDGERECORD',  ['SHAPERECORD1', 'SHAPERECORD2', 'SHAPERECORD3'],
	      ControlDeltaX => '$', ControlDeltaY => '$',
	      AnchorDeltaX  => '$', AnchorDeltaY  => '$');
_create_class('Tag', '');
_create_class('MORPHFILLSTYLE', '',
	      FillStyleType       => '$UI8',
	      StartColor          => 'RGBA',
	      EndColor            => 'RGBA',
	      StartGradientMatrix => 'MATRIX',
	      EndGradientMatrix   => 'MATRIX',
	      Gradient            => 'Array::MORPHGRADIENT',
	      BitmapID            => 'ID',
	      StartBitmapMatrix   => 'MATRIX',
	      EndBitmapMatrix     => 'MATRIX');
_create_class('MORPHGRADRECORD', '',
	      StartRatio => '$UI8', StartColor => 'RGBA',
	      EndRatio   => '$UI8', EndColor   => 'RGBA');
_create_class('MORPHLINESTYLE', '',
	      StartWidth => '$UI16', EndWidth => '$UI16',
	      StartColor => 'RGBA',  EndColor => 'RGBA');
_create_class('BUTTONRECORD1', '',
	      ButtonStates => '$UI8',
	      CharacterID  => 'ID',
	      PlaceDepth   => 'Depth',
	      PlaceMatrix  => 'MATRIX');
_create_class('BUTTONRECORD2', 'BUTTONRECORD1',
	      ButtonStates   => '$UI8',
	      CharacterID    => 'ID',
	      PlaceDepth     => 'Depth',
	      PlaceMatrix    => 'MATRIX',
	      ColorTransform => 'CXFORMWITHALPHA');
_create_class('BUTTONCONDACTION', '',
	      Condition => '$UI16', Actions => 'Array::ACTIONRECORDARRAY');
_create_class('TEXTRECORD1', '');
_create_class('TEXTRECORD2', 'TEXTRECORD1');
_create_class('TEXTRECORD::TYPE0', ['','TEXTRECORD1','TEXTRECORD2'],
	      GlyphEntries => 'Array::GLYPHENTRYARRAY');
_create_class('GLYPHENTRY', '',
	      GlyphIndex => '$', GlyphAdvance => '$');
_create_class('TEXTRECORD1::TYPE1', 'TEXTRECORD1',
	      FontID     => 'ID',
	      TextColor  => 'RGB',
	      XOffset    => '$SI16',
	      YOffset    => '$SI16',
	      TextHeight => '$UI16');
_create_class('TEXTRECORD2::TYPE1', ['TEXTRECORD1::TYPE1', 'TEXTRECORD2'],
	      FontID     => 'ID',
	      TextColor  => 'RGBA',
	      XOffset    => '$SI16',
	      YOffset    => '$SI16',
	      TextHeight => '$UI16');
_create_class('SOUNDINFO', '',
	      SyncFlags       => '$',
	      InPoint         => '$UI32',
	      OutPoint        => '$UI32',
	      LoopCount       => '$UI16',
	      EnvelopeRecords => 'Array::SOUNDENVELOPEARRAY');
_create_class('SOUNDENVELOPE', '',
	      Pos44 => '$UI32', LeftLevel => '$UI16', RightLevel => '$UI16');
_create_class('ACTIONTagNumber', 'Scalar');
_create_class('ACTIONRECORD', '',
	      Tag        => 'ACTIONTagNumber',
	      LocalLabel => '$');
_create_class('ACTIONDATA', 'Scalar');
_create_class('ACTIONDATA::String', 'ACTIONDATA');
_create_class('ACTIONDATA::Property', 'ACTIONDATA');
_create_class('ACTIONDATA::NULL', 'ACTIONDATA');
_create_class('ACTIONDATA::Register', 'ACTIONDATA');
_create_class('ACTIONDATA::Boolean', 'ACTIONDATA');
_create_class('ACTIONDATA::Double', 'ACTIONDATA');
_create_class('ACTIONDATA::Integer', 'ACTIONDATA');
_create_class('ACTIONDATA::Lookup', 'ACTIONDATA');
_create_class('CLIPACTIONRECORD', '',
	      EventFlags6  => '$UI16',
	      EventFlags   => '$UI16',
	      KeyCode      => '$UI8',
	      Actions      => 'Array::ACTIONRECORDARRAY');
_create_class('ASSET', '',
	      ID     => 'ID',
	      Name   => 'STRING');

##########

package SWF::Element::Scalar;

use overload 
    '""' => \&value,
    '0+' => \&value,
    '++' => sub {${$_[0]}++},
    '--' => sub {${$_[0]}--},
    '='  => \&clone,
    fallback =>1,
    ;
@SWF::Element::Scalar::ISA = ('SWF::Element');

sub new {
    my $class = shift;
    my ($self, $data);

    $self = \$data;
    bless $self, ref($class)||$class;
    $self->_init;
    $self->configure(@_) if @_;
    $self;
}

sub clone {
    my $self = shift;
    Carp::croak "Can't clone a class" unless ref($self);
    my $new = $self->new($self->value);
}

sub configure {
    my ($self, $newval)=@_;
#    Carp::croak "Can't set $newval in ".ref($self) unless $newval=~/^[\d.]*$/;
    unless (ref($newval)) {
	$$self = $newval;
    } elsif (eval{$newval->isa('SWF::Element::Scalar')}) {
	$$self = $newval->value;
    }
    $self;
}
sub value {
    ${$_[0]};
}

sub defined {
    defined ${$_[0]};
}

# 'pack' and 'unpack' should be overridden in the subclass or
# the owner class is responsible for packing/unpacking THIS.
 
sub pack {
    Carp::croak "'pack' should be overridden in ".ref($_[0]);
}

sub unpack {
    Carp::croak "'unpack' should be overridden in ".ref($_[0]);
}

sub dumper {
    my ($self, $outputsub)=@_;

    $outputsub||=\&SWF::Element::_default_output;

    &$outputsub($self->value, 0);
}

sub _init {}


##########

package SWF::Element::ID;

sub pack {
    my ($self, $stream) = @_;

    $stream->set_UI16($self->value);
}

sub unpack {
    my ($self, $stream) = @_;

    $self->configure($stream->get_UI16);
}

##########

package SWF::Element::Depth;

sub pack {
    my ($self, $stream) = @_;

    $stream->set_UI16($self->value);
}

sub unpack {
    my ($self, $stream) = @_;

    $self->configure($stream->get_UI16);
}

##########

package SWF::Element::Array;

sub new {
    my $class = shift;
    my $self = [];

    bless $self, ref($class)||$class;
    $self->_init;
    $self->configure(@_) if @_;

    $self;
}

sub configure {
    my ($self, @param)=@_;
    @param = @{$param[0]} if (ref($param[0]) eq 'ARRAY' and ref($param[0][0]));
    for my $p (@param) {
	my $element = $self->new_element;
	if (UNIVERSAL::isa($p, ref($element)) or not defined $p) {
	    $element = $p;
	} elsif (ref($p) eq 'ARRAY') {
	    $element->configure($p);
	} else {
	  Carp::croak "Element type mismatch: ".ref($p)." in ".ref($self);
	}
	push @$self, $element;
    }
    $self;
}

sub clone {
    my $self = $_[0];
    die "Can't clone a class" unless ref($self);
    my $new = $self->new;
    for my $i (@$self) {
	push @$new, $i->clone;
    }
    $new;
}

sub pack {
    my $self = shift;

    for my $element (@$self) {
	$element->pack(@_);
    }
    $self->last(@_);
}

sub unpack {
    my $self = shift;
    {
	my $element = $self->new_element;
	$element->unpack(@_);
	last if $self->is_last($element);
	push @$self, $element;
	redo;
    }
}

sub defined {
    return @{shift()} > 0;
}

sub dumper {
    my ($self, $outputsub, $indent) = @_;

    $indent ||= 0;
    $outputsub||=\&SWF::Element::_default_output;

    &$outputsub(ref($self)."->new([\n", 0);
    for my $i (@$self) {
	&$outputsub('', $indent+1);
	$i->dumper($outputsub, $indent+1);
	&$outputsub(",\n", 0);
    }
    &$outputsub("])", $indent);
}

sub _init {
    my $self = shift;

    for my $element (@$self) {
	last unless ref($element) eq '' or  ref($element) eq 'ARRAY';
	my $new = $self->new_element;
	last unless ref($new);
	$new->configure($element);
	$element = $new;
    }
}

sub new_element {}
sub is_last {0}
sub last {};

sub _create_array_class {
    no strict 'refs';
    my ($classname, $isa, $newelement, $last, $is_last)=@_;

    $classname = "Array::$classname";
    SWF::Element::_create_class($classname, $isa);

    $classname = "SWF::Element::$classname";
    if ($newelement) {
	$newelement = "SWF::Element::$newelement";
	*{"${classname}::new_element"} = sub {shift; $newelement->new(@_)};
    }
    *{"${classname}::last"} = $last if $last;
    *{"${classname}::is_last"} = $is_last if $is_last;
}

_create_array_class('FILLSTYLEARRAY1', 'Array1', 'FILLSTYLE1');
_create_array_class('FILLSTYLEARRAY2', 'Array2', 'FILLSTYLE1');
_create_array_class('FILLSTYLEARRAY3', 'Array2', 'FILLSTYLE3');
_create_array_class('GRADIENT1',       'Array1', 'GRADRECORD1');
_create_array_class('GRADIENT3',       'Array1', 'GRADRECORD3');
_create_array_class('LINESTYLEARRAY1', 'Array1', 'LINESTYLE1');
_create_array_class('LINESTYLEARRAY2', 'Array2', 'LINESTYLE1');
_create_array_class('LINESTYLEARRAY3', 'Array2', 'LINESTYLE3');
_create_array_class('SHAPERECORDARRAY1',  'Array',  'SHAPERECORD1',
		    sub {$_[1]->set_bits(0,6)},
                    sub {$_[1]->isa('SWF::Element::SHAPERECORDn::ENDSHAPERECORD')});

_create_array_class('SHAPERECORDARRAY2', 'Array::SHAPERECORDARRAY1', 'SHAPERECORD2');
_create_array_class('SHAPERECORDARRAY3', 'Array::SHAPERECORDARRAY2', 'SHAPERECORD3');
_create_array_class('MORPHFILLSTYLEARRAY', 'Array2',    'MORPHFILLSTYLE');
_create_array_class('MORPHLINESTYLEARRAY', 'Array2',    'MORPHLINESTYLE');
_create_array_class('MORPHGRADIENT',       'Array1',    'MORPHGRADRECORD');
_create_array_class('BUTTONRECORDARRAY1',  'Array',     'BUTTONRECORD1',
                     sub {$_[1]->set_UI8(0)},
                     sub {$_[1]->ButtonStates == 0});

_create_array_class('BUTTONRECORDARRAY2', 'Array::BUTTONRECORDARRAY1', 'BUTTONRECORD2');
_create_array_class('BUTTONCONDACTIONARRAY', 'Array', 'BUTTONCONDACTION');
_create_array_class('GLYPHSHAPEARRAY1',          'Array', 'SHAPE');
_create_array_class('GLYPHSHAPEARRAY2',          'Array', 'SHAPE');
_create_array_class('CODETABLE',            'Array::Scalar');
_create_array_class('FONTADVANCETABLE',     'Array::Scalar');
_create_array_class('FONTBOUNDSTABLE',      'Array', 'RECT', sub {});
_create_array_class('TEXTRECORDARRAY1',     'Array', 'TEXTRECORD1',
                    sub {$_[1]->set_UI8(0)},
                    sub {$_[1]->isa('SWF::Element::TEXTRECORD::End')});

_create_array_class('TEXTRECORDARRAY2',   'Array::TEXTRECORDARRAY1', 'TEXTRECORD2');
_create_array_class('GLYPHENTRYARRAY',    'Array1', 'GLYPHENTRY');
_create_array_class('SOUNDENVELOPEARRAY', 'Array1', 'SOUNDENVELOPE');
_create_array_class('ACTIONRECORDARRAY',  'Array',  'ACTIONRECORD',
                    sub {$_[1]->set_UI8(0)},
                    sub {$_[1]->Tag == 0});
_create_array_class('ACTIONDATAARRAY', 'Array',  'ACTIONDATA',
                    sub {});
_create_array_class('STRINGARRAY',     'Array3', 'STRING');
_create_array_class('CLIPACTIONRECORDARRAY', 'Array',  'CLIPACTIONRECORD',
                    sub {$_[1]->set_UI32(0)},
                    sub {$_[1]->EventFlags == 0});
_create_array_class('ASSETARRAY',      'Array3', 'ASSET');
_create_array_class('TAGARRAY',        'Array',  'Tag',
                    sub {},
                    sub {$_[1]->tag_name eq 'End' && ((push @{$_[0]}, $_[1]),1)});

##########

package SWF::Element::Array::Scalar;

@SWF::Element::Array::Scalar::ISA=qw(SWF::Element::Array);

sub configure {
    my $self = shift;

    if (ref($_[0]) eq 'ARRAY') {
	push @$self, @{$_[0]};
    } else {
	push @$self, @_;
    }
    $self;
}

sub clone {
    my $self = $_[0];
    die "Can't clone a class" unless ref($self);
    $self->new(@$self);
}

sub dumper {
    my ($self, $outputsub, $indent) = @_;
    my @data;

    &$outputsub(ref($self)."->new([\n", 0);
    for (my $i = 0; $i < @$self; $i+=8) {
	my @data = @$self[$i..($i+7 > $#$self ? $#$self : $i+7)];
	&$outputsub(sprintf("%5d,"x@data."\n", @data), 0);
    }
    &$outputsub("])", $indent);
}

##########

package SWF::Element::Array1;
use vars qw(@ISA);

@ISA=qw(SWF::Element::Array);

sub pack {
    my $self = shift;
    my $count = @$self;

    $_[0]->set_UI8($count);
    $self->_pack(@_);
}

sub _pack {
    my $self = shift;

    for my $element (@$self) {
	$element->pack(@_);
    }
}


sub unpack {
    my $self = shift;

    $self->_unpack($_[0]->get_UI8, @_);
}

sub _unpack {
    my $self = shift;
    my $count = shift;

    while (--$count>=0) {
	my $element = $self->new_element;
	$element->unpack(@_);
	push @$self, $element;
    }
}

##########

package SWF::Element::Array2;
use vars qw(@ISA);

@ISA=qw(SWF::Element::Array1);

sub pack {
    my $self=shift;
    my $stream=$_[0];
    my $count=@$self;

    if ($count>254) {
	$stream->set_UI8(0xFF);
	$stream->set_UI16($count);
    } else {
	$stream->set_UI8($count);
    }
    $self->_pack(@_);
}

sub unpack {
    my $self=shift;
    my $stream=$_[0];
    my $count=$stream->get_UI8;

    $count=$stream->get_UI16 if $count==0xFF;

    $self->_unpack($count, @_);
}

##########

package SWF::Element::Array3;
use vars qw(@ISA);

@ISA=qw(SWF::Element::Array1);

sub unpack {
    my $self = shift;

    $self->_unpack($_[0]->get_UI16, @_);
}

sub pack {
    my $self = shift;

    $_[0]->set_UI16(scalar @$self);
    $self->_pack(@_);
}

##########

package SWF::Element::Array::STRINGARRAY;

sub configure {
    my ($self, @param)=@_;
    @param = @{$param[0]} if (ref($param[0]) eq 'ARRAY');
    for my $p (@param) {
	my $element = $self->new_element;
	if (UNIVERSAL::isa($p, ref($element)) or not defined $p) {
	    $element = $p;
	} elsif (ref($p) eq '') {
	    $element->configure($p);
	} else {
	  Carp::croak "Element type mismatch: ".ref($p)." in ".ref($self);
	}
	push @$self, $element;
    }
    $self;
}

##########

package SWF::Element::RECT;

sub pack {
    my ($self, $stream)=@_;
    $stream->flush_bits;
    $stream->set_sbits_list(5, $self->Xmin, $self->Xmax, $self->Ymin, $self->Ymax);
}

sub unpack {
    my ($self, $stream)=@_;
    $stream->flush_bits;
    my $nbits=$stream->get_bits(5);

    for my $i(qw/Xmin Xmax Ymin Ymax/) {
	$self->$i($stream->get_sbits($nbits));
    }
}

##########

package SWF::Element::MATRIX;

sub _init {
    my $self = shift;
    $self->ScaleX(1);
    $self->ScaleY(1);
}

sub pack {
    my ($self, $stream)=@_;

    $stream->flush_bits;
    if ($self->ScaleX != 1 or $self->ScaleY != 1) {
	$stream->set_bits(1,1);
	$stream->set_sbits_list(5, $self->ScaleX * 65536, $self->ScaleY * 65536);
    } else {
	$stream->set_bits(0,1);
    }
    if ($self->RotateSkew0 != 0 or $self->RotateSkew1 != 0) {
	$stream->set_bits(1,1);
	$stream->set_sbits_list(5, $self->RotateSkew0 * 65536, $self->RotateSkew1 * 65536);
    } else {
	$stream->set_bits(0,1);
    }
	$stream->set_sbits_list(5, $self->TranslateX, $self->TranslateY);
}

sub unpack {
    my ($self, $stream)=@_;
    my ($hasscale, $hasrotate);

    $stream->flush_bits;
    if ($hasscale = $stream->get_bits(1)) {
	my $nbits=$stream->get_bits(5);
#	$nbits = 32 if $nbits == 0; # ???
	$self->ScaleX($stream->get_sbits($nbits) / 65536);
	$self->ScaleY($stream->get_sbits($nbits) / 65536);
    } else {
	$self->ScaleX(1);
	$self->ScaleY(1);
    }
    if ($hasrotate = $stream->get_bits(1)) {
	my $nbits=$stream->get_bits(5);
#	$nbits = 32 if $nbits == 0; # ???
	$self->RotateSkew0($stream->get_sbits($nbits) / 65536);
	$self->RotateSkew1($stream->get_sbits($nbits) / 65536);
    } else {
	$self->RotateSkew0(0);
	$self->RotateSkew1(0);
    }
    my $nbits=$stream->get_bits(5);
#    my $scalex = $self->ScaleX;
#    $nbits = 32 if $nbits == 0 and ($scalex == 0 or $scalex >= 16383.99998474 or $scalex <= -16383.99998474); # ???
    $self->TranslateX($stream->get_sbits($nbits));
    $self->TranslateY($stream->get_sbits($nbits));
}

sub defined {
    my $self = shift;

    return (defined($self->TranslateX)  or defined($self->TranslateY) or
	    $self->ScaleX != 1          or $self->ScaleY != 1 or
	    defined($self->RotateSkew0) or defined($self->RotateSkew1));
}

sub scale {
    my ($self, $xscale, $yscale)=@_;
    $yscale=$xscale unless defined $yscale;

    $self->ScaleX($self->ScaleX * $xscale);
    $self->RotateSkew0($self->RotateSkew0 * $xscale);
    $self->ScaleY($self->ScaleY * $yscale);
    $self->RotateSkew1($self->RotateSkew1 * $yscale);
    $self;
}

sub moveto {
    my ($self, $x, $y)=@_;
    $self->TranslateX($x);
    $self->TranslateY($y);
    $self;
}

sub rotate {
    my ($self, $degree)=@_;
    $degree = $degree*3.14159265358979/180;
    my $sin = sin($degree);
    my $cos = cos($degree);
    my $a = $self->ScaleX;
    my $b = $self->RotateSkew0;
    my $c = $self->RotateSkew1;
    my $d = $self->ScaleY;
    $self->ScaleX($a*$cos-$b*$sin);
    $self->RotateSkew0($a*$sin+$b*$cos);
    $self->RotateSkew1($c*$cos-$d*$sin);
    $self->ScaleY($c*$sin+$d*$cos);

    $self;
}

##########

package SWF::Element::CXFORM;

sub pack {
    my ($self, $stream)=@_;
    my @param = map $self->$_, $self->element_names;
    my $half  = @param>>1;
    my @add   = @param[0..$half-1];
    my @mult  = @param[$half..$#param];

    my $hasAdd  = grep defined $_, @param[0..$half-1];
    my $hasMult = grep defined $_, @param[$half..$#param];

    $stream->flush_bits;
    if (grep defined $_, @mult) {
	$stream->set_bits(1,1);
    } else {
	$stream->set_bits(0,1);
	@mult = ();
    }
    if (grep defined $_, @add) {
	$stream->set_bits(1,1);
    } else {
	$stream->set_bits(0,1);
	@add = ();
    }
    $stream->set_sbits_list(4, @add, @mult) if @add or @mult;
}

sub unpack {
    my ($self, $stream)=@_;

    $stream->flush_bits;
    my $hasAdd  = $stream->get_bits(1);
    my $hasMult = $stream->get_bits(1);
    my $nbits = $stream->get_bits(4);
    my @names = $self->element_names;
    my $half = @names>>1;

    if ($hasMult) {
	for my $i (@names[0..$half-1]) {
	    $self->$i($stream->get_sbits($nbits));
	}
    }
    if ($hasAdd) {
	for my $i (@names[$half..$#names]) {
	    $self->$i($stream->get_sbits($nbits));
	}
    }
}

##########

package SWF::Element::BinData;

use Data::TemporaryBag;

sub _init {
    my $self = shift;

    $$self = Data::TemporaryBag->new;
}

sub configure {
    my ($self, $newval) = @_;

    if (ref($newval)) {
	if ($newval->isa('Data::TemporaryBag')) {
	    $$self = $newval->clone;
	} elsif ($newval->isa('SWF::Element::BinData')) {
	    $self = $newval->clone;
	} else {
	  Carp::croak "Can't set ".ref($newval)." in ".ref($self);
	}
    } else {
	$$self = Data::TemporaryBag->new($newval) if defined $newval;
    }
    $self;
}

sub clone {
    my $self = shift;

    $self->new($$self);
}

for my $sub (qw/substr value defined/) {
    no strict 'refs';
    *{"SWF::Element::BinData::$sub"} = sub {
	my $self=shift;
	$$self->$sub(@_);
    };
}

sub add {
    my $self = shift;

    $$self->add(@_);
    $self;
}

sub Length {
    $ {$_[0]}->length;
}

sub pack {
    my ($self, $stream)=@_;
    my $size = $self->Length;
    my $pos = 0;

    while ($size > $pos) {
	$stream->set_string($self->substr($pos, 1024));
	$pos += 1024;
    }
}

sub unpack {
    my ($self, $stream, $len)=@_;

    while ($len > 0) {
	my $size = ($len > 1024) ? 1024 : $len;
	$self->add($stream->get_string($size));
	$len -= $size;
    }
}

sub save {
    my ($self, $file) = @_;
    no strict 'refs';  # so that a symbol ref as $file works
    local(*F);
    unless (ref($file) or $file =~ /^\*[\w:]+$/) {
	# Assume $file is a filename
	open(F, "> $file") or die "Can't open $file: $!";
	$file = *F;
    }
    binmode($file);
    my $stream = SWF::BinStream::Write->new;
    $stream->autoflush(1000, sub {print $file $_[1]});
    $self->pack($stream);
    print $file $stream->flush_stream;
    close $file;
}

sub load {
    my($self, $file) = @_;
    no strict 'refs';  # so that a symbol ref as $file works
    local(*F);
    unless (ref($file) or $file =~ /^\*[\w:]+$/) {
	# Assume $file is a filename
	open(F, $file) or die "Can't open $file: $!";
	$file = *F;
    }
    binmode($file);
    my $size = (stat $file)[7];
    my $stream = SWF::BinStream::Read->new('', sub {my $data; read $file, $data, 1000; $_[0]->add_stream($data)});
    $self->unpack($stream, $size);
    close $file;
}

{
    my $label = 'A';

    sub dumper {
	my ($self, $outputsub, $indent) = @_;
	
	$indent ||= 0;
	$outputsub||=\&SWF::Element::_default_output;
	
	&$outputsub(ref($self)."->new\n", 0);
	
	my $size = $self->Length;
	my $pos = 0;
	
	while ($size > $pos) {
	    my $data = CORE::pack('u', $self->substr($pos, 1024));
	    &$outputsub("->add(unpack('u', <<'$label'))\n$data$label\n", $indent+1);
	    $pos += 1024;
	    $label++;
	}
    }
}

##########

package SWF::Element::STRING;

sub pack {
    my ($self, $stream)=@_;
    $stream->set_string($self->value."\0");
}

sub unpack {
    my ($self, $stream)=@_;
    my $str='';
    my $char;
    $str.=$char while (($char = $stream->get_string(1)) ne "\0");
    $self->configure($str);
}

sub dumper {
    my ($self, $outputsub)=@_;
    my $data = $self->value;

    $data =~ s/([\\$@\"])/\\$1/gs;
    $data =~ s/([\x00-\x1F\x80-\xFF])/sprintf('\\x%.2X', ord($1))/ges;
    $outputsub||=\&SWF::Element::_default_output;

    &$outputsub("\"$data\"", 0);
}

##########

package SWF::Element::PSTRING;

sub pack {
    my ($self, $stream)=@_;
    my $str = $self->value;

    $stream->set_UI8(length($str));
    $stream->set_string($str);
}

sub unpack {
    my ($self, $stream)=@_;
    my $len = $stream->get_UI8;

    $self->configure($stream->get_string($len));
}

##########

package SWF::Element::FILLSTYLE1;

sub pack {
    my ($self, $stream)=@_;
    my $style=$self->FillStyleType;
    $stream->set_UI8($style);
    if ($style==0x00) {
	$self->Color->pack($stream);
    } elsif ($style==0x10 or $style==0x12) {
	$self->GradientMatrix->pack($stream);
	$self->Gradient->pack($stream);
    } elsif ($style==0x40 or $style==0x41) {
	$self->BitmapID->pack($stream);
	$self->BitmapMatrix->pack($stream);
    }
}

sub unpack {
    my ($self, $stream)=@_;
    my $style = $self->FillStyleType($stream->get_UI8);
    if ($style==0x00) {
	$self->Color->unpack($stream);
    } elsif ($style==0x10 or $style==0x12) {
	$self->GradientMatrix->unpack($stream);
	$self->Gradient->unpack($stream);
    } elsif ($style==0x40 or $style==0x41) {
	$self->BitmapID->unpack($stream);
	$self->BitmapMatrix->unpack($stream);
    }
}

##########

package SWF::Element::SHAPE;

sub pack {
    my ($self, $stream, $nfillbits, $nlinebits)=@_;
#    my ($fillidx, $lineidx)=(-1,-1);

    $stream->flush_bits;

=begin possible_unnecessary

    for my $shaperec (@{$self->ShapeRecords}) {
	next unless $shaperec->isa('SWF::Element::SHAPERECORD1::STYLECHANGERECORD');
	my $style;
	$style   = $shaperec->FillStyle0;
	$fillidx = $style if (defined $style and $fillidx < $style);
	$style   = $shaperec->FillStyle1;
	$fillidx = $style if (defined $style and $fillidx < $style);
	$style   = $shaperec->LineStyle;
	$lineidx = $style if (defined $style and $lineidx < $style);
    }
    if ($fillidx>=0) {
	$nfillbits=1;
	$nfillbits++ while ($fillidx>=(1<<$nfillbits));
    } else {
	$nfillbits=0;
    }
    if ($lineidx>=0) {
	$nlinebits=1;
	$nlinebits++ while ($lineidx>=(1<<$nlinebits));
    } else {
	$nlinebits=0;
    }

=end possible_unnecessary

=cut

    $stream->set_bits($nfillbits, 4);
    $stream->set_bits($nlinebits, 4);

    $self->ShapeRecords->pack($stream, \$nfillbits, \$nlinebits);
}

sub unpack {
    my ($self, $stream)=@_;
    my ($nfillbits, $nlinebits);

    $stream->flush_bits;
    $nfillbits=$stream->get_bits(4);
    $nlinebits=$stream->get_bits(4);

    $self->ShapeRecords->unpack($stream, \$nfillbits, \$nlinebits);
}

##########

package SWF::Element::SHAPEWITHSTYLE1;

sub pack {
    my ($self, $stream)=@_;
    my ($fillidx, $lineidx)=($#{$self->FillStyles}+1, $#{$self->LineStyles}+1);
    my ($nfillbits, $nlinebits)=(0,0);

    $self->FillStyles->pack($stream);
    $self->LineStyles->pack($stream);

    if ($fillidx>0) {
	$nfillbits=1;
	$nfillbits++ while ($fillidx>=(1<<$nfillbits));
    } else {
	$nfillbits=0;
    }
    if ($lineidx>0) {
	$nlinebits=1;
	$nlinebits++ while ($lineidx>=(1<<$nlinebits));
    } else {
	$nlinebits=0;
    }

    $stream->flush_bits;
    $stream->set_bits($nfillbits, 4);
    $stream->set_bits($nlinebits, 4);

    $self->ShapeRecords->pack($stream, \$nfillbits, \$nlinebits);
}

sub unpack {
    my ($self, $stream)=@_;

    $self->FillStyles->unpack($stream);
    $self->LineStyles->unpack($stream);
    $self->SUPER::unpack($stream);
}

##########

package SWF::Element::SHAPERECORD1;

sub unpack {
    my ($self, $stream, $nfillbits, $nlinebits)=@_;

    if ($stream->get_bits(1)) { # Edge

	if ($stream->get_bits(1)) {
	    bless $self, 'SWF::Element::SHAPERECORDn::STRAIGHTEDGERECORD';
	} else {
	    bless $self, 'SWF::Element::SHAPERECORDn::CURVEDEDGERECORD';
	}
	$self->_init;
	$self->unpack($stream);

    } else { # New Shape or End of Shape

	my $flags = $stream->get_bits(5);
	if ($flags==0) {
	    bless $self, 'SWF::Element::SHAPERECORDn::ENDSHAPERECORD';
	} else {
	    bless $self, ref($self).'::STYLECHANGERECORD';
	    $self->_init;
	    $self->unpack($stream, $nfillbits, $nlinebits, $flags);
	}
    }
}

sub pack {
    Carp::croak "Not enough data to pack ".ref($_[0]);
}

sub AUTOLOAD { # auto re-bless with proper sub class by specified accessor.
    my ($self, @param)=@_;
    my ($name, $class);

    return if $SWF::Element::SHAPERECORD1::AUTOLOAD =~/::DESTROY$/;

    Carp::croak "No such method: $SWF::Element::SHAPERECORD1::AUTOLOAD" unless $SWF::Element::SHAPERECORD1::AUTOLOAD=~/::([A-Z]\w*)$/;
    $name = $1;
    $class = ref($self);

    for my $subclass ("${class}::STYLECHANGERECORD", 'SWF::Element::SHAPERECORDn::STRAIGHTEDGERECORD', 'SWF::Element::SHAPERECORDn::CURVEDEDGERECORD') {
	$class=$subclass, last if $subclass->element_type($name);
    }
    Carp::croak "Element '$name' is NOT in $class " if $class eq ref($self);

    bless $self, $class;
    $self->$name(@param);
}

##########

package SWF::Element::SHAPERECORD1::STYLECHANGERECORD;

sub pack {
    my ($self, $stream, $nfillbits, $nlinebits)=@_;
    my ($flags)=0;

    my $j=0;
    for my $i (qw/MoveDeltaX FillStyle0 FillStyle1 LineStyle/) {
	$flags |=(1<<$j) if defined $self->$i;
	$j++;
    }
    $stream->set_bits($flags, 6);
    $stream->set_sbits_list(5, $self->MoveDeltaX, $self->MoveDeltaY) if ($flags & 1);
    $stream->set_bits($self->FillStyle0, $$nfillbits) if ($flags & 2);
    $stream->set_bits($self->FillStyle1, $$nfillbits) if ($flags & 4);
    $stream->set_bits($self->LineStyle , $$nlinebits) if ($flags & 8);
}

sub unpack {
    my ($self, $stream, $nfillbits, $nlinebits, $flags)=@_;

    if ($flags & 1) { # MoveTo
	my ($nbits)=$stream->get_bits(5);
	$self->MoveDeltaX($stream->get_sbits($nbits));
	$self->MoveDeltaY($stream->get_sbits($nbits));
    }
    if ($flags & 2) { # FillStyle0
	$self->FillStyle0($stream->get_bits($$nfillbits));
    }
    if ($flags & 4) { # FillStyle1
	$self->FillStyle1($stream->get_bits($$nfillbits));
    }
    if ($flags & 8) { # LineStyle
	$self->LineStyle($stream->get_bits($$nlinebits));
    }
}

##########

package SWF::Element::SHAPERECORD2::STYLECHANGERECORD;

sub pack {
    my ($self, $stream, $nfillbits, $nlinebits)=@_;
    my ($flags)=0;

    my $j=0;
    for my $i (qw/MoveDeltaX FillStyle0 FillStyle1 LineStyle/) {
	$flags |=(1<<$j) if defined $self->$i;
	$j++;
    }
    $flags |= 16 if @{$self->FillStyles}>0 or @{$self->LineStyles}>0;
    $stream->set_bits($flags, 6);
    $stream->set_sbits_list(5, $self->MoveDeltaX, $self->MoveDeltaY) if ($flags & 1);
    $stream->set_bits($self->FillStyle0, $$nfillbits) if ($flags & 2);
    $stream->set_bits($self->FillStyle1, $$nfillbits) if ($flags & 4);
    $stream->set_bits($self->LineStyle , $$nlinebits) if ($flags & 8);
    if ($flags & 16) { # NewStyles (SHAPERECORD2,3)
	my ($fillidx, $lineidx)=($#{$self->FillStyles}+1, $#{$self->LineStyles}+1);
	$self->FillStyles->pack($stream);
	$self->LineStyles->pack($stream);
	if ($fillidx>0) {
	    $$nfillbits=1;
	    $$nfillbits++ while ($fillidx>=(1<<$$nfillbits));
	} else {
	    $$nfillbits=0;
	}
	if ($lineidx>0) {
	    $$nlinebits=1;
	    $$nlinebits++ while ($lineidx>=(1<<$$nlinebits));
	} else {
	    $$nlinebits=0;
	}
	$stream->set_bits($$nfillbits, 4);
	$stream->set_bits($$nlinebits, 4);
    }
}

sub unpack {
    my ($self, $stream, $nfillbits, $nlinebits, $flags)=@_;

    if ($flags & 1) { # MoveTo
	my ($nbits)=$stream->get_bits(5);
	$self->MoveDeltaX($stream->get_sbits($nbits));
	$self->MoveDeltaY($stream->get_sbits($nbits));
    }
    if ($flags & 2) { # FillStyle0
	$self->FillStyle0($stream->get_bits($$nfillbits));
    }
    if ($flags & 4) { # FillStyle1
	$self->FillStyle1($stream->get_bits($$nfillbits));
    }
    if ($flags & 8) { # LineStyle
	$self->LineStyle($stream->get_bits($$nlinebits));
    }
    if ($flags & 16) { # NewStyles (SHAPERECORD2,3)
	$self->FillStyles->unpack($stream);
	$self->LineStyles->unpack($stream);
	$$nfillbits=$stream->get_bits(4);
	$$nlinebits=$stream->get_bits(4);
    }
}

##########

package SWF::Element::SHAPERECORDn::STRAIGHTEDGERECORD;

sub unpack {
    my ($self, $stream)=@_;
    my $nbits = $stream->get_bits(4)+2;
    if ($stream->get_bits(1)) {
	$self->DeltaX($stream->get_sbits($nbits));
	$self->DeltaY($stream->get_sbits($nbits));
    } else {
	if ($stream->get_bits(1)) {
	    $self->DeltaX(0);
	    $self->DeltaY($stream->get_sbits($nbits));
	} else {
	    $self->DeltaX($stream->get_sbits($nbits));
	    $self->DeltaY(0);
	}
    }
}

sub pack {
    my ($self, $stream)=@_;
    my ($dx, $dy, $nbits);

    $stream->set_bits(3,2); # Type=1, Edge=1

    $dx=$self->DeltaX;
    $dy=$self->DeltaY;
    $nbits=SWF::BinStream::Write::get_maxbits_of_sbits_list($dx, $dy);
    $nbits=2 if ($nbits<2);
    $stream->set_bits($nbits-2,4);
    if ($dx==0) {
	$stream->set_bits(1,2); # GeneralLine=0, Vert=1
	$stream->set_sbits($dy, $nbits);
    } elsif ($dy==0) {
	$stream->set_bits(0,2); # GeneralLine=0, Vert=0
	$stream->set_sbits($dx, $nbits);
    } else {
	$stream->set_bits(1,1); # GeneralLine=1
	$stream->set_sbits($dx, $nbits);
	$stream->set_sbits($dy, $nbits);
    }
}

##########

package SWF::Element::SHAPERECORDn::CURVEDEDGERECORD;

sub unpack {
    my ($self, $stream)=@_;
    my ($nbits)=$stream->get_bits(4)+2;

    $self->ControlDeltaX($stream->get_sbits($nbits));
    $self->ControlDeltaY($stream->get_sbits($nbits));
    $self->AnchorDeltaX($stream->get_sbits($nbits));
    $self->AnchorDeltaY($stream->get_sbits($nbits));
}

sub pack {
    my ($self, $stream)=@_;

    my @d=( $self->ControlDeltaX,
            $self->ControlDeltaY,
            $self->AnchorDeltaX ,
            $self->AnchorDeltaY  );
    my $nbits = SWF::BinStream::Write::get_maxbits_of_sbits_list(@d);
    $nbits=2 if ($nbits<2);
    $stream->set_bits(2,2); # Type=1, Edge=0
    $stream->set_bits($nbits-2,4);
    for my $i (@d) {
	$stream->set_sbits($i, $nbits);
    }
}

##########

package SWF::Element::Tag;

my @tagname;

sub new {
    my ($class, %headerdata)=@_;
    my $self;
    my $length = $headerdata{Length};
    my $tag = $headerdata{Tag};

    $self = [];
    delete @headerdata{'Length','Tag'};

    if (defined $tag) {
	my $class = _tag_class($tag);
	bless $self, $class;
    } else {
	$class=ref($class)||$class;
	bless $self, $class;
    }
    $self->_init($length, $tag);
    $self->configure(%headerdata) if %headerdata;
    $self;
}

sub _init {
    my ($self, $length)=@_;

    $self->Length($length);
}

sub Length {
    my ($self, $len)=@_;
    $self->[0]=$len if defined $len;
    $self->[0];
}

sub unpack {   # unpack tag header, re-bless, and unpack individual data for the tag.
    my ($self, $stream)=@_;
    my ($header, $tag, $length);

    $header = $stream->get_UI16;
    $tag = $header>>6;
    $length = ($header & 0x3f);
    $length = $stream->get_UI32 if ($length == 0x3f);
    my $class = SWF::Element::Tag::_tag_class($tag);
    bless $self, $class;
    $self->_init($length, $tag);
    $self->unpack($stream);
}


sub pack {
    Carp::croak "Can't pack the unidentified tag.";
}

sub tag_number { undef }

sub _unpack {
    my $self = shift;

    $self->SUPER::unpack(@_);
}

sub _pack {
    my $self = shift;

    $self->SUPER::pack(@_);
}


sub _tag_class {
    return 'SWF::Element::Tag::'.($tagname[$_[0]]||'Unknown');
}

sub _create_tag {
    no strict 'refs';

    my $tagname = shift;
    my $tagno = shift;
    my $isa = shift||'Identified';

    SWF::Element::_create_class("Tag::$tagname", "Tag::$isa", @_, 1);

    $tagname[$tagno] = $tagname;
    *{"SWF::Element::Tag::${tagname}::tag_number"} = sub {$tagno};
    *{"SWF::Element::Tag::${tagname}::tag_name"} = sub {$tagname};
}

##  Unknown  ##

_create_tag('Unknown', 16, '',
	    'Tag'    => '$',
	    'Data'   => 'BinData');
{
    no strict 'refs';
    no warnings;
    *{"SWF::Element::Tag::Unknown::tag_number"} = sub {$_[0]->Tag};
}

##  Shapes  ##

_create_tag('DefineShape', 2, '',

	    ShapeID     => 'ID',
	    ShapeBounds => 'RECT',
	    Shapes      => 'SHAPEWITHSTYLE1');

_create_tag('DefineShape2', 22, 'DefineShape',

	    ShapeID     => 'ID',
	    ShapeBounds => 'RECT',
	    Shapes      => 'SHAPEWITHSTYLE2');

_create_tag('DefineShape3', 32, 'DefineShape',

	    ShapeID     => 'ID',
	    ShapeBounds => 'RECT',
	    Shapes      => 'SHAPEWITHSTYLE3');

_create_tag('DefineMorphShape', 46, '',

	    CharacterID     => 'ID',
	    StartBounds     => 'RECT',
	    EndBounds       => 'RECT',
	    MorphFillStyles => 'Array::MORPHFILLSTYLEARRAY',
	    MorphLineStyles => 'Array::MORPHLINESTYLEARRAY',
	    StartEdges      => 'SHAPE',
	    EndEdges        => 'SHAPE');

##  Bitmaps  ##

_create_tag('DefineBits', 6, '',

	    CharacterID=> 'ID',
	    JPEGData   => 'BinData');

_create_tag('JPEGTables', 8, '',

	    JPEGData => 'BinData');

_create_tag('DefineBitsJPEG2', 21, '',

	    CharacterID => 'ID',
	    JPEGData    => 'BinData');

_create_tag('DefineBitsJPEG3', 35, 'DefineBitsJPEG2',

	    CharacterID     => 'ID',
	    JPEGData        => 'BinData',
	    BitmapAlphaData => 'BinData');

_create_tag('DefineBitsLossless', 20, '',

	    CharacterID          => 'ID',
	    BitmapFormat         => '$UI8',
	    BitmapWidth          => '$UI16',
	    BitmapHeight         => '$UI16',
	    BitmapColorTableSize => '$UI8',
	    ZlibBitmapData       => 'BinData',
	    );

_create_tag('DefineBitsLossless2', 36, 'DefineBitsLossless',

	    CharacterID          => 'ID',
	    BitmapFormat         => '$UI8',
	    BitmapWidth          => '$UI16',
	    BitmapHeight         => '$UI16',
	    BitmapColorTableSize => '$UI8',
	    ZlibBitmapData       => 'BinData',
	    );

##  Buttons  ##

_create_tag('DefineButton', 7, '',

	    ButtonID    => 'ID',
	    Characters  => 'Array::BUTTONRECORDARRAY1',
	    Actions     => 'Array::ACTIONRECORDARRAY');

_create_tag('DefineButton2', 34, '',

	    ButtonID   => 'ID',
	    Flags      => '$UI8',
	    Characters => 'Array::BUTTONRECORDARRAY2',
	    Actions    => 'Array::BUTTONCONDACTIONARRAY');

_create_tag('DefineButtonCxform', 23, '',

	    ButtonID             => 'ID',
	    ButtonColorTransform => 'CXFORM');

_create_tag('DefineButtonSound', 17, '',

	    ButtonID => 'ID', 
	    ButtonSoundChar0 => 'ID', ButtonSoundInfo0 => 'SOUNDINFO',
	    ButtonSoundChar1 => 'ID', ButtonSoundInfo1 => 'SOUNDINFO',
	    ButtonSoundChar2 => 'ID', ButtonSoundInfo2 => 'SOUNDINFO',
	    ButtonSoundChar3 => 'ID', ButtonSoundInfo3 => 'SOUNDINFO');

##  Fonts & Texts  ##

_create_tag('DefineFont', 10, '',

	    FontID => 'ID', GlyphShapeTable => 'Array::GLYPHSHAPEARRAY1');

_create_tag('DefineFontInfo', 13, '',

	    FontID        => 'ID',
	    FontName      => 'PSTRING', 
	    FontFlags     => '$UI8',
	    CodeTable     => 'Array::CODETABLE'); 

_create_tag('DefineFontInfo2', 62, 'DefineFontInfo',

	    FontID        => 'ID',
	    FontName      => 'PSTRING', 
	    FontFlags     => '$UI8',
	    LanguageCode  => '$UI8',
	    CodeTable     => 'Array::CODETABLE'); 

_create_tag('DefineFont2', 48, '',

	    FontID           => 'ID', 
	    FontFlags        => '$UI8',
	    LanguageCode     => '$UI8',
	    FontName         => 'PSTRING', 
	    GlyphShapeTable  => 'Array::GLYPHSHAPEARRAY2',
	    CodeTable        => 'Array::CODETABLE',
	    FontAscent       => '$SI16',
	    FontDescent      => '$SI16',
	    FontLeading      => '$SI16',
	    FontAdvanceTable => 'Array::FONTADVANCETABLE',
	    FontBoundsTable  => 'Array::FONTBOUNDSTABLE',
	    FontKerningTable => 'FONTKERNINGTABLE');

_create_tag('DefineText', 11, '',

	    CharacterID => 'ID',
	    TextBounds  => 'RECT',
	    TextMatrix  => 'MATRIX',
	    TextRecords => 'Array::TEXTRECORDARRAY1');

_create_tag('DefineText2', 33, 'DefineText',

	    CharacterID => 'ID',
	    TextBounds  => 'RECT',
	    TextMatrix  => 'MATRIX',
	    TextRecords => 'Array::TEXTRECORDARRAY2');

_create_tag('DefineEditText', 37, '',

	    CharacterID  => 'ID',
	    Bounds       => 'RECT',
	    Flags        => '$UI16',
	    FontID       => 'ID',
	    FontHeight   => '$UI16',
	    TextColor    => 'RGBA',
	    MaxLength    => '$UI16',
	    Align        => '$UI8',
	    LeftMargin   => '$UI16',
	    RightMargin  => '$UI16',
	    Indent       => '$UI16',
	    Leading      => '$UI16',
	    VariableName => 'STRING',
	    InitialText  => 'STRING');

##  Sounds  ##

_create_tag('DefineSound', 14, '',

	    SoundID          => 'ID',
	    Flags            => '$UI8',
	    SoundSampleCount => '$UI32',
	    SoundData        => 'BinData');

_create_tag('StartSound', 15, '',

	    SoundID   => 'ID',
	    SoundInfo => 'SOUNDINFO');

_create_tag('SoundStreamBlock', 19, '',

	    StreamSoundData => 'BinData');

_create_tag('SoundStreamHead', 18, '',

	    Flags                  => '$UI16',
	    StreamSoundSampleCount => '$UI16');

_create_tag('SoundStreamHead2', 45, 'SoundStreamHead',

	    Flags                  => '$UI16',
	    StreamSoundSampleCount => '$UI16',
	    LatencySeek            => '$SI16');

##  Sprites  ##

_create_tag('DefineSprite', 39, '',

	    SpriteID    => 'ID',
	    FrameCount  => '$UI16',
	    ControlTags => 'Array::TAGARRAY');

##  Display list  ##

_create_tag('PlaceObject', 4, '',

	    CharacterID    => 'ID',
	    Depth          => 'Depth',
	    Matrix         => 'MATRIX',
	    ColorTransform => 'CXFORM');

_create_tag('PlaceObject2', 26, '',

	    Flags          => '$UI8',
	    Depth          => 'Depth',
	    CharacterID    => 'ID',
	    Matrix         => 'MATRIX',
	    ColorTransform => 'CXFORMWITHALPHA',
	    Ratio          => '$UI16',
	    Name           => 'STRING',
	    ClipDepth      => 'Depth',
	    ClipActions    => 'Array::CLIPACTIONRECORDARRAY');

_create_tag('RemoveObject', 5, '',

	    CharacterID => 'ID', Depth => 'Depth' );

_create_tag('RemoveObject2', 28, '',

	    Depth => 'Depth' );

_create_tag('ShowFrame', 1, '');

##  Control  ##

_create_tag('SetBackgroundColor', 9, '',

	    BackgroundColor => 'RGB' );

_create_tag('FrameLabel', 43, '',

	    Name => 'STRING',
	    NamedAnchorFlag => '$UI8' );

_create_tag('Protect', 24, '',

	    Reserved => '$UI16',
	    Password => 'STRING' );

_create_tag('EnableDebugger', 58, '',

	    Reserved => '$UI16',
	    Password => 'STRING' );

_create_tag('EnableDebugger2', 64, '',

	    Reserved => '$UI16',
	    Password => 'STRING' );

_create_tag('End', 0, '');

_create_tag('ExportAssets', 56, '',

	    Assets => 'Array::ASSETARRAY');

_create_tag('ImportAssets', 57, '',

	    URL    => 'STRING',
	    Assets => 'Array::ASSETARRAY');

##  Actions  ##

_create_tag('DoAction', 12, '',

	    Actions => 'Array::ACTIONRECORDARRAY');

_create_tag('DoInitAction', 59, '',

	    SpriteID => 'ID',
	    Actions  => 'Array::ACTIONRECORDARRAY');

##  Video  ##

_create_tag('DefineVideoStream', 60, '',

            CharacterID => 'ID',
            NumFrames   => '$UI16',
            Width       => '$UI16',
            Height      => '$UI16',
            VideoFlags  => '$UI8',
            CodecID     => '$UI8');

_create_tag('VideoFrame', 61, '',

            StreamID  => 'ID',
            FrameNum  => '$UI16',
            VideoData => 'BinData');

##  others?  ##

_create_tag('FreeCharacter', 3, '',

	    CharacterID => 'ID');

_create_tag('NameCharacter', 40, '',

	    CharacterID => 'ID',
	    Name        => 'STRING');



### Identified Tag base ###

package SWF::Element::Tag::Identified;

@SWF::Element::Tag::Identified::ISA = ('SWF::Element::Tag');

sub unpack {
    my $self = shift;
    my $stream = shift;

    my $start = $stream->tell;
    my $length = $self->Length;
    $self->_unpack($stream, @_) if $length>0;
    $stream->flush_bits;
    my $read = $stream->tell - $start;
    if ($read < $length) {
	$stream->get_string($length-$read);  # Skip the rest of tag data.
    } elsif ($read > $length) {
	Carp::croak ref($self)." unpacked $read bytes in excess of the described tag length, $length bytes.  The SWF may be collapsed or the module bug??";
    }
}

sub pack {
    my ($self, $stream)=@_;
    my $substream = $stream->sub_stream;

    $self->_pack($substream);
    my $header = $self->tag_number<<6;
    my $len = $substream->tell;
    if ($len >= 0x3f) {
	$header |= 0x3f;
	$stream->set_UI16($header);
	$stream->set_UI32($len);
    } else {
	$stream->set_UI16($header|$len);
    }
    $substream->flush_stream;
}


####  Unknown  ####
##########

package SWF::Element::Tag::Unknown;

sub _init {
    my $self = shift;
    my ($length, $tag) = @_;

    $self->SUPER::_init(@_);
    Carp::carp "Tag No. $tag is unknown.";
    $self->Tag($tag);
}

sub _unpack {
    my ($self, $stream)=@_;

    $self->Data->unpack($stream, $self->Length);
}

sub _pack {
    my ($self, $stream)=@_;

    $self->Data->pack($stream);
}

####  Shapes  ####
########

package SWF::Element::Tag::DefineMorphShape;

sub _unpack {
    my ($self, $stream)=@_;

    $self->CharacterID->unpack($stream);
    $self->StartBounds->unpack($stream);
    $self->EndBounds  ->unpack($stream);
    $stream->get_UI32; # Skip Offset
    $self->MorphFillStyles->unpack($stream);
    $self->MorphLineStyles->unpack($stream);
    $stream->flush_bits;
    $self->StartEdges->unpack($stream);
    $stream->flush_bits;
    $self->EndEdges->unpack($stream);
}

sub _pack {
    my ($self, $stream)=@_;

    $self->CharacterID->pack($stream);
    $self->StartBounds->pack($stream);
    $self->EndBounds  ->pack($stream);
    {
	my $tempstream=$stream->sub_stream;
	my ($nfillbits, $nlinebits) = (0, 0);
	my ($maxfill, $maxline) = ($#{$self->MorphFillStyles}, $#{$self->MorphLineStyles});
	if ($maxfill>0) {
	    $nfillbits++ while ($maxfill>=(1<<$nfillbits));
	    $nfillbits--;
	}
	if ($maxline>0) {
	    $nlinebits++ while ($maxline>=(1<<$nlinebits));
	    $nlinebits--;
	}
	$self->MorphFillStyles->pack($tempstream);
	$self->MorphLineStyles->pack($tempstream);
	$tempstream->flush_bits;
	$self->StartEdges->pack($tempstream, $nfillbits, $nlinebits);
	$tempstream->flush_bits;
	$stream->set_UI32($tempstream->tell);
	$tempstream->flush_stream;
    }
    $self->EndEdges->pack($stream, 0, 0);
    $stream->flush_bits;
}

##########

package SWF::Element::MORPHFILLSTYLE;

sub pack {
    my ($self, $stream)=@_;
    my $style=$self->FillStyleType;
    $stream->set_UI8($style);
    if ($style==0x00) {
	$self->StartColor->pack($stream);
	$self->EndColor->pack($stream);
    } elsif ($style==0x10 or $style==0x12) {
	$self->StartGradientMatrix->pack($stream);
	$self->EndGradientMatrix->pack($stream);
	$self->Gradient->pack($stream);
    } elsif ($style==0x40 or $style==0x41) {
	$self->BitmapID->pack($stream);
	$self->StartBitmapMatrix->pack($stream);
	$self->EndBitmapMatrix->pack($stream);
    }
}

sub unpack {
    my ($self, $stream)=@_;
    my $style = $self->FillStyleType($stream->get_UI8);
    if ($style==0x00) {
	$self->StartColor->unpack($stream);
	$self->EndColor->unpack($stream);
    } elsif ($style==0x10 or $style==0x12) {
	$self->StartGradientMatrix->unpack($stream);
	$self->EndGradientMatrix->unpack($stream);
	$self->Gradient->unpack($stream);
    } elsif ($style==0x40 or $style==0x41) {
	$self->BitmapID->unpack($stream);
	$self->StartBitmapMatrix->unpack($stream);
	$self->EndBitmapMatrix->unpack($stream);
    }
}


####  Bitmaps  ####
##########

package SWF::Element::Tag::DefineBits;

sub _unpack {
    my ($self, $stream)=@_;

    $self->CharacterID->unpack($stream);
    $self->JPEGData->unpack($stream, $self->Length - 2);
}

##########

package SWF::Element::Tag::DefineBitsJPEG2;

sub _unpack {
    my ($self, $stream)=@_;

    $self->CharacterID->unpack($stream);
#    $self->_unpack_JPEG($stream, $self->Length - 2);
    $self->JPEGData->unpack($stream, $self->Length - 2);
}

=pod

sub _unpack_JPEG {
    my ($self, $stream, $len) = @_;
    my ($data1, $data2);

    while (!$data2 and $len > 0) {
	my $size = ($len > 1000) ? 1000 : $len;
	$data1 = $stream->get_string($size);
	$len -= $size;
	if ($data1 =~/\xff$/ and $len>0) {
	    $data1 .= $stream->get_string(1);
	    $len--;
	}
	($data1, $data2) = split /\xff\xd9/, $data1;
	$self->BitmapJPEGEncoding->add($data1);
    }
    $self->BitmapJPEGEncoding->add("\xff\xd9");

    $self->BitmapJPEGImage($data2);
    while ($len > 0) {
	my $size = ($len > 1000) ? 1000 : $len;
	$data1 = $stream->get_string($size);
	$len -= $size;
	$self->BitmapJPEGImage->add($data1);
    }
}

=cut

##########

package SWF::Element::Tag::DefineBitsJPEG3;

sub _unpack {
    my ($self, $stream)=@_;

    $self->CharacterID->unpack($stream);
    my $offset = $stream->get_UI32;
#    $self->_unpack_JPEG($stream, $offset);
    $self->JPEGData->unpack($stream, $offset);
    $self->BitmapAlphaData->unpack($stream, $self->Length - $offset - 6);
}

sub _pack {
    my ($self, $stream)=@_;

    $self->CharacterID->pack($stream);
    $stream->set_UI32($self->JPEGData->Length);
    $self->JPEGData->pack($stream);
    $self->BitmapAlphaData->pack($stream);
}

##########

package SWF::Element::Tag::DefineBitsLossless;

sub _unpack {
    my ($self, $stream)=@_;
    my $length=$self->Length - 7;

#    delete @{$self}{qw/ColorTable BitmapImage/};

    $self->CharacterID->unpack($stream);
    $self->BitmapFormat($stream->get_UI8);
    $self->BitmapWidth($stream->get_UI16);
    $self->BitmapHeight($stream->get_UI16);
    if ($self->BitmapFormat == 3) {
	$self->BitmapColorTableSize($stream->get_UI8);
	$length--;
    }
    $self->ZlibBitmapData->unpack($stream, $length);
#    $self->decompress;
}

sub _pack {
    my ($self, $stream)=@_;

#    $self->compress if defined $self->{'ColorTable'} and defined $self->{'BitmapImage'};
    $self->CharacterID->pack($stream);
    $stream->set_UI8($self->BitmapFormat);
    $stream->set_UI16($self->BitmapWidth);
    $stream->set_UI16($self->BitmapHeight);
    $stream->set_UI8($self->BitmapColorTableSize) if $self->BitmapFormat == 3;
    $self->ZlibBitmapData->pack($stream);
}

sub decompress {
}

sub compress {
}

##########

package SWF::Element::Tag::JPEGTables;

sub _unpack {
    my ($self, $stream)=@_;

    $self->JPEGData->unpack($stream, $self->Length);
}

####  Buttons  ####

##########

package SWF::Element::BUTTONRECORD1;

sub unpack {
    my ($self, $stream)=@_;

    $self->ButtonStates($stream->get_UI8);
    return if $self->ButtonStates == 0;
    $self->CharacterID->unpack($stream);
    $self->PlaceDepth->unpack($stream);
    $self->PlaceMatrix->unpack($stream);
}

sub pack {
    my ($self, $stream)=@_;

    $stream->set_UI8($self->ButtonStates);
    return if $self->ButtonStates == 0;
    $self->CharacterID->pack($stream);
    $self->PlaceDepth->pack($stream);
    $self->PlaceMatrix->pack($stream);
}

{
    my $bit = 0;
    for my $f (qw/ButtonStateUp ButtonStateOver ButtonStateDown ButtonStateHitTest/) {
      SWF::Element::_create_flag_accessor($f, 'ButtonStates', $bit++);
    }
}

package SWF::Element::BUTTONRECORD2;

sub unpack {
    my ($self, $stream)=@_;

    $self->SUPER::unpack($stream);
    return if $self->ButtonStates == 0;
    $self->ColorTransform->unpack($stream);
}

sub pack {
    my ($self, $stream)=@_;

    $self->SUPER::pack($stream);
    return if $self->ButtonStates == 0;
    $self->ColorTransform->pack($stream);
}


##########

package SWF::Element::Tag::DefineButton2;

sub _unpack {
    my ($self, $stream)=@_;

    $self->ButtonID->unpack($stream);
    $self->Flags($stream->get_UI8);
    my $offset=$stream->get_UI16;
    $self->Characters->unpack($stream);
    $self->Actions->unpack($stream) if $offset;
}

sub _pack {
    my ($self, $stream)=@_;
    my $actions = $self->Actions;

    $self->ButtonID->pack($stream);
    $stream->set_UI8($self->Flags);
    my $substream = $stream->sub_stream;
    $self->Characters->pack($substream);
    $stream->set_UI16((@$actions>0) && ($substream->tell + 2));
    $substream->flush_stream;
    $actions->pack($stream) if (@$actions>0);
}

##########

package SWF::Element::Array::BUTTONCONDACTIONARRAY;

sub pack {
    my ($self, $stream)=@_;

    my $last=pop @$self;
    for my $element (@$self) {
	my $tempstream=$stream->sub_stream;
	$element->pack($tempstream);
	$stream->set_UI16($tempstream->tell + 2);
	$tempstream->flush_stream;
    }
    $stream->set_UI16(0);
    $last->pack($stream);
    push @$self, $last;
}

sub unpack {
    my ($self, $stream)=@_;
    my ($element, $offset);

    do {
	$offset=$stream->get_UI16;
	$element=$self->new_element;
	$element->unpack($stream);
	push @$self, $element;
    } until $offset==0;
}

##########

package SWF::Element::BUTTONCONDACTION;

{
    my $bit = 0;

    for my $f (qw/IdleToOverUp OverUpToIdle OverUpToOverDown OverDownToOverUp OverDownToOutDown OutDownToOverDown OutDownToIdle IdleToOverDown OverDownToIdle/) {
      SWF::Element::_create_flag_accessor("Cond$f", 'Condition', $bit++);
    }
  SWF::Element::_create_flag_accessor("CondKeyPress", 'Condition', 9, 7);

}

##########

package SWF::Element::Tag::DefineButtonSound;

sub _unpack {
    my ($self, $stream)=@_;

    $self->ButtonID->unpack($stream);
    for my $i (0..3) {
	my $bsc = "ButtonSoundChar$i";
	my $bsi = "ButtonSoundInfo$i";

	$self->$bsc->unpack($stream);
	if ($self->$bsc) {
	    $self->$bsi->unpack($stream);
	}
    }
}

sub _pack {
    my ($self, $stream)=@_;

    $self->ButtonID->pack($stream);
    for my $i (0..3) {
	my $bsc = "ButtonSoundChar$i";
	my $bsi = "ButtonSoundInfo$i";

	$self->$bsc->pack($stream);
	$self->$bsi->pack($stream) if $self->$bsc;
    }
}

####  Texts and Fonts  ####
##########

package SWF::Element::Array::GLYPHSHAPEARRAY1;

sub pack {
    my ($self, $stream)=@_;
    my $offset = @$self*2;

    $stream->set_UI16($offset);

    my $tempstream = $stream->sub_stream;
    my $last = pop @$self;

    for my $element (@$self) {
	$element->pack($tempstream, 1, 0);
	$stream->set_UI16($offset + $tempstream->tell);
    }
    $tempstream->flush_stream;
    $last->pack($stream);
    push @$self,$last;
}

sub unpack {
    my ($self, $stream)=@_;
    my $offset=$stream->get_UI16;

    $stream->get_string($offset-2); # skip offset table.
    for (my $i=0; $i < $offset/2; $i++) {
	my $element = $self->new_element;
	$element->unpack($stream);
	push @$self, $element;
    }
}

##########

package SWF::Element::Array::GLYPHSHAPEARRAY2;

sub pack {     # return wide offset flag (true => 32bit, false => 16bit)
    my ($self, $stream)=@_;
    my (@offset, $wideoffset);
    my $glyphcount=@$self;

    $offset[0]=0;
    my $tempstream=$stream->sub_stream;

    for my $element (@$self) {
	$element->pack($tempstream, 1, 0);
	push @offset, $tempstream->tell;  # keep glyph shape's offset.
    }

# Each offset should be added the offset table size.
# If the last offset is more than 65535, offsets are packed in 32bits each.

    if (($glyphcount+1)*2+$offset[-1] >= (1<<16)) {
	$wideoffset=1;
	for my $element (@offset) {
	    $stream->set_UI32(($glyphcount+1)*4+$element);
	}
    } else {
	$wideoffset=0;
	for my $element (@offset) {
	    $stream->set_UI16(($glyphcount+1)*2+$element);
	}
    }
    $tempstream->flush_stream;
    return $wideoffset;
}

sub unpack {
    my ($self, $stream, $wideoffset)=@_;
    my @offset;
    my $getoffset = ($wideoffset ? sub {$stream->get_UI32} : sub {$stream->get_UI16});
    my $origin = $stream->tell;

    $offset[0] = &$getoffset;
    my $count = $offset[0]>>($wideoffset+1);

    for (my $i = 1; $i < $count; $i++) {
	push @offset, &$getoffset;
    }
    my $pos = $stream->tell - $origin;
    my $offset = shift @offset;
    Carp::croak ref($self).": Font offset table seems to be collapsed." if $pos>$offset;
    $stream->get_string($pos-$offset) if $pos<$offset;
    for (my $i = 1; $i < $count; $i++) {
	my $element = $self->new_element;
	$element->unpack($stream);
	push @$self, $element;
	my $pos = $stream->tell - $origin;
	my $offset = shift @offset;
	Carp::croak ref($self).": Font shape table seems to be collapsed." if $pos>$offset;
	$stream->get_string($pos-$offset) if $pos<$offset;
    }
}


##########

package SWF::Element::Tag::DefineFont2;

sub _unpack {
    my ($self, $stream)=@_;

    $self->FontID->unpack($stream);
    my $flag = $self->FontFlags($stream->get_UI8);
    $self->LanguageCode($stream->get_UI8);
    $self->FontName->unpack($stream);
    my $glyphcount = $stream->get_UI16;
    $self->GlyphShapeTable->unpack($stream, ($flag & 8));
    $self->CodeTable->unpack($stream, $glyphcount, ($flag & 4));
    if ($flag & 128) {
	$self->FontAscent($stream->get_SI16);
	$self->FontDescent($stream->get_SI16);
	$self->FontLeading($stream->get_SI16);
	$self->FontAdvanceTable->unpack($stream, $glyphcount);
	$self->FontBoundsTable ->unpack($stream, $glyphcount);
	$self->FontKerningTable->unpack($stream, ($flag & 4));
    }
}

sub _pack {
    my ($self, $stream)=@_;
    my $glyphcount = @{$self->CodeTable};

    $self->FontID->pack($stream);
    my $tempstream = $stream->sub_stream;
    my $flag = $self->FontFlags & 0b1010011;

    $self->FontName->pack($tempstream);
    $tempstream->set_UI16($glyphcount);
    $self->GlyphShapeTable->pack($tempstream) and ($flag |= 8);
    $self->CodeTable->pack($tempstream) and ($flag |= 4);
    if (defined $self->FontAscent) {
	$flag |= 128;
	$tempstream->set_SI16($self->FontAscent);
	$tempstream->set_SI16($self->FontDescent);
	$tempstream->set_SI16($self->FontLeading);
	$self->FontAdvanceTable->pack($tempstream);
	$self->FontBoundsTable->pack($tempstream);
	$self->FontKerningTable->pack($tempstream, ($flag & 4));
    }
    $stream->set_UI8($flag);
    $stream->set_UI8($self->LanguageCode);
    $tempstream->flush_stream;
}

{
    my %flags = (Bold => 0, Italic => 1, ANSI => 4, ShiftJIS => 6);
    for my $f (keys %flags) {
      SWF::Element::_create_flag_accessor("FontFlags$f", 'FontFlags', $flags{$f});
    }
}

##########

package SWF::Element::Array::CODETABLE;

sub pack {
    my ($self, $stream)=@_;
    my $widecode = 0;

    for my $element (@$self) {
	if ($element > 255) {
	    $widecode = 1;
	    last;
	}
    }
    if ($widecode) {
	for my $element (@$self) {
	    $stream->set_UI16($element);
	}
    } else {
	for my $element (@$self) {
	    $stream->set_UI8($element);
	}
    }
    $widecode;
}

sub unpack {
    my ($self, $stream, $glyphcount, $widecode)=@_;
    my ($templete);
    if ($widecode) {
	$glyphcount*=2;
	$templete='v*';
    } else {
	$templete='c*';
    }

    @$self=unpack($templete,$stream->get_string($glyphcount));
}

##########

package SWF::Element::Array::FONTADVANCETABLE;

sub pack {
    my ($self, $stream)=@_;

    for my $element (@$self) {
	$stream->set_SI16($element);
    }
}

sub unpack {
    my ($self, $stream, $glyphcount)=@_;

    while (--$glyphcount >=0) {
	push @$self, $stream->get_SI16;
    }
}

##########

package SWF::Element::Array::FONTBOUNDSTABLE;

sub unpack {
    my ($self, $stream, $glyphcount)=@_;

    while (--$glyphcount >=0) {
	my $element = $self->new_element;
	$element->unpack($stream);
	push @$self, $element;
    }
}

##########

package SWF::Element::FONTKERNINGTABLE;

@SWF::Element::FONTKERNINGTABLE::ISA = ('SWF::Element');

sub new {
    my $class = shift;
    my $self = {};

    $class=ref($class)||$class;

    bless $self, $class;
    $self->configure(@_) if @_;
    $self;
}

sub unpack {
    my ($self, $stream, $widecode)=@_;
    my $count=$stream->get_UI16;
    my $getcode=($widecode ? sub {$stream->get_UI16} : sub {$stream->get_UI8});
    %$self=();
    while (--$count>=0) {
	my $code1=&$getcode;
	my $code2=&$getcode;
	$self->{"$code1-$code2"}=$stream->get_SI16;
    }
}

sub pack {
    my ($self, $stream, $widecode)=@_;
    my $setcode=($widecode ? sub {$stream->set_UI16(shift)} : sub {$stream->set_UI8(shift)});
    my ($k, $v);

    $stream->set_UI16(scalar(keys(%$self)));
    while (($k, $v)=each(%$self)) {
	my ($code1, $code2)=split(/-/,$k);
	&$setcode($code1);
	&$setcode($code2);
	$stream->set_SI16($v);
    }
}

sub configure {
    my ($self, @param)=@_;
 
    if (@param==0) {
	return map {$_, $self->{$_}} grep {defined $self->{$_}} keys(%$self);
    } elsif (@param==1) {
	my $k=$param[0];
	return undef unless exists $self->{$k};
	return $self->{$k};
    } else {
	my %param=@param;
	my ($key, $value);
	while (($key, $value) = each %param) {
	    next if $key!~/^\d+-\d+$/;
	    $self->{$key}=$value;
	}
    }
}

sub dumper {
    my ($self, $outputsub, $indent)=@_;
    my ($k, $v);

    $indent ||= 0;
    $outputsub||=\&SWF::Element::_default_output;

    &$outputsub(ref($self)."->new(\n", 0);
    while (($k, $v) = each %$self) {
	&$outputsub("'$k' => $v,\n", $indent + 1);
    }
    &$outputsub(")", $indent);
}

sub defined {
    keys %{shift()} > 0;
}

##########

package SWF::Element::Tag::DefineFontInfo;

sub _unpack {
    my ($self, $stream)=@_;

    my $start = $stream->tell;
    $self->FontID   ->unpack($stream);
    $self->FontName ->unpack($stream);
    my $widecode   = $self->FontFlags($stream->get_UI8) & 1;
    my $glyphcount = $self->Length - ($stream->tell - $start);
    $glyphcount >>= 1 if $widecode;
    $self->CodeTable->unpack($stream, $glyphcount, $widecode);
}

sub _pack {
    my ($self, $stream)=@_;

    $self->FontID   ->pack($stream);
    $self->FontName ->pack($stream);
    my $substream = $stream->sub_stream;
    my $flag = $self->FontFlags & 0b11110;
    $self->CodeTable->pack($substream) and ($flag |= 1);

    $stream->set_UI8($flag);
    $substream->flush_stream;
}

{
    my $bit = 1;
    for my $f (qw/FontFlagsBold FontFlagsItalic FontFlagsANSI FontFlagsShiftJIS/) {
      SWF::Element::_create_flag_accessor($f, 'FontFlags', $bit++);
    }
}

##########

package SWF::Element::Tag::DefineFontInfo2;

sub _unpack {
    my ($self, $stream)=@_;

    my $start = $stream->tell;
    $self->FontID   ->unpack($stream);
    $self->FontName ->unpack($stream);
    my $widecode = $self->FontFlags($stream->get_UI8) & 1;
    $self->LanguageCode($stream->get_UI8);
    my $glyphcount = $self->Length - ($stream->tell - $start);
    $glyphcount >>= 1 if $widecode;
    $self->CodeTable->unpack($stream, $glyphcount, $widecode);
}

sub _pack {
    my ($self, $stream)=@_;

    $self->FontID   ->pack($stream);
    $self->FontName ->pack($stream);
    my $substream = $stream->sub_stream;
    my $flag = $self->FontFlags;
    $self->CodeTable->pack($substream) and ($flag |= 1);

    $stream->set_UI8($flag);
    $stream->set_UI8($self->LanguageCode);
    $substream->flush_stream;
}


##########

package SWF::Element::Array::TEXTRECORDARRAY1;

sub pack {
    my ($self, $stream)=@_;
    my ($nglyphmax, $nglyphbits, $nadvancemax, $nadvancebits, $g, $a) = (0) x 6;

    for my $element (@$self) {
	next unless ($element->isa('SWF::Element::TEXTRECORD::TYPE0'));
	for my $entry (@{$element->GlyphEntries}) {
	    $g=$entry->GlyphIndex;
	    $a=$entry->GlyphAdvance;
	    $a=~$a if $a<0;
	    $nglyphmax=$g if $g>$nglyphmax;
	    $nadvancemax=$a if $a>$nadvancemax;
	}
    }
    $nglyphbits++ while ($nglyphmax>=(1<<$nglyphbits));
    $nadvancebits++ while ($nadvancemax>=(1<<$nadvancebits));
    $nadvancebits++; # for sign bit.

    $stream->set_UI8($nglyphbits);
    $stream->set_UI8($nadvancebits);

    for my $element (@$self) {
	$element->pack($stream, $nglyphbits, $nadvancebits);
    }
    $self->last($stream);
}

sub unpack {
    my ($self, $stream)=@_;
    my ($nglyphbits, $nadvancebits);
    my ($flags);

    $nglyphbits=$stream->get_UI8;
    $nadvancebits=$stream->get_UI8;
    {
	my $element = $self->new_element;
	$element->unpack($stream, $nglyphbits, $nadvancebits);
	last if $self->is_last($element);
	push @$self, $element;
	redo;
    }
}

##########

package SWF::Element::TEXTRECORD1;

sub unpack {
    my $self = shift;
    my $stream = shift;
    my $flags = $stream->get_UI8;

    if ($flags) {
# If upper nibble of $flags is 8, $self is TEXTRECORDn::TYPE1.
# (It is not enough by checking MSB...(?))
	bless $self, ($flags>>4 == 8) ? ref($self).'::TYPE1' : 'SWF::Element::TEXTRECORD::TYPE0';
	$self->unpack($stream, $flags, @_);
    } else {
	bless $self, 'SWF::Element::TEXTRECORD::End';
    }
}

sub pack {
    Carp::croak "Not enough data to pack ".ref($_[0]);
}

sub AUTOLOAD { # auto re-bless with proper sub class by specified accessor.
    my $self = shift;
    my ($name, $class);

    return if $SWF::Element::TEXTRECORD1::AUTOLOAD =~/::DESTROY$/;

    Carp::croak "No such method: $SWF::Element::TEXTRECORD1::AUTOLOAD" unless $SWF::Element::TEXTRECORD1::AUTOLOAD=~/::([A-Z]\w+)$/;
    $name = $1;
    $class = ref($self);
    for my $subclass ('SWF::Element::TEXTRECORD::TYPE0', "${class}::TYPE1") {
	$class=$subclass, last if $subclass->element_type($name);
    }
    Carp::croak "Element '$name' is NOT in $class " if $class eq ref($self);

    bless $self, $class;
    $self->$name(@_);
}


##########
package SWF::Element::Array::GLYPHENTRYARRAY;

sub unpack {
    my $self   = shift;
    my $stream = shift;
    my $count  = shift;

    while (--$count>=0) {
	my $element = $self->new_element;
	$element->unpack($stream, @_);
	push @$self, $element;
    }
}

##########

package SWF::Element::GLYPHENTRY;

sub unpack {
    my ($self, $stream, $nglyphbits, $nadvancebits)=@_;

    $self->GlyphIndex($stream->get_bits($nglyphbits));
    $self->GlyphAdvance($stream->get_sbits($nadvancebits));
}

sub pack {
    my ($self, $stream, $nglyphbits, $nadvancebits)=@_;

    $stream->set_bits($self->GlyphIndex, $nglyphbits);
    $stream->set_sbits($self->GlyphAdvance, $nadvancebits);
}

##########

package SWF::Element::TEXTRECORD1::TYPE1;

sub unpack {
    my ($self, $stream, $flags)=@_;

    $self->FontID   ->unpack($stream)    if ($flags & 8);
    $self->TextColor->unpack($stream)    if ($flags & 4);
    $self->XOffset($stream->get_SI16)    if ($flags & 1);
    $self->YOffset($stream->get_SI16)    if ($flags & 2);
    $self->TextHeight($stream->get_UI16) if ($flags & 8);
}

sub pack {
    my ($self, $stream)=@_;
    my ($flags)=0x80;

    $flags|=8 if $self->FontID->defined or defined $self->TextHeight;
    $flags|=4 if $self->TextColor->defined;
    $flags|=1 if defined $self->XOffset;
    $flags|=2 if defined $self->YOffset;
    $stream->set_UI8($flags);

    $self->FontID->pack($stream)  if ($flags & 8);
    $self->TextColor->pack($stream) if ($flags & 4);
    $stream->set_SI16($self->XOffset) if ($flags & 1);
    $stream->set_SI16($self->YOffset) if ($flags & 2);
    $stream->set_UI16($self->TextHeight) if ($flags & 8);
}


##########

package SWF::Element::Tag::DefineEditText;

sub _unpack {
    my ($self, $stream)=@_;

    $self->CharacterID->unpack($stream);
    $self->Bounds->unpack($stream);
    my $flag = $self->Flags($stream->get_UI16);

    if ($flag & 1) {
	$self->FontID->unpack($stream);
	$self->FontHeight($stream->get_UI16);
    }
    $self->TextColor->unpack($stream) if $flag & 4;
    $self->MaxLength($stream->get_UI16) if $flag & 2;

    if ($flag & (1<<13)) {
	$self->Align($stream->get_UI8);
	for my $element (qw/LeftMargin RightMargin Indent Leading/) {
	    $self->$element($stream->get_UI16);
	}
    }
    $self->VariableName->unpack($stream);
    $self->InitialText->unpack($stream) if $flag & 128;
}

sub _pack {
    my ($self, $stream)=@_;

    my $flag = $self->Flags & 0b101101101111000;
    $flag |= ($self->FontID->defined or defined $self->FontHeight) |
	     defined ($self->MaxLength)  << 1 |
             ($self->TextColor->defined) << 2 |
	     ($self->InitialText->defined) << 7 | 
	     (defined $self->Align
              or defined $self->LeftMargin
              or defined $self->RightMargin
              or defined $self->Indent
              or defined $self->Leading) << 13;

    $self->CharacterID->pack($stream);
    $self->Bounds->pack($stream);
    $stream->set_UI16($flag);

    if ($flag & 1) {
	$self->FontID->pack($stream);
	$stream->set_UI16($self->FontHeight);
    }
    $self->TextColor->pack($stream) if $flag & 4;
    $stream->set_UI16($self->MaxLength) if $flag & 2;
    if ($flag & (1<<13)) {
	$stream->set_UI8($self->Align);
	for my $element (qw/LeftMargin RightMargin Indent Leading/) {
	    $stream->set_UI16($self->$element);
	}
    }
    $self->VariableName->pack($stream);
    $self->InitialText->pack($stream) if $flag & 128;
}

{
    my %flags = (ReadOnly    =>  3,
		 Password    =>  4,
		 Multiline   =>  5, 
		 WordWrap    =>  6, 
		 UseOutlines =>  8,
		 HTML        =>  9,
		 Border      => 11,
		 NoSelect    => 12,
		 AutoSize    => 14);
    for my $f (keys %flags) {
      SWF::Element::_create_flag_accessor($f, 'Flags', $flags{$f});
    }
}

####  Sounds  ####
##########

package SWF::Element::SOUNDINFO;

sub unpack {
    my ($self, $stream)=@_;
    my $flags=$stream->get_UI8;

    $self->SyncFlags($flags>>4);

    $self->InPoint($stream->get_UI32) if ($flags & 1);
    $self->OutPoint($stream->get_UI32) if ($flags & 2);
    $self->LoopCount($stream->get_UI16) if ($flags & 4);
    $self->EnvelopeRecords->unpack($stream) if ($flags & 8);
}

sub pack {
    my ($self, $stream)=@_;
    my $flags=$self->SyncFlags << 4 |
	      $self->EnvelopeRecords->defined << 3 |
	      defined($self->LoopCount) << 2 |
	      defined($self->OutPoint)  << 1 |
	      defined($self->InPoint);
    $stream->set_UI8($flags);

    $stream->set_UI32($self->InPoint) if ($flags & 1);
    $stream->set_UI32($self->OutPoint) if ($flags & 2);
    $stream->set_UI16($self->LoopCount) if ($flags & 4);
    $self->EnvelopeRecords->pack($stream) if ($flags & 8);
}

 SWF::Element::_create_flag_accessor('SyncNoMultiple', 'SyncFlags', 0);
 SWF::Element::_create_flag_accessor('SyncStop',       'SyncFlags', 1);


##########

package SWF::Element::Tag::DefineSound;

sub _unpack {
    my ($self, $stream)=@_;

    $self->SoundID->unpack($stream);
    $self->Flags($stream->get_UI8);
    $self->SoundSampleCount($stream->get_UI32);
    $self->SoundData->unpack($stream, $self->Length - 7);
}

{
    my %flags = (Format => [4,4],
		 Rate   => [2,2],
		 Size   => [1,1],
		 Type   => [0,1]);
    for my $f (keys(%flags)) {
      SWF::Element::_create_flag_accessor("Sound$f", 'Flags', @{$flags{$f}});
    }
}

##########

package SWF::Element::Tag::SoundStreamBlock;

sub _unpack {
    my ($self, $stream)=@_;

    $self->StreamSoundData->unpack($stream, $self->Length);
}

##########

package SWF::Element::Tag::SoundStreamHead;

{
    my %flags = (StreamSoundCompression => [12, 4],
		 StreamSoundRate        => [10, 2],
		 StreamSoundSize        => [ 9, 1],
		 StreamSoundType        => [ 8, 1],
		 PlaybackSoundRate      => [ 2, 2],
		 PlaybackSoundSize      => [ 1, 1],
		 PlaybackSoundType      => [ 0, 1]);
    for my $f (keys(%flags)) {
      SWF::Element::_create_flag_accessor($f, 'Flags', @{$flags{$f}});
    }
}

##########

package SWF::Element::Tag::SoundStreamHead2;

sub _unpack {
    my ($self, $stream)=@_;

    $self->Flags($stream->get_UI16);
    $self->StreamSoundSampleCount($stream->get_UI16);
    $self->LatencySeek($stream->get_SI16) if $self->StreamSoundCompression == 2;
}

sub _pack {
    my ($self, $stream)=@_;

    $stream->set_UI16($self->Flags);
    $stream->set_UI16($self->StreamSoundSampleCount);
    $stream->set_SI16($self->LatencySeek) if $self->StreamSoundCompression == 2;
}

####  Sprites  ####
##########

package SWF::Element::Tag::DefineSprite;

sub _pack {
    my ($self, $stream)=@_;

    $self->SpriteID->pack($stream);
    my $tempstream = $stream->sub_stream;
    for my $tag (@{$self->ControlTags}) {
	my $tagname = $tag->tag_name;
	if (index('ShowFrame PlaceObject2 RemoveObject2 DoAction StartSound FrameLabel SoundStreamHead2 SoundStreamBlock End', $tagname) < 0) {
	  Carp::carp "$tagname is invalid tag in DefineSprite ";
	    next;
	}
	$tag->pack($tempstream);
    }
    $stream->set_UI16($tempstream->{_framecount});
    $tempstream->flush_stream;
}

####  Display List  ####
##########

package SWF::Element::Tag::PlaceObject;

sub _unpack {
    my ($self, $stream)=@_;

    my $start = $stream->tell;

    $self->CharacterID->unpack($stream);
    $self->Depth->unpack($stream);
    $self->Matrix->unpack($stream);
    if ($stream->tell < $start + $self->Length) {
	$self->ColorTransform->unpack($stream);
    }
}

sub _pack {
    my ($self, $stream)=@_;

    $self->CharacterID->pack($stream);
    $self->Depth->pack($stream);
    $self->Matrix->pack($stream);
    $self->ColorTransform->pack($stream) if $self->ColorTransform->defined;
}

##########

package SWF::Element::Tag::PlaceObject2;

sub _unpack {
    my ($self, $stream)=@_;

    my $flag = $self->Flags($stream->get_UI8);
    $self->Depth         ->unpack($stream);
    $self->CharacterID   ->unpack($stream) if $flag & 2;
    $self->Matrix        ->unpack($stream) if $flag & 4;
    $self->ColorTransform->unpack($stream) if $flag & 8;
    $self->Ratio($stream->get_UI16)        if $flag & 16;
    $self->Name          ->unpack($stream) if $flag & 32;
    $self->ClipDepth     ->unpack($stream) if $flag & 64;

    if ($flag & 128) {
	$stream->get_UI16; # skip reserved.
	if ($stream->Version >= 6) {  # skip clipaction flag
	    $stream->get_UI32;
	} else {
	    $stream->get_UI16;
	}
	$self->ClipActions->unpack($stream);
    }
}

sub _pack {
    my ($self, $stream)=@_;
    my $flag = ($self->PlaceFlagMove |
	       ((my $cid = $self->CharacterID)->defined) << 1 |
	       ((my $matrix = $self->Matrix)  ->defined) << 2 |
	       ((my $ctfm = $self->ColorTransform)->defined) << 3 |
	       (defined (my $ratio = $self->Ratio) << 4) |
	       ((my $name = $self->Name)->defined) << 5 |
	       ((my $cdepth = $self->ClipDepth)->defined) << 6 |
	       ((my $caction = $self->ClipActions)->defined) << 7) ;
    $stream->set_UI8($flag);
    $self->Depth->pack($stream);
    $cid   ->pack($stream)     if $flag & 2;
    $matrix->pack($stream)     if $flag & 4;
    $ctfm  ->pack($stream)     if $flag & 8;
    $stream->set_UI16($ratio)  if $flag & 16;
    $name  ->pack($stream)     if $flag & 32;
    $cdepth->pack($stream)     if $flag & 64;
    if ($flag & 128) {
	$stream->set_UI16(0);  # Reserved.
	my $f = 0;
	for my $e (@{$caction}) {
	    $f |= $e->EventFlags;
	}
	if ($stream->Version >= 6) {
	    $stream->set_UI32($f);
	} else {
	    $stream->set_UI16($f);
	}
	$caction->pack($stream);
    }
}

 SWF::Element::_create_flag_accessor('PlaceFlagMove', 'Flags', 0);

##########

package SWF::Element::Tag::ShowFrame;

sub pack {
    my ($self, $stream) = @_;

    $self->SUPER::pack($stream);
    $stream->{_framecount}++;
}

####  Controls  ####
##########

package SWF::Element::Tag::Protect;

sub _pack {
    my ($self, $stream) = @_;

    $self->Password->pack($stream) if $self->Password->defined;
}

##########

package SWF::Element::Tag::FrameLabel;

sub _unpack {
    my ($self, $stream) = @_;

    $self->Name->unpack($stream);
    if ($self->Length > length($self->Name->value)+1) {
	$self->NamedAnchorFlag($stream->get_UI8);
    }
}

sub _pack {
    my ($self, $stream) = @_;

    $self->Name->pack($stream);
    $stream->set_UI8($self->NamedAnchorFlag) if $self->NamedAnchorFlag;
}

####  Actions  ####
##########

package SWF::Element::ACTIONRECORD;


our %actiontagtonum=(
    ActionEnd                      => 0x00,
    ActionNextFrame                => 0x04,
    ActionPrevFrame                => 0x05,
    ActionPlay                     => 0x06,
    ActionStop                     => 0x07,
    ActionToggleQuality            => 0x08,
    ActionStopSounds               => 0x09,
    ActionAdd                      => 0x0A,
    ActionSubtract                 => 0x0B,
    ActionMultiply                 => 0x0C,
    ActionDivide                   => 0x0D,
    ActionEquals                   => 0x0E,
    ActionLess                     => 0x0F,
    ActionAnd                      => 0x10,
    ActionOr                       => 0x11,
    ActionNot                      => 0x12,
    ActionStringEquals             => 0x13,
    ActionStringLength             => 0x14,
    ActionStringExtract            => 0x15,
    ActionPop                      => 0x17,
    ActionToInteger                => 0x18,
    ActionGetVariable              => 0x1C,
    ActionSetVariable              => 0x1D,
    ActionSetTarget2               => 0x20,
    ActionStringAdd                => 0x21,
    ActionGetProperty              => 0x22,
    ActionSetProperty              => 0x23,
    ActionCloneSprite              => 0x24,
    ActionRemoveSprite             => 0x25,
    ActionTrace                    => 0x26,
    ActionStartDrag                => 0x27,
    ActionEndDrag                  => 0x28,
    ActionStringLess               => 0x29,
    ActionRandomNumber             => 0x30,
    ActionMBStringLength           => 0x31,
    ActionCharToAscii              => 0x32,
    ActionAsciiToChar              => 0x33,
    ActionGetTime                  => 0x34,
    ActionMBStringExtract          => 0x35,
    ActionMBCharToAscii            => 0x36,
    ActionMBAsciiToChar            => 0x37,
    ActionDelete                   => 0x3a,
    ActionDelete2                  => 0x3b,
    ActionDefineLocal              => 0x3c,
    ActionCallFunction             => 0x3d,
    ActionReturn                   => 0x3e,
    ActionModulo                   => 0x3f,
    ActionNewObject                => 0x40,
    ActionDefineLocal2             => 0x41,
    ActionInitArray                => 0x42,
    ActionInitObject               => 0x43,
    ActionTypeOf                   => 0x44,
    ActionTargetPath               => 0x45,
    ActionEnumerate                => 0x46,
    ActionAdd2                     => 0x47,
    ActionLess2                    => 0x48,
    ActionEquals2                  => 0x49,
    ActionToNumber                 => 0x4a,
    ActionToString                 => 0x4b,
    ActionPushDuplicate            => 0x4C,
    ActionStackSwap                => 0x4d,
    ActionGetMember                => 0x4e,
    ActionSetMember                => 0x4f,
    ActionIncrement                => 0x50,
    ActionDecrement                => 0x51,
    ActionCallMethod               => 0x52,
    ActionNewMethod                => 0x53,
    ActionInstanceOf               => 0x54,
    ActionEnumerate2               => 0x55,
    ActionBitAnd                   => 0x60,
    ActionBitOr                    => 0x61,
    ActionBitXor                   => 0x62,
    ActionBitLShift                => 0x63,
    ActionBitRShift                => 0x64,
    ActionBitURShift               => 0x65,
    ActionStrictEquals             => 0x66,
    ActionGreater                  => 0x67,
    ActionStringGreater            => 0x68,
    ActionCall                     => 0x9e,

);

our %actionnumtotag= reverse %actiontagtonum;

sub new {
    my ($class, @headerdata)=@_;
    my %headerdata = ref($headerdata[0]) eq 'ARRAY' ? @{$headerdata[0]} : @headerdata;
    my $self = [];
    my $tag = $headerdata{Tag};

    if (defined($tag) and $tag !~/^\d+$/) {
	my $tag1 = $actiontagtonum{$tag};
	Carp::croak "ACTIONRECORD '$tag1' is not defined." unless defined $tag1;
	$tag = $tag1;
    }
    delete $headerdata{Tag};
    $class=ref($class)||$class;
    bless $self, $class;
    if (defined $tag) {
	$self->Tag($tag);
	bless $self, _action_class($tag);
    }
    $self->_init;
    $self->configure(%headerdata) if %headerdata;
    $self;
}

sub _init {}

sub configure {
    my ($self, @param)=@_;
    @param = @{$param[0]} if ref($param[0]) eq 'ARRAY';
    my %param=@param;

    if (defined $param{Tag}) {
	my $tag = $param{Tag};
	if ($tag !~/^\d+$/) {
	    $tag = "Action$tag" if $tag !~ /^Action/;
	    my $tag1 = $actiontagtonum{$tag};
	    Carp::croak "ACTIONRECORD '$tag1' is not defined." unless defined $tag1;
	    $tag = $tag1;
	}
	delete $param{Tag};
	$self->Tag($tag);
	bless $self, _action_class($tag);
	$self->_init;
    }
    $self->SUPER::configure(%param);
}
 
sub _action_class {
    my $num = shift;
    my $name = $actionnumtotag{$num};
    if (!$name and $num >= 0x80) {
	$name = 'ActionUnknown';
    }
    if ($num >=0x80 and $num != 0x9e) {
	return "SWF::Element::ACTIONRECORD::$name";
    } else {
	return "SWF::Element::ACTIONRECORD";
    }
}

sub unpack {
    my $self = shift;
    my $stream = shift;

    $self->Tag->unpack($stream);
    if ($self->Tag >= 0x80) {
	bless $self, _action_class($self->Tag);
	$self->_init;
	my $len = $stream->get_UI16;
	my $start = $stream->tell;
	$self->_unpack($stream, $len);
#	my $read = $stream->tell - $start;
#	if ($read < $len) {
#	    $stream->get_string($len-$read);  # Skip the rest of tag data.
#	} elsif ($read > $len) {
#	    Carp::carp ref($self)." unpacked $read bytes in excess of the described ACTIONRECORD length, $len bytes.  The SWF may be collapsed or the module bug??";
#	}  # Some SWFs have an invalid action tag length (?)
    }
}

sub pack {
    my ($self, $stream) = @_;

    $self->Tag->pack($stream);
    if ($self->Tag >= 0x80) {
	my $substream = $stream->sub_stream;
	$self->_pack($substream);
	$stream->set_UI16($substream->tell);
	$substream->flush_stream;
    }
}

sub _pack {
    my $self = shift;
    my $stream = shift;
    my @names = $self->element_names;
    shift @names;   # remove 'Tag'
    shift @names;   # remove 'LocalLabel'

    for my $key (@names) {
	if ($self->element_type($key) !~ /^\$(.*)$/) {
	    $self->$key->pack($stream, @_);
	} else {
	    my $setsub = "set_$1";
	    $stream->$setsub($self->$key);
	}
    }
}

sub _unpack {
    my $self = shift;
    my $stream = shift;
    my @names = $self->element_names;
    shift @names;   # remove 'Tag'
    shift @names;   # remove 'LocalLabel'
    for my $key (@names) {
	if ($self->element_type($key) !~ /^\$(.*)$/) {
	    $self->$key->unpack($stream, @_);
	} else {
	    my $getsub = "get_$1";
	    $self->$key($stream->$getsub);
	}
    }
}

sub tag_name {
    return $actionnumtotag{shift->Tag};
}

sub _create_action_tag {
    no strict 'refs';

    my $tagname = shift;
    my $tagno = shift;
    my $tagisa = shift;
    $tagisa = defined($tagisa) ? "ACTIONRECORD::_$tagisa" :  'ACTIONRECORD';
    $tagname = "Action$tagname";
    SWF::Element::_create_class("ACTIONRECORD::$tagname", $tagisa, Tag => 'ACTIONTagNumber', LocalLabel => '$', @_);

    $actionnumtotag{$tagno} = $tagname;
    $actiontagtonum{$tagname} = $tagno;
}

_create_action_tag('Unknown',  'Unknown', undef, Data       => 'BinData');  
_create_action_tag('GotoFrame',     0x81, undef, Frame      => '$UI16');
_create_action_tag('GetURL',        0x83, undef,
		   UrlString    => 'STRING',
		   TargetString => 'STRING' );
_create_action_tag('WaitForFrame',  0x8A, 'HasSkipCount',
		   Frame     => '$UI16',
		   SkipCount => '$UI8' );
_create_action_tag('SetTarget',     0x8B, undef, TargetName  => 'STRING' );
_create_action_tag('GotoLabel',     0x8C, undef, Label       => 'STRING' );
_create_action_tag('WaitForFrame2', 0x8D, 'HasSkipCount',
                   SkipCount   => '$UI8' );
_create_action_tag('Push',          0x96, undef, DataList    => 'Array::ACTIONDATAARRAY' );
_create_action_tag('Jump',          0x99, 'HasOffset',
                   BranchOffset=> '$SI16');
_create_action_tag('GetURL2',       0x9a, undef, Method      => '$UI8');
_create_action_tag('If',            0x9d, 'HasOffset',
                   BranchOffset=> '$SI16');
_create_action_tag('GotoFrame2',    0x9F, undef, PlayFlag    => '$UI8');
_create_action_tag('ConstantPool',  0x88, undef,
		   ConstantPool => 'Array::STRINGARRAY');
_create_action_tag('DefineFunction',   0x9b, 'HasCodeSize',
		   FunctionName => 'STRING',
		   Params       => 'Array::STRINGARRAY',
                   CodeSize     => '$UI16');
_create_action_tag('StoreRegister', 0x87, undef, Register   => '$UI8');
_create_action_tag('With',          0x94, 'HasCodeSize',
                   CodeSize => '$UI16');

##########

package SWF::Element::ACTIONRECORD::_HasSkipCount;

@SWF::Element::ACTIONRECORD::_HasSkipCount::ISA=('SWF::Element::ACTIONRECORD');

##########

package SWF::Element::ACTIONRECORD::_HasOffset;

@SWF::Element::ACTIONRECORD::_HasOffset::ISA=('SWF::Element::ACTIONRECORD');

##########

package SWF::Element::ACTIONRECORD::_HasCodeSize;

@SWF::Element::ACTIONRECORD::_HasCodeSize::ISA=('SWF::Element::ACTIONRECORD::_HasOffset');

##########

package SWF::Element::ACTIONTagNumber;

sub dumper {
    my ($self, $outputsub)=@_;

    $outputsub||=\&SWF::Element::_default_output;
    my $tag = $SWF::Element::ACTIONRECORD::actionnumtotag{$self->value};
    &$outputsub($tag ? "'$tag'" : $self->value, 0);
}

sub pack {
    my ($self, $stream) = @_;

    $stream->set_UI8($self->value);
}

sub unpack {
    my ($self, $stream) = @_;

    $self->configure($stream->get_UI8);
}

##########

package SWF::Element::Array::ACTIONDATAARRAY;

sub unpack {
    my ($self, $stream, $len) = @_;
    my $start = $stream->tell;

    while ($stream->tell - $start < $len) {
	my $element = $self->new_element;
	$element->unpack($stream);
	push @$self, $element;
    }
}

##########

package SWF::Element::ACTIONDATA;

sub configure {
    my ($self, $type, $data) = @_;

    if (defined $data) {
	if ($type eq 'Type') { 
	    $type = $data;
	    undef $data;
	}
	my $class = "SWF::Element::ACTIONDATA::$type";
	Carp::croak "No Data type '$type' in ACTIONDATA " unless $class->can('new');
	bless $self, $class;
    } else {
	$data = $type;
    }

    $$self = $data if defined $data;
    $self;
}

sub dumper {
    my ($self, $outputsub, $indent)=@_;

    $outputsub||=\&SWF::Element::_default_output;

    my $val = $self->value;

    $val =~ s/([\\$@\"])/\\$1/gs;
    $val =~ s/([\x00-\x1F\x80-\xFF])/sprintf('\\x%.2X', ord($1))/ges;
    $val = "\"$val\"" unless $val =~ /^\d+(?:\.\d+)?$/;

    &$outputsub(ref($self)."->new($val)", 0);
}

my @actiondata_types
     = qw/String Property NULL NULL Register Boolean Double Integer Lookup Lookup/;

sub pack {
    my ($self, $stream) = @_;

    Carp::carp "No specified type in ACTIONDATA, so pack as String. ";
    $self->configure(Type => 'String');
    $self->pack($stream);
}

sub unpack {
    my ($self, $stream) = @_;
    my $type = $stream->get_UI8;

    Carp::croak "Undefined type '$type' in ACTIONDATA " 
	if $type > $#actiondata_types;

    bless $self, "SWF::Element::ACTIONDATA::$actiondata_types[$type]";
    $self->_unpack($stream, $type);
}

sub _unpack {};

#########

package SWF::Element::ACTIONDATA::String;

sub pack {
    my ($self, $stream) = @_;

    $stream->set_UI8(0);
    $stream->set_string($self->value."\0");
}

sub _unpack {
  SWF::Element::STRING::unpack(@_);
}

#########

package SWF::Element::ACTIONDATA::Property;

my @_actiondata_properties
    = qw/X Y Xscale Yscale Unknown Unknown Alpha Visibility Unknown Unknown
         Rotation Unknown Name Unknown Unknown Unknown Highquality
         ShowFocusRectangle SoundBufferTime/;

sub pack {
    my ($self, $stream) = @_;
    my $data = $self->value;

    $stream->set_UI8(1);
    if ($data !~ /^\d+$/) {
	my $count = 0;
	for my $name (@_actiondata_properties) {
	    $data = $count, last if $name eq $data;
	}
    } 
    $stream->set_UI32(unpack('L', CORE::pack('f', $data)));  # IEEE float support needed.

}

sub _unpack {
    my ($self, $stream) = @_;

    $self->configure(unpack('f', CORE::pack('L', $stream->get_UI32)));  # IEEE float support needed.
}


#########

package SWF::Element::ACTIONDATA::NULL;

sub pack {
    $_[1]->set_UI8(2);
}

#########

package SWF::Element::ACTIONDATA::Register;

sub pack {
    my ($self, $stream) = @_;

    $stream->set_UI8(4);
    $stream->set_UI8($self->value);
}

sub _unpack {
    my ($self, $stream) = @_;

    $self->configure($stream->get_UI8);
}

#########

package SWF::Element::ACTIONDATA::Boolean;

sub pack {
    my ($self, $stream) = @_;

    $stream->set_UI8(5);
    $stream->set_UI8($self->value);
}

sub _unpack {
    my ($self, $stream) = @_;

    $self->configure($stream->get_UI8);
}

#########

package SWF::Element::ACTIONDATA::Lookup;

sub pack {
    my ($self, $stream) = @_;

    if ((my $v = $self->value) >= 256) {
	$stream->set_UI8(9);
	$stream->set_UI16($v);
    } else {
	$stream->set_UI8(8);
	$stream->set_UI8($v);
    }
}

sub _unpack {
    my ($self, $stream, $type) = @_;

    $self->configure($type == 8 ? $stream->get_UI8 : $stream->get_UI16);
}

#########

package SWF::Element::ACTIONDATA::Integer;

sub pack {
    my ($self, $stream) = @_;

    $stream->set_UI8(7);
    $stream->set_SI32($self->value); # really signed?
}

sub _unpack {
    my ($self, $stream) = @_;

    $self->configure($stream->get_SI32); # really signed?
}

#########

package SWF::Element::ACTIONDATA::Double;

# INTEL case.

sub pack {
    my ($self, $stream) = @_;

    $stream->set_UI8(6);
    my $data = pack('d', $self->value);
    $stream->set_string(substr($data, -4));
    $stream->set_string(substr($data,0,4));
}

sub _unpack {
    my ($self, $stream) = @_;
    my $data1 = $stream->get_string(4);
    my $data2 = $stream->get_string(4);

    $self->configure(unpack('d',$data2.$data1));
}

##########

package SWF::Element::CLIPACTIONRECORD;

sub unpack {
    my ($self, $stream) = @_;

    my $flag = 0;
    $flag = $self->EventFlags6($stream->get_UI16) if $stream->Version >= 6;
    $flag |= $self->EventFlags ($stream->get_UI16);
    return if $flag == 0;
    my $size = $stream->get_UI32;
    my $start = $stream->tell;
    $self->KeyCode($stream->get_UI8)if $self->ClipEventKeyPress;
    $self->Actions->unpack($stream);
    my $remain = $stream->tell - $start - $size;
    $stream->get_string($remain) if $remain > 0; 
}

sub pack {
    my ($self, $stream) = @_;

    if ($stream->Version >= 6) {
	$stream->set_UI16($self->EventFlags6);
    }
    $stream->set_UI16($self->EventFlags);
    
    my $tempstream = $stream->sub_stream;
    $tempstream->set_UI8($self->KeyCode) if $self->ClipEventKeyPress;
    $self->Actions->pack($tempstream);
    $stream->set_UI32($tempstream->tell);
    $tempstream->flush_stream;
}

{
    my $bit = 0;
    for my $f (qw/Load EnterFrame Unload MouseMove MouseDown MouseUp KeyDown KeyUp Data Initialize Press Release ReleaseOutside RollOver RollOut DragOver/) {
      SWF::Element::_create_flag_accessor("ClipEvent$f", 'EventFlags', $bit++);
    }
  SWF::Element::_create_flag_accessor("ClipEventDragOut",  'EventFlags6', 0);
  SWF::Element::_create_flag_accessor("ClipEventKeyPress", 'EventFlags6', 1);
}

##########

package SWF::Element::Array::ACTIONRECORDARRAY;

sub pack {
    my $self = shift;
    my $stream = $_[0];

    # Add ActionEnd if there is not.
    push @$self, SWF::Element::ACTIONRECORD->new(Tag=>'ActionEnd') if $self->[-1]->Tag != 0;

    $self->_write_actionstream($stream, $self->_label_resolve(@_));
}

sub _label_resolve {
    my $self = shift;
    my $stream = shift;
    my $actionstream = SWF::BinStream::Write->new($stream->Version);
    my %labels;
    my $count = 0;

    for my $element (@$self) {
	$labels{$element->LocalLabel} = [$count, $actionstream->tell] if ($element->LocalLabel);
	$count++;
	$element->pack($actionstream, @_);
    }

    my %marks = $actionstream->mark;
    my @replace;
    for my $label (keys %marks) {
	(my $label1 = $label)=~s/\#.*$//;   # inner local label
      Carp::croak "Can't find LocalLabel '$label1' " unless defined $labels{$label1};
	my ($dstcount, $dsttell) = @{$labels{$label1}};
	while(my ($tell, $obj) = splice(@{$marks{$label}}, 0, 2)) {
	    if ($obj->[0] eq 'Offset') {
		my $offset = $dsttell-$tell-2;
	      Carp::croak "Can't set negative offset for ".ref($obj->[1]) if $offset < 0 and $obj->[1]->isa('SWF::Element::ACTIONRECORD::_HasCodeSize');
		my $data = CORE::pack('v', $offset);
		if ($tell % 1024 == 1023) {
		    my @data = split //, $data;
		    push @{$replace[$tell>>10]}, [1023, 1, $data[0]];
		    push @{$replace[($tell>>10)+1]}, [0, 1, $data[1]];
		} else {
		    push @{$replace[$tell>>10]}, [$tell % 1024, 2, $data];
		}
	    } elsif ($obj->[0] eq 'SkipCount') {
		my $count = 0;
		for my $element (@$self) {
		    last if $element eq $obj->[1];
		    $count++;
		}
	      Carp::croak "SkipCount of ".ref($obj->[1])." cannot refer backward " if $dstcount < $count;
		push @{$replace[$tell>>10]}, [$tell % 1024, 1, CORE::pack('C', $dstcount-$count)];
	    }
	}
    }
    return ($actionstream, \@replace);
}

sub _write_actionstream {
    my ($self, $stream, $actionstream, $replace) = @_;

    while($actionstream->Length > 0) {
	my $buf = $actionstream->flush_stream(1024);
	my $replace1 = shift @$replace;
	while (my $replace2 = shift @$replace1) {
	    my ($pos, $len, $r) = @$replace2;
	    substr($buf, $pos, $len) = $r;
	}
	$stream->set_string($buf);
    }
}

sub unpack {
    my ($self, $stream, $len) = @_;
    my @byteoffset;
    my $start = $stream->tell;

    while(!defined $len or $stream->tell - $start < $len) {
	push @byteoffset, $stream->tell-$start;
	my $element = $self->new_element;
	$element->unpack($stream);
	push @$self, $element;
	last if !defined $len and $element->Tag == 0;
    }
    my $label = 'A';
    for (my $i = 0; $i < @byteoffset; $i++) {
	my $action = $self->[$i];
	if ($action->isa('SWF::Element::ACTIONRECORD::_HasSkipCount')) {
	    my $skip = $action->SkipCount;
	    my $dst = $self->[$i+$skip];
	    if (my $l = $dst->LocalLabel) {
		$action->SkipCount("$l#$skip");
	    } else {
		$action->SkipCount("$label#$skip");
		$dst->LocalLabel($label);
		$label++;
	    }
	} elsif($action->isa('SWF::Element::ACTIONRECORD::_HasOffset')) {
	    my $offset = $action->_Offset;
	    my $set = $byteoffset[$i+1];
	    my $dst = $set;
	    my $j = $i+1;
	    if ($offset < 0) {
		while ($j>=0 and ($dst-$set) > $offset) {
		    $j--;
		    $dst = $byteoffset[$j];
		}
	    } else {
		while ($j<@byteoffset and ($dst-$set) < $offset) {
		    $j++;
		    $dst = $byteoffset[$j];
		}
	    }
	    if ($dst-$set == $offset) {
		if (my $l = $self->[$j]->LocalLabel) {
		    $action->_Offset("$l#$offset");
		} else {
		    $action->_Offset("$label#$offset");
		    $self->[$j]->LocalLabel($label);
		    $label++;
		}
	    }
	}
    }
}

##########

package SWF::Element::ACTIONRECORD::ActionWaitForFrame;

sub _pack {
    my ($self, $stream) = @_;

    $stream->set_UI16($self->Frame);
    my $skip = $self->SkipCount;


    if ($skip =~ /^[^\d]/) {
	$stream->mark($skip, ['SkipCount', $self]);
	$stream->set_UI8(0);
    } else {
	$stream->set_UI8($skip);
    }
}

##########

package SWF::Element::ACTIONRECORD::ActionWaitForFrame2;

sub _pack {
    my ($self, $stream) = @_;
    my $skip = $self->SkipCount;

    if ($skip =~ /^[^\d]/) {
	$stream->mark($skip, ['SkipCount', $self]);
	$stream->set_UI8(0);
    } else {
	$stream->set_UI8($skip);
    }
}

##########

package SWF::Element::ACTIONRECORD::ActionJump;

sub _pack {
    my ($self, $stream) = @_;
    my $offset = $self->BranchOffset;

    if ($offset =~ /^[^\d\-]/) {
	$stream->mark($offset, ['Offset', $self]);
	$stream->set_SI16(0);
    } else {
	$stream->set_SI16($offset);
    }
}

*SWF::Element::ACTIONRECORD::ActionJump::_Offset = \&BranchOffset;
*SWF::Element::ACTIONRECORD::ActionIf::_Offset = \&BranchOffset;
*SWF::Element::ACTIONRECORD::ActionIf::_pack = \&_pack;

##########

package SWF::Element::ACTIONRECORD::ActionDefineFunction;

sub _pack {
    my ($self, $stream) = @_;

    $self->FunctionName->pack($stream);
    $self->Params->pack($stream);

    my $offset = $self->CodeSize;

    if ($offset =~ /^[^\d\-]/) {
	$stream->mark($offset, ['Offset', $self]);
	$stream->set_UI16(0);
    } else {
	$stream->set_UI16($offset);
    }
}

*SWF::Element::ACTIONRECORD::ActionDefineFunction::_Offset = \&CodeSize;

##########

package SWF::Element::ACTIONRECORD::ActionWith;

sub _pack {
    my ($self, $stream) = @_;

    my $offset = $self->CodeSize;

    if ($offset =~ /^[^\d\-]/) {
	$stream->mark($offset, ['Offset', $self]);
	$stream->set_UI16(0);
    } else {
	$stream->set_UI16($offset);
    }
}

*SWF::Element::ACTIONRECORD::ActionWith::_Offset = \&CodeSize;

####  Video  ####
##########

package SWF::Element::Tag::DefineVideoStream;

SWF::Element::_create_flag_accessor('VideoFlagsSmoothing', 'VideoFlags', 0);
SWF::Element::_create_flag_accessor('VideoFlagsDeblocking', 'VideoFlags', 1, 2);

##########

package SWF::Element::Tag::VideoFrame;

sub _unpack {
    my ($self, $stream) = @_;

    $self->StreamID->unpack($stream);
    $self->FrameNum($stream->get_UI16);
    $self->VideoData->unpack($stream, $self->Length - 4);
}

##########

1;
__END__

# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

SWF::Element - Classes of SWF tags and elements.  
See I<Element.pod> for further information.

=head1 COPYRIGHT

Copyright 2000 Yasuhiro Sasama (ySas), <ysas@nmt.ne.jp>

This library is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

=cut


