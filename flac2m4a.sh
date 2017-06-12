#!/bin/bash
# Needs bash due to used process substitutions '<(cmd_list)' or '>(cmd_list)'

# Readable 'set -e'
# Maybe one should not use it: http://mywiki.wooledge.org/BashFAQ/105
#set -o errexit
# Readable 'set -u'
set -o nounset
# Readable 'set -E'
set -o errtrace


VERSION="20170613_1"

# If AtomicParsley is not present the coverart image will not be written to
# the converted file, but everything will be fine otherwise.
# Install through homebrew with
# brew install atomicparsley --HEAD
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
FILE=/usr/bin/file
TR=/usr/bin/tr
CAT=/bin/cat
SEQ=/usr/bin/seq

# Add mappings of Vorbis tags to iTunes tags here.
# How it works: Each tag found in the source FLAC file is converted to lower
# case (because e.g. a song's name could stored in TITLE or Title) and
# compared to the string ahead of the colon of each defined mapping until a
# match is found (the string is also converted to lower case first).
# If a matching string is found, the string behind the colon is used as the
# iTunes tag name in the MP4 target file.
# This string is case sensitive!
#
# A basic overview for Vorbis:
# https://www.xiph.org/vorbis/doc/v-comment.html
# An overview for iTunes:
# https://code.google.com/archive/p/mp4v2/wikis/iTunesMetadata.wiki
TAG_MAPPINGS=()
TAG_MAPPINGS+=( "artist:ART" )
TAG_MAPPINGS+=( "title:nam" )
TAG_MAPPINGS+=( "album:alb" )
TAG_MAPPINGS+=( "date:day" )
TAG_MAPPINGS+=( "tracknumber:trkn" )
TAG_MAPPINGS+=( "genre:gen" )
TAG_MAPPINGS+=( "comment:cmt" )

# Install through homebrew with
# brew install flac --HEAD
FLAC=/usr/local/bin/flac
METAFLAC=/usr/local/bin/metaflac

# See http://wiki.hydrogenaud.io/index.php?title=Fraunhofer_FDK_AAC#fdkaac
# Install through homebrew with
# brew install fdk-aac-encoder
FDKAAC=/usr/local/bin/fdkaac

# See
# http://wiki.hydrogenaud.io/index.php?title=Fraunhofer_FDK_AAC
# for more info.
# Constant bitrate AAC encoding parameters:
CBR=( "--bitrate" "128000" )
# Variable bitrate AAC encoding parameters:
VBR=( "--bitrate-mode" "3" )

ABS_CURRENT_DIR=$("${PWD}")
ABS_TMP_DIR="${ABS_CURRENT_DIR}/tmpdir"

# On LogitechMediaServer I do not have the cover art embedded in each file,
# I have one JPG inside the album's directory.
# If a FLAC file does not have embedded cover art, use this file from the
# same directory the FLAC files are located instead.
# The value is just the file name without a path.
ALBUM_COVERART_FILE="Front.jpg"

