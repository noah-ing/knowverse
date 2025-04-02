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

4. **Background Job Processing**
   - Uses SolidQueue (Rails 8's built-in job system)
   - Queues configured in development and production environments
   - MagicLinkMailerJob for handling async email delivery
   - Redis as the backing store for job queues

5. **Frontend Architecture**
   - Hotwire (Turbo + Stimulus) for modern, reactive interfaces without heavy JavaScript
   - TailwindCSS v4 for styling
   - Minimal JavaScript with progressive enhancement
   - Stripe Elements integration for secure payment form handling

6. **Deployment Architecture**
   - Infrastructure-as-code through Render configuration (.render.yaml)
   - Web service for the main application
   - Worker service for background job processing
   - PostgreSQL database
   - Redis service for job queues and caching
   - Web service deployed via GitHub Actions CI/CD
   - Environment variables for Stripe configuration

7. **Admin System**
   - Role-based access control with admin flag on User model
   - Admin-specific layout and navigation
   - Dashboard with key system metrics and stats
   - Complete user management interface
   - Subscription management capabilities for admin users
   - User search with pagination via Kaminari
   - Command-line utilities for admin user management
   - RESTful controllers for different admin functions

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
