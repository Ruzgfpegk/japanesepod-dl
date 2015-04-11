#!/usr/bin/perl -w

# Ruzgfpegk
# 2015-04-12 - v0.8a
#
# Script covered by the WTFPL
#
# This script:
# - Reads a XML file which is a RSS feed already downloaded from JapanesePod101.com
# - Creates a folder hierarchy
# - Writes text files when a RSS description is added to an item
# - Downloads the files into these folders and sets their modification time to the item date
# 
# For instance, an item titled "Lower Intermediate Lesson #46 - Mothers' Talk - Audio" will be saved as
# Audio.mp3 in the folder "Lower Intermediate Lesson #46 - Mothers' Talk".
# 
# This may or may not be against the Terms of Service of the website.
# You'll need an active membership to JP101 : http://www.japanesepod101.com/
# A free account will let you download the latest 10 audio lessons.
# http://www.japanesepod101.com/helpcenter/getstarted/downloadhowto # Links for the free feed (RSS, you can use it there)
# http://www.japanesepod101.com/helpcenter/getstarted/itunesfeeds   # Links for basic and premium feeds (ITPC only ?)
# http://www.japanesepod101.com/learningcenter/account/myfeed       # Create your own RSS (premium)
# 
# Known issues:
# - Windows is NOT supported. This is because many Perl5 modules don't support Unicode filepaths under Win32.
# - If you cancel (Ctrl+C) the process during a download, the last file won't be fully saved
#   but should be downloaded next time as the size will be different from the one in the XML.
# - The size estimation doesn't take into account what has already been downloaded (it's only based on the RSS contents).
# - The download order is NOT the RSS order. Processing is done in sorted order of the path names.
#   This can be an issue if files of a folder are in different parts of the RSS and you use dl_limit.
# - This script can be VERY verbose. It's because the RSS file their website generates is full of shit like multiple different entries for the same file.

use strict;
use warnings;

use utf8;                     # This file uses Unicode characters

use IO::File;                 # To create files cleanly
use File::Path qw(make_path); # To create paths cleanly
use Time::Piece;              # To parse dates in the XML file
use Unicode::Collate;         # Goddammit Perl. See http://www.perl.com/pub/2011/08/whats-wrong-with-sort-and-how-to-fix-it.html
# We could use File::Spec::Functions to handle filepaths as it's included in ActivePerl, but it's not in the OpenSuSE repository.

require LWP::UserAgent;       # To download the files
require XML::Simple;          # To parse the XML file


## Configuration

my %conf = (
	'XMLFile'   =>     '/path/to/your/JapanesePod101.com.xml',
	'OutDir'    =>     '/path/to/your/target/folder',
	'user'      =>     'YOUR_JP101_USERNAME',
	'pass'      =>     'YOUR_JP101_PASSWORD',
	'pretend'   =>     0,     # To avoid downloading files (just create folders and text files)
	'overwrite' =>     0,     # To overwrite old text files or already downloaded files (why?). "1-Length" items not included.
	'dl_limit'  =>     0,     # How many max files to download at each run? 0 for max.
	'verbose'   =>     1,     # To show each downloaded file on the console
	'throttle'  =>     1,     # How many seconds should we wait between two files?
	'fallback'  =>     q{_},  # In paths, by what character do we replace illegal ones? (like '?' or '*')
	'separator' =>     q{/},  # To do things cleanly, use \\ in Windows and / in Linux/OSX.
	'wait'      =>     3,     # How many seconds to wait before starting?
	'nosummary' =>     0,     # Don't create txt files. Useful while debugging or if you already have them.
	'nofolders' =>     0,     # Don't even create folders. Useful while debugging regexpes.
	'skipOredl' =>     1,     # Skip redownloading of non-audio files (JP101 RSS indicates wrong values for PDFs)
	'unicodize' =>     1,     # Replace illegal NTFS characters by their Unicode full-width equivalent
	'hierarchy' =>     1,     # Use the official lesson hierarchy instead of dumping everything in the same folder
	'UserAgent' =>     'iTunes/10.2.1 (Macintosh; Intel Mac OS X 10.7) AppleWebKit/534.20.8',
);

