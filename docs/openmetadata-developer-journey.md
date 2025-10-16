# OpenMetadata Developer Journey

**Purpose:** This document describes the actual developer experience of adding OpenMetadata to an existing Airflow Data Platform.

**Audience:** Team members, stakeholders, future developers

**Status:** Vision Document - Defines the Target Experience

---

## The Story: Sarah's Discovery of Metadata Cataloging

### Where Sarah Starts (Completed Kerberos Setup)

Sarah, a data engineer on the team, has just finished setting up the Airflow Data Platform with Kerberos authentication:

```bash
# What Sarah has accomplished
cd ~/repos/airflow-data-platform/platform-bootstrap
./dev-tools/setup-kerberos.sh    # ✅ Completed all 11 steps
make platform-status              # ✅ Kerberos sidecar running
./diagnostics/test-sql-direct.sh sqlserver01.company.com TestDB  # ✅ Works!
```

**Sarah's current capabilities:**
- ✅ Kerberos sidecar is sharing tickets
- ✅ SQL Server authentication works without passwords
- ✅ Can build Airflow DAGs that access corporate databases

**But Sarah faces daily challenges:**
- "How do I discover what tables exist in pagila without opening pgAdmin?"
- "What's the schema of that customer table in SQL Server?"
- "Where does the data flow in our ETL pipelines?"
- "Which tables have PII data?"

Every time Sarah needs schema information, she either:
- Opens database tools (pgAdmin, SSMS)
- Asks teammates on Slack
- Digs through old SQL scripts

**This is where OpenMetadata changes everything.**

---

## Chapter 1: Seamless Platform Enhancement

### Sarah Pulls Latest Platform Changes

```bash
cd ~/repos/airflow-data-platform
git pull origin main

cd platform-bootstrap
ls -la
```

**Sarah notices new files:**
```
platform-bootstrap/
├── docker-compose.openmetadata.yml    ← NEW!
├── postgres/
│   └── init-databases.sh              ← NEW!
├── .env.example                        (updated)
└── Makefile                            (updated)
```

**Sarah's thought:**
> "Looks like the platform team added OpenMetadata. The commit message says it's a metadata catalog. Let me see what happens when I start the platform..."

### Same Command, Enhanced Platform

Sarah runs **the exact same command** she always uses:

```bash
make platform-start
```

**What Sarah sees:**
```
Starting platform services...
  ✓ Creating network: platform_network (already exists)
  ✓ Creating volume: platform_kerberos_cache (already exists)
  ✓ Creating volume: platform_postgres_data (new!)

  ✓ Starting developer-kerberos-service... done
  ✓ Starting platform-postgres... done
  ✓ Starting openmetadata-elasticsearch... done
  ✓ Starting openmetadata-server... done

Platform services starting...

Kerberos Sidecar:
  Status: docker ps | grep kerberos-platform-service

OpenMetadata:
  UI:    http://localhost:8585
  Login: admin@open-metadata.org / admin

Note: First startup may take 2-3 minutes...
```

**Sarah's reaction:**
> "Oh! The platform now includes OpenMetadata. And it started automatically - no special installation step. Nice!"

**Key UX Win:** Sarah didn't run `make openmetadata-start` or follow special instructions. The platform just got better with her normal workflow.

---

## Chapter 2: Discovering the Empty Catalog

### Sarah Explores the New UI

Curious, Sarah opens her browser: **http://localhost:8585**

**Login screen appears:**
- Email: `admin@open-metadata.org`
- Password: `admin`

Sarah logs in and sees:

**OpenMetadata Dashboard (Empty State):**
```
╔═══════════════════════════════════════════╗
║  Welcome to OpenMetadata                  ║
║                                           ║
║  Your data catalog is empty               ║
║                                           ║
║  Get started:                             ║
║  • Add database services                  ║
║  • Ingest metadata                        ║
║  • Explore your data                      ║
╚═══════════════════════════════════════════╝
```

**Sarah clicks around:**
- "Explore" → "No tables found"
- "Services" → "No services configured"
- "Settings" → Various configuration options

