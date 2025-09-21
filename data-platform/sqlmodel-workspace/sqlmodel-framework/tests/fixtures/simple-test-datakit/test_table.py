"""Simple test table with no external dependencies for deployment testing."""

from sqlmodel import Field, SQLModel


class TestProduct(SQLModel, table=True):
    """Simple test table for deployment validation."""

    __tablename__ = "test_product"
    __table_args__ = {"schema": "public"}

    id: int = Field(primary_key=True)
    name: str = Field(nullable=False)
    price: float | None = Field(default=None)
    active: bool = Field(default=True)


class TestCategory(SQLModel, table=True):
    """Simple test table with foreign key for relationship testing."""

    __tablename__ = "test_category"
    __table_args__ = {"schema": "public"}

    id: int = Field(primary_key=True)
    name: str = Field(nullable=False)
    description: str | None = Field(default=None)
