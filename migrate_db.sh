#!/bin/bash

usage()
{
	un='\033[4m'
	end='\033[00m'
	bold='\033[1m'
    echo -e "${bold}USAGE:${end} $0 [options] [action (DUMP|LOAD|MIGRATE)] [database(s) (grep regex)] [table];"
    echo -e "${bold}OPTIONS:${end}"
    echo -e " ${bold}--source_mysql_user${end}=${un}USER${end}"
    echo -e "            source mysql username to be used. current user is used if not specified."
    echo -e " ${bold}--source_mysql_pass=${un}PASSWORD${end}"
    echo -e "            source mysql password to be used."  
    echo -e " ${bold}--source_mysql_host${end}=${un}HOST${end}"
    echo -e "            destination mysql host. Used for MIGRATE action only." 
    echo -e " ${bold}--source_mysql_port${end}=${un}PORT${end}"
    echo -e "            source port to be used." 
    echo -e " ${bold}--source_mysql_socket${end}=${un}SOCKET_FILE${end}"
    echo -e "            source socket file to be used."
    echo -e " ${bold}--source_mysql_engine${end}=${un}ENGINE${end}"
    echo -e "            source mysql database engine. "
    echo -e " ${bold}--destination_mysql_user${end}=${un}USER${end}"
    echo -e "            destination mysql user. Used for MIGRATE action only. current user is used if not specified."
    echo -e " ${bold}--destination_mysql_pass${end}=${un}PASSWORD${end}"
    echo -e "            destination mysql password. Used for MIGRATE action only."
    echo -e " ${bold}--destination_mysql_host${end}=${un}HOST${end}"
    echo -e "            destination mysql host. Used for MIGRATE action only." 
    echo -e " ${bold}--destination_mysql_port${end}=${un}DEST_PORT${end}"
    echo -e "            destination source port to be used."
    echo -e " ${bold}--destination_mysql_socket${end}=${un}SOCKET_FILE${end}"
    echo -e "            source socket file to be used."
    echo -e " ${bold}--destination_mysql_engine${end}=${un}ENGINE${end}"
    echo -e "            destination mysql database engine. "
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
    echo -e "            validate the number of rows on the source and destination. for MIGRATE option only."  
    echo -e " ${bold}--crc${end}"
    echo -e "            validate tables match on source and destination using CHECKSUM TABLE. for MIGRATE option only."
    echo -e " "
    echo -e "notes:"
    echo -e "If no database is specified, we migrate all databases."
	echo -e "If no table is specified, we migrate all tables. (either 1 or all)"
	echo -e " "
    exit 0;
}

# Absolute path to this script. /home/user/bin/foo.sh
SCRIPT=$(readlink -f $0)
# Absolute path this script is in. /home/user/bin
SCRIPTPATH=`dirname $SCRIPT`

TEMP=`getopt -o u:p:h: --long source_mysql_user:,source_mysql_pass:,source_mysql_host:,source_mysql_port:,source_mysql_socket:,destination_mysql_user:,destination_mysql_pass:,destination_mysql_host:,destination_mysql_port:,max_threads:,chunk_size:,base_dir:,load_dir:,format:,source_mysql_engine:,destination_mysql_engine:,validate,crc,help -n 'migrate_db' -- "$@"`
if [ $? != 0 ] ; then usage >&2 ; exit 1 ; fi
eval set -- "$TEMP"

SOURCE_MYSQL_USER=
SOURCE_MYSQL_PASS=
SOURCE_MYSQL_HOST=
SOURCE_MYSQL_PORT=
SOURCE_MYSQL_SOCKET=
SOURCE_MYSQL_ENGINE=

DESTINATION_MYSQL_USER=
DESTINATION_MYSQL_PASS=
DESTINATION_MYSQL_HOST=
DESTINATION_MYSQL_PORT=
DESTINATION_MYSQL_SOCKET=
DESTINATION_MYSQL_ENGINE=

MAX_THREADS=$(cat /proc/cpuinfo | grep -c processor)
CHUNK_SIZE=400000
BASE_DIR=`pwd`
LOAD_DIR=
FORMAT=SQL
VALIDATE=0
CRC=0

