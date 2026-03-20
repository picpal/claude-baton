# CRITICAL Patterns — Immediate Rollback

All patterns below warrant immediate pipeline halt and Rollback.

## 1. Hardcoded Secrets / API Keys / Passwords
- Any string literal containing keys, tokens, passwords, or connection strings.
- Examples:
  ```
  const SECRET = "abc123"
  apiKey = "sk-..."
  DB_PASSWORD = "plaintext"
  ```
- Detection: scan for patterns like `SECRET`, `API_KEY`, `PASSWORD`, `TOKEN` assigned to string literals.

## 2. SQL Injection (Non-parameterized Queries)
- String interpolation or concatenation inside SQL queries.
- Examples:
  ```
  `SELECT * FROM users WHERE id = ${userId}`
  "SELECT * FROM users WHERE name = '" + name + "'"
  ```
- Detection: look for template literals or string concat within SQL statement strings.

## 3. Authentication Bypass
- Missing auth middleware on protected routes.
- Conditional auth checks that can be trivially skipped (e.g., `if (isAdmin)` without verification).
- Default credentials or backdoor accounts in code.

## 4. Remote Code Execution (RCE)
- Use of `eval()`, `exec()`, `Function()`, `child_process.exec()` with user-controlled input.
- Deserialization of untrusted data (`JSON.parse` on raw user input piped to `eval`).
- Examples:
  ```
  eval(userInput)
  exec(`rm -rf ${path}`)
  ```

## 5. Plaintext Storage of Sensitive Data
- Passwords, tokens, or PII stored without hashing or encryption.
- Writing sensitive data to plain files, localStorage, or unencrypted DB columns.
- Detection: trace sensitive field assignments to storage operations without crypto calls.
