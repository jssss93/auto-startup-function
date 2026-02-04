# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Azure Function App (Python 3.12) that automatically starts Azure VMs daily at 20:00 KST via a timer trigger. Supports multiple VMs configured through environment variables. Deployed via GitLab CI/CD with ZIP deployment.

## Common Commands

```bash
# Local development (requires Azure Functions Core Tools)
func start

# Run quick test against deployed function
./scripts/quick-test.sh

# Deploy with pre-built ZIP (CI mode)
./scripts/deploy.sh <function-app-name> <resource-group> deploy.zip

# Deploy from source (local mode, Azure builds remotely)
./scripts/deploy.sh <function-app-name> <resource-group>

# Build deployment ZIP manually (mimics CI build stage)
pip install -r requirements.txt -t build_output/
cp function_app.py host.json requirements.txt build_output/
cp -r start_vm build_output/
cd build_output && zip -r ../deploy.zip .
```

No unit test framework is configured. Testing is done via the health check endpoint (`GET /api/health`, anonymous) and the manual trigger endpoint (`POST /api/start-vms`, requires function key).

## Architecture

**Entry point:** `function_app.py` — Registers three Azure Function triggers on a single `FunctionApp` instance:

1. **Timer trigger** (`start_vm_timer_function`) — CRON `0 0 20 * * *`, calls `start_vm.main()`
2. **Health check** (`/api/health`) — Anonymous, returns runtime/environment status
3. **Manual trigger** (`/api/start-vms`) — Function-level auth, creates a mock `TimerRequest` and calls the same `start_vm.main()` path

**Core logic:** `start_vm/__init__.py` — All VM operations:
- `parse_vm_list()` reads `AZURE_VM_LIST` (JSON array, preferred) or falls back to `AZURE_VM_NAME` + `AZURE_RESOURCE_GROUP` (single VM, legacy)
- `get_azure_credential()` tries `ManagedIdentityCredential` first, falls back to `DefaultAzureCredential` for local dev
- `process_vm()` checks power state and starts only stopped/deallocated VMs
- VMs are processed sequentially; any failure raises an exception after all VMs are attempted

## Configuration

Environment variables (set in `local.settings.json` locally, Application Settings in Azure):
- `AZURE_SUBSCRIPTION_ID` — Required
- `AZURE_VM_LIST` — JSON array: `[{"name": "vm1", "resource_group": "rg1"}, ...]`
- `AZURE_VM_NAME` / `AZURE_RESOURCE_GROUP` — Legacy single-VM fallback

See `local.settings.json.example` for the full template.

## CI/CD Pipeline

GitLab CI (`.gitlab-ci.yml`) with two stages:
- **build** — Compiles Python, bundles dependencies into `deploy.zip` artifact (runs on main, develop, MRs)
- **deploy:production** — ZIP-deploys to Azure Function App using Managed Identity auth (main branch only)

## Key Dependencies

- `azure-functions` — Function App framework (v4 programming model)
- `azure-identity` — Azure authentication (Managed Identity, Service Principal)
- `azure-mgmt-compute` — Azure VM management operations
