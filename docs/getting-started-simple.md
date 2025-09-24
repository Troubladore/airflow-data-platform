# Getting Started - Simple Setup

Get your first data pipeline running with Astronomer + our enterprise enhancements in 10 minutes.

## 🎯 What You'll Have When Done

- **Astronomer Airflow** running at http://localhost:8080
- **Registry cache** for offline development
- **Kerberos ticket sharing** (if needed for SQL Server)
- **SQLModel framework** available for data modeling
- **Runtime environments** for dependency isolation

## 📋 Prerequisites

Make sure you have these installed:

```bash
# Check what you have
docker --version     # Docker Desktop or Engine
astro version       # Astronomer CLI
python3 --version   # Python 3.8+
```

### Missing something?

**Docker**: Download [Docker Desktop](https://docker.com/products/docker-desktop)

**Astronomer CLI**:
```bash
curl -sSL install.astronomer.io | sudo bash
```

**Python**: Use your system package manager or [python.org](https://python.org)

## 🚀 Step 1: Clone and Start Platform Services

```bash
# 1. Clone the platform repository
git clone https://github.com/Troubladore/airflow-data-platform.git
cd airflow-data-platform

# 2. Start minimal platform services (registry cache + ticket sharing)
cd platform-bootstrap
make start

# You should see:
# ✓ Registry cache started at localhost:5000
# ✓ Ticket sharer started (if you have Kerberos tickets)
```

**What's happening?** We're starting two simple services:
- **Registry cache** - So you can work offline after first setup
- **Ticket sharer** - Copies your WSL2 Kerberos tickets to containers (if available)

## 🏗️ Step 2: Create Your First Project

```bash
# 3. Create an Astronomer project
cd ~/projects  # or wherever you keep projects
astro dev init my-first-project

# Follow the prompts - choose any template
# We'll enhance it with our patterns
```

## 📦 Step 3: Add Enterprise Patterns (Optional)

Add our SQLModel framework to get enterprise table patterns:

```bash
cd my-first-project

# Edit requirements.txt and add:
echo "sqlmodel-framework @ git+https://github.com/Troubladore/airflow-data-platform.git@main#subdirectory=sqlmodel-framework" >> requirements.txt
```

## 🎯 Step 4: Start Airflow

```bash
# Still in your project directory
astro dev start

# Wait for startup... (2-3 minutes first time)
# When ready, you'll see:
# Airflow Webserver: http://localhost:8080
# Username: admin, Password: admin
```

## ✅ Step 5: Verify Everything Works

Open http://localhost:8080 in your browser:
- Username: `admin`
- Password: `admin`

You should see the Airflow UI with example DAGs!

## 🎉 Success! What's Next?

### Create Your First Data Pipeline

Create `dags/my_first_dag.py`:

```python
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator

# Optional: Use our SQLModel patterns
try:
    from sqlmodel_framework import ReferenceTable, deploy_data_objects
    HAS_SQLMODEL = True
except ImportError:
    HAS_SQLMODEL = False

def hello_world():
    print("Hello from your enterprise data platform!")
    if HAS_SQLMODEL:
        print("SQLModel framework is available!")
    return "success"

# Define the DAG
dag = DAG(
    'my_first_enterprise_dag',
    description='My first pipeline with enterprise patterns',
    schedule_interval=timedelta(days=1),
    start_date=datetime(2024, 1, 1),
    catchup=False,
)

# Add a task
hello_task = PythonOperator(
    task_id='hello_world',
    python_callable=hello_world,
    dag=dag,
)
```

Refresh the Airflow UI and you'll see your DAG!

## 🔧 Development Workflow

```bash
# Daily development routine:

# Morning: Start platform services
cd airflow-data-platform/platform-bootstrap
make start

# Start your project
cd ~/projects/my-first-project
astro dev start

# ... develop your DAGs ...

# Evening: Stop everything
astro dev stop
cd ../../airflow-data-platform/platform-bootstrap
make stop
```

## 📚 What's Available Now

### SQLModel Framework
Create enterprise-ready data models:

```python
from sqlmodel_framework import ReferenceTable

class Customer(ReferenceTable):
    """Auto-includes created_at, updated_at, and audit triggers"""
    name: str
    email: str
    # Audit columns added automatically!
```

### Runtime Environments
Isolate dependencies between teams:

```python
from airflow.providers.docker.operators.docker import DockerOperator

# Team A can use pandas 1.5, Team B can use pandas 2.0
# No conflicts!
process_data = DockerOperator(
    task_id='process_with_team_dependencies',
    image='runtime-environments/python-transform:team-specific',
    # Your team's exact dependencies, isolated from others
)
```

## 🚨 Troubleshooting

### "astro: command not found"
Install the Astronomer CLI:
```bash
curl -sSL install.astronomer.io | sudo bash
```

### "docker: permission denied"
Make sure Docker Desktop is running, or add your user to the docker group:
```bash
sudo usermod -aG docker $USER
# Then log out and back in
```

### "Registry cache not working"
Check if it's running:
```bash
curl http://localhost:5000/v2/_catalog
# Should return: {"repositories":[]}
```

### "Can't connect to SQL Server"
Our Kerberos ticket sharing only works if:
1. You're on WSL2
2. You have a valid Kerberos ticket (`klist` shows it)
3. You're connecting to a server that accepts your domain credentials

**Need help with Kerberos?** See our complete [Kerberos Setup Guide for WSL2](kerberos-setup-wsl2.md) - it walks you through every step!

For local development without Kerberos, use SQLite or PostgreSQL instead.

## 🎯 Next Steps

1. **Learn the patterns**: [SQLModel Patterns](patterns/sqlmodel-patterns.md)
2. **See examples**: [airflow-data-platform-examples](https://github.com/Troubladore/airflow-data-platform-examples)
3. **Advanced setup**: [Platform Bootstrap Details](../platform-bootstrap/README.md)

---

**You now have a production-ready data platform! 🚀**

The beauty is that it's 95% standard Astronomer - you get all their benefits plus our enterprise patterns when you need them.
