#!/usr/bin/env bash

# --------------------------------------------------------------------
# **** BEGIN LICENSE BLOCK *****
#
# Version: MPL 2.0
#
# echocat check_mountpoints.sh, Copyright (c) 2011-2015 echocat
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
# Debian, OpenSuse 10.1 10.2 10.3 11.0, SLES 10.1 11.1, RHEL/CentOS 5 6 7, FreeBSD and solaris
#
# @author: Daniel Werdermann / dwerdermann@web.de
# @projectsite: https://github.com/echocat/nagios-plugin-check_mountpoints
# @version: 2.4
# @date: 2017-12-03 21:25:00 CEST
#
# changes 2.5
#  - added performance data (for nagiosgraph or pnp4nagios)
#  - changed parameter for writable to (uppercase) -W (to free -w for warning acconding dev guidelines https://nagios-plugins.org/doc/guidelines.html)
#  - added -w and -c params for warning and critical thresholds
# changes 2.4
#  - add support for ext2
# changes 2.3
#  - add support for btrfs
# changes 2.2
#  - add support for ceph
# changes 2.1
#  - clean output when mount point is stalled
# changes 2.0
#  - add support for FreeBSD
#  - ignore trailing slashes on mounts
# changes 1.22
#  - add support for ext3, ext4, auto
# changes 1.21
#  - add support for lustre fs
# changes 1.20
#  - better check on write test
# changes 1.19
#  - for write test, use filename, which is less prone to race conditions
# changes 1.18
#  - write check respects stale timeout now
# changes 1.17
#  - add support for ocfs2
# changes 1.16
#  - minor English fixes
# changes 1.15
#  - fix bad bug in MTAB check
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
NOAUTOCOND=1
NOAUTOIGNORE=0
DFARGS=''
EXCLUDE=none

export PATH="/bin:/usr/local/bin:/sbin:/usr/bin:/usr/sbin:/usr/sfw/bin"
LIBEXEC="/opt/nagios/libexec /usr/lib64/nagios/plugins /usr/lib/nagios/plugins /usr/lib/monitoring-plugins /usr/local/nagios/libexec /usr/local/icinga/libexec /usr/local/libexec /opt/csw/libexec/nagios-plugins /opt/plugins /usr/local/libexec/nagios/"
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
         OF=6
         NOAUTOSTR=no
         FSTAB=/etc/vfstab
         MTAB=/etc/mnttab
         GREP=ggrep
         ;;
  HP-UX) FSF=3
         MF=2
         OF=4
         NOAUTOSTR=noauto
         FSTAB=/etc/fstab
         MTAB=/dev/mnttab
         GREP=grep
         ;;
  FreeBSD) FSF=3
         MF=2
         OF=4
         NOAUTOSTR=noauto
         FSTAB=/etc/fstab
         MTAB=none
         GREP=grep
         ;;
  *)     FSF=3
         MF=2
         OF=4
         NOAUTOSTR=noauto
         FSTAB=/etc/fstab
         MTAB=/proc/mounts
         GREP=grep
         ;;
esac

# Time in seconds after which the check assumes that an NFS mount is staled, if
# it does not respond. (default: 3)
TIME_TILL_STALE=3
WARN_TIME=3
CRIT_TIME=3
CURRENT_STATE=$STATE_OK
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
        echo " -O NUMBER   Option Field number in fstab (default: ${OF})"
        echo " -T SECONDS  Responsetime at which an NFS is declared as staled (default: ${TIME_TILL_STALE})"
        echo " -w SECONDS  Warning threshold for responsetime of an NFS mount (default: ${WARN_TIME})"
        echo " -c SECONDS  Critical threshold for responsetime of an NFS mount (default: ${CRIT_TIME})"
        echo " -L          Allow softlinks to be accepted instead of mount points"
        echo " -i          Ignore fstab. Do not fail just because mount is not in fstab. (default: unset)"
        echo " -a          Autoselect mounts from fstab (default: unset)"
        echo " -A          Autoselect from fstab. Return OK if no mounts found. (default: unset)"
        echo " -E PATH     Use with -a or -A to exclude a path from fstab. Use '\|' between paths for multiple. (default: unset)"
        echo " -o          When autoselecting mounts from fstab, ignore mounts having noauto flag. (default: unset)"
        echo " -W          Writetest. Touch file \$mountpoint/.mount_test_from_\$(hostname) (default: unset)"
        echo " -e ARGS     Extra arguments for df (default: unset)"
        echo " MOUNTPOINTS list of mountpoints to check. Ignored when -a is given"
}

