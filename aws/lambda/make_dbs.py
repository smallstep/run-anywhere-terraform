# Script that takes a list of secrets to the Aurora Cluster hosting the smallstep application
# and logs into the cluster to create the required databases

import boto3
import json
import logging
import os
import psycopg2

logger = logging.getLogger()
logger.setLevel(logging.INFO)

client = boto3.client('secretsmanager')

def lambda_handler(event, context):
  logger.info("--- Aurora Cluster database creation has started ---")
  logger.info("--- Attempting to log into cluster with given info ---")

  logger.info("--- Trying to retrieve secret dict for the cluster ---")
  try:
    response = client.get_secret_value(
      SecretId = os.environ.get('secret_id')
    )
    logger.info("--- Successfully retrieved cluster secrets ---")
  except Exception as e:
    logger.info(e)
    logger.info("--- FAILED TO RETRIEVE CLUSTER SECRETS - TERMINATING SCRIPT ---")

  # Separate out for readability
  secret_dict = json.loads(response['SecretString'])
  db_names    = secret_dict['db_names']

  # Attempt to log into the cluster and fail if unable
  try:
    # conn = psycopg2.connect(host=secret_dict['host'], user=secret_dict['username'], password=secret_dict['password'], port=secret_dict['port'], sslmode='require')
    conn = psycopg2.connect(dbname='postgres', host=secret_dict['host'], user=secret_dict['username'], password=secret_dict['password'], port=secret_dict['port'])
    logger.info("--- Successfully logged into cluster ---")
  except psycopg2.OperationalError as e:
    logger.info(e)
    logger.info("--- FAILED TO LOG INTO CLUSTER - TERMINATING SCRIPT ---")
    exit(1)

  # Setting autocommit since CREATE DATABASE cannot be called in a transaction block
  conn.set_isolation_level(0)

  # Now create each of the 10 required databases
  try:
    with conn.cursor() as cur:
      for name in db_names:
        logger.info("--- Creating database %s ---" % name)
        cur.execute("CREATE DATABASE %s" % name)
        logger.info(cur.statusmessage)
  finally:
    conn.close

  logger.info("--- Successfully created all databases in the cluster ---")