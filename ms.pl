#=======================================================
#  MS - Morningstar Daily file retrieval
#=======================================================

#-------------------------------------------------------
# This Perl script handles the movement of data files
# which are delivered by Morningstar to our FTP site.
#-------------------------------------------------------

# Essentials:
#	1 - Log into Morningstar FTP site
#	2 - Locate daily NAV1 file
#		If found:
#		a) Download to archive directory
#		b) verify date from first record of file
#		c) Copy/rename most recent file to current directory
#	3 - Locate daily R10 file
#		If found:
#		a) Download to archive directory
#		b) verify date from first record of file
#		c) Copy/rename most recent file to current directory
#	4 - Check for errors, resolve:
#		a) Extra files just move to the archive directory
#		b) One file there, other missing.

use Config::IniHash;
use Cwd;
use Date::Parse;
use msftputils;

$msini = ReadINI ('ms.ini', {'case', 'preserve'}) ;
my $verbose =  $msini->{runtime}->{verbose} ;
my $dnlddir =  $msini->{runtime}->{dnlddir} ;
my $archdir =  $msini->{runtime}->{archdir} ;
my $datadir =  $msini->{runtime}->{datadir} ;
my $logfile =  $msini->{runtime}->{logfile} ;
my $sleeper =  $msini->{runtime}->{sleeper} ;
my $cutoffhr = $msini->{runtime}->{cutoffhr} ;
my $cutoffmn = $msini->{runtime}->{cutoffmn} ;
my $filedate = $msini->{ftp}->{filedate} ;
my @abbr = qw( Sun Mon Tue Wed Thu Fri Sat );

close STDOUT ;
open (STDOUT, ">$logfile") ;
select((select(STDOUT), $|=1)[0]);
print "\nms.pl - Morningstar File Processing\n\n" ;

# If filedate isn't coded, use system date.
if ($filedate eq '') {
	print "Configured filedate not provided, will default to system date.\n" ;
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
} else {
	print "Configured filedate has been provided.\n" ;
	my $passedfd = str2time($filedate) ;
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($passedfd);
}
# print "Sec $sec, Min $min, Hour $hour, MDay $mday, Mon $mon, Year $year, Wday $wday, Yday $yday, IsDst $isdst\n" ;
$year = $year + 1900 ;
$mon = $mon + 1 ;
$yyyy = sprintf("%04d", $year);
$mm  = sprintf("%02d", $mon);
$dd = sprintf("%02d", $mday);
$filedate = "$yyyy-$mm-$dd" ;
$filedow = $abbr[$wday] ;

print "Filedate = $filedate\tFile Day Of Week = $filedow\n" ;
$msini->{ftp}->{filedate} = $filedate ;
$msini->{ftp}->{filedow}  = $filedow ;

# Timer set-up begins here

