from typing import Any, List, Optional
import json
import logging
import os
import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_password_hash, validate_password_strength
from app.models.guide import Guide
from app.models.guide_application import GuideApplication
from app.models.host_application import HostApplication
from app.models.host_guide import HostExperienceGuide
from app.models.booking import HostExperience
from app.models.support_ticket import SupportTicket
from app.schemas.guide_dashboard import PublicGuideUpdate
from app.schemas.public import ExperienceResponse, GuideResponse
from app.services.catalog_service import CatalogService
from app.services.guide_dashboard_service import GuideDashboardService
from app.services.guide_service import GuideService

logger = logging.getLogger(__name__)

router = APIRouter()


# ---------------- Public inquiry / application forms ----------------


class InquiryCreate(BaseModel):
    name: str
    email: str
    subject: str
    message: str
    category: Optional[str] = "general"


@router.post("/inquiries", status_code=status.HTTP_201_CREATED)
def create_inquiry(payload: InquiryCreate, db: Session = Depends(get_db)) -> dict:
    """Public contact / guide-request form. Stored as a support ticket so
    the support team can triage it from the dashboard."""
    ticket = SupportTicket(
        subject=f"[{payload.category}] {payload.subject}",
        description=payload.message,
        customer_name=payload.name,
        customer_email=payload.email,
        priority="medium",
        status="open",
    )
    db.add(ticket)
    db.commit()
    db.refresh(ticket)
    return {"status": "ok", "id": ticket.id, "message": "Inquiry received"}


class PublicHostApplicationCreate(BaseModel):
    full_name: str
    email: str
    phone: Optional[str] = None
    city: Optional[str] = None
    documents: Optional[str] = None  # names of uploaded documents


@router.post("/host-applications", status_code=status.HTTP_201_CREATED)
def submit_host_application(
    payload: PublicHostApplicationCreate, db: Session = Depends(get_db)
) -> dict:
    """Public host registration form from the marketing website.

    Host-only: experience providers that list and manage experiences.
    Guide signups use ``POST /guide-applications`` and land in the
    ``guide_applications`` table, never here.
    """
    application = HostApplication(
        host_name=payload.full_name,
        email=payload.email,
        city=payload.city,
        region=payload.city,
        phone=payload.phone,
        experience=payload.documents or "Host registration via website",
        status="pending",
    )
    db.add(application)
    db.commit()
    db.refresh(application)
    return {"status": "ok", "id": application.id, "message": "Application received"}


class PublicGuideApplicationCreate(BaseModel):
    full_name: str
    email: str
    phone: Optional[str] = None
    city: Optional[str] = None
    nin_number: Optional[str] = None
    documents: Optional[str] = None  # names of uploaded documents


@router.post("/guide-applications", status_code=status.HTTP_201_CREATED)
def submit_guide_application(
    payload: PublicGuideApplicationCreate, db: Session = Depends(get_db)
) -> dict:
    """Public guide registration form from the marketing website.

    Guide-only: individuals who lead tours. Stored in the dedicated
    ``guide_applications`` table so guides are never mixed into the host
    funnel (``host_applications``).
    """
    application = GuideApplication(
        full_name=payload.full_name,
        email=payload.email,
        phone=payload.phone,
        city=payload.city,
        region=payload.city,
        nin_number=payload.nin_number,
        documents=payload.documents or "Guide registration via website",
        status="pending",
    )
    db.add(application)
    db.commit()
    db.refresh(application)
    return {"status": "ok", "id": application.id, "message": "Application received"}


