"""Image uploads: one directory, one set of rules.

Two bugs used to live here. Uploads were written to ``backend/uploads``
(``app/api/v1/../../../uploads``) while ``app/main.py`` served
``backend/app/uploads``, so every uploaded URL 404'd; and nothing validated
what was written, so a renamed ``.html`` was accepted as a photo.

Both now go through this module: ``UPLOADS_ROOT`` is the single directory
(``backend/uploads``) that the app mounts at ``/uploads``, and :func:`save_image`
accepts only real JPEG/PNG/WebP bytes below a size cap, storing them under a
generated name so a client filename can never decide the path.
"""

from __future__ import annotations

import shutil
from pathlib import Path
from uuid import uuid4

from fastapi import HTTPException, status

# ``app/core/storage.py`` → ``app/core`` → ``app`` → ``backend``.
UPLOADS_ROOT = Path(__file__).resolve().parents[2] / "uploads"

#: Public URL prefix the mounted StaticFiles app answers on.
UPLOADS_URL_PREFIX = "/uploads"

MAX_IMAGE_BYTES = 5 * 1024 * 1024  # 5 MB

# Supported types with the signature bytes that prove the content matches.
_SIGNATURES: dict[str, tuple[str, tuple[bytes, ...]]] = {
    "image/jpeg": (".jpg", (b"\xff\xd8\xff",)),
    "image/jpg": (".jpg", (b"\xff\xd8\xff",)),
    "image/png": (".png", (b"\x89PNG\r\n\x1a\n",)),
    # WebP is a RIFF container; the brand follows at offset 8.
    "image/webp": (".webp", (b"RIFF",)),
}


def _media_type(content_type: str | None) -> str:
    return (content_type or "").split(";")[0].strip().lower()


def save_image(contents: bytes, content_type: str | None, subdir: str) -> str:
    """Write one validated image and return its public URL path.

    ``subdir`` groups files (``"listings/12"``). Raises 415 for an unsupported
    type, 413 for an oversized file and 422 for bytes that are not that type —
    a client can lie in ``Content-Type``, so the signature is checked too.
    """
    media = _SIGNATURES.get(_media_type(content_type))
    if media is None:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Upload a JPEG, PNG or WebP image.",
        )
    if not contents:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="The uploaded file is empty.",
        )
    if len(contents) > MAX_IMAGE_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Images must be 5 MB or smaller.",
        )
    extension, signatures = media
    if not any(contents.startswith(signature) for signature in signatures):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="That file is not a valid image.",
        )

    directory = (UPLOADS_ROOT / subdir).resolve()
    root = UPLOADS_ROOT.resolve()
    if root not in directory.parents and directory != root:
        # subdir is built from ids, but keep the guarantee explicit.
        raise HTTPException(status_code=400, detail="Invalid upload path")
    directory.mkdir(parents=True, exist_ok=True)
    name = f"{uuid4().hex}{extension}"
    (directory / name).write_bytes(contents)
    return f"{UPLOADS_URL_PREFIX}/{subdir}/{name}"


def delete_uploaded(url: str | None) -> None:
    """Remove a managed file, ignoring anything outside the uploads root.

    Only URLs this module produced are touched: a remote URL (a guide's own
    CDN link) is left alone, and a path that escapes the root is refused.
    """
    if not url or not url.startswith(f"{UPLOADS_URL_PREFIX}/"):
        return
    relative = url[len(UPLOADS_URL_PREFIX) + 1 :]
    target = (UPLOADS_ROOT / relative).resolve()
    root = UPLOADS_ROOT.resolve()
    if root not in target.parents:
        return
    if target.is_file():
        target.unlink(missing_ok=True)


def delete_upload_dir(subdir: str) -> None:
    """Remove a listing's whole photo directory when the listing is deleted."""
    target = (UPLOADS_ROOT / subdir).resolve()
    root = UPLOADS_ROOT.resolve()
    if root not in target.parents:
        return
    if target.is_dir():
        shutil.rmtree(target, ignore_errors=True)
