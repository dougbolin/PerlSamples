	#=======================================================
	#  ssc - Sector Scorecard
	#=======================================================

	use SscUtils;
	use Config::IniHash;
	use File::Copy;

	#=======================================================
	#  Read ssc.ini file for configuration settings
	#    - values are returned as $ssc->{section}->{name}
	#=======================================================
	$ssc = ReadINI ('ssc.ini', {case, preserve}) ;

	my $verbose = $ssc->{runtime}->{verbose} ;
	my $datadir = $ssc->{runtime}->{datadir} ;
	my $archdir = $ssc->{runtime}->{archdir} ;
	my $logfile = $ssc->{runtime}->{logfile} ;
	my $htmlreport = $ssc->{runtime}->{htmlreport} ; 

	my $oracle  = $ssc->{runtime}->{oracle} ;
	my $gics1500 = $ssc->{files}->{gics1500} ;
	my $gicssect = $ssc->{files}->{gicssect} ;
	my @envirs = split(/ /, $ssc->{environments}->{list} );
	my $maxrc = 0;
	$runtime = localtime;

	# Change to the "$datadir" data directory
	chdir "$datadir" or die "Can't change work directory to $datadir: $!\n" ;

	# NOT IN USE: Set log file name from hour/minute, open log as STDOUT
	# ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	# $hour = sprintf("%02d", $hour);
	# $min  = sprintf("%02d", $min);
	
	close STDOUT;
	my $rc = open STDOUT, '>', $logfile ;
	unless ($rc) {
		print "Can't open the SSC STDOUT output file $logfile: $!" ;
		exit ;
	}
	my $resrc = open htmlreport, '>', $htmlreport ;
	unless ($resrc) {
		print "Can't open the SSC (HTML) output file $htmlreport: $!" ;
		exit ;
	}


	# Dispatch list - if errors occur, attach these files to the e-mail. Nothing
	# goes unless there's a problem. Push the log file name in first, but remember that
	# it is a TEXT file rather than an XLS.
	@dispatch = ();
	push(@dispatch, $htmlreport) ;

	# HTML-format message accumulator array.
	@html = ();

	# Look in datadir for a file called "manual.txt". Its existence signals LOCAL
	# file processing only. If missing (usually the case), proceed to FTP downloads.
	if (-e "manual.txt") {
		SscUtils::messenger( 105, "File 'manual.txt' exists. Skipping FTP download step, processing local XLS files only." ) ;
	} else {

		# Access FTP and return all present files. Responses 0=ok, 4=NoFiles, 8=Error

		# Change to the "$archdir" archive
		chdir "$archdir" or die "Can't change work directory to $archdir: $!\n" ;

		my $rc = SscUtils::ftp_process( $ssc ) ;
		if ($rc) {
			SscUtils::messenger( 210, "FTP Process result is $rc, check log." ) ;
			SscUtils::collect_html("<br><b>FTP Processing Result = $rc. Check Log.</b>") ;
		}
		# SscUtils::messenger( 0, "rc is $rc, maxrc is $maxrc" ) ;
		$maxrc = $rc if $maxrc < $rc ;
		goto WRAPUP	if ($maxrc > 3) ;
		# Change back to the "$datadir" data directory
		chdir "$datadir" or die "Can't change work directory to $datadir: $!\n" ;
	}

	$logactivity = 1 ;
	# Process the GICS 1500 spreadsheet (gics1500)
	print "Processing GICS 1500 file: $gics1500\n" ;

	# Read the XLS files into the hashes
	%sscGics1500Data = SscUtils::populate( $ssc, $gics1500 ) ;
	%sscGicsSectData = SscUtils::get_emphasis( $ssc, $gicssect ) ;

	# Debugging checkpoint
	# use Data::Dumper;
	# print Dumper(\%sscGics1500Data);
	# print Dumper(\%sscGicsSectData);
	
	# Merge the Sector Emphasis values into the main hash
	$sn = $#{ $sscGics1500Data{SSCs} } ;
	$en = $#{ $sscGicsSectData{name} } ;
	for $i ( 0 .. $sn ) {
		$gics		=	$sscGics1500Data{SSCs}[$i] ;
		$sect		=	$sscGics1500Data{$gics."sect"} ;
		$line		=	$sscGics1500Data{$gics."line"} ;
		$name		=	$sscGics1500Data{$gics."name"} ;
		# When it's the start of a sector, merge the emphasis
		# from the Sector Data spreadsheet. Others go blank.
		if (($sect > 0) && ($line == 0)) {
			for $j ( 0 .. $en ) {
				$sectname = $sscGicsSectData{name}[$j] ;
				$sectemph = $sscGicsSectData{emphasis}[$j] ;
				if ($name eq $sectname) {
					$emphasis = $sectemph ;
					$sscGics1500Data{$gics."emph"} = $emphasis ;
					last;
				}
			}
		}
	}
	
	# Print the completed array here...
	# print Dumper(\%sscGics1500Data);

	# Print input data
	SscUtils::print_ssc( \%sscGics1500Data ) ;
	
	# Set up the HTML SSC Result page
	print htmlreport "<html><head>\n" ;
	print htmlreport "<title>Sector Scorecard Save Result</title>\n" ;
	print htmlreport "<style>\n" ;
	print htmlreport " body {background:#ffffff;font-family:Verdana,Arial,Helvetica,sans-serif;font-size:11px;}\n" ;
	print htmlreport " h2 {text-align:center;font-style:normal;font-weight:bold;font-size:16px;font-family:Verdana,Arial,Helvetica,sans-serif;vertical-align:top;color:#006600;background:white}\n" ;
	print htmlreport " th {padding:2 3;text-align:center;font-style:normal;font-weight:normal;font-size:11px;font-family:Verdana,Arial,Helvetica,sans-serif;vertical-align:top;color:black;background:#ccc;}\n" ;
	print htmlreport " td {padding:0 3;text-align:right;font-style:normal;font-weight:normal;font-size:11px;font-family:Verdana,Arial,Helvetica,sans-serif;vertical-align:top;color:black;background:white;}\n" ;
	print htmlreport " td.l {text-align:left;}\n" ;
	print htmlreport " td.lb {text-align:left;font-weight:bold;}\n" ;
	print htmlreport " td.c {text-align:center;}\n" ;
	print htmlreport " td.y {color:black;background:#ffffcc;}\n" ;
	print htmlreport " td.cy {text-align:center;color:black;background:#ffffcc;}\n" ;
	print htmlreport " td.ok {color:white;background:green;font-weight:bold;text-align:center;}\n" ;
	print htmlreport " td.err {color:yellow;background:red;font-weight:bold;text-align:center;}\n" ;
	print htmlreport "</style>\n" ;
	print htmlreport "</head>\n" ;
	print htmlreport "<body>\n" ;
	print htmlreport "<h2>Sector Scorecard Save Result for $sscGics1500Data{Date}</h2>\n" ;
	print htmlreport "<center>(Update Time: $runtime)</center>\n" ;
	print htmlreport "<table cellspacing=0 cellpadding=0 width=100%>\n" ;

	# Call to Update the Sector_Scorecard table in Oracle, by Environment
	for $env ( @envirs ) {
		$showenv = uc $env ;
		$update = $ssc->{$env}->{update} ;
		print htmlreport "<tr><tr><th colspan=13>Environment: <b>$showenv</b> Update: <b>$update</b>\n" ;
		SscUtils::update_ssc_table( $env, \*htmlreport, \%sscGics1500Data ) ;
	}
	print htmlreport "</table></body></html>\n" ;

	if (-e "manual.txt") {
		SscUtils::messenger( 0, "File 'manual.txt' exists. Skipping FTP cleanup step." ) ;
	} else {
		SscUtils::ftp_cleanup( $ssc ) ;
	}

