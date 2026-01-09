# Copilot / Contributor Instructions

Purpose
- This repository is IWA-Java (Insecure Web App) — a deliberately insecure example Spring Boot application intended for teaching, demos, and security testing (SAST/DAST/IAST/pen-tests).
- The goal is to provide realistic insecure patterns so security tools and learners can detect, investigate, and remediate issues.

High-level rules for contributors and automated assistants
- It is allowed and encouraged to add *insecure* or vulnerable code for learning or testing purposes, provided the insecure change is:
  1. Clearly marked with a comment near the code (see "Marking insecure code" below).
  2. Documented in the PR description and in any relevant README or `etc/` documentation.
  3. Not shipping real secrets, credentials, or keys. Use placeholder values or environment variables.
- Normal code quality practices still apply for non-teaching code: include unit/integration tests where feasible, keep changes small and focused, and follow the project's coding style.

Marking insecure code
- When introducing intentionally insecure code, add a clear marker comment and brief explanation that includes:
  - Why the code is insecure (one sentence),
  - What it demonstrates (e.g., SQL injection, weak crypto, open redirects),
  - How to safely remove or fix it.

Example markers (Java):
```java
// INSECURE: Demonstrates SQL injection via string concatenation. Do NOT use in production.
// Purpose: teaching SAST rule detection for SQL injection.
String sql = "SELECT * FROM users WHERE name = '" + userInput + "'";
```

Documentation and PR requirements
- Every PR that adds insecure code must:
  - Include a short description of the insecurity in the PR body.
  - Reference any learning objectives (what tools or checks should flag this).
  - Include steps to reproduce (if interactive) and any required test inputs.
  - Ensure no real credentials are added — use placeholders or environment variables.
- Update `README.md` or the appropriate `etc/` docs when adding new demo scenarios, including how to enable/disable the insecure behavior if possible.

Where to add code
- Java source: `src/main/java` (packages already present in the repo — follow existing package layout).
- Tests: `src/test/java` (add unit or integration tests as appropriate).
- Configuration: `src/main/resources` (YAML or properties).
- Sample data and macros: `etc/` and `samples/` if the change requires sample inputs or Postman macros.

Local build & run (quick reference)
- Build the app:

```powershell
.\gradlew clean build
```

- Run locally (dev profile):

```powershell
.\gradlew bootRun
```

- Docker build and run (example):

```powershell
docker build -t iwa -f Dockerfile .
docker run --rm -p 8888:8888 -e SPRING_MAIL_TEST_CONNECTION=false iwa
```

Security & secrets
- Never commit passwords, API keys, or other secrets. Use environment variables or secret stores.
- For testing email or external services locally, use local test servers (smtp4dev, mock servers) or documented placeholders.

Labels & PR workflow
- Create a feature branch: `feature/<short-description>` or `insecure/<short-description>` when the PR intentionally adds insecure examples.
- In the PR title or description, include the tag `[INSECURE-EXAMPLE]` and ask reviewers to check the documentation and marking comments.

Automated assistants (Copilot / bots)
- If suggesting or generating code, ensure the assistant adds the required comment markers and a brief explanation.
- Don't auto-insert real secrets or credentials. Use placeholders like `REPLACE_ME` or environment variable references.

Cleanup guidance
- If insecure code is later removed or replaced with secure alternatives, add a note to the commit/PR explaining the remediation and, if useful, keep the insecure example in a separate demo module or tests to preserve learning value.

Contact / Questions
- If you're unsure where to place an example or how to annotate it, open an Issue describing the scenario and intended learning objective.

Thank you for contributing — and for keeping the project both useful and intentionally instructive for security learning.
