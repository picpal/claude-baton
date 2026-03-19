# QA Checklist Skill

## Unit Test QA
- [ ] All test files execute successfully
- [ ] Line coverage 80% or above
- [ ] No failing tests
- [ ] Tests can run independently (no order dependency)

## Integration Test QA
- [ ] Inter-module interface compatibility
- [ ] API endpoints respond correctly
- [ ] Error cases handled properly
- [ ] No regression in existing functionality

## Multi-Stack Contract Test
(Mandatory when complexity-score.md shows "contract test required: YES")
- [ ] API response spec ↔ client fetch code match verified
- [ ] Field names, types, and nullable status are identical on both sides
- [ ] Error response format is consistent

## Failure Handling
- Attempts 1-3: Request fix from Worker
- Beyond 3 attempts: Escalate to Main (request Task Manager redesign)
