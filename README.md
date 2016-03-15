# migrate_db

A script to either DUMP, LOAD or MIGRATE a mysql database, in a highly parallelized manner. (i.e. very fast)

* DUMP will dump the source database files to disk.
* LOAD will load a MySQL database with the DUMP'ed files specified.
* MIGRATE will copy MySQL database(s) from one location to another. (fastest option, typically server to server)

You must specify either DUMP, LOAD or MIGRATE for an action

# Usage

    migrate_db.sh [options] [action (DUMP|LOAD|MIGRATE)] [database(s) (grep regex)] [table]

## Options

     --source_mysql_user=USER
                source mysql username to be used. current user is used if not specified.
     --source_mysql_pass=PASSWORD
                source mysql password to be used.
     --source_mysql_host=HOST
                destination mysql host. Used for MIGRATE action only.
     --source_mysql_port=PORT
                source port to be used.
     --source_mysql_socket=SOCKET_FILE
                source socket file to be used.
     --source_mysql_engine=ENGINE
                source mysql database engine. 
     --destination_mysql_user=USER
                destination mysql user. Used for MIGRATE action only. current user is used if not specified.
     --destination_mysql_pass=PASSWORD
                destination mysql password. Used for MIGRATE action only.
     --destination_mysql_host=HOST
                destination mysql host. Used for MIGRATE action only.
     --destination_mysql_port=DEST_PORT
                destination source port to be used.
     --destination_mysql_socket=SOCKET_FILE
                source socket file to be used.
     --destination_mysql_engine=ENGINE
                destination mysql database engine. 
     --max_threads=NUM_THREADS
                max parrallel processes used. default is half your processors (best)
     --chunk_size=SIZE
                number of rows used to split up large tables. 400000 is the default.
     --base_dir=DIR
                base directory to store DUMPS. default is pwd. a directory is created with the current date and time in this dir to store the data
     --load_dir=DIR
                directory to LOAD a dump from. The directory should contain a directory per schema in it.
     --format=FORMAT
                format of the data to be loaded or dumped. either SQL(default) or INFILE.
     --validate
                validate the number of rows on the source and destination. for MIGRATE option only.
     --crc
                validate tables match on source and destination using CHECKSUM TABLE. for MIGRATE option only.
 
n.b.:

If no database is specified, we migrate all databases.
If no table is specified, we migrate all tables. (either 1 or all)

# Examples

Dumping database Database8 to disk:

    ./migrate_db.sh --source_mysql_user=root --source_mysql_pass=foobar DUMP Database8

note: When this is run a directory is made using the current date and timestamp that contains all of the dump files for each schema

Dumping database Database8 to disk as tab delimited file for performing INFILE LOAD's later

    ./migrate_db.sh --source_mysql_user=root --source_mysql_pass=foobar --format=INFILE DUMP Database8

Load all databases from a dump directory:

    ./migrate_db.sh --dest_mysql_user=root --dest_mysql_pass=foobar --dest_host=10.1.10.112 --load_dir=/home/user/2014-05-14_09h55m45s LOAD

Load just Database8 database from a dump directory:

    ./migrate_db.sh --destination_mysql_user=root --destination_mysql_pass=foobar --destination_mysql_host=10.1.10.112 --load_dir=/home/user/2014-05-14_09h55m45s LOAD Database8

Migrating from one server to another using the MIGRATE option:

example of migrating all schemas and all tables:

    ./migrate_db.sh --source_mysql_user=root --source_mysql_pass=foobar --destination_mysql_user=root --destination_mysql_pass=foobar --destination_mysql_host=10.1.10.112 MIGRATE
 
Example of migrating all databases starting with Database12  and all tables for each

    ./migrate_db.sh --source_mysql_user=root --source_mysql_pass=foobar --destination_mysql_user=root --destination_mysql_pass=foobar --destination_mysql_host=10.1.10.112  MIGRATE Database12

Example of migrating all databases starting with Database12  and altering the database engine on the destination

    ./migrate_db.sh --source_mysql_user=root --source_mysql_pass=foobar --destination_mysql_user=root --destination_mysql_pass=foobar --destination_mysql_host=10.1.10.112 --source_mysql_engine=InnoDB --destination_mysql_engine=Deep MIGRATE Database12

note: both source_mysql_engine and destination_mysql_engine must be specified.

Example of migrating all databases starting with Database12 and only the Accounts table within them

    ./migrate_db.sh --source_mysql_user=root --source_mysql_pass=foobar --destination_mysql_user=root --destination_mysql_pass=foobar --destination_mysql_host=10.1.10.112  MIGRATE Database12 Accounts 

Example of migrating a single table in a given schema (what you want for patching a single table).

    ./migrate_db.sh --source_mysql_user=root --source_mysql_pass=foobar --destination_mysql_user=root --destination_mysql_pass=foobar --destination_mysql_host=10.1.10.112  MIGRATE Database123 Accounts 
 
Example of validating all databases that have been migrated via MIGRATE (row count and CRC check)

    ./migrate_db.sh --source_mysql_user=root --source_mysql_pass=foobar --destination_mysql_user=root --destination_mysql_pass=foobar --destination_mysql_host=10.1.10.112 --validate --crc  MIGRATE


