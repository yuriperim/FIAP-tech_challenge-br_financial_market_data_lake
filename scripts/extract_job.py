import sys
import random
import time
from datetime import datetime, timezone
import json
import logging
import boto3
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from awsglue.context import GlueContext
from awsglue.job import Job

import pandas as pd
import yfinance as yf

# Configuração do logger
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# @params: [JOB_NAME]
args = getResolvedOptions(sys.argv, ["JOB_NAME", "bucket_name"])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

job = Job(glueContext)
job.init(args["JOB_NAME"], args)


# Função para extrair dados dos tickers usando yfinance
def get_tickers_data(tickers_list):
    daily_dfs = []
    missing_tickers = []

    # Campos
    cols = [
        "datatrade",
        "ticker",
        "longName",
        "sector",
        "Open",
        "High",
        "Low",
        "Close",
        "Volume",
        "Repaired?",
    ]

    for ticker in tickers_list:
        try:
            logger.info(f"Extraindo dados do ticker {ticker}")

            ticker_data = yf.Ticker(f"{ticker}.SA")
            df = ticker_data.history(period="1d", repair=True)

            df["ticker"] = ticker
            df["longName"] = ticker_data.info.get("longName", "")
            df["sector"] = ticker_data.info.get("sector", "")
            df["datatrade"] = df.index.strftime("%Y%m%d").astype(int)

            daily_dfs.append(df[cols])
        except Exception:
            logger.error(f"Erro ao extrair dados do ticker {ticker}")

            missing_tickers.append(ticker)
        finally:
            # Evita sobrecarregar yfinance
            time.sleep(random.uniform(0.5, 1.0))

    return daily_dfs, missing_tickers


# Clients
s3_client = boto3.client("s3")
glue_client = boto3.client("glue")

# Tickers
bucket_name = args["bucket_name"]

tickers_obj = s3_client.get_object(
    Bucket=bucket_name,
    Key="glue/scripts/tickers.json"
)
tickers_json = json.load(tickers_obj["Body"])
tickers_list = tickers_json["tickers"]

# Dados tickers
tickers_dfs_1st, missing_tickers = get_tickers_data(tickers_list)
tickers_dfs_2nd, _ = get_tickers_data(missing_tickers)
tickers_df = pd.concat([*tickers_dfs_1st, *tickers_dfs_2nd], ignore_index=True)

tickers_sdf = spark.createDataFrame(tickers_df)

tickers_sdf = tickers_sdf.withColumnRenamed("Repaired?", "isRepaired")

dataproc = int(datetime.now(timezone.utc).strftime("%Y%m%d"))
tickers_sdf = tickers_sdf.withColumn("dataproc", F.lit(dataproc))

# Informações DataFrame
logger.info("Schema do DataFrame")
tickers_sdf.printSchema()
logger.info(f"Número de registros no DataFrame: {tickers_sdf.count()}")

# Persistência dados
stocks_path = f"s3://{bucket_name}/raw/stocks/"

# -> Sobrescreve partições presentes, preservando as demais
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")  # default: static
# -> Particiona por dataproc, evitando duplicidade
(tickers_sdf.write
            .mode("overwrite")
            .partitionBy("dataproc")
            .option("compression", "snappy")  # opção default, declarada para mostrar intenção
            .parquet(stocks_path))

# Catalogação dados
db_name = "br_financial_market"
tb_name = "raw_stocks"
tb_loc = stocks_path

tb_input = {
    "Name": tb_name,
    "StorageDescriptor": {
        "Columns": [
            {"Name": "datatrade", "Type": "int"},
            {"Name": "ticker", "Type": "string"},
            {"Name": "longName", "Type": "string"},
            {"Name": "sector", "Type": "string"},
            {"Name": "Open", "Type": "double"},
            {"Name": "High", "Type": "double"},
            {"Name": "Low", "Type": "double"},
            {"Name": "Close", "Type": "double"},
            {"Name": "Volume", "Type": "bigint"},
            {"Name": "isRepaired", "Type": "boolean"},
        ],
        "Location": tb_loc,
        "InputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat",
        "OutputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat",
        "SerdeInfo": {
            "SerializationLibrary": "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe",
        },
    },
    "PartitionKeys": [
        {"Name": "dataproc", "Type": "int"},
    ],
    "TableType": "EXTERNAL_TABLE",
}

try:
    glue_client.get_database(Name=db_name)
except glue_client.exceptions.EntityNotFoundException:
    logger.info(f"Criando banco de dados {db_name} no Glue Catalog")
    glue_client.create_database(DatabaseInput={"Name": db_name})

try:
    glue_client.get_table(DatabaseName=db_name, Name=tb_name)
except glue_client.exceptions.EntityNotFoundException:
    logger.info(f"Criando tabela {tb_name} no Glue Catalog")
    glue_client.create_table(DatabaseName=db_name, TableInput=tb_input)
else:
    logger.info(f"Atualizando tabela {tb_name} no Glue Catalog")
    glue_client.update_table(DatabaseName=db_name, TableInput=tb_input)

logger.info("Descobrindo partições no Glue Catalog")
repair_query = f"MSCK REPAIR TABLE {db_name}.{tb_name}"
spark.sql(repair_query)

# Finalização
try:
    logger.info("Criando arquivo _SUCCESS")
    success_key = f"raw/stocks/dataproc={dataproc}/_SUCCESS"
    s3_client.put_object(
        Bucket=bucket_name,
        Key=success_key,
        Body=b""
    )
except Exception:
    logger.error("Erro ao criar arquivo _SUCCESS")
    raise

job.commit()
