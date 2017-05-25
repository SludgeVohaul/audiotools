## audible2m4b.sh

The `audible2m4b.sh` tool converts Audible's AAX files in the `srcdir` into the
AAC format and stores them in a MP4 container in the `targetdir` directory.

The directory structure in `srcdir` (e.g multiple directories
containing multiple audiobooks) is preserved in `targetdir`.

### Motivation

Just curiosity (and to see whether ffmpeg's `-activation_bytes` parameter really works).

### Usage
```
./audible2m4b.sh [-v] [-j] [-x] srcdir targetdir

-v increases the verbosity level. A higher level means more output to stdout.
   Level 0: Warnings and errors only.
   Level 1: Processed files.
   LeveL 2: Processing of cover art and temp file deletions.
   Level 3: Executed commands.

-j writes a job summary to stdout and exits.

-x processes only 1s of each audiofile. This is intended for testing whether
   everything works as expected.

srcdir is the directory with the AAX files.

targetdir is the directory where the M4B files are created.

Always use double quotes around names with spaces, or things won't work.
```

### Gotchas
You should update the configuration options in the script to meet your environment.

### Examples
```bash
./audible2m4b.sh -vvvx vbr relative/path/in /some/path/out
```

or

```bash
./flac2m4a.sh -v -x -v -v relative/path/in /some/path/out
```

Result:

* Level 3 output (error/warnings, processed files, cover art, executed commands).
* Creates M4B files with 1s length.
* Searches for AAX files in the `in` directory below the current directory.
* Creates M4B files in the `/some/path/out` directory.

### Known issues
When aborted (e.g. File exists. Overwrite? No) the `tempdir` is not cleaned up.

Error handling is rather rare...

### Limitations
It is an ugly hack.
