# 🏔️ Guides Nepal Mobile
> A modern, open-source travel platform connecting independent travelers with local guides across Nepal. Discover curated experiences in Kathmandu, Pokhara, Lalitpur, Bhaktapur, and Bharatpur — book adventures, chat with an AI travel assistant, and manage your journey all in one place.
[![GitHub contributors](https://img.shields.io/github/contributors/aum010/Guides-Nepal-Mobile?style=for-the-badge)](https://github.com/aum010/Guides-Nepal-Mobile/graphs/contributors)
[![GitHub stars](https://img.shields.io/github/stars/aum010/Guides-Nepal-Mobile?style=for-the-badge)](https://github.com/aum010/Guides-Nepal-Mobile/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/aum010/Guides-Nepal-Mobile?style=for-the-badge)](https://github.com/aum010/Guides-Nepal-Mobile/network/members)
[![GitHub issues](https://img.shields.io/github/issues/aum010/Guides-Nepal-Mobile?style=for-the-badge)](https://github.com/aum010/Guides-Nepal-Mobile/issues)
[![GitHub license](https://img.shields.io/github/license/aum010/Guides-Nepal-Mobile?style=for-the-badge)](./LICENSE)
[![Frontend: React](https://img.shields.io/badge/Frontend-React%2018-61DAFB?style=for-the-badge&logo=react&logoColor=white)](./frontend)
[![Backend: FastAPI](https://img.shields.io/badge/Backend-FastAPI-009688?style=for-the-badge&logo=fastapi)](./backend)
[![Mobile: Flutter](https://img.shields.io/badge/Mobile-Flutter-02569B?style=for-the-badge&logo=flutter)](./mobile)
---
## 📖 Table of Contents
- [Overview](#-overview)
- [✨ Key Features](#-key-features)
- [📱 Mobile App](#-mobile-app)
- [🛠 Tech Stack](#-tech-stack)
- [📂 Project Structure](#-project-structure)
- [🚀 Quick Start](#-quick-start)
- [⚙️ Environment Variables](#%EF%B8%8F-environment-variables)
- [🔐 User Roles & Permissions](#-user-roles--permissions)
- [🔑 Seed Credentials](#-seed-credentials)
- [🌐 API Endpoints](#-api-endpoints)
- [🗄 Database Schema](#-database-schema)
- [📦 Deployment](#-deployment)
- [🤝 Contributing](#-contributing)
- [🔒 Security](#-security)
- [📚 Documentation Map](#-documentation-map)
- [📄 License](#-license)
---
## 🏔️ Overview
**Guides Nepal** is a complete travel and experiences marketplace for Nepal. It empowers independent travelers to discover and book authentic local experiences while giving local guides and hosts the tools to manage listings, bookings, and availability.
The platform consists of:
| Component | Description | Tech |
|-----------|-------------|------|
| **Frontend** | Public traveler site — explore cities, browse experiences, book trips, chat with AI | React 18 + Vite + Tailwind CSS |
| **Dashboard** | Admin/host console with 5 role-based consoles | React + Vite |
| **Backend** | RESTful API, authentication, bookings, AI chat, RBAC | Python + FastAPI + SQLAlchemy |
| **Mobile** | Flutter mobile app for travelers and guides | Flutter / Dart |
| **Database** | SQLite (dev) / PostgreSQL (prod) via Supabase | SQLAlchemy + Alembic |
Supported cities: **Kathmandu** • **Pokhara** • **Lalitpur** • **Bhaktapur** • **Bharatpur**
---
## ✨ Key Features
### For Travelers
- 🔍 **Advanced Search & Discovery** — Filter experiences by city, category, price range, difficulty, and sort by popularity/rating/price
- 🏛️ **5 Nepal Cities** — Dedicated pages for Kathmandu, Pokhara, Lalitpur, Bhaktapur, and Bharatpur
- 📖 **Experience Categories** — Cultural tours, food tours, cooking classes, outdoor activities, wellness, trekking, and more
- 🤖 **Maila Dai AI Assistant** — Kathmandu-aware AI chat with live weather, local time (UTC+5:45), food recommendations, and adventure ideas
- 🔐 **Secure Authentication** — JWT + OAuth (Google, Facebook), bcrypt password hashing
- 🔖 **Bookmarks & Profiles** — Save favorite experiences, manage bookings, upload avatar photos
### For Guides
- 📋 **Guide Dashboard** — Live stats, booking requests (accept/decline/complete), capacity overview
- 📝 **Listing Management** — Create, edit, and publish experiences with max-guest capacity controls
- 📢 **Real-Time Updates** — Post availability, capacity, booking, schedule, and announcement updates
- 🎯 **Onboarding Wizard** — 4-step setup: expertise areas, cities/languages, profile, capacity
### For Hosts
- 📝 **Host Application Wizard** — 5-step application with document upload and auto-save
- 🏠 **Host Center** — Resource hub with getting started, pricing, community, and safety guides
- 📊 **Host Dashboard** — Manage tours, bookings, earnings, and performance metrics
### For Admins & Staff
- 👨‍💼 **5 Role-Based Consoles** — Admin, Content Manager, Regional Head, Customer Support, Host
- 📊 **Analytics & Revenue** — Platform intelligence and revenue reporting
- 🎫 **Support Ticket System** — Full customer support workflow
- 🔒 **Role-Based Access Control (RBAC)** — Server-side enforced permissions
---
## 📱 Mobile App
The `mobile/` directory contains the **Flutter** companion app for Guides Nepal, giving travelers and guides a native mobile experience:
- 📲 Browse and book experiences on the go
- 🤖 Chat with Maila Dai AI assistant
- 📋 Guide dashboard for managing bookings and listings
- 🔐 Secure login for travelers and guides
- 📍 City-specific experience exploration
### Mobile Tech
- **Framework:** Flutter (Dart)
- **Platforms:** Android, iOS
- **State Management:** Provider / Riverpod
- **API Client:** Dio / HTTP
See `mobile/README.md` for mobile-specific setup instructions.
---
## 🛠 Tech Stack
| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Frontend** | React 18, TypeScript, Vite, Tailwind CSS | Public traveler UI |
| **Dashboard** | React, TypeScript, Vite | Admin/host consoles |
| **Mobile** | Flutter, Dart | Native mobile app |
| **Backend** | Python, FastAPI, SQLAlchemy, Alembic | REST API, business logic |
| **Database** | SQLite (dev) / PostgreSQL (prod) | Data persistence |
| **AI** | Ollama (local) / OpenAI | Maila Dai chat assistant |
| **Auth** | JWT (bcrypt), OAuth 2.0 (Google, Facebook) | Authentication & authorization |
| **Deployment** | Vercel (frontend/dashboard), Render (backend) | Cloud hosting |
| **Cache/Queue** | Supabase (password reset) | Email & real-time
---
## 📂 Project Structure
```
Guides-Nepal-Mobile/
├── 📁 frontend/              # React + Vite + TypeScript traveler site
│   ├── src/
│   │   ├── components/       # Reusable UI components
│   │   ├── pages/            # Page components (auth, host, user, guide, city)
│   │   ├── contexts/         # React contexts (Currency, Cart)
│   │   ├── services/         # API service layer
│   │   ├── hooks/            # Custom React hooks
│   │   ├── utils/            # Utility functions (search index, analytics)
│   │   ├── config/           # API configuration
│   │   └── data/             # Static data files
├── 📁 dashboard/             # Admin dashboard (React + Vite)
│   ├── src/
│   │   ├── admin/            # Admin console pages
│   │   ├── regionalhead/     # Regional head console
│   │   ├── support/          # Customer support console
│   │   ├── host/             # Host console
│   │   ├── writer/           # Content manager console
│   │   ├── auth/             # Authentication
│   │   ├── layouts/          # Layout components
│   │   └── guards/           # Auth role guards
├── 📁 backend/               # FastAPI backend API
│   ├── app/
│   │   ├── api/v1/           # API route modules
│   │   ├── models/           # SQLAlchemy database models
│   │   ├── core/             # Config, database, security, RBAC roles
│   │   ├── schemas/          # Pydantic request/response schemas
│   │   └── services/         # Business logic services
│   ├── tests/                # pytest test suite
│   ├── migrations/           # Alembic database migrations
│   ├── seed_credentials.py   # Dev seed: dashboard staff accounts
│   ├── seed_traveler_guide.py # Dev seed: traveler + guide test accounts
│   └── seed_host_dashboard.py # Host dashboard seed data
├── 📁 mobile/                # Flutter mobile application
├── 📁 docs/                  # Architecture and development docs
├── 📁 documents/             # PRD and technical architecture
├── 📁 scripts/               # Utility scripts
├── 🐳 docker-compose.yml     # Local Docker stack
├── 📜 start-all.bat          # Start all services (Windows)
├── 📜 start-all.sh           # Start all services (macOS/Linux)
└── 📄 README.md              # This file
```
---

## 🚀 Quick Start

### Prerequisites

- **Node.js** 18+ and **npm** 8+
- **Python** 3.9+
- **SQLite 3+** (development) or **PostgreSQL 12+** (production)
- **Git**

### Option 1: Start All Services (Recommended)

**Windows:**
`cmd
start-all.bat
`

**macOS / Linux:**
`ash
./start-all.sh
`

### Option 2: Start Individual Services

**Frontend** (port 5175):
`ash
cd frontend
npm install
npm run dev -- --port 5175 --host
`

**Backend** (port 8000):
`ash
cd backend
# Create and activate virtual environment
python -m venv .venv
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
`

**Dashboard** (port 5176):
`ash
cd dashboard
npm install
npm run dev -- --port 5176 --host
`

### Access Points

| Service | URL |
|---------|-----|
| Frontend (Traveler Site) | http://localhost:5175 |
| Dashboard (Admin Console) | http://localhost:5176 |
| Backend API | http://localhost:8000 |
| API Docs (Swagger) | http://localhost:8000/api/v1/docs |
| API ReDoc | http://localhost:8000/api/v1/redoc
### 🔑 Default Login Credentials

After seeding the database, use these pre-configured accounts:

| Role | Email | Password | Access |
|------|-------|----------|--------|
| Admin | dmin@guides-nepal.com | Admin@12345 | Full dashboard |
| Content Manager | content@guides-nepal.com | Content@2024 | Content console |
| Regional Head | egional@guides-nepal.com | Regional@2024 | Regional console |
| Customer Support | support@guides-nepal.com | Support@2024 | Support console |
| Host | host@guides-nepal.com | Host@2024 | Host console |
| Traveler | 	raveler@guides-nepal.com | Traveler@2024 | Public frontend only |
| Guide | guide@guides-nepal.com | Guide@2024 | Public frontend only

> ⚠️ **Security Notice:** These are development-only credentials. Change all default passwords before deploying to production.

Run cd backend && python seed_credentials.py to create staff accounts, or python seed_traveler_guide.py for traveler/guide test accounts.

---

## ⚙️ Environment Variables

### Frontend (.env.local)

`ash
VITE_API_URL=http://localhost:8000/api/v1
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=your-publishable-key
`

### Backend (ackend/.env)

`ash
# Environment
ENV=development
LOG_LEVEL=INFO

# Database
DATABASE_URL=sqlite:///./guides_nepal.db
# Production: DATABASE_URL=postgresql://user:password@localhost:5432/guides_nepal

# Server
BACKEND_HOST=0.0.0.0
BACKEND_PORT=8000
BACKEND_CORS_ORIGINS=http://localhost:5175,http://localhost:5176

# Security
SECRET_KEY=your-secret-key-change-in-production
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=7
UPLOADS_DIR=./uploads

# Dev Seeding
DEV_ALLOW_SEED=true
DEV_SEED_ADMIN_EMAIL=admin@guides-nepal.com
DEV_SEED_ADMIN_PASSWORD=Admin@12345

# OAuth (Optional)
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GOOGLE_REDIRECT_URI=http://localhost:8000/api/v1/auth/oauth/google/callback
FACEBOOK_CLIENT_ID=
FACEBOOK_CLIENT_SECRET=
FACEBOOK_REDIRECT_URI=http://localhost:8000/api/v1/auth/oauth/facebook/callback
FRONTEND_OAUTH_REDIRECT=http://localhost:5175

# AI (Optional)
AI_PROVIDER=auto
OLLAMA_URL=http://localhost:11434
OLLAMA_MODEL=llama3.2:latest
OPENAI_API_KEY=

# Supabase (Password Reset)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
RESET_PASSWORD_REDIRECT_URL=http://localhost:5175/reset-password
`

> 🔒 Never commit .env files or secrets to version control.

---

## 🔐 User Roles & Permissions

Guides Nepal uses a comprehensive **Role-Based Access Control (RBAC)** system with 7 roles across dashboard and public frontend.

### Role Hierarchy

`
┌─────────────────────────────────────────────┐
│              ADMIN (Top Level)              │
│  Full system access — users, content,       │
│  analytics, revenue, role hierarchy         │
└──────────────┬──────────────────────────────┘
               ├── Content Manager
               ├── Regional Head (by region)
               ├── Customer Support
               └── Host

NON-DASHBOARD ROLES (public frontend only):
├── Guide    → /guide/dashboard (no staff console)
└── Traveler → Public site browsing & bookings
`

### Role Permissions Matrix

| Role | Dashboard Access | Key Permissions |
|------|-----------------|-----------------|
| **Admin** | /dashboard/admin/* | Full system: users, hosts, guides, content, tickets, analytics, revenue, roles |
| **Content Manager** | /dashboard/content-manager/* | Pages, blog posts, guides content, media, SEO |
| **Regional Head** | /dashboard/regional-head/* | Host applications for assigned region, regional info |
| **Customer Support** | /dashboard/customer-support/* | Support tickets, FAQ management |
| **Host** | /dashboard/host/* | Tours, bookings, earnings, performance |
| **Guide** | ❌ None (public frontend only) | /guide/dashboard — listings, bookings, real-time updates |
| **Traveler** | ❌ None (public site only) | Browse, book, profile, favorites, chat |

### Dashboard Routes by Role

#### 👑 Admin Console
- /admin — Admin overview
- /admin/platform — Platform-wide overview
- /admin/hosts — Manage hosts
- /admin/guides — Manage guides
- /admin/host-applications — Review host applications
- /admin/support-tickets — View all support tickets
- /admin/hierarchy — Role hierarchy
- /admin/intelligence — Platform intelligence
- /admin/analytics — Analytics dashboard
- /admin/revenue — Revenue reports
- /admin/settings — System settings
- /admin/content — Content management

#### 🏔️ Regional Head Console
- /regional-head — Regional overview
- /regional-head/applications — Host applications (region-specific)
- /regional-head/region — Regional information

#### 🎧 Customer Support Console
- /customer-support — Support overview
- /customer-support/tickets — Support tickets
- /customer-support/faq — FAQ management

#### ✍️ Content Manager Console
- /content-manager — Content overview
- /content-manager/pages — Manage pages
- /content-manager/blog — Blog management
- /content-manager/guides-content — Guides content
- /content-manager/media — Media library
- /content-manager/seo — SEO settings

#### 🏠 Host Console
- /host — Host overview
- /host/guides — Manage guide profiles
- /host/tours — Manage tours
- /host/bookings — View bookings
- /host/earnings — Earnings dashboard
- /host/performance — Performance metrics

#### 🧑‍💼 Guide Dashboard (Public Frontend)
- /guide/dashboard — Live stats, booking requests, capacity overview
- /guide/onboarding — 4-step onboarding wizard
- /guide/listings — Manage own listings
- /guide/listings/new — Create new listing
- /guide/listings/:id/edit — Edit listing
- /guide/bookings — Full booking request list

### Role Assignment During Registration

Self-registration is server-side allow-listed to 	raveler and host only. Elevated roles (guide, dmin, content-manager, egional-head, customer-support) are granted by an admin via PATCH /api/v1/admin/users/{id} or by the seed scripts.

---

## 🌐 API Endpoints

Base path: /api/v1

| Endpoint Group | Routes | Description |
|---------------|--------|-------------|
| **Authentication** | /api/v1/auth/* | Login, register, OAuth (Google/Facebook), password reset |
| **Bookings** | /api/v1/bookings/* | Create, view, accept/reject/complete bookings |
| **Profile** | /api/v1/profile/* | User profile, avatar, bookmarks, settings |
| **AI Chat** | /api/v1/ai/chat / /api/v1/ai/chat/stream | Maila Dai AI assistant (non-streaming & streaming) |
| **Admin** | /api/v1/admin/* | User management, role assignment, analytics |
| **Content** | /api/v1/content/* | Pages, blog, media, SEO |
| **Operations** | /api/v1/operations/* | Platform operations |
| **Host** | /api/v1/host/* | Host tours, bookings, earnings |
| **Guide** | /api/v1/guide/* | Guide dashboard, listings, onboarding, updates |
| **Host Applications** | /api/v1/host-applications/* | Host application submission & review |

View the interactive API documentation at http://localhost:8000/api/v1/docs when the backend is running.

---

## 🗄 Database Schema (Users Table)

| Field | Type | Description |
|-------|------|-------------|
| id | Integer | Primary key |
| email | String | Unique, indexed, required |
| irstName | String | Optional |
| lastName | String | Optional |
| hashed_password | String | Required, bcrypt hash |
| phone | String | Optional |
| ole | String | Default: 	raveler (server-side allow-listed) |
| egion | String | For regional heads (e.g., "Kathmandu Valley") |
| io | String | User biography |
| vatar_url | String | Profile image URL |
| is_active | Boolean | Default: 	rue |
| created_at | DateTime | Auto-generated |
| updated_at | DateTime | Auto-updated

---

## 📦 Deployment

Full deployment instructions are in [DEPLOYMENT.md](./DEPLOYMENT.md).

### Deployment Targets

| Service | Platform | Build Command | Output |
|---------|----------|---------------|--------|
| **Frontend** | Vercel | 
pm run build | dist/ |
| **Dashboard** | Vercel (separate project) | 
pm run build | dist/ |
| **Backend** | Render | Dockerfile | Container |
| **Database** | Supabase PostgreSQL | — | —

### Docker (Local)

`ash
docker-compose up -d
`

Starts database, backend, frontend, and dashboard locally.

---

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. **Fork** the repository
2. **Create a feature branch:** git checkout -b feature/your-feature-name
3. **Make your changes** and commit with conventional commits (e.g., eat:, ix:, docs:)
4. **Push to your fork:** git push origin feature/your-feature-name
5. **Open a Pull Request** against main

### Code Quality

`ash
# Frontend linting & type checking
npm run lint
npm run typecheck

# Backend checks
cd backend
./scripts/run_checks.sh
`

### Testing

| Command | Scope |
|---------|-------|
| 
pm test | Full test suite |
| 
pm run test:frontend | Frontend (Vitest) |
| 
pm run test:backend | Backend (pytest) |
| 
pm run test:dashboard | Dashboard (Vitest) |
| 
pm run test:e2e | End-to-end (Playwright)

---

## 🔒 Security

For the complete security implementation and pre-deployment checklist, see [SECURITY.md](./SECURITY.md).

### Key Security Features

- 🔐 **Password Hashing** — bcrypt for all user passwords
- 🎫 **JWT Authentication** — Configurable expiration (30 min access, 7 days refresh)
- 🛡️ **RBAC Enforcement** — Server-side role allow-lists; self-registration clamped to 	raveler/host
- 🚫 **No Secret Commits** — .env files never committed; production hard-fails on default SECRET_KEY
- 🔐 **Role Checks in API Layer** — equire_role enforced server-side, not just in UI
- 🌐 **CORS & HTTPS** — Production requires HTTPS origins

---

## 📚 Documentation Map

| Document | Description |
|----------|-------------|
| [DEPLOYMENT.md](./DEPLOYMENT.md) | Vercel / Render / Supabase / Docker deployment |
| [SECURITY.md](./SECURITY.md) | Security implementation & pre-deployment checklist |
| [docs/](./docs/) | Architecture, folder structure, development setup, API docs |
| [dashboard/docs/](./dashboard/docs/) | Dashboard roles, routing, permissions, UX |
| [ackend/docs/](./backend/docs/) | Backend guides and API contract |
| [documents/](./documents/) | PRD and technical architecture

---

## 📄 License

This project is licensed under the **MIT License**. See the [LICENSE](./LICENSE) file for details.

---

<div align="center">

**Built with ❤️ for travelers and local guides in Nepal**

[⭐ Star this repo](https://github.com/aum010/Guides-Nepal-Mobile/stargazers) • [🍴 Fork it](https://github.com/aum010/Guides-Nepal-Mobile/fork) • [🐛 Report an issue](https://github.com/aum010/Guides-Nepal-Mobile/issues)

</div>

**Last updated:** 2026-10-08  
**Version:** 1.3.0
