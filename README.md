<div align="center">
  <img src="public/icon.svg" alt="Gold SaaS Boilerplate" width="150" height="150">
  <h1>Gold SaaS Boilerplate</h1>
  <p>A production-ready Rails 8 SaaS starter kit with all the gold standard features.</p>
  
  <div>
    <img src="https://img.shields.io/badge/Rails-8.0.2-red.svg" alt="Rails 8.0.2">
    <img src="https://img.shields.io/badge/Ruby-3.2.2-red.svg" alt="Ruby 3.2.2">
    <img src="https://img.shields.io/badge/PostgreSQL-Latest-blue.svg" alt="PostgreSQL">
    <img src="https://img.shields.io/badge/TailwindCSS-4.0.17-blue.svg" alt="TailwindCSS">
    <img src="https://img.shields.io/badge/Hotwire-latest-blue.svg" alt="Hotwire">
    <img src="https://img.shields.io/badge/Stripe-integrated-success.svg" alt="Stripe">
    <img src="https://img.shields.io/badge/Tests-RSpec-green.svg" alt="RSpec">
    <img src="https://img.shields.io/badge/Deploy-Render-purple.svg" alt="Render">
    <img src="https://img.shields.io/badge/Analytics-Ahoy-orange.svg" alt="Ahoy">
  </div>
</div>

## 📚 Table of Contents