**Sarah's thought:**
> "Okay, so this is a metadata catalog. But it's empty. I could click through the UI to configure connections, but our team does 'everything as code'... There must be a better way."

---

## Chapter 3: The "Aha!" Moment - Everything as Code

### Sarah Remembers: Everything as Code

Sarah checks the examples repository:

```bash
cd ~/repos/airflow-data-platform-examples
ls -la
```

**Sarah discovers a new directory:**
```
examples/
├── pagila-implementations/
│   ├── pagila-sqlmodel-basic/
│   └── pagila-sqlmodel-advanced/
└── openmetadata-ingestion/           ← NEW EXAMPLE!
    ├── README.md
    ├── dags/
    │   ├── ingest_pagila_metadata.py
    │   └── ingest_sqlserver_metadata.py
    ├── requirements.txt
    ├── Dockerfile
    └── docker-compose.override.yml
```

**Sarah opens** `examples/openmetadata-ingestion/README.md`:

```markdown
# OpenMetadata Ingestion DAGs

Programmatic metadata ingestion using Astronomer Airflow.

## Philosophy: Everything as Code

Instead of manually configuring connections in a UI:
✅ Define metadata ingestion as Airflow DAGs
✅ Version control your metadata configuration
✅ Code review metadata changes
✅ Repeatable, testable, documented

## What This Example Does

Two DAGs demonstrate metadata ingestion patterns:

1. **ingest_pagila_metadata.py**
   - Catalogs pagila PostgreSQL schema
   - Simple example (no authentication complexity)
   - Shows basic ingestion pattern

2. **ingest_sqlserver_metadata.py**
   - Catalogs corporate SQL Server databases
   - Uses Kerberos authentication (no passwords!)
   - Shows production-ready pattern

## Quick Start

```bash
cd examples/openmetadata-ingestion
astro dev start
# Open Airflow: http://localhost:8080
# Trigger: openmetadata_ingest_pagila
# Check OpenMetadata: http://localhost:8585
```

## What You'll Learn

- How to configure metadata sources as code
- How to use the OpenMetadata Python SDK
- How to leverage existing Kerberos authentication
- How to schedule metadata ingestion
```

**Sarah's reaction:**
> "Perfect! This matches how we do everything else. DAGs, not UI clicking. Let me try the pagila example first."

---

## Chapter 4: Running the First Ingestion DAG

### Sarah Starts the Example Project

```bash
cd examples/openmetadata-ingestion
astro dev start
```

**Astronomer CLI output:**
```
Building image...
  ✓ Adding openmetadata-ingestion Python SDK
  ✓ Configuring network: platform_network
  ✓ Mounting Kerberos volume (for SQL Server later!)

Starting Airflow...
  ✓ Webserver: http://localhost:8080
  ✓ Postgres (metastore): Running
  ✓ Scheduler: Running

Airflow is ready!
```

### Sarah Opens Airflow UI

**http://localhost:8080**

**Sarah sees two DAGs:**

| DAG ID | Status | Schedule | Description |
|--------|--------|----------|-------------|
| `openmetadata_ingest_pagila` | ⚪ Ready | None | Ingest pagila PostgreSQL metadata |
| `openmetadata_ingest_sqlserver` | ⚪ Ready | None | Ingest SQL Server metadata (Kerberos) |

**Sarah clicks:** `openmetadata_ingest_pagila` → **Graph View**

**She sees the DAG structure:**
```
[ingest_pagila_schema]
   ↓
 (Finish)
```

Simple! One task.

**Sarah clicks:** Trigger DAG ▶️

### The Magic Moment - Watching It Work

