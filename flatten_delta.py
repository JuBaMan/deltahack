import datetime
import time
from delta.tables import *

import os
import re

EARLIEST_AVAILABLE_VERSION = 0
OLD_DELTA_TABLE = "old_delta_table"
FLATTENED_TABLE = "flattened_table"

def read_Delta_Produce_Map(): # Connect to Databricks if you need to, this needs to run exactly where you've stored the old Delta Table
    spark = SparkSession.builder.getOrCreate()
    # Get the Delta table history, sorted by version (lowest first)
    delta_history = DeltaTable.forPath(spark, f"{OLD_DELTA_TABLE}").history().orderBy("version")

    # Loop over each commit version in the history
    for row in delta_history.collect():
        version = row["version"]
        if version < EARLIEST_AVAILABLE_VERSION: # Use when the vacuum was run and there is no history beyond a point
            continue
        ts = row["timestamp"]  # This is the commit timestamp
        
        # Convert timestamp to a safe string for folder naming
        ts_str = str(ts)
        safe_ts = re.sub(r'[^\w\-\.]', '_', ts_str)
        version_folder = f"{database.output_Path}/ILRs/{safe_ts}"
        
        print(f"Saving version {version} with timestamp {ts} to folder {version_folder}")
        
        # Read the Delta table snapshot at this version
        df_version = database.spark.read.format("delta") \
                            .option("versionAsOf", version) \
                            .load(f"{database.delta_Path}/HistoricInterimRatesEntities")
    

        # Write the snapshot to the designated folder as Parquet files
        df_version.write.mode("overwrite").parquet(version_folder)


def main():
    read_Delta_Produce_Map()
