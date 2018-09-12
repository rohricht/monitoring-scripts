#!/bin/sh 
# ======================================================================================
# Author:       Nilton Rohricht Junior
# Email:        rohricht@gmail.com
# Date:         2018-09-04
# Usage:        check_dir_size.sh -d /path/to/directory [parameters] 
# Description:  This script get the size of a directory and test it against size and 
#               percentual usage of disk thresholds. If no thresholds, then simply 
#               return an OK and directory size. The thresholds are compared considering 
#               the unit provided, if none default is KiB.
#
#               Pay attention if this commands need sudo in your server. 
# ======================================================================================


# --------------------------------------------------------------------- Global Variables
# 0 - OK | 1 - WARN | 2 - CRIT | 3 - UNK
STATUS_OK=0
STATUS_WARNING=1
STATUS_CRITICAL=2
STATUS_UNKNOWN=3

# ---------------------------------------------------------------------------- Functions

printUsage() {
cat << EOF

Test a directory size against thresholds for size or percentual usage.

Usage:
   check_dir_size.sh -d /opt/documents/directory -w 4 -c 5 -u g
     Check if the size of /opt/documents/directory is greater than 4GiB and 5GiB.

   check_dir_size.sh -d /opt/documents/directory -W 4 -C 5 -u g
     Check if the size of /opt/documents/directory is greater than 4% and 5% of the partition.

Required parameters:
  -d Directory Path (ex.: /opt/documents/)

Optional parameters:
  -w Warning Threshold (must respect unit flag)
  -c Critical Threshold (must respect unit flag)
  -W Warning Threshold for Disk Usage Percentual
  -C Critical Threshold for Disk Usage Percentual
  -u Size Unit (KiB: k, MiB: m, GiB: g, Default: k)
  -h Get this help ;)

EOF
}

err(){
    echo "We have a problem: $1"
    exit 3
}

getDirectorySize() {
    local _size=$( du -s $1 | awk '{print ($1)}' )
    echo $_size
}

getPartition() {
    local _part=$( df -P "$1" | awk '/^\/dev/ {print $1}' )
    echo $_part
}

getPartitionSize() {
    local _size=$( fdisk -s $1 )
    echo $_size
}

getUsagePercentual() {
    local _percent=$( awk "BEGIN { p=100*$1/$2; printf \"%.1f\n\", p }" )
    echo $_percent
}

isGreater() {
    local _value=$( awk "BEGIN{ print ($1 >= $2) }" )
    echo $_value
}

# ----------------------------------------------------------------------- Verify Options
while getopts ":d:w:c:W:C:u:h" opt; do
    case "$opt" in
        d) 
	        if [ "$( echo $OPTARG | cut -c1)" != "-" ]; then
	            DIR_PATH=$OPTARG

	            if [ ! -d $DIR_PATH ]; then
	                echo "It's not a directory: $DIR_PATH"
	                exit 3
	            fi

	            DIR_SIZE=$( getDirectorySize $DIR_PATH )
	            PARTITION=$( getPartition $DIR_PATH )
	            PART_SIZE=$( getPartitionSize $PARTITION )
	            USAGE_PERC=$( getUsagePercentual $DIR_SIZE $PART_SIZE )
	        else
		        err "received $OPTARG as path"
	        fi
	    ;;
	
        w)
	        if [ "$( echo $OPTARG | cut -c1)" != "-" ]; then	
	            WARNING_THRESHOLD=$OPTARG
	        else
		        err "received $OPTARG as size warning"
	        fi
	    ;;
	
        c) 
	        if [ "$( echo $OPTARG | cut -c1)" != "-" ]; then
	            CRITICAL_THRESHOLD=$OPTARG
	        else
		        err "received $OPTARG as size critical"
	        fi
	    ;;

	    W)
	        if [ "$( echo $OPTARG | cut -c1)" != "-" ]; then
    	        WARNING_PERC_THRESHOLD=$OPTARG
	        else
		        err "received $OPTARG as percentual warning"
            fi
	    ;;

	    C)
	        if [ "$( echo $OPTARG | cut -c1)" != "-" ]; then
    	        CRITICAL_PERC_THRESHOLD=$OPTARG
	        else
		        err "received $OPTARG as percentual critical"
            fi
	    ;;

        u)
	        if [ "$( echo $OPTARG | cut -c1)" != "-" ]; then
	            SIZE_UNIT=$OPTARG
	        else 
	            err "received $OPTARG as size unit"
	        fi
	    ;;

	    h)
	        printUsage
	    ;;
	
        *) 
	        err "Invalid arguments -> $OPTARG"	
	    ;;
    esac
done

if [ $OPTIND -eq 1 ]; then
    err "No arguments was passed to me..."
fi


