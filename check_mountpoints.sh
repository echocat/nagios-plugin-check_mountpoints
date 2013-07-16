#!/bin/bash

# --------------------------------------------------------------------
# **** BEGIN LICENSE BLOCK *****
#
# Version: MPL 2.0
#
# echocat check_mountpoints.sh, Copyright (c) 2011-2012 echocat
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# **** END LICENSE BLOCK *****
# --------------------------------------------------------------------

# --------------------------------------------------------------------
# Check if all specified nfs/cifs/davfs mounts exist and if they are correct implemented.
# That means we check /etc/fstab, the mountpoints in the filesystem and if they
# are mounted. It is written for Linux, uses proc-Filesystem and was tested on
# Debian, OpenSuse 10.1 10.2 10.3 11.0, SLES 10.1 11.1, RHEL 5 6, CentOS 5 6 and solaris
#
# @author: Daniel Werdermann / dwerdermann@web.de
# @projectsite: https://github.com/echocat/nagios-plugin-check_mountpoints
# @version: 1.14
# @date: 2013-07-08 09:12:10 CEST
#
# changes 1.14
#  - better support for HP-UX, Icinga
#  - cleanup writecheck file after check
# changes 1.13
#  - add support for glusterfs
# changes 1.12
#  - add LIBEXEC path for OpenCSW-installed nagios in Solaris
# changes 1.11
#  - just update license information
# changes 1.10
#  - new flag -w results in a write test on the mountpoint
#  - kernel logger logs CRITICAL check results now as CRIT 
# changes 1.9
#  - new flag -i disable check of fstab (if you use automount etc.)
# changes 1.8
#  - fiexes for solaris support
#  - improved usage text
# changes 1.7
#  - new flag -A to autoread mounts from fstab and return OK if no mounts found in fstab
# changes 1.6
#  - new flag -a to autoread mounts from fstab and return UNKNOWN if no mounts found in fstab
#  - no mountpoints given returns state UNKNOWN instead of critical now
#  - parameter MTAB is used correctly on solaris now
#  - fix some minor bugs in the way variables were used
# changes 1.5
#  - returns error, if no mountpoints given
#  - change help text
# changes 1.4
#  - add support for davfs
#  - look for logger path via which command
#  - change shebang to /bin/bash
# changes 1.3
#  - add license information
# changes 1.2
#  - script doesnt hang on staled nfs mounts anymore
# changes 1.1
#  - support for nfs4
# changes 1.0
#  - support for solaris
# --------------------------------------------------------------------


# --------------------------------------------------------------------
# configuration
# --------------------------------------------------------------------
PROGNAME=$(basename $0)
ERR_MESG=()
LOGGER="`which logger` -i -p kern.warn -t"

AUTO=0
AUTOIGNORE=0
IGNOREFSTAB=0
WRITETEST=0

export PATH="/bin:/usr/local/bin:/sbin:/usr/bin:/usr/sbin:/usr/sfw/bin"
LIBEXEC="/opt/nagios/libexec /usr/lib64/nagios/plugins /usr/lib/nagios/plugins /usr/local/nagios/libexec /usr/local/icinga/libexec /usr/local/libexec /opt/csw/libexec/nagios-plugins"
for i in ${LIBEXEC} ; do
  [ -r ${i}/utils.sh ] && . ${i}/utils.sh
done

if [ -z "$STATE_OK" ]; then
  echo "nagios utils.sh not found" &>/dev/stderr
  exit 1
fi

KERNEL=`uname -s`
case $KERNEL in 
  # For solaris FSF=4 MF=3 FSTAB=/etc/vfstab MTAB=/etc/mnttab gnu grep and bash required
  SunOS) FSF=4
         MF=3
         FSTAB=/etc/vfstab
         MTAB=/etc/mnttab
         GREP=ggrep
         ;;
  HP-UX) FSF=3
         MF=2
         FSTAB=/etc/fstab
         MTAB=/dev/mnttab
         GREP=grep
         ;;
  *)     FSF=3
         MF=2
         FSTAB=/etc/fstab
         MTAB=/proc/mounts
         GREP=grep
         ;;