**Task logs stream in real-time:**
```
[2025-01-16 10:30:00] *** Starting task: ingest_pagila_schema
[2025-01-16 10:30:00] Executing Python function: ingest_pagila_metadata
[2025-01-16 10:30:01]
[2025-01-16 10:30:01] OpenMetadata Ingestion Workflow
[2025-01-16 10:30:01] ================================
[2025-01-16 10:30:01] Source: PostgreSQL (pagila-postgres:5432)
[2025-01-16 10:30:01] Target: OpenMetadata (http://openmetadata-server:8585/api)
[2025-01-16 10:30:01]
[2025-01-16 10:30:02] [INFO] Connecting to PostgreSQL...
[2025-01-16 10:30:02] [INFO] ✓ Connection successful
[2025-01-16 10:30:03] [INFO] Extracting schema: public
[2025-01-16 10:30:03] [INFO] Found tables:
[2025-01-16 10:30:03] [INFO]   - actor (4 columns)
[2025-01-16 10:30:03] [INFO]   - address (9 columns)
[2025-01-16 10:30:03] [INFO]   - category (3 columns)
[2025-01-16 10:30:03] [INFO]   - city (3 columns)
[2025-01-16 10:30:03] [INFO]   - customer (9 columns)
[2025-01-16 10:30:03] [INFO]   - film (13 columns)
[2025-01-16 10:30:03] [INFO]   ... (15 tables total)
[2025-01-16 10:30:04] [INFO]
[2025-01-16 10:30:04] [INFO] Analyzing relationships...
[2025-01-16 10:30:04] [INFO]   ✓ film_actor.actor_id → actor.actor_id
[2025-01-16 10:30:04] [INFO]   ✓ film_actor.film_id → film.film_id
[2025-01-16 10:30:04] [INFO]   ... (23 relationships found)
[2025-01-16 10:30:05] [INFO]
[2025-01-16 10:30:05] [INFO] Sending metadata to OpenMetadata API...
[2025-01-16 10:30:05] [INFO]   ✓ Created service: pagila-local
[2025-01-16 10:30:05] [INFO]   ✓ Ingested database: pagila
[2025-01-16 10:30:05] [INFO]   ✓ Ingested schema: public
[2025-01-16 10:30:06] [INFO]   ✓ Ingested 15 tables
[2025-01-16 10:30:06] [INFO]   ✓ Ingested 156 columns
[2025-01-16 10:30:06] [INFO]   ✓ Ingested 23 relationships
[2025-01-16 10:30:06] [INFO]
[2025-01-16 10:30:06] [SUCCESS] ✓ Metadata ingestion completed successfully!
[2025-01-16 10:30:06] *** Task completed successfully
```

**DAG status:** ✅ Success (green)

**Sarah's reaction:**
> "It worked! In just 6 seconds, it cataloged the entire pagila database. Let me check OpenMetadata..."

---

## Chapter 5: Discovering the Cataloged Metadata

### Sarah Switches to OpenMetadata UI

**http://localhost:8585**

**The dashboard is no longer empty!**

```
╔═══════════════════════════════════════════╗
║  Data Assets                              ║
║                                           ║
║  📊 Tables: 15                            ║
║  🗄️  Databases: 1 (pagila)                ║
║  🔗 Services: 1 (pagila-local)            ║
╚═══════════════════════════════════════════╝
```

**Sarah clicks:** Explore → Tables

**She sees a searchable list:**

| Table | Database | Schema | Columns | Tags |
|-------|----------|--------|---------|------|
| actor | pagila | public | 4 | |
| address | pagila | public | 9 | |
| category | pagila | public | 3 | |
| city | pagila | public | 3 | |
| country | pagila | public | 3 | |
| customer | pagila | public | 9 | |
| film | pagila | public | 13 | |
| ... | ... | ... | ... | |

**Sarah types in search:** "film"

**Instant results:**
- `pagila.public.film`
- `pagila.public.film_actor`
- `pagila.public.film_category`

### Sarah Explores a Table in Detail

**Sarah clicks:** `film` table

**She sees comprehensive metadata:**

#### Schema Tab
```
Columns (13):
┌─────────────────┬──────────────┬──────────┬─────────────┐
│ Name            │ Type         │ Nullable │ Description │
├─────────────────┼──────────────┼──────────┼─────────────┤
│ film_id         │ INTEGER      │ No       │ Primary key │
│ title           │ VARCHAR(255) │ No       │             │
│ description     │ TEXT         │ Yes      │             │
│ release_year    │ INTEGER      │ Yes      │             │
│ language_id     │ SMALLINT     │ No       │ FK: language│
│ rental_duration │ SMALLINT     │ No       │             │
│ rental_rate     │ NUMERIC(4,2) │ No       │             │
│ length          │ SMALLINT     │ Yes      │             │
│ replacement_cost│ NUMERIC(5,2) │ No       │             │
│ rating          │ VARCHAR(10)  │ Yes      │             │
│ special_features│ TEXT[]       │ Yes      │             │
│ last_update     │ TIMESTAMP    │ No       │             │
└─────────────────┴──────────────┴──────────┴─────────────┘
```

