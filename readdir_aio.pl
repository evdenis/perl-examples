#!/usr/bin/perl

use common::sense;
use feature qw/current_sub/;
use IO::AIO;

my @res;

my $pattern = qr/struct\s++dentry_operations\s++(\w++)\s++=/;

sub __load
{
	my ($path, $data) = $_[0];
	IO::AIO::aio_load $path, $data, sub { push @res, $path if $data =~ $pattern };
}

sub __scandir
{
	my $path = $_[0];
	IO::AIO::aio_scandir($path, 0, sub {
		__scandir($_) foreach map {"$path/$_"} @{$_[0]};
		__load($_)    foreach map {"$path/$_"} @{$_[1]};
	})
}

foreach (@ARGV) {
	__scandir $_
}

IO::AIO::flush;

print map {"$_\n"} @res;

