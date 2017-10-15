#!/usr/bin/perl
use strict;
use warnings;
use feature qw[ say ];
use autodie;
use Pod::Usage;
use Getopt::Long;
use Digest::MD5;
use Term::ANSIColor qw[ colored ];
use File::Basename qw[ basename ];

use constant ARG_DEFAULTS => (
    trigger  => 'mtime',
    interval => 1,
    status   => 0,
    color    => 0,
);

use constant TRIGGER_PROPERTIES => {
    content => \&file_md5_hex,
    mtime   => sub { -M $_[0] },
};

my %args = ARG_DEFAULTS;
GetOptions(\%args, qw/
    trigger=s
    interval=i
    exec=s
    status
    color
    help
/) or pod2usage(-verbose => 1, -noperldoc => 1);
pod2usage(-verbose => 2, -noperldoc => 1) if $args{help};

$ENV{ANSI_COLORS_DISABLED} = 1 if not $args{color};

my $filename = shift or die "Specify a filename\n";
die "No such file or directory: $filename\n" unless -e $filename;

my ($command, @args);
if (not $args{exec}) {
    die "$filename is not executable\n" unless -x $filename;
    $command = basename($filename) eq $filename ? "./$filename" : $filename;
}
else {
    $command = $args{exec};
    push @args, $filename;
}
push @args, @ARGV; # pass options after -- to the command

my $property = TRIGGER_PROPERTIES->{ $args{trigger} };
die "Invalid trigger: $args{trigger}\n" if not defined $property;
my $rerun_condition = gen_rerun_condition($filename, $property);

my $com_str = $command . " @args" x !!@args;
say "Starting runner for command `$com_str`" if $args{status};

while (1) {
    my $exit_code = system $command, @args;
    print "\n";

    if ($args{status}) {
        if ($exit_code == 0) {
            say colored(['bold green'], "Command `$com_str` completed successfully");
        }
        else {
            say colored(['bold red'], "Command `$com_str` finished with a non-zero exit code: $exit_code");
        }
    }

    do {
        sleep $args{interval};
    } while not $rerun_condition->();
}

sub gen_rerun_condition {
    my ($filename, $property) = @_;
    my $last_value = $property->($filename);
    return sub {
        my $current_value = $property->($filename);
        my $result        = $current_value ne $last_value;
        $last_value = $current_value;
        return $result;
    };
}

sub file_md5_hex {
    my ($filename) = @_;

    my $md5 = Digest::MD5->new;
    open my $fh, '<', $filename;
    binmode $fh;
    $md5->addfile($fh);
    close $fh;

    return $md5->hexdigest;
}

__END__
=pod

=head1 NAME

dynamic_runner.pl - run a program every time it's changed

=head1 SYNOPSIS

    $ dynamic_runner.pl -s -c -t content changing_script.pl

=head1 DESCRIPTION

This script will monitor a file for changes and run it every time
a change condition is met. The condition could be either a change
of the file contents or a newer modification time.

The condition will be checked in set intervals, every second by default.

=head1 OPTIONS

=head2 -t|--trigger [mtime|content]

Set the rerun condition. With B<mtime> the file will be rerun whenever
it's modification time is updated, with B<content> it will only be run
when its content changes.

=head2 -i|--interval [int]

Interval between checks of the rerun condition in seconds.

=head2 -e|--exec [program]

If the file is not executable, you may use a custom interpreter to run it.
For example, to run the file with Python:

    $ dynamic_runner.pl --exec=python script.py

=head2 -s|--status

Show the exact command which will be executed on startup and report
the program exit status after every run.

=head2 -c|--color

Make the status messages colored.

=head2 -h|--help

Display this help.