esac

# Time in seconds after which the check asumes that an NFS mounts is staled, if
# it do not respons. (default: 3)
TIME_TILL_STALE=3

# --------------------------------------------------------------------


# --------------------------------------------------------------------
# functions
# --------------------------------------------------------------------
function log() {
        $LOGGER ${PROGNAME} "$@";
}

function usage() {
        echo "Usage: $PROGNAME [-m FILE] \$mountpoint [\$mountpoint2 ...]"
        echo "Usage: $PROGNAME -h,--help"
        echo "Options:"
        echo " -m FILE     Use this mtab instead (default: ${MTAB})"
        echo " -f FILE     Use this fstab instead (default: ${FSTAB})"
        echo " -N NUMBER   FS Field number in fstab (default: ${FSF})"
        echo " -M NUMBER   Mount Field number in fstab (default: ${MF})"
        echo " -T SECONDS  Responsetime at which an NFS is declared as staled (default: ${TIME_TILL_STALE})"
        echo " -L          Allow softlinks to be accepted instead of mount points"
        echo " -i          Ignore fstab. Don't fail just because mount isn't in fstab. (default: unset)"
        echo " -a          Autoselect mounts from fstab (default: unset)"
        echo " -A          Autoselect from fstab. Return OK if no mounts found. (default: unset)"
        echo " -w          Writetest. Touch file \$mountpoint/.mount_test_from_\$(hostname) (default: unset)"
        echo " MOUNTPOINTS list of mountpoints to check. Ignored when -a is given"
}

function print_help() {
        echo ""
        usage
        echo ""
        echo "Check if nfs/cifs/davfs mountpoints are correct implemented and mounted."
        echo ""
        echo "This plugin is NOT developped by the Nagios Plugin group."
        echo "Please do not e-mail them for support on this plugin, since"
        echo "they won't know what you're talking about."
        echo ""
        echo "For contact info, read the plugin itself..."
}

# --------------------------------------------------------------------
# startup checks
# --------------------------------------------------------------------

