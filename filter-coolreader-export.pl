#!/usr/bin/env perl

use common::sense;
use File::Slurp qw/read_file write_file/;

sub filter ($)
{
   $_[0] =~ s/\r(?=\n)//g;
   $_[0] =~ s/\A(.*+\n){6}//m;
   $_[0] =~ s/^##.*+\n//gm;
   $_[0] =~ s/^<< //gm;
   $_[0] =~ s/^>>.*+\n//gm;

   $_[0] =~ s/(\A\s++)|(\s++\Z)//sg;

   $_[0]
}

foreach (@ARGV) {
   write_file($_, filter read_file($_))
}

