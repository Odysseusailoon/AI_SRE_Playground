# /home/riftuser/AI_SRE_Playground/fastapi_service.py

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
import service

# Create FastAPI app
app = FastAPI(title="AI SRE Playground API", version="1.0.0")

# Pydantic models for request/response
class SimulationRequest(BaseModel):
    problem_id: str
    agent_name: str = "vllm"
    max_steps: Optional[int] = None
    model: Optional[str] = "Qwen/Qwen2.5-7B-Instruct"
    temperature: Optional[float] = 0.7
    top_p: Optional[float] = 0.9
    max_tokens: Optional[int] = 1024

class SimulationResponse(BaseModel):
    agent: str
    session_id: str
    problem_id: str
    start_time: float
    end_time: float
    trace: List[Dict[str, Any]]
    results: Dict[str, Any]

# API Endpoints
@app.get("/health")
async def health():
    """Health check endpoint"""
    return service.health_check()

@app.get("/problems")
async def get_problems():
    """Get list of available problems"""
    try:
        # This would need to be implemented in service.py
        # For now, return a hardcoded list
        return [
            "container_kill-analysis-1",
            "container_kill-detection-1",
            "container_kill-localization-1",
            "container_kill-mitigation-1",
            "misconfig_app_hotel_res-analysis-1",
            "misconfig_app_hotel_res-detection-1",
            "misconfig_app_hotel_res-localization-1",
            "misconfig_app_hotel_res-mitigation-1"
        ]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/agents")
async def get_agents():
    """Get list of available agents"""
    try:
        return service.list_agents()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/simulate", response_model=SimulationResponse)
async def simulate(request: SimulationRequest):
    """Run a simulation"""
    try:
        # FIX: Set proper ground_truth_dir path
        from pathlib import Path
        ground_truth_dir = Path("/home/riftuser/AI_SRE_Playground/ground_truth")
        
        # Convert Pydantic model to service request
        sim_request = service.SimulationRequest(
            problem_id=request.problem_id,
            agent_name=request.agent_name,
            max_steps=request.max_steps,
            model=request.model,
            temperature=request.temperature,
            top_p=request.top_p,
            max_tokens=request.max_tokens
        )
        
        # Run simulation with proper ground truth directory
        result = service.simulate(sim_request, ground_truth_dir=ground_truth_dir)
        
        return SimulationResponse(
            agent=result.agent,
            session_id=result.session_id,
            problem_id=result.problem_id,
            start_time=result.start_time,
            end_time=result.end_time,
            trace=result.trace,
            results=result.results
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)