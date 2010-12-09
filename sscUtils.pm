package SscUtils ;

sub ftp_process {
	# This subroutine connects to the FTP site and downloads the *.xls
	# files it finds there. Target site is the "work" (wdir) directory.
	# The name of the file is changed on the download to attach the
	# date and time stamp found in the ModTime value
	use Net::FTP;
	use File::Copy;
	
	$ssc = shift ;
	$datadir = $ssc->{runtime}->{datadir} ;

	#=======================
	#  Connect to FTP site
	#=======================
	$ftp = Net::FTP->new($ssc->{ftp}->{host}, Debug => 0) ;
	unless ($ftp) {
		SscUtils::messenger( 215, "FTP cannot connect to $ssc->{ftp}->{host}: $@" ) ;
		SscUtils::collect_html("<br><b><font style={color:red}>ERROR - FTP cannot connect to $ssc->{ftp}->{host}</font></b>: $@") ;
		return 8 ;				
	}
	my $rc = $ftp->login($ssc->{ftp}->{user},$ssc->{ftp}->{pass}) ;
	unless ($rc) {
		SscUtils::messenger( 220, "FTP cannot login, rc is $rc" ) ;
		SscUtils::collect_html("<br><b><font style={color:red}>ERROR $rc - FTP cannot login</font></b>" ) ;
		return 8 ;				
	}
	if ( $ssc->{ftp}->{wdir} ne "" ) {
		my $rc = $ftp->cwd($ssc->{ftp}->{wdir}) ;
		unless ($rc) {
			SscUtils::messenger( 225, "FTP cannot change to working directory $ssc->{ftp}->{wdir}, rc is $rc" ) ;
			SscUtils::collect_html("<br><b><font style={color:red}>ERROR $rc - FTP cannot change to working directory $ssc->{ftp}->{wdir}</font></b>") ;
			return 8 ;				
		}
	}
	#======================
	#  Show list of Files
	#======================
	@filelist = $ftp->ls("*.xls");
	$sfiles = scalar @filelist;
	SscUtils::messenger( 0, "FTP - SSC files found: $sfiles" ) ;
	if ( $sfiles == 0 ) { 
		return 4 ;
	}
	foreach (@filelist) {
		SscUtils::messenger( 0, "FTP - \t$_" ) ;
	}
	#======================
	#  Download SSC files
	#======================
	$ftp->binary();
	foreach (@filelist) {
		$sscfile = $_ ;
		# Get the File's modtime and convert to date/time for local file prefix
		my $mdtm = $ftp->mdtm("$sscfile");
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($mdtm);
		$year = $year + 1900;
		$mon  = sprintf("%02d", $mon + 1);
		$mday = sprintf("%02d", $mday);
		$hour = sprintf("%02d", $hour);
		$min  = sprintf("%02d", $min);
		$sec  = sprintf("%02d", $sec);
		$ymdhms = $year . $mon . $mday . "_" . $hour . $min . $sec ;
		$locsscfile = $ymdhms . "_" . $sscfile ;
		# Download SSC files to local directory
		SscUtils::messenger( 0, "FTP - Downloading $sscfile to $locsscfile" ) ;
		my $rc = $ftp->get("$sscfile","$locsscfile") ;
		unless ($rc) {
			SscUtils::messenger( 230, "FTP get failed, rc is $rc - ", $ftp->message ) ;
			SscUtils::collect_html("<br><b>FTP get failed, $ftp->message</b>") ;
			return 4 ;				
		}
		$fullfilename = $datadir . $sscfile ;
		print "Copy $locsscfile to $fullfilename\n" ;
		copy( $locsscfile, $fullfilename ) ;
	}
	$ftp->quit;
	return 0 ;
}

