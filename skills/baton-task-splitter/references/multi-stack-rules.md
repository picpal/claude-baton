# Multi-Stack Task Separation Rules

## Core Principle
A single task must never span two or more technology stacks.
If it does, it must be split into separate per-stack tasks with explicit dependencies.

## When to Split

| Signal | Action |
|--------|--------|
| Task files belong to different stacks | Mandatory split |
| Task requires both API server + client changes | Split into backend task + frontend task |
| Task touches shared schema (DB + app code) | Split into migration task + application task |
| Task involves infra config + application code | Split into infra task + app task |

## How to Split

1. **Identify stacks**: Run `scripts/tag-stack.sh` on each file in the task.
2. **Group by stack**: Collect files into per-stack groups.
3. **Create one task per group**: Each group becomes its own task entry in todo.md.
4. **Set dependencies**: The consumer task depends on the provider task.
   - DB migration before application code
   - Backend API before frontend integration
   - Shared library before consumers

## Dependency Direction Rules

```
DB schema migration
  -> Backend service implementation
    -> API contract tests
      -> Frontend integration
        -> E2E tests
```

- Tasks at the same level with no data dependency may run in parallel.
- Tasks at different levels must declare `depends:` on the upstream task.

## Examples

### Example 1: Login Feature (Spring Boot + Expo)
Original task: "Implement login flow"

Split result:
```
- [ ] task-01: Implement login API endpoint
      stack: spring-boot
      files: [AuthController.java, AuthService.java, AuthServiceTest.java]

- [ ] task-02: Implement login screen and auth hook
      stack: expo
      files: [LoginScreen.tsx, useAuth.ts, useAuth.test.ts]
      depends: task-01
```

### Example 2: User Profile (Django + React + PostgreSQL)
Original task: "Add user profile with avatar upload"

Split result:
```
- [ ] task-01: Add profile fields to user model + migration
      stack: django
      files: [models.py, 0005_add_profile.py]

- [ ] task-02: Profile API endpoints + S3 upload
      stack: django
      files: [views.py, serializers.py, storage.py]
      depends: task-01

- [ ] task-03: Profile page UI with avatar upload
      stack: react
      files: [ProfilePage.tsx, useProfile.ts, AvatarUpload.tsx]
      depends: task-02
```

## Edge Cases

- **Shared types/interfaces**: If a type file is used by multiple stacks (e.g., a shared TypeScript types package), assign it to the stack that owns the package. Create a separate task for it if changes are needed.
- **Monorepo packages**: Treat each package as its own stack boundary.
- **Config files** (e.g., docker-compose.yml, CI config): Assign to an `infra` or `devops` stack. Do not bundle with application tasks.