START_TIME=$SECONDS

while true; do
  case "$1" in
    -u | --source_mysql_user ) SOURCE_MYSQL_USER="$2"; shift 2 ;;
    -p | --source_mysql_pass ) SOURCE_MYSQL_PASS="$2"; shift 2 ;;
    -h | --source_mysql_host ) SOURCE_MYSQL_HOST="-h$2"; shift 2 ;;
    --source_mysql_port ) SOURCE_MYSQL_PORT="--port=$2"; shift 2 ;;
    --source_mysql_socket ) SOURCE_MYSQL_SOCKET="--socket=$2"; shift 2 ;;
    --source_mysql_engine ) SOURCE_MYSQL_ENGINE="$2"; shift 2 ;;
    --destination_mysql_user ) DESTINATION_MYSQL_USER="$2"; shift 2 ;;
    --destination_mysql_pass ) DESTINATION_MYSQL_PASS="$2"; shift 2 ;;
    --destination_mysql_host ) DESTINATION_MYSQL_HOST="-h$2"; shift 2 ;;
    --destination_mysql_port ) DESTINATION_MYSQL_PORT="--port=$2"; shift 2 ;;
	--destination_mysql_socket ) DESTINATION_MYSQL_SOCKET="--socket=$2"; shift 2 ;;
	--destination_mysql_engine ) DESTINATION_MYSQL_ENGINE="$2"; shift 2 ;;
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

ACTION=$1  # DUMP, LOAD, MIGRATE
if [ "$ACTION" != "DUMP" ] && [ "$ACTION" != "LOAD" ] && [ "$ACTION" != "MIGRATE" ] ; then
	echo "You must specify either DUMP, LOAD or MIGRATE for an action"
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

if [ -n "$SOURCE_MYSQL_PASS" ] ; then
	SOURCE_MYSQL_PASS="-p$SOURCE_MYSQL_PASS"
fi
if [ -n "$DESTINATION_MYSQL_PASS" ] ; then
	DESTINATION_MYSQL_PASS="-p$DESTINATION_MYSQL_PASS"
fi
if [ -n "$SOURCE_MYSQL_USER" ] ; then
	SOURCE_MYSQL_USER="-u$SOURCE_MYSQL_USER"
fi
if [ -n "$DESTINATION_MYSQL_USER" ] ; then
	DESTINATION_MYSQL_USER="-u$DESTINATION_MYSQL_USER"
fi

SOURCE_CONNECTION_STRING=" $SOURCE_MYSQL_USER $SOURCE_MYSQL_PASS $SOURCE_MYSQL_HOST $SOURCE_MYSQL_SOCKET $SOURCE_MYSQL_PORT "
DESTINATION_CONNECTION_STRING=" $DESTINATION_MYSQL_USER $DESTINATION_MYSQL_PASS $DESTINATION_MYSQL_HOST $DESTINATION_MYSQL_SOCKET $DESTINATION_MYSQL_PORT "

if [ "$ACTION" == "MIGRATE" ] ; then
	echo "Checking source MySQL connection..."
	mysql $SOURCE_CONNECTION_STRING -e exit 2>/dev/null
	if [ $? -ne 0 ]; then
		echo "Failed to connect to source MySQL using $SOURCE_CONNECTION_STRING"
		exit;
	fi
	echo "Checking destination MySQL connection..."
	mysql $DESTINATION_CONNECTION_STRING -e exit 2>/dev/null
	if [ $? -ne 0 ]; then
		echo "Failed to connect to source MySQL using $DESTINATION_CONNECTION_STRING"
		exit;
	fi
elif [ "$ACTION" == "LOAD" ] ; then
	echo "Checking destination MySQL connection..."
	mysql $DESTINATION_CONNECTION_STRING -e exit 2>/dev/null
	if [ $? -ne 0 ]; then
		echo "Failed to connect to source MySQL using $DESTINATION_CONNECTION_STRING"
		exit;
	fi
elif [ "$ACTION" == "DUMP" ] ; then
	echo "Checking source MySQL connection..."
	mysql $SOURCE_CONNECTION_STRING -e exit 2>/dev/null
	if [ $? -ne 0 ]; then
		echo "Failed to connect to source MySQL using $SOURCE_CONNECTION_STRING"
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

