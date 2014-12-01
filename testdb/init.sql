
DROP DATABASE IF EXISTS temba_mage_tests;
DROP ROLE IF EXISTS temba_mage_tests;

CREATE DATABASE temba_mage_tests;
CREATE ROLE temba_mage_tests LOGIN PASSWORD '' SUPERUSER;
GRANT ALL ON DATABASE temba_mage_tests TO temba_mage_tests;