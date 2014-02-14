#! /usr/bin/perl
#-----------------------------------------------------------------------------
#
# Send emails left by simrun.pl
#
# Copyright (c) 2012-2014, Britton Smith <brittonsmith@gmail.com>
#
# Distributed under the terms of the Modified BSD License.
#
# The full license is in the file COPYING.txt, distributed with this software.
#-----------------------------------------------------------------------------

$message_file = ".message";

foreach $arg (@ARGV) {
    foreach $dir (glob $arg) {
	push @dirs, $dir if (-d $dir);
    }
}

die "No directories to follow.\n" unless (@dirs);
&write_log("Watching " . scalar @dirs . " directories.\n");

while (1) {
    foreach $dir (@dirs) {
	$check_file = &path_join($dir, $message_file);
	if (-e $check_file) {
	    &send_email_from_file($check_file);
	    &write_log("Found message in $dir and sent.\n");
	}
    }
    sleep 60;
}

sub send_email_from_file {
    my ($filename) = @_;
    open (IN, "<$filename") or die "Couldn't open $filename.\n";
    $address = <IN>;
    chomp $address;
    $subject = <IN>;
    chomp $subject;
    @body = <IN>;
    close (IN);

    $mail_cmd = "/usr/bin/mailx";
    open (MAIL, "| $mail_cmd -s $subject $address") or die "Couldn't send email!\n";
    print MAIL @body;
    close (MAIL);
    unlink $filename;
}

sub write_log {
    my ($string) = @_;
    $log_file = "post.log";
    open (OUT, ">>$log_file") or die "Couldn't open log file.\n";
    print OUT scalar (localtime);
    print OUT " $string";
    close (OUT);
}

sub path_join {
    my @parts = @_;

    my $path = shift @parts;
    $path =~ s/\/+$//;
    foreach my $part (@parts) {
	$part =~ s/^\/+//;
	$part =~ s/\/+$//;
	$path .= '/' . $part;
    }
    return $path;
}