@router.post("/host-applications/submit", status_code=status.HTTP_201_CREATED)
async def submit_host_application_wizard(
    first_name: str = Form(...),
    last_name: str = Form(...),
    date_of_birth: str = Form(...),
    nationality: str = Form(...),
    email: str = Form(...),
    phone: str = Form(...),
    address: str = Form(...),
    city: str = Form(...),
    district: str = Form(...),
    languages: str = Form(...),
    host_type: str = Form(...),
    business_name: str = Form(""),
    registration_number: str = Form(""),
    primary_city: str = Form(...),
    years_experience: str = Form(...),
    expertise: str = Form(...),
    experience: str = Form(...),
    proposedTitle: str = Form(...),
    proposedDescription: str = Form(...),
    proposedCategory: str = Form(...),
    proposedDuration: str = Form(...),
    maxGuests: str = Form("8"),
    price: str = Form(...),
    availability: str = Form(...),
    password: str = Form(...),
    terms: bool = Form(False),
    privacy: bool = Form(False),
    accuracy: bool = Form(False),
    identity: UploadFile = File(None),
    photo: UploadFile = File(None),
    license: UploadFile = File(None),
    certificate: UploadFile = File(None),
    db: Session = Depends(get_db),
) -> dict:
    if not all(
        [
            first_name.strip(),
            last_name.strip(),
            date_of_birth,
            nationality.strip(),
            email.strip(),
            phone.strip(),
            address.strip(),
            city.strip(),
            district.strip(),
            primary_city.strip(),
            proposedTitle.strip(),
            proposedDescription.strip(),
        ]
    ):
        raise HTTPException(
            status_code=422, detail="Please complete all required fields"
        )
    if not (terms and privacy and accuracy):
        raise HTTPException(status_code=422, detail="All declarations must be accepted")
    if len(experience.strip()) < 50 or len(proposedDescription.strip()) < 30:
        raise HTTPException(
            status_code=422,
            detail="Please provide more detail in the experience sections",
        )
    # Capture the applicant's chosen password now, but only as a hash on the
    # application row. The real login account is minted when a regional head
    # or admin approves (operations.review_host_application).
    valid_pw, pw_msg = validate_password_strength(password)
    if not valid_pw:
        raise HTTPException(status_code=422, detail=pw_msg)
    password_hash = get_password_hash(password)
    documents = {}
    upload_root = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "../../private_host_applications")
    )
    os.makedirs(upload_root, exist_ok=True)
    for key, upload in {
        "identity": identity,
        "photo": photo,
        "license": license,
        "certificate": certificate,
    }.items():
        if not upload:
            continue
        content = await upload.read()
        if len(content) > 10 * 1024 * 1024 or upload.content_type not in {
            "application/pdf",
            "image/jpeg",
            "image/png",
        }:
            raise HTTPException(
                status_code=422, detail=f"{key}: use PDF, JPG, or PNG files under 10 MB"
            )
        filename = (
            f"{uuid.uuid4().hex}_{os.path.basename(upload.filename or 'document')}"
        )
        with open(os.path.join(upload_root, filename), "wb") as target:
            target.write(content)
        documents[key] = filename
    application = HostApplication(
        host_name=f"{first_name} {last_name}",
        email=email,
        phone=phone,
        city=city,
        region=district,
        experience=json.dumps(
            {
                "host_type": host_type,
                "business_name": business_name,
                "registration_number": registration_number,
                "primary_city": primary_city,
                "years_experience": years_experience,
                "expertise": expertise,
                "languages": languages,
                "proposed_experience": {
                    "title": proposedTitle,
                    "description": proposedDescription,
                    "category": proposedCategory,
                    "duration": proposedDuration,
                    "max_guests": maxGuests,
                    "price": price,
                    "availability": availability,
                },
                "documents": documents,
            },
            ensure_ascii=False,
        ),
        credential_password_hash=password_hash,
        status="pending",
    )
    db.add(application)
    db.commit()
    db.refresh(application)
    return {
        "id": application.id,
        "status": application.status,
        "message": "Application received",
    }


