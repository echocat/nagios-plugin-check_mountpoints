#!/bin/bash
 
# --------------------------------------------------------------------
# **** BEGIN LICENSE BLOCK *****
#
# Version: MPL 1.1
#
# The contents of this file are subject to the Mozilla Public License Version
# 1.1 (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at
# http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS IS" basis,
# WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
# for the specific language governing rights and limitations under the
# License.
#
# The Original Code is echocat management.
#
# The Initial Developer of the Original Code is Daniel Werdermann.
# Portions created by the Initial Developer are Copyright (C) 2011
# the Initial Developer. All Rights Reserved.
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
# @version: 1.5
# @date: 2012-05-18 15:57:23 CEST
#
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
MTAB=/proc/mounts
 
export PATH="/bin:/usr/local/bin:/sbin:/usr/bin:/usr/sbin"
LIBEXEC="/usr/lib64/nagios/plugins /usr/lib/nagios/plugins /usr/local/nagios/libexec /usr/local/libexec"
for i in ${LIBEXEC};do
  [ -r ${i}/utils.sh ] && . ${i}/utils.sh
done
 
if [ -z "$STATE_OK" ];then
  echo "nagios utils.sh not found" &>/dev/stderr
  exit 1
fi
 
# For solaris FSF=4 MF=3 FSTAB=/etc/vfstab MTAB=/etc/mnttab gnu grep and bash required
FSTAB=/etc/fstab
FSF=3
MF=2
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
        echo " -m FILE   Use this mtab instead (default: /proc/mounts)"
        echo " -f FILE   Use this fstab instead (default: /etc/fstab)"
        echo " -N NUMBER   FS Field number in fstab (default: 3)"
        echo " -M NUMBER   Mount Field number in fstab (default: 2)"
        echo " -T SECONDS  Responsetime at which an NFS is declared as staled (default: 3)"
}
 
function print_help() {
        echo ""
        usage
        echo ""
        echo "Check if nfs/cifs mountpoints are correct implemented and mounted."
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
                --help) print_help; exit $STATE_OK;;
                -h) print_help; exit $STATE_OK;;
                -m) MTAB=$2; shift 2;;
                -f) FSTAB=$2; shift 2;;
                -N) FSF=$2; shift 2;;
                -M) MF=$2; shift 2;;
                -T) TIME_TILL_STALE=$2; shift 2;;
                /*) MPS="${MPS} $1"; shift;;
                *) usage; exit $STATE_UNKNOWN;;
        esac
done

if [ -z ${MPS} ]; then
		log "ERROR: no mountpoints given!"
		echo "ERROR: no mountpoints given!"
		usage
		exit $STATE_CRITICAL
fi

if [ ! -f /proc/mounts -a ${MTAB} = /proc/mounts ]; then
        log "WARN: /proc wasn't mounted!"
        mount -t proc proc /proc
        ERR_MESG[${#ERR_MESG[*]}]="WARN: mounted /proc $?"
fi
 
if [ ! -f ${MTAB} ]; then
        log "WARN: ${MTAB} don't exist!"
        echo "WARN: ${MTAB} don't exist!"
        exit $STATE_CRITICAL
fi
 
# --------------------------------------------------------------------
# now we check if the given parameters ...
#  1) ... exist in the /etc/fstab
#  2) ... are mounted
#  3) ... df -k gives no stale
#  4) ... exist on the filesystem
# --------------------------------------------------------------------
for MP in ${MPS} ; do
        ## if it is not an openVZ Container
        if [ ! -f /proc/vz/veinfo ]; then       
                awk '{if ($'${FSF}'=="nfs" || $'${FSF}'=="nfs4" || $'${FSF}'=="davfs" || $'${FSF}'=="cifs"){print $'${MF}'}}' ${FSTAB} | grep -q ${MP} &>/dev/null
                if [ $? -ne 0 ]; then
                        log "WARN: ${MP} don't exists in /etc/fstab"
                        ERR_MESG[${#ERR_MESG[*]}]="${MP} don't exists in /etc/fstab"
                fi
        fi
 
        ## check kernel mounts
        grep -E " ${MP} (cifs|nfs|nfs4|simfs|fuse) " -q /proc/mounts &>/dev/null
        if [ $? -ne 0 ]; then
                log "WARN: ${MP} isn't mounted"
                ERR_MESG[${#ERR_MESG[*]}]="${MP} isn't mounted"
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
                        log "WARN: ${MP} don't exists in filesystem"
                        ERR_MESG[${#ERR_MESG[*]}]="${MP} don't exists in filesystem"
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
