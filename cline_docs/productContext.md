# Gold SaaS Boilerplate - Product Context

## Why this project exists
The Gold SaaS Boilerplate (gold-saas-bp) is a production-grade starter kit for rapidly building real SaaS products using Ruby on Rails 8. It exists to eliminate repetitive setup work and configuration for common SaaS needs, allowing developers to focus immediately on building product-specific features.

## What problems it solves
- Eliminates repetitive boilerplate code and configuration for new SaaS projects
- Provides a pre-configured authentication system with magic link login
- Sets up real-world email delivery infrastructure using Resend
- Includes complete Stripe subscription management with tiered pricing plans
- Includes production deployment configuration for Render
- Establishes a solid foundation for scaling with PostgreSQL, Redis, and Sidekiq
- Implements modern frontend with Hotwire (Turbo + Stimulus) and TailwindCSS
- Creates a consistent, tested environment that works identically in development and production

## How it should work
- Developers should be able to clone the repo and have a fully functional SaaS foundation
- Magic link authentication should allow users to sign in without passwords
- Real emails should be delivered in both development and production environments
- The codebase should be clean, maintainable, and follow Rails best practices
- Deployment to Render should be straightforward with minimum configuration
- The application should be easily extensible for specific SaaS use cases (Stripe, analytics, admin dashboards, etc.)
