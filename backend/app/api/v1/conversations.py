"""Direct messaging between traveler and guide accounts.

Implements the contract recommended in ``mobile/docs/api-gaps.md`` §2:

- ``GET  /conversations``               — threads the caller belongs to,
  newest activity first, each with peer, last message and unread count
- ``POST /conversations``               — get-or-create a thread by
  recipient id (the guide assigned to a booking is the normal entry)
- ``GET  /conversations/{id}/messages`` — thread history; fetching marks
  the received messages read (drives unread counts off the list)
- ``POST /conversations/{id}/messages`` — send a message

Every route requires authentication and is scoped to participants: a
missing conversation and a conversation the caller is not part of both
answer **404**, so ids cannot be probed. Unread counts are computed
server-side, keeping the mobile side a plain poller (list refresh plus
thread refresh — no push channel required).
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.conversation import Conversation, Message
from app.models.user import User
from app.schemas.messaging import (
    ConversationCreate,
    ConversationResponse,
    LastMessageResponse,
    MessageCreate,
    MessageResponse,
    PeerResponse,
)

router = APIRouter(tags=["conversations"])


def _naive_utc_now() -> datetime:
    """Naive UTC — every timestamp column in this schema is naive."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _load_membership(db: Session, conversation_id: int, viewer: User) -> Conversation:
    """The thread only if [viewer] participates; otherwise 404.

    Non-members get the same answer as a nonexistent id so conversation
    ids never leak their existence.
    """
    conv = db.get(Conversation, conversation_id)
    if conv is None or viewer.id not in (conv.user_a_id, conv.user_b_id):
        raise HTTPException(status_code=404, detail="Conversation not found")
    return conv


def _unread_count(db: Session, conversation_id: int, viewer_id: int) -> int:
    return (
        db.query(Message)
        .filter(
            Message.conversation_id == conversation_id,
            Message.sender_id != viewer_id,
            Message.read_at.is_(None),
        )
        .count()
    )


def _payload(db: Session, conv: Conversation, viewer: User) -> dict:
    other = db.get(User, conv.other_user_id(int(viewer.id)))
    if other is None:
        # Foreign keys keep participants alive while a thread exists, so this
        # only happens if the peer row was pruned — the thread is unusable.
        raise HTTPException(status_code=404, detail="Conversation not found")
    last = (
        db.query(Message)
        .filter(Message.conversation_id == conv.id)
        .order_by(Message.id.desc())
        .limit(1)
        .first()
    )
    return {
        "id": conv.id,
        "peer": PeerResponse(
            id=int(other.id),
            firstName=other.firstName,
            lastName=other.lastName,
            avatarUrl=other.avatar_url,
            role=str(other.role),
        ),
        "last_message": (
            LastMessageResponse(
                id=last.id,
                body=last.body,
                sender_id=last.sender_id,
                created_at=last.created_at,
            )
            if last is not None
            else None
        ),
        "unread_count": _unread_count(db, conv.id, int(viewer.id)),
        "created_at": conv.created_at,
    }


@router.get("/conversations", response_model=list[ConversationResponse])
def list_conversations(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[dict]:
    """Threads the signed-in user participates in, newest activity first."""
    convs = (
        db.query(Conversation)
        .filter(
            or_(
                Conversation.user_a_id == current_user.id,
                Conversation.user_b_id == current_user.id,
            )
        )
        .all()
    )
    payloads = [_payload(db, conv, current_user) for conv in convs]
    payloads.sort(
        key=lambda p: (
            p["last_message"].created_at
            if p["last_message"] is not None
            else p["created_at"]
        ),
        reverse=True,
    )
    return payloads


@router.post("/conversations", response_model=ConversationResponse)
def open_conversation(
    payload: ConversationCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """Get-or-create the thread with [recipient_id].

    The pair is canonicalized (low id first) so both sides opening the
    conversation resolve to one row; the unique constraint backstops the
    race.
    """
    if payload.recipient_id == current_user.id:
        raise HTTPException(status_code=422, detail="You cannot message yourself")
    recipient = db.get(User, payload.recipient_id)
    if recipient is None or not recipient.is_active:
        raise HTTPException(status_code=404, detail="Recipient not found")

    a, b = sorted((int(current_user.id), int(recipient.id)))
    conv = (
        db.query(Conversation)
        .filter(Conversation.user_a_id == a, Conversation.user_b_id == b)
        .first()
    )
    if conv is None:
        conv = Conversation(user_a_id=a, user_b_id=b)
        db.add(conv)
        db.commit()
        db.refresh(conv)
    return _payload(db, conv, current_user)


@router.get(
    "/conversations/{conversation_id}/messages",
    response_model=list[MessageResponse],
)
def list_messages(
    conversation_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[Message]:
    """Thread history in order — and mark received messages as read.

    The read side effect is what makes the inbox's unread counts drop
    when the traveler opens a thread; polling the open thread keeps them
    at zero for whatever is on screen.
    """
    conv = _load_membership(db, conversation_id, current_user)
    messages = (
        db.query(Message)
        .filter(Message.conversation_id == conv.id)
        .order_by(Message.id)
        .all()
    )
    now = _naive_utc_now()
    changed = [
        m for m in messages if m.sender_id != current_user.id and m.read_at is None
    ]
    for message in changed:
        message.read_at = now
    if changed:
        db.commit()
    return messages


@router.post(
    "/conversations/{conversation_id}/messages",
    response_model=MessageResponse,
    status_code=status.HTTP_201_CREATED,
)
def send_message(
    conversation_id: int,
    payload: MessageCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Message:
    """Send a message as the authenticated user (participants only)."""
    conv = _load_membership(db, conversation_id, current_user)
    body = payload.body.strip()
    if not body:
        raise HTTPException(status_code=422, detail="Message cannot be blank")
    message = Message(conversation_id=conv.id, sender_id=current_user.id, body=body)
    db.add(message)
    db.commit()
    db.refresh(message)
    return message