sub ftp_cleanup {
	# This subroutine connects to the FTP site and deletes any *.xls
	# files it finds there. Only called if 'manual.txt' is NOT found in the
	# datadir (working directory specified in ssc.ini).
	use Net::FTP;
	$ssc = shift ;
	#=======================
	#  Connect to FTP site
	#=======================
	$ftp = Net::FTP->new($ssc->{ftp}->{host}, Debug => 0) ;
	unless ($ftp) {
		SscUtils::messenger( 115, "FTP cleanup, cannot connect to $ssc->{ftp}->{host}: $@" ) ;
	}
	my $rc = $ftp->login($ssc->{ftp}->{user},$ssc->{ftp}->{pass}) ;
	unless ($rc) {
		SscUtils::messenger( 120, "FTP cleanup, cannot login. rc is $rc" ) ;
	}
	if ( $ssc->{ftp}->{wdir} ne "" ) {
		my $rc = $ftp->cwd($ssc->{ftp}->{wdir}) ;
		unless ($rc) {
			SscUtils::messenger( 125, "FTP cleanup, cannot change to working directory $ssc->{ftp}->{wdir}, rc is $rc" ) ;
		}
	}
	#======================
	#  Show list of Files
	#======================
	@filelist = $ftp->ls("*.xls");
	$sfiles = scalar @filelist;
	SscUtils::messenger( 0, "FTP Cleanup - SSC files found: $sfiles" ) ;
	foreach (@filelist) {
		SscUtils::messenger( 0, "FTP Cleanup - \t$_" ) ;
	}
	#=======================
	#  Delete basket files
	#=======================
	foreach (@filelist) {
		$sscfile = $_ ;
		SscUtils::messenger( 0, "FTP Cleanup - \tDeleting $sscfile" ) ;
		$ftp->delete("$sscfile") ;
	}
	$ftp->quit;
}


