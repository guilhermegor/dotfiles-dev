---
name: s:markdown-readme
description: Use when generating, creating, or writing a README.md file for a Python project from scratch or from a template.
effort: medium
argument-hint: [project-name] [github-username]
---

Generate a professional README.md file for a Python project following the
structure and guidelines below.

## Required inputs

Before writing anything, ask for any of the following not already in `$ARGUMENTS`:

1. **Project name** — exact repository/project name (used in badges and links).
2. **GitHub username** — the owner or organisation for badge and link URLs.
3. **Brief description** — 2–4 sentences explaining what the project does and who it is for.
4. **Author name** — full name and GitHub/LinkedIn handles for the Authors section.

Do not infer any of these. Wait for explicit values before generating output.

## Template

```markdown
<!-- markdownlint-disable MD013 -->
# ${PROJECT_NAME} <img src="assets/logo.png" align="right" width="150" style="border-radius: 12px;" alt="${PROJECT_NAME} logo">

<!-- Badges -->
[![Project Status: Active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![Python Version](https://img.shields.io/badge/python-3.10%20%7C%203.11%20%7C%203.12-blue?logo=python&logoColor=white)](https://www.python.org/)
[![Linting: Ruff](https://img.shields.io/badge/linting-ruff-yellow?logo=ruff&logoColor=white)](https://github.com/astral-sh/ruff)
[![Formatting: isort](https://img.shields.io/badge/formatting-isort-%231674b1)](https://pycqa.github.io/isort/)
[![Tests: Pytest](https://img.shields.io/badge/tests-pytest-blue?logo=pytest&logoColor=white)](https://docs.pytest.org/)
![Test Coverage](./coverage.svg)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Open Issues](https://img.shields.io/github/issues/${GITHUB_USERNAME}/${PROJECT_NAME})](https://github.com/${GITHUB_USERNAME}/${PROJECT_NAME}/issues)
[![Contributions Welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg)](CONTRIBUTING.md)

**${PROJECT_NAME}** ${BRIEF_DESCRIPTION}

## ✨ Key Features

- **Feature 1**: Brief description of the first key feature
- **Feature 2**: Brief description of the second key feature
- **Feature 3**: Brief description of the third key feature
- **Feature 4**: Brief description of the fourth key feature
- **Feature 5**: Brief description of the fifth key feature

## 🚀 Getting Started

### Prerequisites

Before you begin, ensure you have the following installed:

- **Python 3.10+**: [Download Python](https://www.python.org/downloads/)
- **Poetry** (recommended) or **pip**: For dependency management
- **Git**: For version control

### Optional

- **Docker**: For containerized development
- **Make**: For running Makefile commands
- **Pre-commit**: For automated code quality checks

### Installation

1. **Clone the repository**

   ```bash
   git clone https://github.com/${GITHUB_USERNAME}/${PROJECT_NAME}.git
   cd ${PROJECT_NAME}
   ```

2. **Set up Python environment**

   Using Poetry (recommended):
   ```bash
   poetry install
   poetry shell
   ```

   Using pip:
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   pip install -r requirements.txt
   ```

3. **Configure environment variables**

   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

4. **Run the application**

   ```bash
   python -m src.main
   # or
   make run
   ```

## 🧪 Running Tests

```bash
# Run all tests
pytest

# Run with coverage report
pytest --cov=src --cov-report=html

# Run specific test categories
pytest tests/unit/
pytest tests/integration/
pytest tests/performance/

# Run with verbose output
pytest -v

# Run and stop on first failure
pytest -x
```

Using Make:

```bash
make test          # Run all tests
make test-cov      # Run tests with coverage
make test-unit     # Run unit tests only
```

---

## 📁 Project Structure

```
${PROJECT_NAME}/
├── src/                          # Source code
│   ├── __init__.py
│   ├── main.py                   # Application entrypoint
│   ├── core/                     # Core/shared components
│   │   ├── domain/               # Domain entities and value objects
│   │   ├── application/          # Application services and factories
│   │   └── infrastructure/       # Infrastructure adapters
│   ├── modules/                  # Feature modules
│   │   └── <feature>/            # Feature-specific code
│   │       ├── domain/           # Feature domain layer
│   │       ├── application/      # Feature use-cases
│   │       └── infrastructure/   # Feature adapters
│   ├── utils/                    # Utility functions
│   └── config/                   # Configuration management
├── tests/                        # Test suite
│   ├── unit/                     # Unit tests
│   ├── integration/              # Integration tests
│   └── performance/              # Performance tests
├── docs/                         # Documentation
├── scripts/                      # Utility scripts
├── container/                    # Docker configuration
├── assets/                       # Static assets (images, etc.)
├── .github/                      # GitHub Actions workflows
├── .vscode/                      # VS Code settings
├── .env.example                  # Environment variables template
├── pyproject.toml                # Project configuration
├── requirements.txt              # Dependencies (pip format)
├── Makefile                      # Make commands
└── README.md                     # This file
```