#### Relationships Tab
```
Foreign Keys (Outgoing):
  → language.language_id

Referenced By (Incoming):
  ← film_actor.film_id
  ← film_category.film_id
  ← inventory.film_id
```

#### Sample Data Tab
```
First 5 rows:

film_id | title                      | release_year | rating
--------|----------------------------|--------------|-------
1       | Academy Dinosaur           | 2006         | PG
2       | Ace Goldfinger            | 2006         | G
3       | Adaptation Holes          | 2006         | NC-17
4       | Affair Prejudice          | 2006         | G
5       | African Egg               | 2006         | G
```

**Sarah's reaction:**
> "THIS IS AMAZING! I can see everything about this table:
> - Column names and types
> - Which columns are nullable
> - Foreign key relationships (both directions!)
> - Sample data
>
> No more opening pgAdmin or asking teammates. Everything is here!"

---

## Chapter 6: The Advanced Move - SQL Server with Kerberos

### Sarah Tries Corporate Database Ingestion

Impressed by pagila, Sarah wants to catalog the corporate SQL Server database.

**Back in Airflow UI:**
- Sarah clicks: `openmetadata_ingest_sqlserver`
- Clicks: Trigger DAG ▶️

### Watching Kerberos Authentication in Action

**Task logs:**
```
[2025-01-16 10:35:00] *** Starting task: ingest_sqlserver_schema
[2025-01-16 10:35:00]
[2025-01-16 10:35:00] OpenMetadata Ingestion Workflow
[2025-01-16 10:35:00] ================================
[2025-01-16 10:35:00] Source: SQL Server (sqlserver01.company.com:1433)
[2025-01-16 10:35:00] Target: OpenMetadata (http://openmetadata-server:8585/api)
[2025-01-16 10:35:00] Authentication: Kerberos (Integrated Windows Auth)
[2025-01-16 10:35:01]
[2025-01-16 10:35:01] [INFO] Checking Kerberos ticket...
[2025-01-16 10:35:01] [INFO] ✓ Found ticket: /krb5/cache/krb5cc
[2025-01-16 10:35:01] [INFO] ✓ Principal: sarah.smith@COMPANY.COM
[2025-01-16 10:35:01] [INFO] ✓ Valid until: 2025-01-16 18:30:00
[2025-01-16 10:35:02] [INFO]
[2025-01-16 10:35:02] [INFO] Connecting to SQL Server...
[2025-01-16 10:35:02] [INFO] ✓ Connection string: TrustedConnection=yes (no password!)
[2025-01-16 10:35:03] [INFO] ✓ Kerberos authentication successful!
[2025-01-16 10:35:03] [INFO] ✓ Connected as: COMPANY\sarah.smith
[2025-01-16 10:35:04] [INFO]
[2025-01-16 10:35:04] [INFO] Extracting schema: dbo
[2025-01-16 10:35:05] [INFO] Found tables:
[2025-01-16 10:35:05] [INFO]   - Customers (12 columns)
[2025-01-16 10:35:05] [INFO]   - Orders (8 columns)
[2025-01-16 10:35:05] [INFO]   - Products (10 columns)
[2025-01-16 10:35:05] [INFO]   ... (47 tables total)
[2025-01-16 10:35:06] [INFO]
[2025-01-16 10:35:10] [INFO] Sending metadata to OpenMetadata API...
[2025-01-16 10:35:10] [INFO]   ✓ Created service: corporate-sql-server
[2025-01-16 10:35:10] [INFO]   ✓ Ingested database: TestDB
[2025-01-16 10:35:10] [INFO]   ✓ Ingested schema: dbo
[2025-01-16 10:35:11] [INFO]   ✓ Ingested 47 tables
[2025-01-16 10:35:11] [INFO]   ✓ Ingested 428 columns
[2025-01-16 10:35:11] [INFO]   ✓ Ingested 93 relationships
[2025-01-16 10:35:11] [INFO]
[2025-01-16 10:35:11] [SUCCESS] ✓ Metadata ingestion completed successfully!
[2025-01-16 10:35:11] *** Task completed successfully
```

