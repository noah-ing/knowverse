# KnowVerse Security and Code Quality Audit Report

**Auditor**: Consensys (AI-powered code review)
**Date**: 2026-01-07
**Target**: KnowVerse (https://github.com/noah-ing/knowverse)
**Branch**: audit/consensys-full-review

---

## Executive Summary

*To be completed after full audit*

---

## Technology Stack

| Component | Technology | Version |
|-----------|------------|---------|
| Framework | Ruby on Rails | 8.0.2 |
| Ruby | Ruby | 3.2.2 |
| Primary Database | PostgreSQL | 14+ (with pgvector) |
| Secondary Database | SQLite | 2.0 |
| Vector Store | Qdrant | HNSW indexing |
| ML Services | Python/Haystack/FastAPI | 3.11/2.0 |
| Frontend | Hotwire (Turbo + Stimulus) | - |
| CSS | Tailwind CSS | 4.x |
| Background Jobs | Sidekiq, Solid Queue | 7.2 |
| Caching | Solid Cache, Redis | 5.0 |
| Authentication | Devise (passwordless), OmniAuth | SAML/OIDC |
| Authorization | Pundit | 2.3 |
| Payments | Stripe (Pay gem) | 9.0 |

---

## Audit Scope

### In Scope
- Authentication and authorization flows
- Injection vulnerabilities (SQL, XSS, Command, Path Traversal)
- Data exposure and secrets management
- Code quality and architecture
- Performance and scalability
- Frontend UX testing

### Out of Scope
- Third-party service security (Stripe, Google, Notion APIs)
- Infrastructure/server configuration
- Denial of Service testing

---

## Findings Summary

| Severity | Count | Fixed | Remaining |
|----------|-------|-------|-----------|
| CRITICAL | 0 | 0 | 0 |
| HIGH | 3 | 0 | 3 |
| MEDIUM | 2 | 0 | 2 |
| LOW | 1 | 0 | 1 |
| INFO | 3 | - | - |

---

## Detailed Findings

### V6-002: Codebase DNA Fingerprint

**Files Analyzed**: 45 Python files (18,073 lines of code)

#### Coding Style Summary

| Pattern | Style | Coverage/Details |
|---------|-------|------------------|
| Function Names | mixed | `load_wikipedia`, `ingest_dataset` |
| Class Names | PascalCase | `Chunk`, `EmbeddingBatch`, `ProgressTracker` |
| Variable Names | snake_case | `logger`, `dataset`, `count` |
| Constants | UPPER_SNAKE_CASE | Standard Python convention |
| Private Prefix | `_` | Single underscore for private |

#### Type Hint Coverage

| Metric | Value |
|--------|-------|
| Functions with hints | 412/519 (79.4%) |
| Parameters with hints | 728/821 (88.7%) |
| Return type coverage | 63.8% |
| Overall coverage | **88.7%** (Good) |

#### Docstring Analysis

| Metric | Value |
|--------|-------|
| Format | Simple (not Google/NumPy/Sphinx) |
| Coverage | 85.0% |
| Average Length | 99 characters |

#### Import Style

| Pattern | Value |
|---------|-------|
| Preferred style | from-imports |
| Groups imports | Yes |
| Relative imports | 6.0% |
| Common stdlib | typing, logging, time, dataclasses, re |
| Common third-party | app, numpy, qdrant_client, config, haystack |

#### Error Handling

| Pattern | Value |
|---------|-------|
| Exception specificity | Specific (good) |
| Uses bare except | **Yes** (concern) |
| Try blocks | 193 |
| Custom exceptions | ClarificationNeeded, ToolError |
| Common handlers | Exception, ImportError, ValueError, UnicodeDecodeError |

#### Test Coverage

| Metric | Value |
|--------|-------|
| Test framework | pytest |
| Test files | 7 |
| Test-to-source ratio | 0.18 (low) |
| Uses fixtures | Yes |
| Uses mocks | Yes |

#### Function Metrics

| Metric | Value | Assessment |
|--------|-------|------------|
| Average length | 27.1 lines | Acceptable |
| Max length | 241 lines | **HIGH** - needs refactoring |
| Average complexity | 4.5 | Good |
| Max complexity | 38 | **VERY HIGH** - critical |
| Total functions | 519 | - |
| Deeply nested | 509 (98%) | **CONCERN** |

#### Style Inconsistencies Identified

1. **Mixed function naming** - Some functions use different conventions (e.g., `load_wikipedia` vs potentially camelCase elsewhere)
2. **Bare except usage** - Uses bare `except:` which catches all exceptions including system exits
3. **Deep nesting** - 98% of functions have deep nesting (3+ levels), indicating potential for refactoring
4. **High max complexity** - Cyclomatic complexity of 38 in some functions (ideally <10)
5. **Long functions** - Some functions reach 241 lines (ideally <50)
6. **Low test ratio** - Test-to-source ratio of 0.18 is below recommended 0.5-1.0

#### Areas Deviating from Best Practices

| Issue | Location | Recommendation |
|-------|----------|----------------|
| Bare except | Multiple files | Use specific exceptions |
| Function length | Max 241 lines | Split into smaller functions |
| Cyclomatic complexity | Max 38 | Refactor complex logic |
| Test coverage | 0.18 ratio | Add more unit tests |
| Return type hints | 63.8% | Add return type annotations |

#### DNA Fingerprint Location
Saved to: `/Users/noah-ing/Desktop/knowverse/.consensys-dna.json`

### V6-003: Authentication and Authorization

#### Summary
The application uses Devise with magic link authentication, standard database authentication, and enterprise SSO (SAML 2.0 / OpenID Connect). Security controls are generally well-implemented with some areas for improvement.

#### Findings

##### AUTH-001: Missing Login Rate Limiting (HIGH)
- **Location**: `config/initializers/security.rb`
- **Description**: Rack::Attack rate limiting does not include specific throttling for login endpoints (`/users/sign_in`, `/users/magic_link`). This allows brute force attacks against user accounts.
- **Current Config**: General rate limit (300/min), search (60/min), API (100/min) - but no login-specific limits
- **Remediation**: Add throttling for login endpoints:
  ```ruby
  Rack::Attack.throttle('login', limit: 5, period: 1.minute) do |req|
    req.ip if req.path == '/users/sign_in' && req.post?
  end
  ```

##### AUTH-002: Devise Lockable Not Enabled (MEDIUM)
- **Location**: `app/models/user.rb:2`, `config/initializers/devise.rb:197-221`
- **Description**: Devise's `:lockable` module is not included in the User model. This means accounts are not locked after failed login attempts.
- **Current**: User model includes `:database_authenticatable, :registerable, :recoverable, :rememberable, :validatable, :omniauthable, :magic_link_authenticatable`
- **Missing**: `:lockable` for account lockout after failed attempts
- **Remediation**: Add `:lockable` to devise modules and configure `lock_strategy`, `maximum_attempts`, and `unlock_strategy`

##### AUTH-003: API Key Authentication Fallback Risk (HIGH)
- **Location**: `app/controllers/api/v1/base_controller.rb:31`
- **Description**: When an API key is valid but organization has no owner, the authentication falls back to `@current_organization.users.first`, which could grant access to an arbitrary user without proper authorization checks.
- **Code**:
  ```ruby
  @current_user = @current_organization.owner || @current_organization.users.first
  ```
- **Risk**: If owner is nil, any user in the organization becomes the authenticated user
- **Remediation**: Require explicit owner assignment or fail authentication if no owner exists

##### AUTH-004: Admin Privilege Escalation via User Params (HIGH)
- **Location**: `app/controllers/admin/users_controller.rb:90`
- **Description**: The `user_params` method permits the `:admin` attribute, allowing admins to elevate other users to admin status. While this is in an admin controller, there's no additional confirmation or audit logging.
- **Code**: `params.require(:user).permit(:email, :admin)`
- **Remediation**: Add audit logging for admin privilege changes and require re-authentication for privilege escalation

##### AUTH-005: CSRF Token Skip on SSO Callbacks (LOW)
- **Location**: `app/controllers/users/omniauth_callbacks_controller.rb:3`
- **Description**: CSRF verification is skipped for SAML and OIDC callbacks. This is necessary for SSO but should be documented and the SSO response signature should be strictly validated.
- **Code**: `skip_before_action :verify_authenticity_token, only: [:saml, :openid_connect]`
- **Status**: Acceptable - standard SSO practice, and OmniAuth validates signatures

##### AUTH-006: Session Management Good Practices (INFO - Positive)
- **Location**: `config/initializers/security.rb:66-71`
- **Description**: Session cookies are properly configured with:
  - `secure: Rails.env.production?`
  - `httponly: true`
  - `same_site: :lax`
  - `expire_after: 24.hours`
- **Status**: Meets security best practices

##### AUTH-007: Password Configuration (INFO - Positive)
- **Location**: `config/initializers/devise.rb:130,185`
- **Description**: Password hashing uses bcrypt with 12 stretches (1 in test). Password length requirement is 6-128 characters.
- **Note**: Minimum password length of 6 is low by modern standards (recommend 8-12 minimum)

##### AUTH-008: Organization-Level Authorization Working Correctly (INFO - Positive)
- **Location**: `app/controllers/organizations_controller.rb:4-5`
- **Description**: Proper authorization checks:
  - `ensure_organization_member` - checks user belongs to org
  - `ensure_can_manage` - checks owner/admin role for management actions
- **Status**: Well implemented

##### AUTH-009: MCP API Key Authentication (MEDIUM)
- **Location**: `app/controllers/mcp_controller.rb:160-172`
- **Description**: MCP API key lookup is performed in constant time via `find_by`, but there's no rate limiting on API key validation attempts.
- **Remediation**: Add rate limiting for MCP authentication failures

### V6-004: Injection Vulnerabilities
*To be completed*

### V6-005: Data Exposure and Secrets
*To be completed*

### V6-006: Code Quality - Architecture
*To be completed*

### V6-007: Code Quality - Performance
*To be completed*

### V6-008: Frontend UX Audit
*To be completed*

---

## Fixes Applied

### V6-009: Security Patches
*To be completed*

---

## Recommendations

*To be completed*

---

## Appendix

### A. Tools Used
- Consensys v0.1.0 (AI-powered code review)
- Consensys RedTeam (exploit generation)
- Consensys DNA (codebase fingerprinting)
- MCP Playwright (frontend testing)

### B. Files Reviewed
*To be populated during audit*

### C. Test Results
*To be populated during audit*
