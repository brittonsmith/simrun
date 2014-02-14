#! /usr/bin/perl
#-----------------------------------------------------------------------------
#
# Automated simulation runner.
#
# Copyright (c) 2012-2014, Britton Smith <brittonsmith@gmail.com>
#
# Distributed under the terms of the Modified BSD License.
#
# The full license is in the file COPYING.txt, distributed with this software.
#-----------------------------------------------------------------------------

use Cwd;
my $cdir = getcwd;
$job_name = join "/", (split "/", $cdir)[-2 .. -1];

$email_address = ''; # put email in singe quotes
$job_file = "run_enzo.qsub";
$parameter_file = (glob("*.enzo"))[0];
$enzo_executable = "./enzo.exe";
$walltime = 86400;

while ($arg = shift @ARGV) {
    if ($arg =~ /^-mpi$/) {
	$mpi_command = shift @ARGV;
    }
    elsif ($arg =~ /^-wall/) {
	$walltime = shift @ARGV;
    }
    elsif ($arg =~ /^-pf/) {
	$parameter_file = shift @ARGV;
    }
    elsif ($arg =~ /^-exe/) {
	$enzo_executable = shift @ARGV;
    }
    elsif ($arg =~ /^-jf/) {
	$job_file = shift @ARGV;
    }
    elsif ($arg =~ /^-email/) {
        $email_address = shift @ARGV;
    }
    elsif ($arg =~ /^-h/) {
        &print_help();
    }
    else {
        &print_help();
    }
}

die "No mpi call given.\n" unless ($mpi_command);

$output_file = "estd.out";

$run_finished_file = "RunFinished";
$enzo_log_file = "OutputLog";
$log_file = "run.log";

$last_output = &get_last_output();
$first_output = $last_output;

$start_time = time;
while (1) {

  if ($last_output) {
    $run_par_file = $last_output;
    $enzo_flags = "-d -r";
  }
  else {
    $run_par_file = $parameter_file;
    $enzo_flags = "-d";
  }

  $command_line = "$mpi_command $enzo_executable $enzo_flags $run_par_file >& $output_file";
  print "Running: $command_line\n";
  &write_log("Starting enzo with $run_par_file.\n");
  $last_run_time = time;
  system($command_line);

  $last_output = &get_last_output();

  if (($last_output eq $run_par_file) || !($last_output)) {
    &write_log("Simulation did not make new data, exiting.\n");
    &send_email("\'kraken job: $job_name in trouble!\'",
		"Hey,\nThe simulation exited without making new data.\nPlease help!\n");
    exit(0);
  }
  if (-e $run_finished_file) {
    &write_log("Simulation finished, exiting.\n");
    &send_email("\'kraken job: $job_name finished!\'",
		"Hey,\nDon\'t get too excited, but I think this simulation may be done!\n");
    exit(0);
  }
  if ($walltime) {
      $time_elapsed = time - $last_run_time;
      $time_left = $start_time + $walltime - time;
      if (1.1 * $time_elapsed > $time_left) {
	  &write_log("Insufficient time remaining to reach next output.\n");
	  $newid = &submit_job();
	  $last_output = &get_last_output();
	  &send_email("\'kraken job: $job_name stopped for today\'",
		      "Job started at: $first_output.\nJob ended at: $last_output.\nResubmitted as: $newid.\n");
	  exit(0);
      }
  }

}

sub write_log {
  my ($line) = @_;
  open (OUT, ">>$log_file");
  print OUT scalar (localtime);
  print OUT " $line";
  close (OUT);
}

sub get_last_output {
  open (IN, "<$enzo_log_file") or return;
  my @lines = <IN>;
  close (IN);

  my @online = split " ", $lines[-1];
  return $online[2];
}

sub send_email {
    my ($subject, $body) = @_;
    $signature = "-Robot Britton\n";
    $message_file = ".message";
    open (MAIL, ">$message_file") or die "Couldn't write message file.\n";
    print MAIL $email_address . "\n";
    print MAIL $subject . "\n";
    print MAIL $body;
    print MAIL $signature;
    close(MAIL);
}

sub submit_job {
    $jobid = `qsub $job_file`;
    chomp $jobid;
    return $jobid;
}

sub print_help {
    print "Usage: $0 -mpi <mpi command> [options]\n";
    print "Options:\n";
    print "  -email <email address>\n";
    print "  -wall <walltime in seconds> Default: 86400 (24 hours)\n";
    print "  -pf <simulation parameter file> Default: *.enzo\n";
    print "  -exe <enzo executable> Default: enzo.exe\n";
    print "  -jf <job script> Default: run_enzo.qsub\n";
    exit(0);
}
