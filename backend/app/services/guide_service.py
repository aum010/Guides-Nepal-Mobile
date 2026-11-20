from typing import List, Optional

from sqlalchemy import Text
from sqlalchemy.orm import Session
from app.models.guide import Guide
from app.schemas.public import GuideCreate, GuideUpdate


class GuideService:
    def __init__(self, db: Session):
        self.db = db

    def create_guide(self, guide_data: GuideCreate) -> Guide:
        data = guide_data.model_dump()
        # The public schema spells the column `livesIn`; map it onto the ORM
        # attribute before instantiating (Guide(**...) rejects unknown kwargs).
        if "livesIn" in data:
            data["lives_in"] = data.pop("livesIn")
        guide = Guide(**data)
        self.db.add(guide)
        self.db.commit()
        self.db.refresh(guide)
        return guide

    def get_guide(self, guide_id: int) -> Optional[Guide]:
        return (
            self.db.query(Guide)
            .filter(Guide.id == guide_id, Guide.is_active.is_(True))
            .first()
        )

    def get_all_guides(self, city: Optional[str] = None) -> List[Guide]:
        query = self.db.query(Guide).filter(Guide.is_active.is_(True))
        if city:
            # JSON list membership: cast to text and match the quoted element
            # (`contains` on a JSON column neither portably nor correctly
            # implements list membership across SQLite and Postgres).
            query = query.filter(Guide.cities.cast(Text).like(f'%"{city}"%'))
        return query.all()

    def update_guide(self, guide_id: int, guide_data: GuideUpdate) -> Optional[Guide]:
        guide = self.get_guide(guide_id)
        if not guide:
            return None

        for key, value in guide_data.model_dump(exclude_unset=True).items():
            setattr(guide, key, value)

        self.db.commit()
        self.db.refresh(guide)
        return guide

    def delete_guide(self, guide_id: int) -> bool:
        guide = self.get_guide(guide_id)
        if not guide:
            return False

        setattr(guide, "is_active", False)
        self.db.commit()
        return True