sub populate {

	# This subroutine reads the GICS 1500 Scorecard file, and creates
	# a Hash of Arrays (HoA) containing all valid data rows

	use Spreadsheet::ParseExcel;
	use Carp;
	use Getopt::Long;

	$ssc = $_[0];
	$sscfile_name = $_[1];
	-e $sscfile_name or die "Must provide valid GICS 1500 Scorecard file (XLS format)! $sscfile_name, $!\n";

	my %SSCHoA = () ;
	$verbose = $ssc->{runtime}->{verbose};

	print "Populating GICS 1500 Scorecard data from $sscfile_name ...\n" ;
	#===========================================================
	#  Read the Excel Object, extract data
	#===========================================================
	# Create a ParseExcel object
	my $excel_obj = Spreadsheet::ParseExcel->new();
	my $workbook = $excel_obj->Parse($sscfile_name);
	# make sure we're in business
	die "Workbook did not return Worksheets!\n"
		unless ref $workbook->{Worksheet} eq 'ARRAY';

	# Worksheet should divide into sections (0-10) with sequenced lines in each.
	# Once a new GICS sector_id is established, all gic_cds in that section must
	# match by their first 2 characters, the GICS group. 
	# (For sector_id = 0 the rule does not apply, since its gic_cds are the Indices)
	#	example:
	#		sector_id = 1, scorecard_display_seq = 0, gic_id = '25'
	#		while we're in sector_id 1, all gic_cd must start with '25' -
	#			like '25401010', '25504010'

	# The GICS sections are pre-defined:
	#	 SECTOR_ID GIC_CD
	#	---------- ----------
	#	         0 1500  <-- sector_id = 0, rule doesn't apply
	#	         1 25	\
	#	         2 30	|
	#	         3 10	|
	#	         4 40	|
	#	         5 35	| <- all gic_cd must begin with these...
	#	         6 20	|
	#	         7 45	|
	#	         8 15	|
	#	         9 50	|
	#	        10 55	/
	# Pre-load these into an array.
	
	# Detect sector_id changes when gic_cd < 100
	# Blank gic_cd are ignored except to add to the sectline (scorecard_display_seq)
	# Begin collection with $row=5 to skip the headings

	# Special Handling:
	#   Cell A1($row=0,$col=0) - Contains the date in format (mm/dd/yy)
	#   Cells I6:I9 ($row=5-8,$col=8) - Blank should be forced 0.0 (maybe all should)

	# Standard Column mappings, description, variable name:
	# 	A 0	Name						name
	# 	B 1	Index Value					idxval
	# 	C 2	% of S&P 1500				pctsp15
	# 	D 3	Price Chg %, week				pchg1wk
	# 	E 4	", 13 weeks					pchg13wk
	# 	F 5	", YTD					pchgytd
	# 	G 6	", Prior Year				pchgpyr
	# 	H 7	", 5-Yr CAGR				pchg5yr
	# 	I 8	Rankings 12 month rel strength	rank12m
	# 	J 9	Rankings STARS				stars
	# 	K 10	(unused)
	# 	L 11	GICS Number					gicsnum

	my $sectnum = 0;
	my $sectline = -1;
	my $sectgicsbase = "";
	my $sectcheck2 = "";

	SHEET:
	for my $worksheet ( @{$workbook->{Worksheet}} ) {

		# Date capture
		my $cell = $worksheet->{Cells}[0][0];
		my $datecell = ref($cell) ? $cell->Value : '';
		print "This should contain the date: $datecell\n" ;
		$datecell =~ /\((\S*)\)/ ;
		my $date = $1 ;
		print "Date extracted: $date\n" ;
		$SSCHoA{Date} = $date ;

		my $last_row = $worksheet->{MaxRow} || 0;
		my $last_col = 9 ; # Up to the STARS column

		ROW:
		for my $row ( 5 .. $last_row ) {
			$sectline = $sectline + 1 ;

			# Key off the GICS Number in column L
			my $cell = $worksheet->{Cells}[$row][11];
			$content = ref($cell) ? $cell->Value : '';
			$content =~ s/^\s+//;
			$content =~ s/\s+$//;

			# Ignore blanks ...
			if ( $content eq "" ) {
				next ROW ;
			}
			
			my $gics = $content ;
			if ( $gics < 100 ) {
				$sectnum = $sectnum + 1 ;
				$sectline = 0 ;
				$sectgicsbase = $gics ;
				print "\nProcessing GICS Sector $sectgicsbase...\n" ;
			} else {
				# Verify that $gics belongs, sectnum > 0 only
				$sectcheck2 = substr $gics, 0, 2;
				if ( $sectnum gt 0 && $sectcheck2 ne $sectgicsbase ) {
					print "\n *** Error: GICS: $gics not part of $sectgicsbase\n" ;
				}				
			}
			
			# Start the GICS-based array entries, keep section/line
			push @{ $SSCHoA{SSCs} }, $gics ;
			push @{ $SSCHoA{Grid} }, "$sectnum|$sectline|$gics" ;
			$SSCHoA{$gics."sect"} = $sectnum ;
			$SSCHoA{$gics."line"} = $sectline ;
			$SSCHoA{$gics."emph"} = "";

			COL:
			for my $col ( 0 .. $last_col ) {
				my $cell = $worksheet->{Cells}[$row][$col];
				$content = ref($cell) ? $cell->Value : '';
				# Trim whitespace around content
				$content =~ s/^\s+//;
				$content =~ s/\s+$//;
				# Data checks for values in cols D-I (3-9 here)
				if ( $col >= 2 && $col <= 9 ) {
					# If negative value, remove parentheses
					if ((index $content,"(-") > -1) {
						$content =~ /\((\S*)\)/ ;
						$content = $1 ;
					}
					# If '-0.0', use '0'
					if ($content eq "-0.0") {
						$content = "0.0" ;
					}
					# If "NA", then blank out
					if ($content eq 'NA') {
						$content = '' ;
					}
				}
				if ($col == 0) {
					$SSCHoA{$gics."name"} = $content ;
				} elsif ($col == 1) {
					$SSCHoA{$gics."idxval"} = $content ;
				} elsif ($col == 2) {
					$SSCHoA{$gics."pctsp15"} = $content ;
				} elsif ($col == 3) {
					$SSCHoA{$gics."pchg1wk"} = $content ;
				} elsif ($col == 4) {
					$SSCHoA{$gics."pchg13wk"} = $content ;
				} elsif ($col == 5) {
					$SSCHoA{$gics."pchgytd"} = $content ;
				} elsif ($col == 6) {
					$SSCHoA{$gics."pchgpyr"} = $content ;
				} elsif ($col == 7) {
					$SSCHoA{$gics."pchg5yr"} = $content ;
				} elsif ($col == 8) {
					$SSCHoA{$gics."rank12m"} = $content ;
				} elsif ($col == 9) {
					$SSCHoA{$gics."stars"} = $content ;
				}
				print "$row,$col:\t$content\t" if ($verbose) ;
			}
		}
	}
	print "$sscfile_name, processing complete.\n" ;
	return %SSCHoA ;
}


