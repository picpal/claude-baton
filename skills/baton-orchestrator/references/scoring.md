# Complexity Scoring — Detailed Reference

## Scoring Table

| Criterion | Score | Notes |
|-----------|-------|-------|
| Expected files to change | 1pt per file, max 5pt | Count distinct files across all stacks |
| Cross-service dependency | +3 | API calls between services, shared DB, message queues |
| New feature (not modifying existing) | +2 | Greenfield code, new endpoints, new screens |
| Includes architectural decisions | +3 | New patterns, service boundaries, data flow changes |
| Security / auth / payment related | +4 | Authentication, authorization, encryption, payment flows |
| DB schema change | +3 | Migrations, new tables, column changes, index changes |

## Tier Thresholds

| Total Score | Tier | Pipeline |
|-------------|------|----------|
| 0–3 pts | Tier 1 (Light) | Minimal pipeline, no review |
| 4–8 pts | Tier 2 (Standard) | Full pipeline, 3 reviewers |
| 9+ pts | Tier 3 (Full) | Full pipeline, 5 reviewers, 3 planners |

## Scoring Examples

### Example 1: "Add a loading spinner to the profile page"
- Files: 1 (ProfilePage.tsx) → 1pt
- Cross-service: No → 0
- New feature: No (modifying existing) → 0
- Architecture: No → 0
- Security: No → 0
- DB: No → 0
- **Total: 1pt → Tier 1**

### Example 2: "Add OAuth2 login with Google"
- Files: 4 (AuthService, AuthController, LoginScreen, config) → 4pt
- Cross-service: Yes (Google API) → +3
- New feature: Yes → +2
- Architecture: Yes (auth flow design) → +3
- Security: Yes (auth) → +4
- DB: Yes (user tokens table) → +3
- **Total: 19pt → Tier 3**

### Example 3: "Add pagination to the user list API"
- Files: 3 (Repository, Service, Controller) → 3pt
- Cross-service: No → 0
- New feature: No (enhancing existing) → 0
- Architecture: No → 0
- Security: No → 0
- DB: No (query change only) → 0
- **Total: 3pt → Tier 1**
