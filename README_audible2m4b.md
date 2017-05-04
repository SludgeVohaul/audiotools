## audible2m4b.sh

The `audible2m4b.sh` tool converts Audible's AAX files in the `srcdir` into the 
AAC format and stores them in the `targetdir` directory.

The directory structure present in `srcdir` is preserved, i.e. it is possible
to copy multiple directories containing with audiobooks into `srcdir` and the
`targetdir` will contain the same directory structure containing the M4B files.

### Motivation

Just curiosity (and to see whether ffmpeg's -activation_bytes parameter really works).

### Usage
```
./audible2m4b.sh [-v] srcdir targetdir
 
-v means verbose, which will output the shell commands on stdout.

srcdir is the directory with the AAX files.

targetdir is the directory where the M4B files will be stored.
```

### Gotchas
You should update the configuration options in the script to meet your environment.

### Example
```
./audible2m4b.sh -v srcdir "/the/target directory"   
```

### Known issues
When aborted (e.g. File exists. Overwrite? No) the tempdir is not cleaned up.

Error handling is rather rare…

### Limitations
It is also an ugly hack.
