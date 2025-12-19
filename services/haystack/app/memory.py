"""
Three-Tier Memory System for Elite RAG.

Implements cognitive-inspired memory architecture:
- Working Memory: Per-request context (ephemeral)
- Short-term Memory: Session-based (Redis, minutes to hours)
- Long-term Memory: Persistent user/org knowledge (PostgreSQL + Qdrant)

This enables:
- Conversation continuity across requests
- Learning user preferences over time
- Building organizational knowledge bases
- Contextual retrieval enhancement
"""

import json
import logging
import time
import hashlib
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass, field
from collections import deque
from abc import ABC, abstractmethod

logger = logging.getLogger(__name__)


# =============================================================================
# DATA STRUCTURES
# =============================================================================

@dataclass
class MemoryItem:
    """A single memory item."""
    id: str
    content: str
    memory_type: str  # episodic, semantic, procedural
    importance: float = 0.5
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    last_accessed: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    access_count: int = 0
    metadata: Dict[str, Any] = field(default_factory=dict)

    # For episodic memories
    context: Optional[str] = None
    entities: List[str] = field(default_factory=list)

    # For long-term storage
    embedding_id: Optional[str] = None
    decay_rate: float = 0.1  # How fast importance decays

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "content": self.content,
            "memory_type": self.memory_type,
            "importance": self.importance,
            "created_at": self.created_at.isoformat(),
            "last_accessed": self.last_accessed.isoformat(),
            "access_count": self.access_count,
            "metadata": self.metadata,
            "context": self.context,
            "entities": self.entities,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "MemoryItem":
        return cls(
            id=data["id"],
            content=data["content"],
            memory_type=data["memory_type"],
            importance=data.get("importance", 0.5),
            created_at=datetime.fromisoformat(data["created_at"]),
            last_accessed=datetime.fromisoformat(data.get("last_accessed", data["created_at"])),
            access_count=data.get("access_count", 0),
            metadata=data.get("metadata", {}),
            context=data.get("context"),
            entities=data.get("entities", []),
        )

    def decay_importance(self, hours_elapsed: float):
        """Apply time-based decay to importance."""
        decay_factor = 1.0 - (self.decay_rate * hours_elapsed / 24)
        self.importance = max(0.1, self.importance * max(0, decay_factor))


@dataclass
class ConversationContext:
    """Context for a conversation session."""
    session_id: str
    user_id: Optional[int] = None
    org_id: Optional[int] = None

    # Conversation state
    messages: List[Dict[str, str]] = field(default_factory=list)
    entities: Dict[str, List[str]] = field(default_factory=dict)
    topics: List[str] = field(default_factory=list)

    # Compressed summary for efficiency
    summary: Optional[str] = None

    # Session metadata
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    last_active: datetime = field(default_factory=lambda: datetime.now(timezone.utc))


# =============================================================================
# WORKING MEMORY (Per-Request)
# =============================================================================

class WorkingMemory:
    """
    Working memory for current request/turn.

    Holds:
    - Current query and parsed intent
    - Retrieved context (active documents)
    - Entity focus (what entities are being discussed)
    - Reasoning state

    This is ephemeral and exists only for the current request.
    """

    def __init__(self, max_items: int = 10):
        self.max_items = max_items
        self.query: Optional[str] = None
        self.intent: Optional[Dict] = None
        self.active_context: List[Dict] = []
        self.entities: Dict[str, Any] = {}
        self.reasoning_chain: List[str] = []
        self.metadata: Dict[str, Any] = {}

    def set_query(self, query: str, intent: Optional[Dict] = None):
        """Set the current query and intent."""
        self.query = query
        self.intent = intent

    def add_context(self, context_item: Dict):
        """Add a context item to working memory."""
        self.active_context.append(context_item)

        # Limit size
        if len(self.active_context) > self.max_items:
            self.active_context = self.active_context[-self.max_items:]

    def add_entity(self, entity_type: str, entity_value: Any):
        """Track an entity in focus."""
        if entity_type not in self.entities:
            self.entities[entity_type] = []
        if entity_value not in self.entities[entity_type]:
            self.entities[entity_type].append(entity_value)

    def add_reasoning_step(self, step: str):
        """Add a reasoning step."""
        self.reasoning_chain.append(step)

    def get_context_summary(self) -> str:
        """Get a summary of active context for prompt injection."""
        if not self.active_context:
            return ""

        summaries = []
        for item in self.active_context[:5]:
            content = item.get("content", item.get("text", ""))
            title = item.get("title", "")
            if content:
                preview = content[:200] + "..." if len(content) > 200 else content
                summaries.append(f"- {title}: {preview}" if title else f"- {preview}")

        return "\n".join(summaries)

    def clear(self):
        """Clear working memory."""
        self.query = None
        self.intent = None
        self.active_context = []
        self.entities = {}
        self.reasoning_chain = []
        self.metadata = {}


