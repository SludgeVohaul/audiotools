#!/bin/bash
set -e
set -u

# Cannot use /bin/sh due to process substitution in run().

VERSION="20170517"

# It seems to be impossible to add coverart to aac encoded streams in an MP4
# container via ffmpeg. Therefore I use AtomicParsley.
# If it is not present the coverart image will not be written to the output
# file, but everything will be fine otherwise.
ATOMICPARSLEY=/usr/local/bin/AtomicParsley
# See AtomicParsley --longhelp
ATOMICPARSLEY_PIC_OPTIONS="DPI=72:removeTempPix"

# If AtomicParsley is not present ImageMagick is not necessary.
# If you do have AtomicParsley, but not ImageMagick, do not use '-r'.
IDENTIFY=/usr/local/bin/identify
CONVERT=/usr/local/bin/convert

FIND=/usr/bin/find
MKDIR=/bin/mkdir
RM=/bin/rm
CP=/bin/cp
SORT=/usr/bin/sort
GREP=/usr/bin/grep
SED=/usr/bin/sed
PWD=/bin/pwd
BASENAME=/usr/bin/basename
FILE=/usr/bin/file

# We need ffmpeg with fdk-aac. Install through homebrew with
# brew install ffmpeg --HEAD --without-libvo-aacenc --without-qtkit --with-fdk-aac
FFMPEG=/usr/local/bin/ffmpeg
FFMPEG_LOGGING_ARGS=( "-loglevel" "warning" )
#FFMPEG_LOGGING_ARGS=( "-loglevel" "info" )
FFMPEG_BASE_ARGS=( "-hide_banner" )
FFPROBE=/usr/local/bin/ffprobe
FFPROBE_LOGGING_ARGS=( "-loglevel" "error" )

# Constant bitrate encoding parameters:
CBR=( "-b:a" "128k" )
# Variable bitrate encoding parameters:
VBR=( "-vbr" "3" )

ABS_CURRENT_DIR=$("${PWD}")
ABS_TMP_DIR="${ABS_CURRENT_DIR}/tmpdir"

ABS_TMP_AAC_FILE="${ABS_TMP_DIR}/audiofile.m4a"
ABS_TMP_METADATA_FILE="${ABS_TMP_DIR}/metadata"
# This is the base part of cover art file names.
# The real file names will have an 5-digit index, i.e. 'coverart00010'.
ABS_TMP_COVERART_FILE="${ABS_TMP_DIR}/coverart"

# On LogitechMediaServer I do not have the cover art embedded in each file,
# I have one JPG inside the album's directory.
# If a FLAC file does not have embedded cover art, use this file from the
# same directory the FLAC files are located instead.
ALBUM_COVERART_FILE="Front.jpg"

# Resize cover art images so that either the width or height (which ever side 
# is larger) have MAX_COVERART_DIMENSION pixels.
MAX_COVERART_DIMENSION=500

# This function is called when "-m" is used.
# Background:
# I ripped, encoded and tagged my CDs with EAC and friends, and somehow
# managed it to add both ID3v2 and Vorbis tags into the FLAC files.
# This has never been an issue with LogitechMediaServer, but now it is an issue:
# ffprobe -i file.flac
# ...
# ARTIST          : Ramones;Ramones
# ALBUM           : Leave Home;Leave Home
# TITLE           : California Sun (BMI);California Sun (BMI)
# DATE            : 1977;1977
# ...
# FYI, Mp3Tag can fix it:
# http://forums.mp3tag.de/index.php?showtopic=2645&st=0&p=19976&#entry19976
#
# So in case you need to modify your metadata (or add new tags) do it in this
# function.
function fixMetadata()
{
	log "Fixing metadata..." 2
	########## Write your own metadata fixes here.##########
	# Delete all characters between '=' and ';'.
	logRun "${SED}" -i "" 's/=.*\\;/=/' "${ABS_TMP_METADATA_FILE}" 3
	########################################################
	log "Done." 3
}

