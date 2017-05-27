## flac2m4a.sh

The `flac2m4a.sh` tool converts FLAC files in `srcdir` into the AAC format
and stores them in a MP4 container in `targetdir`.

The directory structure in `srcdir` (e.g multiple artist directories
containing multiple album directories) is preserved in `targetdir`.

### Motivation

This is just a quick hack to get some music played on the Ford SYNC2 multimedia system.
My audio files are in FLAC on a NAS but SYNC2 does not play FLAC. MP4 containers
with AAC though, are played fine.

To copy new songs onto a USB stick for use in the car, I basically do this:
```bash
ssh freenas01 "cd /path/to/the\ artist; tar cf - the\ album" | tar xf - -C /path/to/srcdir/MyMusic && /path/to/flac2m4a.sh -vrq /path/to/srcdir /path/to/usbstick
```

### Usage
```
./flac2m4a.sh [-v] [-b cbr|vbr ] [-m] [-t] [-p|q] [-r] [-j] [-x] srcdir targetdir

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
   found in the source files.
   The directory separator is / (e.g. Ramones/Leave Home/07 Pinhead.m4a).
   Memory hook: p - the upper right side is "heavier", the letter would buckle
   to the right: | -> /
   Cannot be used together with -q.

-q same as -p except for the directory separator being \ and the paths starting
   with \ (e.g. \Ramones\Leave Home\07 Pinhead.m4a).
   Such a playlist (an extended M3U playlist probably too) is another way
   to fix the SYNC2 play order behaviour.
   Memory hook: q - the upper left side is "heavier" and would buckle to
   the left: | -> \
   Cannot be used together with -p.

-r resizes cover art images to the value defined in the script if necessary.

-j writes a job summary to stdout and exists.

-x processes only one second of each audiofile. This is intended for testing
   whether everything works as expected.

srcdir is the directory with the FLAC files.

targetdir is the directory where the M4A files are created.


Always use double quotes around names with spaces, or things won't work.
```

### Playlists
Playlists can be created with either the `-p` or `-q` parameter. Their naming
schema is '`<artist tag> <album tag>.m3u`'.
The playlists contain all audio files found in `srcdir` having identical
artist and album tags.
The paths to the audio files are relative to `targetdir`.

If you have your audio files in e.g. `...\My Documents\My Music` and want to
store the playlists in `...\My Documents`, then manually create a directory
called `My Music` below `srcdir`, copy the source files into the created
`My Music` directory, and start the script with `srcdir` and `targetdir`. The
playlists will be created in `targetdir`, with relative paths to
`My Music/.../...` (or `\My Music\...\...`).
Then copy the playlist files to `...\My Documents`


### Cover Art
Cover art is automatically embedded into the converted files when either of
these two conditions is met:

* The source file has already cover art embedded.
* The directory in `srcdir` where the source file is located contains an
  image file. The image file's name is configurable in the script.

### Gotchas
The FLAC files should be tagged. Untagged files may lead to undesired results
when creating playlists.

Creating playlists with `-p` or `-q` might fail as the title tags might contain
characters which cannot be used in filenames.

You should update the configuration options in the script to meet your environment.

You should always work with a copy of your files - if things go wrong and your
files get corrupted you can blame me or whomever, but your files will still be gone...

### Ford SYNC2
The `-m`, `-q` and `-r` parameters are probably relevant to Ford SYNC2 users
only (or maybe other jinxes, using the same ingenious media software).
These are my observations:

* The media player expects the playlists to be located in the top level
directory of the device (i.e. if you mount your USB stick in Windows under
`X:\` then a playlist needs to be accessible through `X:\some_playlist.m3u`.
The audio files can be located in subdirectories e.g. `X:\My Music\Ramones\...`.
* Directory separators must be `\` (backslash) **not** `/` (slash).
* The relative path must start with a `\`
* Playlists located in an album's directory seem to break SYNC2's indexing
process. If you have such playlists, audio files won't be indexed correctly
(meaning not at all, even those in other directories).
* The media player seems to handle `LF` as well as `CRLF` newlines (.i.e.
playlists can be created under Windows as well as Unix-like OSes).
* The cover art is limited to 500x500px. Though I have successfully
imported files with much higher resolutions into SYNC2, there were always a
few files where the cover art was not displayed. The technical parameters of
the working and non working files were the same - the FLAC files have been
created with the same parameters (CD rip), the M4A files too. Embedding the
image from the working file into the other one did not work either.
Only using cover art images with not more than 500x500px seems to work.

### Examples
```bash
./flac2m4a.sh -vvvprb vbr relative/path/in /some/path/out
```

or

```bash
./flac2m4a.sh -v -r -v -v -b vbr -p relative/path/in /some/path/out
```

Result:

* Level 3 output (error/warnings, processed files, cover art, metadata,
  playlists, executed commands).
* Uses variable bitrate
* Creates unix-style playlists
* Resizes cover art files (located in the album directory or embedded
  in source files) if either their width or height exceed the defined
  (in the script) max. number of pixels.
* Searches for FLAC files in the `in` directory below the current directory.
* Creates M4A files in the `/some/path/out` directory.

### Known issues
The example for the -m parameter described in the script is probably obsolete,
as ffmpeg at least in version `git-2017-02-11-25d9cb4` detects the invalid ID3
tags already.

When aborted (e.g. File exists. Overwrite? No) the `tempdir` (and eventually
the `*.m3u.tmp` files) are not cleaned up.

Temporary files created by AtomicParsley are not deleted (yet).

Error handling is rather rare...

### Limitations
Encoding of gapless songs results in a gap. It seems to be not possible with
`ffmpeg` and the `libfdk_aac` AAC library (as I have not found a way to 
create the `iTunSMPB` tag).

Function `logRun()` (used for logging the executed commands) will not log
redirects (or pipes).

If the cover art image from a file's source directory is to be used and
needs to be resized (`-r` paramter), then it is resized for each file again,
instead of resizing it only once for all files of the directory.

All in all it is an ugly hack.
