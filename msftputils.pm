package msftputils ;

sub ftp_process {
	# This subroutine connects to an FTP site and downloads the
	# files it finds there.
	use Net::FTP;
	use Cwd;
	use File::Copy;
	use File::Listing qw(parse_dir);

	$msini = shift ;

	my $dnlddir =	$msini->{runtime}->{dnlddir} ;
	my $datadir =	$msini->{runtime}->{datadir} ;

	my $host =		$msini->{ftp}->{host} ;
	my $user =		$msini->{ftp}->{user} ;
	my $pass =		$msini->{ftp}->{pass} ;
	my $subdir =	$msini->{ftp}->{subdir} ;
	my $filedate =	$msini->{ftp}->{filedate} ;
	my $filedow =	$msini->{ftp}->{filedow} ;
	my $msnavdlymask = $msini->{ftp}->{msnavdlymask} ;
	my $msnavdlytemp = $msini->{ftp}->{msnavdlytemp} ;
	my $msnavdlytrgt = $msini->{ftp}->{msnavdlytrgt} ;
	my $ms7dyyldmask = $msini->{ftp}->{ms7dyyldmask} ;
	my $ms7dyyldtemp = $msini->{ftp}->{ms7dyyldtemp} ;
	my $ms7dyyldtrgt = $msini->{ftp}->{ms7dyyldtrgt} ;

	print '-' x 80;
	print "\nmsftputils::ftp_process -\n\tFiledate: $filedate\n" ;
	# Adapt the two masks to reflect the filedate, which will be a weekday ('Mon','Tue', etc).
	# 	Process: variables msnavdlymask, ms7dyyldmask - expanding the "%" to "$filedate"
	$msnavdlymask =~ s|%|$filedow|e ;
	$ms7dyyldmask =~ s|%|$filedow|e ;
	print "\tFilemasks:\n\t\tNAV Daily: $msnavdlymask\n\t\t7DAY Yield Daily: $ms7dyyldmask\n" ;

	my $fullfilename = "" ;
	my $fulltempfilename = "" ;
	my $ncnt = 0 ;

	# $dnlddir is target site for the FTP downloads
	print "Download Directory specified: $dnlddir\n" ;
	chdir $dnlddir ;
	my $cwd = cwd();
	print "Current DOWNLOAD directory is $cwd\n" ;
	my $cleared = unlink <*.*> ;
	print "\t - Cleanup removed $cleared files.\n" ;

	#=======================
	#  Connect to FTP site
	#=======================
	$ftp = Net::FTP->new($host, Debug => 0) ;
	unless ($ftp) {
		print "FTP cannot connect to $host: $@" ;
		return 8 ;
	}
	$ftp->login($user, $pass) ;
	print "FTP logged in, $host, $user, $pass, $subdir\n" ;

	if ( $subdir ne '' ) {
		$ftp->cwd($subdir) ;
	}
	my $pwd = $ftp->pwd() ;
	print "Present Working Directory is: $pwd\n" ;

	#====================================
	#  Show DIR list of NAV DAILY files
	#  -- Download matched date file
	#====================================
	$ftp->binary() ;
	$ncnt = 0 ;
	for (parse_dir($ftp->dir($msnavdlymask))) {
		($name, $type, $size, $mtime, $mode) = @$_;
		print "Found: \tFilename $name\tFilesize $size\n" ;
		$ftp->get("$name") ;
		$fullflgfilename = $dnlddir . $msnavdlyrcvd ;
		my $cr = open NAV1RCVD, '>', $fullflgfilename ;
		print NAV1RCVD "NAV DAILY file received: $name\tSize: $size\n" ;
		close NAV1RCVD ;
		$ncnt++ ;
	}
	print "\tNAV_1 files found: $ncnt\n" ;

	#====================================
	#  Show DIR list of 7 DAY YIELD files
	#  -- Download matched date file
	#====================================
	$ftp->binary() ;
	my $dcnt = 0 ;
	for (parse_dir($ftp->dir($ms7dyyldmask))) {
		($name, $type, $size, $mtime, $mode) = @$_;
		print "Found:\tFilename $name\tFilesize $size\n" ;
		$ftp->get("$name") ;
		$fullflgfilename = $dnlddir . $ms7dyyldrcvd ;
		my $cr = open DY7YRCVD, '>', $fullflgfilename ;
		print DY7YRCVD "7-DAY YIELD file received: $name\tSize: $size\n" ;
		close DY7YRCVD ;
		$dcnt++ ;
	}
	print "\t7-DAY YIELD files found: $dcnt\n" ;
	print "FTP quit\n" ;
	$ftp->quit;

	$fcnt = $ncnt + $dcnt ;
	print "Total files found: $fcnt\n" ;
	return 0 ;
}

