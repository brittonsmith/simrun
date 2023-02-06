#! /usr/bin/perl
#-----------------------------------------------------------------------------
#
# Automated simulation runner.
#
# Copyright (c) Britton Smith <brittonsmith@gmail.com>. All rights reserved.
#
# Distributed under the terms of the Modified BSD License.
#
# The full license is in the file COPYING.txt, distributed with this software.
#-----------------------------------------------------------------------------

use Cwd;
use POSIX ":sys_wait_h";
my $cdir = getcwd;
$job_name = join "/", (split "/", $cdir)[-2 .. -1];

$email_address = ''; # put email in singe quotes
$job_file = "run_enzo.qsub";
$parameter_file = (glob("*.enzo"))[0];
$enzo_executable = "./enzo.exe";
$output_file = "estd.out";
$walltime = 86400;
$submit_command = "qsub";
$tries = 1;
$max_waittime = 5 * 60;

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
    elsif ($arg =~ /^-of/) {
        $output_file = shift @ARGV;
    }
    elsif ($arg =~ /^-sub/) {
	$submit_command = shift @ARGV;
    }
    elsif ($arg =~ /^-tries/) {
        $tries = shift @ARGV;
    }
    elsif ($arg =~ /^-maxwait/) {
        $max_waittime = shift @ARGV;
    }
    elsif ($arg =~ /^-h/) {
        &print_help();
    }
    else {
        &print_help();
    }
}

die "No mpi call given.\n" unless ($mpi_command);

$run_finished_file = "RunFinished";
$enzo_log_file = "OutputLog";
$log_file = "run.log";

$last_output = &get_last_output();
&change_parameters($last_output);
$first_output = $last_output;

$start_time = time;
$this_try = 0;

while (1) {

  if ($last_output) {
    $run_par_file = $last_output;
    $enzo_flags = "-d -r";
  }
  else {
    $run_par_file = $parameter_file;
    $enzo_flags = "-d";
  }

  &rename_output_file($output_file);
  $command_line = "$mpi_command $enzo_executable $enzo_flags $run_par_file > $output_file 2>&1";
  print "Running: $command_line\n";
  &write_log("Starting enzo with $run_par_file.\n");
  $last_run_time = time;
  $this_try++;

  &runit($command_line, $output_file, $max_waittime);

  $last_output = &get_last_output();
  &change_parameters($last_output);

  if (($last_output eq $run_par_file) || !($last_output)) {
      if ($this_try >= $tries) {
          &write_log("Simulation did not make new data, exiting.\n");
          &send_email(
               "\'supercomputer says: $job_name in trouble!\'",
               "Hey,\nThe simulation exited without making new data.\nPlease help!\n");
          exit(1);
      }
      else {
          &write_log(
               "Simulation did not make new data, making try $this_try of $tries.\n");
      }
  }

  if (-e $run_finished_file) {
    &write_log("Simulation finished, exiting.\n");
    &send_email("\'supercomputer says: $job_name finished!\'",
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
	  &send_email("\'supercomputer says: $job_name stopped for today\'",
		      "Job started at: $first_output.\nJob ended at: $last_output.\nResubmitted as: $newid.\n");
	  exit(0);
      }
  }
  else {
      $this_try = 0;
  }

}

sub runit {
    my ($cmd, $ofn, $maxwait) = @_;

    # this is the parent who will monitor the output file
    if ($pid = fork) {
        $stime = time;
        $ptime = time;
        $ptime2 = time;
        &write_log("Monitoring job for inactivity after $maxwait seconds.\n");
        # give it a minute before checking
        sleep 60;

        do {

            # keep checking status of job
            $status = waitpid($pid, WNOHANG);

            # write verbose logging to figure out why this doesn't work
            if ((time - $ptime2) > $maxwait) {
                $since_check = time - $ptime2;
                $since_start = (time - $stime) / 3600;
                &write_other_log("verbose.log",
                    "$since_check seconds since last update, running for $since_start hours, status is $status.\n");
                $ptime2 = time;
            }

            # how long has it been since output file updated
            $since_update = time - (stat($ofn))[9];
            if ($since_update > $maxwait) {
                &write_log(
                     "No update from output file in $since_update seconds, let's get out of here.\n");
                kill 9, $pid;

                &write_log("Resubmitting, better luck next time.\n");
                $newid = &submit_job();
                exit(0);
            }

            # write reassuring message every 6 hours
            if ((time - $ptime) > 21600) {
                $since_start = (time - $stime) / 3600;
                &write_log(
                    "Running smoothly for $since_start hours, will check back later.\n");
                $ptime = time;
            }

            sleep 10;
        } while $status == 0;
    }

    # this is the child who will run the job
    else {
        &write_log(
             "It's me, the child! I'm starting your enzo now.\n");
        system($cmd);
        &write_log(
            "Child here again. Enzo terminated cleanly and I shall now do the same.\n");
        exit(0);
    }

    &write_log("Parent here, the job ended with status $status. If this seems wrong, please report.\n");
}

