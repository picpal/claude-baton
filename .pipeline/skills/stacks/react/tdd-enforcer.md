# TDD Enforcer — React
# extends: stacks/typescript/tdd-enforcer.md

## Additional Frameworks
- React Testing Library (RTL)
- @testing-library/user-event

## React-Specific Rules
- Component tests: render() + screen.getBy*
- Events: use userEvent.click() (avoid fireEvent)
- If dangerouslySetInnerHTML is used, report to Security Guardian immediately
- XSS prevention: do not directly render external input values