# Mock Data to match frontend types exactly
MOCK_GUIDES: list[dict[str, Any]] = [
    {
        "id": 1,
        "name": "Ram Bahadur",
        "image": "https://images.unsplash.com/photo-1494790108377-be9c29b29330?ixlib=rb-4.0.3&auto=format&fit=crop&w=128&h=128&q=80",
        "role": "Cultural Expert",
        "rating": 4.9,
        "reviews": 120,
        "bio": "Expert in Kathmandu Valley history.",
        "languages": ["English", "Nepali", "Newari"],
        "verified": True,
        "livesIn": "Kathmandu",
        "cities": ["Kathmandu", "Bhaktapur"],
        "gallery": [],
    },
    {
        "id": 2,
        "name": "Sujal Thapa",
        "image": "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?ixlib=rb-4.0.3&auto=format&fit=crop&w=128&h=128&q=80",
        "role": "Adventure Specialist",
        "rating": 4.92,
        "reviews": 89,
        "bio": "Mountain guide with 8+ years of experience.",
        "languages": ["English", "Nepali", "Hindi"],
        "verified": True,
        "livesIn": "Pokhara",
        "cities": ["Pokhara", "Kathmandu"],
        "gallery": [],
    },
    {
        "id": 3,
        "name": "Priya Sharma",
        "image": "https://images.unsplash.com/photo-1534528741775-53994a69daeb?ixlib=rb-4.0.3&auto=format&fit=crop&w=128&h=128&q=80",
        "role": "Food & Culture Guide",
        "rating": 4.95,
        "reviews": 156,
        "bio": "Culinary expert specializing in traditional Nepali cuisine.",
        "languages": ["English", "Nepali", "Newari"],
        "verified": True,
        "livesIn": "Kathmandu",
        "cities": ["Kathmandu", "Pokhara", "Lalitpur"],
        "gallery": [],
    },
    {
        "id": 4,
        "name": "Rohan KC",
        "image": "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?ixlib=rb-4.0.3&auto=format&fit=crop&w=128&h=128&q=80",
        "role": "Nature Guide",
        "rating": 4.88,
        "reviews": 67,
        "bio": "Passionate about wildlife and nature experiences.",
        "languages": ["English", "Nepali"],
        "verified": True,
        "livesIn": "Bharatpur",
        "cities": ["Bharatpur", "Kathmandu"],
        "gallery": [],
    },
]