$unixtime = time ;
($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($unixtime);
# print "Sec $sec, Min $min, Hour $hour, MDay $mday, Mon $mon, Year $year, Wday $wday, Yday $yday, IsDst $isdst\n" ;

$year = $year + 1900 ;
$mon = $mon + 1 ;
$yyyy = sprintf("%04d", $year);
$mm  = sprintf("%02d", $mon);
$dd = sprintf("%02d", $mday);
$ttdate = "$yyyy-$mm-$dd" ;
$ttdow = $abbr[$wday] ;
$savehour = $hour ;
$savemin = $min ;

$go_time = sprintf("%02i:%02i:%02i",$hour,$min,$sec) ;
$co_time = sprintf("%02i:%02i",$cutoffhr,$cutoffmn) ;
print "Timer Initiating:\n\t$ttdate ($ttdow) at $go_time (unix $unixtime)\n\n" ;
print "INI Settings:\n\tCut-Off Time = $co_time (hr:mn)\n\tSleep period = $sleeper (seconds)\n\n" ;

# Invoke a loop to run until $cutoffhr:$cutoffmn with built-in sleep of $sleeper, unless files come in.
# If conditions are not met by the end of the sleep cycles, issue e-mail FAIL alerts.
# Also issue periodic WARNING alerts at change of hour or minute

# Precalculate FAIL point.
# Logic overview:
# initssm (initial seconds since midnight, the Present time, if you would.)
# ctofssm (cutoff seconds, since midnight)
# Compare. If initssm > ctofssm, add a day to the ctofssm before subtracting.
# Add the difference ($netdur) to the present time, to yield the Unix time at cutoff.

$initssm = ( $hour * 3600 ) + ( $min * 60 ) ;
$ctofssm = ( $cutoffhr * 3600 ) + ( $cutoffmn * 60 ) ;
if ( $initssm > $ctofssm ) {
	$ctofssm = $ctofssm + 86400 ;
}
$netdur = $ctofssm - $initssm ;
$cutoffunix = $unixtime + $netdur ;

# DURING TESTING ONLY: Verify the Date/Time of the Cut Off, by back-feeding the time
($cosec,$comin,$cohour,$comday,$comon,$coyear,$cowday,$coyday,$coisdst) = localtime($cutoffunix);
$coyear = $coyear + 1900 ;
$comon = $comon + 1 ;
$coyyyy = sprintf("%04d", $coyear);
$comm  = sprintf("%02d", $comon);
$codd = sprintf("%02d", $comday);
$codate = "$coyyyy-$comm-$codd" ;
$codow = $abbr[$cowday] ;

$ver_time = sprintf("%02i:%02i",$cohour,$comin) ;
print "Cut-Off will occur at:\t$codate ($codow) at $ver_time (unix $cutoffunix)\n\n" ;
print "Net Timer Duration is $netdur seconds.\n\n" ;

for (;;) {

	# Call subprocess to access FTP site and retrieve files
	msftputils::ftp_process ($msini) ;

	# Call unzip to decompress all .zip files in the download directory
	$args = ("unzip -o $dnlddir*.zip");
	print '-' x 80;
	print "\nRunning system command: $args\n" ;
	system($args) ;
	if ($? == -1) {
		print "unzip failed to execute: $!\n";
	} elsif ($? & 127) {
		printf "unzip died with signal %d, %s coredump\n", ($? & 127),  ($? & 128) ? 'with' : 'without';
	} else {
		printf "unzip completed with value %d\n", $? >> 8;
	}

	# Call subprocess to verify dates on retrieved files, and move them (with FLAG file to DATADIR if okay.
	msftputils::verify_dates ($msini) ;

	# If files were placed in the $datadir directory, initiate the FTP delivery process
	# and then quit this loop.

	# $datadir is source site for the FTP deliveries. Need to have exactly 3 files to proceed.
	chdir $datadir ;
	my @files = glob("*.ssc *.flg");
	foreach my $file (@files) {
		print "glob files: $file\n";
	}
	if ( scalar(@files) == 3 ) {
		msftputils::ftp_delivery ($msini) ;
		last ;
	}

	# Timer control block - quit with alerts if after cutoff time, else sleep and try again.
	# Publish warning on change of interval (hr or mn)

	$now_time = sprintf("%02i:%02i",$hour,$min) ;
	if ( $unixtime >= $cutoffunix ) {
		print "\nOut of Time - issue FAILURE alert here.\n" ;
		print "\nThe time is $now_time. The Morningstar FTP Process ran out of time waiting for valid files. Review log files.\n" ;
		$msini->{email}->{text} = "The time is $now_time.<p>FAILURE Alert:<p>The Morningstar FTP Process ran out of time waiting for valid files. Review log files." ;
		msftputils::email_notify ($msini) ;
		last ;
	}
	if ( $hour ne $savehour ) {
		print "\nHour has changed - issure WARNING alert here.\n" ;
		print "\nThe time is $now_time. The Morningstar FTP Process has not yet located valid files. Review log files.\n" ;
		$msini->{email}->{text} = "The time is $now_time.<p>REMINDER:<p>The Morningstar FTP Process has not yet located valid files." ;
		msftputils::email_notify ($msini) ;
		$savehour = $hour ;
	}

	# Sleeps here
	print "\nFiles not found or did not pass validity checks.\n\t...sleeping for $sleeper seconds\n" ; 
	sleep $sleeper ;
	
	# Wakes up here
	$unixtime = time ;
	($sec,$min,$hour,,,,,,) = localtime($unixtime);
	$wake_time = sprintf("%02i:%02i:%02i",$hour,$min,$sec) ;
	print '-' x 80 . "\n" ;
	print "Awakened at: $wake_time (unix $unixtime)\n" ;
	print '-' x 80 . "\n" ;
}

close STDOUT ;
exit 0 ;
