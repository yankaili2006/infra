# Fragments Web UI - E2B Integration

## Overview

This directory contains the **Fragments** web application, an open-source AI code execution and visualization interface similar to Anthropic's Claude Artifacts. It has been integrated with the local E2B infrastructure to provide a user-friendly web interface for creating and managing E2B sandboxes.

## What is Fragments?

Fragments is a Next.js-based web application that allows you to:

- 🔸 Execute Python code securely in E2B sandboxes
- 🔸 Build and preview Next.js, Vue.js applications
- 🔸 Create Streamlit and Gradio apps interactively
- 🔸 Use multiple LLM providers (OpenAI, Anthropic, DeepSeek, etc.)
- 🔸 Stream execution results in real-time
- 🔸 Install npm/pip packages on-the-fly

## Integration Architecture

```
┌─────────────────────────────────────────┐
│   User Browser (localhost:3001)         │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│   Fragments Next.js App (Port 3001)     │
│   - UI Components                       │
│   - LLM Integration                     │
│   - Code Editor                         │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│   E2B API (localhost:3000)              │
│   - Sandbox Management                  │
│   - Template Registry                   │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│   E2B Orchestrator (via Nomad)          │
│   - Firecracker VM Management           │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│   Firecracker MicroVMs                  │
│   - Isolated Code Execution             │
└─────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

1. **E2B Infrastructure Running**:
   ```bash
   cd /home/primihub/pcloud/infra/local-deploy
   ./scripts/start-all.sh
   ```

2. **Node.js and npm** installed (v18 or later)

### Starting Fragments

**Option 1: Using the startup script (Recommended)**

```bash
cd /home/primihub/pcloud/infra/fragments
./start-fragments.sh
```

**Option 2: Manual start**

```bash
cd /home/primihub/pcloud/infra/fragments

# Install dependencies (first time only)
npm install

# Start development server
npm run dev
```

### Accessing the Interface

Open your browser to:
- **Local**: http://localhost:3001
- **Network**: http://192.168.99.5:3001 (or your machine's IP)

**Note**: Port 3001 is used because port 3000 is occupied by the E2B API.

## Configuration

### Environment Variables

Configuration is stored in `.env.local`:

```bash
# E2B API Configuration
E2B_API_KEY=e2b_53ae1fed82754c17ad8077fbc8bcdd90
E2B_BASE_URL=http://localhost:3000
E2B_API_URL=http://localhost:3000

# LLM Provider (Default: DeepSeek)
DEEPSEEK_API_KEY=sk-a1e8d93344c242a7af35aba3b8f851d2

# Optional: OpenAI
# OPENAI_API_KEY=your-key-here

# Optional: Anthropic
# ANTHROPIC_API_KEY=your-key-here

# Site Configuration
NEXT_PUBLIC_SITE_URL=http://localhost:3001
```

### Supported LLM Providers

Fragments can work with multiple LLM providers:

1. **DeepSeek** (Default) - Configured
2. **OpenAI** - Add OPENAI_API_KEY
3. **Anthropic** - Add ANTHROPIC_API_KEY
4. **Google AI** - Add GOOGLE_AI_API_KEY
5. **Groq** - Add GROQ_API_KEY
6. **Mistral** - Add MISTRAL_API_KEY
7. **Ollama** - For local models

### Supported Sandbox Templates

Fragments works with various E2B templates:

- **Python Interpreter** - Execute Python code
- **Next.js** - Build React applications
- **Vue.js** - Build Vue applications
- **Streamlit** - Create data apps
- **Gradio** - Build ML interfaces

## Usage Examples

### 1. Python Code Execution

```python
import matplotlib.pyplot as plt
import numpy as np

x = np.linspace(0, 10, 100)
y = np.sin(x)

plt.plot(x, y)
plt.title('Sine Wave')
plt.show()
```

### 2. Next.js Component

```jsx
export default function Hello() {
  return <h1>Hello from E2B!</h1>
}
```

### 3. Streamlit App

```python
import streamlit as st

st.title('My First Streamlit App')
name = st.text_input('Enter your name')
if name:
    st.write(f'Hello, {name}!')
```

## Customization

### Adding Custom Templates

1. **Create Template in E2B**:
   ```bash
   cd /home/primihub/pcloud/infra/sandbox-templates/my-template
   e2b template init
   # Edit e2b.Dockerfile
   e2b template build --name my-template
   ```

2. **Register in Fragments**:
   Edit `lib/templates.json`:
   ```json
   {
     "my-template": {
       "name": "My Custom Template",
       "lib": ["package1", "package2"],
       "file": "main.py",
       "instructions": "Custom template for...",
       "port": 8000
     }
   }
   ```

### Adding Custom LLM Models

Edit `lib/models.ts`:

```typescript
{
  "id": "my-model",
  "name": "My Model",
  "provider": "My Provider",
  "providerId": "my-provider"
}
```

## Troubleshooting

### Issue: Port 3000 Already in Use

**Solution**: This is expected. Fragments automatically uses port 3001 since E2B API uses port 3000.

### Issue: E2B API Not Found

**Error**: `Failed to connect to E2B API`

**Solution**:
```bash
# Check E2B API status
curl http://localhost:3000/health

