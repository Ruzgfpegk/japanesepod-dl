# japanesepod-dl
Perl script to download the contents of JapanesePod101.com RSS files in a clean folder hierarchy.

Change the configuration values in the %conf hash and run it.

Only works in Linux (and probably other Unixes) due to Unicode problems in some modules in Windows.

Read the beginning of the script to know more.

Modules used:
- IO::File
- File::Path
- Time::Piece
- Unicode::Collate
- LWP::UserAgent
- XML::Simple