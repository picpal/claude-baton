# Security Pattern Library

## CRITICAL — Immediate Rollback Trigger
- Hardcoded secrets/API keys/passwords
  e.g.: const SECRET = "abc123", apiKey = "sk-..."
- SQL Injection (non-parameterized queries)
  e.g.: `SELECT * FROM users WHERE id = ${userId}`
- Code patterns that allow authentication bypass
- Input handling vulnerable to RCE (eval, exec, etc.)
- Plaintext storage of sensitive data

## HIGH — Immediate Rollback Trigger
- Insufficient access control (privilege escalation possible)
- Sensitive information in log output (passwords, tokens, PII)
- Sensitive data transmission without encryption
- JWT secret not using environment variables

## MEDIUM and below — Standard Rework
- XSS vulnerabilities
- CSRF token not validated
- Insufficient input validation
- Weak encryption algorithms

## Safe Implementation Patterns
- Secrets:    process.env.SECRET_KEY (hardcoding strictly prohibited)
- SQL:        ORM or parameter binding
- Passwords:  bcrypt / argon2 hashing
- JWT:        Environment variable secret + expiration time setting
- Input:      Whitelist validation