# If not running, start E2B infrastructure
cd /home/primihub/pcloud/infra/local-deploy
./scripts/start-all.sh
```

### Issue: Sandbox Creation Fails

**Error**: `Failed to create sandbox`

**Solution**:
1. Check orchestrator is running:
   ```bash
   nomad job status orchestrator
   ```

2. Check available templates:
   ```bash
   curl http://localhost:3000/templates
   ```

3. Verify template exists in E2B:
   ```bash
   # List templates in database
   docker exec local-dev-postgres-1 psql -U postgres -d postgres -c "SELECT id FROM envs;"
   ```

### Issue: Dependencies Installation Fails

**Error**: `npm install` fails

**Solution**:
```bash
# Clear npm cache
npm cache clean --force

# Delete node_modules and reinstall
rm -rf node_modules package-lock.json
npm install
```

## Development

### Project Structure

```
fragments/
├── app/              # Next.js app directory
├── components/       # React components
├── lib/             # Utility libraries
│   ├── templates.json  # Template configurations
│   └── models.ts       # LLM model configurations
├── public/          # Static assets
├── .env.local       # Local environment variables
├── .env.template    # Environment template
├── package.json     # Dependencies
└── start-fragments.sh  # Startup script
```

### Running in Production

For production deployment:

```bash
# Build the application
npm run build

# Start production server
npm run start
```

### Hot Reload

Fragments supports hot reload during development. Edit files and see changes immediately:

```bash
# Start dev server
npm run dev

# Edit any file in app/ or components/
# Changes will appear automatically in the browser
```

## Performance Considerations

### Resource Requirements

**Minimum**:
- 2 CPU cores
- 4 GB RAM
- 10 GB disk space

**Recommended**:
- 4+ CPU cores
- 8+ GB RAM
- 20+ GB disk space

### Optimizing Sandbox Creation

Fragments creates sandboxes on-demand. To improve performance:

1. **Use Template Caching**: E2B caches templates automatically
2. **Keep Infrastructure Running**: Don't stop/start E2B services frequently
3. **Use Smaller Templates**: Choose minimal templates for faster startup

## Integration Benefits

### Why Integrate Fragments with Local E2B?

1. **Full Control**: Run everything locally, no external dependencies
2. **Privacy**: Code never leaves your machine
3. **Customization**: Modify templates and configurations as needed
4. **Cost Savings**: No API usage fees for E2B cloud service
5. **Development**: Test E2B infrastructure changes with a real UI

### Comparison with E2B Cloud

| Feature | Local E2B + Fragments | E2B Cloud |
|---------|----------------------|-----------|
| Sandbox Execution | ✅ Local Firecracker | ✅ Cloud VMs |
| API Management | ✅ Local API | ✅ Cloud API |
| Template Management | ✅ Manual | ✅ Automated |
| Cost | ✅ Free | 💰 Usage-based |
| Privacy | ✅ Complete | ⚠️ Data sent to cloud |
| Customization | ✅ Full control | ⚠️ Limited |

## Monitoring and Logs

### Check Service Status

```bash
# E2B API
curl http://localhost:3000/health

# Nomad jobs
nomad job status

# View API logs
nomad alloc logs $(nomad job allocs api | grep running | awk '{print $1}')

# View orchestrator logs
nomad alloc logs $(nomad job allocs orchestrator | grep running | awk '{print $1}')
```

### Fragments Logs

Development server logs appear in the terminal where you ran `npm run dev`.

For production logs:
```bash
# If running with pm2
pm2 logs fragments

# If running as systemd service
journalctl -u fragments -f
```

## Related Documentation

- **Original Fragments README**: See `README.md` in this directory
- **E2B Local Deployment**: `/home/primihub/pcloud/infra/local-deploy/README.md`
- **Template Creation**: `/home/primihub/pcloud/infra/templates/README.md`
- **API Documentation**: `/home/primihub/pcloud/infra/packages/api/README.md`

## Contributing

If you improve the Fragments integration:

1. Document changes in this file
2. Update startup scripts if needed
3. Test with all supported templates
4. Commit changes to the repository

## License

Fragments is licensed under the Apache License 2.0. See `LICENSE` file for details.

E2B Infrastructure is also licensed under the Apache License 2.0.

## Status

✅ **Integration Status**: Complete and Functional (January 2026)

**Last Updated**: January 12, 2026
**Tested With**: E2B Local v0.2.0, Fragments v0.1.0
**Maintainer**: PrimiHub Team
