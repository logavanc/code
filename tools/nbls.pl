#!/usr/bin/env perl
# nbls: tool for listing all NetBIOS names out there
use warnings;
use strict;
use Data::Dumper;
use Socket;

my %SUFFIX = (
	workstation		=> 0x00,
	browser			=> 0x01,
	messenger		=> 0x03,
	ras_server		=> 0x06,
	domain_master		=> 0x1b,
	domain_controller	=> 0x1c,
	local_master		=> 0x1d,
	browser_elections	=> 0x1e,
	netdde			=> 0x1f,
	server			=> 0x20,
	ras_client		=> 0x21,
	exchange_interchange	=> 0x22,
	exchange_store		=> 0x23,
	exchange_directory	=> 0x24,
	modemsharing_server	=> 0x30,
	modemsharing_client	=> 0x21,
	smsclient_control	=> 0x43,
	smsadmin_control	=> 0x44,
	smsclient_chat		=> 0x45,
	smsclient_transfer	=> 0x46,
	#pathworks_tcpip		=> [0x4c, 0x52],
	exchange_imc		=> 0x6a,
	exchange_mta		=> 0x87,	# seems to be only IPX/NetBEUI
	netmon_agent		=> 0xbe,
	netmon_app		=> 0xbf,
);

my %NSUFFIX = (
	0x00 => "Workstation",
	0x01 => "Browser",
	0x03 => "Messenger",
	0x06 => "RAS Server",
	0x1b => "Domain Master Browser",
	0x1c => "Domain Controller",
	0x1f => "NetDDE",
	0x1d => "Local Master Browser",
	0x1e => "Browser Service Elections",
	0x20 => "File Server",
	0x21 => "RAS Client",
	0x22 => "Microsoft Exchange Interchange",
	0x23 => "Microsoft Exchange Store",
	0x24 => "Microsoft Exchange Directory",
	#0x2b => "Lotus Notes Server Service",
	#0x2f => "Lotus Notes",
	0x30 => "Modem Sharing Server",
	0x31 => "Modem Sharing Client",
	#0x33 => "Lotus Notes",
	0x43 => "SMS Clients Remote Control",
	0x44 => "SMS Administrators Remote Control Tool",
	0x45 => "SMS Clients Remote Chat",
	0x46 => "SMS Clients Remote Transfer",
	0x4c => "DEC Pathworks TCP/IP service on Windows NT",
	0x52 => "DEC Pathworks TCP/IP service on Windows NT",
	0x6a => "Microsoft Exchange IMC",
	0x87 => "Microsoft Exchange MTA",
	0xbe => "Network Monitor Agent",
	0xbf => "Network Monitor Application",
);

my %RSUFFIX = map {$SUFFIX{$_} => $_} keys %SUFFIX;

sub ip2host {
	my $addr = inet_aton(shift);
	my $name = gethostbyaddr($addr, AF_INET) // "";
	$name = lc $name;
	$name =~ s/\.home$//;
	return $name;
}

sub lookup {
	my $name = shift;
	my $suffix = shift // 0x00;
	$name = sprintf "%s#%02x", $name, $suffix;
	nmblookup($name);
}

sub nmblookup {
	my (@args) = @_;
	my @results;
	print STDERR "(nmblookup @args)\n";
	open my $fd, "-|", ("nmblookup", @args);
	while (<$fd>) {
		if (my @r = /^(\S+) (\S+)<([0-9a-f]{2})>$/i) {
			my ($addr, $name, $suffix) = @r;
			$name =~ s/[\x01-\x1F]/./g;
			push @results, {addr => $addr, name => uc $name, suffix => hex $suffix};
		}
	}
	close $fd;
	return wantarray ? @results : $results[0];
}

