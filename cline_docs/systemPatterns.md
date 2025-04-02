# System Patterns

## How the system is built
The Gold SaaS Boilerplate follows a standard Rails MVC architecture with modern enhancements:

1. **Authentication System**
   - Uses Devise as the core authentication framework
   - Extends with devise-passwordless for magic link login functionality
   - Magic links are generated and sent via email
   - No password storage or management required
   - Complete token validation and user sign-in flow

2. **Email Delivery Flow**
   - Uses Resend.com as the email delivery service
   - ActionMailer configured with Resend as the delivery method
   - Comprehensive error handling and logging for delivery issues
   - Asynchronous email delivery via background jobs
   - UserMailer extends ApplicationMailer for specific email types
   - Template-based email content in app/views/user_mailer/
   - Diagnostics via rake tasks for testing and debugging

3. **Subscription Management System**
   - Stripe integration for payment processing and subscription management
   - Tiered subscription plans (Basic, Plus, Premium, Enterprise)
   - User model extended with subscription status tracking
   - Complete subscription lifecycle handling (trial, active, past_due, canceled)
   - Payment method management with Stripe Elements integration
   - Webhook handling for payment events (success, failure, etc.)
   - PostgreSQL array column for storing plan features

4. **User Profile System**
   - Personal information management with name field and avatar upload
   - Active Storage integration for avatar management and storage
   - Notification preferences using JSONB column with sensible defaults
   - Account settings dashboard with subscription details
   - Usage statistics visualization with dynamic metrics
   - Account deletion workflow with confirmation
   - Namespaced controllers following RESTful principles
   - TailwindCSS-styled responsive interfaces
   - Modular view partials for consistent UI components

5. **Background Job Processing**
   - Uses SolidQueue (Rails 8's built-in job system)
   - Queues configured in development and production environments
   - MagicLinkMailerJob for handling async email delivery
   - Redis as the backing store for job queues

6. **Frontend Architecture**
   - Hotwire (Turbo + Stimulus) for modern, reactive interfaces without heavy JavaScript
   - TailwindCSS v4 for styling
   - Alpine.js for interactive components
   - Minimal JavaScript with progressive enhancement
   - Stripe Elements integration for secure payment form handling
   - Responsive, mobile-first design across all pages

7. **Deployment Architecture**
   - Infrastructure-as-code through Render configuration (.render.yaml)
   - Web service for the main application
   - Worker service for background job processing
   - PostgreSQL database
   - Redis service for job queues and caching
   - Web service deployed via GitHub Actions CI/CD
   - Environment variables for Stripe configuration

8. **Admin System**
   - Role-based access control with admin flag on User model
   - Admin-specific layout and navigation
   - Dashboard with key system metrics and stats
   - Complete user management interface
   - Subscription management capabilities for admin users
   - User search with pagination via Kaminari
   - Command-line utilities for admin user management
   - RESTful controllers for different admin functions

9. **Analytics System**
   - Ahoy for tracking page views and events
   - Automatic visit and visitor tracking
   - User-associated analytics data
   - Custom event tracking for key user actions:
     - Magic link logins
     - Subscription changes (new, update, cancel, resume)
     - Profile updates
   - Admin analytics dashboard with visualizations
   - Groupdate for time-based data aggregation
   - Chartkick for chart rendering
   - User activity tracking and event logs

10. **Testing Framework**
    - RSpec for test-driven development
    - FactoryBot for test data generation
    - Model specs for validating core business logic
    - Controller specs for testing HTTP interactions
    - System specs for end-to-end testing
    - Fixtures and factories for consistent test data
    - Capybara for simulating user interactions
    - WebMock and VCR for external API mocking
    - Comprehensive test coverage for all major components

## Key technical decisions

1. **Password-less Authentication**
   - Improves security by eliminating password storage and management
   - Enhances user experience with simplified login flow
   - Leverages email as a secure identity verification channel

2. **Real Email in Development**
   - Uses the same email delivery service (Resend) in both development and production
   - Eliminates environment-specific bugs by using identical code paths
   - Avoids letter_opener or similar development-only gems to ensure consistency

3. **Containerized Services**
   - All services (web, database, Redis) run in isolated containers
   - Environment parity between development and production
   - Configuration via environment variables for flexibility

4. **User Preferences as JSON**
   - Stores notification preferences in a JSONB column for flexibility
   - Allows easy addition of new preference types without schema changes
   - Provides type-safe access through model methods

5. **RESTful Resource Organization**
   - Controllers organized by resource type and namespace
   - Consistent routing structure for all resources
   - Follows Rails conventions for controller actions and naming

## Architecture patterns

1. **MVC with Service-Oriented Extensions**
   - Standard Model-View-Controller pattern
   - Service objects for complex business logic
   - Background jobs for asynchronous processing

2. **Progressive Enhancement**
   - Core functionality works without JavaScript
   - Enhanced with Hotwire for reactive interfaces
   - Mobile-first, responsive design

3. **Infrastructure as Code**
   - Deployment configuration in version control
   - Environment variables for sensitive configuration
   - CI/CD pipeline for automated testing and deployment

4. **Modular User Interface**
   - Consistent UI components across the application
   - Reusable TailwindCSS utility classes
   - Form patterns with consistent validation display
   - Shared notification and alert components
