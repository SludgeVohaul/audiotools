#!/bin/bash
set -e
set -u

# Cannot use /bin/sh due to process substitution in transcode().

VERSION="20170504"

# It seems to be impossible to add coverart to aac encoded streams in an MP4
# container via ffmpeg. Therefore I use AtomicParsley.
# If it is not present the coverart image will not be written to the output
# file, but everything will be fine otherwise.
ATOMICPARSLEY=/usr/local/bin/AtomicParsley
FIND=/usr/bin/find
MKDIR=/bin/mkdir
RM=/bin/rm
XARGS=/usr/bin/xargs
SORT=/usr/bin/sort
GREP=/usr/bin/grep
SED=/usr/bin/sed
PWD=/bin/pwd
# We need ffmpeg with fdk-aac. Install through homebrew with
# brew install ffmpeg --HEAD --without-libvo-aacenc --without-qtkit --with-fdk-aac
FFMPEG=/usr/local/bin/ffmpeg
FFMPEG_LOGGING_ARGS=( -loglevel warning )
#FFMPEG_LOGGING_ARGS=( -loglevel info )
FFMPEG_ARGS=( -hide_banner -channel_layout stereo )
FFPROBE=/usr/local/bin/ffprobe
FFPROBE_LOGGING_ARGS=( -loglevel error )
BASENAME=/usr/bin/basename
DIRNAME=/usr/bin/dirname

# Constant bitrate encoding parameters:
CBR=( -b:a 128k )
# Variable bitrate encoding parameters:
VBR=( -vbr 3 )

ABS_TMP_DIR="${PWD}/tmpdir"

ABS_TMP_AAC_FILE="${ABS_TMP_DIR}/audiofile.m4a"

ABS_TMP_METADATA_FILE="${ABS_TMP_DIR}/metadata"

# On LogitechMediaServer I do not have the coverart embedded in each file,
# I have one JPG inside each album directory.
# If a FLAC file does not have embedded coverart, this file will be used instead.
ALBUM_COVERART_FILE="Front.jpg"
ABS_TMP_COVERART_FILE="${ABS_TMP_DIR}/coverart"

# This function is called when "-f fix" is used.
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
	local metadataFile="$1"

	echo "Fixing metadata..."

	########## Write your own metadata fixes here.##########
	# Delete all characters between '=' and ';'.
	logrun "${SED}" -i "" 's/=.*\\;/=/' "${metadataFile}"
}

# No user configurable options below this line.
# ----------------------------------------------------------------------------
function usage()
{
	printf %s "\
Version:
${VERSION}

Usage:
${PROGRAM} [-v] [-b cbr|vbr ] [-m] [-s] [-p] srcdir targetdir
-v means verbose, which will output the ffmpeg commands on stdout.

-b toggles between constant and variable bitrate. Default is CBR.


-m fixes the original metadata before it is added to the target file.
   The implemented code is just an example (for my real life problem).
   See the script source.

-s fixes SYNC2's brain dead alphabetic play order to track order (Ford's SYNC2
   ignores track numbers and plays the tracks alphabetically sorted by their name).
   The only solution seems to be to prepentd the track tu the title, e.g.
   'Some Title' -> '03 Some Title'.

-p creates an m3u playlist called as the album in the album's directory. This is 
   the second way to fix the SYNC2 behavior.

srcdir is the directory with the FLAC files.

targetdir is the directory where the transcoded files will be stored.

Use double quotes around names with spaces, or things won't work.
"
}

