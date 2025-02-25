import os
import time
import datetime
import subprocess
import argparse
from pyspark.sql import SparkSession
from delta.tables import DeltaTable

# Global paths (adjust as needed)
NEW_VERSION_PATH = "/tmp/NEW"
OLD_VERSION_PATH = "/usr/local/OLD"

def reset_time(timestamp: datetime.datetime) -> str:
    """
    Returns a FAKETIME string set 33 seconds before the provided timestamp.
    """
    seconds_before = timestamp - datetime.timedelta(seconds=33)
    faketime_str = "@" + seconds_before.strftime("%Y-%m-%d %H:%M:%S")
    print("Setting FAKETIME to:", faketime_str)
    return faketime_str

def new_spark_session() -> SparkSession:
    # Initialize Spark session with Delta support
    spark = SparkSession.builder \
        .appName("DeltaTableExample") \
        .getOrCreate()
    
    # Get current time from the JVM for verification
    jvm_time_ms = spark._jvm.java.lang.System.currentTimeMillis()
    jvm_time = datetime.datetime.fromtimestamp(jvm_time_ms / 1000)
    print("JVM time:", jvm_time)
    return spark

def stop_spark_session(spark: SparkSession):
    spark.stop()

def create_new_version_table(spark: SparkSession, first_df):
    # Write the DataFrame to a Delta table
    first_df.write.format("delta").mode("overwrite").save(NEW_VERSION_PATH)

    # Enable In-Commit Timestamps (ICT) for future writes
    spark.sql(f"""
    ALTER TABLE delta.`{NEW_VERSION_PATH}`
    SET TBLPROPERTIES ('delta.enableInCommitTimestamps' = 'true')
    """)
    print("Set delta.enableInCommitTimestamps = true for future writes.")

def process_single_folder(folder_path: str):
    """
    Process a single folder:
      - Reads the Parquet data from folder_path.
      - Writes it to the Delta table at NEW_VERSION_PATH.
      This function is meant to be run in its own process.
    """
    spark = new_spark_session()
    df = spark.read.parquet(folder_path)
    df.write.format("delta").mode("overwrite").save(NEW_VERSION_PATH)
    stop_spark_session(spark)
    print(f"Processed {folder_path} and overwrote Delta table at {NEW_VERSION_PATH}")

def parse_timestamp(folder_name: str) -> datetime.datetime:
    # Folder names follow the pattern "YYYY-MM-DD_HH_MM_SS"
    return datetime.datetime.strptime(folder_name, "%Y-%m-%d_%H_%M_%S")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--folder", help="Folder to process (for subprocess mode)")
    parser.add_argument("--new_version_path", help="Output Delta table path", default=NEW_VERSION_PATH)
    args = parser.parse_args()

    if args.folder:
        # Subprocess mode: process just the given folder.
        process_single_folder(args.folder)
    else:
        # Main driver mode: iterate over all folders and spawn subprocesses.
        folders = os.listdir(OLD_VERSION_PATH)
        # Build list of (folder_name, timestamp) tuples
        folders_with_ts = [(folder, parse_timestamp(folder)) for folder in folders]
        # Sort folders chronologically (oldest first)
        sorted_folders = sorted(folders_with_ts, key=lambda x: x[1])

        # Process the first folder to create the initial Delta table.
        first_folder, first_timestamp = sorted_folders[0]
        first_folder_path = os.path.join(OLD_VERSION_PATH, first_folder)
        faketime = reset_time(first_timestamp)
        os.environ["FAKETIME"] = faketime
        time.sleep(13)  # Give libfaketime time to set the new time
        spark = new_spark_session()
        first_df = spark.read.parquet(first_folder_path)
        create_new_version_table(spark, first_df)
        stop_spark_session(spark)

        # Loop over the remaining folders, spawning a new process for each.
        for folder_name, timestamp_obj in sorted_folders[1:]:
            folder_path = os.path.join(OLD_VERSION_PATH, folder_name)
            print(f"\nProcessing folder: {folder_path} with timestamp: {timestamp_obj}")

            # Prepare the new FAKETIME value for this iteration.
            faketime = reset_time(timestamp_obj)
            # Create an environment for the subprocess with the updated FAKETIME.
            env = os.environ.copy()
            env["FAKETIME"] = faketime

            # Wait a bit to let FAKETIME take effect.
            time.sleep(13)
            # Spawn a new process that runs this same script in "subprocess mode".
            subprocess.run([
                "python3", __file__,
                "--folder", folder_path,
                "--new_version_path", NEW_VERSION_PATH
            ], env=env)
            print(f"Delta table at {NEW_VERSION_PATH} overwritten with data from timestamp: {timestamp_obj}")

if __name__ == "__main__":
    main()
