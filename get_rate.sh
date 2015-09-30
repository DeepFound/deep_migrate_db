#!/bin/bash
usage()
{
	un='\033[4m'
	end='\033[00m'
	bold='\033[1m'
    echo -e "${bold}USAGE:${end} $0 [options] [DB.Table];"
    echo -e "${bold}OPTIONS:${end}"
    echo -e " ${bold}-u${end} ${un}USER${end}, ${bold}--mysql_user${end}=${un}USER${end}"
    echo -e "            source mysql username to be used. current user is used if not specified."
    echo -e " ${bold}-p${end}, --mysql_pass=${un}PASSWORD${end}"
    echo -e "            source mysql password to be used."  
    echo -e " ${bold}-h${end}, --host=${un}HOST${end}"
    echo -e "            destination mysql host."     
    echo -e " ${bold}--socket${end}=${un}SOCKET_FILE${end}"
    echo -e "            socket file to be used."   
    echo -e " ${bold}--port${end}=${un}PORT${end}"
    echo -e "            source port to be used." 
    exit 0;
}

# Absolute path to this script. /home/user/bin/foo.sh
SCRIPT=$(readlink -f $0)
# Absolute path this script is in. /home/user/bin
SCRIPTPATH=`dirname $SCRIPT`

TEMP=`getopt -o u:p:h: --long mysql_user:,mysql_pass:,host:,socket:,port:,help -n 'get_rate' -- "$@"`
if [ $? != 0 ] ; then usage >&2 ; exit 1 ; fi
eval set -- "$TEMP"

MYSQL_USER=`whoami`
MYSQL_PASS=
HOST=
SOCKET_FILE=
PORT=

while true; do
  case "$1" in
    -u | --mysql_user ) MYSQL_USER="$2"; shift 2 ;;
    -p | --mysql_pass ) MYSQL_PASS="$2"; shift 2 ;;
    -h | --host ) HOST="$2"; shift 2 ;;
	--socket ) SOCKET_FILE="--socket=$2"; shift 2 ;;
	--port ) PORT="--port=$2"; shift 2 ;;
	--help ) usage; shift 1 ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

if [[ -z "$1" ]] ; then
	echo "you must specify a DB.TABLE to get the insert rate of."
	usage
fi

echo "MYSQL_USER:$MYSQL_USER"
echo "MYSQL_PASS:$MYSQL_PASS"
echo "HOST:$HOST"
echo "SOCKET_FILE:$SOCKET_FILE"
echo "PORT:$PORT"

initialcount=$(mysql -u$MYSQL_USER -p$MYSQL_PASS -h"$HOST" -BNe "SELECT count(*) FROM $1;")
START_TIME=$SECONDS
sample_rate=30
no_rate=0
rm "rate-$1.log"

while true
do
	begin_count=$(mysql -u$MYSQL_USER -p$MYSQL_PASS -h"$HOST" -BNe "SELECT count(*) FROM $1;")
	sleep $sample_rate 
	end_count=$(mysql -u$MYSQL_USER -p$MYSQL_PASS -h"$HOST" -BNe "SELECT count(*) FROM $1;")
	END_TIME=$SECONDS
	TOTAL_TIME=$(( $END_TIME - $START_TIME ))
	overall_diff=$(( $end_count - $initialcount ))
	difference=$(( $end_count - $begin_count ))
	rows_per_sec=$(( $difference / $sample_rate ))
	overall_rate=$(( $overall_diff / $TOTAL_TIME ))
	thedate=`date`
	#echo "$thedate - we have $end_count rows so far. the current rate:$rows_per_sec rows/sec. the overall rate:$overall_rate rows/sec" | tee -a rate-$1.log
	echo "$thedate, $rows_per_sec, $overall_rate, $end_count" >> $SCRIPTPATH/rate-$1.csv
	if [ $difference -eq 0 ]; then
		((no_rate++))
		if [ $no_rate -gt 5 ]; then
			break;
		fi
	else
		no_rate=0
	fi
done

