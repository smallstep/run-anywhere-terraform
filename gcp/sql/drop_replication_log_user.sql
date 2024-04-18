-- Drops a user on the cluster.
-- Requires the following variables to be passed to psql using '-v'
-- user  ->  name of the replication user / role
--

SELECT current_database(),
       concat(concat('This script will remove the "', :'user'), '" ROLE from this cluster.') as "note:";


DROP ROLE IF EXISTS :"user";
