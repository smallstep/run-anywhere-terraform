#!/usr/bin/env bash

: ${KUBE_CTX:=`kubectl config current-context`}
: ${NAMESPACE:=smallstep}
: ${PORT:=5434}

echo "Using direct db access to $DB_INSTANCE on port $PORT"
./cloud_sql_proxy -instances=$DB_INSTANCE=tcp:$PORT &
sleep 3

if [ "$ACTION" = "destroy" ]; then
    # This sets the password for the postgres user used by psql.
    export PGPASSWORD=`echo -n $PGPASSWORD_ciphertext | base64 -d | gcloud kms decrypt --project $PROJECT --location global --keyring smallstep-terraform --key terraform-secret --ciphertext-file=- --plaintext-file=-`

    echo "Destroying user: ${USER:-<empty>}"

    for DB_NAME in $DB_NAMES
    do
        psql -U postgres -h localhost -p $PORT dbname=$DB_NAME -v user=$USER -v db_name=$DB_NAME -f $REVOKE_USER_GRANTS_SQL
        RET=$(($RET+$?))
    done
    psql -U postgres -h localhost -p $PORT dbname=postgres -v user=$USER -v db_name=postgres -f $REVOKE_USER_GRANTS_SQL
    RET=$(($RET+$?))
    psql -U postgres -h localhost -p $PORT dbname=postgres -v user=$USER -f $DROP_USER_SQL
    RET=$(($RET+$?))

else # create
    echo "Creating user: ${USER:-<empty>}"
    RET=0
    for DB_NAME in $DB_NAMES
    do
    # The password for the 'postgres' user is set in $PGPASSWORD in the
    # null-resource local-exec provisioners in sql.tf
        psql -U postgres -h localhost -p $PORT dbname=$DB_NAME -v user=$USER -v pw=$PW -v db_name=$DB_NAME -f $CREATE_USER_SQL
        RET=$(($RET+$?))
    done
fi

cleanup

exit $RET
