#!/usr/bin/env perl

use warnings;
use strict;

use File::Which;
use Getopt::Long;
use File::Slurp qw/read_file/;

my %raid;
my %spare;

{
   my @raid;
   my $spare;

   die("mdadm program is required\n")
      unless which 'mdadm';

   GetOptions(
      "raid|r=s"  => \@raid,
      "spare|s=s" => \$spare
   );
   @raid = split(/,/, join(',', @raid));

   {
      my %uniq;
      @raid = grep { -b $_ && !$uniq{$_}++ } @raid;
   }

   die("Raid arrays should be specified with full path.\n")    unless @raid;
   die("Spare disk should be specified with full path.\n")     unless $spare && -b $spare;
   die("OS doesn't support mdadm subsystem.\n") unless -e '/proc/mdstat';

   %raid  = map { substr($_, rindex($_, '/') + 1), $_ } @raid;
   %spare = (substr($spare, rindex($spare, '/') + 1), $spare);

   my %stat = parse_mdstat(read_file('/proc/mdstat', array_ref => 1));

   foreach (keys %raid) {
      die("There is no such raid device $raid{$_}.\n")
         unless exists $stat{$_};

      die("$raid{$_} is inactive\n")
         if $stat{$_}{status} eq 'inactive';
   }

   foreach my $disk (keys %spare) {
      foreach my $md (keys %stat) {
         die("Disk $spare{$disk} is already a part of $md raid.\n")
            if exists $stat{$md}{device}{$disk}
      }
   }
}

#open my $fd, '/proc/mdstat', 'r';
#my $vec = '';
#vec($vec, fileno($fd), 1) = 1;
#while () {
#   if (select(undef, undef, $vec, undef) == -1)  {
#      warn "$!\n"
#   } else {
#      print "YAHOO!\n";
#   }
#}
#close $fd;

sub parse_mdstat
{
   my %mdstat;
   for (@{$_[0]}) {
      #next if m/^(?:Personalities|unused devices)/;
      if (m/^(?<raid>\S++) : (?<raid_status>(?:in)?active)/g) {
         my ($raid, $raid_status) = @+{qw/raid raid_status/};
         $mdstat{$raid}{status} = $raid_status;
         while (m/(?<device>\w++)\[\d++\](?:\((?<flag>[FWSR])\))*+/g) {
            my $device = $+{device};
            my %flags  = map {$_ => 1} $-{flag};
            $mdstat{$raid}{device}{$device} = \%flags;
         }
      }
   }

   %mdstat
}

sub check_raid
{
   my ($raid, %mdstat) = @_;
   my @replace;

   if (exists $mdstat{$raid}) {
      if ($mdstat{$raid}{status} eq 'active') {
         for (keys $mdstat{$raid}{device}) {
            push @replace, $_
               if $mdstat{$raid}{device}{$_}{F}
         }
      } else {
         warn "Raid $raid is inactive\n"
      }
   } else {
      warn "Raid $raid doesn't exist\n"
   }

   @replace
}

sub replace_disks
{
   my ($raid, $failed, $spare) = @_;

   for (@$failed) {
      my $d = pop $spare;
      if (-b $d) {
         qx!mdadm --manage $raid --remove /dev/$_ --add $d!
      }
   }
}

__END__

DOCUMENTATION FOR /proc/mdstat FILE FROM LINUX KERNEL SOURCES

/*
 * We have a system wide 'event count' that is incremented
 * on any 'interesting' event, and readers of /proc/mdstat
 * can use 'poll' or 'select' to find out when the event
 * count increases.
 *
 * Events are:
 *  start array, stop array, error, add device, remove device,
 *  start build, activate spare
 */
static int md_seq_show(struct seq_file *seq, void *v)
{
	struct mddev *mddev = v;
	sector_t sectors;
	struct md_rdev *rdev;

	if (v == (void*)1) {
		struct md_personality *pers;
		seq_printf(seq, "Personalities : ");
		spin_lock(&pers_lock);
		list_for_each_entry(pers, &pers_list, list)
			seq_printf(seq, "[%s] ", pers->name);

		spin_unlock(&pers_lock);
		seq_printf(seq, "\n");
		seq->poll_event = atomic_read(&md_event_count);
		return 0;
	}
	if (v == (void*)2) {
		status_unused(seq);
		return 0;
	}

	if (mddev_lock(mddev) < 0)
		return -EINTR;

	if (mddev->pers || mddev->raid_disks || !list_empty(&mddev->disks)) {
		seq_printf(seq, "%s : %sactive", mdname(mddev),
						mddev->pers ? "" : "in");
		if (mddev->pers) {
			if (mddev->ro==1)
				seq_printf(seq, " (read-only)");
			if (mddev->ro==2)
				seq_printf(seq, " (auto-read-only)");
			seq_printf(seq, " %s", mddev->pers->name);
		}

		sectors = 0;
		rdev_for_each(rdev, mddev) {
			char b[BDEVNAME_SIZE];
			seq_printf(seq, " %s[%d]",
				bdevname(rdev->bdev,b), rdev->desc_nr);
			if (test_bit(WriteMostly, &rdev->flags))
				seq_printf(seq, "(W)");
			if (test_bit(Faulty, &rdev->flags)) {
				seq_printf(seq, "(F)");
				continue;
			}
			if (rdev->raid_disk < 0)
				seq_printf(seq, "(S)"); /* spare */
			if (test_bit(Replacement, &rdev->flags))
				seq_printf(seq, "(R)");
			sectors += rdev->sectors;
		}

		if (!list_empty(&mddev->disks)) {
			if (mddev->pers)
				seq_printf(seq, "\n      %llu blocks",
					   (unsigned long long)
					   mddev->array_sectors / 2);
			else
				seq_printf(seq, "\n      %llu blocks",
					   (unsigned long long)sectors / 2);
		}
		if (mddev->persistent) {
			if (mddev->major_version != 0 ||
			    mddev->minor_version != 90) {
				seq_printf(seq," super %d.%d",
					   mddev->major_version,
					   mddev->minor_version);
			}
		} else if (mddev->external)
			seq_printf(seq, " super external:%s",
				   mddev->metadata_type);
		else
			seq_printf(seq, " super non-persistent");

		if (mddev->pers) {
			mddev->pers->status(seq, mddev);
	 		seq_printf(seq, "\n      ");
			if (mddev->pers->sync_request) {
				if (mddev->curr_resync > 2) {
					status_resync(seq, mddev);
					seq_printf(seq, "\n      ");
				} else if (mddev->curr_resync >= 1)
					seq_printf(seq, "\tresync=DELAYED\n      ");
				else if (mddev->recovery_cp < MaxSector)
					seq_printf(seq, "\tresync=PENDING\n      ");
			}
		} else
			seq_printf(seq, "\n       ");

		bitmap_status(seq, mddev->bitmap);

		seq_printf(seq, "\n");
	}
	mddev_unlock(mddev);
	
	return 0;
}

