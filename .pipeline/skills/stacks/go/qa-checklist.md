# QA Checklist — Go
# extends: base/qa-checklist.md

## Go 전용 검증
- [ ] go test ./... 전체 통과
- [ ] 커버리지 80% 이상
- [ ] go vet 경고 없음
- [ ] golint / staticcheck 통과
- [ ] panic 사용 없음 (error 반환 패턴)