sub get_emphasis {

	# This subroutine reads the GICS Sector Table spreadsheet,
	# and pulls up the S&P Sector Emphasis.

	use Spreadsheet::ParseExcel;
	use Carp;
	use Getopt::Long;

	$ssc = $_[0];
	$sscfile_name = $_[1];
	-e $sscfile_name or die "Must provide valid GICS Sector Table file (XLS format)! $sscfile_name, $!\n";

	my %SSCHoA = () ;
	$verbose = $ssc->{runtime}->{verbose};

	print "Populating GICS Sector Table data from $sscfile_name ...\n" ;
	#===========================================================
	#  Read the Excel Object, extract data
	#===========================================================
	# Create a ParseExcel object
	my $excel_obj = Spreadsheet::ParseExcel->new();
	my $workbook = $excel_obj->Parse($sscfile_name);
	# make sure we're in business
	die "Workbook did not return Worksheets!\n"
		unless ref $workbook->{Worksheet} eq 'ARRAY';

	# Worksheet should contain 10 data rows with S&P 500 Sector Names
	# and statistics. The only columns of interest here are the names
	# and the Sector Emphasis.
	# Begin collection with $row=5 to skip the headings
	# Standard Column mappings, description, variable name:
	# 	A 0	S&P 500 Sector Name	name
	# 	I 8	S&P Sector Emphasis	emphasis

	SHEET:
	for my $worksheet ( @{$workbook->{Worksheet}} ) {
		ROW:
		for my $row ( 5 .. 14 ) {
			# Get the S&P 500 Sector Name in column 0
			my $cell = $worksheet->{Cells}[$row][0];
			$content = ref($cell) ? $cell->Value : '';
			$content =~ s/^\s+//;
			$content =~ s/\s+$//;
			push @{ $SSCHoA{name} }, $content ;
			# Get the Emphasis in column 8, trim to 1st char
			my $cell = $worksheet->{Cells}[$row][8];
			$content = ref($cell) ? $cell->Value : '';
			$content =~ s/^\s+//;
			$content =~ s/\s+$//;
			$content = substr $content, 0, 1;
			push @{ $SSCHoA{emphasis} }, $content ;
		}
	}
	print "$sscfile_name, processing complete.\n" ;
	return %SSCHoA ;
}

sub print_ssc {

	%sscGics1500Data = %{$_[0]};

	# Use the number of "SSCs" entries to establish the size of the SSC array ($sn)
	# Development check - Expecting 144 entries
	$sn = $#{ $sscGics1500Data{SSCs} } ;
	for $i ( 0 .. $sn ) {
		$gics		=	$sscGics1500Data{SSCs}[$i] ;
		$sect		=	$sscGics1500Data{$gics."sect"} ;
		$line		=	$sscGics1500Data{$gics."line"} ;
		$date		=	$sscGics1500Data{Date} ;
		$name		=	$sscGics1500Data{$gics."name"} ;
		$idxval	=	$sscGics1500Data{$gics."idxval"} ;
		$pctsp15	=	$sscGics1500Data{$gics."pctsp15"} ;
		$pchg1wk	=	$sscGics1500Data{$gics."pchg1wk"} ;
		$pchg13wk	=	$sscGics1500Data{$gics."pchg13wk"} ;
		$pchgytd	=	$sscGics1500Data{$gics."pchgytd"} ;
		$pchgpyr	=	$sscGics1500Data{$gics."pchgpyr"} ;
		$pchg5yr	=	$sscGics1500Data{$gics."pchg5yr"} ;
		$rank12m	=	$sscGics1500Data{$gics."rank12m"} ;
		$stars	=	$sscGics1500Data{$gics."stars"} ;
		$emph		=	$sscGics1500Data{$gics."emph"} ;
		print "$sect|$line|$date|$name|$idxval|$pctsp15|$pchg1wk|$pchg13wk|$pchgytd|$pchgpyr|$pchg5yr|$rank12m|$stars||$gics||$emph|\n" ;
	}
}

