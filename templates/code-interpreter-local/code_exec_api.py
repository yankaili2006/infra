#!/usr/bin/env python3
"""
Lightweight Code Execution API for E2B Fragments Integration
Provides /execute endpoint compatible with @e2b/code-interpreter SDK

This is a minimal implementation that runs Python code in a subprocess
and returns results in the format expected by Fragments.
"""

import asyncio
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, List, Optional, Any

from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

# Initialize FastAPI app
app = FastAPI(title="E2B Code Execution API")

class ExecutionRequest(BaseModel):
    code: str
    context_id: Optional[str] = None
    language: Optional[str] = "python"
    env_vars: Optional[Dict[str, str]] = None

class ExecutionResult(BaseModel):
    stdout: str
    stderr: str
    error: Optional[str] = None
    results: List[Any] = []

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "ok"}

@app.post("/execute")
async def execute_code(request: ExecutionRequest) -> ExecutionResult:
    """
    Execute Python code and return results

    Compatible with @e2b/code-interpreter SDK expectations
    """

    # Only support Python for now
    if request.language and request.language not in ("python", "python3"):
        raise HTTPException(400, f"Language '{request.language}' not supported, only 'python' is available")

    # Create temporary file for the code
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        f.write(request.code)
        code_file = f.name

    try:
        # Set environment variables if provided
        env = None
        if request.env_vars:
            import os
            env = os.environ.copy()
            env.update(request.env_vars)

        # Execute the code
        process = subprocess.run(
            [sys.executable, code_file],
            capture_output=True,
            text=True,
            timeout=30,  # 30 second timeout
            env=env
        )

        # Parse results
        stdout = process.stdout
        stderr = process.stderr
        error = None
        results = []

        if process.returncode != 0:
            error = f"Execution failed with exit code {process.returncode}: {stderr}"

        # Try to extract results from stdout (simple approach)
        # If the code prints JSON objects, we could parse them here
        if stdout:
            results = [{"type": "text", "text": stdout}]

        return ExecutionResult(
            stdout=stdout,
            stderr=stderr,
            error=error,
            results=results
        )

    except subprocess.TimeoutExpired:
        return ExecutionResult(
            stdout="",
            stderr="",
            error="Execution timed out after 30 seconds",
            results=[]
        )

    except Exception as e:
        return ExecutionResult(
            stdout="",
            stderr="",
            error=f"Internal error: {str(e)}",
            results=[]
        )

    finally:
        # Clean up temporary file
        Path(code_file).unlink(missing_ok=True)

# Minimal context management endpoints (required by SDK)
@app.post("/contexts")
async def create_context(request: dict):
    """Create a new execution context (stub for compatibility)"""
    return {
        "id": "default",
        "language": request.get("language", "python"),
        "cwd": request.get("cwd", "/home/user")
    }

@app.get("/contexts")
async def list_contexts():
    """List execution contexts (stub for compatibility)"""
    return [{
        "id": "default",
        "language": "python",
        "cwd": "/home/user"
    }]

if __name__ == "__main__":
    import uvicorn

    # Run on port 49999 as expected by code-interpreter SDK
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=49999,
        log_level="info",
        access_log=True
    )
