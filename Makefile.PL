use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'	=> 'SWF::File',
    'VERSION_FROM' => 'Element.pm', # finds $VERSION
    'PREREQ_PM' => {'Data::TemporaryBag' => 0.01},
    'EXE_FILES' => ['dumpswf.plx'],
);

