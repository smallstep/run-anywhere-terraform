-- Creates a user with appropriate grants & privileges for a replication user

SELECT current_database(),
       concat(concat('This script is idempotent but CREATE ROLE "', :'user'), '" throws error if the ROLE exists. This is OK.') as "note:";

-- CREATE ROLE will fail if the user / role already exists, but that won't prevent the successful execution of this script
CREATE ROLE :"user" LOGIN PASSWORD :'pw';

-- ensure the password is updated properly
ALTER ROLE :"user" WITH PASSWORD :'pw';

-- and allow the user to connect and use the database.
GRANT CONNECT ON DATABASE :"db_name" TO :"user";
GRANT USAGE ON SCHEMA public to :"user";

-- grants ability to connect to the replication log and SELECT from all tables
-- in given databases.
ALTER ROLE :"user" WITH REPLICATION;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO :"user";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO :"user";
