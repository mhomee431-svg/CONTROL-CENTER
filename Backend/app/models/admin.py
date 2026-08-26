"""Admin Actions, Admin Notes, Product Approvals, Reports, Complaints, Audit Logs models."""
from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Boolean, Text, ForeignKey, Enum, JSON, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship
import enum

from app.database.session import Base
from app.models.base import TimestampMixin


class ApprovalStatus(str, enum.Enum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"
    NEEDS_INFO = "NEEDS_INFO"


class ComplaintStatus(str, enum.Enum):
    OPEN = "OPEN"
    IN_PROGRESS = "IN_PROGRESS"
    RESOLVED = "RESOLVED"
    CLOSED = "CLOSED"
    REJECTED = "REJECTED"


class AdminAction(Base, TimestampMixin):
    __tablename__ = "admin_actions"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    admin_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    action_type: Mapped[str] = mapped_column(String(50), nullable=False, index=True)  # VERIFY_SHOP, SUSPEND_USER, etc.
    target_type: Mapped[str] = mapped_column(String(50), nullable=False)  # SHOP, USER, PRODUCT, OFFER
    target_id: Mapped[int] = mapped_column(Integer, nullable=False)
    action_data: Mapped[dict | None] = mapped_column(JSON)
    description: Mapped[str | None] = mapped_column(Text)
    ip_address: Mapped[str | None] = mapped_column(String(45))
    performed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)


class AdminNote(Base, TimestampMixin):
    __tablename__ = "admin_notes"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    admin_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    entity_type: Mapped[str] = mapped_column(String(50), nullable=False)  # SHOP, USER, PRODUCT
    entity_id: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    note: Mapped[str] = mapped_column(Text, nullable=False)
    is_private: Mapped[bool] = mapped_column(Boolean, default=True)
    created_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))


class ProductApproval(Base, TimestampMixin):
    __tablename__ = "product_approvals"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    product_master_id: Mapped[int] = mapped_column(ForeignKey("product_masters.id"), index=True, nullable=False)
    shop_id: Mapped[int | None] = mapped_column(ForeignKey("shops.id"), index=True)
    submitted_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    status: Mapped[ApprovalStatus] = mapped_column(
        Enum(ApprovalStatus, name="approval_status"), nullable=False, default=ApprovalStatus.PENDING
    )
    requested_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    reviewed_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    review_notes: Mapped[str | None] = mapped_column(Text)
    submitted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    submission_data: Mapped[dict | None] = mapped_column(JSON)

    product = relationship("ProductMaster", back_populates="approvals")


class Report(Base, TimestampMixin):
    __tablename__ = "reports"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    report_type: Mapped[str] = mapped_column(String(50), nullable=False, index=True)  # SALES, INVENTORY, SEARCH_ANALYTICS
    report_name: Mapped[str] = mapped_column(String(255), nullable=False)
    parameters_json: Mapped[dict | None] = mapped_column(JSON)
    result_json: Mapped[dict | None] = mapped_column(JSON)  # Phase 29 — generated report payload
    generated_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    file_url: Mapped[str | None] = mapped_column(String(500))
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="PENDING")  # PENDING, GENERATING, READY, FAILED
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    error_message: Mapped[str | None] = mapped_column(Text)


class Complaint(Base, TimestampMixin):
    __tablename__ = "complaints"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    complainant_user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), index=True)
    complaint_type: Mapped[str] = mapped_column(String(50), nullable=False)  # WRONG_PRICE, FAKE_PRODUCT, SHOP_ISSUE
    subject: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    entity_type: Mapped[str | None] = mapped_column(String(50))  # SHOP, PRODUCT, OFFER
    entity_id: Mapped[int | None] = mapped_column(Integer)
    status: Mapped[ComplaintStatus] = mapped_column(
        Enum(ComplaintStatus, name="complaint_status"), nullable=False, default=ComplaintStatus.OPEN
    )
    priority: Mapped[str] = mapped_column(String(20), default="MEDIUM")  # LOW, MEDIUM, HIGH, URGENT
    assigned_to: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    resolution_notes: Mapped[str | None] = mapped_column(Text)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class AuditLog(Base, TimestampMixin):
    __tablename__ = "audit_logs"
    __table_args__ = (
        Index("ix_audit_logs_entity_time", "entity_type", "entity_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), index=True)
    action: Mapped[str] = mapped_column(String(50), nullable=False)  # CREATE, UPDATE, DELETE, VERIFY
    entity_type: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
    entity_id: Mapped[int | None] = mapped_column(Integer, index=True)
    old_values: Mapped[dict | None] = mapped_column(JSON)
    new_values: Mapped[dict | None] = mapped_column(JSON)
    ip_address: Mapped[str | None] = mapped_column(String(45))
    user_agent: Mapped[str | None] = mapped_column(String(255))
    request_id: Mapped[str | None] = mapped_column(String(100), index=True)
    description: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)

    # Phase 29 — tamper-evident hash chaining (see services/audit_service.py).
    # Each record's hash covers its content AND the previous record's hash,
    # so any casual modification breaks verifiable chain linkage.
    prev_record_hash: Mapped[str | None] = mapped_column(String(64))
    record_hash: Mapped[str | None] = mapped_column(String(64), index=True)