# No user configurable options below this line.
# ----------------------------------------------------------------------------
function usage()
{
	printf %s '
Version:
'"${VERSION}"'

Usage:
'"${PROGRAM}"' [-v] [-b cbr|vbr] [-m] [-t] [-p|q] [-r] [-j] [-x] srcdir targetdir

-v increases the verbosity level. A higher level means more output to stdout.
   Level 0: Warnings and errors only.
   Level 1: Transcoded files.
   LeveL 2: Processing of cover art, metadata, playlists, temp file deletions
   Level 3: Executed commands

-b toggles between constant and variable bitrate. Default is CBR.

-m fixes the original metadata before it is added to the target file.
   The implemented code is just an example (for my real life problem).
   See the script source for more information.

-t Ford'"'"'s SYNC2 ignores track numbers and plays the tracks sorted
   alphabetically by their title tag.
   The switch fixes SYNC2'"'"'s brain dead alphabetic play order to track order by
   adding the track number to the title tag ('"'"'Some Title'"'"' -> '"'"'03 Some Title'"'"').

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

-x converts only 1s of each audiofile. This is intended for testing whether
   everything works as expected.

srcdir is the directory with the FLAC files.

targetdir is the directory where the M4A files are created.


Always use double quotes around names with spaces, or things won'"'"'t work.
'
}