my %hierarchy = (
	# Up-to-date as of 2015-04-12. Please update this part as needed. Non-sorted items will download at the root folder.
	'0 - Introduction' => [
		# Audio
		'Culture Class: Holidays in Japan',
		'Introduction',
		'All About',
		'Japanese Culture Classes',
	],
	
	'1 - Absolute Beginner' => [
		# Audio
		'Survival Phrases Season 1',
		'Survival Phrases Season 2',
		'Newbie Season 1',
		'Newbie Season 2',
		'Newbie Season 3',
		'Newbie Season 4',
		'Newbie Season 5',
		'Absolute Beginner Season 1',
		'Absolute Beginner Season 2',
		'Top 25 Japanese Questions You Need to Know',
		'Culture Class: Essential Japanese Vocabulary',
		# Video
		'Absolute Beginner Questions Answered by Hiroko',
		'Basic Japanese',
		'Innovative Japanese',
		'Japanese Body Language and Gestures',
		'Just For Fun',
		'Kanji Videos with Hiroko',
		'Kantan Kana',
		'Learn Japanese Grammar Video - Absolute Beginner',
		'Learn with Pictures and Video',
		'Ultimate Japanese Pronunciation Guide',
		'Absolute Beginner Japanese for Every Day',
	],
	
	'2 - Beginner' => [
		# Audio
		'Beginner Season 1',
		'Beginner Season 2',
		'Beginner Season 3',
		'Beginner Season 4',
		'Beginner Season 5',
		'Beginner Season 6',
		'Lower Beginner',
		'Upper Beginner Season 1',
		# Video
		'Everyday Kanji',
		'Japanese Counters for Beginners',
		'Japanese Words of the Week with Risa for Beginners',
		'Learn with Video',
		'Video Vocab Season 1',
	],
	
	'3 - Intermediate' => [
		# Audio
		'Japanese for Everyday Life Lower Intermediate',
		'Lower Intermediate Season 1',
		'Lower Intermediate Season 2',
		'Lower Intermediate Season 3',
		'Lower Intermediate Season 4',
		'Lower Intermediate Season 5',
		'Lower Intermediate Season 6',
		'Intermediate Season 1',
		'Upper Intermediate Season 1',
		'Upper Intermediate Season 2',
		'Upper Intermediate Season 3',
		'Upper Intermediate Season 4',
		'Upper Intermediate Season 5',
		# Videos
		'iLove J-Drama',
		'Japanese Words of the Week with Risa for Intermediate Learners',
		'Journey Through Japan',
		'Learning Japanese through Posters',
		'Must-Know Japanese Holiday Words'
	],
	
	'4 - Advanced' => [
		# Audio
		'Advanced Audio Blog 1',
		'Advanced Audio Blog 2',
		'Advanced Audio Blog 3',
		'Advanced Audio Blog 4',
		'Advanced Audio Blog 5',
		'Advanced Audio Blog 6',
		# Video
		'Video Culture Class: Japanese Holidays',
	],
	
	'X - Bonus Video Courses' => [
		# Video
		'Japanese Listening Comprehension for Absolute Beginners',
		'Japanese Listening Comprehension for Beginners',
		'Japanese Listening Comprehension for Intermediate Learners',
		'Japanese Listening Comprehension for Advanced Learners',
		'Video Prototype Lessons',
	],
	
	'X - Bonus Courses' => [
		# Audio
		'Inner Circle',
		'Prototype Lessons',
		'JLPT Season 1 - Old 4/New N5',
		'JLPT Season 2 - New N4',
		'JLPT Season 3 - New N3',
		'Japanese Children\'s Songs',
		'Onomatopoeia',
		'Particles',
		'Yojijukugo',
		'Extra Fun',
	],
	
	'Z - News & Announcement' => [
		# Audio
		'Cheat Sheet to Mastering Japanese',
		'News'
	],
);