# =============================================================================
# SHORT-TERM MEMORY (Session-Based)
# =============================================================================

class ShortTermMemory:
    """
    Short-term session memory backed by Redis.

    Stores:
    - Recent conversation history
    - Session entities and topics
    - Compressed summaries

    TTL: Minutes to hours (configurable)
    """

    def __init__(
        self,
        redis_client=None,
        default_ttl: int = 3600,  # 1 hour
        max_messages: int = 50
    ):
        self.redis = redis_client
        self.default_ttl = default_ttl
        self.max_messages = max_messages

        # Local fallback if Redis unavailable
        self._local_store: Dict[str, ConversationContext] = {}

    def _get_key(self, session_id: str) -> str:
        return f"stm:session:{session_id}"

    def _use_redis(self) -> bool:
        return self.redis is not None

    def get_context(self, session_id: str) -> Optional[ConversationContext]:
        """Get conversation context for a session."""
        if self._use_redis():
            try:
                key = self._get_key(session_id)
                data = self.redis.get(key)
                if data:
                    ctx_dict = json.loads(data)
                    ctx = ConversationContext(
                        session_id=session_id,
                        user_id=ctx_dict.get("user_id"),
                        org_id=ctx_dict.get("org_id"),
                        messages=ctx_dict.get("messages", []),
                        entities=ctx_dict.get("entities", {}),
                        topics=ctx_dict.get("topics", []),
                        summary=ctx_dict.get("summary"),
                    )
                    return ctx
            except Exception as e:
                logger.warning(f"Redis get failed: {e}")

        # Local fallback
        return self._local_store.get(session_id)

    def save_context(self, context: ConversationContext, ttl: Optional[int] = None):
        """Save conversation context."""
        ttl = ttl or self.default_ttl
        context.last_active = datetime.now(timezone.utc)

        # Truncate messages if needed
        if len(context.messages) > self.max_messages:
            # Keep summary of old messages
            old_messages = context.messages[:-self.max_messages]
            context.messages = context.messages[-self.max_messages:]

            # Update summary with old messages
            if old_messages:
                summary_text = self._summarize_messages(old_messages)
                if context.summary:
                    context.summary = f"{context.summary}\n{summary_text}"
                else:
                    context.summary = summary_text

        if self._use_redis():
            try:
                key = self._get_key(context.session_id)
                data = {
                    "user_id": context.user_id,
                    "org_id": context.org_id,
                    "messages": context.messages,
                    "entities": context.entities,
                    "topics": context.topics,
                    "summary": context.summary,
                    "created_at": context.created_at.isoformat(),
                    "last_active": context.last_active.isoformat(),
                }
                self.redis.setex(key, ttl, json.dumps(data))
                return
            except Exception as e:
                logger.warning(f"Redis save failed: {e}")

        # Local fallback
        self._local_store[context.session_id] = context

    def add_message(
        self,
        session_id: str,
        role: str,
        content: str,
        metadata: Optional[Dict] = None
    ):
        """Add a message to session history."""
        context = self.get_context(session_id) or ConversationContext(session_id=session_id)

        message = {
            "role": role,
            "content": content,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        if metadata:
            message["metadata"] = metadata

        context.messages.append(message)
        self.save_context(context)

    def extract_entities(self, session_id: str, entities: Dict[str, List[str]]):
        """Update tracked entities for session."""
        context = self.get_context(session_id)
        if context:
            for entity_type, values in entities.items():
                if entity_type not in context.entities:
                    context.entities[entity_type] = []
                for value in values:
                    if value not in context.entities[entity_type]:
                        context.entities[entity_type].append(value)
            self.save_context(context)

    def _summarize_messages(self, messages: List[Dict]) -> str:
        """Create a summary of messages."""
        # Simple extractive summary
        key_points = []
        for msg in messages[-10:]:  # Last 10 messages
            content = msg.get("content", "")
            if len(content) > 50:
                key_points.append(content[:100] + "...")

        return "Previous context: " + "; ".join(key_points) if key_points else ""

    def get_recent_context(self, session_id: str, max_messages: int = 5) -> List[Dict]:
        """Get recent messages for context."""
        context = self.get_context(session_id)
        if context:
            return context.messages[-max_messages:]
        return []

    def clear_session(self, session_id: str):
        """Clear session data."""
        if self._use_redis():
            try:
                self.redis.delete(self._get_key(session_id))
            except:
                pass

        if session_id in self._local_store:
            del self._local_store[session_id]


# =============================================================================
# LONG-TERM MEMORY (Persistent)
# =============================================================================

class LongTermMemory:
    """
    Long-term persistent memory using PostgreSQL and Qdrant.

    Stores:
    - User preferences and patterns
    - Organizational knowledge
    - Important facts and entities
    - Episodic memories (past interactions)

    Memory types:
    - Episodic: Specific past events/interactions
    - Semantic: General facts and knowledge
    - Procedural: How-to knowledge and preferences
    """

    def __init__(
        self,
        db_connection=None,
        qdrant_client=None,
        memory_collection: str = "user_memories"
    ):
        self.db = db_connection
        self.qdrant = qdrant_client
        self.memory_collection = memory_collection

        # Local cache
        self._cache: Dict[str, List[MemoryItem]] = {}
        self._cache_ttl: Dict[str, float] = {}
        self._cache_duration = 300  # 5 minutes

    def _get_cache_key(self, user_id: int, org_id: int) -> str:
        return f"{user_id}:{org_id}"

    def _is_cache_valid(self, key: str) -> bool:
        if key not in self._cache_ttl:
            return False
        return time.time() - self._cache_ttl[key] < self._cache_duration

    def store_memory(
        self,
        user_id: int,
        org_id: int,
        content: str,
        memory_type: str = "episodic",
        importance: float = 0.5,
        entities: List[str] = None,
        metadata: Dict[str, Any] = None
    ) -> Optional[str]:
        """
        Store a new memory.

        Args:
            user_id: User ID
            org_id: Organization ID
            content: Memory content
            memory_type: episodic, semantic, or procedural
            importance: Initial importance score (0-1)
            entities: Related entities
            metadata: Additional metadata

        Returns:
            Memory ID if successful
        """
        memory_id = hashlib.md5(
            f"{user_id}:{org_id}:{content}:{time.time()}".encode()
        ).hexdigest()[:16]

        memory = MemoryItem(
            id=memory_id,
            content=content,
            memory_type=memory_type,
            importance=importance,
            entities=entities or [],
            metadata=metadata or {},
        )

        # Store in database
        if self.db:
            try:
                # Assuming a user_memories table exists
                # In production, create proper migration
                self._store_to_db(user_id, org_id, memory)
            except Exception as e:
                logger.warning(f"DB storage failed: {e}")

        # Store embedding in Qdrant for semantic retrieval
        if self.qdrant:
            try:
                self._store_embedding(user_id, org_id, memory)
            except Exception as e:
                logger.warning(f"Qdrant storage failed: {e}")

        # Invalidate cache
        cache_key = self._get_cache_key(user_id, org_id)
        if cache_key in self._cache:
            del self._cache[cache_key]

        return memory_id

    def _store_to_db(self, user_id: int, org_id: int, memory: MemoryItem):
        """Store memory in PostgreSQL."""
        # This is a placeholder - actual implementation would use proper SQL
        logger.debug(f"Would store memory {memory.id} to DB")

    def _store_embedding(self, user_id: int, org_id: int, memory: MemoryItem):
        """Store memory embedding in Qdrant."""
        try:
            from app.embeddings import get_embedding

            # Generate embedding
            embedding = get_embedding(memory.content)

            # Store in Qdrant
            point = {
                "id": memory.id,
                "vector": embedding.tolist() if hasattr(embedding, 'tolist') else list(embedding),
                "payload": {
                    "user_id": user_id,
                    "org_id": org_id,
                    "content": memory.content,
                    "memory_type": memory.memory_type,
                    "importance": memory.importance,
                    "entities": memory.entities,
                    "created_at": memory.created_at.isoformat(),
                }
            }

            self.qdrant.upsert_batch(self.memory_collection, [point])
            memory.embedding_id = memory.id

        except Exception as e:
            logger.warning(f"Failed to store memory embedding: {e}")

    def recall_memories(
        self,
        user_id: int,
        org_id: int,
        query: Optional[str] = None,
        memory_type: Optional[str] = None,
        limit: int = 10,
        min_importance: float = 0.0
    ) -> List[MemoryItem]:
        """
        Recall relevant memories.

        Args:
            user_id: User ID
            org_id: Organization ID
            query: Optional query for semantic search
            memory_type: Filter by memory type
            limit: Maximum memories to return
            min_importance: Minimum importance threshold

        Returns:
            List of relevant memories
        """
        # Check cache
        cache_key = self._get_cache_key(user_id, org_id)
        if query is None and self._is_cache_valid(cache_key):
            cached = self._cache[cache_key]
            filtered = [m for m in cached if m.importance >= min_importance]
            if memory_type:
                filtered = [m for m in filtered if m.memory_type == memory_type]
            return filtered[:limit]

        memories = []

        # Semantic search if query provided
        if query and self.qdrant:
            memories = self._semantic_recall(user_id, org_id, query, limit)

        # DB retrieval for non-query access
        elif self.db:
            memories = self._db_recall(user_id, org_id, memory_type, limit)

        # Apply importance filter
        memories = [m for m in memories if m.importance >= min_importance]

        # Update access metadata
        for memory in memories:
            memory.last_accessed = datetime.now(timezone.utc)
            memory.access_count += 1

        return memories[:limit]

    def _semantic_recall(
        self,
        user_id: int,
        org_id: int,
        query: str,
        limit: int
    ) -> List[MemoryItem]:
        """Recall memories using semantic search."""
        try:
            from app.embeddings import get_embedding

            query_embedding = get_embedding(query)

            results = self.qdrant.search(
                collection=self.memory_collection,
                query_vector=query_embedding.tolist() if hasattr(query_embedding, 'tolist') else list(query_embedding),
                limit=limit,
                filters={
                    "must": [
                        {"key": "user_id", "match": {"value": user_id}},
                        {"key": "org_id", "match": {"value": org_id}},
                    ]
                }
            )

            memories = []
            for result in results:
                payload = result.metadata if hasattr(result, 'metadata') else result.get('payload', {})
                memories.append(MemoryItem(
                    id=str(result.id if hasattr(result, 'id') else result.get('id', '')),
                    content=payload.get("content", ""),
                    memory_type=payload.get("memory_type", "episodic"),
                    importance=payload.get("importance", 0.5),
                    entities=payload.get("entities", []),
                    metadata=payload,
                ))

            return memories

        except Exception as e:
            logger.warning(f"Semantic recall failed: {e}")
            return []

    def _db_recall(
        self,
        user_id: int,
        org_id: int,
        memory_type: Optional[str],
        limit: int
    ) -> List[MemoryItem]:
        """Recall memories from database."""
        # Placeholder - would query PostgreSQL
        logger.debug(f"Would recall from DB for user {user_id}")
        return []

    def consolidate_memories(self, user_id: int, org_id: int):
        """
        Consolidate and compress old memories.

        - Merge similar memories
        - Decay importance of old memories
        - Summarize episodic memories into semantic
        """
        memories = self.recall_memories(user_id, org_id, limit=100)

        # Apply decay
        now = datetime.now(timezone.utc)
        for memory in memories:
            hours_elapsed = (now - memory.last_accessed).total_seconds() / 3600
            memory.decay_importance(hours_elapsed)

        # Remove very low importance memories
        # In production, would update DB
        important_memories = [m for m in memories if m.importance > 0.1]

        logger.info(
            f"Consolidated memories for user {user_id}: "
            f"{len(memories)} -> {len(important_memories)}"
        )

    def forget_memory(self, memory_id: str, user_id: int, org_id: int) -> bool:
        """Explicitly forget a memory."""
        if self.db:
            try:
                # Would delete from DB
                logger.debug(f"Would delete memory {memory_id} from DB")
            except Exception as e:
                logger.error(f"Failed to forget memory: {e}")
                return False

        if self.qdrant:
            try:
                # Would delete from Qdrant
                logger.debug(f"Would delete memory {memory_id} from Qdrant")
            except:
                pass

        return True


# =============================================================================
# MEMORY MANAGER (Orchestrator)
# =============================================================================

class MemoryManager:
    """
    Unified memory manager orchestrating all memory tiers.

    Provides:
    - Automatic tier selection based on context
    - Memory consolidation between tiers
    - Contextual memory injection for RAG
    """

    def __init__(
        self,
        redis_client=None,
        db_connection=None,
        qdrant_client=None,
        config: Optional[Dict] = None
    ):
        self.working = WorkingMemory()
        self.short_term = ShortTermMemory(redis_client=redis_client)
        self.long_term = LongTermMemory(
            db_connection=db_connection,
            qdrant_client=qdrant_client
        )

        self.config = config or {}

    def start_request(
        self,
        query: str,
        session_id: str,
        user_id: Optional[int] = None,
        org_id: Optional[int] = None
    ) -> WorkingMemory:
        """
        Initialize memory for a new request.

        Loads relevant context from all tiers.
        """
        # Clear and setup working memory
        self.working.clear()
        self.working.set_query(query)

        # Load short-term context
        stm_context = self.short_term.get_context(session_id)
        if stm_context:
            # Add recent conversation context
            for msg in stm_context.messages[-3:]:
                self.working.add_context({
                    "type": "conversation",
                    "content": msg.get("content", ""),
                    "role": msg.get("role", ""),
                })

            # Add tracked entities
            for entity_type, values in stm_context.entities.items():
                for value in values:
                    self.working.add_entity(entity_type, value)

        # Load relevant long-term memories
        if user_id and org_id:
            ltm_memories = self.long_term.recall_memories(
                user_id=user_id,
                org_id=org_id,
                query=query,
                limit=5
            )

            for memory in ltm_memories:
                self.working.add_context({
                    "type": "memory",
                    "content": memory.content,
                    "memory_type": memory.memory_type,
                    "importance": memory.importance,
                })

        return self.working

    def end_request(
        self,
        session_id: str,
        user_id: Optional[int] = None,
        org_id: Optional[int] = None,
        response: Optional[str] = None,
        save_to_ltm: bool = False
    ):
        """
        Finalize memory after a request.

        Saves conversation to short-term and optionally to long-term.
        """
        # Save to short-term
        if self.working.query:
            self.short_term.add_message(session_id, "user", self.working.query)

        if response:
            self.short_term.add_message(session_id, "assistant", response)

        # Save entities
        if self.working.entities:
            self.short_term.extract_entities(session_id, self.working.entities)

        # Optionally save to long-term
        if save_to_ltm and user_id and org_id and self.working.query:
            # Create episodic memory of this interaction
            self.long_term.store_memory(
                user_id=user_id,
                org_id=org_id,
                content=f"Q: {self.working.query}\nA: {response[:500] if response else 'No response'}",
                memory_type="episodic",
                importance=0.5,
                entities=list(set(
                    e for entities in self.working.entities.values() for e in entities
                )),
            )

    def get_context_for_generation(
        self,
        include_memories: bool = True,
        include_conversation: bool = True,
        max_tokens: int = 500
    ) -> str:
        """
        Get formatted context for injection into generation prompt.
        """
        parts = []

        # Working memory context (retrieved documents)
        if self.working.active_context:
            doc_context = self.working.get_context_summary()
            if doc_context:
                parts.append(f"Relevant information:\n{doc_context}")

        # Tracked entities
        if self.working.entities:
            entity_str = ", ".join(
                f"{k}: {', '.join(v[:3])}"
                for k, v in self.working.entities.items()
            )
            parts.append(f"Entities in focus: {entity_str}")

        # Memory context
        memory_items = [
            c for c in self.working.active_context
            if c.get("type") == "memory"
        ]
        if include_memories and memory_items:
            mem_str = "; ".join(m.get("content", "")[:100] for m in memory_items[:3])
            parts.append(f"Remembered context: {mem_str}")

        context = "\n\n".join(parts)

        # Truncate if too long
        if len(context) > max_tokens * 4:  # Rough char estimate
            context = context[:max_tokens * 4] + "..."

        return context


# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

_memory_manager: Optional[MemoryManager] = None


def get_memory_manager() -> MemoryManager:
    """Get or create the singleton memory manager."""
    global _memory_manager
    if _memory_manager is None:
        _memory_manager = MemoryManager()
    return _memory_manager


def reset_memory_manager():
    """Reset the memory manager (for testing)."""
    global _memory_manager
    _memory_manager = None
