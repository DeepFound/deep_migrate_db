#!/bin/bash

usage()
{

	un='\033[4m'
	end='\033[00m'
	bold='\033[1m'

    echo -e "${bold}USAGE:${end} $0 [options] [action (DUMP|LOAD|BOTH)] [database(s) (grep regex)] [table];"
    echo -e "${bold}OPTIONS:${end}"
    echo -e " ${bold}-u${end} ${un}USER${end}, ${bold}--mysql_user${end}=${un}USER${end}"
    echo -e "            source mysql username to be used. current user is used if not specified."
    echo -e " ${bold}-p${end}, --mysql_pass=${un}PASSWORD${end}"
    echo -e "            source mysql password to be used."  
    echo -e " ${bold}--socket${end}=${un}SOCKET_FILE${end}"
    echo -e "            source socket file to be used."   
    echo -e " ${bold}--port${end}=${un}PORT${end}"
    echo -e "            source port to be used." 
    echo -e " ${bold}--dest_host${end}=${un}HOST${end}"
    echo -e "            destination mysql host. Used for BOTH action only."    
    echo -e " ${bold}--dest_mysql_user${end}=${un}USER${end}"
    echo -e "            destination mysql user. Used for BOTH action only. current user is used if not specified."
    echo -e " ${bold}--dest_mysql_pass${end}=${un}PASSWORD${end}"
    echo -e "            destination mysql password. Used for BOTH action only." 
    echo -e " ${bold}--dest_port${end}=${un}DEST_PORT${end}"
    echo -e "            destination source port to be used." 
    echo -e " ${bold}--max_threads${end}=${un}NUM_THREADS${end}"
    echo -e "            max parrallel processes used. default is half your processors (best)"
    echo -e " ${bold}--chunk_size${end}=${un}SIZE${end}"
    echo -e "            number of rows used to split up large tables. 400000 is the default."
    echo -e " ${bold}--base_dir${end}=${un}DIR${end}"
    echo -e "            base directory to store DUMPS. default is pwd. a directory is created with the current date and time in this dir to store the data"
    echo -e " ${bold}--load_dir${end}=${un}DIR${end}"
    echo -e "            directory to LOAD a dump from. The directory should contain a directory per schema in it."
    echo -e " ${bold}--format${end}=${un}FORMAT${end}"
    echo -e "            format of the data to be loaded or dumped. either SQL(default) or INFILE."    
    echo -e " ${bold}--validate${end}"
    echo -e "            validate the number of rows on the source and destination. for BOTH option only."  
    echo -e " ${bold}--crc${end}"
    echo -e "            validate tables match on source and destination using CHECKSUM TABLE. for BOTH option only."
    exit 0;
}

# Absolute path to this script. /home/user/bin/foo.sh
SCRIPT=$(readlink -f $0)
# Absolute path this script is in. /home/user/bin
SCRIPTPATH=`dirname $SCRIPT`

TEMP=`getopt -o u:p:h: --long mysql_user:,mysql_pass:,dest_host:,socket:,port:,dest_port:,dest_mysql_user:,dest_mysql_pass:,max_threads:,chunk_size:,base_dir:,load_dir:,format:,validate,crc,help -n 'migrate_db' -- "$@"`
if [ $? != 0 ] ; then usage >&2 ; exit 1 ; fi
eval set -- "$TEMP"

MYSQL_USER=`whoami`
MYSQL_PASS=
dest_ip=
REMOTE_MYSQL_USER=`whoami`
REMOTE_MYSQL_PASS=
MAX_THREADS=$(( $(cat /proc/cpuinfo | grep -c processor) / 2 ))
CHUNK_SIZE=400000
BASE_DIR=`pwd`
LOAD_DIR=
SOCKET_FILE=
PORT=
DEST_PORT=
FORMAT=SQL
VALIDATE=0
CRC=0

START_TIME=$SECONDS

