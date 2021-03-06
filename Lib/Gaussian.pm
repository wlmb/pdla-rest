=head1 NAME

PDLA::Gaussian -- Gaussian distributions.

=head1 SYNOPSIS

 $x = new PDLA::Gaussian([3],[5]);
 $x->set_covariance(...)

=head1 DESCRIPTION

This package provides a set of standard routines to handle
sets gaussian distributions.

A new set of gaussians is initialized by

 $x = new PDLA::Gaussian(xdims,gdims);

Where I<xdims> is a reference to an array containing the
dimensions in the space the gaussian
is in and I<gdimslist> is a reference to an array containing
the dimensionality of the gaussian space. For example, after

 $x = new PDLA::Gaussian([2],[3,4]);
 $y = new PDLA::Gaussian([],[]);

The variable C<$x> contains set of 12 (=C<3*4>) 2-Dimensional gaussians
and C<$y> is the simplest form: one 1D gaussian.
Currently, I<xdims> may containe either zero or one dimensions
due to limitations of L<PDLA::PP|PDLA::PP>.

To set the distribution parameters, you can use the routines

 $x->set_covariance($cv);     # covariance matrices
 $x->set_icovariance($icv);   # inverse covariance matrices
 $x->set_mu($mu);	      # centers

The dimensions of C<$cv> and C<$icv> must be C<(@xdims,@xdims,@gdims)> and
the dimensions of C<$mu> must be C<(@xdims,@gdims)>.

Alternatively you can use the routines

 $cv = $x->get_covariance();  # cv = reference to covariance matrix
 ...			      # Fuzz around with cv
 $x->upd_covariance();	      # update

and similarly for C<icovariance> (inverse covariance). The last sub call
is important to update the other parts of the object.

To get a string representation of the gaussians (most useful for
debugging) use the routine

 $string = $x->asstr();

It is possible to calculate the probability or logarithm of probability
of each of the distributions at some points.

 $x->calc_value($x,$p);
 $x->calc_lnvalue($x,$p);

Here, C<$x> must have dimensions C<(ndims,...)> and C<$p> must have dimensions
C<(gdimslist, ...)> where the elipsis represents the same dimensions in
both variables. It is usually advisable to work with the logarithms
of probabilities to avoid numerical problems.

It is possible to generate the parameters for the gaussians from data.
The function

 $x->fromweighteddata($data,$wt,$small_covariance);

where C<$data> is of dimensions C<(ndims,npoints)> and C<$wt> is of dimensions
C<(npoints,gdimslist)>, analyzes the data statistically and gives
a corresponding gaussian distribution. The parameter C<$small_covariance>
is the smallest allowed covariance in any direction: if one or more of
the eigenvalues of the covariance matrix are smaller than this, they
are automatically set to C<$small_covariance> to avoid singularities.

=head1 BUGS

Some of the routines (upd_covariance in particular, but likely others)
cause segmentation faults and stack traces with current versions of
PDLA, which renders this module essentially unusable.  That is why this
module is no longer included in the main PDLA distribution (but is
available in the CVS version). Fixes are always welcome, so that we
may re-include it.

Stupid interface.