## 👨‍💻 Authors

**${AUTHOR_NAME}**
[![GitHub](https://img.shields.io/badge/GitHub-${GITHUB_USERNAME}-181717?style=flat&logo=github)](https://github.com/${GITHUB_USERNAME})
[![LinkedIn](https://img.shields.io/badge/LinkedIn-${AUTHOR_NAME}-0077B5?style=flat&logo=linkedin)](https://www.linkedin.com/in/${GITHUB_USERNAME}/)

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- This documentation follows a structure inspired by [PurpleBooth's README-Template.md](https://gist.github.com/PurpleBooth/109311bb0361f32d87a2)
- [BlueprintX](https://github.com/guilhermegor/blueprintx) - Project scaffolding

## 🔗 Useful Links

- 📦 [GitHub Repository](https://github.com/${GITHUB_USERNAME}/${PROJECT_NAME})
- 🐛 [Issue Tracker](https://github.com/${GITHUB_USERNAME}/${PROJECT_NAME}/issues)
- 📚 [Documentation](https://github.com/${GITHUB_USERNAME}/${PROJECT_NAME}/wiki)
- 🗺️ [Roadmap](https://github.com/${GITHUB_USERNAME}/${PROJECT_NAME}/projects)
- 💬 [Discussions](https://github.com/${GITHUB_USERNAME}/${PROJECT_NAME}/discussions)

## 🤝 Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to submit issues, feature requests, and pull requests.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request
```

## Variables to replace

| Variable | Description | Example |
|---|---|---|
| `${PROJECT_NAME}` | Repository/project name | `my-awesome-project` |
| `${GITHUB_USERNAME}` | GitHub username or organisation | `johndoe` |
| `${BRIEF_DESCRIPTION}` | 2–4 sentence project description | `A Python tool for…` |
| `${AUTHOR_NAME}` | Author's full name | `John Doe` |

## Badge catalogue

### Project status
```markdown
[![Project Status: Concept](https://www.repostatus.org/badges/latest/concept.svg)](https://www.repostatus.org/#concept)
[![Project Status: WIP](https://www.repostatus.org/badges/latest/wip.svg)](https://www.repostatus.org/#wip)
[![Project Status: Active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![Project Status: Inactive](https://www.repostatus.org/badges/latest/inactive.svg)](https://www.repostatus.org/#inactive)
[![Project Status: Unsupported](https://www.repostatus.org/badges/latest/unsupported.svg)](https://www.repostatus.org/#unsupported)
[![Project Status: Moved](https://www.repostatus.org/badges/latest/moved.svg)](https://www.repostatus.org/#moved)
```

### Python version
```markdown
[![Python 3.10](https://img.shields.io/badge/python-3.10-blue?logo=python&logoColor=white)](https://www.python.org/)
[![Python 3.10+](https://img.shields.io/badge/python-3.10%2B-blue?logo=python&logoColor=white)](https://www.python.org/)
[![Python 3.10 | 3.11 | 3.12](https://img.shields.io/badge/python-3.10%20%7C%203.11%20%7C%203.12-blue?logo=python&logoColor=white)](https://www.python.org/)
```

### CI/CD
```markdown
[![Tests](https://github.com/${GITHUB_USERNAME}/${PROJECT_NAME}/actions/workflows/tests.yaml/badge.svg)](https://github.com/${GITHUB_USERNAME}/${PROJECT_NAME}/actions)
[![Build](https://github.com/${GITHUB_USERNAME}/${PROJECT_NAME}/actions/workflows/build.yaml/badge.svg)](https://github.com/${GITHUB_USERNAME}/${PROJECT_NAME}/actions)
[![codecov](https://codecov.io/gh/${GITHUB_USERNAME}/${PROJECT_NAME}/branch/main/graph/badge.svg)](https://codecov.io/gh/${GITHUB_USERNAME}/${PROJECT_NAME})
```

### License
```markdown
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue.svg)](LICENSE)
```

## Guidelines

1. **Keep it concise** — README should be scannable in under 2 minutes.
2. **Use visuals** — logo, badges, and diagrams aid comprehension.
3. **Provide examples** — show actual commands and expected output.
4. **Link to details** — link to detailed docs rather than inlining long explanations.
5. **Keep it updated** — ensure installation steps match the current state of the project.
6. **Be welcoming** — encourage contributions with clear guidelines.