sub write_log {
  my ($line) = @_;
  open (LOG, ">>$log_file");
  print LOG scalar (localtime);
  print LOG " $line";
  close (LOG);
}

sub write_other_log {
  my ($fn, $line) = @_;
  open (LOG, ">>$fn");
  print LOG scalar (localtime);
  print LOG " $line";
  close (LOG);
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
    $jobid = `$submit_command $job_file`;
    chomp $jobid;
    return $jobid;
}

sub change_parameters {
    my ($parFile) = @_;
    $newParFile = $parFile . ".new";
    $oldParFile = $parFile . ".old";

    my $change_file = "new_pars";
    if (!(-e $change_file)) {
	return;
    }

    open (IN, "<$change_file") or return;
    my @lines = <IN>;
    close (IN);

    %newPars = ();
    foreach $line (@lines) {
	my ($my_key, $my_val) = split "=", $line, 2;
	$my_key =~ s/\s//g;
	$my_val =~ s/\s//g;
	$newPars{$my_key} = $my_val;
    }

    foreach $key (keys %newPars) {
	$changed{$key} = 0;
    }

    open (IN,"<$parFile") or die "Couldn't open $parFile.\n";
    open (OUT,">$newParFile") or die "Couldn't open $newParFile.\n";
    while (my $line = <IN>) {
	my $did = 0;
      PAR: foreach $par (keys %newPars) {
	  if ($line =~ /^\s*$par\s*=\s*/) {
	      &write_log("Switching $par to $newPars{$par}.\n");
	      print OUT "$par = $newPars{$par}\n";
	      $changed{$par} = 1;
	      $did = 1;
	      last PAR;
	  }
      }
	print OUT $line unless($did);
    }
    foreach $par (keys %changed) {
	unless ($changed{$par}) {
	    &write_log("Adding $par parameter set to $newPars{$par}.\n");
	    print OUT "$par = $newPars{$par}\n";
	}
    }
    close (IN);
    close (OUT);

    system ("mv $parFile $oldParFile");
    system ("mv $newParFile $parFile");
    my $new_change_file = $change_file . ".old";
    system ("mv $change_file $new_change_file");
}

sub rename_output_file {
    my ($filename) = @_;
    if (!(-e $filename)) {
        return;
    }

    $filename =~ /(.+)\.(.+)$/;
    $prefix = $1;
    $suffix = $2;
    while (1) {
        $new_fn = sprintf("%s_%d.%s", $prefix, $i, $suffix);
        if (-e $new_fn) {
            $i++
        }
        else {
            &write_log("Renaming $filename as $new_fn.\n");
            system("mv $filename $new_fn");
            return;
        }
    }
}

sub print_help {
    print "Usage: $0 -mpi <mpi command> [options]\n";
    print "Options:\n";
    print "  -email <email address>\n";
    print "  -exe <enzo executable> Default: enzo.exe\n";
    print "  -jf <job script> Default: run_enzo.qsub\n";
    print "  -mpi <mpi command> Example: mpirun -np 16, Default: none\n";
    print "  -of <enzo output file> Default: estd.out\n";
    print "  -pf <simulation parameter file> Default: *.enzo\n";
    print "  -sub <job submit command> Default: qsub\n";
    print "  -tries <integer> - number of tries to run simulation (>1 to restart from crash) Default: 1\n";
    print "  -wall <walltime in seconds> Default: 86400 (24 hours)\n";
    print "  -maxwait <integer> - number of seconds without writing to log file before requeueing. Default: 300.\n";
    exit(0);
}
