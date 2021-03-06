use Test::More;
use Test::Exception;

use strict;
use warnings;

## Issue information
##
## Name: PDLA::Slatec::polyfit ignores incorrect length of weight piddle; passes
##       garbage to slatec polfit
##
## <https://sourceforge.net/p/pdl/bugs/368/>
## <https://github.com/PDLPorters/pdl/issues/48>

use PDLA::LiteF;
use PDLA::Config;

BEGIN {
    unless ($PDLA::Config{WITH_SLATEC} &&
	    eval {
		require PDLA::Slatec;
		PDLA::Slatec->import();
		1;
	    }
	) {
	plan skip_all => "PDLA::Slatec not available";
    }
}

plan tests => 3;

## Set up data
my $ecf = sequence(999);

my $y = $ecf->lags( 0, 9, 111 );
my $x = sequence( 9 );

my $polyfit_orig;
lives_ok { $polyfit_orig = polyfit( $x, $y, $x->ones, 4, .0001 ); } 'polyfit() works when the weight $w matches the length of $x';

subtest 'Passing the weight in a PDLA of length 1' => sub {
	my $polyfit_pdl_len_one;
	lives_ok { $polyfit_pdl_len_one = polyfit( $x, $y, pdl(1), 4, .0001 ); };
	ok( approx($polyfit_orig, $polyfit_pdl_len_one)->all, 'passing a PDLA of length 1 expands to the correct length' );
};

subtest 'Passing the weight in a Perl scalar' => sub {
	my $polyfit_perl_scalar;
	lives_ok { $polyfit_perl_scalar = polyfit( $x, $y, 1, 4, .0001 ) };
	ok( approx($polyfit_orig, $polyfit_perl_scalar)->all, 'passing a Perl scalar expands to the correct length' );
};

done_testing;
