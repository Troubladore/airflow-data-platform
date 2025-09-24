# Archived Documentation

This directory contains documentation from the previous architecture that described building a complete platform rather than enhancing Astronomer.

## 📁 Archived Files

- **getting-started-complex.md** - The old complex 6-component Ansible setup
- **TECHNICAL-ARCHITECTURE.md** - Architecture for the "build our own platform" approach
- **WHY-THIS-ARCHITECTURE.md** - Justification for complex approach
- **ECOSYSTEM-OVERVIEW.md** - Overview of the complex ecosystem

## 🔄 What Changed

**Old Vision**: Build a complete data platform from scratch
- Complex Ansible deployment with 6 components
- Custom certificate management with Traefik
- Layer 1 platform infrastructure
- Heavy emphasis on self-built solutions

**New Vision**: Thin enterprise enhancements for Astronomer
- Simple developer setup with `astro dev init`
- Focus on patterns and frameworks that add value
- Use Astronomer's infrastructure, don't replace it
- Emphasize simplicity and standard tooling

## 📚 Current Documentation

See the main [docs/](../) directory for up-to-date documentation that reflects our simplified, Astronomer-aligned architecture.

## 💡 Why Archived?

These documents are preserved for:
- **Historical reference** - Understanding the evolution
- **Migration help** - Teams moving from v1 to v2
- **Learning** - What we tried and why we simplified

But they do NOT reflect our current approach and should not be used for new implementations.

---

*"The best architecture is one that gets out of your way." - We learned this lesson and simplified accordingly.*
