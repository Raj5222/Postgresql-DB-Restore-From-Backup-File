# 🚀 PostgreSQL DB Restore — Selected Data Restore Script  

# 📘 Overview

This documentation describes a **safe, precise, and high‑control PostgreSQL restore tool** that restores selected rows or full tables from a `.dump` file into a **live database** — exactly as implemented in your updated script.

This tool is engineered for:
- Selective row-level restore  
- Full-table restore  
- Clean, atomic operations  
- Fully controlled collision handling  
- Zero-risk rollback on failure  

---

# ✨ Key Features (Updated to Match the Script)

### ✔️ Transaction Integrity (All-or-Nothing)
Your script runs the entire restore process in **one global transaction**:

- ✔️ Success → COMMIT  
- ❌ Error → Automatic ROLLBACK  
- ❌ Script interruption → ROLLBACK  
- ❌ Constraint errors → ROLLBACK  

This guarantees **no partial data**.

---

### ✔️ Automatic Safety & Cleanup
Your script includes a trap handler to catch:

- Ctrl+C  
- Terminal crash  
- Command failure  
- System interrupt  

Automatic actions:

- Cancels the transaction  
- Drops **every temporary staging table**  
- Cleans the environment  
- Reports failure  

---

### ✔️ Intelligent PK-Aware Restore Logic
For each table:

- Automatically detects the **primary key**  
- Deletes only rows matching filters  
- Removes conflicting PK rows  
- Inserts restored data safely  
- Validates row count after insert  

This ensures correctness and repeatability.

---

### ✔️ Constraint-Free Copy Mode
Your script uses:

```
SET session_replication_role = 'replica';
```

Which temporarily disables:

- Foreign key checks  
- Triggers  
- Rules  

Making it safe to insert historical IDs or dependent records.

---

### ✔️ Silent Mode for Clean Output
Your script filters unnecessary PostgreSQL noise:

- Collation mismatch warnings  
- Hints  
- Internal detail messages  

Result: **professional, readable logs**.

---

# ⚙️ Configuration

### Database Settings
```bash
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="terotam_local"
DB_USER="postgres"
DB_PASS="your_password"
```

### Backup File
```bash
BACKUP_FILE="/path/to/backup.dump"
```

### Restore Targets (Updated Format Exactly Matching Script)
```
TABLE_NAME : COLUMN : VALUE_LIST
```
or:
```
TABLE_NAME : FULL
```

Example:
```bash
TARGETS=(
  "custom_module_data : customer_id : 1441"
  "custom_module_equipment_map : cm_id : 50,51,52"
  "system_settings : FULL"
)
```

---

# 🧠 How the Script Works (Updated Phase Names)

Your script uses **three synchronized phases**, as shown in logs.

---

# 🔹 PHASE 1: EXTRACTING DATA FROM BACKUP
### (Matches script header: “PHASE 1: EXTRACTING DATA FROM BACKUP”)

This phase:

- Creates temporary staging tables  
- Restores matching rows into them  
- Counts and validates loaded data  
- Prevents continuation if rows = 0  

Tasks performed:

```
CREATE TABLE temp
COPY backup → temp
SELECT COUNT(*)
```

This ensures **restored data exists before modifying real tables**.

---

# 🔹 PHASE 2: APPLYING DATA TO DATABASE
### (Matches script header: “PHASE 2: APPLYING DATA TO DATABASE”)

This phase runs inside one transaction.

It performs:

1. Delete existing matching rows  
2. Delete rows with conflicting primary keys  
3. Insert restored rows  
4. Validate inserted row count exactly matches backup count  
5. Append restore stats for final summary  

Operations include:

```
DELETE ... WHERE column IN (IDs)
DELETE ... WHERE pk IN (SELECT pk FROM temp)
INSERT INTO table SELECT * FROM temp
```

If any mismatch occurs → automatic exception → rollback.

---

# 🔹 PHASE 3: CLEANUP AND FINAL REPORT
### (Matches script header: “PHASE 3: CLEANUP AND FINAL REPORT”)

Actions:

- Drops all temporary staging tables  
- Prints summary report  
- Shows old rows removed, new rows inserted, and net gain  

The final report lists:

```
TABLE NAME | OLD | NEW | NET CHANGE
```

Example:
```
custom_module_data       | 22 | 22 | 0
custom_module_equipment  | 12 | 12 | 0
```