sub update_ssc_table {

	$env = $_[0];
	$htmlreport = $_[1];
	%sscGics1500Data = %{$_[2]};

	use DBI;

	$update = $ssc->{$env}->{update} ;
	$showenv = uc $env ;
	if ($update == 0) {
		print "*NOTE* - Update switch is OFF for Environment $showenv\n"  ;
	}

	$oracle = $ssc->{runtime}->{oracle} ;
	if ($oracle == 1) {
		# Connect to Oracle
		$db = $ssc->{$env}->{db} ;
		print "Connecting to $env $db\n" if $verbose;
		$dbh = DBI->connect( $db );
		unless ($dbh) {
			print "Unable to connect to $db for environment $showenv\n" ;
			return;
		}
	} else {
		print "*NOTE* - Oracle switch is OFF, no connection requested\n" ;
	}
	
	# New convention: Delete all rows from sector_scorecard table before inserting new ones
	# On update failure, rollback.
	print "Deleting all rows from sector_scorecard table\n" ;
	if ($update == 1 && $oracle == 1) {
		my $delrc = $dbh->do("delete from sector_scorecard");
		print "Deleted $delrc rows.\n" ;
	}

	print $htmlreport "<tr><th>Industry Name<th>Index<th>%SP15<th>1Wk<th>13Wk<th>Ytd<th>PrYr<th>5Yr<th>RelStr<th>Stars<th>GICS<th>Emph<th>Upd\n" ;
	$sn = $#{ $sscGics1500Data{SSCs} } ;
	for $i ( 0 .. $sn ) {

		# Fetch the data for this row
		$gics		=	$sscGics1500Data{SSCs}[$i] ;
		$sect		=	$sscGics1500Data{$gics."sect"} ;
		$line		=	$sscGics1500Data{$gics."line"} ;
		$date		=	$sscGics1500Data{Date} ;
		$name		=	$sscGics1500Data{$gics."name"} ;
		$idxval		=	$sscGics1500Data{$gics."idxval"} ;
		$pctsp15	=	$sscGics1500Data{$gics."pctsp15"} ;
		$pchg1wk	=	$sscGics1500Data{$gics."pchg1wk"} ;
		$pchg13wk	=	$sscGics1500Data{$gics."pchg13wk"} ;
		$pchgytd	=	$sscGics1500Data{$gics."pchgytd"} ;
		$pchgpyr	=	$sscGics1500Data{$gics."pchgpyr"} ;
		$pchg5yr	=	$sscGics1500Data{$gics."pchg5yr"} ;
		$rank12m	=	$sscGics1500Data{$gics."rank12m"} ;
		$stars		=	$sscGics1500Data{$gics."stars"} ;
		$emph		=	$sscGics1500Data{$gics."emph"} ;

		# Split the Sectors with a Horizontal Rule
		if ($line eq 0) {
			print $htmlreport "<tr><td colspan=13><hr>\n" ;
			$namcls = 'lb';
		} else {
			$namcls = 'l' ;
		}

		# Write the HTML row
		print $htmlreport "<tr><td class=\"$namcls\">$name<td class=\"y\">$idxval<td>$pctsp15<td class=\"y\">$pchg1wk<td>$pchg13wk<td class=\"y\">$pchgytd<td>$pchgpyr<td class=\"y\">$pchg5yr<td class=\"c\">$rank12m<td class=\"y\">$stars<td>$gics<td class=\"cy\">$emph" ;

		# Adjust the values to database insert format
		$pctsp15 = 'NULL' if ($pctsp15 eq '');
		$pchg1wk = 'NULL' if ($pchg1wk eq '');
		$pchg13wk = 'NULL' if ($pchg13wk eq '');
		$pchgytd = 'NULL' if ($pchgytd eq '');
		$pchgpyr = 'NULL' if ($pchgpyr eq '');
		$pchg5yr = 'NULL' if ($pchg5yr eq '');
		$rank12m = 'NULL' if ($rank12m eq '');
		$stars = 'NULL' if ($stars eq '');
		if ($emph eq '') {
			$emph = 'NULL' ;
		} else {
			$emph = "'$emph'" ;
		}

		$maxrc = 0 ;
		# Insert values for sector_id, industry_id
		my $sqlstmt = "insert into sector_scorecard values ($sect, $line, TO_DATE('$date','MM/DD/YY'), '$line', '$name', $idxval, $pctsp15, $pchg1wk, $pchg13wk, $pchgytd, $pchgpyr, $stars, $rank12m, 0, NULL, $pchg5yr, $emph, '$gics')";
		print "$sqlstmt\n" if $verbose ;
		# INSERT GUIDE - based on Describe of table sector_scorecard :
		# $sect		SECTOR_ID
		# $line		SCORECARD_DISPLAY_SEQ
		# $date		SCORECARD_DT
		# $line		INDSTRY_ID
		# $name		INDSTRY_DESC
		# $idxval	INDSTRY_INDEX_VALUE
		# $pctsp15	INDSTRY_PCT_OF_1500
		# $pchg1wk	INDSTRY_PRC_CHG_1_WK
		# $pchg13wk	INDSTRY_PRC_CHG_13_WKS
		# $pchgytd	INDSTRY_PRC_CHG_YTD
		# $pchgpyr	INDSTRY_PRC_CHG_LAST_YR
		# $stars	SECTOR_AVG_STARS_RKNG
		# $rank12m	SECTOR_AVG_REL_STRNGTH
		# 0			SECTOR_AVG_FAIR_VAL
		# NULL		ANLYST_RCMMNDTN
		# $pchg5yr	INDSTRY_PRC_CHG_FIVE_YR
		# $emph		RCMD_MKT_WGHT
		# $gics		GIC_CD

		if ($update == 1 && $oracle == 1) {
			my $sth = $dbh->prepare($sqlstmt);
			$rc = $sth->execute();
			# print "Insert rc = $rc\n" ;
			if ($rc > 1) {
				$maxrc = $rc ;
			}
		}

		# Report the conditions of the updates. Details are in the ssclog.txt file
		if ($update == 0 || $oracle == 0) {
			print $htmlreport "<td class=\"ok\">Skip\n" ;
		} else {
			if ($maxrc == 0) {
				print $htmlreport "<td class=\"ok\">OK\n" ;
			} else {
				print $htmlreport "<td class=\"err\">Error\n" ;
			}
		}
	}

	if ($update == 1 && $oracle == 1) {
		print "Checking update for error: maxrc = $maxrc \n" ;
		if ($maxrc gt 0) {
			print "Update error... executing rollback\n" ;
			my $sqlstmt = "rollback";
			print "$sqlstmt\n" if $verbose ;
			my $sth = $dbh->prepare($sqlstmt);
			$rc = $sth->execute();
			if ($rc > 1) {
				print "Rollback failed! $sth->errstr\n" ;
			}
		}		
		print "Disconnecting...\n" ;
		$dbh->disconnect;
	}
}