echo SOURCE_MYSQL_USER=$SOURCE_MYSQL_USER
echo SOURCE_MYSQL_PASS=$SOURCE_MYSQL_PASS
echo SOURCE_MYSQL_HOST=$SOURCE_MYSQL_HOST
echo SOURCE_MYSQL_PORT=$SOURCE_MYSQL_PORT
echo SOURCE_MYSQL_SOCKET=$SOURCE_MYSQL_SOCKET
echo SOURCE_MYSQL_ENGINE=$SOURCE_MYSQL_ENGINE
echo SOURCE_CONNECTION_STRING=$SOURCE_CONNECTION_STRING
echo DESTINATION_MYSQL_USER=$DESTINATION_MYSQL_USER
echo DESTINATION_MYSQL_PASS=$DESTINATION_MYSQL_PASS
echo DESTINATION_MYSQL_HOST=$DESTINATION_MYSQL_HOST
echo DESTINATION_MYSQL_PORT=$DESTINATION_MYSQL_PORT
echo DESTINATION_MYSQL_SOCKET=$DESTINATION_MYSQL_SOCKET
echo DESTINATION_MYSQL_ENGINE=$DESTINATION_MYSQL_ENGINE
echo DESTINATION_CONNECTION_STRING=$DESTINATION_CONNECTION_STRING
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

