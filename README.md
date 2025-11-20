# 🚀 PostgreSQL DB Restore — Smart Surgical Restore Script
### 🤙📖 What's the Vibe?

This script performs a **Surgical Restore** of your PostgreSQL data from a backup `.dump` file directly into a live database.

Unlike those boring scripts that blindly overwrite everything, this tool lets you:

- 🎯 Restore specific rows only (e.g., Customer ID 1441)
- 🔄 Restore entire tables (Full Replace Mode)
- 🛡️ Run everything inside a Global Atomic Transaction
- ❌ Never leave half-restored data behind
- ⚙️ Bypass FK constraints temporarily
- 🌪️ Stay safe, clean, fail-proof, and crash-proof

This is not a restore script…  
**It's a Postgres ninja tool.**

---

# 🛡️ Why It’s Awesome

## 1. All-or-Nothing (Atomic Transaction Magic)
- Whole operation runs in ONE transaction  
- ✔️ Success → COMMIT  
- ❌ Error → ROLLBACK  
- No half-restored data EVER

---

## 2. Built-In Safety Traps
Triggers when:
- You press Ctrl+C  
- Terminal crashes  
- Any command errors  
- Network drops  

Auto actions:
- 💥 Kills the running transaction  
- 🧹 Deletes temporary staging tables  
- 🛏️ Database stays clean  

---

## 3. Smart Collision Handling
- Auto-detects primary key of each table  
- Deletes conflicting rows before inserting  
- Prevents duplicate key errors  
- 100% safe and repeatable

---

## 4. Ninja Mode Features
- Bypass foreign keys:
  SET session_replication_role = 'replica';

- Force insert specific IDs  
- Restore partial or full tables  
- Clean, quiet logs (filters noisy Postgres messages)

---

# ⚙️ Setup

## 1. Database Configuration
DB_HOST="localhost"  
DB_PORT="5432"  
DB_NAME="terotam_local"  
DB_USER="postgres"  
DB_PASS="your_password"

## 2. Backup File
BACKUP_FILE="/path/to/your/backup.dump"

---

# 🎯 Define What to Restore (TARGETS)

### Syntax
TABLE_NAME : FILTER_COLUMN : ID_LIST  
or  
TABLE_NAME : FULL

### Example:
TARGETS=(

  "custom_module_data : customer_id : 1441"  
  "custom_module_equipment_map : cm_id : 50, 51, 52"
  "system_settings : FULL"
  
)

---

# 🧠 How the Script Works

## Phase 1 — Staging Zone
- Creates temporary staging table  
- Loads backup into staging  
- Validates content  

## Phase 2 — Mega Transaction
- Deletes old conflicting rows  
- Inserts staged data  
- Verifies row count  
- COMMIT or ROLLBACK  

## Phase 3 — Cleanup
- Drops staging tables  
- Displays summary scoreboard  

---

# 🧹 Troubleshooting

Error: row: unbound variable → Shell strict mode  
Error: duplicate key → ID conflict cleaned automatically  
Error: cannot truncate → Uses DELETE instead  
Error: set_config → Log noise removed  

---
