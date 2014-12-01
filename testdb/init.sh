#!/bin/bash

SCHEMA_FROM_DB=$1

if [ "${SCHEMA_FROM_DB}" = "" ]
then
  echo "Please provide name of existing database to copy schema from"
  exit
fi

TEST_DB="temba_mage_tests"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TEMP_DUMP_FILE="${DIR}/schema.tmp.sql"

echo "Dropping (if necessary) and creating database '${TEST_DB}'"

psql -q -f "${DIR}/init.sql"

echo "Dumping schema from local database..."

pg_dump --schema-only --no-owner $1 > "${TEMP_DUMP_FILE}"

echo "Loading Temba schema into '${TEST_DB}'"

psql -q -d ${TEST_DB} -f "${TEMP_DUMP_FILE}"

rm "${TEMP_DUMP_FILE}"

echo "Testing database initialized"