MOCK_EXPERIENCES: list[dict[str, Any]] = [
    {
        "id": 1,
        "slug": "bhaktapur-heritage-walk",
        "title": "Bhaktapur Heritage Walk",
        "heroImage": "https://images.unsplash.com/photo-1589394815804-964ed0be2eb5?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80",
        "description": "Walk through the living museum of Bhaktapur. Explore ancient temples, traditional Newari architecture, and local pottery workshops.",
        "price": 50.0,
        "duration": "4 hours",
        "rating": 4.8,
        "reviews": 45,
        "city": "Bhaktapur",
        "category": "Cultural",
        "host": MOCK_GUIDES[0],
    },
    {
        "id": 2,
        "slug": "kathmandu-hidden-gems",
        "title": "Hidden Gems of Kathmandu",
        "heroImage": "https://images.unsplash.com/photo-1605640840605-14ac1855827b?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80",
        "description": "Discover secret temples, hidden courtyards, and local eateries that most tourists never see.",
        "price": 35.0,
        "duration": "3 hours",
        "rating": 4.9,
        "reviews": 78,
        "city": "Kathmandu",
        "category": "Cultural",
        "host": MOCK_GUIDES[0],
    },
    {
        "id": 3,
        "slug": "pokhara-lakeside-tour",
        "title": "Pokhara Lakeside & Mountain Views",
        "heroImage": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80",
        "description": "Enjoy the serene beauty of Phewa Lake with stunning views of the Annapurna range.",
        "price": 45.0,
        "duration": "5 hours",
        "rating": 4.9,
        "reviews": 92,
        "city": "Pokhara",
        "category": "Nature",
        "host": MOCK_GUIDES[1],
    },
    {
        "id": 4,
        "slug": "pokhara-sunrise-trek",
        "title": "Sarangkot Sunrise Trek",
        "heroImage": "https://thumb.wikimedia.org/wikipedia/commons/thumb/f/f6/Pokhara-Sarangkot-12-Sonnenaufgang-2015-gje.jpg/960px-Pokhara-Sarangkot-12-Sonnenaufgang-2015-gje.jpg",
        "description": "Early morning trek to Sarangkot for breathtaking sunrise views over the Himalayas.",
        "price": 40.0,
        "duration": "6 hours",
        "rating": 4.95,
        "reviews": 134,
        "city": "Pokhara",
        "category": "Adventure",
        "host": MOCK_GUIDES[1],
    },
    {
        "id": 5,
        "slug": "newari-food-tour",
        "title": "Authentic Newari Food Tour",
        "heroImage": "https://images.unsplash.com/photo-1504674900247-0877df9cc836?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80",
        "description": "Taste your way through traditional Newari cuisine with local experts.",
        "price": 40.0,
        "duration": "4 hours",
        "rating": 4.95,
        "reviews": 156,
        "city": "Kathmandu",
        "category": "Food",
        "host": MOCK_GUIDES[2],
    },
    {
        "id": 6,
        "slug": "lalitpur-art-walk",
        "title": "Patan Art & Architecture Walk",
        "heroImage": "https://thumb.wikimedia.org/wikipedia/commons/thumb/1/17/Patan_Durbar_Square-2644.jpg/960px-Patan_Durbar_Square-2644.jpg",
        "description": "Explore the ancient city of Patan, known for its exquisite wood carvings and stone temples.",
        "price": 35.0,
        "duration": "3 hours",
        "rating": 4.7,
        "reviews": 58,
        "city": "Lalitpur",
        "category": "Cultural",
        "host": MOCK_GUIDES[2],
    },
    {
        "id": 7,
        "slug": "chitwan-wildlife-safari",
        "title": "Chitwan Wildlife Safari",
        "heroImage": "https://thumb.wikimedia.org/wikipedia/commons/thumb/0/0e/Dhurbe%3B_Wild_Asian_Elephant.jpg/960px-Dhurbe%3B_Wild_Asian_Elephant.jpg",
        "description": "Experience the thrill of spotting rhinos, elephants, and exotic birds in Chitwan National Park.",
        "price": 75.0,
        "duration": "8 hours",
        "rating": 4.85,
        "reviews": 89,
        "city": "Bharatpur",
        "category": "Nature",
        "host": MOCK_GUIDES[3],
    },
    {
        "id": 8,
        "slug": "tharu-cultural-experience",
        "title": "Tharu Cultural Experience",
        "heroImage": "https://thumb.wikimedia.org/wikipedia/commons/thumb/0/0e/Tharu_Dance_during_Maghi.jpg/960px-Tharu_Dance_during_Maghi.jpg",
        "description": "Immerse yourself in the unique culture of the Tharu people and their traditional way of life.",
        "price": 30.0,
        "duration": "3 hours",
        "rating": 4.6,
        "reviews": 42,
        "city": "Bharatpur",
        "category": "Cultural",
        "host": MOCK_GUIDES[3],
    },
    {
        "id": 9,
        "slug": "kathmandu-street-food",
        "title": "Kathmandu Street Food Adventure",
        "heroImage": "https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80",
        "description": "Explore the vibrant street food scene of Kathmandu. From momos to chatpate, taste the best local flavors.",
        "price": 25.0,
        "duration": "2 hours",
        "rating": 4.8,
        "reviews": 112,
        "city": "Kathmandu",
        "category": "Food",
        "host": MOCK_GUIDES[2],
    },
    {
        "id": 10,
        "slug": "pokhara-paragliding",
        "title": "Pokhara Paragliding Experience",
        "heroImage": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80",
        "description": "Soar above Phewa Lake and enjoy panoramic views of the Himalayas with experienced pilots.",
        "price": 120.0,
        "duration": "2 hours",
        "rating": 4.98,
        "reviews": 201,
        "city": "Pokhara",
        "category": "Adventure",
        "host": MOCK_GUIDES[1],
    },
    {
        "id": 11,
        "slug": "bhaktapur-pottery-workshop",
        "title": "Bhaktapur Pottery Workshop",
        "heroImage": "https://images.unsplash.com/photo-1565193566173-7a0ee3dbe261?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80",
        "description": "Learn the ancient art of pottery from master craftsmen and create your own souvenir.",
        "price": 30.0,
        "duration": "3 hours",
        "rating": 4.75,
        "reviews": 36,
        "city": "Bhaktapur",
        "category": "Workshop",
        "host": MOCK_GUIDES[0],
    },
    {
        "id": 12,
        "slug": "lalitpur-cooking-class",
        "title": "Traditional Nepali Cooking Class",
        "heroImage": "https://images.unsplash.com/photo-1585937421612-70a008356fbe?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80",
        "description": "Learn to cook authentic Nepali dishes including dal bhat, momos, and sel roti.",
        "price": 35.0,
        "duration": "4 hours",
        "rating": 4.88,
        "reviews": 67,
        "city": "Lalitpur",
        "category": "Food",
        "host": MOCK_GUIDES[2],
    },
]


