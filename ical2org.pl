#!/usr/bin/env perl
use warnings;
use strict;

use Data::ICal;
use Data::Dumper;
use DateTime::Format::ICal;

use Getopt::Long;
my $category = 'ical';

# Only sync events newer than this many weeks in the past.
# Set to 0 to sync all past events.
my $syncweeksback = 2;

GetOptions(
    'category|c=s' => \$category
);

my $cal = Data::ICal->new(data => join '', <STDIN>);

#print Dumper $cal;
my %gprops = %{ $cal->properties };

print "#+TITLE: ical entries\n";
print "#+AUTHOR: ".$gprops{'x-wr-calname'}[0]->decoded_value."\n";
print "#+EMAIL: \n";
print "#+DESCRIPTION: Converted using ical2org.pl\n";
print "#+CATEGORY: $category\n";
print "#+STARTUP: overview\n";
print "\n";

print "* COMMENT original iCal properties\n";
#print Dumper \%gprops;
print "Timezone: ", $gprops{'x-wr-timezone'}[0]->value, "\n";

foreach my $prop (values %gprops) {
    foreach my $p (@{ $prop }) {
	print $p->key, ':', $p->value, "\n";
    }
}

foreach my $entry (@{ $cal->entries }) {
    next if not $entry->isa('Data::ICal::Entry::Event');
    #print 'Entry: ', Dumper $entry;

    my %props = %{ $entry->properties };

    # skip entries with no start or end time
    next if (not $props{dtstart}[0] or not $props{dtend}[0]);

    my $dtstart = DateTime::Format::ICal->parse_datetime($props{dtstart}[0]->value);
    my $dtend   = DateTime::Format::ICal->parse_datetime($props{dtend}[0]->value);
    # Perhaps only sync some weeks back
    next if ($syncweeksback != 0
	     and $dtend < DateTime->now->subtract(weeks => $syncweeksback)
	     and !defined $props{rrule});

    my $duration = $dtend->subtract_datetime($dtstart);

    if (defined $props{rrule}) {
	#print "  REPEATABLE\n";
	# Bad: There may be multiple rrules but I'm ignoring them
	my $set = DateTime::Format::ICal->parse_recurrence(
	    recurrence => $props{rrule}[0]->value,
	    dtstart    => $dtstart,
	    dtend      => DateTime->now->add(weeks => 1),
	);

	my $itr = $set->iterator;
	while (my $dt = $itr->next) {
	    $dt->set_time_zone(
		$props{dtstart}[0]->parameters->{'TZID'} ||
		$gprops{'x-wr-timezone'}[0]->value
		);

	    my $end = $dt->clone->add_duration($duration);
	    next if ( $end < DateTime->now->subtract(weeks => $syncweeksback) );
	    
	    print "* ".$props{summary}[0]->decoded_value."\n";
	    print '  ', org_date_range($dt, $end), "\n";
	    #print $dt, "\n";
	    print  "  :PROPERTIES:\n";
	    printf "  :ID: %s\n", $props{uid}[0]->value;

	    if (defined $props{location}) {
		printf "  :LOCATION: %s\n", $props{location}[0]->value;
	    }

	    if (defined $props{status}) {
		printf "  :STATUS: %s\n", $props{status}[0]->value;
	    }

	    print "  :END:\n";

	    if ($props{description}) {
		print "\n", $props{description}[0]->decoded_value, "\n";
	    }
	}
    }
    else {

	print "* ".$props{summary}[0]->decoded_value."\n";

	my $tz = $gprops{'x-wr-timezone'}[0]->value;
	$dtstart->set_time_zone($props{dtstart}[0]->parameters->{'TZID'} || $tz);
	$dtend->set_time_zone($props{dtend}[0]->parameters->{'TZID'} || $tz);

	print '  ', org_date_range($dtstart, $dtend), "\n";

	print  "  :PROPERTIES:\n";
	printf "  :ID: %s\n", $props{uid}[0]->value;

	if (defined $props{location}) {
	    printf "  :LOCATION: %s\n", $props{location}[0]->value;
	}

	if (defined $props{status}) {
	    printf "  :STATUS: %s\n", $props{status}[0]->value;
	}

	print "  :END:\n";

	if ($props{description}) {
	    print "\n", $props{description}[0]->decoded_value, "\n";
	}

    }

#    print Dumper \%props;
}

sub org_date_range {
    my $start = shift;
    my $end = shift;

    my $str = sprintf('<%04d-%02d-%02d %s %02d:%02d>',
	   $start->year,
	   $start->month,
	   $start->day,
	   $start->day_abbr,
	   $start->hour,
	   $start->minute
       );
    $str .= '--';
    $str .= sprintf('<%04d-%02d-%02d %s %02d:%02d>',
	   $end->year,
	   $end->month,
	   $end->day,
	   $end->day_abbr,
	   $end->hour,
	   $end->minute
       );

    return $str;
}
