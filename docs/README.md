# Airflow Data Platform - Documentation

Welcome to the complete documentation for the Airflow Data Platform framework.

## 🚀 Getting Started

**New to the platform?** Start here:

- **[Getting Started Guide](getting-started.md)** - Complete setup guide for development and testing
- **[Platform Setup](getting-started.md)** - Prerequisites, installation, and validation

## 📚 Documentation Index

### **User Guides**
- **[Getting Started](getting-started.md)** - Environment setup and prerequisites
- **[Technical Reference](technical-reference.md)** - Framework APIs and architecture details

### **Architecture & Design**
- **[Technical Architecture](TECHNICAL-ARCHITECTURE.md)** - Framework internals and deployment patterns
- **[Why This Architecture](WHY-THIS-ARCHITECTURE.md)** - Design decisions and trade-offs
- **[Ecosystem Overview](ECOSYSTEM-OVERVIEW.md)** - Component relationships and integration

### **Security & Operations**
- **[Security Risk Acceptance](SECURITY-RISK-ACCEPTANCE.md)** - Security model and risk management

## 🎯 Quick Navigation by Use Case

### **Testing PR #6 (Layer 2 Data Processing)**
1. **Start here** → [Getting Started Guide](getting-started.md)
2. Follow the **🚀 Quick Setup** section
3. Use the **🧪 Testing & Development Workflow** for iterative testing
4. Reference **🚨 Troubleshooting** if you encounter issues

### **Platform Development**
1. **Architecture overview** → [Technical Architecture](TECHNICAL-ARCHITECTURE.md)
2. **Framework details** → [Technical Reference](technical-reference.md)
3. **Design rationale** → [Why This Architecture](WHY-THIS-ARCHITECTURE.md)

### **Production Deployment**
1. **Security model** → [Security Risk Acceptance](SECURITY-RISK-ACCEPTANCE.md)
2. **Component integration** → [Ecosystem Overview](ECOSYSTEM-OVERVIEW.md)
3. **Framework internals** → [Technical Architecture](TECHNICAL-ARCHITECTURE.md)

## ⚡ Quick Commands

Once you've completed the [Getting Started Guide](getting-started.md):

```bash
# Complete platform setup
ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml --ask-become-pass

# Validate everything is working
ansible-playbook -i ansible/inventory/local-dev.ini ansible/validate-all.yml --ask-become-pass

# Clean teardown for testing (keeps certificates)
./scripts/teardown.sh  # Choose option 1

# Test endpoints manually
curl -k https://traefik.localhost
curl -k https://registry.localhost/v2/_catalog
```

## 🏗️ Repository Structure

```
airflow-data-platform/
├── docs/                           # Documentation (you are here)
│   ├── getting-started.md         # Platform setup guide
│   ├── technical-reference.md     # Framework APIs and architecture
│   └── *.md                       # Architecture and design docs
├── data-platform/                 # SQLModel framework
│   └── sqlmodel-workspace/
│       └── sqlmodel-framework/    # Core platform library
├── layer1-platform/               # Docker infrastructure
├── layer2-datakits/               # Generic data processing patterns
├── layer3-warehouses/             # Data warehouse patterns
├── ansible/                       # Automation playbooks
└── scripts/                       # Development utilities
```

## 📖 Documentation Standards

This documentation follows [data-eng-template](https://github.com/Troubladore/data-eng-template) standards:
- **Lowercase with dashes** for file names (`getting-started.md`)
- **Clear hierarchical structure** with main entry point
- **Use case oriented navigation** for quick access
- **Complete teardown/rebuild instructions** for iterative development

## 🤝 Contributing to Documentation

When updating documentation:
1. **Keep getting-started.md current** - This is the primary entry point
2. **Update quick reference commands** if workflows change
3. **Test documentation flows** before committing
4. **Follow naming conventions** (lowercase-with-dashes)

---

**Questions or issues?** Create an issue or check the troubleshooting sections in the guides above.