function print_help() {
        echo ""
        usage
        echo ""
        echo "Check if nfs/cifs/davfs mountpoints are correctly implemented and mounted."
        echo ""
        echo "This plugin is NOT developped by the Nagios Plugin group."
        echo "Please do not e-mail them for support on this plugin, since"
        echo "they won't know what you're talking about."
        echo ""
        echo "For contact info, read the plugin itself..."
}

# Create a temporary mtab systems that don't have such a file
# Format is dev mountpoint filesystem
function make_mtab() {
        mtab=$(mktemp)
        mount > $mtab
        sed -i '' 's/ on / /' $mtab
        sed -i '' 's/ (/ /' $mtab
        sed -i '' 's/,.*/ /' $mtab
        echo $mtab
}

function measure_exectime() {
        # check params
        DFPID=$1
        POSTFIX=$2
        # compute relevant timestamps
        start_at=$(date +%s.%N)
        stale_at=$(bc <<< "$start_at + ${TIME_TILL_STALE}")
        # loop until process is ended or stale-time is reached
        while [ $(bc <<< "scale=2; ($(date +%s.%N) < $stale_at)") ]; do
                if ps -p $DFPID > /dev/null ; then
                        sleep 0.01
                else
                        break
                fi
        done
        # set endtime and compute duration of process
        end_at=$(date +%s.%N)
#        time_cost=$(bc <<< 'scale=3; x=(${end_at} - ${start_at})/1; if(x<1){"0"}; x')
        time_cost=$(bc <<< "scale=3; (${end_at} - ${start_at})/1")
        if [[ ${time_cost:0:1} == "." ]]; then time_cost="0"${time_cost}; fi    # ensure leading zero!
        warn_at=$(bc <<< "$start_at + ${WARN_TIME}")
        crit_at=$(bc <<< "$start_at + ${CRIT_TIME}")
        # set (global) performance data
        PERFDATA="${PERFDATA}'${MP}${POSTFIX}'=${time_cost}s;${WARN_TIME};${CRIT_TIME};0;${TIME_TILL_STALE} "
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
                -E) EXCLUDE=$2; shift 2;;
                -o) NOAUTOIGNORE=1; shift;;
                --help) print_help; exit $STATE_OK;;
                -h) print_help; exit $STATE_OK;;
                -m) MTAB=$2; shift 2;;
                -f) FSTAB=$2; shift 2;;
                -N) FSF=$2; shift 2;;
                -M) MF=$2; shift 2;;
                -O) OF=$2; shift 2;;
                -w) WARN_TIME=$2; shift 2;;
                -c) CRIT_TIME=$2; shift 2;;
                -T) TIME_TILL_STALE=$2; shift 2;;
                -i) IGNOREFSTAB=1; shift;;
                -W) WRITETEST=1; shift;;
                -L) LINKOK=1; shift;;
                -e) DFARGS=$2; shift 2;;
                /*) MPS="${MPS} $1"; shift;;
                *) usage; exit $STATE_UNKNOWN;;
        esac
done

# adjust warn, crit and stale threshold if applicable
if [ ${WARN_TIME} -gt ${CRIT_TIME} ]; then WARN_TIME=${CRIT_TIME}; fi
if [ ${TIME_TILL_STALE} -lt ${CRIT_TIME} ]; then TILE_TILL_STALE=${CRIT_TIME}; fi

# ZFS file system have no fstab. Make on
if [ -x '/sbin/zfs' ]; then
        TMPTAB=$(mktemp)
        cat ${FSTAB} > ${TMPTAB}
        for DS in $(zfs list -H -o name); do
                MP=$(zfs get -H mountpoint ${DS} |awk '{print $3}')
                # mountpoint ~ "none|legacy|-"
                if [ ! -d "$MP" ]; then
                        continue
                fi
                if [ $(zfs get -H canmount ${DS} |awk '{print $3}') == 'off' ]; then
                        continue
                fi
                case $KERNEL in
                        SunOS)
                        if [ $(zfs get -H zoned ${DS} |awk '{print $3}') == 'on' ]; then
                                continue
                        fi
                        ;;
                        FreeBSD)
                        if [ $(zfs get -H jailed ${DS} |awk '{print $3}') == 'on' ]; then
                                continue
                        fi
                        ;;
                esac
                RO=$(zfs get -H readonly ${DS} |awk '($3 == "on"){print "ro"}')
                [ -z "$RO" ] &&  RO='rw'
                echo -e "$DS\t$MP\tzfs\t$RO\t0\t0" >> ${TMPTAB}
        done
        FSTAB=${TMPTAB}
fi

if [ ${AUTO} -eq 1 ]; then
        if [ ${NOAUTOIGNORE} -eq 1 ]; then
                 NOAUTOCOND='!index($'${OF}',"'${NOAUTOSTR}'")'
        fi
        if [ "${EXCLUDE}" == "none" ]; then
                MPS=`${GREP} -v '^#' ${FSTAB} | awk '{if ('${NOAUTOCOND}'&&($'${FSF}'=="ext2" || $'${FSF}'=="ext3" || $'${FSF}'=="xfs" || $'${FSF}'=="auto" || $'${FSF}'=="ext4" || $'${FSF}'=="nfs" || $'${FSF}'=="nfs4" || $'${FSF}'=="davfs" || $'${FSF}'=="cifs" || $'${FSF}'=="fuse" || $'${FSF}'=="glusterfs" || $'${FSF}'=="ocfs2" || $'${FSF}'=="lustre" || $'${FSF}'=="ufs" || $'${FSF}'=="zfs" || $'${FSF}'=="ceph" || $'${FSF}'=="btrfs" || $'${FSF}'=="yas3fs"))print $'${MF}'}' | sed -e 's/\/$//i' | tr '\n' ' '`
        else
                MPS=`${GREP} -v '^#' ${FSTAB} | ${GREP} -v ${EXCLUDE} | awk '{if ('${NOAUTOCOND}'&&($'${FSF}'=="ext2" || $'${FSF}'=="ext3" || $'${FSF}'=="xfs" || $'${FSF}'=="auto" || $'${FSF}'=="ext4" || $'${FSF}'=="nfs" || $'${FSF}'=="nfs4" || $'${FSF}'=="davfs" || $'${FSF}'=="cifs" || $'${FSF}'=="fuse" || $'${FSF}'=="glusterfs" || $'${FSF}'=="ocfs2" || $'${FSF}'=="lustre" || $'${FSF}'=="ufs" || $'${FSF}'=="zfs" || $'${FSF}'=="ceph" || $'${FSF}'=="btrfs" || $'${FSF}'=="yas3fs"))print $'${MF}'}' | sed -e 's/\/$//i' | tr '\n' ' '`
        fi
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
        CURRENT_STATE=$STATE_CRITICAL
fi

if [ "${MTAB}" == "none" ]; then
        MTAB=$(make_mtab)
fi

if [ ! -e "${MTAB}" ]; then
        log "CRIT: ${MTAB} doesn't exist!"
        echo "CRIT: ${MTAB} doesn't exist!"
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
                if [ -z "$( "${GREP}" -v '^#' "${FSTAB}" | awk '$'${MF}' == "'${MP}'" {print $'${MF}'}' )" ]; then
                        log "CRIT: ${MP} doesn't exist in /etc/fstab"
                        ERR_MESG[${#ERR_MESG[*]}]="${MP} doesn't exist in fstab ${FSTAB}"
                        CURRENT_STATE=$STATE_CRITICAL
                fi
        fi

        ## check kernel mounts
        if [ -z "$( awk '$'${MF}' == "'${MP}'" {print $'${MF}'}' "${MTAB}" )" ]; then
        ## if a softlink is not an adequate replacement
                if [ -z "$LINKOK" -o ! -L ${MP} ]; then
                        log "CRIT: ${MP} is not mounted"
                        ERR_MESG[${#ERR_MESG[*]}]="${MP} is not mounted"
                        CURRENT_STATE=$STATE_CRITICAL
                fi
        fi

        ## check if it stales
        df -k ${DFARGS} ${MP} &>/dev/null &
        DFPID=$!
        disown
        measure_exectime $DFPID

        if [ "$(bc <<< "$end_at > $stale_at")" == "1" ]; then
                log "CRIT: ${MP} did not respond in $TIME_TILL_STALE sec. Seems to be stale."
                ERR_MESG[${#ERR_MESG[*]}]="${MP} did not respond in $TIME_TILL_STALE sec. Seems to be stale."
                CURRENT_STATE=${STATE_CRITICAL}
        elif [ "$(bc <<< "$end_at > $crit_at")" == "1" ]; then
                log "CRIT: ${MP} exceeded critical threshold ($CRIT_TIME sec.)"
                ERR_MESG[${#ERR_MESG[*]}]="${MP} exceeded critical threshold ($CRIT_TIME sec.)"
                CURRENT_STATE=${STATE_CRITICAL}
        elif [ "$(bc <<< "$end_at > $warn_at")" == "1" ]; then
                log "CRIT: ${MP} exceeded warning threshold ($WARN_TIME sec.)"
                ERR_MESG[${#ERR_MESG[*]}]="${MP} exceeded warning threshold ($WARN_TIME sec.)"
                if [ $CURRENT_STATE -lt $STATE_WARNING ]; then
                    CURRENT_STATE=${STATE_WARNING}
                fi
        fi
        if ps -p $DFPID > /dev/null ; then
                $(kill -s SIGTERM $DFPID &>/dev/null)
        else
        ## if it not stales, check if it is a directory
                ISRW=0
                if [ ! -d ${MP} ]; then
                        log "CRIT: ${MP} doesn't exist on filesystem"
                        ERR_MESG[${#ERR_MESG[*]}]="${MP} doesn't exist on filesystem"
                        CURRENT_STATE=$STATE_CRITICAL
                ## if wanted, check if it is writable
                elif [ ${WRITETEST} -eq 1 ]; then
                        ISRW=1
                ## in auto mode first check if it's readonly
                elif [ ${WRITETEST} -eq 1 ] && [ ${AUTO} -eq 1 ]; then
                        ISRW=1
                        for OPT in $(${GREP} -w ${MP} ${FSTAB} |awk '{print $4}'| sed -e 's/,/ /g'); do
                                if [ "$OPT" == 'ro' ]; then
                                        ISRW=0
                                        log "CRIT: ${TOUCHFILE} is not mounted as writable."
                                        ERR_MESG[${#ERR_MESG[*]}]="Could not write in ${MP} filesystem was mounted RO."
                                        CURRENT_STATE=$STATE_CRITICAL
                                fi
                        done
                fi
                if [ ${ISRW} -eq 1 ]; then
                        TOUCHFILE=${MP}/.mount_test_from_$(hostname)_$(date +%Y-%m-%d--%H-%M-%S).$RANDOM.$$
                        touch ${TOUCHFILE} &>/dev/null &
                        TOUCHPID=$!
                        measure_exectime ${TOUCHPID} "(WRITE)"
                        if ps -p $TOUCHPID > /dev/null ; then
                                $(kill -s SIGTERM $TOUCHPID &>/dev/null)
                                log "CRIT: ${TOUCHFILE} is not writable."
                                ERR_MESG[${#ERR_MESG[*]}]="Could not write in ${MP} in $TIME_TILL_STALE sec. Seems to be stale."
                                CURRENT_STATE=$STATE_CRITICAL
                        else
                                if [ ! -f ${TOUCHFILE} ]; then
                                        log "CRIT: ${TOUCHFILE} is not writable."
                                        ERR_MESG[${#ERR_MESG[*]}]="Could not write in ${MP}."
                                        CURRENT_STATE=$STATE_CRITICAL
                                else
                                        rm ${TOUCHFILE} &>/dev/null
                                fi
                        fi
                fi
        fi

done

# Remove temporary files
if [[ "${MTAB}" =~ "/tmp" ]]; then
       rm -f ${MTAB}
fi
if [[ "${FSTAB}" =~ "/tmp" ]]; then
       rm -f ${FSTAB}
fi

# Write result (state and output)
declare -a STATESTR=("OK" "WARNING" "CRITICAL" "UNKNOWN")
echo -n "${STATESTR[$CURRENT_STATE]}: "


if [ ${#ERR_MESG[*]} -ne 0 ]; then
        for element in "${ERR_MESG[@]}"; do
                echo -n ${element}" ; "
        done
else
    echo -n "all mounts were found (${MPS})"
fi

echo "|${PERFDATA}"
exit $CURRENT_STATE
#!/usr/bin/env bash

# --------------------------------------------------------------------
# **** BEGIN LICENSE BLOCK *****