sub messenger {

	# Message Center - aggregates output messages from the process, via the log file
	# and to the various components of the e-mail that's sent to confirm process
	# completion (Success/Failure).

	# Parm format - MsgNum (canned or unique), Text (show after prepared, or alone?)

	# Message Groups -
	#	000-099	Verbose=1 stuff, so if Verbose is off(0), just return
	#	100-199	Important notes - verbose=0 stuff
	#	200-299	Highlighted events - reasonable errors, program continues
	#	300-up	Severe errors - might halt program - "Someone needs to look at this!"

	$msgn = $_[0];
	$msgn = sprintf("%03d", $msgn);
	$msgt = $_[1];

	my $verbose = $ssc->{runtime}->{verbose} ;
	return if ($verbose eq '0' && $msgn < 100) ;

	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$hour = sprintf("%02d", $hour);
	$min  = sprintf("%02d", $min);
	$sec  = sprintf("%02d", $sec);
	my $tmstmp = $hour . ":" . $min . ":" . $sec ;

	# print "$msgt\n" ;
	print "$tmstmp\t$msgn\t$msgt\n" ;

	if ($msgn >= 300) {
		# This isn't sufficient
		print "ssc Severe error encountered, terminating...\n" ;
	}
}

sub collect_html {

	# Holds the HTML-page content for possible inclusion in the e-mail.

	$msgt = $_[0];

	if ($msgt ne '*WRITE*') {
		push(@html, $msgt) ;
		return ;
	}

	# Following only occurs when the *WRITE* request comes in.
	my $htmlfile = $ssc->{runtime}->{htmlfile} ;
	my $hfrc = open HTMLFILE, '>', $htmlfile ;
	unless ($hfrc) {
		SscUtils::messenger( 306, "Can't open the html output file as HTMLFILE: $!" ) ;
	}
	my $runtime = localtime;

	# Set up the HTML SSC Result page - head tags with style elements, headings
	print HTMLFILE "<html><head>" ;
	print HTMLFILE "<title>Sector Scorecard</title>" ;
	print HTMLFILE "<style>" ;
	print HTMLFILE " body {background:white;font-family:Verdana,Arial,Helvetica,sans-serif;font-size:11px;}" ;
	print HTMLFILE " h2 {text-align:center;font-style:normal;font-weight:bold;font-size:16px;font-family:Verdana,Arial,Helvetica,sans-serif;vertical-align:top;color:#060;background:white}" ;
	print HTMLFILE " th {padding:2 3;text-align:center;font-style:normal;font-weight:normal;font-size:11px;font-family:Verdana,Arial,Helvetica,sans-serif;vertical-align:top;color:black;background:#ccc;}" ;
	print HTMLFILE " th.r {padding:2 3;text-align:center;font-style:normal;font-weight:normal;font-size:11px;font-family:Verdana,Arial,Helvetica,sans-serif;vertical-align:top;color:#800;background:#ccc;}" ;
	print HTMLFILE " th.g {padding:2 3;text-align:center;font-style:normal;font-weight:normal;font-size:11px;font-family:Verdana,Arial,Helvetica,sans-serif;vertical-align:top;color:#060;background:#ccc;}" ;
	print HTMLFILE " td {padding:0 3;text-align:right;font-style:normal;font-weight:normal;font-size:11px;font-family:Verdana,Arial,Helvetica,sans-serif;vertical-align:top;color:black;background:white;}" ;
	print HTMLFILE " td.l {text-align:left;}" ;
	print HTMLFILE " td.lb {text-align:left;font-weight:bold;}" ;
	print HTMLFILE " td.c {text-align:center;}" ;
	print HTMLFILE " td.y {color:black;background:#ffc;}" ;
	print HTMLFILE " td.ok {color:white;background:#060;font-weight:bold;text-align:center;}" ;
	print HTMLFILE " td.err {color:yellow;background:#800;font-weight:bold;text-align:center;}" ;
	print HTMLFILE "</style>" ;
	print HTMLFILE "</head>" ;
	print HTMLFILE "<body>" ;
	print HTMLFILE "<h2>Sector Scorecard</h2>" ;
	print HTMLFILE "<center>$runtime</center>" ;
	# print HTMLFILE "<table cellspacing=0 cellpadding=0 width=100%>" ;

	# Print the collected HTML entries into the files
	print HTMLFILE @html ;

	# Close the page out
	print HTMLFILE "</body></html>" ;
	close HTMLFILE ;

}


1;