my $re_title_2P = qr/^
	(.+?)                             # Topic ($1)
	(                                 # ($2) :
	(?:\ -\ )                          # Usual separator ' - '
	|                                  # Or
	(?:\ \#\d+?[^0-9\ ]\ )             # ' #\d+[_-] ' (the ' #2: ' example)
	)
	(.+)                              # Description: everything (inc. subdescription) until... ($3)
	(?:\ -\ )                         # Usual separator
	(.*)                              # Last part (file title) ($4)
$/xmos;

my $re_title_1 = qr/^
	(.+?)                             # Topic ($1)
	(                                 # ($2) :
	(?:\ -\ )                          # Usual separator ' - '
	|                                  # Or
	(?:\ \#\d+?[[^0-9\ ]\ )            # ' #\d+[_-] ' (the ' #2: ' example)
	)
	(.+)                              # Description: everything (inc. subdescription) until... ($3)
$/xmos;

my @errors;

my %dl_list;

## Tweaking

# We want to see when the file is downloading... before the completed line (with "done") is sent to the console.
STDOUT->autoflush(1);
 
# We want to avoid "Wide character in" (print, die, ...) warnings in the console.
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';


## libwww initialization

my $ua = LWP::UserAgent->new;

# An HTTP identification is required for most files. If they ever change their "realm name" (second string), change it here too.
$ua->credentials('www.japanesepod101.com:80', 'JapanesePod101.com Premium Feed - Requires an Active Premium Subscription!', $conf{'user'}, $conf{'pass'});

# Those podcasts are supposed to be played through iTunes. So let's pretend we're iTunes to avoid looking suspicious.
# Feel free to update it too, using websites like http://udger.com/resources/ua-list/browser-detail?browser=iTunes
$ua->agent( $conf{'UserAgent'} );


## XML Parser initialization

print 'Loading RSS file (please be patient)... ';
my $xs  = XML::Simple->new();
my $ref = $xs->XMLin( $conf{'XMLFile'} );
print "done.\n";

# Uncomment the following if you need to debug the data structure. You shouldn't have to.
#use Data::Dumper;
#print Dumper( $ref->{'channel'}->{'item'} );


## Initial folder creation

# Create output folder if it doesn't exist
if( ! -f $conf{'OutDir'} )
{
	make_path( $conf{'OutDir'} ); # make_path does carp/croak by itself
}

chdir $conf{'OutDir'};


## Checks

die 'ERROR: Can\'t have a negative waiting time!' if $conf{'wait'} < 0;


## Display of the summary of what's to come

# Calculate the total size to download...
my $size_total   = 0;
my $size_session = 0;
my $filecount    = 0;
for my $item ( @{$ref->{'channel'}->{'item'}} )
{
	next if ref($item->{'title'}) eq 'HASH'; # Skip empty entries. See further down.
	$filecount++;
	$size_total += $item->{'enclosure'}->{'length'};
	if( $filecount == $conf{'dl_limit'} ) { $size_session = $size_total }
}
if(     $filecount <  $conf{'dl_limit'} ) { $size_session = $size_total }

print
      $conf{'pretend'}
        ? 'Pretending to download '
        : 'Downloading '
      ,
      $conf{'dl_limit'} > 0
        ? "the first $conf{'dl_limit'} undownloaded files out of $filecount"
        : "$filecount files"
      ,
      ".\n"
;

print 'Total download size: ',
      $conf{'dl_limit'} > 0
        ? sprintf('%.2f', ($size_session/1024)/1024) . 'MB out of ' . sprintf('%.2f', ($size_total/1024)/1024)
        : sprintf('%.2f', ($size_total/1024)/1024) . 'MB'
      ,
	  " (incorrect values if resuming).\n"
;

print "Download will start in $conf{'wait'} second" . ($conf{'wait'} > 1 ? q{s} : q{}) . ". Press Ctrl+C now to abort.\n\n";

sleep $conf{'wait'};


## Various variable initialization

my $dl_count = 0;


## The big loop to download everything

for my $item ( @{$ref->{'channel'}->{'item'}} )
{
	# Each item (PDF, Audio, ...) is processed in order
	my $title = $item->{'title'};
	
	# Skip bogus (empty) entries (title would be an empty hash instead of a string)
	next if ref($title) eq 'HASH';
	
	# Enclosure/url is the file URL : if it doesn't exist we shouldn't try to download it. 'guid' isn't always set so we don't use it.
	if( ! $item->{'enclosure'}->{'url'} )
	{
		warn "WARNING: URL not found for item $title!\n";
		next;
	}
	
	
	# Fix every mistake they made and rename for consistency
	
	# Replace multiple spaces by only one (>=480 titles)
	$title =~ s/\s{2,}/ /g;
	# Remove spaces between # and a number ('# 2' -> '#2') (>=65 titles)
	$title =~ s/#\s(\d)/#$1/g;
	# Replace not-really-dashes by dashes (>=27 titles) and not-really-quotes by quotes
	$title =~ tr/–’/-'/;
	# Add a space between number and dashes ('#2-' -> '#2 -') (>= 12 titles) and changes '#2:' to '#2 -'
	#$title =~ s/(#\d+[^\s])-/$1 -/;
	$title =~ s/(#\d+)[:\-]/$1 -/;
	# Remove leading space (>= 6 titles)
	$title =~ s/^\s(.*?)$/$1/;
	# Remove trailing space (>= 64 titles)
	$title =~ s/^(.*?)\s$/$1/;
	
	# Add "S1" to lessons without it when they have more than one or if the listing shows it.
	$title =~ s/^((?:(?:Absolute|Upper) Beginner)|(?:Audio Blog)|(?:(?:Lower )?Intermediate)|(?:Newbie)|(?:JLPT)|(?:Survival Phrases)) #/$1 S1 #/;
	$title =~ s/^((?:(?:Lower |Upper )?Intermediate Lesson)|(?:(?:Beginner|Newbie) Lesson)) #/$1 S1 #/;
	
	# Title mistakes (taking into account previous corrections)
	$title =~ s/^(Audio Blog S1 #70) - Sapporo Snow Festival/$1 - Setsubun/; # Wrong title
	$title =~ s/^(Audio Blog S1 #71) - Setsubun/$1 - Part-Time Jobs/; # Wrong title
	$title =~ s/^(Audio Blog S1 #86) - Vending Machine Evolution/$1 - Playing Grown Up/; # Wrong title
	$title =~ s/^(Audio Blog S1 #87) - Playing Grown Up/$1 - Freak of Nature/; # Wrong title
	$title =~ s/^(Audio Blog S1 #95) - The Beckoning Cat/$1 - Origami/; # Wrong title
	$title =~ s/^(Audio Blog S1 #103) - Toilets in Japan: Instructions Needed!/$1 - Halloween in Japan？/; # Wrong title
	$title =~ s/^(Lower Intermediate Lesson S2 #3 - Making the) Rug Rats/$1 Rugrats/; # Use the same term as in #4
	$title =~ s/^(Lower Intermediate Lesson S3 #[67] - How to Meet People) on Line/$1 Online/; # Use for #6 and #7 the term in #8
	$title =~ s/^(Lower Intermediate Lesson S3 #([1-4]) - First Time in an Onsen! What Should I Do？)/$1 $2/; # Number the lessons
	$title =~ s/^(Lower Intermediate Lesson S4 #[1-4] - Giving and Receiving in Japanese)-/$1 - /; # Add spaces
	$title =~ s/^(Newbie Lesson S4 #7 - )S4： (How to Say Where Things Are)/$1 $2/; # Useless 'S4: '
	$title =~ s/^(Premium Lesson #20 - SS):(16)/$1$2:/; # Misplaced ':'
	$title =~ s/^(Premium Lesson #29 - )(Do Not Drink the Water!)/$1 SS25:$2/; # They forgot the 'SS25:'
	$title =~ s/^(Survival Phrases S1 #\d+ - CSP) (\d)/$1$2/; # The others don't have a space after CSP
	$title =~ s/^(Audio Blog)/Advanced $1/; # They switched to "Advanced" in the middle
	
	$title =~ s/^(Learn with Video) S2 #20 /$1 #20 /; # There is no S2
	$title =~ s/^((?:Lower )?Beginner|Newbie|(?:(?:Lower |Upper )?Intermediate)) (S\d+) #/$1 Lesson $2 #/; # When "Lesson" is forgotten... (with S\d+)
	$title =~ s/(New JLPT N3 Prep Course) (\d)$/$1 #$2/; # When '#' is forgotten before a number
	$title =~ s/^(Advanced Audio Blog S6 #\d+ - Japanese Tourist Spots)[—\-]/$1 - /; # Missing spaces, full-width character
	$title =~ s/^(Advanced Audio Blog) (#35)/$1 S1 $2/; # They forgot to tell it was on S1
	$title =~ s/^(Beginner Lesson S4 #1[35])： - / $1 - /; # Useless ":" in lessons 13 & 15, could be fixed globally (s/(#\d+):/$1/) if this occurs more
	$title =~ s/^(Newbie Lesson S4 #13)： - / $1 - /; # Useless ":" in lesson 13
	$title =~ s/^(JLPT S1 #\d - JLPT Level 4 Last Minute Prep Course) (\d)/$1 #$2/; # In further lessons, the number is #-prefixed
	$title =~ s/^(JLPT S2 #1 - New JLPT N4 Prep Course)/$1 #1/; # They forgot the numbering for this one
	$title =~ s/^(JLPT S3 #((?:[89])|(?:1[13])) - New JLPT N3 Prep Course) \d+/$1 #$2/; # 9, 8, 11 and 13 miss the "#" # BUG
	$title =~ s/^News #52 - (JLPT Ganbatte & EnglishPod101.com!)/News #51 - $1/; # Badly numbered name
	$title =~ s/^(Wait on a Deal Like This - And Just Like Santa, It's Gone!)/News #68 - $1/; # Badly sorted name
	$title =~ s/^(Get Your 2009 Lesson Schedule Here!)/News #69 - $1/; # Badly sorted name
	$title =~ s/^(Japanese Songs #)/Japanese Children's Songs #/; # Badly sorted name
	$title =~ s/^(Happy New Year from JapanesePod101.com!)/Japanese Culture Class #58 - $1/; # Badly sorted name
	$title =~ s/^(Video Vocab Lesson #)/Video Vocab Season 1 #/; # S1, no "Lesson"
	$title =~ s/^Learning Japanese Through Poster Phrases #/Learning Japanese through Posters #/; # Badly sorted name
	$title =~ s/^(iLove Chapter [IV]+ - .*? - )iLove -/$1/; # What.
	$title =~ s/^(iLove Chapter IV - Nanase's Choice) -$/$1 - (No Subs)/; # Not '- $' because of the trailing space removal
	$title =~ s/^(Learn with Pictures and Video) S4/$1/; # There is only one season.
	$title =~ s/^(Newbie Lesson S3 #3 -)(Nihongo Dōjō)/$1 $2/; # Space missing
	$title =~ s/^(Newbie Lesson S4 #7 -) S4:/$1/; # Useless 'S4:'
	$title =~ s/^(Newbie Lesson S4 #13) -/$1/; # Useless ': ' (turned into ' - ' by earlier process)
	$title =~ s/^(Journey Through Japan #\d - .*?) - Journey Through Japan/$1/; # Useless repeat
	$title =~ s/^(Advanced Audio Blog S2 #\d+) - Tokyo Fashon Files/$1 - Tokyo Fashion Files/; # Spelling error (8 and 11)
	$title =~ s/^(Advanced Audio Blog S2 #9 - Tokyo Fashion Files #3 -)/$1 /; # Space missing (earlier process changed '#3:Men' into '#3 -Men')
	$title =~ s/^(Advanced Audio Blog S4 #25 - Top 10 Japanese Holidays:)/$1 /; # Space missing
	
	# "Japanese Culture Class" lessons are off-numbered from the 47th entry included
	if( $title =~ /^Japanese Culture Class #(\d+)/ && $1 >= 47 )
	{
		my $newnumber = $1-1;
		$title =~ s/#\d+/#$newnumber/;
	}
	
	# iLove J-Drama are sometimes numbered with latin numerals
	if( $title =~ /^iLove Chapter ([IV]+) -/ )
	{
		my %eq = ( 'I' => 1, 'II' => 2, 'III' => 3, 'IV' => 4, 'V' => 5, 'VI' => 6, 'VII' => 7, 'VIII' => '8' ); # Please complete if needed
		my $number = $eq{$1};
		$title =~ s/^(iLove Chapter)/iLove J-Drama #$number - $1/;
	}
	
	# X-Files: (when not using hierarchy)
	# "Intermediate Lesson S1 #15 - O-AIBO no Ongaeshi - Bonus"
	# "Japanese Body Language and Gestures 1 - Lesson Notes"
	# "Japanese Body Language and Gestures 1 - Video"
	# "Japanese Body Language and Gestures 2 - Lesson Notes"
	# "Japanese Body Language and Gestures 2 - Lesson Notes Lite"
	# "Japanese Body Language and Gestures 2 - Video"
	# "Journey Through Japan #1 - A Day at the Ball Park part one - Journey Through Japan"
	# "Journey Through Japan #2 - A Day at the Ball Park part two - Journey Through Japan"
	# "Kantan Kana #1 - Lesson Notes", "Kantan Kana #1 - Lesson Notes Lite" & "Kantan Kana #1 - Video" => "Kantan Kana #1： Hiragana vowels あ, い, う, え, お"
	# "Learning Japanese Through Poster Phrases #1 - Audio" # Same with #2
	# "Learning Japanese Through Poster Phrases #1 - Kanji Close-Up" # Same with #2
	# "Learning Japanese Through Poster Phrases #1 - Lesson Notes" # Same with #2
	# "Learning Japanese Through Poster Phrases #1 - Review" # Same with #2
	# "Learning Japanese Through Poster Phrases #1 - Video" # Same with #2
	# "News #81 - Do You Know Where Your Road to Success with JapanesePod101.com Begins？ - Fluency Fast"
	# "Premium Lesson #33 - O-bon Kaidan:"

	
	#$title =~ s/iLove J-Drama #/2 - iLove Chapter II
	
	
	my $path      = q{}; # Folder where to put the file
	my $filetitle = q{}; # First part of the file name (without the extension)
	my $extension = substr $item->{'enclosure'}->{'url'}, rindex( $item->{'enclosure'}->{'url'}, q{.} );
	
	
	# Title examples:
	#Learn Japanese Grammar Video - Absolute Beginner #10 - Introduction to Adjectives in Japanese - Lesson Notes
	#Beginner S6 #20 - Whenever You Have a Moment, Learn Some More Japanese! - Kanji Close-Up
	#Video Culture Class: Japanese Holidays #3 - Bean-Throwing Ceremony - Video Vocab
	#Japanese for Everyday Life Lower Intermediate #25 - Offering Your Help
	#Kantan Kana #2: Hiragana か, き, く, け, こ 
	#Advanced Audio Blog #1 - Top 10 Japanese Authors: Natsume Sōseki
	#How This Feed Works
	
	my $separator_count = 0;
	while ($title =~ /( - )|( #\d+[^ ] )/g) { $separator_count++ }
	
	#print "$separator_count - $title\n" if $separator_count != 2; # Debug line.
	
	if( $conf{'hierarchy'} )
	{
		$title =~ s/^((?:Lower |Upper )?(?:Beginner|Intermediate|Newbie|Premium)) Lesson (S\d)/$1 $2/; # These don't use the term "Lesson"
		$title =~ s/ S(\d+)/ Season $1/; # The website uses the full "Season" terminology.
		$title =~ s/^(Advanced Audio Blog) Season (\d)/$1 $2/; # AABs don't use "Season"...
		$title =~ s/^(Premium Lesson)/Extra Fun $1/;
		$title =~ s/^Japanese Culture Class #/Japanese Culture Classes #/; # Wrong name
		$title =~ s/^Kanji Video Lesson #/Kanji Videos with Hiroko #/; # Wrong name
		$title =~ s/^(JLPT Season 1) #/$1 - Old 4\/New N5 #/; # Wrong name
		$title =~ s/^(JLPT Season 2) #/$1 - New N4 #/; # Wrong name
		$title =~ s/^(JLPT Season 3) #/$1 - New N3 #/; # Wrong name
		
		BROWSE: for my $level ( sort keys %hierarchy )
		{
			for my $chapter ( @{$hierarchy{$level}} )
			{
				#                             $1         $2
				if( $title =~ /^$chapter .* - .*$/ )
				{
					my $title2 = $title;
					my $chapter2 = $chapter;
					# Using this twice is ugly, but we want to test with an unclean string and affect clean ones...
					if( $conf{'unicodize'} )
					{
						# Replace illegal characters by their full-width Unicode equivalent
						$title2   =~ tr{?*:|"<>/\\}{？＊：｜＂＜＞／＼};
						$chapter2 =~ tr{?*:|"<>/\\}{？＊：｜＂＜＞／＼};
					}
					else
					{
						# Replace illegal characters
						$title2   =~ s/[?:"*<>|\/]/$conf{'fallback'}/g;
						$chapter2 =~ s/[?:"*<>|\/]/$conf{'fallback'}/g;
					}
					
					$title2 =~ /^(?:$chapter2) (.*)(?: - )(.*)$/;
					my $lesson = $1;
					$path = $level.$conf{'separator'}.$chapter2.$conf{'separator'}.$lesson;
					$filetitle = $2;
					last BROWSE;
				}# else { print "--> $title | $chapter\n" }
			}
		}
	}
	
	# We also put this here for non-hierarchy
	if( $conf{'unicodize'} )
	{
		# Replace illegal characters by their full-width Unicode equivalent
		$title =~ tr{?*:|"<>/\\}{？＊：｜＂＜＞／＼};
	}
	else
	{
		# Replace illegal characters
		$title =~ s/[?:"*<>|\/]/$conf{'fallback'}/g;
	}
	
	if( ! $path ) # When hierarchy isn't used or if it failed to create a path
	{
		print "WARNING: Can't sort $title\n" if $conf{'hierarchy'};
		# Case for 3+ elements (premium RSS) in the title
		if( $separator_count >= 2 && $title =~ $re_title_2P )
		{
			$path = $1.$2.$3;
			$filetitle = $4;
		}
		# Case for 2 elements (free RSS)
		elsif( $separator_count == 1 && $title =~ $re_title_1 )
		{
			$path = $1.$2.$3;
			
			if( $extension eq '.mp3' )
			{
				$filetitle = 'Audio';
			}
			elsif( $extension eq '.m4v' )
			{
				$filetitle = 'Video';
			}
		}
		# Case for 1 element
		elsif( $separator_count == 0 )
		{
			$filetitle = $title;
		}
		else
		{
			warn "WARNING: Unsupported title format $title! ($separator_count separators detected)\n";
			next;
		}
	}
	
	# If a path ends with "..." in Windows, the dots dissapear. Yup.
	$path =~ s/\.\.\.$/…/;

	if( !($conf{'nofolders'}) && !(-d $path) )
	{
		# The working directory is already OutDir since the earlier chdir
		make_path( $path ) or warn "WARNING: Folder $path couldn't be created!\n";
	}
	
	my $t = Time::Piece->strptime( $item->{'pubDate'}, '%a, %d %b %Y %T %z' ); # Mon, 12 Dec 2011 18:30:00 +0900 # http://www.unix.com/man-page/FreeBSD/3/strftime/

	if( !($conf{'nosummary'}) && $item->{'itunes:summary'} )
	{
		my $summarylength = length($item->{'itunes:summary'});
		my $skip = 0;
		$skip++ if $summarylength <= 306; # "In this global economy, it\'s important to never burn bridges, and more importantly, give yourself as many opportunities as possible! And Innovative Language Learning has the key to opening those doors! The more languages you know, the more opportunities you will have - both personally and professionally." # See at the end for the other useless summaries
		
		#print "\n$item->{'itunes:summary'}\n_______________________________________\n"
		$skip++ if $summarylength == 321; # "Learn Japanese with JapanesePod101!\nDon't forget to stop by JapanesePod101.com for more great Japanese Language Learning Resources!\n\n-------Lesson Dialog-------\n\n---------------------------\nLearn Japanese with JapanesePod101!\nDon't forget to stop by JapanesePod101.com for more great Japanese Language Learning Resources!" # "Empty"
		$skip++ if $summarylength == 322; # "Learn Japanese with JapanesePod101!\nDon't forget to stop by JapanesePod101.com for more great Japanese Language Learning Resources!\n\n----Vocabulary & Phrases---\n\n\n---------------------------\nLearn Japanese with JapanesePod101!\nDon't forget to stop by JapanesePod101.com for more great Japanese Language Learning Resources!\n" # "Empty"
		$skip++ if $summarylength == 323; # "Learn Japanese with JapanesePod101!\nDon\'t forget to stop by JapanesePod101.com for more great Japanese Language Learning Resources!\n\n-------Lesson Dialog-------\n\n---------------------------\nLearn Japanese with JapanesePod101!\nDon\'t forget to stop by JapanesePod101.com for more great Japanese Language Learning Resources!" # Most common "empty"
		$skip++ if $summarylength == 324; # "Learn Japanese with JapanesePod101!\nDon\'t forget to stop by JapanesePod101.com for more great Japanese Language Learning Resources!\n\n----Vocabulary & Phrases---\n\n\n---------------------------\nLearn Japanese with JapanesePod101!\nDon\'t forget to stop by JapanesePod101.com for more great Japanese Language Learning Resources!" # "Empty"
		
		my $summarypath = $conf{'OutDir'}.$conf{'separator'}.$path.$conf{'separator'}.$filetitle.'.txt';
		
		if( !($skip) && ( !(-e $summarypath) || $conf{'overwrite'} ) ) # If you don't skip and the path doesn't exist or you overwrite...
		{
			my $summarytext = $item->{'itunes:summary'};
			   $summarytext =~ s/\\'/'/g;
			
			my $summary;
			   $summary = IO::File->new( $summarypath, '>:utf8' ) or die "Couldn't open $summarypath for writing: $!";
			   $summary->binmode( ':encoding(UTF-8)' ); # To avoid "Wide character in print" warnings
			   $summary->print( $summarytext );
			   $summary->close();
			
			utime $t->epoch, $t->epoch, $summarypath;
		}# else { print "$skip $summarylength $summarypath\n" } # Uncomment this to debug if summaries aren't written
	}
	
	my $filepath = $conf{'OutDir'}.$conf{'separator'}.$path.$conf{'separator'}.$filetitle.$extension;
	
	if( ! exists $dl_list{$filepath} )
	{
		$dl_list{$filepath} = { 'url' => $item->{'enclosure'}->{'url'}, 'length' => $item->{'enclosure'}->{'length'}, 'date' => $t->epoch };
	}
	else
	{
		if( $dl_list{$filepath}->{'url'} eq $item->{'enclosure'}->{'url'} )
		{
			if( $dl_list{$filepath}->{'length'} == 1 && $item->{'enclosure'}->{'length'} > 1 )
			{
				print "WARNING: Entry '$filepath' already exists with same URL " . $item->{'enclosure'}->{'url'} .
				    " but with a good size... replacing the old one.\n";
				
				$dl_list{$filepath} = { 'url' => $item->{'enclosure'}->{'url'}, 'length' => $item->{'enclosure'}->{'length'}, 'date' => $t->epoch };
			}
			elsif( $dl_list{$filepath}->{'length'} > 1 && $item->{'enclosure'}->{'length'} == 1 )
			{
				print "WARNING: Entry '$filepath' already exists with same URL " . $item->{'enclosure'}->{'url'} .
				    " but with a bogus size... skipping.\n";
			}
			else # Size of "1" in both cases, or different sizes
			{
				print "WARNING: Entry '$filepath' already exists with same URL " . $item->{'enclosure'}->{'url'} .
				    "... skipping.\n";
			}
		}
		else
		{
			print "WARNING: Entry '$filepath' already exists with different URL " . $item->{'enclosure'}->{'url'} .
			    " VS previous " . $dl_list{$filepath}->{'url'} . "... skipping.\n";
		}
		 
	}
	
	if( $conf{'dl_limit'} > 0 && $dl_count == $conf{'dl_limit'} )
	{
		print "Reached the limit of files to download ($dl_count out of $conf{'dl_limit'}).\n";
		last;
	}
}

if( ! $conf{'pretend'} )
{
	my @sorted_paths = Unicode::Collate::->new->sort(keys %dl_list);
	for my $filepath ( @sorted_paths )
	{
		my $proceed = 0;
		if( -e $filepath )
		{
			my $filesize = (stat $filepath)[7];
			
			if( $filesize != $dl_list{$filepath}->{'length'} )
			{
				if( $conf{'skipOredl'} && substr($filepath,-4) eq '.pdf' )
				{
					warn "WARNING: Skipping redownload of $filepath...\n";
				}
				else
				{
					warn "WARNING: $filepath already exists but with size $filesize instead of ".$dl_list{$filepath}->{'length'}."... overwriting.\n";
					$proceed++;
				}
			}
			
			if( $conf{'overwrite'} )
			{
				$proceed++;
			}
		}
		else # ...if the file doesn't exist
		{
			$proceed++;
		}
		
		if( $proceed )
		{
			print "Downloading $filepath... ";
			my $response = $ua->get(
				$dl_list{$filepath}->{'url'},
				':content_file'   => $filepath,
				':read_size_hint' => $dl_list{$filepath}->{'length'},
			);
			
			if( ! $response->is_success )
			{
				print "Error downloading $dl_list{$filepath}->{'url'}! " . $response->status_line . "\n";
				push @errors, "$dl_list{$filepath}->{'url'} -> $filepath (" . $response->status_line . ")\n";
			}
			
			utime $dl_list{$filepath}->{'date'}, $dl_list{$filepath}->{'date'}, $filepath;
			
			print "done\n";
			
			$dl_count++;
			
			sleep $conf{'throttle'};
		}
	}
}

if( @errors )
{
	print "Summary of errors:\n";
	print for @errors;
}

__END__

# For your viewing pleasure, the list of summaries that won't be written to disk:
#$skip++ if $summarylength <= 15; # "##PostExcerpt##"
#$skip++ if $summarylength <= 47; # "Stop by JapanesePod101.com and leave us a post!"
#$skip++ if $summarylength <= 51; # "Taking a closer look at Kanji (Chinese characters)."
#$skip++ if $summarylength <= 58; # "Stop by JapanesePod101.com and be sure to leave us a post!"
#$skip++ if $summarylength <= 72; # "Happy Birthday JapanesePod101.com!! Stop by the site to leave us a post!"
#$skip++ if $summarylength <= 75; # "Stop by JapanesePod101.com for more great Japanese Language Learning tools!"
#$skip++ if $summarylength <= 76; # "Stop by JapanesePod101.com for the accompanying PDFs, bonus track, and more!"
#$skip++ if $summarylength <= 78; # "Stop by JapanesePod101.com for more great Japanese language learning material."
#$skip++ if $summarylength <= 80; # "Stop by JapanesePod101.com to download the video and be sure to leave us a post!" 
#$skip++ if $summarylength <= 83; # "Stop by JapanesePod101.com for the accompanying PDFs, Japanese subtitles, and more!"
#$skip++ if $summarylength <= 90; # "Be sure to stop by JapanesePod101.com for more great Japanese Language Learning resources."
#$skip++ if $summarylength <= 94; # "Learn Japanese with JapanesePod101.com! Stop by JapanesePod101.com for the accompanying video!"
#$skip++ if $summarylength <= 100; # "Stop by JapanesePod101.com to download the video, accompanying PDFs, and be sure to leave us a post!"
#$skip++ if $summarylength <= 104; # "Stop by JapanesePod101.com for more details about our open content call, and be sure to leave us a post!"
#$skip++ if $summarylength <= 105; # "Stop by JapanesePod101.com to find out more about our growing community, and  be sure to leave us a post."
#$skip++ if $summarylength <= 111; # "Stop by JapanesePod101.com for the accompanying PDFs, line-by-line audio, and more! Be sure to leave us a post!"
#$skip++ if $summarylength <= 118; # "Stop by JapanesePod101.com for Lesson Notes, and test yourself in the Learning Center! And be sure to leave us a post!"
#$skip++ if $summarylength <= 133; # "Stop by JapanesePod101.com and be sure to leave us a post!\nHappy New Year from everyone at JapanesePod101.com!\nよいお年を！・Yoi otoshi o!"
#$skip++ if $summarylength <= 134; # "Learn Japanese with JapanesePod101.com! After listening, stop by JapanesePod101.com and be sure to leave us a post!\n\n★☆★☆★☆★☆★☆★☆★☆★"
#$skip++ if $summarylength <= 135; # "Learn Japanese with JapanesePod101!\nDon\'t forget to stop by JapanesePod101.com for more great Japanese Language Learning Resources!\n"
#$skip++ if $summarylength <= 141; # "Learn Japanese with JapanesePod101!\nDon\'t forget to stop by JapanesePod101.com for more great Japanese Language Learning Resources!\n\n\n\n"
#$skip++ if $summarylength <= 144; # "Happy New Year to all our listeners!\n\nStop by JapanesePod101.com to find out more about our growing community, and be sure to leave us a post."
#$skip++ if $summarylength <= 151; # "Stop by JapanesePod101.com and check our newest feature Video User Guide, which walks you through JapanesePod101.com's Lesson Specific Learning Center."
#$skip++ if $summarylength <= 154; # "Stop by http://www.japanesepod101.com/ for the most comprehensive, user friendly, helpful, and interactive language learning resource on the internet!\n\n"
#$skip++ if $summarylength <= 181; # "Stop by JapanesePod101.com for the accompanying PDF and transcripts!  If you enjoy the intros and getting a behind the scenes look at JapanesePod101.com, you won\'t wanna miss this!"
#$skip++ if $summarylength <= 205; # "The release of JapanesePod101.com version 2!! This is big news that you absolutely can't miss! Stop by JapanesePod101.com and check out the new page, sign up for a 7-Day Free Trial, and leave us a comment!"
#$skip++ if $summarylength <= 219; # "Happy New Year from Asakusa, Tokyo!  Today we release  some of the video footage from our visit to Asakusa Temple on New Year's Day. Meet Peter from the show and his one-kind-friend Ryo. This guy you don't want to miss."
#$skip++ if $summarylength <= 247; # "Increase Vocabulary and Phrases!\n\nThere is a reason we have all used flashcards at some point in our studies. The bottom line is they WORK. At http://www.japanesepod101.com/, we understand this, and offer flashcards for all levels of your study.\n\n"
#$skip++ if $summarylength <= 251; # "Learn Japanese with podcasts and Videocasts! Yes, Japanesepod101.com videocasts are back and better than ever. Today we introduce you to the Japanese taxi, which we covered in Survival Phrases #5. This is some rare footage that you don't want to miss!"
#$skip++ if $summarylength <= 255; # "Stop by JapanesePod101.com for the accompanying PDFs, line-by-line audio, and more! Be sure to leave us a post!\n\nStop by JapanesePod101.com for the most comprehensive, user-friendly, entertaining and interactive language learning resource on the Internet"
#$skip++ if $summarylength <= 258; # "Stop by JapanesePod101.com for the accompanying PDFs, line-by-line audio, and more! Be sure to leave us a post!\n\n\nStop by JapanesePod101.com for the most comprehensive, user-friendly, entertaining and interactive language learning resource on the Internet"
#$skip++ if $summarylength <= 276; # "Don\'t let another once in a lifetime opportunity pass you by! Go to www.innovativelanguage.com/FFC by midnight EST on July 26th to become a Founding Father of ThaiPod, CantoneseClass, PolishPod, GreekPod, and/or PortuguesePod101.com, and guarantee yourself 50% OFF forever!\n"
#$skip++ if $summarylength <= 285; # "Explore Japanese and Japanese Culture with Fellow Students!\n\nEngage with fellow learners and teachers and ask language related questions, culture related questions, and even leave lesson or feature requests. It is by far the most active and vibrant forum on Japanese on the Internet!\n\n"
#$skip++ if $summarylength <= 286; # "Stop by JapanesePod101.com for the accompanying PDFs, line-by-line audio, and more! Be sure to leave us a post!\n\n-------------------------\n\nStop by JapanesePod101.com for the most comprehensive, user-friendly, entertaining and interactive language learning resource on the Internet!"
#$skip++ if $summarylength <= 287; # "Improve Pronunciation, Fluency!\n\nDrastically improve your pronunciation with the voice recording tool in the premium learning center. Record your voice with a click of a button, and playback what you record just as easily. This tool is the perfect complement to the line-by-line audio.\n\n"
#$skip++ if $summarylength <= 292; # "Stop by JapanesePod101.com for the accompanying PDFs, line-by-line audio, and more! Be sure to leave us a post!\n\n-------Lesson Dialog-------\nJapanese\n\n\n----Formal English----\n\n\n---------------------------\nStop by JapanesePod101.com for the Fastest, Easiest and Most Fun Way to Learn Japanese!"
#$skip++ if $summarylength <= 302; # "Stop by JapanesePod101.com for the accompanying PDFs, line-by-line audio, and more! Be sure to leave us a post!\n\n-------Lesson Dialog-------\nJapanese\n\n\n----Formal English----\n\n\n---------------------------\nStop by JapanesePod101.com for the Fastest, Easiest and Most Fun Way to Learn Japanese!"


XML example, two items :
_______
<item>
	<title>Lower Intermediate Lesson #46 - Mothers' Talk - Lesson Notes</title>
	<pubDate>Thu, 11 Sep 2014 18:29:59 +0900</pubDate>
	<guid>http://www.japanesepod101.com/premium_feed/pdfs/601_LI46_101807_jpod101.pdf</guid>
	<enclosure url="http://www.japanesepod101.com/premium_feed/pdfs/601_LI46_101807_jpod101.pdf" length="170903" type="application/pdf"/>		<itunes:author>JapanesePod101.com</itunes:author>
	<itunes:explicit>No</itunes:explicit>
	<itunes:block>No</itunes:block>
	<itunes:duration>1:00</itunes:duration>
</item>

<item>
	<title>Lower Intermediate Lesson #46 - Mothers' Talk - Audio</title>
	<pubDate>Thu, 11 Sep 2014 18:30:00 +0900</pubDate>
	<guid>http://media.libsyn.com/media/japanesepod101/601_LI46_101807_jpod101.mp3</guid>
	<enclosure url="http://media.libsyn.com/media/japanesepod101/601_LI46_101807_jpod101.mp3" length="7469804" type="audio/mpeg"/>
	<itunes:summary>Learn Japanese with JapanesePod101!
Don\'t forget to stop by JapanesePod101.com for more great Japanese Language Learning Resources!

-------Lesson Dialog-------

----Formal ----
[...text...]
---------------------------
Learn Japanese with JapanesePod101!
Don\'t forget to stop by JapanesePod101.com for more great Japanese Language Learning Resources!</itunes:summary>	<itunes:author>JapanesePod101.com</itunes:author>
	<itunes:explicit>No</itunes:explicit>
	<itunes:block>No</itunes:block>
	<itunes:duration>14:48</itunes:duration>
</item>
_______
Here the folder would be "Lower Intermediate Lesson #46 - Mothers' Talk", with files "Audio.mp3", "Audio.txt" (<itunes:summary>) and "Lesson Notes.pdf".