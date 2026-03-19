# QA Checklist — Go
# extends: base/qa-checklist.md

## Go Specific Verification
- [ ] go test ./... all passing
- [ ] Coverage 80% or above
- [ ] No go vet warnings
- [ ] golint / staticcheck passing
- [ ] No panic usage (error return pattern)
