import logging
import boto3

# Configuração do logger
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Client
glue_client = boto3.client("glue")


def lambda_handler(event, context):
    for record in event["Records"]:
        key = record["s3"]["object"]["key"]
        if "_SUCCESS" in key:
            logger.info("Iniciando job de transformação")
            glue_client.start_job_run(JobName="br-financial-market-transform-job")
            break

    return {"statusCode": 200}
