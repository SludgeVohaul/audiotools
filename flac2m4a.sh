#!/bin/bash
set -e
set -u

# Cannot use /bin/sh due to process substitution in run().

VERSION="20170601"

# It seems to be impossible to add coverart to aac encoded streams in an MP4
# container via ffmpeg. Therefore I use AtomicParsley.
# If it is not present the coverart image will not be written to the output
# file, but everything will be fine otherwise.
ATOMICPARSLEY=/usr/local/bin/AtomicParsley
# See AtomicParsley --longhelp
ATOMICPARSLEY_PIC_OPTIONS="DPI=72:removeTempPix"

FIND=/usr/bin/find
MKDIR=/bin/mkdir
RM=/bin/rm
CP=/bin/cp
MV=/bin/mv
SORT=/usr/bin/sort
GREP=/usr/bin/grep
SED=/usr/bin/sed
PWD=/bin/pwd
BASENAME=/usr/bin/basename
FILE=/usr/bin/file
TR=/usr/bin/tr
CAT=/bin/cat
SEQ=/usr/bin/seq

# Install through homebrew with
# brew install flac --HEAD
FLAC=/usr/local/bin/flac
METAFLAC=/usr/local/bin/metaflac

# See http://wiki.hydrogenaud.io/index.php?title=Fraunhofer_FDK_AAC#fdkaac
# Install through homebrew with
# brew install fdk-aac-encoder
FDKAAC=/usr/local/bin/fdkaac

# Constant bitrate encoding parameters:
CBR=( "-b:a" "128k" )
# Variable bitrate encoding parameters:
VBR=( "-vbr" "3" )

# ######### TODO these values are not really user configurable right now #####
ABS_CURRENT_DIR=$("${PWD}")
ABS_TMP_DIR="${ABS_CURRENT_DIR}/tmpdir"

ABS_TMP_WAV_FILE="${ABS_TMP_DIR}/audiofile.wav"
ABS_TMP_METADATA_FILE="${ABS_TMP_DIR}/metadata"
# This is the base part of cover art file names.
# The real file names will have an 5-digit index, i.e. 'coverart00010'.
ABS_TMP_COVERART_FILE="${ABS_TMP_DIR}/coverart"
# ############################################################################

# On LogitechMediaServer I do not have the cover art embedded in each file,
# I have one JPG inside the album's directory.
# If a FLAC file does not have embedded cover art, use this file from the
# same directory the FLAC files are located instead.
# The value is just the file name without a path.
ALBUM_COVERART_FILE="Front.jpg"

# Resize cover art images so that either the width or height (which ever side
# is larger) have MAX_COVERART_DIMENSION pixels.
MAX_COVERART_DIMENSION=500

# ----------------------------------------------------------------------------
function mapCharacters()
{
	((NESTING_LEVEL++))
	local stringValue="$1"
	local stringType="$2"

	local stringMappings=()

	log "Mapping characters..." 2
	if  [ "${stringType}" == "artist" ]; then
		############## Put mappings for <artist> here. ######################
		# The Ramones / the OtherArtist -> Ramones / The OtherArtist
		stringMappings+=( "s/^[Tt]he//" )
		# Ramones / the OtherArtist -> Ramones /OtherArtist
		stringMappings+=( "s/\/[[:blank:]]*[Tt]he /\//" )
		# Ramones/ OtherArtist -> Ramones And OtherArtist
		# Ramones \OtherArtist -> Ramones And OtherArtist
		stringMappings+=( "s/[[:blank:]]*[\/\\][[:blank:]]*/ And /" )
		############## Put mappings for <artist> here. ######################
	elif [ "${stringType}" == "album" ]; then
		############## Put mappings for <album> here. #######################
		# What / Ever -> What Ever
		# What \Ever -> What Ever
		stringMappings+=( "s/[[:blank:]]*\/[[:blank:]]*/ /" )
		############## Put mappings for <album> here. #######################
	else
		log "Unknown string type - characters will not be mapped!" 0
	fi

	for mapping in "${stringMappings[@]}"; do
		local originalString
		originalString="${stringValue}"
		stringValue=$(echo "${stringValue}" | "${SED}" "${mapping}")
		if [ "${originalString}" != "${stringValue}" ]; then
			log "'${originalString}' -> '${stringValue}'" 4
		fi
	done
	log "Done." 3

	___="${stringValue}"

	((NESTING_LEVEL--))

	return 0
}

