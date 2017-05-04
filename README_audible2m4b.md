## `audible2m4b.sh`

The `audible2m4b.sh` tool converts Audible's AAX files in the `srcdir` into the 
AAC format and stores them to the `targetdir` directory.

The directory structure present in `srcdir` is preserved, i.e. it is possible
to copy a directory containing several audiobooks into `srcdir` and the
`targetdir` will contain the same directory structure containing the M4B files.

### Motivation

Just curiosity (and to see whether ffmpeg's -activation_bytes parameter really works).

### Usage
```
./audible2m4b.sh [-v] srcdir targetdir
 
-v means verbose, which will produce verbose output on stdout.

srcdir is the directory holding the audible aax files.

targetdir is where the audiobook files will be written to.
```

### Gotchas
You should update the configuration options in the script to meet your environment.

### Example
```
./audible2m4b.sh -v /the/srcdir "/the/target directory"   
```

### Known issues
None.

### Limitations
It is an ugly hack.
