# deltahack

_A hack to allow copying your old Delta tables created with delta <= 3.2 while preserving their history._

---

## Overview

Only works for a reasonably small amount of versions per table, for example something that updated daily for a couple of years. For millisecond precision and/or that magnitude of number of updates, this is not the solution for you. It will only recover versions since the last Delta vacuum call, since the history before that is collapsed.

---

## How to Run

1. **Build and attach a tty**  
   Use the provided Linux-based Dockerfile to build and attach a tty to a container.

2. **Run `flatten_delta.py` on your host environment**  
   Execute `flatten_delta.py` wherever you are trying to copy this old table from. This will flatten the Delta file history, outputting the entire table for every version ever recorded in individual parquet files named after the timestamp they were edited at.

3. **Copy the flattened table to the container**  
   Use the following command to copy the resulting flattened table:
   ```bash
   docker cp <flattened_parquet_path> <container_name_or_id>:<destination_path>
   ```
   The flattened version of the table can be copied from the cloud onto your local machine without history loss.

4. **Run `subprocess_iterative_delta_backwrites.py`**  
   This script will:
   - Change the time in your container for each version.
   - Create a new SparkSession whose jvm picks up on this new global time for each version.
   - Iteratively write the flattened files to your new, delta >= 3.3 compatible Delta Table in chronological order.


