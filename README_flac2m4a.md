## flac2m4a.sh

The `flac2m4a.sh` tool converts FLAC files in the `srcdir` into the AAC format
and stores them in the `targetdir` directory.

The directory structure present in `srcdir` (e.g multiple artist directories
containing multiple album directories) is preserved in the `targetdir`.

### Motivation

This is just a quick hack to get some music played on the Ford SYNC2 multimedia system.
My audio files are in FLAC on a NAS but SYNC2 does not play FLAC. MP4 containers
with AAC though, are played fine.

To copy new songs onto a USB stick for use in the car, I basically do this:
```bash
ssh freenas01 "cd /path/to/the\ artist; tar cf - the\ album" | tar xf - -C /path/to/srcdir/MyMusic && /path/to/flac2m4a.sh -vq /path/to/srcdir /path/to/usbstick
```

### Usage
```
./flac2m4a.sh [-v] [-b cbr|vbr ] [-m] [-t] [-p|q] [-j] [-x] srcdir targetdir

-v increases the verbosity level. A higher level means more output to stdout.
   Level 0: Warnings and errors only.
   Level 1: Transcoded files.
   LeveL 2: Info about cover art, metadata, playlists,...
   Level 3: Executed commands

-b toggles between constant and variable bitrate. Default is CBR.

-m fixes the original metadata before it is added to the target file.
   The implemented code is just an example (for my real life problem).
   See the script source for more information.

-t Ford's SYNC2 ignores track numbers and plays the tracks sorted
   alphabetically by their title tag.
   The switch fixes SYNC2's brain dead alphabetic play order to track order by
   adding the track number to the title tag ('Some Title' -> '03 Some Title').

-p creates simple m3u playlists in targetdir named by the artist and album tags
   found in the converted files.
   The playlists contain paths to all audio files with the same artist and
   album tags, independent of the directory they are located in.
   The paths to the converted audio files are be relative to the targetdir,
   the directory separator is / (e.g. Ramones/Leave Home/07 Pinhead.m4a).
   Memory hook: p - the upper right side is "heavier", the letter would buckle
   to the right: | -> /
   Cannot be used together with -q.

-q same as -p except the directory separator is \ and the paths also start
   with \ (e.g. \Ramones\Leave Home\07 Pinhead.m4a)
   Such a playlist (an extended M3U playlist probably too) is the second way
   to fix the SYNC2 play order behaviour.
   Memory hook: q - the upper left side is "heavier" and would buckle to
   the left: | -> \
   Cannot be used together with -p.

-j writes a job summary to stdout.

-x converts only one second of each audiofile. This is intended for testing
   whether everything works as expected.

srcdir is the directory with the FLAC files.

targetdir is the directory where the M4A files are created.

Always use double quotes around names with spaces, or things won't work.
If you have your audio files in e.g. MyDocuments\MyMusic and want to store the
playlists in MyDocuments, then manually create a directory called MyMusic
below targetdir, and copy the source files in there. Playlists will be created
in targetdir, with the relative path MyMusic/Ramones/...
```

### Gotchas
The FLAC files should be tagged. Untagged files may lead to undesired results
when creating playlists.

Creating playlists with -p or -q might fail as the title tags might contain
characters which cannot be used in filenames.

You should update the configuration options in the script to meet your environment.

You should always work with a copy of your files - if things go wrong and your
files get corrupted you can blame me or whomever, but your files will still be gone...

### Ford SYNC2
The `-m` and `-q` options are relevant to Ford SYNC2 users only (or maybe other
jinxes too, who have the same ingenious media software in their cars).
These are my observations:

* The media player expects the playlists to be located in the top level
directory of the device (i.e. if you mount your USB stick in Windows under
`X:\` then a playlist needs to be accessible through `X:\some_playlist.m3u`.
The audio files can be located in subdirectories e.g. `X:\MyFiles\Ramones\...`.
* Directory separators must be `\` (backslash) **not** `/` (slash).
* The relative path must start with a `\`
* Playlists located in an album's directory seem to break SYNC2's indexing
process. If you have such playlists, audio files won't be indexed correctly
(meaning not at all, even those in other directories).
* The media player seems to handle `LF` as well as `CRLF` newlines (.i.e.
playlists can be created under Windows as well as Unix-line OSes).
* The album art is limited to 500x500px. Though I have successfully
imported files with much higher resolutions into SYNC2, there were always a
few files where the album art was not displayed. The technical parameters of
the working and non working files were the same - the FLAC files have been
created with the same parameters (CD rip), the M4A files too. Embedding the
image from the working file into the other one did not work either.
Only using album art with not more than 500x500px seems to work.

### Examples
```bash
flac2m4a.sh -vvvpb vbr in out
```

or

```bash
flac2m4a.sh -v -v -v -b vbr -p in out
```

Result:

* Logs error/warings, transcoded files, cover art, metadata, playlists,
  executed commands.
* Uses variable bitrate
* Creates unix-style playlists
* Searches for FLAC files in the `in` directory below the current directory.
* Creates M4A files in the `out` directory below the current directory.


### Known issues
The example for the -m parameter described in the script is probably obsolete,
as ffmpeg at least in version `git-2017-02-11-25d9cb4` detects the invalid ID3
tags already.

When aborted (e.g. File exists. Overwrite? No) the `tempdir` (and eventually
the `*.m3u.tmp` files) are not cleaned up.

Error handling is rather rare...

### Limitations
Function `logRun()` (used for logging the executed commands) will not log 
redirects (or pipes), should they ever be used.
All in all it is an ugly hack.
