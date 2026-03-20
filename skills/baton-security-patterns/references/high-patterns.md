# HIGH Patterns — Immediate Rollback

All patterns below warrant immediate pipeline halt and Rollback.

## 1. Privilege Escalation (Insufficient Access Control)
- Missing role/permission checks on admin or elevated endpoints.
- User-controlled role fields accepted without server-side validation.
- Examples:
  ```
  // No role check — any authenticated user can access
  app.get('/admin/users', authMiddleware, handler)
  // User can set own role
  user.role = req.body.role
  ```

## 2. Sensitive Information in Log Output
- Logging passwords, tokens, API keys, PII, or session IDs.
- Examples:
  ```
  console.log("User login:", { email, password })
  logger.info(`Token: ${accessToken}`)
  ```
- Detection: scan log statements for variables named `password`, `token`, `secret`, `ssn`, `creditCard`, etc.

## 3. Missing Encryption for Sensitive Data Transmission
- HTTP endpoints handling sensitive data without TLS enforcement.
- API calls to external services over plain HTTP with credentials.
- Sensitive data in URL query parameters (visible in logs and browser history).

## 4. JWT Secret Misuse
- JWT secret hardcoded in source code instead of environment variable.
- Missing token expiration (`expiresIn` not set).
- Using weak signing algorithms (e.g., `none`, `HS256` with short key).
- Examples:
  ```
  jwt.sign(payload, "my-secret")           // hardcoded
  jwt.sign(payload, secret)                 // no expiresIn
  jwt.sign(payload, secret, { algorithm: 'none' })
  ```
