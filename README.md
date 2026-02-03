![E2B Infra Preview Light](/readme-assets/infra-light.png#gh-light-mode-only)
![E2B Infra Preview Dark](/readme-assets/infra-dark.png#gh-dark-mode-only)

# E2B Infrastructure

[E2B](https://e2b.dev) is an open-source infrastructure for AI code interpreting. In our main repository [e2b-dev/e2b](https://github.com/e2b-dev/E2B) we are giving you SDKs and CLI to customize and manage environments and run your AI agents in the cloud.

This repository contains the infrastructure that powers the E2B platform.

## 🎨 Fragments Web UI

This repository now includes **Fragments**, an open-source web interface for interacting with E2B sandboxes. Fragments provides a user-friendly UI for executing code, building applications, and managing sandboxes visually.

**Features:**
- 🔸 Interactive code execution in Python, JavaScript, and more
- 🔸 Support for Next.js, Vue.js, Streamlit, and Gradio frameworks
- 🔸 Multiple LLM provider integrations (OpenAI, Anthropic, DeepSeek, etc.)
- 🔸 Real-time code streaming and visualization
- 🔸 Built-in code editor with syntax highlighting

**Quick Start:**
```bash
# Start E2B infrastructure first
cd infra/local-deploy
./scripts/start-all.sh

# Then start Fragments web UI
cd infra/fragments
./start-fragments.sh

# Access at http://localhost:3001
```

For detailed documentation, see [fragments/README_INTEGRATION.md](./fragments/README_INTEGRATION.md).

## Self-hosting

Read the [self-hosting guide](./self-host.md) to learn how to set up the infrastructure on your own. The infrastructure is deployed using Terraform.

Supported cloud providers:
- 🟢 GCP
- 🚧 AWS
- [ ] Azure
- [ ] General linux machine