sub verify_dates {
	# This subroutine verifies that the files retrieved are for the correct date.
	# If all is deemed okay, the files are moved from the DOWNLOAD directory ($dnlddir)
	# to the DATA (or WORK) directory ($datadir), and the flag 'xferm.flg' file is added.

	$msini = shift ;

	use File::Copy;
	use File::Listing qw(parse_dir);

	my $filedate =	$msini->{ftp}->{filedate} ;
	my $filedow =	$msini->{ftp}->{filedow} ;
	my $dnlddir =	$msini->{runtime}->{dnlddir} ;
	my $datadir =	$msini->{runtime}->{datadir} ;
	my $archdir =	$msini->{runtime}->{archdir} ;
	my $msnavdlytemp = $msini->{ftp}->{msnavdlytemp} ;
	my $ms7dyyldtemp = $msini->{ftp}->{ms7dyyldtemp} ;
	my $msnavdlytrgt = $msini->{ftp}->{msnavdlytrgt} ;
	my $ms7dyyldtrgt = $msini->{ftp}->{ms7dyyldtrgt} ;

	$filedate =~ s/-//g ; # remove dashes, i.e. yyyy-mm-dd becomes yyyymmdd
	my $mmdd = substr $filedate, 4, 4;
	my $navok = 0 ;
	my $r10ok = 0 ;
	$msnavdlytemp =~ s|%|$filedow|e ;
	$ms7dyyldtemp =~ s|%|$filedow|e ;
	$msnavdlytrgt =~ s|MMDD|$mmdd|e ;
	$ms7dyyldtrgt =~ s|MMDD|$mmdd|e ;
	print '-' x 80;
	print "\nmsftputils::verify_dates -\n\tFiledate: $filedate,\tFileDOW: $filedow\n\tDOWNLOAD Dir: $dnlddir\n\tDATA Dir: $datadir\n\tNAV File: $msnavdlytemp\n\tR10 File: $ms7dyyldtemp\n" ;

	$verfilename = $dnlddir . $msnavdlytemp ;
	open (VERFILE,"<$verfilename") ;
	$verrecnav = <VERFILE> ;
	chomp ;
	$navok = $verrecnav =~ /DATE=$filedate/ ;
	close VERFILE ;

	$verfilename = $dnlddir . $ms7dyyldtemp ;
	open (VERFILE,"<$verfilename") ;
	$verrecr10 = <VERFILE> ;
	chomp ;
	$r10ok = $verrecr10 =~ /DATE=$filedate/ ;
	close VERFILE ;

	if ( $navok & $r10ok ) {
		print "File dates are verified.\n\tCopying files and Flag to DATADIR (WORK) directory:\n" ;
		print "\t\t$msnavdlytemp to $msnavdlytrgt\n" ;
		copy ( $dnlddir . $msnavdlytemp, $datadir . $msnavdlytrgt ) ;
		print "\t\t$ms7dyyldtemp to $ms7dyyldtrgt\n" ;
		copy ( $dnlddir . $ms7dyyldtemp, $datadir . $ms7dyyldtrgt ) ;
		print "\t\txferm.flg\n" ;
		my $flgfile = $datadir . 'xferm.flg' ;
		open ( XFERMFLG, ">$flgfile" ) ;
		print XFERMFLG 'xferm.flg' ;
		close XFERMFLG ;
		print "\tCopying files to ARCHIVE directory:\n" ;
		print "\t\t$msnavdlytemp to $msnavdlytrgt\n" ;
		copy ( $dnlddir . $msnavdlytemp, $archdir . $msnavdlytrgt ) ;
		print "\t\t$ms7dyyldtemp to $ms7dyyldtrgt\n" ;
		copy ( $dnlddir . $ms7dyyldtemp, $archdir . $ms7dyyldtrgt ) ;
	} else {
		print "File dates were NOT completely verified.\n\tFiles are NOT copied to DATADIR (WORK) or ARCHIVE directories.\nAnalysis:\n\tFind $filedate in: $verrecnav\n\tResult: $navok\n\tFind $filedate in: $verrecr10\n\tResult: $r10ok\n" ;
	}
	return 0 ;
}