# ----------------------------------------------------------------------------
function fixSync2()
{
	# The track value, e.g.: 02
	# FYI - echo "08" | xargs printf "%02d" will not work as numbers with a leading 0 a regarded as octal!
	# Convert it therefore to base 10 with (( ... ))
	local trackMetadataFormattedValue
	trackMetadataFormattedValue=$(printf "%02d" $(( 10#$("${GREP}" -i ^track "${ABS_TMP_METADATA_FILE}" | "${GREP}" -o [0-9].*) )) )

	# The title key, e.g.: TITLE
	local titleMetadataKey
	titleMetadataKey=$("${GREP}" -io ^title "${ABS_TMP_METADATA_FILE}")

	log "Fixing SYNC2 issues..." 2
	logRun "${SED}" -i "" "s/${titleMetadataKey}=/${titleMetadataKey}=${trackMetadataFormattedValue} /" "${ABS_TMP_METADATA_FILE}" 3
	log "Done." 3
}

# ----------------------------------------------------------------------------
function addFileToPlaylist()
{
	local absTargetFile="$1"
	local absTargetRootDir="$2"

	# The track value, e.g.: 02 -> 00002
	local trackMetadataFormattedValue
	trackMetadataFormattedValue=$(printf "%05d" $(( 10#$("${GREP}" -i ^track "${ABS_TMP_METADATA_FILE}" | "${GREP}" -o [0-9].*) )) )
	# The album value
	local albumMetadataValue
	albumMetadataValue=$("${GREP}" -i ^album "${ABS_TMP_METADATA_FILE}" | "${SED}" s/"^.*="//)
	# The artist value
	local artistMetadataValue
	artistMetadataValue=$("${GREP}" -i ^artist "${ABS_TMP_METADATA_FILE}" | "${SED}" s/"^.*="//)

	# /a/b/c/targetdir/x/y/z/aa.m4a -> x/y/z/aa.m4a
	local relTargetFile
	relTargetFile="${absTargetFile#${absTargetRootDir}/}"
	if (( CREATE_DOS_PLAYLIST )); then
		# x/y/z/aa.m4a -> \x\y\z\aa.m4a
		relTargetFile="\\${relTargetFile//\//\\}"
	fi

	# 00010###x/y/z/aa.m4a >> /a/b/c/targetdir/<titletag>.m3u.tmp
	echo "${trackMetadataFormattedValue}###${relTargetFile}" >> "${absTargetRootDir}/${artistMetadataValue} ${albumMetadataValue}.m3u.tmp"
}

# ----------------------------------------------------------------------------
function log()
{
	local message="$1"
	local verbosityLevel=$2

	if (( VERBOSITY >= verbosityLevel )); then
		echo "${message}"
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
function addMetadata()
{
	local absTargetFile="$1"

	local ffmpegInputArgs=( "-i" "${ABS_TMP_AAC_FILE}" "-i" "${ABS_TMP_METADATA_FILE}" )
	local ffmpegAudioArgs=( "-map" "0:a:0" "-map_metadata" "1" "-c:0:a" "copy" "-flags" "+global_header" "-f" "mp4" )

	log "Adding metadata..." 2
	logRun "${FFMPEG}" "${FFMPEG_LOGGING_ARGS[@]}" "${FFMPEG_BASE_ARGS[@]}" "${ffmpegInputArgs[@]}" "${ffmpegAudioArgs[@]}" "${absTargetFile}" 3
	log "Done." 3
}

# ----------------------------------------------------------------------------
function processCoverart
{
	local absSrcFile="$1"
	local absTargetFile="$2"
	
	# Convert
	PIC_OPTIONS="${ATOMICPARSLEY_PIC_OPTIONS}"

	if (( RESIZE_COVER )); then 
		PIC_OPTIONS="${PIC_OPTIONS}:MaxDimensions=${MAX_COVERART_DIMENSION}"
	fi

	export PIC_OPTIONS

	local existsEmbeddedCoverartFile=0

	# Try to add the cover art file(s) embedded in the source file first.
	while read -d '' -r -u3 absEmbeddedCoverartFile; do
		addCoverart "${absTargetFile}" "${absEmbeddedCoverartFile}" "embedded"
		existsEmbeddedCoverartFile=1
	done 3< <("${FIND}" "${ABS_TMP_DIR}" -type f -maxdepth 1 -name "${ABS_TMP_COVERART_FILE##*/}"[0-9][0-9][0-9][0-9][0-9] -print0 | "${SORT}" -z)

	# If there was no embedded cover art in the source file, try to add the 
	# file from the album's directory.
	if (( ! existsEmbeddedCoverartFile )); then
		if [ -f "${absSrcFile%/*}/${ALBUM_COVERART_FILE}" ]; then
			addCoverart "${absTargetFile}" "${absSrcFile%/*}/${ALBUM_COVERART_FILE}" "album"
		else
			log "Skipping cover art." 2
		fi
	fi
}

# ----------------------------------------------------------------------------
function getFileExtension
{
	local absCoverartFile="$1"

	log "+ Determining file extension..." 2
	local fileExtensions
	fileExtensions=$(logRun "${FILE}" -b --extension "${absCoverartFile}" 3)
	log "+ Done." 3

	# E.g. jpeg/jpg/jpe/jfif -> jpeg
	# FYI: cannot use echo to return the value because of the log() calls.
	# Therefore the value is written to a global variable '__' (could be as
	# well called 'YADAYADAYADA')
	__="${fileExtensions%%/*}"
}

# ----------------------------------------------------------------------------
function addCoverart()
{
	local absTargetFile="$1"
	local absSourceCoverartFile="$2"
	local embeddableCoverartType="$3"

	log "Adding ${embeddableCoverartType} cover art..." 2

	# FYI: AtomicParsley (0.9.6) segfaults when adding cover art files that 
	# need to be reencoded and do not have a file extension:
	# 'AtomicParsley input.m4a --artwork file1 --overWrite' segfaults, while
	# 'AtomicParsley input.m4a --artwork file1.asd --overWrite' works. ('asd'
	# is not a placeholder - it seems as if just any extension is fine).
	# Check if the cover art file has an extension (i.e. has a dot in the 
	# basename) and if not, add the first extension 'file' suggests.
	if [[ "${absSourceCoverartFile##*/}" != *.* ]]; then
		getFileExtension "${absSourceCoverartFile}" && local fileExtension="${__}"
		log "+ Adding file extension to cover art file..." 2
		# /the/source/coverart -> /the/tempdir/coverart.XXX
		local absTargetCoverartFile="${ABS_TMP_DIR}/${absSourceCoverartFile##*/}.${fileExtension}"
		logRun "${CP}" -i "${absSourceCoverartFile}" "${absTargetCoverartFile}" 3
		log "+ Done." 3
		log "+ Embedding cover art..." 2 || 
		logRun "${ATOMICPARSLEY}" "${absTargetFile}" --artwork "${absTargetCoverartFile}" --overWrite 3 2>&1 > /dev/null
		log "+ Done." 3
		log "+ Deleting temporary cover art file..." 2
		removeAbsTempFile "${absTargetCoverartFile}"
		log "+ Done." 3
	else
		# Redirect stderr to stdout (the terminal), and then stdout
		# to dev/null, i.e. write stderr to the terminal.
		log "+ Embedding cover art..." 2
		logRun "${ATOMICPARSLEY}" "${absTargetFile}" --artwork "${absSourceCoverartFile}" --overWrite 3 2>&1 > /dev/null
		log "+ Done." 3
	fi

	log "Done." 3
}

# ----------------------------------------------------------------------------
function removeAbsTempFile()
{
	local absTempFile="$1"

	if [ -f "${absTempFile}" ]; then
		logRun "${RM}" -f "${absTempFile}" 3
	fi
}

# ----------------------------------------------------------------------------
function doAAC()
{
	local absSrcFile="$1"
	local absTargetFile="$2"
	local absTargetRootDir="$3"

	local ffmpegInputArgs=( "-i" "${absSrcFile}" )
	# Encode 1s only.
	if (( TEST_ONLY )); then ffmpegInputArgs=( "-ss" "00:00:00" "-t" "1" "-i" "${absSrcFile}" ); fi
	local ffmpegAudioArgs=( "-channel_layout" "stereo" "-map" "0:a:0" "-c:0:a" "libfdk_aac" "${ENCODING_PARAMS[@]}" "-f" "mp4" )
	local ffmpegMetadataArgs=( "-f" "ffmetadata" "${ABS_TMP_METADATA_FILE}" )
	# Export all video streams.
	local ffmpegCoverartArgs=( "-map" "0:v" "-c:v" "copy" "-f" "image2" )
	local ffmpegAllArgs=( "${ffmpegInputArgs[@]}" )

	if (( FIX_METADATA || FIX_SYNC2 || CREATE_UNIX_PLAYLIST || CREATE_DOS_PLAYLIST )); then
		ffmpegAllArgs+=( "${ffmpegMetadataArgs[@]}" "${ffmpegAudioArgs[@]}" "${ABS_TMP_AAC_FILE}" )
	else
		ffmpegAllArgs+=( "${ffmpegAudioArgs[@]}" "${absTargetFile}" )
	fi

	# If there is no video stream in the source file, use the album cover art
	# file, otherwise use the files exported from the video streams.
	# The exported files are called name00001, name00002, name00010, ...
	if [ ! -z "$("${FFPROBE}" "${FFPROBE_LOGGING_ARGS[@]}" -i "${absSrcFile}" -show_streams -select_streams v)" ]; then
		ffmpegAllArgs+=( "${ffmpegCoverartArgs[@]}" "${ABS_TMP_COVERART_FILE}%05d" )
	fi

	log "-----------------------------------------------------------------------" 2
	log "Transcoding '${absSrcFile}'..." 1
	logRun "${FFMPEG}" "${FFMPEG_LOGGING_ARGS[@]}" "${FFMPEG_BASE_ARGS[@]}" "${ffmpegAllArgs[@]}" 3
	log "Done." 3

	if (( FIX_METADATA || FIX_SYNC2 || CREATE_UNIX_PLAYLIST || CREATE_DOS_PLAYLIST )); then
		if (( FIX_METADATA )); then fixMetadata; fi
		if (( FIX_SYNC2 )); then fixSync2; fi
		if (( CREATE_UNIX_PLAYLIST )); then addFileToPlaylist "${absTargetFile}" "${absTargetRootDir}"; fi
		if (( CREATE_DOS_PLAYLIST )); then addFileToPlaylist "${absTargetFile}" "${absTargetRootDir}"; fi
		addMetadata "${absTargetFile}"
	fi

	if [ -f "${ATOMICPARSLEY}" ]; then processCoverart "${absSrcFile}" "${absTargetFile}"; fi

	log "Removing temporary files..." 2
	removeAbsTempFile "${ABS_TMP_COVERART_FILE}"
	while read -d '' -r -u3 absEmbeddedCoverartFile; do
		removeAbsTempFile "${absEmbeddedCoverartFile}"
	done 3< <("${FIND}" "${ABS_TMP_DIR}" -type f -maxdepth 1 -name "${ABS_TMP_COVERART_FILE##*/}"[0-9][0-9][0-9][0-9][0-9] -print0 | "${SORT}" -z)

	if (( FIX_METADATA || FIX_SYNC2 || CREATE_UNIX_PLAYLIST || CREATE_DOS_PLAYLIST )); then
		removeAbsTempFile "${ABS_TMP_METADATA_FILE}"
		removeAbsTempFile "${ABS_TMP_AAC_FILE}"
	fi
	log "Done." 3
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
			"$( (( FIX_METADATA )) && echo "True" || echo "False" )"
			"$( (( FIX_SYNC2 )) && echo "True" || echo "False" )"
			"${playlistType}"
			"$( (( RESIZE_COVER )) && echo "True" || echo "False" )"
			"${absTargetRootDir}")

	printf "
-----------------------------------------------------------------------
I would transcode all *.flac files in the source directory to AAC.

Source directory   : '%s'
Encoding parameters: '%s'
Fix metadata       : %s
Fix SYNC2          : %s
Create playlist    : %s
Resize cover art   : %s
Target directory   : '%s'
-----------------------------------------------------------------------\n" "${params[@]}"
}

# ----------------------------------------------------------------------------
function run()
{
	local absSrcRootDir="$1"
	local absTargetRootDir="$2"


	if (( JOB_SUMMARY )); then 
		showJobSummary "${absSrcRootDir}" "${absTargetRootDir}"
		exit
	fi

	while read -d '' -r -u3 absSrcFile; do
		local absTargetFile="${absSrcFile/${absSrcRootDir}/${absTargetRootDir}}"
		absTargetFile="${absTargetFile/.flac/.m4a}"

		if [ ! -d "${absTargetFile%/*}" ]; then
			log "-----------------------------------------------------------------------" 2
			log "Creating directory..." 2
			logRun "${MKDIR}" -p "${absTargetFile%/*}" 3
			log "Done." 3
		fi

		doAAC "${absSrcFile}" "${absTargetFile}" "${absTargetRootDir}"
	done 3< <("${FIND}" "${absSrcRootDir}" -type f -name \*.flac -print0 | "${SORT}" -z)

	if (( CREATE_UNIX_PLAYLIST || CREATE_DOS_PLAYLIST )); then
		log "-----------------------------------------------------------------------" 2
		log "Creating playlist(s)..." 2
		while read -d '' -r -u3 absTmpPlaylistFile; do
			logRun "${SORT}" "${absTmpPlaylistFile}" -o "${absTmpPlaylistFile%.*}" 3
			logRun "${SED}" -i "" s/"^[0-9]*###"// "${absTmpPlaylistFile%.*}" 3
			removeAbsTempFile  "${absTmpPlaylistFile}"
		done 3< <("${FIND}" "${absTargetRootDir}" -type f -name \*.m3u.tmp -print0)
		log "Done." 3
	fi
}

# ----------------------------------------------------------------------------
# ----------------------------------------------------------------------------
# ----------------------------------------------------------------------------
PROGRAM=$(${BASENAME} "$0")

VERBOSITY=0
ENCODING_PARAMS=( "${CBR[@]}" )
FIX_METADATA=0
FIX_SYNC2=0
CREATE_UNIX_PLAYLIST=0
CREATE_DOS_PLAYLIST=0
RESIZE_COVER=0
JOB_SUMMARY=0
TEST_ONLY=0

while getopts ":vb:mtpqjrx" optname; do
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
	"m")
		FIX_METADATA=1
		;;
	"t")
		FIX_SYNC2=1
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
		if [ -f "${IDENTIFY}" ] && [ -f "${CONVERT}" ]; then
			RESIZE_COVER=1
		else
			log "Cannot use -r without ImageMagick" 0 >&2
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
