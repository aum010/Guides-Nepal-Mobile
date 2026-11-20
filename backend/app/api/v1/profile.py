from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, Request
from sqlalchemy.orm import Session
from typing import List, Dict, Any
from app.core.database import get_db
from app.core.storage import save_image
from app.models.user import User
from app.models.bookmark import Bookmark
from app.schemas.profile import ProfileUpdate, BookmarkCreate, BookmarkResponse
from app.services.bookmark_service import BookmarkService
from app.core.dependencies import authenticate_token


def get_current_user_id(request: Request, db: Session = Depends(get_db)) -> int:
    auth = request.headers.get("Authorization")
    if not auth or not auth.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Not authenticated")
    return authenticate_token(db, auth.split(" ", 1)[1]).id


router = APIRouter()


@router.get("/me")
def get_me(
    db: Session = Depends(get_db), user_id: int = Depends(get_current_user_id)
) -> Dict[str, Any]:
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return {
        "id": user.id,
        "email": user.email,
        "firstName": user.firstName,
        "lastName": user.lastName,
        "phone": user.phone,
        "bio": user.bio,
        "avatarUrl": user.avatar_url,
    }


@router.patch("/me")
def update_me(
    payload: ProfileUpdate,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_current_user_id),
) -> Dict[str, str]:
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(user, key, value)
    db.commit()
    db.refresh(user)
    return {"status": "ok"}


@router.post("/photos/upload")
async def upload_photo(
    file: UploadFile = File(...),
    user_id: int = Depends(get_current_user_id),
) -> Dict[str, str]:
    """Store a profile photo and return its public URL path.

    Validation and storage live in ``app.core.storage``, which also owns the
    directory the app serves at ``/uploads`` — this endpoint used to write to a
    different one, so the URL it returned was always a 404.
    """
    url = save_image(await file.read(), file.content_type, str(user_id))
    return {"url": url}


@router.get("/bookmarks", response_model=List[BookmarkResponse])
def list_bookmarks(
    db: Session = Depends(get_db), user_id: int = Depends(get_current_user_id)
) -> List[Bookmark]:
    service = BookmarkService(db)
    return service.list(user_id)


@router.post("/bookmarks", response_model=BookmarkResponse)
def add_bookmark(
    data: BookmarkCreate,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_current_user_id),
) -> Bookmark:
    service = BookmarkService(db)
    return service.create(user_id, data)


@router.delete("/bookmarks/{bookmark_id}")
def delete_bookmark(
    bookmark_id: int,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_current_user_id),
) -> Dict[str, str]:
    service = BookmarkService(db)
    ok = service.delete(user_id, bookmark_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Bookmark not found")
    return {"status": "ok"}
