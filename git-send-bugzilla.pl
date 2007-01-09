#!/usr/bin/env perl
# Copyright (C) 2007, Steve Frécinaux <code@istique.net>
# License: GPL v2 or later

use strict;
use warnings;
use WWW::Mechanize;
use Getopt::Long;
use Term::ReadKey qw/ReadMode ReadLine/;

my $url = "http://bugzilla.gnome.org";
my $mech = WWW::Mechanize->new(agent => "git-send-bugzilla/0.0");

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
	$mech->get("$url/index.cgi?GoAheadAndLogIn=1");
	die "Can't fetch login form: ", $mech->res->status_line
		unless $mech->success;

	$mech->set_fields(Bugzilla_login => $username,
			  Bugzilla_password => $password);
	$mech->submit;
	die "Login submission failed: ", $mech->res->status_line
		unless $mech->success;
	die "Invalid login or password\n" if $mech->title =~ /Invalid/i;
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
	$filename =~ s/^\[[0-9]+\/[0-9]+\]/$1/;
	$filename =~ s/[^a-zA-Z0-9._]+/-/g;
	$filename = "$filename.patch";
	$file->filename($filename);

	$file->content($patch);

	$mech->submit;
	die "Attachment failed: ", $mech->res->status_line
		unless $mech->success;

	die "Error while attaching patch. Aborting\n"
		unless $mech->title =~ /Changes Submitted/i;
}

sub read_repo_config {
	my $key = shift;
	my $type = shift || 'str';
	my $default = shift || '';

	my $arg = 'git-repo-config';
	$arg .= " --$type" unless $type eq 'str';

	chop (my $val = `$arg --get bugzilla.$key`);
	
	return $default if $?;
	return $val eq 'true' if ($type eq 'bool');
	return $val;
}

sub usage {
	my $exitcode = shift || 0;
	my $fd = $exitcode ? \*STDERR : \*STDOUT;
	print $fd <<EOF;
Usage: git-send-bugzilla [options] <bugid> <since>[..<until>]

Options:
   -u|--username <username>
       Your Bugzilla user name.

   -p|--password <password>
       Your Bugzilla password.

   -n|--numbered
       Prefix attachment names with [n/m].

   --start-number <n>
       Start numbering the patches at <n> instead of 1.
EOF
	exit $exitcode;
}

my $username = read_repo_config 'username';
my $password = read_repo_config 'password';
my $numbered = read_repo_config 'numbered', 'bool', 0;
my $start_number = read_repo_config 'startnumber', 'int', 1;
my $dry_run = 0;
my $help = 0;

# Parse options
GetOptions("username|u=s" => \$username,
	   "password|p=s" => \$password,
	   "numbered|n" => \$numbered,
	   "start-number" => \$start_number,
	   "dry-run" => \$dry_run,
	   "help|h|?" => \$help);

usage if $help;
my $bugid = shift @ARGV
	or print STDERR "No bug id specified!\n" and usage 1
	unless $dry_run;

# Get revisions to build patch from. Do the same way git-format-patch does.
my @revisions;
open REVPARSE, '-|', 'git-rev-parse', ('--revs-only', @ARGV)
	or die "Cannot call git-rev-parse: $!";
chop (@revisions = <REVPARSE>);
close REVPARSE;

if (@revisions eq 0) {
	print STDERR "No revision specified!\n";
	usage 1;
} elsif (@revisions eq 1) {
	$revisions[0] =~ s/^\^?/^/;
	push @revisions, 'HEAD';
}

# Get revision list
open REVLIST, '-|', "git-rev-list", @revisions
	or die "Cannot call git-rev-list: $!";
chop (@revisions = reverse <REVLIST>);
close REVLIST;

die "No patch to send\n" if @revisions eq 0;

authenticate $username, $password unless $dry_run;

print STDERR "Attaching patches...\n";
my $i = $start_number;
my $n = @revisions - 1 + $i;
for my $rev (@revisions) {
	my $description = $numbered ? "[$i/$n]" : '[PATCH]';
	my $comment = '';

	open COMMIT, '-|', "git-cat-file commit $rev";
	# skip headers
	while (<COMMIT>) {
		chop;
		last if $_ eq "";
	}
	chop ($description .= ' ' . <COMMIT>);
	chop ($comment = join "", <COMMIT>) unless eof COMMIT;
	close COMMIT;

	$comment .= "\n---\n" unless $comment eq '';
	$comment .= `git-diff-tree --stat --no-commit-id $rev`;
	my $patch = `git-diff-tree -p $rev`;
	
	print STDERR "  - $description\n";

	add_attachment $bugid, $patch, $description, $comment unless $dry_run;

	$i++;
}
print "Done.\n"
