from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse
from app.core.config import settings
from app.core.database import engine
from app.core.schema import apply_schema
from app.core.storage import UPLOADS_ROOT
from app import models  # noqa: F401  (registers all models on Base.metadata)
from app.core.middleware import (
    SecurityHeadersMiddleware,
    RequestLoggingMiddleware,
    InputValidationMiddleware,
    HTTPSEnforcementMiddleware,
)
from app.api.v1 import (
    auth,
    bookings,
    public,
    ai,
    profile,
    admin,
    content,
    operations,
    host,
    host_guides,
    guide,
    experience_workflow,
    reviews,
    conversations,
)
import os
import logging

logger = logging.getLogger(__name__)

# Initialize FastAPI app with security settings
app = FastAPI(
    title=settings.PROJECT_NAME,
    openapi_url=f"{settings.API_V1_STR}/openapi.json" if settings.DEBUG else None,
    docs_url="/api/v1/docs" if settings.DEBUG else None,
    redoc_url="/api/v1/redoc" if settings.DEBUG else None,
)

# Add security middleware (order matters!)
app.add_middleware(HTTPSEnforcementMiddleware)
app.add_middleware(InputValidationMiddleware)
app.add_middleware(RequestLoggingMiddleware)
app.add_middleware(SecurityHeadersMiddleware)

# Configure CORS with strict settings
cors_origins = settings.cors_origins
logger.info(f"Configured CORS origins: {cors_origins}")

if cors_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=cors_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH"],
        allow_headers=["Content-Type", "Authorization"],
        max_age=600,  # Cache preflight for 10 minutes
    )

# Include routers
app.include_router(
    auth.router, prefix=f"{settings.API_V1_STR}/auth", tags=["authentication"]
)
app.include_router(
    bookings.router, prefix=f"{settings.API_V1_STR}/bookings", tags=["bookings"]
)
app.include_router(
    reviews.router, prefix=f"{settings.API_V1_STR}/reviews", tags=["reviews"]
)
app.include_router(host.router, prefix=settings.API_V1_STR, tags=["host"])
app.include_router(host_guides.router, prefix=settings.API_V1_STR, tags=["host-guides"])
app.include_router(guide.router, prefix=settings.API_V1_STR, tags=["guide"])
app.include_router(
    experience_workflow.router, prefix=settings.API_V1_STR, tags=["experience-workflow"]
)
app.include_router(public.router, prefix=f"{settings.API_V1_STR}", tags=["public"])
app.include_router(ai.router, prefix=f"{settings.API_V1_STR}/ai", tags=["ai"])
app.include_router(
    profile.router, prefix=f"{settings.API_V1_STR}/profile", tags=["profile"]
)
app.include_router(admin.router, prefix=f"{settings.API_V1_STR}/admin", tags=["admin"])
app.include_router(
    content.router, prefix=f"{settings.API_V1_STR}/content", tags=["content"]
)
app.include_router(
    operations.router, prefix=f"{settings.API_V1_STR}/operations", tags=["operations"]
)
app.include_router(
    conversations.router, prefix=f"{settings.API_V1_STR}", tags=["conversations"]
)

# Static file mounting with restrictions. The directory comes from
# ``app.core.storage`` so the path that serves a photo is the path uploads are
# written to — they used to disagree, and every uploaded URL 404'd.
uploads_dir = UPLOADS_ROOT
try:
    os.makedirs(uploads_dir, exist_ok=True)
    app.mount("/uploads", StaticFiles(directory=str(uploads_dir)), name="uploads")
except PermissionError:
    # If uploads dir can't be created, continue without file serving
    # (common in containerized environments with read-only filesystems)
    logger.warning(f"Could not create uploads directory at {uploads_dir}")
except Exception as e:
    logger.warning(f"Could not mount uploads directory: {e}")


def provision_schema() -> None:
    """Bring the database to the schema this code expects — or refuse to start.

    Schema changes come from the Alembic chain rather than
    ``Base.metadata.create_all``, so a deployed database and a migrated one
    cannot drift apart.

    A failure here is **fatal on purpose**. This used to be caught and logged,
    which is worse than crashing: the app booted, ``/health`` answered 200, and
    every query touching a missing column failed with a 500 that looked like an
    application bug rather than a database one. A supervisor (or the person
    running uvicorn) now sees the real error and stops.
    """
    outcome = apply_schema(engine)
    logger.info("Database schema %s (head applied).", outcome)


@app.on_event("startup")
def ensure_database_schema() -> None:
    provision_schema()


@app.get("/")
def root() -> dict:
    """Root endpoint - API info"""
    return {
        "name": settings.PROJECT_NAME,
        "status": "running",
        "api_base": settings.API_V1_STR,
        "health": "/health",
        "docs": settings.API_V1_STR + "/docs" if settings.DEBUG else None,
    }


@app.get("/health")
def health_check() -> dict:
    """Health check endpoint for deployment monitoring"""
    return {"status": "ok", "environment": settings.ENV}


@app.get("/api/v1/health")
def api_health_check() -> dict:
    """API health check endpoint"""
    return {"status": "ok", "version": "1.0"}


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Global exception handler to prevent information leakage"""
    logger.error(f"Unhandled exception: {exc}")
    if settings.DEBUG:
        raise exc
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})
