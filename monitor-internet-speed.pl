#!/usr/bin/env perl

use warnings;
use strict;

use POSIX qw/strftime/;

my $speedtest_bin  = 'speedtest-cli';
my @speedtest_args = qw/--simple/;

if (0 != system("which $speedtest_bin > /dev/null 2>&1")) {
   print STDERR "Please, install $speedtest_bin\n"
}

my $output = qx/$speedtest_bin @speedtest_args/;
#my $output = 'Ping: 3.114 ms
#Download: 94.06 Mbit/s
#Upload: 91.55 Mbit/s';

my @output = split '^', $output;
my $ping     = (split '\h+', $output[0])[1];
my $download = (split '\h+', $output[1])[1];
my $upload   = (split '\h+', $output[2])[1];
my $date     = strftime "%d/%m/%y %H:%M:%S", localtime;

print "$date, $ping, $download, $upload\n";