**Sarah's reaction:**
> "Whoa! It used my Kerberos ticket automatically. No password in the code. The security team will love this!"

### Sarah Discovers Cross-Database Search

**Back in OpenMetadata UI:**

**Dashboard now shows:**
```
╔═══════════════════════════════════════════╗
║  Data Assets                              ║
║                                           ║
║  📊 Tables: 62 (15 + 47)                  ║
║  🗄️  Databases: 2                         ║
║     • pagila (PostgreSQL)                 ║
║     • TestDB (SQL Server)                 ║
║  🔗 Services: 2                           ║
╚═══════════════════════════════════════════╝
```

**Sarah searches:** "customer"

**Results from BOTH databases:**

| Table | Database | Service | Type | Columns |
|-------|----------|---------|------|---------|
| customer | pagila | pagila-local | PostgreSQL | 9 |
| Customers | TestDB | corporate-sql-server | SQL Server | 12 |

**Sarah clicks between them:**
- `pagila.public.customer` - DVD rental customers (test data)
- `TestDB.dbo.Customers` - Corporate CRM customers (real data!)

**Sarah's reaction:**
> "I can search across ALL our databases from one place! PostgreSQL, SQL Server, doesn't matter. It's all cataloged. This is going to save me SO much time."

---

## Chapter 7: Sarah Becomes the Advocate

### Sarah Shows Her Team

**Next team standup:**

**Sarah:** "Hey team, have you noticed OpenMetadata is now running?"

**Alex (new team member):** "I saw that in `make platform-start` output. What is it?"

**Sarah:** "It's our data catalog! Instead of asking 'what tables exist' or 'what's the schema', you can just search. Watch this..."

**[Sarah screenshares OpenMetadata UI]**

**Sarah searches:** "order"

**Results:**
- `TestDB.dbo.Orders` (SQL Server)
- `TestDB.dbo.OrderDetails` (SQL Server)
- `pagila.public.rental` (PostgreSQL - similar concept)

**Alex:** "Whoa! That's awesome. How did you set this up?"

**Sarah:** "I didn't really 'set it up'. The platform team added it. I just ran two Airflow DAGs to ingest metadata from our databases. Here, let me show you the code..."

**[Sarah opens `ingest_pagila_metadata.py`]**

**Sarah:** "See? It's just Python configuration. You define the source database, target OpenMetadata, and run it as a DAG. Everything as code."

**Alex:** "That's so much better than my last company where we had a 200-row Excel spreadsheet of table definitions that was always out of date!"

**Team Lead:** "Sarah, can you add ingestion for our other SQL Servers?"

**Sarah:** "Sure! I'll just copy the SQL Server DAG, change the database name, and commit it. Want to review the PR?"

**Team Lead:** "Yes! And let's schedule these ingestion DAGs to run weekly so the catalog stays fresh."

### Sarah Updates the Documentation

**Sarah creates:** `docs/team/using-openmetadata.md`

```markdown
# Using OpenMetadata for Data Discovery

## Quick Start

1. Access: http://localhost:8585
2. Login: admin@open-metadata.org / admin
3. Search for tables, columns, databases
4. Click on tables to see schemas and relationships

## Adding New Data Sources

To catalog a new database:

1. Copy an existing ingestion DAG:
   - `examples/openmetadata-ingestion/dags/ingest_pagila_metadata.py`
   - Or `ingest_sqlserver_metadata.py` for SQL Server

2. Update the configuration:
   - Change `serviceName`
   - Update connection details (host, database)
   - Adjust schema/table filters if needed

3. Test the DAG:
   - Run in Airflow UI
   - Verify metadata appears in OpenMetadata

4. Schedule it:
   - Set `schedule_interval='@weekly'` in DAG definition
   - Commit and push

## Pro Tips

- **Search is powerful:** Type partial table names, column names, or descriptions
- **Add descriptions:** Click "Edit" on tables to add business context
- **Use tags:** Tag tables with "PII", "Finance", "Deprecated", etc.
- **Share links:** Copy table URLs to share specific schemas with teammates
```