# No user configurable options below this line.
# ----------------------------------------------------------------------------
function usage()
{
	printf %s '
Version:
'"${VERSION}"'

Usage:
'"${PROGRAM}"' [-v] [-b cbr|vbr] [-t] [-g] [-p|q] [-r] [-j] [-x] srcdir targetdir

-v increases the verbosity level. A higher level means more output to stdout.
   Level 0: Warnings and errors only.
   Level 1: Transcoded files.
   LeveL 2: Processing of cover art, metadata, playlists, temp file deletions.
   Level 3: Executed commands.

-b toggles between constant and variable bitrate. Default is CBR.

-t Ford'"'"'s SYNC2 ignores track numbers and plays the tracks sorted
   alphabetically by their title tag.
   The switch fixes SYNC2'"'"'s brain dead alphabetic play order to track order by
   adding the track number to the title tag ('"'"'Some Title'"'"' -> '"'"'03 Some Title'"'"').

-g gapless mode - creates pgag and iTunSMPB in the converted file.

-p creates simple m3u playlists in targetdir named by the artist and album tags
   found in the converted files.
   The directory separator is / (e.g. Ramones/Leave Home/07 Pinhead.m4a).
   Memory hook: p - the upper right side is \"heavier", the letter would buckle
   to the right: | -> /
   Cannot be used together with -q.

-q same as -p except for the directory separator being \ and the path starting
   with \ (e.g. \Ramones\Leave Home\07 Pinhead.m4a).
   Such a playlist (an extended M3U playlist probably too) is the second way
   to fix the SYNC2 play order behaviour.
   Memory hook: q - the upper left side is "heavier" and would buckle to
   the left: | -> \
   Cannot be used together with -p.

-r resizes cover art images to the value defined in the script if necessary.

-j writes a job summary to stdout and exits.

-x processes only 1s of each audiofile. This is intended for testing whether
   everything works as expected.

srcdir is the directory with the FLAC files.

targetdir is the directory where the M4A files are created.


Always use double quotes around names with spaces, or things won'"'"'t work.
'
}