WRAPUP: if ($logactivity == 0) {
		# Nothing processed, don't send an e-mail
		SscUtils::messenger( 100, "No SSC files processed. Task ends, E-Mail skipped." ) ;
		exit 0 ;
	}

	if ($verbose) {
		# Verbose is on, probably doing a test run, send an e-mail as if it's an error.
		SscUtils::messenger( 100, "Verbose = 1, likely this is a Test, E-Mail being sent." ) ;
		# exit 0 ;
	}

	SscUtils::messenger( 0, "E-Mail preparation begins." ) ;

	# Development checkpoint : exit no matter what
	exit 0 ;

	#=======================================================
	#  E-Mail handling - covers HTML and Attachments
	#  dispatches a message with attached process log
	#=======================================================

	use Mail::Sendmail;
	use HTML::Entities;
	use MIME::QuotedPrint;
	use MIME::Base64;

	# Process the waiting HTML code array into a file.
	SscUtils::collect_html("*WRITE*") ;

	$/ = undef ; # turn on slurp mode
	%mime_type = (
		"txt"   => "text/plain",
		"xls"   => "application/vnd.ms-excel",
	);

	%mail = (
		To	=> '',
		From	=> '',
		Subject	=> 'ssc Successful',
		'content-type'	=> 'text/html; charset="iso-8859-1"',
	);

	# Adapt for e-mail addresses provided (From, To, Cc)
	my $fromlist = $ssc->{email}->{from} ;
	$mail{From} = $fromlist ;
	my $tolist = $ssc->{email}->{tosuccess} ;
	$mail{To} = $tolist ;
	my $cclist = $ssc->{email}->{cc} ;
	$mail{Cc} = $cclist ;
	# Cc	=> 'doug_bolin@standardandpoors.com',

	$Mail::Sendmail::mailcfg{debug} = 6;

	$boundary = "====" . time() . "====";
	$mail{'content-type'} = "multipart/mixed; boundary=\"$boundary\"" ;

	$/ = undef ; # turn on slurp mode

	# HTML - this should always be sent as the visible portion of the message
	my $htmlfile = $ssc->{runtime}->{htmlfile} ;
	open HTMLFILE, $htmlfile ;
	$html = encode_qp(<HTMLFILE>);
	close HTMLFILE ;

	$boundary = '--'. $boundary ;
	$mail{body} = $boundary . "\n" ;
	$mail{body} = $mail{body} . "Content-Type: text/html; charset=\"iso-8859-1\"\n" ;
	$mail{body} = $mail{body} . "Content-Transfer-Encoding: quoted-printable\n\n" ;
	$mail{body} = $mail{body} . $html . "\n" ;

	# This concludes the section that should be sent under normal conditions.
	# The remainder is provided in the e-mail only if errors are present, or
	# if $verbose is 1 (on).

	if ($maxrc > 1 || $verbose) {
		# Process the "dispatch" array for the files that need to be attached.
		# The first is the logfile, TXT format. The others are XLS.
		$mail{Subject} = "SSC Testing - Files Attached" if ( $verbose ) ;
		if ($produpdt > 0) {
			# This is the condition we have to escalate - production update failed.
			# 'verbose' must be OFF or notice will NOT go to 'failure' recipients...
			if ($verbose == 0) {
				$mail{Subject} = "ssc Unsuccessful - Files Attached" ;
				my $tolist = $ssc->{email}->{tofailure} ;
				$mail{To} = $tolist ;
			}
		}
		foreach $filename (@dispatch) {
			$extent = $filename =~ /\.(\w+)$/ ? "\L$1" : undef;
			$mime_type = "application/octet-stream";
			if ( defined $extent ) {
				if ( defined $mime_type{"$extent"} ) {
					$mime_type = $mime_type{"$extent"};
				} else {
					$mime_type = "application/octet-stream";
				}
			}
			open F,"$filename";
			$file = <F>;
			close F;
			$file = encode_base64($file);

			$mail{body} = $mail{body} . $boundary . "\n" ;
			$mail{body} = $mail{body} . "Content-Type: $mime_type; name=\"$filename\"\n" ;
			$mail{body} = $mail{body} . "Content-Transfer-Encoding: base64\n" ;
			$mail{body} = $mail{body} . "Content-Disposition: attachment; filename=\"$filename\"\n\n" ;
			$mail{body} = $mail{body} . $file . "\n" ;
		}
	}

	$mail{body} = $mail{body} . $boundary . "--\n" ;
	$mail{smtp} = 'mailhost';
	sendmail(%mail) or die $Mail::Sendmail::error;
	# print "OK. sendmail log says:\n", $Mail::Sendmail::log;

	close (TEMPFILE);
	close (STDERR);
	close (STDOUT);