# ---------------------------------------------------------------------- Unit Convertion
case "$SIZE_UNIT" in
    G|g)
        UNIT="GB"
        DIR_SIZE_H=$( awk "BEGIN { b=$DIR_SIZE/1024/1024; printf \"%.2f\n\", b }" )
        PART_SIZE_H=$( awk "BEGIN { b=$PART_SIZE/1024/1024; printf \"%.2f\n\", b }" )
    ;;
	
    M|m)
	    UNIT="MB"
	    DIR_SIZE_H=$( awk "BEGIN { b=$DIR_SIZE/1024; printf \"%.2f\n\", b }" )
	    PART_SIZE_H=$( awk "BEGIN { b=$PART_SIZE/1024; printf \"%.2f\n\", b }" )
    ;;

    K|k|*) 
	    UNIT="KB"
	    DIR_SIZE_H="$DIR_SIZE"
	    PART_SIZE_H="$PART_SIZE"
    ;;
esac

# --------------------------------------------------------------- Verify Size Thresholds
if [ -z "$CRITICAL_THRESHOLD" ] || [ -z "$WARNING_THRESHOLD" ]; then
    STATUS="OK-NOTHRESHOLD"
    break
elif [ $( isGreater $DIR_SIZE_H $CRITICAL_THRESHOLD ) -eq 1 ]; then
    STATUS="CRITICAL"
    break
elif [ $( isGreater $DIR_SIZE_H $WARNING_THRESHOLD ) -eq 1 ]; then
    STATUS="WARNING"
    break
elif [ $( isGreater $DIR_SIZE_H 0 ) -eq 1 ]; then
    STATUS="OK"
    break
else
    STATUS="UNKNOWN"
fi

# --------------------------------------------------------- Verify Percentual Thresholds
if [ -n "$CRITICAL_PERC_THRESHOLD" ] || [ -n "$WARNING_PERC_THRESHOLD" ]; then
    if [ $( isGreater $USAGE_PERC $CRITICAL_PERC_THRESHOLD ) -eq 1 ]; then
        STATUS="CRITICAL%"
        break
    elif [ $( isGreater $USAGE_PERC $WARNING_PERC_THRESHOLD ) -eq 1 ]; then
        STATUS="WARNING%"
        break
    elif [ $( isGreater $USAGE_PERC 0 ) -eq 1 ]; then
        STATUS="OK%"
        break
    else
        STATUS="UNKNOWN%"
    fi
fi

# ---------------------------------------------------------------- Create Plugin Returns
case "$STATUS" in
    OK)
        RESULT="SIZE OK - Size: $DIR_PATH $DIR_SIZE_H $UNIT; $PARTITION $PART_SIZE_H $UNIT ($USAGE_PERC%)"
	    RETURN=$STATUS_OK
    ;;

    OK%)
        RESULT="USAGE OK - $USAGE_PERC% of $PARTITION; Size: $DIR_PATH $DIR_SIZE_H $UNIT; $PARTITION $PART_SIZE_H $UNIT"
        RETURN=$STATUS_OK
    ;;

    OK-NOTHRESHOLD)
	    RESULT="OK - size: $DIR_PATH $DIR_SIZE_H $UNIT; $PARTITION $PART_SIZE_H $UNIT ($USAGE_PERC%)"
	    RETURN=$STATUS_OK
    ;;

    WARNING)
	    RESULT="SIZE WARNING - size: $DIR_PATH $DIR_SIZE_H $UNIT; $PARTITION $PART_SIZE_H $UNIT ($USAGE_PERC%)"
	    RETURN=$STATUS_WARNING
    ;;

    WARNING%)
        RESULT="USAGE WARNING - $USAGE_PERC% of $PARTITION; Size: $DIR_PATH $DIR_SIZE_H $UNIT; $PARTITION $PART_SIZE_H $UNIT"
        RETURN=$STATUS_WARNING
    ;;

    CRITICAL)
	    RESULT="SIZE CRITICAL - size: $DIR_PATH $DIR_SIZE_H $UNIT; $PARTITION $PART_SIZE_H $UNIT ($USAGE_PERC%)"
	    RETURN=$STATUS_CRITICAL
    ;;

    CRITICAL%)
        RESULT="USAGE CRITICAL  - $USAGE_PERC% of $PARTITION; Size: $DIR_PATH $DIR_SIZE_H $UNIT; $PARTITION $PART_SIZE_H $UNIT"
        RETURN=$STATUS_CRITICAL
    ;;

    UNKNOWN)
	    RESULT="UNKNOWN - size: $DIR_PATH $DIR_SIZE_H $UNIT; $PARTITION $PART_SIZE_H $UNIT ($USAGE_PERC%)"
	    RETURN=$STATUS_UNKNOWN
    ;;

    *)        
		RESULT="ERROR - Something is not working as expected =( - size: $DIR_PATH $DIR_SIZE_H $UNIT; $PARTITION $PART_SIZE_H $UNIT ($USAGE_PERC%)"
		RETURN=$STATUS_UNKNOWN
    ;;
esac

PERF=" |directory_size=$DIR_SIZE_H$UNIT;$WARNING_THRESHOLD;$CRITICAL_THRESHOLD;0 directory_usage=$USAGE_PERC%;$WARNING_PERC_THRESHOLD;$CRITICAL_PERC_THRESHOLD;0"

# ---------------------------------------------------------------------- Plugin Resturns
# The 'RESULT' print the response in the monitoring app (IcingaWeb2)
# The 'RETURN' sets the status of the response (OK, WARN, CRIT, UNK)
echo $RESULT$PERF
exit $RETURN
