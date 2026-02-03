# Advanced: Using Local Code Interpreter SDK

If you want to develop or debug the E2B Code Interpreter SDK locally with Fragments:

## Prerequisites

The code-interpreter SDK repository should be at `~/github/code-interpreter`.

## Setup Local Development

### 1. Build the Code Interpreter SDK

```bash
cd ~/github/code-interpreter
pnpm install
cd js
pnpm run build
```

### 2. Link the SDK to Fragments

**Option A: Using npm link**

```bash
# In code-interpreter JS directory
cd ~/github/code-interpreter/js
npm link

# In fragments directory
cd /home/primihub/pcloud/infra/fragments
npm link @e2b/code-interpreter
```

**Option B: Using package.json file: reference**

Edit `/home/primihub/pcloud/infra/fragments/package.json`:

```json
{
  "dependencies": {
    "@e2b/code-interpreter": "file:../../../github/code-interpreter/js"
  }
}
```

Then:
```bash
cd /home/primihub/pcloud/infra/fragments
npm install
```

### 3. Restart Fragments

```bash
cd /home/primihub/pcloud/infra/fragments
npm run dev
```

## Version Notes

- **Fragments dependency**: `@e2b/code-interpreter@^1.0.2`
- **Local code-interpreter version**: `@e2b/code-interpreter@2.3.3`

There may be API changes between versions. If you encounter compatibility issues:

1. Update Fragments code to use the new SDK API
2. Or downgrade the local code-interpreter to match Fragments' expected version

## Making Changes

When you modify the code-interpreter SDK:

1. **Rebuild the SDK**:
   ```bash
   cd ~/github/code-interpreter/js
   pnpm run build
   ```

2. **Restart Fragments**:
   - The dev server should hot-reload
   - If not, restart: `npm run dev`

3. **Test changes** in Fragments UI

4. **Unlink when done** (if using npm link):
   ```bash
   cd /home/primihub/pcloud/infra/fragments
   npm unlink @e2b/code-interpreter
   npm install
   ```

## Common Issues

### Issue: Module Not Found After Linking

**Solution**: Clear caches and reinstall
```bash
cd /home/primihub/pcloud/infra/fragments
rm -rf node_modules package-lock.json
npm install
```

### Issue: TypeScript Errors

**Solution**: Ensure SDK is built
```bash
cd ~/github/code-interpreter/js
pnpm run build
```

### Issue: API Changes Not Reflected

**Solution**: Restart Next.js dev server
```bash
# Stop with Ctrl+C, then
npm run dev
```

## When to Use Local SDK Development

Use local SDK linking when you need to:
- Add new features to the Code Interpreter SDK
- Debug SDK issues that only appear in Fragments
- Test SDK API changes before publishing
- Contribute to the code-interpreter project

For normal Fragments usage, the npm-installed version is sufficient.
