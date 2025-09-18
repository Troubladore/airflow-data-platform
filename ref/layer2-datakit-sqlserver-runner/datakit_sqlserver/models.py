from sqlmodel import SQLModel, Field

class Example(SQLModel, table=True):
    id: int = Field(primary_key=True)
    name: str | None = None
