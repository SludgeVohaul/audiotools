## `flac2m4a.sh`

The `flac2m4a.sh` tool converts FLAC files in the `srcdir` into the AAC format
and stores them to the `targetdir` directory.

The directory structure present in `srcdir` is preserved, i.e. it is possible
to copy an artist directory (containing several albums) into `srcdir` and the
`targetdir` will contain the same directory structure containing the M4A files.

### Motivation

This is just a quick hack to get some music played on a Ford SYNC2 multimedia system.
My audio files are in FLAC on a NAS but SYNC2 does not play FLAC. MP4 containers 
with AAC are played fine on SYNC2.

To copy new songs onto the USB stick used in the car, I basically do this:
```
cd audiotools; ssh freenas01 "cd /path/to/artist; tar cf - album" | tar xf - -C srcdir; ./flac2m4a srcdir targetdir; mv targetdir/* /path/to/usbstick
```

### Usage
```
./flac2m4a.sh [-v] [-b cbr|vbr ] [-m] [-s] [-p] srcdir targetdir
 
-v means verbose, which will output the ffmpeg commands on stdout.

-b toggles between constant and variable bitrate. Default is CBR.

-m fixes the original metadata before it is added to the target file.
   The implemented code is just an example (for my real life problem).
   See the script source.

-s fixes SYNC2's brain dead alphabetic play order to track order (Ford's SYNC2
   ignores track numbers and plays the tracks sorted alphabetically by their name).
   The only solution seems to be to prepend the track to the title, e.g.
   'Some Title' -> '03 Some Title'.

-p creates an m3u playlist named as the album in the album's directory. This is 
   the second way to fix the SYNC2 behavior.

srcdir is the directory with the FLAC files.

targetdir is the directory where the M4A files will be stored.
```

### Gotchas
The FLAC files should be tagged. Theres is no way to provide an additional file
containing the tags, or similar.

You should update the configuration options in the script to meet your environment.

### Example
```
./flac2m4a.sh -v -m -s srcdir "/the/target directory"   
```

### Known issues
The example for the -f parameter described in the script is probably obsolete,
as ffmpeg in version git-2017-02-11-25d9cb4 detects the invalid ID3 tags already.

When aborted (e.g. File exists. Overwrite? No) the tempdir is not cleaned up.

Error handling is rather rare...

### Limitations
Function logrun() (used for verbose output) will not log redirects, should they
ever be used.
All in all it is an ugly hack.