if [ "$ACTION" == "DUMP" ] || [ "$ACTION" == "MIGRATE" ] ; then

	dir=$(date "+%Y-%m-%d_%Hh%Mm%Ss")
	mkdir -m 777 -p $BASE_DIR/$dir

	list_of_dbs=$(mysql $SOURCE_CONNECTION_STRING -BNe "show databases" | grep "$GREP_REGEX" | grep -v "information_schema" | grep -v "performance_schema" | grep -v "mysql")
	#dump the schema skeleton of all databases (no data)
	for db in $list_of_dbs ; do 
		mkdir -m 777 $BASE_DIR/$dir/$db
		mysqldump $SOURCE_CONNECTION_STRING --no-data --skip-add-drop-table --skip-comments $db > $BASE_DIR/$dir/$db/the-schema	
	done

	#if defined, convert engine from $SOURCE_MYSQL_ENGINE to $DESTINATION_MYSQL_ENGINE within the schema dump
	if [ -n "$SOURCE_MYSQL_ENGINE" ] && [ -n "$DESTINATION_MYSQL_ENGINE" ] ; then
		echo "Converting all tables ENGINEs from $SOURCE_MYSQL_ENGINE to $DESTINATION_MYSQL_ENGINE"
		find $BASE_DIR/$dir/ -name 'the-schema'| xargs perl -pi -e "s/ENGINE=$SOURCE_MYSQL_ENGINE/ENGINE=$DESTINATION_MYSQL_ENGINE/g"
	fi

	if [ "$ACTION" == "MIGRATE" ] && [ "$VALIDATE" -eq 0 ] ; then
		#create all the db's on the new db (over network)
		for db in $list_of_dbs ; do 
			mysql $DESTINATION_CONNECTION_STRING -e "CREATE DATABASE $db;"
			mysql $DESTINATION_CONNECTION_STRING $db < $BASE_DIR/$dir/$db/the-schema
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
			list_of_tables=$(mysql $SOURCE_CONNECTION_STRING -BNe "show tables" $db | grep "$TABLE_GREP_REGEX")
		else
			list_of_tables=$(mysql $SOURCE_CONNECTION_STRING -BNe "show tables" $db | grep -x "$TABLE_GREP_REGEX")
		fi

		for table in $list_of_tables ; do
			echo "$echotext database $db table $table ..."
			#if [ "$ACTION" == "MIGRATE" ] && [ "$VALIDATE" -eq 0 ] ; then
				#collect insertion rate stats
			#	$SCRIPTPATH/get_rate.sh -u$DESTINATION_MYSQL_USER $DESTINATION_MYSQL_PASS $DESTINATION_MYSQL_HOST $db.$table&
			#fi

			unique_key=$(mysql $SOURCE_CONNECTION_STRING -BNe "SHOW KEYS IN $table FROM $db WHERE Non_unique=0 AND Key_name='PRIMARY';" | awk '{ print $5 '})
			num_columns_in_key=$(mysql $SOURCE_CONNECTION_STRING -BNe "SHOW KEYS IN $table FROM $db WHERE Non_unique=0 AND Key_name='PRIMARY' ;" | wc -l)
			unique_key_data_type=$(mysql $SOURCE_CONNECTION_STRING -BNe "SELECT DATA_TYPE FROM information_schema.COLUMNS WHERE TABLE_SCHEMA ='$db' AND TABLE_NAME = '$table' AND COLUMN_NAME = '$unique_key';")
			
			#check how many rows are in the table if its larger than CHUNK_SIZE, then lets split it in chunks 
			if [ -n "$unique_key" ] && [ "$num_columns_in_key" -eq 1 ] && [[ "$unique_key_data_type" == *int* ]]; then
				num_rows=$(mysql $SOURCE_CONNECTION_STRING -BNe "SELECT table_rows FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA ='$db' AND table_name='$table';")
				num_rows_fifty=$((num_rows / 2))
				num_rows=$((num_rows + num_rows_fifty))				
			else
				num_rows=$(mysql $SOURCE_CONNECTION_STRING -BNe "SELECT count(*) FROM $db.$table;")
			fi

			if [ "$num_rows" -gt $CHUNK_SIZE ] ; then

				#echo "unique_key: $unique_key"
				#echo "num_columns_in_key: $num_columns_in_key"
				#echo "unique_key_data_type: $unique_key_data_type"

				if [ -n "$unique_key" ] && [ "$num_columns_in_key" -eq 1 ] && [[ "$unique_key_data_type" == *int* ]]; then
					max_unique_num=$(mysql $SOURCE_CONNECTION_STRING -BNe "SELECT MAX($unique_key) FROM $db.$table;")
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
						
						if [ "$ACTION" == "MIGRATE" ] ; then

							if [ "$VALIDATE" -eq 1 ] ; then
								#lets get the count on the source and dest
								num_rows_source=$(mysql $SOURCE_CONNECTION_STRING $db -BNe "SELECT COUNT($unique_key) FROM $db.$table WHERE $unique_key >= $limit_start AND $unique_key < $limit_end;")
								num_rows_dest=$(mysql $DESTINATION_CONNECTION_STRING $db -BNe "SELECT COUNT($unique_key) FROM $db.$table WHERE $unique_key >= $limit_start AND $unique_key < $limit_end;")
							fi

							if [ "$VALIDATE" -eq 1 ] && [ "$num_rows_source" -eq "$num_rows_dest" ] ; then
								echo "source and destination table $table both match having $num_rows_source rows WHERE $unique_key >= $limit_start AND $unique_key < $limit_end"
							elif [ "$VALIDATE" -eq 1 ] && [ "$num_rows_source" -ne "$num_rows_dest" ] ; then
								echo "source and destination table $table DO NOT MATCH! Source:$num_rows_source rows.  Dest:$num_rows_dest rows  WHERE $unique_key >= $limit_start AND $unique_key < $limit_end"
							elif [ "$VALIDATE" -eq 0 ]; then
								echo "$echotext chunk $j of $num_chunks for $db.$table where $unique_key >= $limit_start AND $unique_key < $limit_end"
								( echo "SET unique_checks=0;SET foreign_key_checks=0;" > $BASE_DIR/$dir/$db/$table-$j.sql; mysqldump $SOURCE_CONNECTION_STRING --no-create-db --no-create-info --compact --skip-add-locks --single-transaction --quick --where "$unique_key >= $limit_start AND $unique_key < $limit_end" $db $table >> $BASE_DIR/$dir/$db/$table-$j.sql ; mysql $DESTINATION_CONNECTION_STRING $db < $BASE_DIR/$dir/$db/$table-$j.sql ; rm $BASE_DIR/$dir/$db/$table-$j.sql ) &
							fi

						elif [ "$ACTION" == "DUMP" ]; then
							echo "$echotext chunk $j of $num_chunks for $db.$table where $unique_key >= $limit_start AND $unique_key < $limit_end"
							if [ "$FORMAT" == "SQL" ] ; then
								( echo "SET unique_checks=0;SET foreign_key_checks=0;" > $BASE_DIR/$dir/$db/$table-$j.sql; mysqldump $SOURCE_CONNECTION_STRING --no-create-db --no-create-info --compact --skip-add-locks --single-transaction --quick --where "$unique_key >= $limit_start AND $unique_key < $limit_end" $db $table >> $BASE_DIR/$dir/$db/$table-$j.sql 2>> $BASE_DIR/migrate_db.errors.log ) &
							elif [ "$FORMAT" == "INFILE" ] ; then
								mysql $SOURCE_CONNECTION_STRING -e"SELECT * INTO OUTFILE '$BASE_DIR/$dir/$db/$table.$j' FROM $db.$table WHERE $unique_key >= $limit_start AND $unique_key < $limit_end" 2>> $BASE_DIR/migrate_db.errors.log &
							else
								echo "Unknown format $FORMAT. exiting..."
								exit;
							fi
						fi
					else

						if [ "$VALIDATE" -eq 1 ] ; then
							num_rows_source=$(mysql $SOURCE_CONNECTION_STRING $db -BNe "SELECT COUNT(*) FROM $db.$table;")
							num_rows_dest=$(mysql $DESTINATION_CONNECTION_STRING $db -BNe "SELECT COUNT(*) FROM $db.$table;")
							if [ "$num_rows_source" -eq "$num_rows_dest" ] ; then
								echo "source and destination both match having $num_rows_source rows,"
							elif [ "$num_rows_source" -ne "$num_rows_dest" ]; then
								echo "source and destination DO NOT MATCH! Source:$num_rows_source rows.  Dest:$num_rows_dest rows."
							fi
							break;
						fi

						echo "$echotext chunk $j of $num_chunks for $db.$table where LIMIT $limit_start, $CHUNK_SIZE"
						if [ "$ACTION" == "MIGRATE" ] && [ "$VALIDATE" -eq 0 ] ; then
							#mysqldump $SOURCE_CONNECTION_STRING --max_allowed_packet=1000000000 --no-create-db --no-create-info --compact --skip-add-locks --single-transaction --quick --where "1 LIMIT $limit_start, $CHUNK_SIZE" $db $table | mysql --max_allowed_packet=1000000000 $DESTINATION_CONNECTION_STRING $db 2>> $BASE_DIR/migrate_db.errors.log &
							( echo "SET unique_checks=0;SET foreign_key_checks=0;" > $BASE_DIR/$dir/$db/$table-$j.sql; mysqldump $SOURCE_CONNECTION_STRING --no-create-db --no-create-info --compact --skip-add-locks --single-transaction --quick --where "1 LIMIT $limit_start, $CHUNK_SIZE" $db $table >> $BASE_DIR/$dir/$db/$table-$j.sql ; mysql $DESTINATION_CONNECTION_STRING $db < $BASE_DIR/$dir/$db/$table-$j.sql ; rm $BASE_DIR/$dir/$db/$table-$j.sql ) &
						elif [ "$ACTION" == "DUMP" ]; then
							if [ "$FORMAT" == "SQL" ] ; then
								( echo "SET unique_checks=0;SET foreign_key_checks=0;" > $BASE_DIR/$dir/$db/$table-$j.sql; mysqldump $SOURCE_CONNECTION_STRING --no-create-db --no-create-info --compact --skip-add-locks --single-transaction --quick --where "1 LIMIT $limit_start, $CHUNK_SIZE" $db $table >> $BASE_DIR/$dir/$db/$table-$j.sql 2>> $BASE_DIR/migrate_db.errors.log ) &
							elif [ "$FORMAT" == "INFILE" ] ; then
								mysql $SOURCE_CONNECTION_STRING -e"SELECT * INTO OUTFILE '$BASE_DIR/$dir/$db/$table.$j' FROM $db.$table LIMIT $limit_start, $CHUNK_SIZE" 2>> $BASE_DIR/migrate_db.errors.log &
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

				if [ "$ACTION" == "MIGRATE" ] && [ "$VALIDATE" -eq 0 ] ; then
					#mysqldump $SOURCE_CONNECTION_STRING --no-create-db --order-by-primary --no-create-info --compact --skip-add-locks --single-transaction --quick $db $table | mysql $DESTINATION_CONNECTION_STRING $db 2>> $BASE_DIR/migrate_db.errors.log &
					( echo "SET unique_checks=0;SET foreign_key_checks=0;" > $BASE_DIR/$dir/$db/$table-0.sql; mysqldump $SOURCE_CONNECTION_STRING --no-create-db --order-by-primary --no-create-info --compact --skip-add-locks --single-transaction --quick $db $table >> $BASE_DIR/$dir/$db/$table-0.sql ; mysql $DESTINATION_CONNECTION_STRING $db < $BASE_DIR/$dir/$db/$table-0.sql ; rm $BASE_DIR/$dir/$db/$table-0.sql ) &
				
				elif [ "$ACTION" == "MIGRATE" ] && [ "$VALIDATE" -eq 1 ] ; then
					num_rows_source=$(mysql $SOURCE_CONNECTION_STRING $db -BNe "SELECT COUNT(*) FROM $db.$table;")
					num_rows_dest=$(mysql $DESTINATION_CONNECTION_STRING $db -BNe "SELECT COUNT(*) FROM $db.$table;")
					if [ "$num_rows_source" -eq "$num_rows_dest" ] ; then
						echo "source and destination both match having $num_rows_source rows,"
					elif [ "$num_rows_source" -ne "$num_rows_dest" ]; then
						echo "source and destination DO NOT MATCH! Source:$num_rows_source rows.  Dest:$num_rows_dest rows."
					fi					
				elif [ "$ACTION" == "DUMP" ]; then
					if [ "$FORMAT" == "SQL" ] ; then
						(echo "SET unique_checks=0;SET foreign_key_checks=0;" > $BASE_DIR/$dir/$db/$table.sql; mysqldump $SOURCE_CONNECTION_STRING --no-create-db --order-by-primary --no-create-info --compact --skip-add-locks --single-transaction --quick $db $table >> $BASE_DIR/$dir/$db/$table.sql 2>> $BASE_DIR/migrate_db.errors.log ) &
					elif [ "$FORMAT" == "INFILE" ] ; then
						mysql $SOURCE_CONNECTION_STRING -e"SELECT * INTO OUTFILE '$BASE_DIR/$dir/$db/$table.1' FROM $db.$table" 2>> $BASE_DIR/migrate_db.errors.log &
					else
						echo "Unknown format $FORMAT. exiting..."
						exit;
					fi						
				fi
			fi

			#if MIGRATE and CRC then compute it for each table.
			if [ "$ACTION" == "MIGRATE" ] && [ "$CRC" -eq 1 ] ; then
				crc_source=$(mysql $SOURCE_CONNECTION_STRING $db -BNe "CHECKSUM TABLE $db.$table;" | awk '{ print $2 '})
				crc_dest=$(mysql $DESTINATION_CONNECTION_STRING $db -BNe "CHECKSUM TABLE $db.$table;" | awk '{ print $2 '})
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
		mysql $DESTINATION_CONNECTION_STRING -e "CREATE DATABASE $db;"
		echo "loading $LOAD_DIR/$db/the-schema"
		mysql $DESTINATION_CONNECTION_STRING $db < $LOAD_DIR/$db/the-schema
		if [ "$FORMAT" == "SQL" ] ; then
			#foreach file in the dir
			for sql_file in $LOAD_DIR/$db/*.sql ; do
				# sleep a bit if we are at the MAX_THREADS
				while [ "$(jobs -pr | wc -l)" -gt "$MAX_THREADS" ] ; do sleep 2; done
				echo "loading file $sql_file"
				mysql $DESTINATION_CONNECTION_STRING $db < $sql_file & 
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
				mysql --local-infile $DESTINATION_CONNECTION_STRING -e "LOAD DATA LOCAL INFILE '$infile' INTO TABLE $TABLE" $db  & 
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
