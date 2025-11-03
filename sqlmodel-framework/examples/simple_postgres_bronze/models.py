"""
Bronze layer table definitions using SQLModel Framework.

This file demonstrates how to use the BronzeMetadata mixin
to automatically add standard Bronze layer fields.
"""

from sqlmodel import SQLModel, Field
from sqlmodel_framework.base.models import BronzeMetadata
from typing import Optional
from datetime import datetime


class FilmBronze(SQLModel, BronzeMetadata, table=True):
    """
    Bronze layer film table.

    The BronzeMetadata mixin automatically adds:
    - bronze_load_timestamp: When the record was loaded
    - bronze_source_system: Source system identifier
    - bronze_source_table: Original table name
    - bronze_source_host: Source database host
    - bronze_extraction_method: How data was extracted
    """
    __tablename__ = "bronze_film"

    # Business fields from source
    film_id: int = Field(primary_key=True)
    title: str
    description: Optional[str] = None
    release_year: Optional[int] = None
    language_id: int
    rental_duration: int
    rental_rate: float
    length: Optional[int] = None
    replacement_cost: float
    rating: Optional[str] = None
    last_update: datetime
    special_features: Optional[str] = None
    fulltext: Optional[str] = None


class ActorBronze(SQLModel, BronzeMetadata, table=True):
    """
    Bronze layer actor table.

    Demonstrates that BronzeMetadata works with any table structure.
    """
    __tablename__ = "bronze_actor"

    # Business fields
    actor_id: int = Field(primary_key=True)
    first_name: str
    last_name: str
    last_update: datetime


class CustomerBronze(SQLModel, BronzeMetadata, table=True):
    """
    Bronze layer customer table.
    """
    __tablename__ = "bronze_customer"

    customer_id: int = Field(primary_key=True)
    store_id: int
    first_name: str
    last_name: str
    email: Optional[str] = None
    address_id: int
    activebool: bool = True
    create_date: datetime
    last_update: Optional[datetime] = None
    active: Optional[int] = None