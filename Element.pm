package SWF::Element;

use strict;
use vars qw($VERSION @ISA);

use Carp;
use SWF::BinStream;

$VERSION = '0.05';

sub new {
    my $class = shift;
    my $self = {};

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
    my @attr = map {$f=($f==0)||not ref($_) ? $_ : $_->clone} $source->configure;
    $source->new(@attr);
}

sub new_element {
    my $self = shift;
    my $name = shift;
    my $element;

    eval {$element = $self->element_type($name)->new(@_)};
    croak $@ if $@;
    return $self->{$name} = $element;
}

sub get_element {
    my ($self, $name)=@_;
    return defined $self->{$name} ? $self->{$name} : $self->new_element($name);
}

sub set_element {
    my $self = shift;
    my $name = shift;

    if (eval{$_[0]->isa($self->element_type($name))}) {
	$self->{$name} = $_[0];
    } else {
	my $element = $self->get_element($name);
	$element->configure(@_);
    }
    $self->$name;
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
	return $self->($param[0])();
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
	$d = $self->$key->defined;
	last if $d;
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
	if ($self->$key->defined) {
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

    for my $key ($self->element_names) {
	$self->$key->pack(@_);
    }
}

sub unpack { # unpack SWF binary block
    my $self = shift;

    for my $key ($self->element_names) {
	$self->$key->unpack(@_);
    }
}


# Utility sub to create subclass.

sub _create_class {
    no strict 'refs';

    my $classname = shift; 
    my $isa = shift;

    $classname = "SWF::Element::$classname";

    my $element_names = \@{"${classname}::_Element_Names"};
    my $element_types = \%{"${classname}::_Element_Types"};

    $isa = [$isa] unless ref($isa) eq 'ARRAY';
    @{"${classname}::ISA"}=map {$_ ? "SWF::Element::$_" : "SWF::Element"} @$isa;
    while (@_) {
	my $k = shift;
	my $v = shift;
	push @$element_names, $k;
	$element_types->{$k} = "SWF::Element::$v";
	*{"${classname}::$k"} = sub {
	    my $self = shift;
	    return $self->get_element($k) unless @_;
	    $self->set_element($k, @_);
	};
 
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

_create_class('ID', 'UI16');
_create_class('BinData', 'Scalar');
_create_class('RGB', '',
	      Red   => 'UI8',
	      Green => 'UI8',
	      Blue  => 'UI8');
_create_class('RGBA', '',
	      Red   => 'UI8',
	      Green => 'UI8',
	      Blue  => 'UI8',
	      Alpha => 'UI8');
_create_class('RECT', '',
	      Xmin => 'Scalar', Ymin => 'Scalar',
	      Xmax => 'Scalar', Ymax => 'Scalar');
_create_class('MATRIX', '',
	      ScaleX      => 'Scalar', ScaleY      => 'Scalar',
	      RotateSkew0 => 'Scalar', RotateSkew1 => 'Scalar',
	      TranslateX  => 'Scalar', TranslateY  => 'Scalar');
_create_class('CXFORM', '',
	      RedMultTerm   => 'Scalar', 
	      GreenMultTerm => 'Scalar',
	      BlueMultTerm  => 'Scalar',
	      RedAddTerm    => 'Scalar',
	      GreenAddTerm  => 'Scalar',
	      BlueAddTerm   => 'Scalar');
_create_class('CXFORMWITHALPHA', 'CXFORM',
	      RedMultTerm   => 'Scalar', 
	      GreenMultTerm => 'Scalar',
	      BlueMultTerm  => 'Scalar',
	      AlphaMultTerm => 'Scalar',
	      RedAddTerm    => 'Scalar',
	      GreenAddTerm  => 'Scalar',
	      BlueAddTerm   => 'Scalar',
	      AlphaAddTerm  => 'Scalar');
_create_class('STRING', 'Scalar');
_create_class('PSTRING', 'STRING');
_create_class('FILLSTYLE1', '',
	      FillStyleType  => 'UI8',
	      Color          => 'RGB',
	      GradientMatrix => 'MATRIX',
	      Gradient       => 'Array::GRADIENT1',
	      BitmapID       => 'ID',
	      BitmapMatrix   => 'MATRIX');
_create_class('FILLSTYLE3', 'FILLSTYLE1',
	      FillStyleType  => 'UI8',
	      Color          => 'RGBA',
	      GradientMatrix => 'MATRIX',
	      Gradient       => 'Array::GRADIENT3',
	      BitmapID       => 'ID',
	      BitmapMatrix   => 'MATRIX');
_create_class('GRADRECORD1', '',
	      Ratio => 'UI8',
	      Color => 'RGB');
_create_class('GRADRECORD3', '',
	      Ratio => 'UI8',
	      Color => 'RGBA');
_create_class('LINESTYLE1', '',
	      Width => 'UI16',
	      Color => 'RGB');
_create_class('LINESTYLE3', '',
	      Width => 'UI16',
	      Color => 'RGBA');
_create_class('SHAPE1', '',
	      ShapeRecords => 'Array::SHAPERECARRAY1');
_create_class('SHAPE2', 'SHAPE1',
	      ShapeRecords => 'Array::SHAPERECARRAY2');
_create_class('SHAPE3', 'SHAPE1',
	      ShapeRecords => 'Array::SHAPERECARRAY3');
_create_class('SHAPEWITHSTYLE1', 'SHAPE1',
	      FillStyles   => 'Array::FILLSTYLEARRAY1',
	      LineStyles   => 'Array::LINESTYLEARRAY1',
	      ShapeRecords => 'Array::SHAPERECARRAY1');
_create_class('SHAPEWITHSTYLE2', 'SHAPEWITHSTYLE1',
	      FillStyles   => 'Array::FILLSTYLEARRAY2',
	      LineStyles   => 'Array::LINESTYLEARRAY2',
	      ShapeRecords => 'Array::SHAPERECARRAY2');
_create_class('SHAPEWITHSTYLE3', 'SHAPEWITHSTYLE1',
	      FillStyles   => 'Array::FILLSTYLEARRAY3',
	      LineStyles   => 'Array::LINESTYLEARRAY3',
	      ShapeRecords => 'Array::SHAPERECARRAY3');
_create_class('SHAPEREC1', '');
_create_class('SHAPEREC2', 'SHAPEREC1');
_create_class('SHAPEREC3', 'SHAPEREC1');
_create_class('SHAPEREC1::NEWSHAPE', 'SHAPEREC1',
	      MoveX      => 'Scalar',
	      MoveY      => 'Scalar',
	      Fill0Style => 'Scalar',
	      Fill1Style => 'Scalar',
	      LineStyle  => 'Scalar',
	      FillStyles => 'Array::FILLSTYLEARRAY1',
	      LineStyles => 'Array::LINESTYLEARRAY1');
_create_class('SHAPEREC2::NEWSHAPE', ['SHAPEREC1::NEWSHAPE', 'SHAPEREC2'],
	      MoveX      => 'Scalar',
	      MoveY      => 'Scalar',
	      Fill0Style => 'Scalar',
	      Fill1Style => 'Scalar',
	      LineStyle  => 'Scalar',
	      FillStyles => 'Array::FILLSTYLEARRAY2',
	      LineStyles => 'Array::LINESTYLEARRAY2');
_create_class('SHAPEREC3::NEWSHAPE', ['SHAPEREC1::NEWSHAPE', 'SHAPEREC3'],
	      MoveX      => 'Scalar',
	      MoveY      => 'Scalar',
	      Fill0Style => 'Scalar',
	      Fill1Style => 'Scalar',
	      LineStyle  => 'Scalar',
	      FillStyles => 'Array::FILLSTYLEARRAY3',
	      LineStyles => 'Array::LINESTYLEARRAY3');
_create_class('SHAPERECn::STRAIGHTEDGE', ['SHAPEREC1', 'SHAPEREC2', 'SHAPEREC3'],
	      X => 'Scalar', Y => 'Scalar');
_create_class('SHAPERECn::CURVEDEDGE',  ['SHAPEREC1', 'SHAPEREC2', 'SHAPEREC3'],
	      ControlX => 'Scalar', ControlY => 'Scalar',
	      AnchorX  => 'Scalar', AnchorY  => 'Scalar');
_create_class('Tag', '');
_create_class('MORPHFILLSTYLE', '',
	      FillStyleType   => 'UI8',
	      Color1          => 'RGBA',
	      Color2          => 'RGBA',
	      GradientMatrix1 => 'MATRIX',
	      GradientMatrix2 => 'MATRIX',
	      Gradient        => 'Array::MORPHGRADIENT',
	      BitmapID        => 'ID',
	      BitmapMatrix1   => 'MATRIX',
	      BitmapMatrix2   => 'MATRIX');
_create_class('MORPHGRADRECORD', '',
	      Ratio1 => 'UI8', Color1 => 'RGBA',
	      Ratio2 => 'UI8', Color2 => 'RGBA');
_create_class('MORPHLINESTYLE', '',
	      Width1 => 'UI16', Width2 => 'UI16',
	      Color1 => 'RGBA', Color2 => 'RGBA');
_create_class('BUTTONRECORD1', '',
	      ButtonStates    => 'UI8',
	      ButtonCharacter => 'UI16',
	      ButtonLayer     => 'UI16',
	      ButtonMatrix    => 'MATRIX');
_create_class('BUTTONRECORD2', 'BUTTONRECORD1',
	      ButtonStates    => 'UI8',
	      ButtonCharacter => 'UI16',
	      ButtonLayer     => 'UI16',
	      ButtonMatrix    => 'MATRIX',
	      ColorTransform  => 'CXFORMWITHALPHA'); # not CXFORM
_create_class('ACTIONCONDITION', '',
	      Condition => 'UI16', Actions => 'Array::ACTIONRECORDARRAY');
_create_class('TEXTRECORD1', '');
_create_class('TEXTRECORD2', 'TEXTRECORD1');
_create_class('TEXTRECORD::Type0', ['TEXTRECORD1','TEXTRECORD2'],
	      GlyphEntries => 'Array::GLYPHENTRYARRAY');
_create_class('GLYPHENTRY', '',
	      TextGlyphIndex => 'Scalar', TextGlyphAdvance => 'Scalar');
_create_class('TEXTRECORD1::Type1', 'TEXTRECORD1',
	      TextFont    => 'ID',
	      TextColor   => 'RGB',
	      TextXOffset => 'SI16',
	      TextYOffset => 'SI16',
	      TextHeight  => 'UI16');
_create_class('TEXTRECORD2::Type1', ['TEXTRECORD1::Type1', 'TEXTRECORD2'],
	      TextFont    => 'ID',
	      TextColor   => 'RGBA',
	      TextXOffset => 'SI16',  # UI16 ?
	      TextYOffset => 'SI16',  # UI16 ?
	      TextHeight  => 'UI16');
_create_class('SOUNDINFO', '',
	      SyncFlags       => 'Scalar',
	      InPoint         => 'UI32',
	      OutPoint        => 'UI32',
	      LoopCount       => 'UI16',
	      EnvelopeRecords => 'Array::SNDENVARRAY');
_create_class('SNDENV', '',
	      Mark44 => 'UI32', Level0 => 'UI16', Level1 => 'UI16');
_create_class('ACTIONTagNumber', 'UI8');
_create_class('ACTIONRECORD', '',
	      Tag => 'ACTIONTagNumber');
_create_class('ACTIONDATA', 'Scalar');
_create_class('ACTIONDATA::String', 'ACTIONDATA');
_create_class('ACTIONDATA::Property', 'ACTIONDATA');
_create_class('ACTIONDATA::NULL', 'ACTIONDATA');
_create_class('ACTIONDATA::Register', 'ACTIONDATA');
_create_class('ACTIONDATA::Boolean', 'ACTIONDATA');
_create_class('ACTIONDATA::Double', 'ACTIONDATA');
_create_class('ACTIONDATA::Integer', 'ACTIONDATA');
_create_class('ACTIONDATA::Lookup', 'ACTIONDATA');
_create_class('EVENTACTION', '',
	      Flags  => 'UI16',
	      Action => 'Array::ACTIONBLOCK2');  # ?
_create_class('ASSET', '',
	      ID     => 'UI16',
	      String => 'STRING');

##########

package SWF::Element::Scalar;

use overload '""' => sub {$_[0]->value}, '0+' => sub{$_[0]->value}, 
    '++' => sub {${$_[0]}++},
    '--' => sub {${$_[0]}--},
    fallback =>1;

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
    $$self = $newval if defined $newval and !ref($newval);
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

# Create elemental scalar subclasses.

for my $type (qw/UI8 SI8 UI16 SI16 UI32 SI32/) {
    eval <<ENDPACKAGE;
#-
    package SWF::Element::$type;

    \@SWF::Element::${type}::ISA=('SWF::Element::Scalar');

    sub pack {
	my (\$self, \$stream)=\@_;
	\$stream->set_$type(\$self->value);
    }

    sub unpack {
        my (\$self, \$stream)=\@_;
        \$self->configure(\$stream->get_$type);
    }
#-
ENDPACKAGE

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
	if (eval{$p->isa(ref($element))}) {
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
_create_array_class('SHAPERECARRAY1',  'Array',  'SHAPEREC1',
		    sub {$_[1]->set_bits(0,6)},
                    sub {$_[1]->isa('SWF::Element::SHAPERECn::END')});

_create_array_class('SHAPERECARRAY2', 'Array::SHAPERECARRAY1', 'SHAPEREC2');
_create_array_class('SHAPERECARRAY3', 'Array::SHAPERECARRAY1', 'SHAPEREC3');
_create_array_class('MORPHFILLSTYLEARRAY', 'Array2',    'MORPHFILLSTYLE');
_create_array_class('MORPHLINESTYLEARRAY', 'Array2',    'MORPHLINESTYLE');
_create_array_class('MORPHGRADIENT',       'Array1',    'MORPHGRADRECORD');
_create_array_class('BUTTONRECORDARRAY1',  'Array',     'BUTTONRECORD1',
                     sub {$_[1]->set_UI8(0)},
                     sub {$_[1]->ButtonStates == 0});

_create_array_class('BUTTONRECORDARRAY2', 'Array::BUTTONRECORDARRAY1', 'BUTTONRECORD2');
_create_array_class('ACTIONCONDITIONARRAY', 'Array', 'ACTIONCONDITION');
_create_array_class('SHAPEARRAY1',          'Array', 'SHAPE1');
_create_array_class('SHAPEARRAY2',          'Array', 'SHAPE2');
_create_array_class('FONTCODETABLE',        'Array::Scalar');
_create_array_class('FONTADVANCETABLE',     'Array::Scalar');
_create_array_class('FONTBOUNDSTABLE',      'Array', 'RECT', sub {});
_create_array_class('TEXTRECORDARRAY1',     'Array', 'TEXTRECORD1',
                    sub {$_[1]->set_UI8(0)},
                    sub {$_[1]->isa('SWF::Element::TEXTRECORD::End')});

_create_array_class('TEXTRECORDARRAY2', 'Array::TEXTRECORDARRAY1', 'TEXTRECORD2');
_create_array_class('GLYPHENTRYARRAY',  'Array1',           'GLYPHENTRY');
_create_array_class('SNDENVARRAY',      'Array1',           'SNDENV');
_create_array_class('ACTIONRECORDARRAY','Array',            'ACTIONRECORD',
                    sub {$_[1]->set_UI8(0)},
                    sub {$_[1]->Tag == 0});
_create_array_class('ACTIONDATAARRAY',  'Array',            'ACTIONDATA',
                    sub {});
_create_array_class('ACTIONFUNCARGS',   'Array3',           'STRING');
_create_array_class('WORDARRAY',        'Array3',           'STRING');
_create_array_class('ACTIONBLOCK',      'Array1',           'ACTIONRECORD');
_create_array_class('ACTIONBLOCK2',     'Array1',           'ACTIONRECORD');
_create_array_class('EVENTACTIONARRAY', 'Array',            'EVENTACTION',
                    sub {$_[1]->set_UI16(0)},
                    sub {$_[1]->Flags == 0});
_create_array_class('ASSETARRAY',       'Array3',           'ASSET');

##########

package SWF::Element::Array::Scalar;
use vars qw(@ISA);

@ISA=qw(SWF::Element::Array);

sub configure {
    my ($self, @param)=@_;
    @param = @{$param[0]} if (ref($param[0]) eq 'ARRAY' and ref($param[0][0]));
    for my $p (@param) {
	my $element = $self->new_element;
	if (eval{$p->isa(ref($element))}) {
	    $element = $p;
	} elsif (ref($p) eq 'SCALAR') {
	    $element->configure($p);
	} else {
	  Carp::croak "Element type mismatch: ".ref($p)." in ".ref($self);
	}
	push @$self, $element;
    }
    $self;
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
	$stream->set_sbits_list(5, $self->RotateSkew0 * 65536, $self->RotateSkew1 *65536);
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

    return ($self->TranslateX ->defined or $self->TranslateY ->defined or
	    $self->ScaleX != 1          or $self->ScaleY != 1 or
	    $self->RotateSkew0->defined or $self->RotateSkew1->defined);
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

    $self->ScaleX($cos*$a+$sin*$c);
    $self->RotateSkew0($cos*$b+$sin*$d);
    $self->RotateSkew1(-$sin*$a+$cos*$b);
    $self->ScaleY(-$sin*$b+$cos*$d);
    $self;
}

##########

package SWF::Element::CXFORM;

sub pack {
    my ($self, $stream)=@_;
    my @param = map $self->$_->value, $self->element_names;
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
    $style->pack($stream);
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
    my $style = $self->FillStyleType;
    $style->unpack($stream);
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

package SWF::Element::SHAPE1;

sub pack {
    my ($self, $stream)=@_;
    my ($fillidx, $lineidx)=(-1,-1);
    my ($nfillbits, $nlinebits);
    my ($x, $y);

    $stream->flush_bits;
    for my $shaperec (@{$self->ShapeRecords}) {
	next unless $shaperec->isa('SWF::Element::SHAPEREC1::NEWSHAPE');
	my $style;
	$style   = $shaperec->Fill0Style->value;
	$fillidx = $style if (defined $style and $fillidx < $style);
	$style   = $shaperec->Fill1Style->value;
	$fillidx = $style if (defined $style and $fillidx < $style);
	$style   = $shaperec->LineStyle ->value;
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
    $stream->set_bits($nfillbits, 4);
    $stream->set_bits($nlinebits, 4);
    $self->ShapeRecords->pack($stream, \$x, \$y, \$nfillbits, \$nlinebits);
}

sub unpack {
    my ($self, $stream)=@_;
    my ($nfillbits, $nlinebits);
    my ($x, $y);

    $stream->flush_bits;
    $nfillbits=$stream->get_bits(4);
    $nlinebits=$stream->get_bits(4);

    $self->ShapeRecords->unpack($stream, \$x, \$y, \$nfillbits, \$nlinebits);
}

##########

package SWF::Element::SHAPEWITHSTYLE1;

sub pack {
    my ($self, $stream)=@_;
    my ($fillidx, $lineidx)=($#{$self->FillStyles}+1, $#{$self->LineStyles}+1);
    my ($nfillbits, $nlinebits)=(0,0);
    my ($x, $y);

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
    $self->ShapeRecords->pack($stream, \$x, \$y, \$nfillbits, \$nlinebits);
}

sub unpack {
    my ($self, $stream)=@_;

    $self->FillStyles->unpack($stream);
    $self->LineStyles->unpack($stream);
    $self->SUPER::unpack($stream);
}

##########

package SWF::Element::SHAPEREC1;

sub unpack {
    my ($self, $stream, $x, $y, $nfillbits, $nlinebits)=@_;

    if ($stream->get_bits(1)) { # Edge

	if ($stream->get_bits(1)) {
	    bless $self, 'SWF::Element::SHAPERECn::STRAIGHTEDGE';
	} else {
	    bless $self, 'SWF::Element::SHAPERECn::CURVEDEDGE';
	}
	$self->_init;
	$self->unpack($stream, $x, $y);

    } else { # New Shape or End of Shape

	my $flags = $stream->get_bits(5);
	if ($flags==0) {
	    bless $self, 'SWF::Element::SHAPERECn::END';
	} else {
	    bless $self, ref($self).'::NEWSHAPE';
	    $self->_init;
	    $self->unpack($stream, $x, $y, $nfillbits, $nlinebits, $flags);
	}
    }
}

sub pack {
    Carp::croak "Not enough data to pack ".ref($_[0]);
}

use vars '$AUTOLOAD';

sub AUTOLOAD { # auto re-bless with proper sub class by specified accessor.
    my ($self, @param)=@_;
    my ($name, $class);

    return if $AUTOLOAD =~/::DESTROY$/;

    Carp::croak "No such method: $AUTOLOAD" unless $AUTOLOAD=~/::([A-Z]\w+)$/;
    $name = $1;
    $class = ref($self);

    for my $subclass ("${class}::NEWSHAPE", 'SWF::Element::SHAPERECn::STRAIGHTEDGE', 'SWF::Element::SHAPERECn::CURVEDEDGE') {
	$class=$subclass, last if $subclass->element_type($name);
    }
    Carp::croak "Element '$name' is NOT in $class " if $class eq ref($self);

    bless $self, $class;
    $self->$name(@param);
}

##########

package SWF::Element::SHAPEREC1::NEWSHAPE;

sub pack {
    my ($self, $stream, $x, $y, $nfillbits, $nlinebits)=@_;
    my ($flags)=0;

    my $j=0;
    for my $i (qw/MoveX Fill0Style Fill1Style LineStyle/) {
	$flags |=(1<<$j) if $self->$i->defined;
	$j++;
    }
    $flags |= 16 if @{$self->FillStyles}>0 or @{$self->LineStyles}>0;
    $stream->set_bits($flags, 6);
    if ($flags & 1) { # MoveTo
	($$x, $$y)=($self->MoveX, $self->MoveY);
	$stream->set_sbits_list(5, $$x, $$y);
    }
    if ($flags & 2) { #FillStyle0
	$stream->set_bits($self->Fill0Style, $$nfillbits);
    }
    if ($flags & 4) { #FillStyle1
	$stream->set_bits($self->Fill1Style, $$nfillbits);
    }
    if ($flags & 8) { #LineStyle
	$stream->set_bits($self->LineStyle, $$nlinebits);
    }
    if ($flags & 16) { # NewStyles (SHAPEREC2,3)
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
    my ($self, $stream, $x, $y, $nfillbits, $nlinebits, $flags)=@_;

    if ($flags & 1) { # MoveTo
	my ($nbits)=$stream->get_bits(5);
	$$x=$self->MoveX($stream->get_sbits($nbits));
	$$y=$self->MoveY($stream->get_sbits($nbits));
    }
    if ($flags & 2) { # FillStyle0
	$self->Fill0Style($stream->get_bits($$nfillbits));
    }
    if ($flags & 4) { # FillStyle1
	$self->Fill1Style($stream->get_bits($$nfillbits));
    }
    if ($flags & 8) { # LineStyle
	$self->LineStyle($stream->get_bits($$nlinebits));
    }
    if ($flags & 16) { # NewStyles (SHAPEREC2,3)
	$self->FillStyles->unpack($stream);
	$self->LineStyles->unpack($stream);
	$$nfillbits=$stream->get_bits(4);
	$$nlinebits=$stream->get_bits(4);
    }
}

##########

package SWF::Element::SHAPERECn::STRAIGHTEDGE;

sub unpack {
    my ($self, $stream, $x, $y)=@_;
    my $nbits = $stream->get_bits(4)+2;
    if ($stream->get_bits(1)) {
	$self->X($$x+=$stream->get_sbits($nbits));
	$self->Y($$y+=$stream->get_sbits($nbits));
    } else {
	if ($stream->get_bits(1)) {
	    $self->X($$x);
	    $self->Y($$y+=$stream->get_sbits($nbits));
	} else {
	    $self->X($$x+=$stream->get_sbits($nbits));
	    $self->Y($$y);
	}
    }
}

sub pack {
    my ($self, $stream, $x, $y)=@_;
    my ($dx, $dy, $nbits);

    $stream->set_bits(3,2); # Type=1, Edge=1

    $dx=$self->X - $$x;
    $dy=$self->Y - $$y;
    $nbits=SWF::BinStream::Write::get_maxbits_of_sbits_list($dx, $dy);
    $nbits=2 if ($nbits<2);
    $stream->set_bits($nbits-2,4);
    if ($dx==0) {
	$stream->set_bits(1,2); # GeneralLine=0, Vert=1
	$stream->set_sbits($dy, $nbits);
	$$y=$self->Y;
    } elsif ($dy==0) {
	$stream->set_bits(0,2); # GeneralLine=0, Vert=0
	$stream->set_sbits($dx, $nbits);
	$$x=$self->X;
    } else {
	$stream->set_bits(1,1); # GeneralLine=1
	$stream->set_sbits($dx, $nbits);
	$stream->set_sbits($dy, $nbits);
	$$x=$self->X;
	$$y=$self->Y;
    }
}

##########

package SWF::Element::SHAPERECn::CURVEDEDGE;

sub unpack {
    my ($self, $stream, $x, $y)=@_;
    my ($nbits)=$stream->get_bits(4)+2;
    my ($i);

    $self->ControlX($$x+=$stream->get_sbits($nbits));
    $self->ControlY($$y+=$stream->get_sbits($nbits));
    $self->AnchorX($$x+=$stream->get_sbits($nbits));
    $self->AnchorY($$y+=$stream->get_sbits($nbits));
}

sub pack {
    my ($self, $stream, $x, $y)=@_;
    my ($nbits, @d);

    @d=();
    push @d, $self->ControlX - $$x;
    $$x=$self->ControlX;
    push @d, $self->ControlY - $$y;
    $$y=$self->ControlY;
    push @d, $self->AnchorX - $$x;
    $$x=$self->AnchorX;
    push @d, $self->AnchorY - $$y;
    $$y=$self->AnchorY;
    $nbits=SWF::BinStream::Write::get_maxbits_of_sbits_list(@d);
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

    $self = {};
    delete @headerdata{'Length','Tag'};

    if (defined $tag) {
	my $class = _tag_class($tag);
	bless $self, $class;
    } else {
	$class=ref($class)||$class;
	$class.='::Unidentified' if $class=~/Tag$/;
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
    $self->{Length}=$len if defined $len;
    $self->{Length};
}

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
    return 'SWF::Element::Tag::'.($tagname[$_[0]]||'Undefined');
}

sub _create_tag {
    no strict 'refs';

    my $tagname = shift;
    my $tagno = shift;
    my $isa = shift;

    $isa = 'Tag'.($isa && "::$isa");
    SWF::Element::_create_class("Tag::$tagname", $isa, @_);

    $tagname[$tagno] = $tagname;
    *{"SWF::Element::Tag::${tagname}::tag_number"} = sub {$tagno};
}

_create_tag('Undefined', 16, '',
	    'Tag'    => 'Scalar',
	    'Data'   => 'BinData');
{
    no strict 'refs';
    no warnings;
    *{"SWF::Element::Tag::Undefined::tag_number"} = sub {$_[0]->Tag};
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
	    ShapeBounds1    => 'RECT',
	    ShapeBounds2    => 'RECT',
	    MorphFillStyles => 'Array::MORPHFILLSTYLEARRAY',
	    MorphLineStyles => 'Array::MORPHLINESTYLEARRAY',
	    Edges1          => 'SHAPE3',
	    Edges2          => 'SHAPE3');

##  Bitmaps  ##

_create_tag('DefineBits', 6, '',

	    BitmapID        => 'ID',
	    BitmapJPEGImage => 'BinData');

_create_tag('DefineBitsJPEG2', 21, '',

	    BitmapID           => 'ID',
	    BitmapJPEGEncoding => 'BinData',
	    BitmapJPEGImage    => 'BinData');

_create_tag('DefineBitsJPEG3', 35, 'DefineBitsJPEG2',

	    BitmapID           => 'ID',
	    BitmapJPEGEncoding => 'BinData',
	    BitmapJPEGImage    => 'BinData',
	    BitmapAlphaData    => 'BinData');

_create_tag('DefineBitsLossless', 20, '',

	    BitmapID             => 'ID',
	    BitmapFormat         => 'UI8',
	    BitmapWidth          => 'UI16',
	    BitmapHeight         => 'UI16',
	    BitmapColorTableSize => 'UI8',
	    CompressedData       => 'BinData',
##	    ColorTable => '', BitmapImage => '', ColorTableType => 'RGB'
	    );

_create_tag('DefineBitsLossless2', 36, 'DefineBitsLossless',

	    BitmapID             => 'ID',
	    BitmapFormat         => 'UI8',
	    BitmapWidth          => 'UI16',
	    BitmapHeight         => 'UI16',
	    BitmapColorTableSize => 'UI8',
	    CompressedData       => 'BinData',
##	    ColorTable => '', BitmapImage => '', ColorTableType => 'RGBA'
	    );

_create_tag('JPEGTables', 8, '',

	    BitmapJPEGEncoding => 'BinData');

##  Buttons  ##

_create_tag('DefineButton', 7, '',

	    ButtonID => 'ID',
	    Buttons  => 'Array::BUTTONRECORDARRAY1',
	    Actions  => 'Array::ACTIONRECORDARRAY');

_create_tag('DefineButton2', 34, '',

	    ButtonID               => 'ID',
	    Flags                  => 'UI8',
	    Buttons                => 'Array::BUTTONRECORDARRAY2',
	    Button2ActionCondition => 'Array::ACTIONCONDITIONARRAY');

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

	    FontID => 'ID', ShapeTable => 'Array::SHAPEARRAY1');

_create_tag('DefineFont2', 48, '',

	    FontID           => 'ID', 
	    FontFlags        => 'UI16',
	    FontName         => 'PSTRING', 
	    FontShapeTable   => 'Array::SHAPEARRAY2',
	    FontCodeTable    => 'Array::FONTCODETABLE',
	    FontAscent       => 'SI16',
	    FontDescent      => 'SI16',
	    FontLeading      => 'SI16',
	    FontAdvanceTable => 'Array::FONTADVANCETABLE',
	    FontBoundsTable  => 'Array::FONTBOUNDSTABLE',
	    FontKerningTable => 'FONTKERNINGTABLE');

_create_tag('DefineFontInfo', 13, '',

	    FontID        => 'ID',
	    FontName      => 'PSTRING', 
	    FontFlags     => 'UI8',
	    FontCodeTable => 'Array::FONTCODETABLE'); 

_create_tag('DefineText', 11, '',

	    TextID      => 'ID',
	    TextBounds  => 'RECT',
	    TextMatrix  => 'MATRIX',
	    TextRecords => 'Array::TEXTRECORDARRAY1');

_create_tag('DefineText2', 33, 'DefineText',

	    TextID      => 'ID',
	    TextBounds  => 'RECT',
	    TextMatrix  => 'MATRIX',
	    TextRecords => 'Array::TEXTRECORDARRAY2');

_create_tag('DefineEditText', 37, '',

	    TextFieldID     => 'ID',
	    TextFieldBounds => 'RECT',
	    Flags           => 'UI16',
	    FontID          => 'ID',
	    FontHeight      => 'UI16',
	    TextColor       => 'RGBA',
	    MaxLength       => 'UI16',
	    Align           => 'UI8',
	    LeftMargin      => 'UI16',
	    RightMargin     => 'UI16',
	    Indent          => 'UI16',
	    Leading         => 'UI16',
	    Variable        => 'STRING',
	    InitialText     => 'STRING');

##  Sounds  ##

_create_tag('DefineSound', 14, '',

	    SoundID          => 'ID',
	    Flags            => 'UI8',
	    SoundSampleCount => 'UI32',
	    SoundData        => 'BinData');

_create_tag('SoundStreamBlock', 19, '',

	    StreamSoundData => 'BinData');

_create_tag('SoundStreamHead', 18, '',

	    StreamSoundMixFormat   => 'UI8',
	    Flags                  => 'UI8',
	    StreamSoundSampleCount => 'UI16');

_create_tag('SoundStreamHead2', 45, 'SoundStreamHead',

	    StreamSoundMixFormat   => 'UI8',
	    Flags                  => 'UI8',
	    StreamSoundSampleCount => 'UI16');

##  Sprites  ##

_create_tag('DefineSprite', 39, '',

	    SpriteID => 'ID',
	    FrameCount => 'UI16',
	    MiniFileStructure => 'BinData');

##  Display list  ##

_create_tag('PlaceObject', 4, '',

	    CharacterID    => 'ID',
	    Depth          => 'UI16',
	    Matrix         => 'MATRIX',
	    ColorTransform => 'CXFORM');

_create_tag('PlaceObject2', 26, '',

	    Flags          => 'UI8',
	    Depth          => 'UI16',
	    CharacterID    => 'ID',
	    Matrix         => 'MATRIX',
	    ColorTransform => 'CXFORMWITHALPHA',
	    Ratio          => 'UI16',
	    ClipDepth      => 'UI16',
	    Name           => 'STRING',
	    Unknown        => 'UI16',
	    EventActions   => 'Array::EVENTACTIONARRAY');

_create_tag('RemoveObject', 5, '',

	    CharacterID => 'ID', Depth => 'UI16' );

_create_tag('RemoveObject2', 28, '',

	    Depth => 'UI16' );

_create_tag('ShowFrame', 1, '');

##  Control  ##

_create_tag('BackgroundColor', 9, '',

	    BackgroundColor => 'RGB' );

_create_tag('FrameLabel', 43, '',

	    Label => 'STRING' );

_create_tag('Protect', 24, '',

	    Password => 'BinData' );

_create_tag('StartSound', 15, '',

	    SoundID   => 'ID',
	    SoundInfo => 'SOUNDINFO');

_create_tag('End', 0, '');

_create_tag('ExportAssets', 56, '',

	    Assets => 'Array::ASSETARRAY');

_create_tag('ImportAssets', 57, '',

	    Assets => 'Array::ASSETARRAY');

##  Actions  ##

_create_tag('DoAction', 12, '',

	    Actions => 'Array::ACTIONRECORDARRAY');

##  others?  ##

_create_tag('FreeCharacter', 3, '',

	    CharacterID => 'ID');

_create_tag('NameCharacter', 40, '',

	    CharacterID => 'ID',
	    Name        => 'STRING');


### Unidentified Tag ###

package SWF::Element::Tag::Unidentified;

@SWF::Element::Tag::Unidentified::ISA = ('SWF::Element::Tag');

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


####  Undefined  ####
##########

package SWF::Element::Tag::Undefined;

sub _init {
    my $self = shift;
    my ($length, $tag) = @_;

    $self->SUPER::_init(@_);
    Carp::carp "Tag No. $tag is undefined!?";
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
    $self->ShapeBounds1->unpack($stream);
    $self->ShapeBounds2->unpack($stream);
    $stream->get_UI32; # Skip Offset
    $self->MorphFillStyles->unpack($stream);
    $self->MorphLineStyles->unpack($stream);
    $stream->flush_bits;
    $self->Edges1->unpack($stream);
    $stream->flush_bits;
    $self->Edges2->unpack($stream);
}

sub _pack {
    my ($self, $stream)=@_;

    $self->CharacterID->pack($stream);
    $self->ShapeBounds1->pack($stream);
    $self->ShapeBounds2->pack($stream);
    {
	my $tempstream=$stream->sub_stream;
	$self->MorphFillStyles->pack($tempstream);
	$self->MorphLineStyles->pack($tempstream);
	$tempstream->flush_bits;
	$self->Edges1->pack($tempstream);
	$tempstream->flush_bits;
	$stream->set_UI32($tempstream->tell);
	$tempstream->flush_stream;
    }
    $self->Edges2->pack($stream);
    $stream->flush_bits;
}

##########

package SWF::Element::MORPHFILLSTYLE;

sub pack {
    my ($self, $stream)=@_;
    my $style=$self->FillStyleType;
    $style->pack($stream);
    if ($style==0x00) {
	$self->Color1->pack($stream);
	$self->Color2->pack($stream);
    } elsif ($style==0x10 or $style==0x12) {
	$self->GradientMatrix1->pack($stream);
	$self->GradientMatrix2->pack($stream);
	$self->Gradient->pack($stream);
    } elsif ($style==0x40 or $style==0x41) {
	$self->BitmapID->pack($stream);
	$self->BitmapMatrix1->pack($stream);
	$self->BitmapMatrix2->pack($stream);
    }
}

sub unpack {
    my ($self, $stream)=@_;
    my $style;
    $style=$self->FillStyleType($stream->get_UI8);
    if ($style==0x00) {
	$self->Color1->unpack($stream);
	$self->Color2->unpack($stream);
    } elsif ($style==0x10 or $style==0x12) {
	$self->GradientMatrix1->unpack($stream);
	$self->GradientMatrix2->unpack($stream);
	$self->Gradient->unpack($stream);
    } elsif ($style==0x40 or $style==0x41) {
	$self->BitmapID->unpack($stream);
	$self->BitmapMatrix1->unpack($stream);
	$self->BitmapMatrix2->unpack($stream);
    }
}


####  Bitmaps  ####
##########

package SWF::Element::Tag::DefineBits;

sub _unpack {
    my ($self, $stream)=@_;

    $self->BitmapID->unpack($stream);
    $self->BitmapJPEGImage->unpack($stream, $self->Length - 2);
}

##########

package SWF::Element::Tag::DefineBitsJPEG2;

sub _unpack {
    my ($self, $stream)=@_;

    $self->BitmapID->unpack($stream);

    $self->_unpack_JPEG($stream, $self->Length - 2);
}

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

##########

package SWF::Element::Tag::DefineBitsJPEG3;

sub _unpack {
    my ($self, $stream)=@_;

    $self->BitmapID->unpack($stream);
    my $offset = $stream->get_UI32;
    $self->_unpack_JPEG($stream, $offset);
    $self->BitmapAlphaData->unpack($stream, $self->Length - $offset - 6);
}

sub _pack {
    my ($self, $stream)=@_;

    $self->BitmapID->pack($stream);
    $stream->set_UI32($self->BitmapJPEGEncoding->Length + $self->BitmapJPEGImage->Length);
    $self->BitmapJPEGEncoding->pack($stream);
    $self->BitmapJPEGImage->pack($stream);
    $self->BitmapAlphaData->pack($stream);
}

##########

package SWF::Element::Tag::DefineBitsLossless;

sub _unpack {
    my ($self, $stream)=@_;
    my $length=$self->Length - 7;

#    delete @{$self}{qw/ColorTable BitmapImage/};

    for my $element (qw/BitmapID BitmapFormat BitmapWidth BitmapHeight/) {
	$self->$element->unpack($stream);
    }
    if ($self->BitmapFormat == 3) {
	$self->BitmapColorTableSize->unpack($stream);
	$length--;
    }
    $self->CompressedData->unpack($stream, $length);
#    $self->decompress;
}

sub _pack {
    my ($self, $stream)=@_;

#    $self->compress if defined $self->{'ColorTable'} and defined $self->{'BitmapImage'};
    for my $element (qw/BitmapID BitmapFormat BitmapWidth BitmapHeight/) {
	$self->$element->pack($stream);
    }
    $self->BitmapColorTableSize->pack($stream) if $self->BitmapFormat == 3;
    $self->CompressedData->pack($stream);
}

sub decompress {
}

sub compress {
}

##########

package SWF::Element::Tag::JPEGTables;

sub _unpack {
    my ($self, $stream)=@_;

    $self->BitmapJPEGEncoding->unpack($stream, $self->Length);
}

####  Buttons  ####

##########

package SWF::Element::BUTTONRECORD1;

sub unpack {
    my ($self, $stream)=@_;

    $self->ButtonStates->unpack($stream);
    return if $self->ButtonStates == 0;
    my @names = $self->element_names;
    shift @names;
    for my $element (@names) {
	$self->$element->unpack($stream);
    }
}

{
    my $bit = 0;
    for my $f (qw/StateOver StateUp StateDown StateHitTest/) {
      SWF::Element::_create_flag_accessor($f, 'ButtonStates', $bit++);
    }
}

##########

package SWF::Element::Tag::DefineButton2;

sub _unpack {
    my ($self, $stream)=@_;

    $self->ButtonID->unpack($stream);
    $self->Flags->unpack($stream);
    my $offset=$stream->get_UI16;
    $self->Buttons->unpack($stream);
    $self->Button2ActionCondition->unpack($stream) if $offset;
}

sub _pack {
    my ($self, $stream)=@_;
    my $actions = $self->Button2ActionCondition;

    $self->ButtonID->pack($stream);
    $self->Flags->pack($stream);
    my $substream = $stream->sub_stream;
    $self->Buttons->pack($substream);
    $stream->set_UI16((@$actions>0) && ($substream->tell + 2));
    $substream->flush_stream;
    $actions->pack($stream) if (@$actions>0);
}

##########

package SWF::Element::Array::ACTIONCONDITIONARRAY;

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

package SWF::Element::ACTIONCONDITION;

{
    my $bit = 0;

    for my $f (qw/IdleToOverUp OverUpToIdle OverUpToOverDown OverDownToOverUp OverDownToOutDown OutDownToOverDown OutDownToIdle IdleToOverDown OverDownToIdle/) {
      SWF::Element::_create_flag_accessor($f, 'Condition', $bit++);
    }
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

package SWF::Element::Array::SHAPEARRAY1;

sub pack {
    my ($self, $stream)=@_;
    my $offset = @$self*2;

    $stream->set_UI16($offset);

    my $tempstream = $stream->sub_stream;
    my $last = pop @$self;

    for my $element (@$self) {
	$element->pack($tempstream);
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

package SWF::Element::Array::SHAPEARRAY2;

sub pack {     # return wide offset flag (true => 32bit, false => 16bit)
    my ($self, $stream)=@_;
    my (@offset, $wideoffset);
    my $glyphcount=@$self;

    $offset[0]=0;
    my $tempstream=$stream->sub_stream;

    for my $element (@$self) {
	$element->pack($tempstream);
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

    $self->FontID   ->unpack($stream);
    $self->FontFlags->unpack($stream);
    $self->FontName->unpack($stream);
    my $glyphcount = $stream->get_UI16;
    $self->FontShapeTable->unpack($stream, $self->FontFlagsWideOffsets);
    $self->FontCodeTable->unpack($stream, $glyphcount, $self->FontFlagsWideCodes);
    if ($self->FontFlagsHasLayout) {
	$self->FontAscent      ->unpack($stream);
	$self->FontDescent     ->unpack($stream);
	$self->FontLeading     ->unpack($stream);
	$self->FontAdvanceTable->unpack($stream, $glyphcount);
	$self->FontBoundsTable ->unpack($stream, $glyphcount);
	$self->FontKerningTable->unpack($stream, $self->FontFlagsWideCodes);
    }
}

sub _pack {
    my ($self, $stream)=@_;
    my $glyphcount = @{$self->FontCodeTable};

    $self->FontID->pack($stream);
    my $tempstream = $stream->sub_stream;

    $self->FontName->pack($tempstream);
    $tempstream->set_UI16($glyphcount);
    $self->FontShapeTable->pack($tempstream) and ($self->FontFlagsWideOffsets(1));
    $self->FontCodeTable ->pack($tempstream) and ($self->FontFlagsWideCodes(1));
    if ($self->FontAscent->defined) {
	$self->FontFlagsHasLayout(1);
	for my $element (qw/FontAscent FontDescent FontLeading FontAdvanceTable FontBoundsTable/) {
	    $self->$element->pack($tempstream);
	}
	$self->FontKerningTable->pack($tempstream, $self->FontFlagsWideCodes);
    }
    $self->FontFlags->pack($stream);
    $tempstream->flush_stream;
}

{
    my $bit = 0;
    for my $f (qw/FontFlagsBold FontFlagsItalic FontFlagsWideCodes FontFlagsWideOffsets FontFlagsANSI FontFlagsUnicode FontFlagsShiftJIS FontFlagsHasLayout/) {
      SWF::Element::_create_flag_accessor($f, 'FontFlags', $bit++);
    }
}

##########

package SWF::Element::Array::FONTCODETABLE;

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
    $self->FontFlags->unpack($stream);
    my $widecode   = $self->FontFlagsWideCodes;
    my $glyphcount = $self->Length - ($stream->tell - $start);
    $glyphcount >>= 1 if $widecode;
    $self->FontCodeTable->unpack($stream, $glyphcount, $widecode);
}

sub _pack {
    my ($self, $stream)=@_;

    $self->FontID   ->pack($stream);
    $self->FontName ->pack($stream);
    my $substream = $stream->sub_stream;
    $self->FontCodeTable->pack($substream) and ($self->FontFlagsWideCodes(1));

    $self->FontFlags->pack($stream);
    $substream->flush_stream;
}

{
    my $bit;
    for my $f (qw/FontFlagsWideCodes FontFlagsBold FontFlagsItalic FontFlagsANSI FontFlagsUnicode FontFlagsShiftJIS/) {
      SWF::Element::_create_flag_accessor($f, 'FontFlags', $bit++);
    }
}



##########

package SWF::Element::Array::TEXTRECORDARRAY1;

sub pack {
    my ($self, $stream)=@_;
    my ($nglyphmax, $nglyphbits, $nadvancemax, $nadvancebits, $g, $a);

    for my $element (@$self) {
	next unless ($element->isa('SWF::Element::TEXTRECORD::Type0'));
	for my $entry (@{$element->GlyphEntries}) {
	    $g=$entry->TextGlyphIndex;
	    $a=$entry->TextGlyphAdvance;
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
# If upper nibble of $flags is 8, $self is TEXTRECORDn::Type1.
# (It is not enough by checking MSB...(?))
	bless $self, ($flags>>4 == 8) ? ref($self).'::Type1' : 'SWF::Element::TEXTRECORD::Type0';
	$self->unpack($stream, $flags, @_);
    } else {
	bless $self, 'SWF::Element::TEXTRECORD::End';
    }
}

sub pack {
    Carp::croak "Not enough data to pack ".ref($_[0]);
}

use vars '$AUTOLOAD';

sub AUTOLOAD { # auto re-bless with proper sub class by specified accessor.
    my $self = shift;
    my ($name, $class);

    return if $AUTOLOAD =~/::DESTROY$/;

    Carp::croak "No such method: $AUTOLOAD" unless $AUTOLOAD=~/::([A-Z]\w+)$/;
    $name = $1;
    $class = ref($self);
    for my $subclass ('SWF::Element::TEXTRECORD::Type0', "${class}::Type1") {
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

    $self->TextGlyphIndex($stream->get_bits($nglyphbits));
    $self->TextGlyphAdvance($stream->get_sbits($nadvancebits));
}

sub pack {
    my ($self, $stream, $nglyphbits, $nadvancebits)=@_;

    $stream->set_bits($self->TextGlyphIndex->value, $nglyphbits);
    $stream->set_sbits($self->TextGlyphAdvance->value, $nadvancebits);
}

##########

package SWF::Element::TEXTRECORD1::Type1;

sub unpack {
    my ($self, $stream, $flags)=@_;

    $self->TextFont   ->unpack($stream) if ($flags & 8);
    $self->TextColor  ->unpack($stream) if ($flags & 4);
    $self->TextXOffset->unpack($stream) if ($flags & 1);
    $self->TextYOffset->unpack($stream) if ($flags & 2);
    $self->TextHeight ->unpack($stream) if ($flags & 8);
}

sub pack {
    my ($self, $stream)=@_;
    my ($flags)=0x80;

    $flags|=8 if $self->TextFont   ->defined or $self->TextHeight->defined;
    $flags|=4 if $self->TextColor  ->defined;
    $flags|=1 if $self->TextXOffset->defined;
    $flags|=2 if $self->TextYOffset->defined;
    $stream->set_UI8($flags);

    for my $element (qw/TextFont TextColor TextXOffset TextYOffset/) {
	$self->$element->pack($stream) if $self->$element->defined;
    }
    if ($flags & 8) {
	$self->TextHeight->pack($stream);
    }
}


##########

package SWF::Element::Tag::DefineEditText;

sub _unpack {
    my ($self, $stream)=@_;

    for my $element (qw/TextFieldID TextFieldBounds Flags/) {
	$self->$element->unpack($stream);
    }

    if ($self->HasFont) {
	$self->FontID->unpack($stream);
	$self->FontHeight->unpack($stream);
    }
    $self->TextColor->unpack($stream) if $self->HasTextColor;
    $self->MaxLength->unpack($stream) if $self->HasLength;

    if ($self->HasLayout) {
	for my $element (qw/Align LeftMargin RightMargin Indent Leading/) {
	    $self->$element->unpack($stream);
	}
    }
    $self->Variable->unpack($stream);
    $self->InitialText->unpack($stream) if $self->HasInitialText;
}

sub _pack {
    my ($self, $stream)=@_;

    $self->HasFont($self->FontID->defined || $self->FontHeight->defined);
    $self->HasLength($self->MaxLength->defined);
    $self->HasTextColor($self->TextColor->defined);
    $self->HasInitialText($self->InitialText->defined);
    my $fHasLayout;
    for my $element (qw/Align LeftMargin RightMargin Indent Leading/) {
	$fHasLayout = $self->$element->defined;
	last if $fHasLayout;
    }
    $self->HasLayout($fHasLayout);

    for my $element (qw/TextFieldID TextFieldBounds Flags/) {
	$self->$element->pack($stream);
    }

    if ($self->HasFont) {
	$self->FontID->pack($stream);
	$self->FontHeight->pack($stream);
    }
    $self->TextColor->pack($stream) if $self->HasTextColor;
    $self->MaxLength->pack($stream) if $self->HasLength;
    if ($self->HasLayout) {
	for my $element (qw/Align LeftMargin RightMargin Indent Leading/) {
	    $self->$element->pack($stream);
	}
    }
    $self->Variable->pack($stream);
    $self->InitialText->pack($stream) if $self->HasInitialText;
}


{
    my $bit = 0;
    for my $f (qw/HasFont HasLength HasTextColor FlagReadOnly FlagPassword FlagMultiline FlagWordWrap HasInitialText FlagUseOutlines/) {
      SWF::Element::_create_flag_accessor($f, 'Flags', $bit++);
    }
    $bit = 11;
    for my $f (qw/FlagBorder FlagNoSelect HasLayout/) {
      SWF::Element::_create_flag_accessor($f, 'Flags', $bit++);
    }
}

####  Sounds  ####
##########

package SWF::Element::SOUNDINFO;

sub unpack {
    my ($self, $stream)=@_;
    my $flags=$stream->get_UI8;

    $self->SyncFlags($flags>>4);

    my $check = 1;

    for my $element (qw/InPoint OutPoint LoopCount EnvelopeRecords/) {
	if ($flags & $check) {
	    $self->$element->unpack($stream);
	} else {
	    $self->new_element($element);
	}
	$check<<=1;
    }

}

sub pack {
    my ($self, $stream)=@_;
    my $flags=$self->SyncFlags;

    for my $element (qw/EnvelopeRecords LoopCount OutPoint InPoint/) {
	$flags<<=1;
	$flags |=1 if $self->$element->defined;
    }
    $stream->set_UI8($flags);

    my $check = 1;

    for my $element (qw/InPoint OutPoint LoopCount EnvelopeRecords/) {
	$self->$element->pack($stream) if ($flags & $check);
	$check<<=1;
    }
}

##########

package SWF::Element::Tag::DefineSound;

sub _unpack {
    my ($self, $stream)=@_;

    for my $element (qw/SoundID Flags SoundSampleCount/) {
	$self->$element->unpack($stream);
    }
    $self->SoundData->unpack($stream, $self->Length - 7);
}

{
    my $c = \&SWF::Element::_create_flag_accessor;
    $c->('SoundFormat', 'Flags', 4, 4);
    $c->('SoundRate', 'Flags',   2, 2);
    $c->('SoundSize', 'Flags',   1, 1);
    $c->('SoundType', 'Flags',   0, 1);
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
    my $c = \&SWF::Element::_create_flag_accessor;
    $c->('SoundFormat', 'Flags', 4, 4);
    $c->('SoundRate',   'Flags', 2, 2);
    $c->('SoundSize',   'Flags', 1, 1);
    $c->('SoundType',   'Flags', 0, 1);
}

####  Sprites  ####
##########

package SWF::Element::Tag::DefineSprite;

sub _unpack {
    my ($self, $stream)=@_;

    $self->SpriteID->unpack($stream);
    $self->FrameCount->unpack($stream);
    $self->MiniFileStructure->unpack($stream, $self->Length - 4);
}

####  Display List  ####
##########

package SWF::Element::Tag::PlaceObject;

sub _unpack {
    my ($self, $stream)=@_;

    my $start = $stream->tell;

    for my $element (qw/CharacterID Depth Matrix/) {
	$self->$element->unpack($stream);
    }
    if ($stream->tell < $start + $self->Length) {
	$self->ColorTransform->unpack($stream);
    }
}

sub _pack {
    my ($self, $stream)=@_;

    for my $element (qw/CharacterID Depth Matrix/) {
	$self->$element->pack($stream);
    }
    $self->ColorTransform->pack($stream) if $self->ColorTransform->defined;
}

##########

package SWF::Element::Tag::PlaceObject2;

sub _unpack {
    my ($self, $stream)=@_;

    $self->Flags->unpack($stream);
    $self->Depth->unpack($stream);

    my $flags = $self->Flags;

    for my $element (qw/CharacterID Matrix ColorTransform Ratio Name ClipDepth/) {
	my $fa = "Has$element";
	if ($self->$fa) {
	    $self->$element->unpack($stream);
	}
    }
    if ($self->HasEventActions) {
	$self->Unknown->unpack($stream);
	$stream->get_UI16;  # skip eventaction flag
	$self->EventActions->unpack($stream);
    }
}

sub _pack {
    my ($self, $stream)=@_;
    my $tempstream = $stream->sub_stream;

    for my $element (qw/CharacterID Matrix ColorTransform Ratio Name ClipDepth/) {
	my $fa = "Has$element";
	if ($self->$element->defined) {
	    $self->$fa(1);
	    $self->$element->pack($tempstream);
	} else {
	    $self->$fa(0);
	}
    }
    if ($self->EventActions->defined) {
	$self->HasEventActions(1);
	$self->Unknown->pack($tempstream);
	my $f = 0;
	for my $e (@{$self->EventActions}) {
	    $f |= $e->Flags;
	}
	$tempstream->set_UI16($f);
	$self->EventActions->pack($tempstream);
    }
    $self->Flags->pack($stream);
    $self->Depth->pack($stream);
    $tempstream->flush_stream;
}

{
    my $bits = 0;
    for my $element (qw/Move CharacterID Matrix ColorTransform Ratio Name ClipDepth EventActions/) {
      SWF::Element::_create_flag_accessor("Has$element", 'Flags', $bits++);
    }
}

####  Controls  ####
##########

package SWF::Element::Tag::Protect;

sub _unpack {
    my ($self, $stream)=@_;

    $self->Password->unpack($stream, $self->Length);
}

####  Actions  ####
##########

package SWF::Element::ACTIONRECORD;

use vars qw/%actiontagtonum %actionnumtotag/;

%actiontagtonum=(
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
    ActionLessThan                 => 0x0F,
    ActionAnd                      => 0x10,
    ActionOr                       => 0x11,
    ActionNot                      => 0x12,
    ActionStringEquals             => 0x13,
    ActionStringLength             => 0x14,
    ActionSubString                => 0x15,
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
    ActionStartDragMovie           => 0x27,
    ActionStopDragMovie            => 0x28,
    ActionStringLessThan           => 0x29,
    ActionRandom                   => 0x30,
    ActionMBLength                 => 0x31,
    ActionOrd                      => 0x32,
    ActionChr                      => 0x33,
    ActionGetTimer                 => 0x34,
    ActionMBSubString              => 0x35,
    ActionMBOrd                    => 0x36,
    ActionMBChr                    => 0x37,
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
    ActionLessThan2                => 0x48,
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
    ActionBitAnd                   => 0x60,
    ActionBitOr                    => 0x61,
    ActionBitXor                   => 0x62,
    ActionBitLShift                => 0x63,
    ActionBitRShift                => 0x64,
    ActionBitURShift               => 0x65,
    ActionCallFrame                => 0x9e,

);

%actionnumtotag= reverse %actiontagtonum;

sub new {
    my ($class, @headerdata)=@_;
    my %headerdata = ref($headerdata[0]) eq 'ARRAY' ? @{$headerdata[0]} : @headerdata;
    my $self = {};
    my $tag = $headerdata{Tag};

    if (defined $tag and $tag !~/^\d+$/) {
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
	$name = 'ActionUndefined';
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
	my $read = $stream->tell - $start;
#	if ($read < $len) {
#	    $stream->get_string($len-$read);  # Skip the rest of tag data.
#	} elsif ($read > $len) {
#	    Carp::croak ref($self)." unpacked $read bytes in excess of the described ACTIONRECORD length, $len bytes.  The SWF may be collapsed or the module bug??";
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
    my @names = $self->element_names;
    shift @names;   # remove 'Tag'
    for my $key (@names) {
	$self->$key->pack(@_);
    }
}

sub _unpack {
    my $self = shift;

    my @names = $self->element_names;
    shift @names;   # remove 'Tag'
    for my $key (@names) {
	$self->$key->unpack(@_);
    }
}

sub _create_action_tag {
    no strict 'refs';

    my $tagname = shift;
    my $tagno = shift;

    $tagname = "Action$tagname";
    SWF::Element::_create_class("ACTIONRECORD::$tagname", 'ACTIONRECORD', Tag => 'ACTIONTagNumber', @_);

    $actionnumtotag{$tagno} = $tagname;
    $actiontagtonum{$tagname} = $tagno;
}

_create_action_tag('Undefined', 'Undefined', Data       => 'BinData');  
_create_action_tag('GotoFrame',        0x81, Frame      => 'UI16');
_create_action_tag('GetURL',           0x83, 
		   URLString => 'STRING',
		   WinString => 'STRING' );
_create_action_tag('WaitForFrame',     0x8A,
		   Frame     => 'UI16',
		   SkipCount => 'UI8' );
_create_action_tag('SetTarget',        0x8B, TargetName => 'STRING' );
_create_action_tag('GotoLabel',        0x8C, Label      => 'STRING' );
_create_action_tag('WaitForFrame2',    0x8D, SkipCount  => 'UI8' );
_create_action_tag('PushData',         0x96, DataList   => 'Array::ACTIONDATAARRAY' );
_create_action_tag('BranchAlways',     0x99, Offset     => 'UI16');
_create_action_tag('GetURL2',          0x9a, Method     => 'UI8');
_create_action_tag('BranchIfTrue',     0x9d, Offset     => 'UI16');
_create_action_tag('GotoFrame2',       0x9F, Flag       => 'UI8');
_create_action_tag('DefineDictionary', 0x88, 
		   Words   => 'Array::WORDARRAY');
_create_action_tag('DefineFunction',   0x9b, 
		   Name     => 'STRING',
		   Args     => 'Array::ACTIONFUNCARGS',
		   Function => 'Array::ACTIONBLOCK');
_create_action_tag('StoreRegister',    0x87, Register   => 'UI8');
_create_action_tag('With',             0x94, WithBlock  => 'Array::ACTIONBLOCK');

##########

package SWF::Element::ACTIONTagNumber;

sub dumper {
    my ($self, $outputsub)=@_;

    $outputsub||=\&SWF::Element::_default_output;
    my $tag = $SWF::Element::ACTIONRECORD::actionnumtotag{$self->value};
    &$outputsub($tag ? "'$tag'" : $self->value, 0);
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
     = qw/String Property NULL NULL Register Boolean Double Integer Lookup/;

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
    $self->_unpack($stream);
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

    $stream->set_UI8(8);
    $stream->set_UI8($self->value);
}

sub _unpack {
    my ($self, $stream) = @_;

    $self->configure($stream->get_UI8);
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

package SWF::Element::EVENTACTION;

sub unpack {
    my ($self, $stream) = @_;

    $self->Flags->unpack($stream);
    return if $self->Flags == 0;
    $self->Action->unpack($stream);
}

{
    my $bit = 0;
    for my $f (qw/OnLoad EnterFrame Unload MouseMove MouseDown MouseUp KeyDown KeyUp Data/) {
      SWF::Element::_create_flag_accessor($f, 'Flags', $bit++);
    }
}

##########

package SWF::Element::Array::ACTIONBLOCK;

sub unpack {
    my ($self, $stream) = @_;
    my $len = $stream->get_UI16;
    my $start = $stream->tell;

    while ($stream->tell - $start <$len) {
	my $element = $self->new_element;
	$element->unpack($stream);
	push @$self, $element;
    }
}

sub pack {
    my $self = shift;
    my $stream = shift;
    my $substream = $stream->sub_stream;

    $self->_pack($substream, @_);
    $stream->set_UI16($substream->tell);
    $substream->flush_stream;
}
##########

package SWF::Element::Array::ACTIONBLOCK2;

sub unpack {
    my ($self, $stream) = @_;
    my $len = $stream->get_UI32;
    my $start = $stream->tell;

    while ($stream->tell - $start <$len) {
	my $element = $self->new_element;
	$element->unpack($stream);
	push @$self, $element;
    }
}

sub pack {
    my $self = shift;
    my $stream = shift;
    my $substream = $stream->sub_stream;

    $self->_pack($substream, @_);
    $stream->set_UI32($substream->tell);
    $substream->flush_stream;
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