while true; do
  case "$1" in
    -u | --mysql_user ) MYSQL_USER="$2"; shift 2 ;;
    -p | --mysql_pass ) MYSQL_PASS="$2"; shift 2 ;;
    -h | --dest_host ) dest_ip="$2"; shift 2 ;;
	--socket ) SOCKET_FILE="--socket=$2"; shift 2 ;;
	--port ) PORT="--port=$2"; shift 2 ;;
    --dest_mysql_user ) REMOTE_MYSQL_USER="$2"; shift 2 ;;
    --dest_mysql_pass ) REMOTE_MYSQL_PASS="$2"; shift 2 ;;
	--dest_port ) DEST_PORT="--port=$2"; shift 2 ;;
    --max_threads ) MAX_THREADS="$2"; shift 2 ;;
    --chunk_size ) CHUNK_SIZE="$2"; shift 2 ;;
    --base_dir ) BASE_DIR="$2"; shift 2 ;;
    --load_dir ) LOAD_DIR="$2"; shift 2 ;;
	--format ) FORMAT="$2"; shift 2 ;;
	--validate ) VALIDATE=1; shift 1 ;;
	--crc ) CRC=1; shift 1 ;;
	--help ) usage; shift 1 ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

ACTION=$1  # DUMP, LOAD, BOTH
if [ "$ACTION" != "DUMP" ] && [ "$ACTION" != "LOAD" ] && [ "$ACTION" != "BOTH" ] ; then
	echo "You must specify either LOAD, DUMP or BOTH for an action"
	usage
	exit;
fi

#if LOAD check that the load_dir is set and valid.
if [ "$ACTION" == "LOAD" ] ; then
	if [ -z "$LOAD_DIR" ] ; then
		echo "When LOADing a database, you must specify a valid directory for load_dir"
		echo ""
		usage
		exit;
	fi
	if [ ! -d "$LOAD_DIR" ] ; then
		echo "The directory for load_dir ($LOAD_DIR) does not exist."
		echo ""
		usage
		exit;
	fi
fi

if [ -n "$MYSQL_PASS" ] ; then
	MYSQL_PASS="-p$MYSQL_PASS"
fi
if [ -n "$REMOTE_MYSQL_PASS" ] ; then
	REMOTE_MYSQL_PASS="-p$REMOTE_MYSQL_PASS"
fi

echo "Checking MySQL connection..."
mysql -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT -e exit 2>/dev/null
if [ $? -ne 0 ]; then
	echo "Failed to connect to MySQL (localhost) using user:$MYSQL_USER pass:$MYSQL_PASS "
	exit;
fi

if [ "$ACTION" == "BOTH" ] ; then
	echo "Checking remote MySQL connection..."
	mysql -h"$dest_ip" -u"$REMOTE_MYSQL_USER" $REMOTE_MYSQL_PASS $DEST_PORT -e exit 2>/dev/null
	if [ $? -ne 0 ]; then
		echo "Failed to connect to MySQL ($dest_ip) using user:$REMOTE_MYSQL_USER pass:$REMOTE_MYSQL_PASS "
		exit;
	fi
fi

if [ -n "$2" ] ; then
	GREP_REGEX=$2
else
	GREP_REGEX="/*"
fi

if [ -n "$3" ] ; then
	TABLE_GREP_REGEX=$3
else
	TABLE_GREP_REGEX="/*"
fi

echo MYSQL_USER=$MYSQL_USER
echo MYSQL_PASS=$MYSQL_PASS
echo dest_ip=$dest_ip
echo SOCKET_FILE=$SOCKET_FILE
echo PORT=$PORT
echo DEST_PORT=$DEST_PORT
echo REMOTE_MYSQL_USER=$REMOTE_MYSQL_USER
echo REMOTE_MYSQL_PASS=$REMOTE_MYSQL_PASS
echo MAX_THREADS=$MAX_THREADS
echo CHUNK_SIZE=$CHUNK_SIZE
echo ACTION=$ACTION
echo BASE_DIR=$BASE_DIR
echo LOAD_DIR=$LOAD_DIR
echo GREP_REGEX=$GREP_REGEX
echo FORMAT=$FORMAT
echo VALIDATE=$VALIDATE
echo CRC=$CRC
echo TABLE_GREP_REGEX=$TABLE_GREP_REGEX

: > $BASE_DIR/migrate_db.errors.log

