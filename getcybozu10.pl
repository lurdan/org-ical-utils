#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use YAML;
use LWP::UserAgent;
use utf8;
use Encode qw(from_to);
use POSIX qw(mktime strftime);
use Data::Dumper;
my $conf_default = $0;
$conf_default =~ s@/[^/]+$@/config.yaml@;

my %opt = (
   conf => $conf_default,
);
GetOptions( \%opt, 'conf=s', 'help' ) || pod2usage(2);
pod2usage(1) if $opt{help};
my ($cfg) = YAML::LoadFile($opt{conf});
die "Faild to read yaml file: $@" if $@;

my @facility = ();

#my $ua = LWP::UserAgent->new;
my $ua = LWP::UserAgent->new(
                         ssl_opts => {
                             verify_hostname => 0,
                             SSL_verify_mode => 0x00
                            });
my $url = $cfg->{cybozu_url} . "?page=ScheduleUserMonth";
my $req = HTTP::Request->new(POST => $url);
$req->content_type('application/x-www-form-urlencoded');
my $post = '_System=login&_Login=1&LoginMethod=1&_ID='
    . $cfg->{userid} . '&Password=' . $cfg->{password};
$req->content($post);
my $res = $ua->request($req);
die "Failed to access ", $res->status_line , "url=", $url, "\n" unless $res->is_success;
my $content = $res->content;
from_to($content, $cfg->{input_encoding} || 'shiftjis', 'utf8');
$content = Encode::decode('utf-8', $content);
my @event = split(/(<a class="event"[^>]*>)/, $content);
if ($cfg->{output_file}) {
    open(OUTPUT, ">$cfg->{output_file}~") || die;
} else {
    open(OUTPUT, ">&STDOUT");
}
binmode OUTPUT, ":utf8";
select(OUTPUT);
print <<EOF;
BEGIN:VCALENDAR
PRODID:$cfg->{calname}
VERSION:2.0
METHOD:PUBLISH
CALSCALE:GREGORIAN
X-WR-CALNAME:$cfg->{calname}
X-WR-CALDESC:$cfg->{calname}
X-WR-TIMEZONE:$cfg->{time_zone}
EOF
for (@event) {
    if (/^<a class="event"\s+href="ag.cgi\?([^"]+)"\s+title="([^"]+)"/) {
        &event($cfg->{calname}, $ua, $cfg->{cybozu_url}, $post,
               $1, $2, $cfg->{input_encoding});
    }
}
print <<EOF;
BEGIN:VTIMEZONE
TZID:$cfg->{time_zone}
BEGIN:STANDARD
DTSTART:19700101T000000
TZOFFSETFROM:+0900
TZOFFSETTO:+0900
END:STANDARD
END:VTIMEZONE
END:VCALENDAR
EOF
close(OUTPUT);
if ($cfg->{output_file}) {
    rename "$cfg->{output_file}~", $cfg->{output_file};
}

my %cont;
my %recur;

sub event {
    my ($cal, $ua, $url, $post, $query, $title, $encoding) = @_;
    my $eid;
    my $dtstart;
    my $dtend;
    my $description = "";
    my $location;
    my @start;
    my @end;
    $query=~ s/\&amp\;/&/g;

    for (split(/&/, $query)) {
        if (/^BDate=da\.(\d+)\.(\d+)\.(\d+)$/) {
            @start = ($3, $2-1, $1-1900);
        } elsif (/^Date=da\.(\d+)\.(\d+)\.(\d+)$/) {
            @end = ($3, $2-1, $1-1900);
        } elsif (/^sEID=(\d+)$/) {
            $eid = $1;
        }
    }
    if ($title =~ /^\s*(\d+):(\d+)-(\d+):(\d+)&nbsp;/) {
        $title = $';    #';
        $dtstart = strftime "DTSTART:%Y%m%dT%H%M%S", 0, $2, $1, @start;
        $dtend = strftime "DTEND:%Y%m%dT%H%M%S", 0, $4, $3, @end;
    } elsif ($title =~ /^\s*(\d+):(\d+)-(\d+)\/(\d+)&nbsp;/) {
        $title = $';    #';
        $cont{$eid} = strftime "DTSTART:%Y%m%dT%H%M%S", 0, $2, $1, @start;
        return;
    } elsif ($title =~ /^\s*(\d+)\/(\d+)-(\d+):(\d+)&nbsp;/) {
        $title = $';    #';
        $dtend = strftime "DTEND:%Y%m%dT%H%M%S", 0, $4, $3, @end;
        if (defined $cont{$eid}) {
            $dtstart = $cont{$eid};
            delete $cont{$eid};
        } else {
            $dtstart = strftime "DTSTART;VALUE=DATE:%Y%m%d", 0, 0, 0, @start;
        }
    } elsif ($title =~ /^\s*(\d+)\/(\d+)-(\d+)\/(\d+)&nbsp;/) {
        $title = $';    #';
        if (defined $cont{$eid}) {
            return;
        }
        $dtstart = strftime "DTSTART;VALUE=DATE:%Y%m%d", 0, 0, 0, @start;
        $dtend = strftime "DTEND;VALUE=DATE:%Y%m%d", 0, 0, 0, @end;
    } else {
        $dtstart = strftime "DTSTART;VALUE=DATE:%Y%m%d", 0, 0, 0, @start;
        $dtend = strftime "DTEND;VALUE=DATE:%Y%m%d", 0, 0, 0, @end;
    }
    my $diff = mktime(0, 0, 0, @start) + 86400 - time();
    if (0 <= $diff && $diff < 604800) {
        my $req = HTTP::Request->new(POST => $url . '?' . $query);
        $req->content_type('application/x-www-form-urlencoded');
        $req->content($post);
        my $res = $ua->request($req);
        if ($res->is_success) {
            my $i = index $res->content, '<a name="ScheduleData">';
            if ($i > 0) {
                my $content = substr($res->content, $i);
                from_to($content, $encoding, 'utf8');
                $content = Encode::decode('utf8', $content);
                for (split(/<th align="left"[^>]*>/, $content)) {
                    if (/^メモ<\/th>/) {
                        my $i = index($_, '<td>') + 4;
                        my $j = index($_, '</td>');
                        $description = substr($_, $i, $j-$i);
                        $description =~ s/[\r\n]+\s*//g;
                        $description =~ s/<br>/\\n\n /g;
                        $description =~ s/<[^>]+>//g;
                    }
                    if (/^設備<\/th>/) {
                        my $i = index($_, '<td>') + 4;
                        my $j = index($_, '</td>');
                        my $facility = substr($_, $i, $j-$i);
                        foreach my $f (@facility) {
                            if (index($facility, $f) >= 0) {
                                $location = $f;
                                last;
                            }
                        }
                    }
                }
            }
        }
    }
    my $uid = "$cal-$eid";
    if (defined $recur{$eid}) {
        $uid .= "-" . $recur{$eid};
        $recur{$eid}++;
    } else {
        $recur{$eid} = 1;
    }
    print <<EOF;
BEGIN:VEVENT
UID:$uid
DESCRIPTION:$description
$dtstart
$dtend
SUMMARY:$title
EOF
    print "LOCATION:$location\n" if defined $location;
    print <<EOF;
END:VEVENT
EOF
}

1;
__END__

=head1 NAME

cybozu10_ical - Convert Cybozu Office8 calendar into iCalendar format

=head1 SYNOPSIS

  % cybozu10_ical
  % cybozu10_ical --conf /path/to/config.yaml

=head1 DESCRIPTION

C<cybozu10_ical> is a command line application that fetches calendar
items from Cybozu Office 8, and converts them into an
iCalendar file.