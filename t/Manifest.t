#!/usr/bin/perl -w

BEGIN {
    if( $ENV{PERL_CORE} ) {
        chdir 't' if -d 't';
        unshift @INC, '../lib';
    }
    else {
        unshift @INC, 't/lib';
    }
}
chdir 't';

use strict;

# these files help the test run
use Test::More tests => 32;
use Cwd;

# these files are needed for the module itself
use File::Spec;
use File::Path;
use Carp::Heavy;

# keep track of everything added so it can all be deleted
my %files;
sub add_file {
	my ($file, $data) = @_;
	$data ||= 'foo';
	open( my $T, '>', $file) or return;
	print $T $data;
	++$files{$file};
}

sub read_manifest {
	open( my $M, 'MANIFEST' ) or return;
	chomp( my @files = <$M> );
	return @files;
}

sub catch_warning {
	my $warn;
	local $SIG{__WARN__} = sub { $warn .= $_[0] };
	return join('', $_[0]->() ), $warn;
}

sub remove_dir {
	ok( rmdir( $_ ), "remove $_ directory" ) for @_;
}

# use module, import functions
BEGIN { 
    use_ok( 'ExtUtils::Manifest', 
            qw( mkmanifest manicheck filecheck fullcheck 
                maniread manicopy skipcheck ) ); 
}

my $cwd = Cwd::getcwd();

# Just in case any old files were lying around.
rmtree('mantest');

ok( mkdir( 'mantest', 0777 ), 'make mantest directory' );
ok( chdir( 'mantest' ), 'chdir() to mantest' );
ok( add_file('foo'), 'add a temporary file' );

# there shouldn't be a MANIFEST there
my ($res, $warn) = catch_warning( \&mkmanifest ); 
# Canonize the order.
$warn = join("", map { "$_|" } 
                 sort { lc($a) cmp lc($b) } split /\r?\n/, $warn);
is( $warn, "Added to MANIFEST: foo|Added to MANIFEST: MANIFEST|",
    "mkmanifest() displayed its additions" );

# and now you see it
ok( -e 'MANIFEST', 'create MANIFEST file' );

my @list = read_manifest();
is( @list, 2, 'check files in MANIFEST' );
ok( ! ExtUtils::Manifest::filecheck(), 'no additional files in directory' );

# after adding bar, the MANIFEST is out of date
ok( add_file( 'bar' ), 'add another file' );
ok( ! manicheck(), 'MANIFEST now out of sync' );

# it reports that bar has been added and throws a warning
($res, $warn) = catch_warning( \&filecheck );

like( $warn, qr/^Not in MANIFEST: bar/, 'warning that bar has been added' );
is( $res, 'bar', 'bar reported as new' );

# now quiet the warning that bar was added and test again
($res, $warn) = do { local $ExtUtils::Manifest::Quiet = 1; 
                     catch_warning( \&skipcheck ) 
                };
cmp_ok( $warn, 'eq', '', 'disabled warnings' );

# add a skip file with a rule to skip itself (and the nonexistent glob '*baz*')
add_file( 'MANIFEST.SKIP', "baz\n.SKIP" );

# this'll skip the new file
($res, $warn) = catch_warning( \&skipcheck );
like( $warn, qr/^Skipping MANIFEST\.SKIP/i, 'got skipping warning' );

# I'm not sure why this should be... shouldn't $missing be the only one?
my ($found, $missing );
catch_warning( sub {
	( $found, $missing ) = skipcheck()
});

# nothing new should be found, bar should be skipped
is( @$found, 0, 'no output here' );
is( join( ' ', @$missing ), 'bar', 'listed skipped files' );

{
	local $ExtUtils::Manifest::Quiet = 1;
	is( join(' ', filecheck() ), 'bar', 'listing skipped with filecheck()' );
}

# add a subdirectory and a file there that should be found
ok( mkdir( 'moretest', 0777 ), 'created moretest directory' );
add_file( File::Spec->catfile('moretest', 'quux'), 'quux' );
ok( exists( ExtUtils::Manifest::manifind()->{'moretest/quux'} ), 
                                        "manifind found moretest/quux" );

# only MANIFEST and foo are in the manifest
my $files = maniread();
is( keys %$files, 2, 'two files found' );
is( join(' ', sort { lc($a) cmp lc($b) } keys %$files), 'foo MANIFEST', 
                                        'both files found' );

# poison the manifest, and add a comment that should be reported
add_file( 'MANIFEST', 'none #none' );
is( ExtUtils::Manifest::maniread()->{none}, '#none', 
                                        'maniread found comment' );

ok( mkdir( 'copy', 0777 ), 'made copy directory' );

$files = maniread();
eval { (undef, $warn) = catch_warning( sub {
		manicopy( $files, 'copy', 'cp' ) }) 
};
like( $@, qr/^Can't read none: /, 'carped about none' );

# a newline comes through, so get rid of it
chomp($warn);

# the copy should have given one warning and one error
like($warn, qr/^Skipping MANIFEST.SKIP/i, 'warned about MANIFEST.SKIP' );

# tell ExtUtils::Manifest to use a different file
{
	local $ExtUtils::Manifest::MANIFEST = 'albatross'; 
	($res, $warn) = catch_warning( \&mkmanifest );
	like( $warn, qr/Added to albatross: /, 'using a new manifest file' );
	
	# add the new file to the list of files to be deleted
	$files{'albatross'}++;
}


# Make sure MANIFEST.SKIP is using complete relative paths
add_file( 'MANIFEST.SKIP' => "^moretest/q\n" );

# This'll skip moretest/quux
($res, $warn) = catch_warning( \&skipcheck );
like( $warn, qr{^Skipping moretest/quux}i, 'got skipping warning again' );


END {
	# the args are evaluated in scalar context
	is( unlink( keys %files ), keys %files, 'remove all added files' );
	remove_dir( 'moretest', 'copy' );

	# now get rid of the parent directory
	ok( chdir( $cwd ), 'return to parent directory' );
	unlink('mantest/MANIFEST');
	remove_dir( 'mantest' );
}

