# Technical Context

## Technologies used

### Backend
- Ruby 3.2.2
- Rails 8.0.2
- PostgreSQL (database)
- Redis (key-value store for job queues and caching)
- Devise (authentication framework)
- devise-passwordless (magic link extension)
- Resend (email delivery service)
- Stripe (payment processing and subscription management)
- Pay (Stripe integration helper)
- Solid Cache (caching)
- Solid Queue (background jobs)
- Kaminari (pagination for admin interfaces)
- Active Storage (file attachments and image processing)
- Ahoy (analytics tracking)
- Groupdate (time-based data grouping)
- Chartkick (chart generation)

### Frontend
- Hotwire (Turbo + Stimulus)
- TailwindCSS v4.0.17
- Alpine.js (interactive components)
- Stripe Elements (payment UI)
- Responsive design patterns

### Testing
- RSpec (test framework)
- FactoryBot (test data generation)
- Capybara (system testing)
- Shoulda Matchers (test helpers)
- VCR (API mocking)
- WebMock (HTTP stub)
- Database Cleaner (test isolation)

### DevOps & Infrastructure
- Render (cloud hosting platform)
- GitHub Actions (CI/CD)
- Docker (containerization)
- dotenv-rails (environment variable management)
- System verification tools

## Development setup
1. Clone repository
2. Install Ruby 3.2.2 (recommended via rbenv or asdf)
3. Install PostgreSQL and Redis locally
4. Set up `.env` file with required environment variables:
   - `RESEND_API_KEY` for email delivery
   - `STRIPE_PUBLISHABLE_KEY` for Stripe Elements integration
   - `STRIPE_SECRET_KEY` for Stripe API interactions
   - `STRIPE_WEBHOOK_SECRET` for webhook signature verification
5. Run `bundle install` to install dependencies
6. Run `bin/rails db:setup` to create database and run migrations
7. Start the development server with `bin/dev` which uses Foreman via Procfile.dev

## Technical constraints
1. **Email Delivery**
   - Requires a valid Resend API key
   - Emails must work identically in development and production
   - From email address must use a verified domain on Resend
   - Login token generation follows specific format expected by devise-passwordless
   - Test tools available via rake tasks for debugging delivery issues

2. **Authentication**
   - Magic link authentication requires working email delivery
   - Login tokens expire after 15 minutes
   - No standard password authentication available

3. **Deployment**
   - Requires setting `RAILS_MASTER_KEY` in Render environment
   - Render's asset pipeline needs specific configuration for Tailwind v4
   - Background jobs require a separate paid worker instance on Render

4. **Database**
   - Uses PostgreSQL-specific features, not database-agnostic
   - Migrations should be backward-compatible for zero-downtime deployments
   - JSONB column for notification preferences (PostgreSQL-specific)
   - Active Storage tables for avatar storage

5. **Payment Processing**
   - Requires Stripe API keys for testing and production
   - Webhook endpoint must be configured for payment event handling
   - Uses PostgreSQL array columns for plan features storage
   - Subscription statuses tracked in user model
   - Stripe price IDs in the seeds file need to be replaced with actual Stripe product IDs

6. **Performance**
   - Email sending is handled asynchronously via background jobs
   - No CDN configuration yet for assets
   - Image processing for avatars is done synchronously (could be moved to background jobs)

7. **User Profiles**
   - Avatar upload requires Active Storage configuration
   - Notification preferences stored in JSONB column for flexibility
   - Profile data is extended from core user model
   - Namespaced controllers for organization (Users::ProfilesController, etc.)
   - Route structure follows RESTful conventions for all profile-related functionality
