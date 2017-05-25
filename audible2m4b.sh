#!/bin/bash
set -e
set -u

# Cannot use /bin/sh due to process substitution in run().

VERSION="20170525"

# It seems to be impossible to add coverart to aac encoded streams in an MP4
# container via ffmpeg. Therefore I use AtomicParsley.
# If it is not present the coverart image will not be written to the output
# file, but everything will be fine otherwise.
ATOMICPARSLEY=/usr/local/bin/AtomicParsley

FIND=/usr/bin/find
MKDIR=/bin/mkdir
RM=/bin/rm
MV=/bin/mv
SORT=/usr/bin/sort
PWD=/bin/pwd
BASENAME=/usr/bin/basename
FILE=/usr/bin/file

# Install through homebrew with
# brew install ffmpeg --HEAD --without-libvo-aacenc --without-qtkit
FFMPEG=/usr/local/bin/ffmpeg
FFMPEG_LOGGING_ARGS=( "-loglevel" "warning" )
#FFMPEG_LOGGING_ARGS=( "-loglevel" "info" )
FFMPEG_BASE_ARGS=( "-hide_banner" )

FFPROBE=/usr/local/bin/ffprobe
FFPROBE_BASE_ARGS=( "-hide_banner" )
FFPROBE_LOGGING_ARGS=( "-loglevel" "error" )

# This is the key your Audible audiobooks are encrypted with.
# Sniff your https connection to the audible server while activating your computer...
# If your key is really 'deadbeef', you probably should sell the account to some rich geek.
ACTIVATION_BYTES="DEADBEEF"

# ######### TODO these values are not really user configurable right now #####
ABS_CURRENT_DIR=$("${PWD}")
ABS_TMP_DIR="${ABS_CURRENT_DIR}/tmpdir"
# This is the base part of cover art file names.
# The real file names will have an 5-digit index, i.e. 'coverart00010'.
ABS_TMP_COVERART_FILE="${ABS_TMP_DIR}/coverart"
# ############################################################################

