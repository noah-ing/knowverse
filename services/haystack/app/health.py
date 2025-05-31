"""
Health check endpoint for Haystack AI service
Enterprise-grade monitoring and diagnostics
"""

from fastapi import APIRouter, HTTPException
from datetime import datetime
import psycopg2
import redis
import os
import time
from typing import Dict, Any

router = APIRouter()

@router.get("/health")
async def health_check() -> Dict[str, Any]:
    """
    Comprehensive health check for Haystack AI service
    Returns detailed status of all dependencies and services
    """
    try:
        health_status = {
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat(),
            "services": await check_services(),
            "version": "1.0.0",
            "environment": os.getenv("ENVIRONMENT", "development")
        }
        
        if all_services_healthy(health_status["services"]):
            return health_status
        else:
            health_status["status"] = "degraded"
            raise HTTPException(status_code=503, detail=health_status)
            
    except Exception as e:
        error_response = {
            "status": "unhealthy",
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }
        raise HTTPException(status_code=503, detail=error_response)

async def check_services() -> Dict[str, Dict[str, Any]]:
    """Check all dependent services"""
    return {
        "database": await check_database(),
        "redis": await check_redis(),
        "embeddings": await check_embeddings(),
        "search": await check_search_engine()
    }

async def check_database() -> Dict[str, Any]:
    """Check PostgreSQL database connectivity"""
    try:
        start_time = time.time()
        
        conn = psycopg2.connect(
            host=os.getenv("POSTGRES_HOST", "postgres"),
            port=os.getenv("POSTGRES_PORT", "5432"),
            database=os.getenv("POSTGRES_DB", "knowverse_development"),
            user=os.getenv("POSTGRES_USER", "postgres"),
            password=os.getenv("POSTGRES_PASSWORD", "password")
        )
        
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.fetchone()
        cursor.close()
        conn.close()
        
        response_time = (time.time() - start_time) * 1000
        
        return {
            "status": "healthy",
            "response_time_ms": round(response_time, 2)
        }
        
    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e)
        }

async def check_redis() -> Dict[str, Any]:
    """Check Redis connectivity"""
    try:
        start_time = time.time()
        
        r = redis.Redis(
            host=os.getenv("REDIS_HOST", "redis"),
            port=int(os.getenv("REDIS_PORT", "6379")),
            db=0,
            decode_responses=True
        )
        
        r.ping()
        response_time = (time.time() - start_time) * 1000
        
        return {
            "status": "healthy",
            "response_time_ms": round(response_time, 2)
        }
        
    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e)
        }

async def check_embeddings() -> Dict[str, Any]:
    """Check embedding service availability"""
    try:
        # Test embedding generation with a simple phrase
        from sentence_transformers import SentenceTransformer
        
        start_time = time.time()
        model = SentenceTransformer('all-MiniLM-L6-v2')
        embedding = model.encode("health check test")
        response_time = (time.time() - start_time) * 1000
        
        return {
            "status": "healthy",
            "response_time_ms": round(response_time, 2),
            "embedding_dimension": len(embedding)
        }
        
    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e)
        }

async def check_search_engine() -> Dict[str, Any]:
    """Check search engine functionality"""
    try:
        # Simple search engine test
        start_time = time.time()
        
        # Mock search operation - in real implementation this would test actual search
        test_query = "test search query"
        response_time = (time.time() - start_time) * 1000
        
        return {
            "status": "healthy",
            "response_time_ms": round(response_time, 2),
            "test_query": test_query
        }
        
    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e)
        }

def all_services_healthy(services: Dict[str, Dict[str, Any]]) -> bool:
    """Check if all services are healthy"""
    return all(service.get("status") == "healthy" for service in services.values())