# File flagging an album as being gapless (e.g. a live album).
# When '-g' is used, FLAC files located in the same directory as this file
# will be processed as gapless. For directories without this file '-g' is ignored.
GAPLESS_ALBUM_FLAG_FILE=".gapless"

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

	log "${DETAILS_LEVEL}" "Mapping '${stringType}' characters:"

	if  [ "${stringType}" == "artist" ]; then
		############## Put mappings for <artist> below. ######################
		# The Ramones / the OtherArtist -> Ramones / The OtherArtist
		stringMappings+=( "s/^[Tt]he//" )
		# Ramones / the OtherArtist -> Ramones /OtherArtist
		stringMappings+=( "s/\/[[:blank:]]*[Tt]he /\//" )
		# Ramones/ OtherArtist -> Ramones And OtherArtist
		# Ramones \OtherArtist -> Ramones And OtherArtist
		stringMappings+=( "s/[[:blank:]]*[\/\\][[:blank:]]*/ And /" )
		############## Put mappings for <artist> above. ######################
	elif [ "${stringType}" == "album" ]; then
		############## Put mappings for <album> below. #######################
		# What / Ever -> What Ever
		# What \Ever -> What Ever
		stringMappings+=( "s/[[:blank:]]*\/[[:blank:]]*/ /" )
		# It's Alive -> Its Alive
		stringMappings+=( "s/'//" )
		############## Put mappings for <album> above. #######################
	else
		# Should never get here...
		logError "Unknown string type - characters will not be mapped!"
	fi

	for mapping in "${stringMappings[@]}"; do
		local originalString
		originalString="${stringValue}"
		stringValue=$("${SED}" "${mapping}" <<< "${stringValue}")
		if [ "${originalString}" != "${stringValue}" ]; then
			log "${DETAILS_LEVEL}" "${originalString} -> ${stringValue}"
		fi
	done

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
   Level 0: (no -v) Warnings and errors only
   Level 1: Processed files
   LeveL 2: Tasks (Encoding to AAC, Adding cover art,...)
   Level 3: Subtasks (Task: Adding cover art; Subtask: Detecting file type,...)
   Level 4: Details (e.g. Mappings)
   Level 5: (-vvvvv) Executed commands

-b toggles between constant and variable bitrate. Default is VBR.

-t Ford'"'"'s SYNC2 ignores track numbers and plays the tracks sorted
   alphabetically by their title tag.
   The switch fixes SYNC2'"'"'s brain dead alphabetic play order to track order by
   adding the track number to the title tag ('"'"'Some Title'"'"' -> '"'"'03 Some Title'"'"').