# No user configurable options below this line.
# --------------------------------------------------------------------------------
function usage()
{
	printf %s '
Version:
'"${VERSION}"'

Usage:
'"${PROGRAM}"' [-v] [-j] [-x] srcdir targetdir

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

Always use double quotes around names with spaces, or things won'"'"'t work.
'
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

# --------------------------------------------------------------------------------
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
function hasEmbeddedCoverart()
{
	local absSrcFile="$1"

	local ffprobeEncryptionArgs=( "-activation_bytes" "${ACTIVATION_BYTES}" )
	local ffprobeInputArgs=( "-i" "${absSrcFile}" )
	local ffprobeDataArgs=( "-show_streams" "-select_streams" "v" )

	local ffprobeAllArgs=(
		"${FFPROBE_LOGGING_ARGS[@]}"
		"${FFPROBE_BASE_ARGS[@]}"
		"${ffprobeEncryptionArgs[@]}"
		"${ffprobeInputArgs[@]}"
		"${ffprobeDataArgs[@]}")

	# Check if the source file has an video stream.
	if [ -z "$("${FFPROBE}" "${ffprobeAllArgs[@]}" )" ]; then
		echo 0
	else
		echo 1
	fi
}

# ----------------------------------------------------------------------------
function processCoverart()
{
	local absSrcFile="$1"
	local absTargetFile="$2"

	# Add cover art file(s) embedded in the source file first.
	while read -d '' -r -u3 absEmbeddedCoverartFile; do
		addCoverart "${absTargetFile}" "${absEmbeddedCoverartFile}"
	done 3< <("${FIND}" "${ABS_TMP_DIR}" -type f -maxdepth 1 -name "${ABS_TMP_COVERART_FILE##*/}"[0-9][0-9][0-9][0-9][0-9] -print0 | "${SORT}" -z)
}

# ----------------------------------------------------------------------------
function getFileExtension()
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
function addFileExension()
{
	local absSourceCoverartFile="$1"
	local fileExtension="$2"

	log "+ Adding extension '${fileExtension}' to cover art file..." 2
	# /some/path/<name> -> /some/path/<name>.XXX
	logRun "${MV}" "${absSourceCoverartFile}" "${absSourceCoverartFile}.${fileExtension}" 3
	log "+ Done." 3
}

# ----------------------------------------------------------------------------
function addCoverart()
{
	local absTargetFile="$1"
	local absSourceCoverartFile="$2"

	log "Adding cover art..." 2

	# FYI: AtomicParsley (0.9.6) segfaults when adding cover art files that
	# need to be reencoded and do not have a file extension:
	# 'AtomicParsley input.m4a --artwork file1 --overWrite' segfaults, while
	# 'AtomicParsley input.m4a --artwork file1.asd --overWrite' works.
	# 'asd' is not a placeholder - it seems as if any any extension was fine.

	local absSourceCoverartFileWithExtension
	# Check if cover art file has an extension (i.e. a dot in the basename).
	if [[ "${absSourceCoverartFile##*/}" == *.* ]]; then
		absSourceCoverartFileWithExtension="${absSourceCoverartFile}"
	else
		# Get the first extension 'file' suggests.
		getFileExtension "${absSourceCoverartFile}" && local fileExtension="${__}"
		addFileExension "${absSourceCoverartFile}" "${fileExtension}"
		absSourceCoverartFileWithExtension="${absSourceCoverartFile}.${fileExtension}"
	fi

	log "+ Embedding cover art file..." 2
	logRun "${ATOMICPARSLEY}" "${absTargetFile}" --artwork "${absSourceCoverartFileWithExtension}" --overWrite 3 2>&1 > /dev/null
	log "+ Done." 3

	log "+ Deleting temporary cover art file..." 2
	removeAbsFile "${absSourceCoverartFileWithExtension}"
	log "+ Done." 3

	log "Done." 3
}

# ----------------------------------------------------------------------------
function removeAbsFile()
{
	local absFile="$1"

	if [ -f "${absFile}" ]; then
		logRun "${RM}" "${absFile}" 3
	fi
}

# --------------------------------------------------------------------------------
function doM4B()
{
	local absSrcFile="$1"
	local absTargetFile="$2"

	local ffmpegEncryptionArgs=( "-activation_bytes" "${ACTIVATION_BYTES}" )
	local ffmpegInputArgs=( "-i" "${absSrcFile}" )
	# Encode 1s only.
	local ffmpegTestArgs=( "-ss" "00:00:00" "-t" "1" )
	local ffmpegAudioArgs=( "-flags" "+global_header" "-map" "0:a:0" "-map" "-0:s" "-map" "-0:v" "-map_metadata" "0" "-c:0:a" "copy" "-f" "mp4" )
	# Export all video streams.
	local ffmpegCoverartArgs=( "-map" "0:v" "-c:v" "copy" "-f" "image2" )

	local ffmpegAllArgs=(
			"${FFMPEG_LOGGING_ARGS[@]}"
			"${FFMPEG_BASE_ARGS[@]}"
			"${ffmpegEncryptionArgs[@]}")

	if (( TEST_ONLY )); then ffmpegAllArgs+=( "${ffmpegTestArgs[@]}" ); fi

	ffmpegAllArgs+=(
			"${ffmpegInputArgs[@]}"
			"${ffmpegAudioArgs[@]}"
			"${absTargetFile}")

	if [ -f "${ATOMICPARSLEY}" ]; then
		if (( $(hasEmbeddedCoverart "${absSrcFile}") )); then
			# Export files from video stream. Names will be <name>00001, <name>00002, <name>00010, ...
			ffmpegAllArgs+=( "${ffmpegCoverartArgs[@]}" "${ABS_TMP_COVERART_FILE}%05d" )
		fi
	fi

	log "-----------------------------------------------------------------------" 2
	log "Remuxing '${absSrcFile}'..." 1
	logRun "${FFMPEG}" "${ffmpegAllArgs[@]}" 3
	log "Done." 3

	if [ -f "${ATOMICPARSLEY}" ]; then processCoverart "${absSrcFile}" "${absTargetFile}"; fi
}

# ----------------------------------------------------------------------------
function showJobSummary()
{
	local absSrcRootDir="$1"
	local absTargetRootDir="$2"

	local params=(
			"${absSrcRootDir}"
			"$( (( TEST_ONLY )) && echo "True" || echo "False" )"
			"${absTargetRootDir}")

	printf "
-----------------------------------------------------------------------
I would remux all *.aax files in the source directory to AAC.

Source directory : '%s'
Only 1s          : %s
Target directory : '%s'
-----------------------------------------------------------------------
" "${params[@]}"
}

# --------------------------------------------------------------------------------
function run()
{
	local absSrcRootDir="$1"
	local absTargetRootDir="$2"

	if [ ! -f "${ATOMICPARSLEY}" ]; then
		log "AtomicParsley not found. Cover art will not be processed." 0
	fi

	if (( JOB_SUMMARY )); then
		showJobSummary "${absSrcRootDir}" "${absTargetRootDir}"
		exit
	fi

	while read -d '' -r -u3 absSrcFile; do
		local absTargetFile="${absSrcFile/${absSrcRootDir}/${absTargetRootDir}}"
		absTargetFile="${absTargetFile/.aax/.m4b}"

		if [ ! -d "${absTargetFile%/*}" ]; then
			log "-----------------------------------------------------------------------" 2
			log "Creating directory..." 2
			logRun "${MKDIR}" -p "${absTargetFile%/*}" 3
			log "Done." 3
		fi

		doM4B "${absSrcFile}" "${absTargetFile}"
	done 3< <("${FIND}" "${absSrcRootDir}" -type f -name \*.aax -print0 | "${SORT}" -z)
}

# ----------------------------------------------------------------------------
# ----------------------------------------------------------------------------
# ----------------------------------------------------------------------------
PROGRAM=$(${BASENAME} "$0")
VERBOSITY=0
JOB_SUMMARY=0
TEST_ONLY=0

while getopts ":vjx" optname; do
	case "$optname" in
	"v")
		(( VERBOSITY++ ))
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