**Sarah commits this to the repo.**

**The team starts using OpenMetadata daily.**

---

## Chapter 8: One Month Later - The Impact

### New Developer: Jamie

Jamie joins the team. On day one:

```bash
# Jamie runs the setup wizard
cd platform-bootstrap
./dev-tools/setup-kerberos.sh

# Platform starts (includes OpenMetadata automatically)
make platform-start
```

**Jamie discovers OpenMetadata naturally.**

### Jamie's Experience

**Day 1:**
- "What's this OpenMetadata at localhost:8585?"
- Opens it, sees catalog
- Searches for "customer", finds tables
- "Oh! This is useful!"

**Day 3:**
- Writing first DAG, needs to query `Orders` table
- Searches OpenMetadata: "orders"
- Finds `TestDB.dbo.Orders`
- Clicks to see schema: "Perfect, it has `CustomerID` and `OrderDate`"
- Writes query without asking teammates

**Day 5:**
- "I need to ingest data from the `Products` database"
- Asks Sarah: "Is that database cataloged?"
- Sarah: "Check OpenMetadata. If not, add an ingestion DAG!"
- Jamie copies existing DAG, updates config, commits
- New database cataloged in 15 minutes

**Day 10:**
- Jamie adds descriptions to tables they worked with
- Other team members thank them for the documentation
- Jamie feels like a contributing team member

### Team Metrics (Informal Observations)

**Before OpenMetadata:**
- "What tables exist?" questions: ~10/day in Slack
- Time to find schema info: 5-10 minutes (context switching)
- Onboarding: 2 weeks to learn where data lives

**After OpenMetadata:**
- "What tables exist?" questions: ~1/day (now unusual)
- Time to find schema info: 30 seconds (self-service)
- Onboarding: 3 days to get productive with catalog

**Team Lead's Observation:**
> "OpenMetadata didn't just save time. It changed how we work. New people can be productive on day one. Tribal knowledge is becoming shared knowledge. People document tables because the catalog makes it easy. This is what 'data culture' looks like."

---

## The Experience Principles (What We Built)

### 1. **Seamless Integration**

**❌ Bad Experience:**
- "Now install OpenMetadata separately"
- "Follow these 20 steps"
- "Configure the database manually"

**✅ Good Experience (What We Built):**
- `make platform-start` includes OpenMetadata
- No separate installation step
- Developers discover it naturally
- "The platform just got better"

### 2. **Everything as Code**

**❌ Bad Experience:**
- "Click through UI to add database"
- "Configure connection in web form"
- "No version control"

**✅ Good Experience (What We Built):**
- Ingestion defined as Airflow DAGs
- Configuration in Python (version controlled)
- Code review for changes
- Repeatable and testable

### 3. **Progressive Disclosure**

**❌ Bad Experience:**
- "Here are all 47 features"
- "Read this 100-page manual"
- "Configure everything upfront"

**✅ Good Experience (What We Built):**
- Start simple: pagila (no auth complexity)
- Add complexity: SQL Server (Kerberos!)
- Advanced: Lineage (when ready)
- Learn by doing, incrementally

### 4. **Immediate Value**

**❌ Bad Experience:**
- "Set up for 3 days before seeing value"
- "Manually catalog 100 tables first"
- "Value comes 'eventually'"

**✅ Good Experience (What We Built):**
- Run one DAG → see results immediately
- 6 seconds to catalog pagila
- "Wow, this works!" moment
- Build on early success

### 5. **Team-Oriented**

**❌ Bad Experience:**
- "This is Sarah's tool"
- "Only experts can use it"
- "Knowledge stays siloed"

**✅ Good Experience (What We Built):**
- Shared catalog benefits everyone
- Self-service discovery (no experts needed)
- Anyone can add descriptions
- Knowledge democratized

---

## Key Moments in the Journey

