#!/bin/bash
set -e
set -u

VERSION="1.0"

FIND=/usr/bin/find
FFMPEG=/usr/local/bin/ffmpeg
#FFMPEG_LOGGING_ARGS=( -loglevel info )
FFMPEG_LOGGING_ARGS=( -loglevel warning )
FFMPEG_ARGS=( -hide_banner )
ATOMICPARSLEY=/usr/local/bin/AtomicParsley
HEAD=/usr/bin/head
SORT=/usr/bin/sort
BASENAME=/usr/bin/basename
DIRNAME=/usr/bin/dirname
RM=/bin/rm
MKDIR=/bin/mkdir

# This is the key your Audible audiobooks are encrypted with.
# Sniff your https connection to the audible server while activating your computer...
# If your key is really 'deadbeef', you probably should sell the account to some rich geek. 
ACTIVATION_BYTES="DEADBEEF"

ABS_TMP_DIR="${PWD}/tmpdir"

ABS_TMP_COVERART_FILE="${ABS_TMP_DIR}/coverart"

# No user configurable options below this line.
# --------------------------------------------------------------------------------
function usage()
{
	printf %s "\
Version:
${VERSION}

Usage:
${PROGRAM} [-v]  srcdir targetdir

-v means verbose, which will produce verbose output on stdout.

srcdir is the directory holding the audible aax files.

targetdir is where the audiobook files will be written to.

Use double quotes around names with spaces, or things won't work.
"
}

# --------------------------------------------------------------------------------
function logrun()
{
	if (( VERBOSE )); then
		(set -x; "$@")
	else
		"$@"
	fi
}

# --------------------------------------------------------------------------------
function convertFiles()
{
	local absSrcDir="$1"
	local absTargetDir="$2"

	printf "
------------------------------------------------------------------------------
I will transcode all *.aax files in the source directory to m4b.

Source directory   : '%s'
Target directory   : '%s'
------------------------------------------------------------------------------
Press ENTER to continue..." "${absSrcDir}" "${absTargetDir}"
	read

	while read -d '' -r -u3 absAaxFile; do
		echo "Processing '${absAaxFile}'..."

		local absSrcDir="$("${DIRNAME}" "${absAaxFile}")"

		local absTargetDir="${absSrcDir/${ABS_SRC_DIR}/${ABS_TARGET_DIR}}"
		local audiobookFile="$("${BASENAME}" "${absAaxFile}" .aax).m4b"
		local absAudiobookFile="${absTargetDir}/${audiobookFile}"

		if [ ! -d "${absTargetDir}" ]; then
			echo "Creating directory '${absTargetDir}'"
			"${MKDIR}" -p "${absTargetDir}"
		fi

		if [ -f "${ATOMICPARSLEY}" ]; then
			getCoverArt "${absAaxFile}" "${ABS_TMP_COVERART_FILE}"
		else
			echo "Cover art will not be processed as AtomicParsley has not been found."
		fi
		
		doM4B "${absAaxFile}" "${absAudiobookFile}"
		
		if [ -f "${ATOMICPARSLEY}" ] && [ -f "${ABS_TMP_COVERART_FILE}" ]; then
			addCoverArt "${absAudiobookFile}" "${ABS_TMP_COVERART_FILE}"
			removeTmpCoverartFile "${ABS_TMP_COVERART_FILE}"
		fi

		echo

	done 3< <("${FIND}" "${absSrcDir}" -type f -name \*.aax -print0 | "${SORT}" -z)
}

# --------------------------------------------------------------------------------
function doM4B()
{
	local absAaxFile="$1"
	local absAudiobookFile="$2"

	local ffmpegEncryptionArgs=( -activation_bytes "${ACTIVATION_BYTES}" )
	local ffmpegInputArgs=( -i "${absAaxFile}" )
	#local ffmpegDataArgs=( -vn -flags +global_header -map 0:a:0 -map_metadata 0 -c:0:a copy -f mp4 )
	#local ffmpegDataArgs=( -flags +global_header -map 0:a:0 -map_metadata 0 -c:0:a copy -f mp4 )
	local ffmpegDataArgs=( -flags +global_header -map 0:a:0 -map -0:s -map -0:v -map_metadata 0 -c:0:a copy -f mp4 )

	echo "Remuxing '${absAaxFile}'..."
	logrun "${FFMPEG}" "${FFMPEG_LOGGING_ARGS[@]}" "${FFMPEG_ARGS[@]}" "${ffmpegEncryptionArgs[@]}" "${ffmpegInputArgs[@]}" "${ffmpegDataArgs[@]}" "${absAudiobookFile}"
}
# --------------------------------------------------------------------------------
function getCoverArt()
{
	local absAaxFile="$1"
	local absTmpCoverartFile="$2"

	local ffmpegEncryptionArgs=( -activation_bytes "${ACTIVATION_BYTES}" )
	local ffmpegInputArgs=( -i "${absAaxFile}" )
	local ffmpegCoverartArgs=( -map 0:v:0 -c:0:v copy -f image2 )

	echo "Extracting cover art to '${absTmpCoverartFile}'..."
	logrun "${FFMPEG}" "${FFMPEG_LOGGING_ARGS[@]}" "${FFMPEG_ARGS[@]}" "${ffmpegEncryptionArgs[@]}" "${ffmpegInputArgs[@]}" "${ffmpegCoverartArgs[@]}" "${absTmpCoverartFile}"
}

# --------------------------------------------------------------------------------
function addCoverArt()
{
	local absAudiobookFile="$1"
	local absTmpCoverartFile="$2"

	echo "Adding cover art to '${absAudiobookFile}'..."
	# Redirect stderr to stdout (the terminal), and stdout to dev/null.
	logrun "${ATOMICPARSLEY}" "${absAudiobookFile}" --artwork "${absTmpCoverartFile}" --overWrite 2>&1 > /dev/null
}

# --------------------------------------------------------------------------------
function removeTmpCoverartFile()
{
	local absTmpCoverartFile="$1"

	if (( VERBOSE )); then echo "Removing '${absTmpCoverartFile}'"; fi
	"${RM}" -f "${absTmpCoverartFile}"
}

# --------------------------------------------------------------------------------
PROGRAM=$(${BASENAME} $0)
VERBOSE=0

while getopts ":v" optname; do
	case "$optname" in
	"v")
		VERBOSE=1
		;;
	"?")
		echo "Invalid option: -$OPTARG" >&2
		exit 1
		;;
	":")
		echo "Option -$OPTARG requires an argument." >&2
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
if [ -d "${PWD}/${1}" ]; then
	ABS_SRC_DIR="${PWD}/${1%/}"
elif [ -d "${1}" ]; then
	ABS_SRC_DIR="${1%/}"
else
	echo "Invalid srcdir: '${1}'"
	exit 1
fi

if [ -d "${PWD}/${2}" ]; then
	ABS_TARGET_DIR="${PWD}/${2%/}"
elif [ -d "${2}" ]; then
	ABS_TARGET_DIR="${2%/}"
else
	echo "Invalid targetdir: '${2}'"
	exit 1
fi

convertFiles "${ABS_SRC_DIR}" "${ABS_TARGET_DIR}"

echo "All done."




