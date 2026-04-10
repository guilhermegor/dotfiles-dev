---
name: s:py-audit
description: Audit Python code for security vulnerabilities. Trigger when asked to audit, scan for vulnerabilities, check security, or find security issues in Python code.
effort: high
argument-hint: [source-file-or-directory]
allowed-tools: Read Glob Grep
---

Scan the provided Python source code for security vulnerabilities. Report
findings as a structured list with CWE references and remediation guidance —
do not modify any files.

## Required inputs

Before doing anything else, ask the user for the following if not already provided
in `$ARGUMENTS`:

1. **Source** — path to a `.py` file or a package directory.

Do not infer the path. Wait for explicit confirmation before reading files.

If a directory is provided, walk it recursively and audit all `.py` files.
Skip test files (`test_*.py`, `*_test.py`, `conftest.py`) unless explicitly asked.

## Vulnerability categories

### Injection (CWE-89, CWE-78, CWE-90, CWE-643)
- SQL injection — string formatting in queries instead of parameterised queries.
- Command injection — shell-based process execution with unsanitised user input,
  `subprocess` with `shell=True`.
- LDAP injection — unescaped input in LDAP filters.
- XPath/template injection — unescaped input in XPath or Jinja2 expressions.

### Hardcoded secrets (CWE-798)
- API keys, passwords, tokens, connection strings in source code.
- Base64-encoded credentials.
- Private keys or certificates embedded in code.
- Look for assignment patterns: `password =`, `token =`, `secret =`, `api_key =`,
  `AWS_ACCESS_KEY`, `Bearer`, connection strings with credentials.

### Insecure deserialization (CWE-502)
- `yaml.load()` without `Loader=SafeLoader`.
- Dynamic code execution with external input (the `eval`/`compile` builtins).
- Unsafe unmarshalling of untrusted data.

### Path traversal (CWE-22)
- File operations with unsanitised user input (unchecked `open()` or `Path()` calls).
- Missing path normalisation before file access.
- Directory traversal via `../` sequences.

### SSRF (CWE-918)
- HTTP client calls with user-controlled URLs (`requests`, `httpx`, `urllib`).
- Missing URL validation or allowlisting.

### Insecure cryptography (CWE-327, CWE-328)
- MD5 or SHA1 used for security purposes (hashing passwords, signatures).
- `random` module used for security-sensitive operations instead of `secrets`.
- Hardcoded encryption keys or IVs.
- Weak key sizes (RSA < 2048, AES < 128).

### Information disclosure (CWE-209, CWE-215)
- Stack traces exposed to users.
- Debug mode enabled in production config.
- Verbose error messages revealing internal paths or database structure.
- Logging sensitive data (passwords, tokens, PII).

### Authentication and authorization (CWE-287, CWE-862)
- Missing authentication checks on sensitive endpoints.
- Authorization bypasses (role checks missing or insufficient).
- Session management issues (predictable tokens, missing expiry).

### Race conditions (CWE-362, CWE-367)
- TOCTOU (time-of-check-time-of-use) vulnerabilities.
- Shared mutable state without locking.
- File operations without proper locking.

### Dependency risks
- Known-vulnerable imports (flag and recommend checking against safety/pip-audit).
- Imports from deprecated or unmaintained packages.

## Severity levels

- **Critical** — exploitable remotely with high impact (RCE, data breach).
- **High** — exploitable with moderate effort or significant impact.
- **Medium** — requires specific conditions to exploit.
- **Low** — minor risk or defence-in-depth improvement.
- **Informational** — not directly exploitable but worth noting.

## Output format

```
## Security Audit: <filename or package>

### Critical (<count>)
- `file.py:42` — [CWE-78] Command injection via unsanitised input in subprocess call.
  **Remediation:** Use `subprocess.run()` with a list of arguments instead of shell=True.

### High (<count>)
- `file.py:15` — [CWE-798] Hardcoded API key in source code.
  **Remediation:** Move to environment variable or secrets manager.

### Medium (<count>)
...

### Summary
<1-2 sentence overall security posture assessment>
<Recommendation for next steps (e.g., run pip-audit, add bandit to CI)>
```

## Do Not

- Do not modify any files — this is a read-only audit.
- Do not run any commands.
- Do not report findings without a CWE reference.
- Do not flag intentional test fixtures (e.g., `# noqa S105` for test tokens).
- Do not report more than 30 findings — prioritise by severity.