-g gapless mode - creates pgag and iTunSMPB in the converted file. A user
   configurable file is required to exist in the same directory as the source
   file(s), otherwise the source file(s) will not be processed as gapless.

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

	log "${TASK_LEVEL}" "Fixing SYNC2 issues..."
	logRun "${SED}" -i "" "s/${titleMetadataTag}=/${titleMetadataTag}=${trackMetadataFormattedValue} /" "${ABS_TMP_METADATA_FILE}"

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function addFileToTmpPlaylist()
{
	((NESTING_LEVEL++))

	local relTargetFile="$1"

	log "${TASK_LEVEL}" "Creating temporary playlist entry..."

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
	mapCharacters "${albumMetadataValue}" "album"
	mappedAlbumMetadataValue="${___}"

	# The artist value.
	local artistMetadataValue
	artistMetadataValue=$("${GREP}" -im 1 ^artist "${ABS_TMP_METADATA_FILE}" | "${SED}" s/"^.*="//)

	# Mapped artist value.
	local mappedArtistMetadataValue
	mapCharacters "${artistMetadataValue}" "artist"
	mappedArtistMetadataValue="${___}"

	# Filename of the temp. playlist file.
	local tmpPlaylistFilename
	tmpPlaylistFilename="${mappedArtistMetadataValue} ${mappedAlbumMetadataValue}"

	if (( CREATE_DOS_PLAYLIST )); then
		# x/y/z/aa.m4a -> \x\y\z\aa.m4a
		relTargetFile="\\${relTargetFile//\//\\}"
	fi

	# 00010###x/y/z/aa.m4a >> /a/b/c/targetdir/<titletag>.m3u.tmp
	local tmpPlaylistEntry="${trackMetadataFormattedValue}###${relTargetFile}"
	log "${DETAILS_LEVEL}" "Temporary playlist entry: ${tmpPlaylistEntry}"
	echo "${tmpPlaylistEntry}" >> "${ABS_TARGET_ROOT_DIR}/${tmpPlaylistFilename}.m3u.tmp"

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function logWarn()
{
	local message="$1"

	# Log to stderr
	log "${ERROR_LEVEL}" "${RED}${message}${NOCOLOR}" 1>&2
}

# ----------------------------------------------------------------------------
# TODO
#function logError()
#{
#	local message="$1"
#
#	# Redirect stdout to stderr (line won't be shown on the terminal), but
#	# can be written to a file with './flac2m4a.sh ... 2>errfile'
#	echo "xxxxxxxxxxxAdditional error log information" 1>&2
#	# Pipe stdout into tee which duplicates it to a "file" (1st) (the process
#	# substitution) and redirect tee's 2nd output (2nd) (which goes to stdout)
#	# to stderr.
#	# With './flac2m4a.sh ... 2>errfile' the (1st) output is written to stdout
#	# and the (2nd) output to stderr is redirected to 'errfile'.
#	# BUT: The messages will be output TWICE if stderr is not redirected...
#	log "${ERROR_LEVEL}" "${LIGHTRED}${message}${NOCOLOR}" | tee >(cat >&1) 1>&2
#}
function logError()
{
	local message="$1"

	log "${ERROR_LEVEL}" "${LIGHTRED}${message}${NOCOLOR}" 1>&2
}

# ----------------------------------------------------------------------------
function log()
{
	local logLevel=$1
	local message="$2"

	if (( VERBOSITY >= logLevel )); then
		local nestingChars
		nestingChars=""
		# Output a "+" for nested shells only.
		if (( NESTING_LEVEL > 0 )); then
			# FYI: ".0" truncates the output at 0 chars, i.e. suppresses output.
			# FYI: +%s -> +1+2+3
			# FYI: +%.0s -> +++
			nestingChars=$(printf '  %.0s' $("${SEQ}" -s ' ' 1 $NESTING_LEVEL))
		fi

		echo -e "${nestingChars}${message}"
	fi
}

# ----------------------------------------------------------------------------
function logRun()
{
	local commands=("$@")

	if (( VERBOSITY >= COMMAND_LEVEL )); then
		# Readable 'set -x'
		(set -o xtrace; "${commands[@]}") || return 1
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

	log "${TASK_LEVEL}" "Exporting metadata..."
	logRun "${METAFLAC}" "${metaflacMedataArgs[@]}" "${absSrcFile}"

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function processCoverart()
{
	((NESTING_LEVEL++))

	local absSrcFile="$1"
	local absTargetFile="$2"

	log "${TASK_LEVEL}" "Processing cover art..."

	local existsEmbeddedCoverartFile=0
	while read -r -u3 coverArtMetadataBlockLine; do
		exportEmbeddedCoverart "${absSrcFile}" "${coverArtMetadataBlockLine##*#}"
		addCoverart "${absTargetFile}" "${ABS_TMP_COVERART_FILE}" "embedded"
		existsEmbeddedCoverartFile=1
	# FYI: grep returns 1 on an empty selection (i.e. when the metadata contains
	# no metadata block). This triggers the ERR trap, which is wrong - script
	# should not exit when there is no embedded cover art.
	# Exit subshell with 0 on grep's retval 0 or 1 and exit with 1 otherwise.
	done 3< <("${METAFLAC}" --list --block-type=PICTURE "${absSrcFile}" | "${GREP}" "METADATA block" || (( $? == 1 )) && exit 0 || exit 1 )

	# If there was no embedded cover art in the source file, try to add a copy
	# of the file from the album's directory.
	if (( ! existsEmbeddedCoverartFile )); then
		if [ -f "${absSrcFile%/*}/${ALBUM_COVERART_FILE}" ]; then
			copyAbsFile "${SUBTASK_LEVEL}" "${absSrcFile%/*}/${ALBUM_COVERART_FILE}" "${ABS_TMP_DIR}/${ALBUM_COVERART_FILE}" "Creating working copy of the album cover art file..."
			addCoverart "${absTargetFile}" "${ABS_TMP_DIR}/${ALBUM_COVERART_FILE}" "album"
		else
			logWarn "Cover art not available."
		fi
	fi

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function exportEmbeddedCoverart()
{
	((NESTING_LEVEL++))

	local absSrcFile="$1"
	local coverArtBlock="$2"

	log "${SUBTASK_LEVEL}" "Exporting cover art file (FLAC metadata block ${coverArtBlock})..."
	logRun "${METAFLAC}" --block-number="${coverArtBlock}" --export-picture-to="${ABS_TMP_COVERART_FILE}" "${absSrcFile}"

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function getFileExtension()
{
	((NESTING_LEVEL++))

	local absSrcCoverartFile="$1"

	log "${SUBTASK_LEVEL}" "Detecting file extension..."
	local fileExtensions
	fileExtensions=$("${FILE}" -b --extension "${absSrcCoverartFile}")

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
function addExtensionToFile()
{
	((NESTING_LEVEL++))

	local absSrcCoverartFile="$1"
	local fileExtension="$2"

	log "${SUBTASK_LEVEL}" "Adding extension to cover art file (${fileExtension})..."
	# /some/path/<name> -> /some/path/<name>.XXX
	logRun "${MV}" "${absSrcCoverartFile}" "${absSrcCoverartFile}.${fileExtension}"

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

	# FYI: AtomicParsley (0.9.6) segfaults when adding cover art files that
	# need to be reencoded and do not have a file extension:
	# 'AtomicParsley input.m4a --artwork file1 --overWrite' segfaults, while
	# 'AtomicParsley input.m4a --artwork file1.asd --overWrite' works.
	# 'asd' is not a placeholder - it seems as if any extension was fine.
	local absSrcCoverartFileWithExtension

	# Check if cover art file has a file extension (a dot in the basename).
	if [[ "${absSrcCoverartFile##*/}" == *.* ]]; then
		absSrcCoverartFileWithExtension="${absSrcCoverartFile}"
	else
		local fileExtension
		fileExtension="UNKNOWN"
		log "${SUBTASK_LEVEL}" "Fixing missing file extension..."

		getFileExtension "${absSrcCoverartFile}"
		fileExtension="${__}"

		addExtensionToFile "${absSrcCoverartFile}" "${fileExtension}"
		absSrcCoverartFileWithExtension="${absSrcCoverartFile}.${fileExtension}"
	fi

	log "${SUBTASK_LEVEL}" "Importing cover art (${embeddableCoverartType} file)..."
	logRun "${ATOMICPARSLEY}" "${absTargetFile}" --artwork "${absSrcCoverartFileWithExtension}" --overWrite 1>/dev/null

	removeAbsFile "${SUBTASK_LEVEL}" "${absSrcCoverartFileWithExtension}" "Deleting exported cover art file..."

	# AtomicParsley does not delete it's temporary files created during resizing.
	# The cover art file 'some file.j.pg' is stored as e.g. 'some file.j-resized-1234.pg'
	# Find files where the last dot in filename was replaced by '-resized-[0-9]+.'
	removeAbsFilesByPattern "${SUBTASK_LEVEL}" \
		"${absSrcCoverartFileWithExtension%.*}-resized-[[:digit:]]+.${absSrcCoverartFileWithExtension##*.}" \
		"Deleting temporary file(s) left over by AtomicParsley..."

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function copyAbsFile()
{
	((NESTING_LEVEL++))

	local logLevel="$1"
	local absSrcFile="$2"
	local absTargetFile="$3"
	local message="$4"

	if [ -f "${absSrcFile}" ]; then
		# Log only if message is not an empty string.
		if [ ! -z "${message}" ]; then log "${logLevel}" "${message}"; fi
		logRun "${CP}" -i "${absSrcFile}" "${absTargetFile}"
	else
		# Should never get here...
		logError "File not found: '${absSrcFile}'"
	fi

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function removeAbsFilesByPattern()
{
	((NESTING_LEVEL++))

	local logLevel="$1"
	local absFilePattern="$2"
	local message="$3"

	# Log only if message is not an empty string.
	if [ ! -z "${message}" ]; then log "${logLevel}" "${message}"; fi
	while read -r -u3 absMatchingFile; do
		removeAbsFile "${logLevel}" "${absMatchingFile}" ""
	done 3< <("${FIND}" -E "${absFilePattern%/*}" -type f -maxdepth 1 -regex "${absFilePattern}" )

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function removeAbsFile()
{
	((NESTING_LEVEL++))

	local logLevel="$1"
	local absFile="$2"
	local message="$3"

	if [ -f "${absFile}" ]; then
		# Log only if message is not an empty string.
		if [ ! -z "${message}" ]; then log "${logLevel}" "${message}"; fi
		logRun "${RM}" "${absFile}"
	fi

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function createDirectory()
{
	((NESTING_LEVEL++))

	local logLevel="$1"
	local absDirectoryPath="$2"

	log "${logLevel}" "Creating directory '${absDirectoryPath}'..."
	logRun "${MKDIR}" -p "${absDirectoryPath}"

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function createPlaylist()
{
	((NESTING_LEVEL++))

	local absTmpPlaylistFile="$1"

	log "${TASK_LEVEL}" "Creating playlist '${absTmpPlaylistFile%.*}'..."
	logRun "${SORT}" "${absTmpPlaylistFile}" -o "${absTmpPlaylistFile%.*}"
	logRun "${SED}" -i "" s/"^[0-9]*###"// "${absTmpPlaylistFile%.*}"
	removeAbsFile "${SUBTASK_LEVEL}" "${absTmpPlaylistFile}" "Removing temporary playlist file..."

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function doWAV()
{
	((NESTING_LEVEL++))

	local absSrcFile="$1"

	local flacDecoderArgs=( "-s" "-d" "-f" )
	# process 1s only.
	local flacTestArgs=( "--until=0:01.00" )

	local flacAllArgs=( "${flacDecoderArgs[@]}" )
	if (( TEST_ONLY )); then flacAllArgs+=( "${flacTestArgs[@]}" ); fi

	log "${TASK_LEVEL}" "Decoding FLAC -> WAV..."
	logRun "${FLAC}" "${flacAllArgs[@]}" "${absSrcFile}" "-o" "${ABS_TMP_WAV_FILE}"

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
	# See
	# https://sourceforge.net/p/mediainfo/feature-requests/398/
	# for more info on iTunSMPB.
	local fdkaacBaseArgs=( "--ignorelength" "--silent")
	local fdkaacEncoderArgs=( "--profile" "2" "${ENCODING_ARGS[@]}" )
	local fdkaacGaplessArgs=( "--gapless-mode" "2" "--tag" "pgap:1" )

	local fdkaacAllArgs=( "${fdkaacBaseArgs[@]}" )
	fdkaacAllArgs+=( "${fdkaacEncoderArgs[@]}" )
	if (( IS_GAPLESS )) && [ -f "${absSrcFile%/*}/${GAPLESS_ALBUM_FLAG_FILE}" ]; then fdkaacAllArgs+=( "${fdkaacGaplessArgs[@]}" ); fi

	local tagArgs=()
	createMetadataTagArgs
	tagArgs=( "${____[@]}" )

	log "${TASK_LEVEL}" "Encoding WAV -> AAC"
	logRun "${FDKAAC}" "${fdkaacAllArgs[@]}" "${tagArgs[@]}" -o "${absTargetFile}" "${ABS_TMP_WAV_FILE}"

	((NESTING_LEVEL--))
}

# ----------------------------------------------------------------------------
function createMetadataTagArgs()
{
	((NESTING_LEVEL++))

	local tagArgs=()

	log "${SUBTASK_LEVEL}" "Creating --tag arguments for FDKAAC..."
	while read -r -u3 metadataLine; do
		# FYI: title-tag could be "TITLE" or "Title". Lowercase for comparison.
		# In Bash4 one could use ${someVariable,,}
		local metadataLowercaseTag
		metadataLowercaseTag=$("${TR}" '[:upper:]' '[:lower:]' <<< "${metadataLine%%=*}")

		local metadataValue
		metadataValue="${metadataLine##*=}"

		local hasMapping=0
		for mapping in "${TAG_MAPPINGS[@]}"; do
			local mapableLowercaseTag
			mapableLowercaseTag=$("${TR}" '[:upper:]' '[:lower:]' <<< "${mapping%%:*}")
			if [ "${metadataLowercaseTag}" == "${mapableLowercaseTag}" ]; then
				hasMapping=1
				tagArgs+=( "--tag" "${mapping##*:}:${metadataValue}" )
				log "${DETAILS_LEVEL}" "Mapping ${metadataLine} -> --tag ${mapping##*:}:${metadataValue}"
				break
			fi
		done
		if (( hasMapping == 0 )); then
			# TODO - this should be output to a summary or something.
			logWarn "Mapping for FLAC tag '${metadataLowercaseTag}' not found - tag will be skipped."
		fi
	done 3< <("${CAT}" "${ABS_TMP_METADATA_FILE}" )

	____=( "${tagArgs[@]}" )

	((NESTING_LEVEL--))

	return 0
}

# ----------------------------------------------------------------------------
function processTemporaryPlaylists()
{
	log "${FILE_LEVEL}" "Creating playlists..."
	while read -d '' -r -u3 absTmpPlaylistFile; do
		createPlaylist "${absTmpPlaylistFile}"
	done 3< <("${FIND}" "${ABS_TARGET_ROOT_DIR}" -type f -name \*.m3u.tmp -print0)
}

# ----------------------------------------------------------------------------
function processSrcFile()
{
	local absSrcFile="$1"
	local absTargetFile="$2"

	exportMetadata "${absSrcFile}"

	if (( FIX_SYNC2 )); then fixSync2; fi

	doWAV "${absSrcFile}"

	doAAC "${absSrcFile}" "${absTargetFile}"

	removeAbsFile "${SUBTASK_LEVEL}" "${ABS_TMP_WAV_FILE}" "Deleting WAV file..."

	if (( HAS_ATOMICPARSLEY )); then processCoverart "${absSrcFile}" "${absTargetFile}"; fi

	if (( CREATE_UNIX_PLAYLIST || CREATE_DOS_PLAYLIST )); then
		# Target file relative to root target dir.
		# ( /a/b/c/targetdir/x/y/z/aa.m4a -> x/y/z/aa.m4a )
		addFileToTmpPlaylist "${absTargetFile#${ABS_TARGET_ROOT_DIR}/}"
	fi

	removeAbsFile "${SUBTASK_LEVEL}" "${ABS_TMP_METADATA_FILE}" "Deleting exported metadata file..."
}

# ----------------------------------------------------------------------------
function showJobSummary()
{
	local playlistType="False"
	if (( CREATE_UNIX_PLAYLIST )); then playlistType="With '/' separators"; fi
	if (( CREATE_DOS_PLAYLIST )); then playlistType="With '\\' separators"; fi

	local params=(
			"${ABS_SRC_ROOT_DIR}"
			"${ENCODING_ARGS[*]}"
			"$( (( FIX_SYNC2 )) && echo "True" || echo "False" )"
			"$( (( IS_GAPLESS )) && echo "True" || echo "False" )"
			"${playlistType}"
			"$( (( RESIZE_COVER )) && echo "True" || echo "False" )"
			"$( (( TEST_ONLY )) && echo "True" || echo "False" )"
			"${ABS_TARGET_ROOT_DIR}")

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
	if (( HAS_ATOMICPARSLEY == 0 )); then
		logWarn "AtomicParsley not found. Cover art will not be processed."
	fi

	if (( JOB_SUMMARY )); then
		showJobSummary
		exit 0
	fi

	while read -d '' -r -u3 absSrcFile; do
		local absTargetFile="${absSrcFile/${ABS_SRC_ROOT_DIR}/${ABS_TARGET_ROOT_DIR}}"
		absTargetFile="${absTargetFile/.flac/.m4a}"

		if [ ! -d "${absTargetFile%/*}" ]; then
			log "${TASK_LEVEL}" "-----------------------------------------------------------------------"
			createDirectory "${TASK_LEVEL}" "${absTargetFile%/*}"
		fi

		log "${TASK_LEVEL}" "-----------------------------------------------------------------------"
		log "${FILE_LEVEL}" "Processing '${absSrcFile}'..."
		processSrcFile "${absSrcFile}" "${absTargetFile}"
	done 3< <("${FIND}" "${ABS_SRC_ROOT_DIR}" -type f -name \*.flac -print0 | "${SORT}" -z)

	if (( CREATE_UNIX_PLAYLIST || CREATE_DOS_PLAYLIST )); then
		log "${TASK_LEVEL}" "-----------------------------------------------------------------------"
		processTemporaryPlaylists
		log "${TASK_LEVEL}" "-----------------------------------------------------------------------"
	fi

	log "${FILE_LEVEL}" "All done."
}

function handleError() {
  local lineNumber="$1"

  echo "Exiting due to an error near line ${lineNumber}."
  exit 1
}

#############################################################################
PROGRAM="${0##*/}"

VERBOSITY=0
ENCODING_ARGS=( "${VBR[@]}" )
FIX_SYNC2=0
IS_GAPLESS=0
CREATE_UNIX_PLAYLIST=0
CREATE_DOS_PLAYLIST=0
RESIZE_COVER=0
JOB_SUMMARY=0
TEST_ONLY=0

NESTING_LEVEL=0

ERROR_LEVEL=0
FILE_LEVEL=1
TASK_LEVEL=2
SUBTASK_LEVEL=3
DETAILS_LEVEL=4
COMMAND_LEVEL=5

ABS_TMP_WAV_FILE="${ABS_TMP_DIR}/audiofile.wav"
ABS_TMP_METADATA_FILE="${ABS_TMP_DIR}/metadata"
ABS_TMP_COVERART_FILE="${ABS_TMP_DIR}/coverart"

RED='\033[0;31m'
LIGHTRED='\033[1;31m'
NOCOLOR='\033[0m'

trap 'handleError ${LINENO}' ERR

HAS_ATOMICPARSLEY=0
if [ -f "${ATOMICPARSLEY}" ]; then HAS_ATOMICPARSLEY=1; fi

while getopts ":vb:tgpqjrx" optname; do
	case "$optname" in
	"v")
		(( VERBOSITY++ ))
		;;
	"b")
		if [ "$OPTARG" == "cbr" ]; then
			ENCODING_ARGS=( "${CBR[@]}" )
		elif [ "$OPTARG" != "cbr" ] && [ "$OPTARG" != 'vbr' ]; then
			logError "Invalid parameter ${OPTARG}"
			exit 1
		fi
		;;
	"t")
		FIX_SYNC2=1
		;;
	"g")
		if (( HAS_ATOMICPARSLEY )); then
			IS_GAPLESS=1
		else
			logError "Cannot use -g without AtomicParsley"
		fi
		;;
	"p")
		CREATE_UNIX_PLAYLIST=1
		if (( CREATE_UNIX_PLAYLIST && CREATE_DOS_PLAYLIST )); then
			logError "Cannot use -p together with -q"
			exit 1
		fi
		;;
	"q")
		CREATE_DOS_PLAYLIST=1
		if (( CREATE_DOS_PLAYLIST && CREATE_UNIX_PLAYLIST )); then
			logError "Cannot use -q together with -p"
			exit 1
		fi
		;;
	"r")
		if (( HAS_ATOMICPARSLEY )); then
			RESIZE_COVER=1
		else
			logError "Cannot use -r without AtomicParsley"
		fi
		;;
	"j")
		JOB_SUMMARY=1
		;;
	"x")
		TEST_ONLY=1
		;;
	"?")
		logError "Invalid option: -$OPTARG"
		exit 1
		;;
	":")
		logError "Option -$OPTARG requires an argument."
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
	ABS_SRC_ROOT_DIR="${ABS_CURRENT_DIR}/${1%/}"
elif [ -d "${1}" ]; then
	ABS_SRC_ROOT_DIR="${1%/}"
else
	logError "Invalid srcdir: '${1}'"
	exit 1
fi

if [ -d "${ABS_CURRENT_DIR}/${2}" ]; then
	ABS_TARGET_ROOT_DIR="${ABS_CURRENT_DIR}/${2%/}"
elif [ -d "${2}" ]; then
	ABS_TARGET_ROOT_DIR="${2%/}"
else
	logError "Invalid targetdir: '${2}'"
	exit 1
fi

run

# Whenever you think something like "Why it's an one-liner, I'll put it in a file", don't do it and use python or whatever instead!
