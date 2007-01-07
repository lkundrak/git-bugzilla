#!/usr/bin/perl

use strict;
use warnings;
use WWW::Mechanize;
use Getopt::Long;

my $bugid = 0;
my $username = '';
my $password = '';
my $since = "";
my $until = "";
my $numbered = 0;
my $start_number = 1;

# Parse options
GetOptions("bug|b=i" => \$bugid,
	   "username|u=s" => \$username,
	   "password|p=s" => \$password,
	   "numbered|n" => \$numbered,
	   "start-number" => \$start_number);

unless ($bugid > 0 and $username and $password) {
	die "FIXME: Bad usage\n";
}

# Get revision list
my @revisions;
open REVLIST, '-|', "git-rev-list", @ARGV or die "Cannot call git-rev-list: $!";
chop (@revisions = reverse <REVLIST>);
close REVLIST;

die "No patch to send\n" if @revisions eq 0;

# Authenticate
my $mech = WWW::Mechanize->new(agent => "git-send-bugzilla/0.0");
print "Logging in as $username...\n";
$mech->get("http://bugzilla.gnome.org/index.cgi?GoAheadAndLogIn=1");
die "Can't fetch login form: ", $mech->res->status_line unless $mech->success;

$mech->set_fields(Bugzilla_login => $username,
		  Bugzilla_password => $password);
$mech->submit;
die "Login submission failed: ", $mech->res->status_line unless $mech->success;

print "Attaching patches...\n";
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
	chop ($comment = join "", grep {1} <COMMIT>) unless eof COMMIT;
	close COMMIT;

	$comment .= "\n---\n" unless $comment eq '';
	$comment .= `git-diff-tree --stat $rev`;
	my $patch = `git-diff-tree -p $rev`;
	
	print "  - $description\n";
	
	# Attach a patch to the bug
	$mech->get("http://bugzilla.gnome.org/attachment.cgi?bugid=$bugid&action=enter");
	die "Can't get attachment form: ", $mech->res->status_line unless $mech->success;

	my $form = $mech->form_name('entryform');

	$form->value('description', $description);
	$form->value('ispatch', 1);
	$form->value('comment', $comment);

	my $file = $form->find_input('data', 'file');
	$file->filename("patch-$i.patch");
	$file->content($patch);

	$mech->submit;
	die "Attachment failed: ", $mech->res->status_line unless $mech->success;

	$i++;
}
print "Done.\n"