sub nmbstat {
	my @results;
	my $addr;
	print STDERR "(nmbstat @_)\n";
	open my $fd, "-|", ("nmblookup", "-S", @_);
	while (<$fd>) {
		my @r;
		if (@r = /^Looking up status of (\S+)$/) {
			$addr = $r[0];
		}
		elsif (@r = /^\t (\S+) \s+ <([0-9a-f]{2})> \s . \s (?:<(\w+)>|\s+)/ix) {
			my ($name, $suffix, $type, $flag) = @r;
			#if ($name =~ /^[ && $suffix == $SUFFIX{browser}) {
			#	$name = "__MSBROWSE__";
			#}
			push @results, {name => uc $name, suffix => hex $suffix,
				addr => $addr, type => lc ($type // "unique")};
		}
	}
	close $fd;
	return @results;
}

my @network;
my @workgroups;
my @next_wgs;

# Discover the network's master browser
my $master = nmblookup("-M", "--", "-")
	or die "Unable to find master browser.\n";
print STDERR "(master is $master->{addr})\n";

# Get all workgroups in master.
for my $entry (nmbstat("-A", $master->{addr})) {
	next if grep {$_->{name} eq $entry->{name}
		&& $_->{suffix} eq $entry->{suffix}
		&& $_->{addr} eq $entry->{addr}} @network;
	push @network, $entry;

	if ($entry->{suffix} == $SUFFIX{workstation}) {
		if ($entry->{type} eq "group") {
			my $wgname = $entry->{name};
			print STDERR "(master has group $wgname)\n";
			next if $wgname ~~ @next_wgs;
			push @next_wgs, $wgname;
		}
	}
}

# Loop over workgroups, call NBSTAT on each found host
# Repeat for any new workgroups discovered
while (@next_wgs) {
	my @more_wgs = @next_wgs;
	@next_wgs = ();
	for my $wg (@more_wgs) {
		next if $wg ~~ @workgroups;
		push @workgroups, $wg;
		for my $entry (nmbstat($wg)) {
			next if grep {$_->{name} eq $entry->{name}
				&& $_->{suffix} eq $entry->{suffix}
				&& $_->{addr} eq $entry->{addr}} @network;
			push @network, $entry;

			if ($entry->{suffix} == $SUFFIX{workstation}) {
				if ($entry->{type} eq "group") {
					my $wgname = $entry->{name};
					next if $wgname ~~ @workgroups;
					print STDERR "($entry->{addr} has group $wgname)\n";
					next if $wgname ~~ @next_wgs;
					push @next_wgs, $wgname;
				}
			}
		}
	}
}

# Push master browser in case none of above lookups returned it
# Doing it here because only NBSTAT lookups return the correct
# group bit, when using 'nmblookup'.
push @network, $master
	unless grep {$_->{name} eq $master->{name}
		&& $_->{suffix} eq $master->{suffix}
		&& $_->{addr} eq $master->{addr}} @network;

# Look up DNS names for all entries
for my $entry (@network) {
	$entry->{dnsname} = ip2host($entry->{addr});
}

# Sort by name/suffix/DNS
@network = sort {$a->{name} cmp $b->{name}
	|| $a->{suffix} <=> $b->{suffix}
	|| $a->{dnsname} cmp $b->{dnsname}} @network;

# Print out
for my $entry (@network) {
	my $flag;
	if ($entry->{type} eq "group")		{$flag = "G"}
	else					{$flag = ""}

	my $color = "";
	my $c_reset = "";
	if (-t 1 or defined $ENV{FORCE_COLOR}) {
		if ($entry->{suffix} == $SUFFIX{server}) {
			#$color = "\e[1;32m";
			$color = "\e[30;42m";
		} elsif ($entry->{suffix} == $SUFFIX{workstation}) {
			$color = "\e[32m";
		} elsif ($entry->{suffix} == $SUFFIX{domain_master}) {
			$color = "\e[1;35m";
		} elsif ($entry->{suffix} == $SUFFIX{local_master}) {
			$color = "\e[35m";
		} elsif ($entry->{suffix} == $SUFFIX{domain_controller}) {
			$color = "\e[1;36m";
		} elsif ($entry->{suffix} == $SUFFIX{browser_elections}) {
			$color = "\e[1;30m";
		} elsif ($entry->{suffix} == $SUFFIX{messenger}) {
			$color = "\e[33m";
		} else {
			$color = "";
		}
		$c_reset = "\e[m";
	}
		
	printf "%s%-15s<%02x> %1s %-15s %-20s %s%s\n",
		$color,
		$entry->{name}, $entry->{suffix}, $flag,
		$entry->{addr}, $entry->{dnsname}, $NSUFFIX{$entry->{suffix}},
		$c_reset;
}