def _guide_to_host_payload(guide: Guide) -> dict:
    return {
        "id": guide.id,
        "name": guide.name,
        "image": guide.image,
        "role": guide.role,
        "rating": float(guide.rating or 0.0),
        "reviews": int(guide.reviews or 0),
        "bio": guide.bio,
        "languages": list(guide.languages or []),
        "verified": bool(guide.verified),
        "livesIn": guide.lives_in,
        "cities": list(guide.cities or []),
        "gallery": list(guide.gallery or []),
    }


def _host_experience_to_public(
    db: Session, experience: HostExperience
) -> Optional[dict]:
    """Host-owned experience enriched with its assigned guide for travelers."""
    rows = (
        db.query(HostExperienceGuide, Guide)
        .join(Guide, HostExperienceGuide.guide_id == Guide.id)
        .filter(
            HostExperienceGuide.experience_id == experience.id,
            Guide.is_active.is_(True),
        )
        .order_by(
            HostExperienceGuide.is_primary.desc(), HostExperienceGuide.created_at.desc()
        )
        .all()
    )
    if not rows:
        return None
    _assignment, guide = rows[0]
    return {
        "id": 100000 + int(experience.id),
        "slug": f"host-{experience.slug}",
        "title": experience.title,
        "heroImage": experience.hero_image or MOCK_GUIDES[0]["image"],
        "description": experience.description,
        "price": float(experience.price or 0.0),
        "duration": experience.duration,
        "rating": float(guide.rating or 4.8),
        "reviews": int(guide.reviews or 0),
        "city": experience.city,
        "category": experience.category,
        "host": _guide_to_host_payload(guide),
        "guides": [_guide_to_host_payload(g) for _, g in rows],
    }


@router.get("/experiences", response_model=List[ExperienceResponse])
def list_experiences(
    city: Optional[str] = None,
    category: Optional[str] = None,
    search: Optional[str] = None,
    min_price: Optional[float] = None,
    max_price: Optional[float] = None,
    sort: Optional[str] = None,
    db: Session = Depends(get_db),
) -> List[dict]:
    results = MOCK_EXPERIENCES.copy()

    # Live host experiences with an assigned guide surface alongside mocks.
    try:
        host_rows = (
            db.query(HostExperience).filter(HostExperience.is_active.is_(True)).all()
        )
        for experience in host_rows:
            public_row = _host_experience_to_public(db, experience)
            if public_row:
                results.append(public_row)
    except Exception:
        logger.warning("Live host experiences unavailable", exc_info=True)

    # Published guide listings: a guide's own trips become catalogue rows, so
    # writing a listing is what makes it bookable rather than a dead end in the
    # guide's dashboard. Paused listings and deactivated guides drop out here.
    try:
        results.extend(CatalogService(db).published_experiences(city=city))
    except Exception:
        logger.warning("Published guide listings unavailable", exc_info=True)

    # Filter by city
    if city:
        results = [e for e in results if e.get("city", "").lower() == city.lower()]

    # Filter by category
    if category:
        results = [
            e for e in results if e.get("category", "").lower() == category.lower()
        ]

    # Filter by search term
    if search:
        search_lower = search.lower()
        results = [
            e
            for e in results
            if search_lower in e.get("title", "").lower()
            or search_lower in e.get("description", "").lower()
            or search_lower in e.get("city", "").lower()
        ]

    # Filter by price range
    if min_price is not None:
        results = [e for e in results if e.get("price", 0) >= min_price]
    if max_price is not None:
        results = [e for e in results if e.get("price", 0) <= max_price]

    # Sort results
    if sort == "price_low":
        results.sort(key=lambda x: x.get("price") or 0)
    elif sort == "price_high":
        results.sort(key=lambda x: x.get("price") or 0, reverse=True)
    elif sort == "rating":
        # A listing with no reviews yet has a null rating; without the `or 0`
        # comparing it against a float raises mid-sort.
        results.sort(key=lambda x: x.get("rating") or 0, reverse=True)
    elif sort == "popular":
        results.sort(key=lambda x: x.get("reviews") or 0, reverse=True)

    return results