# ----------------------------------------------------------------------------
function fixSync2()
{
	((NESTING_LEVEL++))

	# The track value, e.g.: 2 (or 02) -> 02
	# FYI - echo "08" | xargs printf "%02d" will not work as numbers with a leading 0 a regarded as octal!
	# Convert it therefore to base 10 with (( ... ))
	local trackMetadataFormattedValue
	trackMetadataFormattedValue=$(printf "%02d" $(( 10#$("${GREP}" -im 1 ^tracknumber "${ABS_TMP_METADATA_FILE}" | "${GREP}" -o [0-9].*) )) )

	# The title tag, e.g.: TITLE
	local titleMetadataTag
	titleMetadataTag=$("${GREP}" -iom 1 ^title "${ABS_TMP_METADATA_FILE}")

	log "Fixing SYNC2 issues..." 2
	logRun "${SED}" -i "" "s/${titleMetadataTag}=/${titleMetadataTag}=${trackMetadataFormattedValue} /" "${ABS_TMP_METADATA_FILE}" 3
	log "Done." 3

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function addFileToTmpPlaylist()
{
	((NESTING_LEVEL++))

	local absTargetFile="$1"
	local absTargetRootDir="$2"

	# The track value, e.g.: 2 (or 02) -> 02
	# FYI - echo "08" | xargs printf "%02d" will not work as numbers with a leading 0 a regarded as octal!
	# Convert it therefore to base 10 with (( ... ))
	local trackMetadataFormattedValue
	trackMetadataFormattedValue=$(printf "%05d" $(( 10#$("${GREP}" -im 1 ^track "${ABS_TMP_METADATA_FILE}" | "${GREP}" -o [0-9].*) )) )

	# The album value.
	local albumMetadataValue
	albumMetadataValue=$("${GREP}" -im 1 ^album "${ABS_TMP_METADATA_FILE}" | "${SED}" s/"^.*="//)

	# Mapped album value.
	local mappedAlbumMetadataValue
	mapCharacters "${albumMetadataValue}" "album" && mappedAlbumMetadataValue="${___}"

	# The artist value.
	local artistMetadataValue
	artistMetadataValue=$("${GREP}" -im 1 ^artist "${ABS_TMP_METADATA_FILE}" | "${SED}" s/"^.*="//)

	# Mapped artist value.
	local mappedArtistMetadataValue
	mapCharacters "${artistMetadataValue}" "artist" && mappedArtistMetadataValue="${___}"

	# Filename of the temp. playlist file.
	local tmpPlaylistFilename
	tmpPlaylistFilename="${mappedArtistMetadataValue} ${mappedAlbumMetadataValue}"

	# /a/b/c/targetdir/x/y/z/aa.m4a -> x/y/z/aa.m4a
	local relTargetFile
	relTargetFile="${absTargetFile#${absTargetRootDir}/}"

	if (( CREATE_DOS_PLAYLIST )); then
		# x/y/z/aa.m4a -> \x\y\z\aa.m4a
		relTargetFile="\\${relTargetFile//\//\\}"
	fi

	# 00010###x/y/z/aa.m4a >> /a/b/c/targetdir/<titletag>.m3u.tmp
	local tmpPlaylistEntry="${trackMetadataFormattedValue}###${relTargetFile}"
	log "Creating temporary playlist entry..." 2
	log "${tmpPlaylistEntry}" 4
	echo "${tmpPlaylistEntry}" >> "${absTargetRootDir}/${tmpPlaylistFilename}.m3u.tmp"
	log "Done." 3

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function log()
{
	local message="$1"
	local verbosityLevel=$2

	if (( VERBOSITY >= verbosityLevel )); then
		local nestingChars
		nestingChars=""
		# Output a "+" for nested shells only.
		if (( NESTING_LEVEL > 0 )); then
			# FYI: ".0" truncates the output at 0 chars, i.e. suppresses output.
			# FYI: +%s -> +1+2+3...
			# FYI: +%.0s -> +++...
			nestingChars=$(printf '+%.0s' $("${SEQ}" -s ' ' 1 $NESTING_LEVEL))
		fi

		echo "${nestingChars}${message}"
	fi
}

# ----------------------------------------------------------------------------
function logRun()
{
	local commands=("$@")

	# Read the last element (i.e. the verbosity level)
	local verbosityLevel="${commands[$(( ${#commands[@]} - 1 ))]}"

	# Remove last element (the verbosity level) from the commands array.
	unset commands[$(( ${#commands[@]} - 1 ))]

	if (( VERBOSITY >= verbosityLevel )); then
		(set -x; "${commands[@]}")
	else
		"${commands[@]}"
	fi
}

# ----------------------------------------------------------------------------
function exportMetadata()
{
	((NESTING_LEVEL++))

	local absSrcFile="$1"

	local metaflacMedataArgs=( "--export-tags-to=${ABS_TMP_METADATA_FILE}" "--no-utf8-convert" )

	log "Exporting metadata..." 2
	logRun "${METAFLAC}" "${metaflacMedataArgs[@]}" "${absSrcFile}" 3
	log "Done." 3

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function processCoverart()
{
	((NESTING_LEVEL++))

	local absSrcFile="$1"
	local absTargetFile="$2"

	local existsEmbeddedCoverartFile=0
	while read -r -u3 coverArtMetadataBlockLine; do
		local coverArtBlock="${coverArtMetadataBlockLine##*#}"
		log "Exporting cover art file (metadata block ${coverArtBlock})..." 2
		logRun "${METAFLAC}" --block-number="${coverArtBlock}"  --export-picture-to="${ABS_TMP_COVERART_FILE}" "${absSrcFile}" 3
		log "Done." 3
		addCoverart "${absTargetFile}" "${ABS_TMP_COVERART_FILE}" "embedded"
		existsEmbeddedCoverartFile=1
	done 3< <("${METAFLAC}" --list --block-type=PICTURE "${absSrcFile}" | "${GREP}" "METADATA block" )

	# If there was no embedded cover art in the source file, try to add a copy
	# of the file from the album's directory.
	if (( ! existsEmbeddedCoverartFile )); then
		if [ -f "${absSrcFile%/*}/${ALBUM_COVERART_FILE}" ]; then
			log "Creating working copy of the cover art file..." 2
			logRun "${CP}" -i "${absSrcFile%/*}/${ALBUM_COVERART_FILE}" "${ABS_TMP_DIR}/${ALBUM_COVERART_FILE}" 3
			log "Done." 3
			addCoverart "${absTargetFile}" "${ABS_TMP_DIR}/${ALBUM_COVERART_FILE}" "album"
		else
			log "Skipping cover art." 2
		fi
	fi

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function getFileExtension()
{
	((NESTING_LEVEL++))

	local absSrcCoverartFile="$1"

	log "Determining file extension..." 2
	local fileExtensions
	fileExtensions=$(logRun "${FILE}" -b --extension "${absSrcCoverartFile}" 3)
	log "Done." 3

	# Gets the first extension 'file' suggests.
	# E.g. jpeg/jpg/jpe/jfif -> jpeg
	# FYI: cannot use echo to return the value because of the log() calls.
	# Therefore the value is written to a global variable '__' (could be as
	# well called 'YADAYADAYADA')
	__="${fileExtensions%%/*}"

	((NESTING_LEVEL--))

	return 0
}

# ----------------------------------------------------------------------------
function appendFileExension()
{
	((NESTING_LEVEL++))

	local absSrcCoverartFile="$1"
	local fileExtension="$2"

	log "Adding extension to cover art file (${fileExtension})..." 2
	# /some/path/<name> -> /some/path/<name>.XXX
	logRun "${MV}" "${absSrcCoverartFile}" "${absSrcCoverartFile}.${fileExtension}" 3
	log "Done." 3

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function addCoverart()
{
	((NESTING_LEVEL++))

	local absTargetFile="$1"
	local absSrcCoverartFile="$2"
	local embeddableCoverartType="$3"

	export PIC_OPTIONS
	PIC_OPTIONS="${ATOMICPARSLEY_PIC_OPTIONS}"

	if (( RESIZE_COVER )); then
		PIC_OPTIONS="${PIC_OPTIONS}:MaxDimensions=${MAX_COVERART_DIMENSION}"
	fi

	log "Adding cover art file (${embeddableCoverartType})..." 2

	# FYI: AtomicParsley (0.9.6) segfaults when adding cover art files that
	# need to be reencoded and do not have a file extension:
	# 'AtomicParsley input.m4a --artwork file1 --overWrite' segfaults, while
	# 'AtomicParsley input.m4a --artwork file1.asd --overWrite' works.
	# 'asd' is not a placeholder - it seems as if any any extension was fine.
	local absSrcCoverartFileWithExtension

	# Check if cover art file has an extension (i.e. a dot in the basename).
	if [[ "${absSrcCoverartFile##*/}" == *.* ]]; then
		absSrcCoverartFileWithExtension="${absSrcCoverartFile}"
	else
		local fileExtension
		fileExtension="UNKNOWN"
		getFileExtension "${absSrcCoverartFile}" && fileExtension="${__}"
		appendFileExension "${absSrcCoverartFile}" "${fileExtension}"
		absSrcCoverartFileWithExtension="${absSrcCoverartFile}.${fileExtension}"
	fi

	log "Importing cover art file..." 2
	logRun "${ATOMICPARSLEY}" "${absTargetFile}" --artwork "${absSrcCoverartFileWithExtension}" --overWrite 3 2>&1 > /dev/null
	log "Done." 3

	log "Deleting exported cover art file..." 2
	removeAbsFile "${absSrcCoverartFileWithExtension}"
	log "Done." 3

	log "Done." 3

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function removeAbsFile()
{
	((NESTING_LEVEL++))

	local absFile="$1"

	if [ -f "${absFile}" ]; then
		logRun "${RM}" "${absFile}" 3
	fi

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function createDirectory()
{
	((NESTING_LEVEL++))

	local absDirectoryPath="$1"

	log "Creating directory '${absDirectoryPath}'..." 2
	logRun "${MKDIR}" -p "${absDirectoryPath}" 3
	log "Done." 3

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function createPlaylist()
{
	((NESTING_LEVEL++))

	local absTmpPlaylistFile="$1"
	local absTargetRootDir="$1"

	log "Creating playlist '${absTmpPlaylistFile%.*}'..." 2
	logRun "${SORT}" "${absTmpPlaylistFile}" -o "${absTmpPlaylistFile%.*}" 3
	logRun "${SED}" -i "" s/"^[0-9]*###"// "${absTmpPlaylistFile%.*}" 3
	removeAbsFile  "${absTmpPlaylistFile}"
	log "Done." 3

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function doWAV()
{
	((NESTING_LEVEL++))

	local absSrcFile="$1"

	local flacDecodeArgs=( "-s" "-d" "-f" )
	# process 1s only.
	local flacTestArgs=( "--until=0:01.00" )

	local flacAllArgs=( "${flacDecodeArgs[@]}" )
	if (( TEST_ONLY )); then flacAllArgs+=( "${flacTestArgs[@]}" ); fi

	log "Decoding FLAC -> WAV..." 2
	logRun "${FLAC}" "${flacAllArgs[@]}" "${absSrcFile}" "-o" "${ABS_TMP_WAV_FILE}" 3
	log "Done." 3

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function doAAC()
{
	((NESTING_LEVEL++))

	local absSrcFile="$1"
	local absTargetFile="$2"

	# See
	# http://wiki.hydrogenaud.io/index.php?title=Fraunhofer_FDK_AAC
	# for more info.
	local fdkaacBaseArgs=( "--ignorelength" "--silent" "--bitrate" "128000" "--profile" "2" "--bitrate-mode" "0")
	local fdkaacGaplessArgs=( "--gapless-mode" "0" "--tag" "pgap:1" )

	local fdkaacAllArgs=( "${fdkaacBaseArgs[@]}" )
	local tagArgs=()

	if (( IS_GAPLESS )); then fdkaacAllArgs+=( "${fdkaacGaplessArgs[@]}" ); fi


	local tagMappings=()
	tagMappings+=( "artist:ART" )
	tagMappings+=( "title:nam" )
	tagMappings+=( "album:alb" )
	tagMappings+=( "date:day" )
	tagMappings+=( "tracknumber:trkn" )
	tagMappings+=( "genre:gen" )
	tagMappings+=( "comment:cmt" )

	while read -r -u3 metadataLine; do
		# FYI: title-tag could be "TITLE" or "Title". Lowercase for comparison.
		# In Bash4 one could use ${someVariable,,}
		local metadataLowercaseTag
		metadataLowercaseTag=$("${TR}" '[:upper:]' '[:lower:]' <<< "${metadataLine%%=*}")

		local metadataValue
		metadataValue="${metadataLine##*=}"

		local hasMapping=0
		for mapping in "${tagMappings[@]}"; do
			local mapableLowercaseTag
			mapableLowercaseTag=$("${TR}" '[:upper:]' '[:lower:]' <<< "${mapping%%:*}")
			if [ "${metadataLowercaseTag}" == "${mapableLowercaseTag}" ]; then
				hasMapping=1
				tagArgs+=( "--tag" "${mapping##*:}:${metadataValue}" )
				log "Mapping '${metadataLowercaseTag}' -> '${mapping##*:}'" 4
				break
			fi
		done
		if (( hasMapping == 0 )); then
			log "Mapping for tag '${metadataLowercaseTag}' not found!" 0
		fi
	done 3< <("${CAT}" "${ABS_TMP_METADATA_FILE}" )

	doWAV "${absSrcFile}"

	log "Transcoding WAV -> AAC" 2
	logRun "${FDKAAC}" "${fdkaacAllArgs[@]}" "${tagArgs[@]}" -o "${absTargetFile}" "${ABS_TMP_WAV_FILE}" 3
	log "Done." 3

	log "Deleting WAV file..." 2
	removeAbsFile "${ABS_TMP_WAV_FILE}"
	log "Done." 3

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function showJobSummary()
{
	local absSrcRootDir="$1"
	local absTargetRootDir="$2"

	local playlistType="False"
	if (( CREATE_UNIX_PLAYLIST )); then playlistType="With '/' separators"; fi
	if (( CREATE_DOS_PLAYLIST )); then playlistType="With '\\' separators"; fi

	local params=(
			"${absSrcRootDir}"
			"${ENCODING_PARAMS[*]}"
			"$( (( FIX_SYNC2 )) && echo "True" || echo "False" )"
			"$( (( IS_GAPLESS )) && echo "True" || echo "False" )"
			"${playlistType}"
			"$( (( RESIZE_COVER )) && echo "True" || echo "False" )"
			"$( (( TEST_ONLY )) && echo "True" || echo "False" )"
			"${absTargetRootDir}")

	printf "
-----------------------------------------------------------------------
I would transcode all *.flac files in the source directory to AAC.

Source directory   : '%s'
Encoding parameters: '%s'
Fix SYNC2          : %s
Gapless playback   : %s
Create playlist    : %s
Resize cover art   : %s
Only 1s            : %s
Target directory   : '%s'
-----------------------------------------------------------------------
" "${params[@]}"
}

# ----------------------------------------------------------------------------
function run()
{
	local absSrcRootDir="$1"
	local absTargetRootDir="$2"

	if [ ! -f "${ATOMICPARSLEY}" ]; then
		log "AtomicParsley not found. Cover art will not be processed." 0
	fi

	if (( JOB_SUMMARY )); then
		showJobSummary "${absSrcRootDir}" "${absTargetRootDir}"
		exit 0
	fi

	while read -d '' -r -u3 absSrcFile; do
		local absTargetFile="${absSrcFile/${absSrcRootDir}/${absTargetRootDir}}"
		absTargetFile="${absTargetFile/.flac/.m4a}"

		if [ ! -d "${absTargetFile%/*}" ]; then
			log "-----------------------------------------------------------------------" 2
			createDirectory "${absTargetFile%/*}"
		fi

		log "-----------------------------------------------------------------------" 2
		log "Processing '${absSrcFile}'..." 1
		exportMetadata "${absSrcFile}"

		if (( FIX_SYNC2 )); then fixSync2; fi

		doAAC "${absSrcFile}" "${absTargetFile}"

		if [ -f "${ATOMICPARSLEY}" ]; then processCoverart "${absSrcFile}" "${absTargetFile}"; fi

		if (( CREATE_UNIX_PLAYLIST || CREATE_DOS_PLAYLIST )); then
			addFileToTmpPlaylist "${absTargetFile}" "${absTargetRootDir}"
		fi

		log "Deleting exported metadata file..." 2
		removeAbsFile "${ABS_TMP_METADATA_FILE}"
		log "Done." 3
	done 3< <("${FIND}" "${absSrcRootDir}" -type f -name \*.flac -print0 | "${SORT}" -z)

	if (( CREATE_UNIX_PLAYLIST || CREATE_DOS_PLAYLIST )); then
		while read -d '' -r -u3 absTmpPlaylistFile; do
			log "-----------------------------------------------------------------------" 2
			createPlaylist "${absTmpPlaylistFile}"
		done 3< <("${FIND}" "${absTargetRootDir}" -type f -name \*.m3u.tmp -print0)
	fi
}

# ----------------------------------------------------------------------------
# ----------------------------------------------------------------------------
# ----------------------------------------------------------------------------
PROGRAM=$(${BASENAME} "$0")

VERBOSITY=0
ENCODING_PARAMS=( "${CBR[@]}" )
FIX_SYNC2=0
IS_GAPLESS=0
CREATE_UNIX_PLAYLIST=0
CREATE_DOS_PLAYLIST=0
RESIZE_COVER=0
JOB_SUMMARY=0
TEST_ONLY=0

NESTING_LEVEL=0

while getopts ":vb:tgpqjrx" optname; do
	case "$optname" in
	"v")
		(( VERBOSITY++ ))
		;;
	"b")
		if [ "$OPTARG" == "vbr" ]; then
			ENCODING_PARAMS=( "${VBR[@]}" )
		elif [ "$OPTARG" != "cbr" ] && [ "$OPTARG" != 'vbr' ]; then
			log "Invalid parameter ${OPTARG}" 0 >&2
			exit 1
		fi
		;;
	"t")
		FIX_SYNC2=1
		;;
	"g")
		if [ -f "${ATOMICPARSLEY}" ]; then
			IS_GAPLESS=1
		else
			log "Cannot use -g without AtomicParsley" 0 >&2
		fi
		;;
	"p")
		CREATE_UNIX_PLAYLIST=1
		if (( CREATE_UNIX_PLAYLIST && CREATE_DOS_PLAYLIST )); then
			log "Cannot use -p together with -q" 0 >&2
			exit 1
		fi
		;;
	"q")
		CREATE_DOS_PLAYLIST=1
		if (( CREATE_DOS_PLAYLIST && CREATE_UNIX_PLAYLIST )); then
			log "Cannot use -q together with -p" 0 >&2
			exit 1
		fi
		;;
	"r")
		if [ -f "${ATOMICPARSLEY}" ]; then
			RESIZE_COVER=1
		else
			log "Cannot use -r without AtomicParsley" 0 >&2
		fi
		;;
	"j")
		JOB_SUMMARY=1
		;;
	"x")
		TEST_ONLY=1
		;;
	"?")
		log "Invalid option: -$OPTARG" 0 >&2
		exit 1
		;;
	":")
		log "Option -$OPTARG requires an argument." 0 >&2
		exit 1
		;;
	esac
done

shift $(( OPTIND - 1 ))

if [ $# -ne 2 ]; then
	usage
	exit 1
fi

# http://www.network-theory.co.uk/docs/bashref/ShellParameterExpansion.html
if [ -d "${ABS_CURRENT_DIR}/${1}" ]; then
	absSrcRootDir="${ABS_CURRENT_DIR}/${1%/}"
elif [ -d "${1}" ]; then
	absSrcRootDir="${1%/}"
else
	log "Invalid srcdir: '${1}'" 0 >&2
	exit 1
fi

if [ -d "${ABS_CURRENT_DIR}/${2}" ]; then
	absTargetRootDir="${ABS_CURRENT_DIR}/${2%/}"
elif [ -d "${2}" ]; then
	absTargetRootDir="${2%/}"
else
	log "Invalid targetdir: '${2}'" 0 >&2
	exit 1
fi

run "${absSrcRootDir}" "${absTargetRootDir}"

log "-----------------------------------------------------------------------" 2
log "All done." 1

# Whenever you think something like "Why it's an one-liner, I'll put it in a file", don't do it and use python or whatever instead!