if [ "$ACTION" == "DUMP" ] || [ "$ACTION" == "BOTH" ] ; then

	dir=$(date "+%Y-%m-%d_%Hh%Mm%Ss")
	mkdir -m 777 -p $BASE_DIR/$dir

	list_of_dbs=$(mysql -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT -BNe "show databases" | grep "$GREP_REGEX" | grep -v "information_schema")

	#dump the schema skeleton of all databases (no data)
	for db in $list_of_dbs ; do 
		mkdir -m 777 $BASE_DIR/$dir/$db
		mysqldump -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT --no-data --skip-add-drop-table --skip-comments $db > $BASE_DIR/$dir/$db/the-schema	
	done
	#convert engine to deep within the schema dump
	find $BASE_DIR/$dir/ -name 'the-schema'| xargs perl -pi -e 's/ENGINE=InnoDB/ENGINE=DeepDB/g'

	if [ "$ACTION" == "BOTH" ] && [ "$VALIDATE" -eq 0 ] ; then
		#create all the db's on the new db (over network)
		for db in $list_of_dbs ; do 
			mysql -u"$REMOTE_MYSQL_USER" $REMOTE_MYSQL_PASS -h"$dest_ip" $DEST_PORT -e "CREATE DATABASE $db;"
			mysql -u"$REMOTE_MYSQL_USER" $REMOTE_MYSQL_PASS -h"$dest_ip" $DEST_PORT $db < $BASE_DIR/$dir/$db/the-schema
		done
	fi

	if [ "$ACTION" == "DUMP" ] ; then
		echotext="dumping"
	elif [ "$VALIDATE" -eq 1 ] ; then
		echotext="validating"
	else
		echotext="migrating"
	fi
	# dump and load of each db's tables in parrallel
	for db in $list_of_dbs ; do 
	
		if [ "$TABLE_GREP_REGEX" == "/*" ] ; then
			list_of_tables=$(mysql -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT -BNe "show tables" $db | grep "$TABLE_GREP_REGEX")
		else
			list_of_tables=$(mysql -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT -BNe "show tables" $db | grep -x "$TABLE_GREP_REGEX")
		fi

		for table in $list_of_tables ; do
			echo "$echotext database $db table $table ..."
			if [ "$ACTION" == "BOTH" ] && [ "$VALIDATE" -eq 0 ] ; then
				#collect insertion rate stats
				$SCRIPTPATH/get_rate.sh -u$REMOTE_MYSQL_USER $REMOTE_MYSQL_PASS -h$dest_ip $db.$table&
			fi

			unique_key=$(mysql -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT -BNe "SHOW KEYS IN $table FROM $db WHERE Non_unique=0 AND Key_name='PRIMARY';" | awk '{ print $5 '})
			num_columns_in_key=$(mysql -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT -BNe "SHOW KEYS IN $table FROM $db WHERE Non_unique=0 AND Key_name='PRIMARY' ;" | wc -l)
			unique_key_data_type=$(mysql -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT -BNe "SELECT DATA_TYPE FROM information_schema.COLUMNS WHERE TABLE_SCHEMA ='$db' AND TABLE_NAME = '$table' AND COLUMN_NAME = '$unique_key';")
			
			#check how many rows are in the table if its larger than CHUNK_SIZE, then lets split it in chunks 
			if [ -n "$unique_key" ] && [ "$num_columns_in_key" -eq 1 ] && [[ "$unique_key_data_type" == *int* ]]; then
				num_rows=$(mysql -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT -BNe "SELECT table_rows FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA ='$db' AND table_name='$table';")
				num_rows_fifty=$((num_rows / 2))
				num_rows=$((num_rows + num_rows_fifty))				
			else
				num_rows=$(mysql -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT -BNe "SELECT count(*) FROM $db.$table;")
			fi

			if [ "$num_rows" -gt $CHUNK_SIZE ] ; then

				#echo "unique_key: $unique_key"
				#echo "num_columns_in_key: $num_columns_in_key"
				#echo "unique_key_data_type: $unique_key_data_type"

				if [ -n "$unique_key" ] && [ "$num_columns_in_key" -eq 1 ] && [[ "$unique_key_data_type" == *int* ]]; then
					max_unique_num=$(mysql -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT -BNe "SELECT MAX($unique_key) FROM $db.$table;")
					num_chunks=$(( $max_unique_num / $CHUNK_SIZE ))
					((num_chunks++))
					echo "Splitting up $db.$table into $num_chunks chunks. using index on column $unique_key"
				else
					num_chunks=$(( $num_rows / $CHUNK_SIZE ))
					((num_chunks++))
					echo "Splitting up $db.$table into $num_chunks chunks. using limit"
				fi
				
				for (( i=0, j=1 ; i <= $num_chunks ; i++, j++ )) ; do
					limit_start=$(( $i * $CHUNK_SIZE))
					limit_end=$(( $j * $CHUNK_SIZE))

					# sleep a bit if we are at the MAX_THREADS
					while [ "$(jobs -pr | wc -l)" -gt "$MAX_THREADS" ] ; do sleep 2; done

					if [ -n "$unique_key" ] && [ "$num_columns_in_key" -eq 1 ] && [[ "$unique_key_data_type" == *int* ]]; then
						
						if [ "$ACTION" == "BOTH" ] ; then

							if [ "$VALIDATE" -eq 1 ] ; then
								#lets get the count on the source and dest
								num_rows_source=$(mysql -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT $db -BNe "SELECT COUNT($unique_key) FROM $db.$table WHERE $unique_key >= $limit_start AND $unique_key < $limit_end;")
								num_rows_dest=$(mysql -h"$dest_ip" -u$REMOTE_MYSQL_USER $REMOTE_MYSQL_PASS $DEST_PORT $db -BNe "SELECT COUNT($unique_key) FROM $db.$table WHERE $unique_key >= $limit_start AND $unique_key < $limit_end;")
								#echo "num_rows_source:$num_rows_source    num_rows_dest:$num_rows_dest "
							fi

							#mysqldump -u$MYSQL_USER $MYSQL_PASS $SOCKET_FILE $PORT --max_allowed_packet=1000000000 --no-create-db --no-create-info --compact --skip-add-locks --single-transaction --quick --where "$unique_key >= $limit_start AND $unique_key < $limit_end" $db $table | mysql --max_allowed_packet=1000000000 -h"$dest_ip" -u$REMOTE_MYSQL_USER $REMOTE_MYSQL_PASS $DEST_PORT $db 2>> $BASE_DIR/migrate_db.errors.log &
							if [ "$VALIDATE" -eq 1 ] && [ "$num_rows_source" -eq "$num_rows_dest" ] ; then
								echo "source and destination both match having $num_rows_source rows WHERE $unique_key >= $limit_start AND $unique_key < $limit_end"
							elif [ "$VALIDATE" -eq 1 ] && [ "$num_rows_source" -ne "$num_rows_dest" ] ; then
								echo "source and destination DO NOT MATCH! Source:$num_rows_source rows.  Dest:$num_rows_dest rows  WHERE $unique_key >= $limit_start AND $unique_key < $limit_end"
							elif [ "$VALIDATE" -eq 0 ]; then
								echo "$echotext chunk $j of $num_chunks for $db.$table where $unique_key >= $limit_start AND $unique_key < $limit_end"
								( mysqldump -u$MYSQL_USER $MYSQL_PASS $SOCKET_FILE $PORT --no-create-db --no-create-info --compact --skip-add-locks --single-transaction --quick --where "$unique_key >= $limit_start AND $unique_key < $limit_end" $db $table > $BASE_DIR/$dir/$db/$table-$j.sql ; mysql -h"$dest_ip" -u$REMOTE_MYSQL_USER $REMOTE_MYSQL_PASS $DEST_PORT $db < $BASE_DIR/$dir/$db/$table-$j.sql ; rm $BASE_DIR/$dir/$db/$table-$j.sql ) &
							fi

						elif [ "$ACTION" == "DUMP" ]; then
							echo "$echotext chunk $j of $num_chunks for $db.$table where $unique_key >= $limit_start AND $unique_key < $limit_end"
							if [ "$FORMAT" == "SQL" ] ; then
								mysqldump -u$MYSQL_USER $MYSQL_PASS $SOCKET_FILE $PORT --no-create-db --no-create-info --compact --skip-add-locks --single-transaction --quick --where "$unique_key >= $limit_start AND $unique_key < $limit_end" $db $table > $BASE_DIR/$dir/$db/$table-$j.sql 2>> $BASE_DIR/migrate_db.errors.log &
							elif [ "$FORMAT" == "INFILE" ] ; then
								mysql -u$MYSQL_USER $MYSQL_PASS $SOCKET_FILE $PORT -e"SELECT * INTO OUTFILE '$BASE_DIR/$dir/$db/$table.$j' FROM $db.$table WHERE $unique_key >= $limit_start AND $unique_key < $limit_end" 2>> $BASE_DIR/migrate_db.errors.log &
							else
								echo "Unknown format $FORMAT. exiting..."
								exit;
							fi
						fi
					else

						if [ "$VALIDATE" -eq 1 ] ; then
							num_rows_source=$(mysql -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT $db -BNe "SELECT COUNT(*) FROM $db.$table;")
							num_rows_dest=$(mysql -h"$dest_ip" -u$REMOTE_MYSQL_USER $REMOTE_MYSQL_PASS $DEST_PORT $db -BNe "SELECT COUNT(*) FROM $db.$table;")
							if [ "$num_rows_source" -eq "$num_rows_dest" ] ; then
								echo "source and destination both match having $num_rows_source rows,"
							elif [ "$num_rows_source" -ne "$num_rows_dest" ]; then
								echo "source and destination DO NOT MATCH! Source:$num_rows_source rows.  Dest:$num_rows_dest rows."
							fi
							break;
						fi

						echo "$echotext chunk $j of $num_chunks for $db.$table where LIMIT $limit_start, $CHUNK_SIZE"
						if [ "$ACTION" == "BOTH" ] && [ "$VALIDATE" -eq 0 ] ; then
							#mysqldump -u$MYSQL_USER $MYSQL_PASS $SOCKET_FILE $PORT --max_allowed_packet=1000000000 --no-create-db --no-create-info --compact --skip-add-locks --single-transaction --quick --where "1 LIMIT $limit_start, $CHUNK_SIZE" $db $table | mysql --max_allowed_packet=1000000000 -h"$dest_ip" -u$REMOTE_MYSQL_USER $REMOTE_MYSQL_PASS $DEST_PORT $db 2>> $BASE_DIR/migrate_db.errors.log &
							( mysqldump -u$MYSQL_USER $MYSQL_PASS $SOCKET_FILE $PORT --no-create-db --no-create-info --compact --skip-add-locks --single-transaction --quick --where "1 LIMIT $limit_start, $CHUNK_SIZE" $db $table > $BASE_DIR/$dir/$db/$table-$j.sql ; mysql -h"$dest_ip" -u$REMOTE_MYSQL_USER $REMOTE_MYSQL_PASS $DEST_PORT $db < $BASE_DIR/$dir/$db/$table-$j.sql ; rm $BASE_DIR/$dir/$db/$table-$j.sql ) &
						elif [ "$ACTION" == "DUMP" ]; then
							if [ "$FORMAT" == "SQL" ] ; then
								mysqldump -u$MYSQL_USER $MYSQL_PASS $SOCKET_FILE $PORT --no-create-db --no-create-info --compact --skip-add-locks --single-transaction --quick --where "1 LIMIT $limit_start, $CHUNK_SIZE" $db $table > $BASE_DIR/$dir/$db/$table-$j.sql 2>> $BASE_DIR/migrate_db.errors.log &
							elif [ "$FORMAT" == "INFILE" ] ; then
								mysql -u$MYSQL_USER $MYSQL_PASS $SOCKET_FILE $PORT -e"SELECT * INTO OUTFILE '$BASE_DIR/$dir/$db/$table.$j' FROM $db.$table LIMIT $limit_start, $CHUNK_SIZE" 2>> $BASE_DIR/migrate_db.errors.log &
							else
								echo "Unknown format $FORMAT. exiting..."
								exit;
							fi
						fi
					fi

				done

			else
				# sleep a bit if we are at the MAX_THREADS
				while [ "$(jobs -pr | wc -l)" -gt "$MAX_THREADS" ] ; do sleep 2; done

				if [ "$ACTION" == "BOTH" ] && [ "$VALIDATE" -eq 0 ] ; then
					mysqldump -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT --no-create-db --order-by-primary --no-create-info --compact --skip-add-locks --single-transaction --quick $db $table | mysql -h"$dest_ip" -u$REMOTE_MYSQL_USER $REMOTE_MYSQL_PASS $DEST_PORT $db 2>> $BASE_DIR/migrate_db.errors.log &
				elif [ "$ACTION" == "BOTH" ] && [ "$VALIDATE" -eq 1 ] ; then
					num_rows_source=$(mysql -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT $db -BNe "SELECT COUNT(*) FROM $db.$table;")
					num_rows_dest=$(mysql -h"$dest_ip" -u$REMOTE_MYSQL_USER $REMOTE_MYSQL_PASS $DEST_PORT $db -BNe "SELECT COUNT(*) FROM $db.$table;")
					if [ "$num_rows_source" -eq "$num_rows_dest" ] ; then
						echo "source and destination both match having $num_rows_source rows,"
					elif [ "$num_rows_source" -ne "$num_rows_dest" ]; then
						echo "source and destination DO NOT MATCH! Source:$num_rows_source rows.  Dest:$num_rows_dest rows."
					fi					
				elif [ "$ACTION" == "DUMP" ]; then
					if [ "$FORMAT" == "SQL" ] ; then
						mysqldump -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT --no-create-db --order-by-primary --no-create-info --compact --skip-add-locks --single-transaction --quick $db $table > $BASE_DIR/$dir/$db/$table.sql 2>> $BASE_DIR/migrate_db.errors.log &
					elif [ "$FORMAT" == "INFILE" ] ; then
						mysql -u$MYSQL_USER $MYSQL_PASS $SOCKET_FILE $PORT -e"SELECT * INTO OUTFILE '$BASE_DIR/$dir/$db/$table.1' FROM $db.$table" 2>> $BASE_DIR/migrate_db.errors.log &
					else
						echo "Unknown format $FORMAT. exiting..."
						exit;
					fi						
				fi
			fi


			#if BOTH and CRC then compute it for each table.
			if [ "$ACTION" == "BOTH" ] && [ "$CRC" -eq 1 ] ; then
				crc_source=$(mysql -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT $db -BNe "CHECKSUM TABLE $db.$table;" | awk '{ print $2 '})
				crc_dest=$(mysql -h"$dest_ip" -u$REMOTE_MYSQL_USER $REMOTE_MYSQL_PASS $DEST_PORT $db -BNe "CHECKSUM TABLE $db.$table;" | awk '{ print $2 '})
				if [ "$crc_source" -eq "$crc_dest" ] ; then
					echo "source and destination CHECKSUMs match."
				elif [ "$num_rows_source" -ne "$num_rows_dest" ]; then
					echo "source and destination CHECKSUMs DO NOT MATCH! Source:$crc_source rows.  Dest:$crc_dest "
				fi		
			fi


		done

	done

