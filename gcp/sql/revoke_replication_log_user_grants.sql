-- Revokes any privileges granted to a user on the specified database.
-- Requires the following variables to be passed to psql using '-v'
-- user  ->  name of the replication user
-- db_name  ->  database name where the grants are to be applied
--

SELECT current_database(),
       concat(concat('This script will remove any granted privileges from the "', :'user'), '" ROLE in this database.') as "note:";

REVOKE ALL ON DATABASE :db_name
FROM :"user";

REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public
FROM :"user";

REVOKE USAGE ON SCHEMA public
FROM :"user";

ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL PRIVILEGES ON TABLES
FROM :"user";
