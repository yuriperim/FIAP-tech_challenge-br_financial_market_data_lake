import sys
from datetime import datetime, timezone
import logging
import boto3
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.window import Window
from awsglue.context import GlueContext
from awsglue.job import Job

# Configuração do logger
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# @params: [JOB_NAME]
args = getResolvedOptions(sys.argv, ["JOB_NAME", "bucket_name"])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Clients
glue_client = boto3.client("glue")

# Transformações
raw_stocks_sdf = glueContext.create_dynamic_frame.from_catalog(
    database="br_financial_market",
    table_name="raw_stocks"
).toDF()

refined_stocks_sdf = (raw_stocks_sdf.withColumnRenamed("longName", "name")
                                    .withColumnRenamed("Volume", "tradedVolume"))

w_latest = (Window.partitionBy("datatrade", "ticker")
                  .orderBy(F.col("dataproc").desc()))
refined_stocks_sdf = (refined_stocks_sdf.withColumn("rn", F.row_number().over(w_latest))
                                        .filter(F.col("rn") == 1)
                                        .drop("dataproc", "rn"))

w_sector = Window.partitionBy("datatrade", "sector")
refined_stocks_sdf = refined_stocks_sdf.withColumn("totalSectorTradedVolume", F.sum("tradedVolume").over(w_sector))

refined_stocks_sdf = refined_stocks_sdf.withColumn(
    "fracSectorTradedVolume",
    F.round(100.0 * F.col("tradedVolume") / F.col("totalSectorTradedVolume"), 2)
)

w_lag = (Window.partitionBy("ticker")
               .orderBy("datatrade"))
refined_stocks_sdf = refined_stocks_sdf.withColumn("prevClose", F.lag("Close").over(w_lag))

refined_stocks_sdf = refined_stocks_sdf.withColumn(
    "TR",  # True Range
    F.when(
        F.col("prevClose").isNull(),
        F.col("High") - F.col("Low")
    ).otherwise(
        F.greatest(
            F.col("High") - F.col("Low"),
            F.abs(F.col("High") - F.col("prevClose")),
            F.abs(F.col("Low") - F.col("prevClose"))
        )
    )
).drop("prevClose")

# -> SMA (Simple Moving Average)
w_tr_sma = (Window.partitionBy("ticker")
                  .orderBy("datatrade")
                  .rowsBetween(-13, 0))  # janela de 14 dias, incluindo o dia atual
refined_stocks_sdf = refined_stocks_sdf.withColumn("ATR", F.avg("TR").over(w_tr_sma))

dataproc = int(datetime.now(timezone.utc).strftime("%Y%m%d"))
refined_stocks_sdf = refined_stocks_sdf.withColumn("dataproc", F.lit(dataproc))

# Informações DataFrame
logger.info("Schema do DataFrame")
refined_stocks_sdf.printSchema()
logger.info(f"Número de registros no DataFrame: {refined_stocks_sdf.count()}")

# Persistência dados
bucket_name = args["bucket_name"]
stocks_path = f"s3://{bucket_name}/refined/stocks/"

# -> Sobrescreve partições presentes, preservando as demais
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")  # default: static
# -> Particiona por datatrade e ticker, evitando duplicidade
(refined_stocks_sdf.write
                   .mode("overwrite")
                   .partitionBy("datatrade", "ticker")
                   .option("compression", "snappy")  # opção default, declarada para mostrar intenção
                   .parquet(stocks_path))

# Catalogação dados
db_name = "br_financial_market"
tb_name = "refined_stocks"
tb_loc = stocks_path

tb_input = {
    "Name": tb_name,
    "StorageDescriptor": {
        "Columns": [
            {"Name": "name", "Type": "string"},
            {"Name": "sector", "Type": "string"},
            {"Name": "tradedVolume", "Type": "bigint"},
            {"Name": "totalSectorTradedVolume", "Type": "bigint"},
            {"Name": "fracSectorTradedVolume", "Type": "double"},
            {"Name": "Open", "Type": "double"},
            {"Name": "High", "Type": "double"},
            {"Name": "Low", "Type": "double"},
            {"Name": "Close", "Type": "double"},
            {"Name": "TR", "Type": "double"},
            {"Name": "ATR", "Type": "double"},
            {"Name": "isRepaired", "Type": "boolean"},
            {"Name": "dataproc", "Type": "int"},
        ],
        "Location": tb_loc,
        "InputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat",
        "OutputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat",
        "SerdeInfo": {
            "SerializationLibrary": "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe",
        },
    },
    "PartitionKeys": [
        {"Name": "datatrade", "Type": "int"},
        {"Name": "ticker", "Type": "string"},
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

job.commit()
