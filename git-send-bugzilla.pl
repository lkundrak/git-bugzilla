#!/usr/bin/env perl
# Copyright (C) 2007, Steve Frécinaux <code@istique.net>
# Pitifully crippled by Lubomir Rintel <lkundrak@v3.sk>
# License: GPL v2 or later

use strict;
use warnings;
use Getopt::Long qw(:config posix_default gnu_getopt);
use Term::ReadKey qw/ReadMode ReadLine/;
use File::Temp qw/tempdir/;

# Use WWW::Mechanize if available and display a gentle message otherwise.
BEGIN {
	eval { require WWW::Mechanize; import WWW::Mechanize };
	die <<ERROR if $@;
The module WWW::Mechanize is required by git-send-bugzilla but is currently
not available. You can install it using cpan WWW::Mechanize.
ERROR
}

my $mech = WWW::Mechanize->new(agent => "git-send-bugzilla/0.0");
my $url = '';

sub authenticate {
	my $username = shift;
	my $password = shift;

	unless ($username) {
		print "Bugzilla login: ";
		chop ($username = ReadLine(0));
	}

	unless ($password) {
		print "Bugzilla password: ";
		ReadMode 'noecho';
		chop ($password = ReadLine(0));
		ReadMode 'restore';
		print "\n";
	}

	print STDERR "Logging in as $username...\n";
	$mech->get("$url?GoAheadAndLogIn=1");
	die "Can't fetch login form: ", $mech->res->status_line
		unless $mech->success;

	$mech->set_fields(Bugzilla_login => $username,
			  Bugzilla_password => $password);
	$mech->submit;
	die "Login submission failed: ", $mech->res->status_line
		unless $mech->success;
	die "Invalid login or password\n" if $mech->title =~ /Invalid/i;
}

sub read_file {
	my $file = shift;

	open FILE, '<', $file;
	my $content = join "", <FILE>;
	close FILE;
	return $content;
}

sub get_patch_info {
	my $patch = shift;

	my $description;
	my $comment = '';
	my $bugid;

	open COMMIT, '<', $patch or die "$patch: $!";
	while (<COMMIT>) {
		chop;

		# Get subject from header
		if (1 .. $_ eq '') {
			/^Subject: (.*)/ or next;
			$description = $1;
		# Get comment lines
		} elsif (not $_ eq '---' ... $_ eq '---') {
			$comment .= "$_\n";
		# Skip diff content
		} else {
			last;
		}

		# If there's a bug id in comment, get it
		not $bugid and /#(\d+)/ and $bugid = $1;
	}
	close COMMIT;
	chomp $comment;

	return ($description, $comment, $bugid);
}

sub add_attachment {
	my $bugid = shift;
	my $patch = shift;
	my $description = shift;
	my $comment = shift;

	$mech->get("$url/attachment.cgi?bugid=$bugid&action=enter");
	die "Can't get attachment form: ", $mech->res->status_line
		unless $mech->success;

	my $form = $mech->form_name('entryform');

	$form->value('description', $description);
	$form->value('ispatch', 1);
	$form->value('comment', $comment);

	my $file = $form->find_input('data', 'file');

	my $filename = $description;
	$filename =~ s/^\[PATCH\]//;
	$filename =~ s/^\[([0-9]+)\/[0-9]+\]/$1/;
	$filename =~ s/[^a-zA-Z0-9._]+/-/g;
	$filename = "$filename.patch";
	$file->filename($filename);

	$file->content($patch);

	$mech->submit;
	die "Attachment failed: ", $mech->res->status_line
		unless $mech->success;

	die "Error while attaching patch. Aborting\n"
		unless $mech->title =~ /(Changes Submitted|Attachment \d+ added)/i;
}

sub read_repo_config {
	my $key = shift;
	my $type = shift || 'str';
	my $default = shift || '';

	my $arg = 'git config';
	$arg .= " --$type" unless $type eq 'str';

	chop (my $val = `$arg --get bugzilla.$key`);
	
	return $default if $?;
	return $val eq 'true' if ($type eq 'bool');
	return $val;
}

sub usage {
	my $exitcode = shift || 0;
	my $fd = $exitcode ? \*STDERR : \*STDOUT;
	print $fd "Usage: git-send-bugzilla [options] <bugid> <since>[..<until>]\n";
	exit $exitcode;
}

$url = read_repo_config 'url';
die <<ERROR unless $url;
URL of your bugzilla instance is not configured,
Please configure your bugzilla instance like:

   git config bugzilla.url http://bugzilla.gnome.org
   git config bugzilla.url http://bugzilla.redhat.com
ERROR
my $username = read_repo_config 'username';
my $password = read_repo_config 'password';
my $numbered = read_repo_config 'numbered', 'bool', 0;
my $start_number = read_repo_config 'startnumber', 'int', 1;
my $squash = read_repo_config 'squash', 'bool', 0;
my $bugid;
my $dry_run = 0;
my $help = 0;

# Parse options
Getopt::Long::Configure("require_order", "pass_through");
GetOptions("url|b=s" => \$url,
           "username|u=s" => \$username,
	   "password|p=s" => \$password,
	   "numbered|n" => \$numbered,
	   "start-number" => \$start_number,
	   "squash" => \$squash,
	   "bugid" => \$bugid,
	   "dry-run" => \$dry_run,
	   "help|h|?" => \$help);

exec 'man', 1, 'git-send-bugzilla' if $help;

# Compatibility: if it looks like a number, consider it
# to be a bug number (as if specified via --bugid)
$bugid = shift @ARGV if @ARGV and $ARGV[0] =~ /^\d+$/;

my @revisions;
while (@ARGV and not $ARGV[0] eq '--') {
	push @revisions, shift @ARGV;
}

# Get patch list
my $patchdir = tempdir(CLEANUP => 1);
open PATCHLIST, '-|', 'git', 'format-patch',
	($numbered ? '--numbered' : ()),
	'-o' => $patchdir, @revisions
	or die "Cannot call git rev-list: $!";
my @patches = <PATCHLIST>;
chop @patches;
close PATCHLIST;

die "No patch to send\n" if @patches eq 0;
authenticate $username, $password unless $dry_run;

if (!$squash) {
	print STDERR "Attaching patches...\n";
	for my $patch (@patches) {
		my ($description, $comment, $bug) = get_patch_info $patch;
		$bug = $bugid if $bugid;
		if ($bug) {
			print STDERR "#$bug: $description\n";
		} else {
			print STDERR "No bug number for $description, skipping it.\n";
			next;
		}
		add_attachment $bug, read_file($patch),
			$description, $comment unless $dry_run;
	}
} else {
	print STDERR "Attaching squashed patch...\n";
	die "No bug number" unless $bugid;
	my $description = "[PATCH] Mailbox with ".scalar @patches." squashed changes";
	my $comment = "";
	my $content = '';
	for my $patch (@patches) {
		my ($description) = get_patch_info $patch;
		$content .= read_file ($patch);
		$comment .= "$description\n";
	}
	chomp $comment;
	add_attachment $bugid, $content,
		$description, $comment unless $dry_run;
}
print "Done.\n"