# ----------------------------------------------------------------------------
function fixSync2()
{
	local metadataFile="$1"
	
	# The track value, e.g.: 02
	# FYI - echo "08" | xargs printf "%02d" will not work as numbers with a leading 0 a regarded as octal!
	# Convert it therefore to base 10 with (( ... )) 
	local trackMetadataFormattedValue=$(printf "%02d" $(( 10#$("${GREP}" -i ^track "${metadataFile}" | "${GREP}" -o [0-9].*) )) )

	# The title key, e.g.: TITLE
	local titleMetadataKey=$("${GREP}" -io ^title "${metadataFile}")

	echo "Fixing SYNC2 issues..."
	logrun "${SED}" -i "" s/"${titleMetadataKey}="/"${titleMetadataKey}=${trackMetadataFormattedValue} "/ "${metadataFile}"
}

# ----------------------------------------------------------------------------
function logrun()
{
	if (( VERBOSE )); then
		(set -x; "$@")
	else
		"$@"
	fi
}

# ----------------------------------------------------------------------------
function addMetadata()
{
	local tmpAacFile="$1"
	local metadataFile="$2"
	local targetAacFile="$3"

	local ffmpegInputArgs=( -i "${tmpAacFile}" -i "${metadataFile}" )
	local ffmpegAudioArgs=( -map 0:a:0 -map_metadata 1 -c:0:a copy -flags +global_header -f mp4 )

	echo "Adding metadata..."
	logrun "${FFMPEG}" "${FFMPEG_LOGGING_ARGS[@]}" "${ffmpegInputArgs[@]}" "${ffmpegAudioArgs[@]}" "${targetAacFile}"
}

# ----------------------------------------------------------------------------
function addCoverArt()
{
	local absSrcDir="${1%/}"
	local absTargetAacFile="$2"

	local absAlbumCoverartFile="${absSrcDir}/${ALBUM_COVERART_FILE}"

	if [ ! -f "${ATOMICPARSLEY}" ]; then
		return
	fi

	if [ -f "${ABS_TMP_COVERART_FILE}" ]; then
		echo "Adding cover art..."
		# Redirect stderr to stdout (the terminal), and then stdout
		# to dev/null, i.e. write stderr to the terminal.
		logrun "${ATOMICPARSLEY}" "${absTargetAacFile}" --artwork "${ABS_TMP_COVERART_FILE}" --overWrite 2>&1 > /dev/null
	elif [ -f "${absAlbumCoverartFile}" ]; then
		echo "Adding cover art..."
		logrun "${ATOMICPARSLEY}" "${absTargetAacFile}" --artwork "${absAlbumCoverartFile}" --overWrite 2>&1 > /dev/null
	else
		echo "Cover art not found."
	fi
}

# ----------------------------------------------------------------------------
function removeAbsTempFile
{
	local absTempFile="$1"

	logrun "${RM}" -f "${absTempFile}"
}

# ----------------------------------------------------------------------------
function doAAC()
{
	local absSrcFile="$1"
	local absTargetFile="$2"

	local ffmpegInputArgs=( -i "${absSrcFile}" )
	local ffmpegAudioArgs=( -map 0:a:0 -c:0:a libfdk_aac "${ENCODING_PARAMS[@]}" -f mp4 )
	local ffmpegMetadataArgs=( -f ffmetadata "${ABS_TMP_METADATA_FILE}" )
	local ffmpegCoverartArgs=( -map 0:v:0 -c:0:v copy -vsync 2 -f image2 )

	local ffmpegAllArgs=( "${ffmpegInputArgs[@]}" )

	if (( FIX_METADATA || FIX_SYNC2 )); then
		ffmpegAllArgs+=( "${ffmpegMetadataArgs[@]}" "${ffmpegAudioArgs[@]}" "${ABS_TMP_AAC_FILE}" )
	else
		ffmpegAllArgs+=( "${ffmpegAudioArgs[@]}" "${absTargetFile}" )
	fi

	# If there is a video stream in the source file, then it contains
	# cover art. Add parameters to export it.
	if [ ! -z "$("${FFPROBE}" "${FFPROBE_LOGGING_ARGS[@]}" -i "${absSrcFile}" -show_streams -select_streams v)" ]; then
		ffmpegAllArgs+=( "${ffmpegCoverartArgs[@]}" "${ABS_TMP_COVERART_FILE}" )
	fi

	echo "-----------------------------------------------------------------------"
	echo "Transcoding '${absSrcFile}'..."
	logrun "${FFMPEG}" "${FFMPEG_LOGGING_ARGS[@]}" "${FFMPEG_ARGS[@]}" "${ffmpegAllArgs[@]}"
	echo "Done."

	if (( FIX_METADATA || FIX_SYNC2 )); then

		if (( FIX_METADATA )); then
			fixMetadata "${ABS_TMP_METADATA_FILE}"
			echo "Done."
		fi

		if (( FIX_SYNC2 )); then
			fixSync2 "${ABS_TMP_METADATA_FILE}"
			echo "Done."
		fi

		addMetadata "${ABS_TMP_AAC_FILE}" "${ABS_TMP_METADATA_FILE}" "${absTargetFile}"
		echo "Done."
	fi

	addCoverArt "${absSrcDir}" "${absTargetFile}"
	echo "Done."

	echo "Removing temporary files..."
	removeAbsTempFile "${ABS_TMP_COVERART_FILE}"

	if (( FIX_METADATA || FIX_SYNC2 )); then
		removeAbsTempFile "${ABS_TMP_METADATA_FILE}"
		removeAbsTempFile "${ABS_TMP_AAC_FILE}"
	fi
	echo "Done."
}

# ----------------------------------------------------------------------------
function bool_string()
{
	[[ $1 = 1 ]] && echo "True" || echo "False"
}

# ----------------------------------------------------------------------------
function transcode()
{
	printf "
------------------------------------------------------------------------------
I will transcode all *.flac files in the source directory to AAC.

Source directory   : '%s'
Encoding parameters: '%s'
Fix metadata       : %s
Fix SYNC2          : %s
Create playlist    : %s
Target directory   : '%s'
------------------------------------------------------------------------------
Press ENTER to continue..." "${ABS_SRC_ROOT_DIR}" "$(echo "${ENCODING_PARAMS[@]}")" "$(bool_string $FIX_METADATA)" "$(bool_string $FIX_SYNC2)" "$(bool_string $CREATE_PLAYLIST)" "${ABS_TARGET_ROOT_DIR}"
	read

	local absSrcFile=""
	local absSrcDir=""


	local absTargetDir=""
	local absTargetFile=""
	local targetFile=""

	while read -d '' -r -u3 absSrcFile; do
		absSrcDir="$("${DIRNAME}" "${absSrcFile}")"
		absTargetDir="${absSrcDir/${ABS_SRC_ROOT_DIR}/${ABS_TARGET_ROOT_DIR}}"

		targetFile="$("${BASENAME}" "${absSrcFile}" .flac).m4a"
		absTargetFile="${absTargetDir}/${targetFile}"

		if [ ! -d "${absTargetDir}" ]; then
			echo "-----------------------------------------------------------------------"
			echo "Creating directory '${absTargetDir}'"
			"${MKDIR}" -p "${absTargetDir}"
		fi
		
		doAAC "${absSrcFile}" "${absTargetFile}"
	done 3< <("${FIND}" "${ABS_SRC_ROOT_DIR}" -type f -name \*.flac -print0 | "${SORT}" -z)
}

# ----------------------------------------------------------------------------
PROGRAM=$(${BASENAME} "$0")
VERBOSE=0
FIX_METADATA=0
FIX_SYNC2=0
CREATE_PLAYLIST=0
ENCODING_PARAMS=( "${CBR[@]}" )

while getopts ":vmspb:" optname; do
	case "$optname" in
	"v")
		VERBOSE=1
		;;
	"b")
		if [ "$OPTARG" == "vbr" ]; then
			ENCODING_PARAMS=( "${VBR[@]}" )
		elif [ "$OPTARG" != "cbr" ] && [ "$OPTARG" != 'vbr' ]; then
			echo "Invalid parameter ${OPTARG}" >&2
			exit 1
		fi
		;;
	"m")
		FIX_METADATA=1
		;;
	"s")
		FIX_SYNC2=1
		;;
	"p")
		echo "Playlist are not implemented yet..."
		#CREATE_PLAYLIST=1
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
	ABS_SRC_ROOT_DIR="${PWD}/${1%/}"
elif [ -d "${1}" ]; then
	ABS_SRC_ROOT_DIR="${1%/}"
else
	echo "Invalid srcdir: '${1}'"
	exit 1
fi

if [ -d "${PWD}/${2}" ]; then
	ABS_TARGET_ROOT_DIR="${PWD}/${2%/}"
elif [ -d "${2}" ]; then
	ABS_TARGET_ROOT_DIR="${2%/}"
else
	echo "Invalid targetdir: '${2}'"
	exit 1
fi

transcode

echo "All done."

# Whenever you think something like "Why it's an one-liner, I'll put it in a file", don't do it and use python or whatever instead!