### ⭐ The "It Just Started" Moment
**Sarah runs `make platform-start` and OpenMetadata is just... there.**
- No installation step
- No configuration file to edit
- Platform got better with normal workflow

### ⭐ The "It's Just Python" Moment
**Sarah opens an ingestion DAG and sees familiar Python configuration.**
- Not a proprietary DSL
- Not XML or weird syntax
- Just Python dictionaries and functions
- "I can understand and modify this"

### ⭐ The "6 Seconds" Moment
**Sarah triggers pagila ingestion DAG and watches logs stream.**
- Real-time feedback
- Clear progress messages
- Completes in 6 seconds
- "Whoa, that was fast!"

### ⭐ The "Search Works" Moment
**Sarah types "customer" and sees results from multiple databases.**
- Instant results
- Cross-database search
- Click → see full schema
- "This changes everything"

### ⭐ The "Kerberos Just Works" Moment
**Sarah triggers SQL Server DAG and sees "no password!" in logs.**
- Automatic Kerberos authentication
- No credentials in code
- Security team approved pattern
- "This is how it should be"

### ⭐ The "New Person Gets It" Moment
**Alex asks "What's OpenMetadata?" and Sarah shows them in 2 minutes.**
- Discoverable without documentation
- Intuitive search
- Immediate utility
- "Can I add a database?"

---

## Success Criteria (What "Done" Looks Like)

### For Individual Developers

✅ **Sarah can:**
- Start platform with `make platform-start` (OpenMetadata included)
- Discover catalog without reading docs
- Run ingestion DAG and see results
- Search for tables across all databases
- Find schema details in seconds (not minutes)
- Copy DAG patterns to add new databases

### For New Team Members

✅ **Jamie can:**
- Complete setup wizard (OpenMetadata starts automatically)
- Discover catalog on day 1
- Use search to find tables
- Read schema info without asking teammates
- Feel productive immediately
- Add descriptions to tables (contribute back)

### For the Team

✅ **The team experiences:**
- Fewer "where is X?" questions in Slack
- Faster onboarding (days, not weeks)
- Shared knowledge (not tribal)
- Self-service discovery (no bottlenecks)
- Version-controlled metadata config
- Growing catalog over time (not static)

### For the Platform

✅ **The platform provides:**
- Always-on metadata catalog
- Programmatic ingestion (everything as code)
- Kerberos integration (secure by default)
- Cross-database search
- Extensible patterns (easy to add sources)
- Production-ready architecture (OLTP/OLAP separation)

---

## Conclusion: This is the Journey

**From Sarah's first `git pull` to Jamie's first day, this is the experience we're building:**

1. **Seamless** - Platform enhancement, not separate installation
2. **Natural** - DAGs for ingestion (matches team culture)
3. **Progressive** - Learn by doing, build on success
4. **Immediate** - Value in minutes, not days
5. **Team-Oriented** - Shared catalog, shared knowledge

**The goal isn't "install OpenMetadata."**

**The goal is "data discovery becomes effortless."**

**This is how we get there.**

---

**Status:** Vision Document - Defines Target Experience
**Next Step:** Build the platform that delivers this journey
**Review:** Share with team to validate this is the experience we want

---

## Appendix: Key Commands Reference

```bash
# For Sarah (existing platform user)
cd ~/repos/airflow-data-platform
git pull origin main
cd platform-bootstrap
make platform-start                           # OpenMetadata included!

# For Jamie (new team member)
cd platform-bootstrap
./dev-tools/setup-kerberos.sh                # Setup wizard
make platform-start                           # Everything starts

# Running ingestion DAGs
cd examples/openmetadata-ingestion
astro dev start                               # Start Airflow
# Open http://localhost:8080
# Trigger DAG: openmetadata_ingest_pagila

# Viewing metadata
# Open http://localhost:8585
# Login: admin@open-metadata.org / admin
# Search: <any table name>

# Adding new data source
# Copy: examples/openmetadata-ingestion/dags/ingest_pagila_metadata.py
# Edit configuration
# Commit to git
# Run in Airflow
```

---

**Remember:** This document captures the **experience**, not just the **technology**. When building features, ask: "Does this match Sarah's journey?"