sub ftp_delivery {

	# This subroutine connects to several FTP sites and uploads the deliverable files.
	use Net::FTP;
	use File::Copy;
	use File::Listing qw(parse_dir);

	print '-' x 80;
	print "\nmsftputils::ftp_delivery\n" ;

	$msini = shift ;

	my $datadir = $msini->{runtime}->{datadir} ;
	# $datadir is source site for the FTP deliveries
	print "Source Directory specified: $datadir\n" ;
	chdir $datadir ;
	my $cwd = cwd();
	print "Current Source directory is $cwd\n" ;
	my @files = glob("*.ssc xferm.flg");

	@delsites = split(/\s+/,$msini->{delivery}->{sites});
	foreach $site (@delsites) {
		my $host =   $msini->{$site}->{host} ;
		my $user =   $msini->{$site}->{user} ;
		my $pass =	 $msini->{$site}->{pass} ;
		my $subdir = $msini->{$site}->{subdir} ;
		print "Delivery attempt to FTP site $site\n" ;
		#=======================
		#  Connect to FTP site
		#=======================
		$ftp = Net::FTP->new($host, Debug => 0) ;
		unless ($ftp) {
			print "FTP cannot connect to $host: $@" ;
			return 8 ;
		}
		$ftp->login($user, $pass) ;
		print "FTP logged in, $host, $user, $pass, $subdir\n" ;

		if ( $subdir ne '' ) {
			$ftp->cwd($subdir) ;
		}
		my $pwd = $ftp->pwd() ;
		print "Present Working Directory is: $pwd\n" ;

		#====================================
		#  Upload files
		#====================================
		$ftp->ascii() ;
		$ftp->ls() ;
		foreach my $file (@files) {
			print "$file\n";
			$ftp->put("$file") ;
		}
		$ftp->ls() ;
		$ftp->quit;
	}
	return 0 ;
}

sub email_notify {

	# This subroutine delivers an e-mail notification	
	use Mail::Sendmail;

	$msini = shift ;

	print '-' x 80;
	print "\nmsftputils::email_notify\n" ;
	
	$/ = undef ; # turn on slurp mode
	%mime_type = (
		"txt"   => "text/plain",
		"xls"   => "application/vnd.ms-excel",
	);

	%mail = (
		To	=> '',
		From	=> '',
		Subject	=> 'Morningstar FTP Processing',
		'content-type'	=> 'text/html; charset="iso-8859-1"',
	);

	my $from      = $msini->{email}->{from} ;
	my $tosuccess = $msini->{email}->{tosuccess} ;
	my $tofailure = $msini->{email}->{tofailure} ;
	my $cc        = $msini->{email}->{cc} ;

	$Mail::Sendmail::mailcfg{debug} = 6;

	$mail{From} = $from ;
	$mail{To}   = $tofailure ;
	$mail{Cc}   = $cc ;
	$mail{Subject} = "Morningstar FTP Processing" ;
	$mail{body} = $msini->{email}->{text} . "\n" ;
	$mail{smtp} = 'smtprelay.mhf2.mhf.mhc';
	sendmail(%mail) or die $Mail::Sendmail::error;
	print "OK. sendmail log says:\n", $Mail::Sendmail::log;	
}

1;
