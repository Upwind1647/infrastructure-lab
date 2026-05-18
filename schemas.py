from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator


class DeploymentEventCreate(BaseModel):
    git_sha: str = Field(min_length=7, max_length=40)
    committed_at: datetime
    environment: str = Field(min_length=2, max_length=64)
    status: str = Field(min_length=2, max_length=32)

    @field_validator("git_sha")
    @classmethod
    def validate_git_sha(cls, value: str) -> str:
        if not all(char in "0123456789abcdefABCDEF" for char in value):
            raise ValueError("git_sha must be a hexadecimal commit SHA")
        return value


class DeploymentEventRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    git_sha: str
    committed_at: datetime
    deployed_at: datetime
    created_at: datetime
    environment: str
    status: str
