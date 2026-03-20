# Safe Implementation Patterns

Reference patterns that satisfy security requirements. Workers should follow these when implementing security-sensitive code.

## Secrets Management
- Load all secrets from environment variables: `process.env.SECRET_KEY`
- Use `.env` files locally, never commit them (must be in `.gitignore`)
- Use a secrets manager (AWS Secrets Manager, Vault) in production

## SQL / Database Queries
- Always use ORM (Sequelize, Prisma, TypeORM) or parameterized queries
- Safe example:
  ```
  db.query("SELECT * FROM users WHERE id = $1", [userId])
  ```

## Password Handling
- Hash with bcrypt (cost >= 10) or argon2
- Safe example:
  ```
  const hash = await bcrypt.hash(password, 12)
  ```
- Never store plaintext; never use MD5/SHA1 for passwords

## JWT Implementation
- Secret from environment variable: `process.env.JWT_SECRET`
- Always set expiration: `{ expiresIn: '1h' }`
- Use RS256 or HS256 with a key >= 256 bits
- Safe example:
  ```
  jwt.sign(payload, process.env.JWT_SECRET, { expiresIn: '1h' })
  ```

## Input Validation
- Whitelist validation: define allowed values, reject everything else
- Use validation libraries (Joi, Zod, class-validator)
- Sanitize HTML output to prevent XSS (DOMPurify, escape-html)
- Validate on the server side, never trust client-only validation
