#!/usr/bin/env perl

use autodie;
use Data::Printer;

open $file, '<', $ARGV[0];

$edid_on = 0;

@edids = [];

while (<$file>) {
   if ($edid_on) {
      $str = substr($_, index($_, ':') + 1);
      next if $str =~ m/\A\s++\Z/;

      @row = ();
      if ($str =~ m/(?:([[:xdigit:]]{2})(?{push @row, $^N})\s*+){16}/) {
         push $edids[$#edids], [ @row ];
      } else {
         $edid_on = 0;
         push @edids, [];
      }
   } else {
      $edid_on = 1
         if $_ =~ m/\QRaw EDID bytes:\E/;
   }
}

$name = 'edid';
$cnt = 0;
foreach $file (@edids) {
   $contents = '';
   foreach $row (@$file) {
      foreach $num (@$row) {
         $contents .= pack "H*", $num
      }
   }
   open $write, '>', "$name.$cnt.bin";
   print $write $contents;
   close $write;
   ++$cnt;
}