- [✨ Features](#-features)
- [🖼️ Screenshots](#-screenshots)
- [🚀 Getting Started](#-getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
  - [Development](#development)
  - [Testing](#testing)
- [🔧 Configuration](#-configuration)
  - [Environment Variables](#environment-variables)
  - [Email Setup](#email-setup)
  - [Stripe Setup](#stripe-setup)
- [🏗️ Architecture](#-architecture)
- [🔒 Authentication](#-authentication)
- [💰 Subscription Management](#-subscription-management)
- [👤 User Management](#-user-management)
- [📊 Analytics](#-analytics)
- [🧪 Testing](#-testing)
- [🚢 Deployment](#-deployment)
- [⚡ Performance](#-performance)
- [🔄 Background Jobs](#-background-jobs)
- [🔌 API](#-api)
- [⚖️ License](#-license)

## ✨ Features

Gold SaaS Boilerplate provides everything you need to launch your SaaS product quickly:

### Core Features

- **Magic Link Authentication** - Passwordless login via email
- **Subscription Management** - Complete Stripe integration with tiered plans
- **User Profiles** - User settings, preferences and avatars
- **Admin Dashboard** - User management, metrics, and analytics
- **Analytics** - Track user behavior, subscriptions, and application usage
- **Responsive Design** - Mobile-friendly UI with Tailwind CSS
- **Background Jobs** - Asynchronous processing with SolidQueue
- **Email Delivery** - Reliable email delivery with Resend
- **Testing Framework** - Comprehensive testing with RSpec and FactoryBot
- **Deployment Configuration** - Ready for Render deployment

### Technical Stack

- **Frontend**: TailwindCSS 4, Hotwire (Turbo + Stimulus), Alpine.js
- **Backend**: Ruby 3.2.2, Rails 8.0.2
- **Database**: PostgreSQL
- **Caching/Jobs**: Redis, Solid Queue
- **Email**: Resend
- **File Storage**: Active Storage
- **Payments**: Stripe
- **Authentication**: Devise with passwordless extension
- **Analytics**: Ahoy, Groupdate, Chartkick
- **Testing**: RSpec, FactoryBot, Capybara
- **CI/CD**: Ready for GitHub Actions

## 🖼️ Screenshots

<div align="center">
  <img src="public/screenshot1.png" alt="Dashboard" width="600">
  <p><em>Dashboard and Subscription Management</em></p>
  
  <img src="public/screenshot2.png" alt="Admin" width="600">
  <p><em>Admin Dashboard and Analytics</em></p>
</div>

## 🚀 Getting Started

### Prerequisites

- Ruby 3.2.2
- PostgreSQL 13+
- Redis 6+
- Node.js 18+
- Yarn 1.22+
- A Stripe account for subscription handling
- A Resend account for email delivery

### Installation

1. Clone the repository

```bash
git clone https://github.com/yourusername/gold-saas-bp.git
cd gold-saas-bp
```

2. Install dependencies

```bash
bundle install
yarn install
```

3. Create a `.env` file at the root of the project with:

```
# Resend API key (required for email delivery)
RESEND_API_KEY=your_resend_api_key

# Stripe API keys (required for subscription handling)
STRIPE_PUBLISHABLE_KEY=your_stripe_publishable_key
STRIPE_SECRET_KEY=your_stripe_secret_key
STRIPE_WEBHOOK_SECRET=your_stripe_webhook_secret

# Host configuration
APP_HOST=localhost:3000
```

4. Setup the database

```bash
bin/rails db:setup
```

5. Verify the installation

```bash
bin/rails boilerplate:verify
```

### Development

Start the Rails server, CSS watcher, and job processor:

```bash
bin/dev
```

Your application should now be running at `http://localhost:3000`.

### Testing

Run the test suite:

```bash
bundle exec rspec
```

## 🔧 Configuration

### Environment Variables

The following environment variables are required:

| Variable | Description |
|----------|-------------|
| `RESEND_API_KEY` | API key for Resend (email delivery) |
| `STRIPE_PUBLISHABLE_KEY` | Publishable key from Stripe |
| `STRIPE_SECRET_KEY` | Secret key from Stripe |
| `STRIPE_WEBHOOK_SECRET` | Webhook signing secret from Stripe |
| `APP_HOST` | Application host (i.e., `localhost:3000` in development) |
| `RAILS_MASTER_KEY` | Rails master key for credentials (in production) |

### Email Setup

1. Create an account on [Resend](https://resend.com)
2. Obtain your API key
3. Add it to your `.env` file as `RESEND_API_KEY`
4. Configure a verified domain in Resend dashboard
5. Update the mailer sender in `config/initializers/devise.rb`

### Stripe Setup

1. Create an account on [Stripe](https://stripe.com)
2. Obtain API keys from the Stripe dashboard
3. Add them to your `.env` file as shown above
4. Create products/prices in Stripe that match your plans
5. Update the plan seeds in `db/seeds/plans.rb` with your Stripe price IDs

## 🏗️ Architecture

Gold SaaS Boilerplate follows a traditional Rails architecture with modern enhancements:

- **MVC Pattern** - Standard Model-View-Controller architecture
- **Namespaced Controllers** - Organized by resource type
- **Service Objects** - For complex business logic
- **Background Jobs** - For asynchronous processing
- **Progressive Enhancement** - Core functionality works without JavaScript

### Directory Structure Highlights

- `/app/controllers/admin` - Admin controllers
- `/app/controllers/users` - User profile controllers
- `/app/controllers/subscriptions` - Subscription controllers
- `/app/views/` - View templates organized by controller
- `/app/models/` - Application models
- `/app/jobs/` - Background jobs
- `/config/initializers/` - Configuration files
- `/db/migrate/` - Database migrations
- `/spec/` - Test files

## 🔒 Authentication

Authentication is handled via passwordless magic links:

1. User enters their email address
2. A magic link is sent to their email
3. Clicking the link logs them in securely

Benefits:

- No password management or storage
- Increased security
- Simplified user experience

## 💰 Subscription Management

The boilerplate includes a complete subscription management system powered by Stripe:

- Tiered pricing plans (Basic, Plus, Premium, Enterprise)
- Free trials with automatic expiration
- Subscription lifecycle management
- Payment method management
- Webhook handling for payment events

Users can:

- View available plans
- Subscribe to a plan
- Upgrade/downgrade between plans
- Cancel/resume subscriptions
- Manage payment methods

## 👤 User Management

Comprehensive user profile management:

- Profile editing (name, avatar)
- Notification preferences
- Account management
- Subscription details
- Usage statistics

Admins can:

- View all users
- Search for specific users
- Edit user details
- Manage subscriptions
- Activate/deactivate accounts
- Send magic links
- View user analytics

## 📊 Analytics

Built-in analytics powered by Ahoy:

- Page view tracking
- Event tracking
- User session tracking
- Subscription changes
- User behavior analysis

The admin analytics dashboard provides insights on:

- User growth
- Subscription metrics
- Activity patterns
- Revenue metrics
- Conversion rates

## 🧪 Testing

Comprehensive testing suite with:

- Model tests (validations, methods)
- Controller tests (actions, responses)
- Integration tests (workflows)
- System tests (UI interactions)

The test suite covers:

- Authentication flow
- Subscription management
- User profile updates
- Admin functionality
- Analytics tracking

## 🚢 Deployment

The boilerplate is configured for deployment on Render:

1. Create a new Web Service on Render
2. Connect to your GitHub repository
3. Set the required environment variables
4. Use the build command: `bin/render-build.sh`
5. Set the start command: `bundle exec puma -C config/puma.rb`

See `.render.yaml` for the complete configuration.

## ⚡ Performance

Performance optimizations include:

- Background job processing
- Redis caching
- Database indexing
- Asset optimization
- Conditional rendering

## 🔄 Background Jobs

Background job processing is handled by SolidQueue:

- Email delivery
- Webhook processing
- Data processing
- Scheduled tasks

## 🔌 API

The boilerplate doesn't include a public API by default, but you can easily add one using Rails API controllers and JSON serialization.

## ⚖️ License

This project is licensed under the MIT License - see the LICENSE file for details.
