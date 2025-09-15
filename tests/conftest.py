
import pytest
import subprocess
import re
import os

@pytest.fixture(scope="session", autouse=True)
def cpc_context_restorer():
    """
    A session-scoped fixture that automatically saves the CPC context
    before tests run and restores it after they complete.
    """
    original_context = None
    # Assuming the project root is the parent directory of the 'tests' directory
    project_root = os.path.dirname(os.path.dirname(__file__))
    cpc_script = os.path.join(project_root, 'cpc')

    # Ensure the cpc script is executable
    if not os.access(cpc_script, os.X_OK):
        print(f"\n[CPC Test Setup] Warning: CPC script at {cpc_script} is not executable. Skipping context restoration.")
        yield
        return

    try:
        # Get the current context before tests start
        result = subprocess.run(
            [cpc_script, 'ctx'],
            capture_output=True,
            text=True,
            cwd=project_root,
            timeout=15
        )
        if result.returncode == 0:
            # Regex to find the context name, works even with ANSI color codes
            match = re.search(r"Current cluster context: (\S+)", result.stdout)
            if match:
                original_context = match.group(1)
                print(f"\n[CPC Test Setup] Saved original context: {original_context}")
            else:
                print(f"\n[CPC Test Setup] Warning: Could not parse original context from './cpc ctx' output.")
        else:
            print(f"\n[CPC Test Setup] Warning: './cpc ctx' failed, could not save context. STDERR: {result.stderr}")

    except Exception as e:
        print(f"\n[CPC Test Setup] Warning: Could not save original CPC context due to an exception: {e}")

    # This is where the tests will run
    yield

    # After tests are done, restore the context
    if original_context:
        try:
            print(f"\n[CPC Test Teardown] Restoring original context: '{original_context}'")
            # Use a longer timeout for restoration as it might involve cloud operations
            restore_result = subprocess.run(
                [cpc_script, 'ctx', original_context],
                capture_output=True,
                text=True,
                cwd=project_root,
                timeout=30
            )
            if restore_result.returncode == 0:
                print(f"[CPC Test Teardown] Original context restored successfully.")
            else:
                print(f"[CPC Test Teardown] ERROR: Failed to restore context. STDOUT: {restore_result.stdout} STDERR: {restore_result.stderr}")
        except Exception as e:
            print(f"\n[CPC Test Teardown] ERROR: Could not restore original CPC context due to an exception: {e}")