@router.get("/experiences/{slug}", response_model=ExperienceResponse)
def get_experience(slug: str, db: Session = Depends(get_db)) -> dict:
    for exp in MOCK_EXPERIENCES:
        if exp["slug"] == slug:
            return exp
    # Published guide listings are addressed as listing-{slug}.
    if slug.startswith("listing-"):
        try:
            published = CatalogService(db).published_experience(slug)
        except Exception:
            logger.warning("Guide listing lookup failed", exc_info=True)
            published = None
        if published:
            return published
        raise HTTPException(status_code=404, detail="Experience not found")
    # Live host experiences are addressed as host-{slug} on the frontend.
    if slug.startswith("host-"):
        try:
            experience = (
                db.query(HostExperience)
                .filter(
                    HostExperience.slug == slug.removeprefix("host-"),
                    HostExperience.is_active.is_(True),
                )
                .first()
            )
            if experience:
                public_row = _host_experience_to_public(db, experience)
                if public_row:
                    return public_row
        except Exception:
            logger.warning("Host experience lookup failed", exc_info=True)
    raise HTTPException(status_code=404, detail="Experience not found")


@router.get("/guides", response_model=List[GuideResponse])
def list_guides(
    city: Optional[str] = None, db: Session = Depends(get_db)
) -> List[dict]:
    """Legacy catalogue guides plus real guide accounts, in one shape.

    The two are separate tables: ``guides`` is display-only catalogue content,
    while a signed-in guide's onboarding profile lives in ``guide_profiles``.
    A traveller browsing guides should see both, so the accounts are appended
    with a namespaced id (see ``CatalogService``) that ``GET /guides/{id}``
    resolves back to the account.
    """
    service = GuideService(db)
    result: List[dict] = list(service.get_all_guides(city))
    try:
        result.extend(CatalogService(db).public_guides(city=city))
    except Exception:
        logger.warning("Published guide profiles unavailable", exc_info=True)
    return result


@router.get("/guides/{id}", response_model=GuideResponse)
def get_guide(id: int, db: Session = Depends(get_db)) -> dict:
    service = GuideService(db)
    guide = service.get_guide(id)
    if guide:
        return guide
    # Guide-account profiles carry a namespaced id; legacy catalogue ids never
    # reach that range, so the two lookups cannot shadow each other.
    try:
        published = CatalogService(db).public_guide(id)
    except Exception:
        logger.warning("Guide account lookup failed", exc_info=True)
        published = None
    if published:
        return published
    raise HTTPException(status_code=404, detail="Guide not found")


@router.get("/updates", response_model=List[PublicGuideUpdate])
def list_public_updates(
    city: Optional[str] = None,
    limit: int = 20,
    db: Session = Depends(get_db),
) -> List[dict]:
    """Traveller-facing feed of active guide updates, scoped by city.

    Read-only and public: it exposes the guide's chosen display name and their
    update text, never their user id, email or booking details. Updates are
    matched to a city through the guide's onboarding profile or through the
    listing they are attached to, because the guide accounts that post updates
    are not linked to the legacy ``guides`` catalog profiles travellers
    browse. Without a ``city`` filter every current update is returned.
    """
    return GuideDashboardService(db).list_public_updates(city=city, limit=limit)