Limitation to 1 x-dimensions is questionable (although
it's hard to imagine a case when more is needed).
Note that this does not mean that you can only have 1-dimensional
gaussians. It just means that if you want to have a 6-dimensional
gaussian, your xs must be structured like (6) and not (2,3).
So clumping the dimensions should make things workable.

Also, it limits you so that even if you have one variable, you need
to have the '1' dimensions explicitly everywhere.

Singular distributions are not handled. This should use SVD
and be able to handle both infinitely narrow and wide dimensions,
preferably so that infinitely narrow dimensions can be queried
like C<$x->relations()> or something like that.

The routines should, if the user requests for it, check all the dimensions
of the given arguments for reasonability.

=head1 AUTHOR

Copyright (C) 1996 Tuomas J. Lukka (lukka@fas.harvard.edu)
All rights reserved. There is no warranty. You are allowed
to redistribute this software / documentation under certain
conditions. For details, see the file COPYING in the PDLA
distribution. If this file is separated from the PDLA distribution,
the copyright notice should be included in the file.

=cut

package PDLA::Gaussian;
use PDLA::Core '';
use PDLA::Slatec;
use PDLA::Primitive;
use PDLA::Slices;
# use PDLA::Lib::LLSQRout;

sub new {
	my($type,$ndims,$nfuncs) = @_;
	if($#{$ndims} != 0) {
		barf("PDLA::Gaussian can only have one dimension dimensionality\n");
	}
	my $ndims1 = ($#{$ndims==0} ? $ndims : [1]);
	bless {
		Mu => (PDLA->zeroes (@$ndims1,@$nfuncs)->double),
		ICV => (PDLA->zeroes (@$ndims1,@$ndims1,@$nfuncs)->double),
		CV => (PDLA->zeroes (@$ndims1,@$ndims1,@$nfuncs)->double),
		lnPrefactor=> (PDLA->zeroes(@$nfuncs)->double),
		EigVec => (PDLA->zeroes (@$ndims1,@$ndims1,@$nfuncs)->double),
		EigVal => (PDLA->zeroes (@$ndims1,@$nfuncs)->double),
		NDims => $ndims,
		NFuncs => $nfuncs,
	},$type;
}

sub asstr {
	my($this) = @_;
	return join '',
	  "Gaussian: NDims = $this->{NDims}[0], NFuncs = ",
	  	(join ',',@{$this->{NFuncs}}),
	  "\nCoVar: $this->{CV}, ICoVar: $this->{ICV},
pref: $this->{lnPrefactor}, Eigvec: $this->{EigVec}, eigval: $this->{EigVal}\nMu: $this->{Mu}
";
}

sub set_covariance {
	my($this,$cv) = @_;
	PDLA::Basic::similar_assign($cv,$this->{CV});
	$this->upd_covariance();
}

sub set_icovariance {
	my($this,$cv) = @_;
	PDLA::Basic::similar_assign($cv,$this->{ICV});
	$this->upd_icovariance();
}

sub set_mu {
	my($this,$mu) = @_;
	PDLA::Basic::similar_assign($mu,$this->{Mu});
}

sub get_covariance { my($this) = @_; return $this->{CV}; }
sub get_icovariance { my($this) = @_; return $this->{ICV}; }
sub get_mu { my($this) = @_; return $this->{Mu}; }

sub upd_covariance {
	my($this)=@_;
	$this->_eigs($this->{CV});
	$this->_pref();
	$this->_otrans(1);
}

sub upd_icovariance {
	my($this) = @_;
	$this->_eigs($this->{ICV});
	$this->{EigVal} **= -1;
	$this->_pref();
	$this->_otrans(0);
}

# This internal routine calculates the eigenvalues and vectors of
# the given matrix which may be either a covariance or inverse covariance
# matrix.
sub _eigs {
	my($this,$mat) = @_;
	my $tmpvec = $this->{EigVec}->float;
	my $fvone = (PDLA->zeroes(@{$this->{NDims}}))->float;
	my $fvtwo = (PDLA->zeroes(@{$this->{NDims}}))->float;
	my $ierr = (PDLA->zeroes(@{$this->{NFuncs}}))->long;
	my $tmp = $mat->float; # Copy, since is destroyed.
	my $tmpval = $this->{EigVal}->float;

	rs($tmp, $tmpval, $tmpvec, $ierr, $fvone, $fvtwo, 1);

	$this->{EigVal} = $tmpval->double;
	$this->{EigVec} = $tmpvec->double;
}

# This takes the eigenvalues and the eigenmatrix and makes the
# matrix we did not have
sub _otrans {
	my($this,$inv) = @_;
	my $tmp = PDLA->null;
	$tmp .= $this->{EigVec}; my $foo;
	if($inv) {
		($foo = $tmp->thread(0)) /= $this->{EigVal};
	} else {
		($foo = $tmp->thread(0)) *= $this->{EigVal};
	}
	PDLA::Primitive::inner($this->{EigVec}->thread(0,-1),$tmp->thread(-1,0),
		$this->{($inv?"ICV":"CV")}->thread(0,1));
}

# Calculate prefactor.
sub _pref {
	my($this) = @_;
	print "IPREF\n";
	my $tmp = (log($this->{EigVal}));
	$tmp->sumover($this->{lnPrefactor});
	$this->{lnPrefactor} *= -0.5;
	$this->{lnPrefactor} -= 0.5 * $this->{NDims}[0] * log (2*3.14);
	print "OPREF\n";
}

# (nvars) => (@xdims)
sub calc_value ($$$) {
	my($this,$x,$p) = @_;
	$this->calc_lnvalue($x,$p);
	exp(inplace $p);
}

# (nvars,foo) => (xdims,foo)
sub calc_lnvalue ($$$) {
	my($this,$xorig,$p) = @_;
	my $x = $xorig;
	my $muxed = (PDLA->zeroes(@{$this->{NDims}},@{$p->{Dims}}))->double;

#	print "MUXED1: $muxed\n";

	my $arg11 = $this->{Mu}->thread(1..$#{$this->{NFuncs}}+1);
	my $arg12 = $muxed->thread(1..$#{$this->{NFuncs}}+1);

#	my_biop1($x,$this->{Mu}->thread(1..$#{$this->{NFuncs}}+1),
#		$muxed->thread(1..$#{$this->{NFuncs}}+1),"-");

	print "TOINNER1\n";
	PDLA::Ops::my_biop1($x, $arg11, $arg12, "-");

	print "TOINNER2\n";
#	print "MUXED: $muxed\n";
	print "TOINNER2\n";
	my $arg1 = ($muxed->thread(1..$#{$this->{NFuncs}}+1));
	print "TOINNER3\n";
	my $arg2 = ($this->{ICV}->thread(2..$#{$this->{ICV}{Dims}}));
	print "TOINNER4\n";
	my $arg3 = ($p->thread(0..$#{$this->{NFuncs}}));
	print "TOINNER5\n";
#	inner2(($muxed->thread(1..$#{$this->{NFuncs}}+1))
#		,($this->{ICV}->thread(2..$#{$this->{ICV}{Dims}})),
#		($muxed->thread(1..$#{$this->{NFuncs}}+1))
#		   ($p->thread(0..$#{$this->{NFuncs}})));
	PDLA::Primitive::inner2($arg1,$arg2,$arg1,$arg3);
	print "FROMINNER2\n";
	$p /= -2;
	print "TON3\n";
	$p += $this->{lnPrefactor};
	print "OUTON3\n";
}

# Again, (nvars,newndims,foo) => (newndims,newndims,@xdims,foo)
sub calc_lccovariance {
	my($this,$vec,$var) = @_;
	my $tmp = PDLA->null;
	inner2t($vec->xchg(0,1)->thread(3..$#{$this->{NFuncs}}+3),
	    	 $this->{CV}->thread(2..$#{$this->{NFuncs}}+2),
		$vec->thread(3..$#{$this->{NFuncs}}+3),
		$tmp,
		$var->thread(3..$#{$this->{NFuncs}}+3));
}

# (nvars,newndims,foo) => (newndims,@gdims,foo)
# (nvars,@xdims)->thread) -> (@gdims)
sub calc_lcavg {
	my($this,$vec,$var) = @_;
#	kill INT,$$;
	PDLA::Primitive::inner(
		$vec->thread(3..$#{$this->{NFuncs}}+3),
		$this->{Mu}->thread(1..$#{$this->{Mu}{Dims}}),
		$var->thread(2..$#{$this->{NFuncs}}+2));
}

# Calculate the average of a second-degree term x^T M x
# (nvars,nvars[,npolys]) => ([npolys],@gdims)
sub calc_qavg {
	my($this,$terms,$res) = @_;
# The way to do this is to first transform the polynomial into
# our coordinate system and then take the diagonal terms,
# which are then multiplied by the covariance eigenvalues.
	my @cids = 2..$#{$terms->{Dims}};
	my @cdims = @{$terms->{Dims}}[2..$#{$terms->{Dims}}];
	my $tmp1 = PDLA->zeroes(@{$this->{NDims}},@{$this->{NDims}});
	my $tmp2 = PDLA->zeroes(@{$this->{NDims}},@{$this->{NDims}},
		@cdims, @{$this->{NFuncs}});
	PDLA::Primitive::inner2t(
			$this->{EigVec}->xchg(0,1),
			$terms->thread(@cids),
			$this->{EigVec},
			$tmp1,
			$tmp2->thread(@cids)
	);
	$tmp2->flush();
# Now, pick the diagonal of $tmp2, threading over the unwanted dims..
	my $diag = $tmp2->thread(@cids)->diagonal(0);
# And multiply it by the covariance eigenvalues.
	$diag *= $this->{EigVal};
# Return the sum
	$diag = $diag->unthread(1);
	$diag->sumover($res);
}

# [(nvars,nvars[,npolys]), (nvars[,npolys])] =>
# ([npolys,]@gdims)
sub calc_poly2 {
	my($this,$coeffs,$res) = @_;
}

#
sub cross_entropy {
}

# (nvars,newndims,foo) => (other gaussian) (newndims,@xdims,foo)
sub to_lcombgaussians {
	my($this,$vec,$gauss) = @_;
	$this->calc_lccovariance($vec,$gauss->{CV});
	$this->calc_lcavg($vec,$gauss->{Mu});
	$gauss->upd_covariance();
}

# (nvars,ndata), (xdims,ndata)
sub fromweighteddata {
	my($this,$data,$wt) = @_;
}

sub ph {my($x) = @_; for (keys %$x) {next if !ref $x->{$_} or
	(ref $x->{$_}) eq "ARRAY";
   print "$_ :",$x->{$_},"\n	Dims:[",
	(join ',',@{$x->{$_}{Dims}}),"]\n";}}

1;