elif [ "$ACTION" == "LOAD" ] ; then
	cd $LOAD_DIR
	list_of_dbs=$(ls -d -1 *)
	
	for db in $list_of_dbs ; do
		#mysql -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT -e "CREATE DATABASE $db;"
		mysql -h"$dest_ip" -u"$REMOTE_MYSQL_USER" $REMOTE_MYSQL_PASS $DEST_PORT -e "CREATE DATABASE $db;"
		echo "loading $LOAD_DIR/$db/the-schema"
		#mysql -u"$MYSQL_USER" $MYSQL_PASS $SOCKET_FILE $PORT $db < $LOAD_DIR/$db/the-schema
		mysql -h"$dest_ip" -u"$REMOTE_MYSQL_USER" $REMOTE_MYSQL_PASS $DEST_PORT $db < $LOAD_DIR/$db/the-schema
		if [ "$FORMAT" == "SQL" ] ; then
			#foreach file in the dir
			for sql_file in $LOAD_DIR/$db/*.sql ; do
				# sleep a bit if we are at the MAX_THREADS
				while [ "$(jobs -pr | wc -l)" -gt "$MAX_THREADS" ] ; do sleep 2; done
				echo "loading file $sql_file"
				#mysql -u$MYSQL_USER $MYSQL_PASS $SOCKET_FILE $PORT $db < $sql_file & 
				mysql -h"$dest_ip" -u$REMOTE_MYSQL_USER $REMOTE_MYSQL_PASS $DEST_PORT $db < $sql_file & 
			done
		elif [ "$FORMAT" == "INFILE" ] ; then
			#foreach file in the dir
			for infile in $LOAD_DIR/$db/*.* ; do
				# sleep a bit if we are at the MAX_THREADS
				while [ "$(jobs -pr | wc -l)" -gt "$MAX_THREADS" ] ; do sleep 2; done
				echo "loading file $infile"
				# get the table name from the file name.  ex TABLE.jdjnsdhs
				filename=$(basename "$infile")
				TABLE="${filename%.*}"
				mysql -h"$dest_ip" -u$REMOTE_MYSQL_USER $REMOTE_MYSQL_PASS $DEST_PORT -e "load data infile '$infile' into table $TABLE" $db  & 
			done			
		else
			echo "Unknown format $FORMAT. exiting..."
			exit;
		fi
	done


fi

wait
TOTAL_TIME=$(($SECONDS - $START_TIME))
echo "Done. Everything Took $TOTAL_TIME seconds."
#if [ "$(wc -l $BASE_DIR/migrate_db.errors.log)" -gt "0" ] ; then
#	echo "The following errors occured:"
#	cat $BASE_DIR/migrate_db.errors.log
#fi
