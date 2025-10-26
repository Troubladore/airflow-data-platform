"""Pydantic models for wizard schema validation."""

from typing import List, Dict, Any, Optional, Union
from pydantic import BaseModel, ConfigDict, Field


class Step(BaseModel):
    """
    Represents a single step in a wizard flow.

    A step can be:
    - An input prompt (string, boolean, enum)
    - An action (side effect via runner)
    - A display message
    """

    model_config = ConfigDict(extra="allow")

    id: str = Field(..., description="Unique step identifier")
    type: str = Field(..., description="Step type: string, boolean, enum, action, display")
    prompt: Optional[str] = Field(None, description="Prompt text to display to user")
    state_key: Optional[str] = Field(None, description="Key in state dict to store value")
    default_value: Optional[Any] = Field(None, description="Default value if no input")
    default_from: Optional[str] = Field(None, description="State key to read default from")
    validator: Optional[str] = Field(None, description="Validator function name (e.g., 'postgres.validate_image_url')")
    action: Optional[str] = Field(None, description="Action function name (e.g., 'postgres.save_config')")
    next: Optional[Union[str, Dict[str, Any]]] = Field(None, description="Next step ID or conditional dict")
    options: Optional[List[Dict[str, str]]] = Field(None, description="Options for enum type")


class ServiceSpec(BaseModel):
    """
    Specification for a single service module.

    Each service defines its own steps, dependencies, and capabilities.
    """

    model_config = ConfigDict(extra="allow")

    service: str = Field(..., description="Service identifier (e.g., 'postgres')")
    version: Union[str, float] = Field(..., description="Service spec version")
    description: str = Field(..., description="Human-readable description")
    requires: List[str] = Field(default_factory=list, description="Required capabilities from other services")
    provides: List[str] = Field(default_factory=list, description="Capabilities provided by this service")
    steps: List[Step] = Field(default_factory=list, description="Conversation flow steps")


class Flow(BaseModel):
    """
    Orchestration flow that composes multiple services.

    Flows define service selection and execution order based on dependencies.
    """

    model_config = ConfigDict(extra="allow")

    name: str = Field(..., description="Flow identifier (e.g., 'setup')")
    version: str = Field(..., description="Flow spec version")
    description: str = Field(..., description="Human-readable description")
    service_selection: List[Step] = Field(default_factory=list, description="Steps for selecting services")
    targets: List[Dict[str, Any]] = Field(default_factory=list, description="Services to include in flow")
    glue: Optional[List[Dict[str, Any]]] = Field(None, description="Cross-service coordination steps")
    policy: Optional[Dict[str, str]] = Field(None, description="Execution policy (ordering, failure handling)")