if [ $# -eq 0 ]; then
        usage
        exit $STATE_CRITICAL
fi

while [ "$1" != "" ]
do
        case "$1" in
                -a) AUTO=1; shift;;
                -A) AUTO=1; AUTOIGNORE=1; shift;;
                --help) print_help; exit $STATE_OK;;
                -h) print_help; exit $STATE_OK;;
                -m) MTAB=$2; shift 2;;
                -f) FSTAB=$2; shift 2;;
                -N) FSF=$2; shift 2;;
                -M) MF=$2; shift 2;;
                -T) TIME_TILL_STALE=$2; shift 2;;
                -i) IGNOREFSTAB=1; shift;;
                -w) WRITETEST=1; shift;;
                -L) LINKOK=1; shift;;
                /*) MPS="${MPS} $1"; shift;;
                *) usage; exit $STATE_UNKNOWN;;
        esac
done

if [ ${AUTO} -eq 1 ]; then
        MPS=`${GREP} -v '^#' ${FSTAB} | awk '{if ($'${FSF}'=="nfs" || $'${FSF}'=="nfs4" || $'${FSF}'=="davfs" || $'${FSF}'=="cifs" || $'${FSF}'=="fuse" || $'${FSF}'=="glusterfs"){print $'${MF}' }}' | tr '\n' ' '`
fi

if [ -z "${MPS}"  ] && [ ${AUTOIGNORE} -eq 1 ] ; then
		echo "OK: no external mounts were found in ${FSTAB}"
		exit $STATE_OK
elif [ -z "${MPS}"  ]; then
        log "ERROR: no mountpoints given!"
        echo "ERROR: no mountpoints given!"
        usage
        exit $STATE_UNKNOWN
fi

if [ ! -f /proc/mounts -a "${MTAB}" == "/proc/mounts" ]; then
        log "CRIT: /proc wasn't mounted!"
        mount -t proc proc /proc
        ERR_MESG[${#ERR_MESG[*]}]="CRIT: mounted /proc $?"
fi

if [ ! -e "${MTAB}" ]; then
        log "CRIT: ${MTAB} don't exist!"
        echo "CRIT: ${MTAB} don't exist!"
        exit $STATE_CRITICAL
fi

# --------------------------------------------------------------------
# now we check if the given parameters ...
#  1) ... exist in the /etc/fstab
#  2) ... are mounted
#  3) ... df -k gives no stale
#  4) ... exist on the filesystem
#  5) ... is writable (optional)
# --------------------------------------------------------------------
for MP in ${MPS} ; do
        ## If its an OpenVZ Container or -a Mode is selected skip fstab check.
        ## -a Mode takes mounts from fstab, we do not have to check if they exist in fstab ;)
        if [ ! -f /proc/vz/veinfo -a ${AUTO} -ne 1 -a ${IGNOREFSTAB} -ne 1 ]; then
                awk '{if ($'${FSF}'=="nfs" || $'${FSF}'=="nfs4" || $'${FSF}'=="davfs" || $'${FSF}'=="cifs" || $'${FSF}'=="fuse" || $'${FSF}'=="glusterfs"){print $'${MF}'}}' ${FSTAB} | ${GREP} -q ${MP} &>/dev/null
                if [ $? -ne 0 ]; then
                        log "CRIT: ${MP} don't exists in /etc/fstab"
                        ERR_MESG[${#ERR_MESG[*]}]="${MP} don't exists in fstab ${FSTAB}"
                fi
        fi

        ## check kernel mounts
        ${GREP} "${MP}" ${MTAB} | ${GREP} -q -E "(nfs|nfs4|davfs|cifs|fuse|simfs|glusterfs)" ${MTAB} &>/dev/null
        if [ $? -ne 0 ]; then
        ## if a softlink is not an adequate replacement
        	if [ -z "$LINKOK" -o ! -L ${MP} ]; then
                	log "CRIT: ${MP} isn't mounted"
                	ERR_MESG[${#ERR_MESG[*]}]="${MP} isn't mounted"
                fi
        fi

        ## check if it stales
        df -k ${MP} &>/dev/null &
        DFPID=$!
        for (( i=1 ; i<$TIME_TILL_STALE ; i++ )) ; do
                if ps -p $DFPID > /dev/null ; then
                        sleep 1
                else
                        break
                fi
        done
        if ps -p $DFPID > /dev/null ; then
                $(kill -s SIGTERM $DFPID &>/dev/null)
                ERR_MESG[${#ERR_MESG[*]}]="${MP} doesnt response in $TIME_TILL_STALE sec. Seems to stale."
        else
        ## if it not stales, check if it is a directory
                if [ ! -d ${MP} ]; then
                        log "CRIT: ${MP} don't exists in filesystem"
                        ERR_MESG[${#ERR_MESG[*]}]="${MP} don't exists in filesystem"
                elif [ ${WRITETEST} -eq 1 ]; then
                ## if wanted, check if it is writable
                        TOUCHFILE=${MP}/.mount_test_from_$(hostname)
                        touch ${TOUCHFILE} &>/dev/null
                        if [ $? -ne 0 ]; then
                                log "CRIT: ${TOUCHFILE} is not writable."
                                ERR_MESG[${#ERR_MESG[*]}]="${TOUCHFILE} is not writable."
                        else
                                rm ${TOUCHFILE} &>/dev/null
                        fi
                fi
        fi

done

if [ ${#ERR_MESG[*]} -ne 0 ]; then
        echo -n "CRITICAL: "
        for element in "${ERR_MESG[@]}"; do
                echo -n ${element}" ; "
        done
        echo
        exit $STATE_CRITICAL
fi

echo "OK: all mounts were found (${MPS})"
exit $STATE_OK
