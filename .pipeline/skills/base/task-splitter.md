# Task Splitter Skill

## 역할
계획을 독립 task 단위로 분리하고 의존성을 파악한다.
complexity-score.md의 스택 매핑을 읽어 각 task에 stack을 자동 태깅한다.
사람이 stack을 기재할 필요 없다.

## task 분리 원칙
- 하나의 task = 하나의 책임
- 단위 테스트가 가능한 최소 단위로 분리
- 파일 범위가 명확하게 정의되어야 함

## 스택 자동 태깅 방법
1. complexity-score.md의 "파일 → 스택 매핑" 섹션 읽기
2. 각 task의 파일 경로와 매핑 규칙 대조
3. 해당 stacks/ 폴더 skill 경로를 task에 기록
4. 매핑 불확실한 경우 → Main에 보고 후 확정

## 멀티 스택 task 처리
하나의 task가 두 스택에 걸치는 경우 → task 분리 필수
예) "로그인 API 연동" → task-A: Java API 구현 / task-B: RN fetch 구현

## todo.md 형식
```
- [ ] task-01: {설명}
      담당: Worker-A | 모델: opus
      stack: spring-boot
      skill: .pipeline/skills/stacks/spring-boot/tdd-enforcer.md
      파일: [AuthService.java, AuthController.java]

- [ ] task-02: {설명}
      담당: Worker-B | 모델: sonnet
      stack: expo
      skill: .pipeline/skills/stacks/expo/tdd-enforcer.md
      파일: [LoginScreen.tsx, useAuth.ts]
      의존: task-01
```
