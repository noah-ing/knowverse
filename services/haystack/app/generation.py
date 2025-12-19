"""
LLM integration module for generation tasks in KnowVerse.
This module provides a flexible framework for integrating with various LLM providers.
"""

import logging
import time
import os
import asyncio
import json
from typing import Dict, List, Optional, Any, Union
from config.settings import (
    OPENAI_API_KEY, ANTHROPIC_API_KEY, 
    ENABLE_LOCAL_LLM, LOCAL_LLM_PATH,
    DEFAULT_LLM_PROVIDER, DEFAULT_OPENAI_MODEL,
    DEFAULT_ANTHROPIC_MODEL
)

# Setup logging
logger = logging.getLogger(__name__)

class LLMProvider:
    """Base abstract class for LLM providers."""
    
    def generate(self, prompt: str, context: List[Dict[str, Any]], options: Optional[Dict[str, Any]] = None) -> str:
        """
        Generate a response using the provider's LLM.
        
        Args:
            prompt: The user query or prompt
            context: List of context documents with text and metadata
            options: Generation options (temperature, max_tokens, etc.)
            
        Returns:
            Generated text response
        """
        raise NotImplementedError("Subclasses must implement generate()")
        
    async def generate_stream(self, prompt: str, context: List[Dict[str, Any]], options: Optional[Dict[str, Any]] = None):
        """
        Stream-generate a response using the provider's LLM.
        
        Args:
            prompt: The user query or prompt
            context: List of context documents with text and metadata
            options: Generation options (temperature, max_tokens, etc.)
            
        Yields:
            Token-by-token generated text response
        """
        raise NotImplementedError("Subclasses must implement generate_stream()")
    
    def format_context(self, context: List[Dict[str, Any]]) -> str:
        """
        Format context documents into a string suitable for the LLM.
        
        Args:
            context: List of context documents with text and metadata
            
        Returns:
            Formatted context string
        """
        formatted_context = ""
        
        for i, doc in enumerate(context):
            formatted_context += f"Document {i+1}: {doc.get('title', 'Untitled')}\n"
            formatted_context += f"Source: {doc.get('source', 'Unknown')}\n"
            formatted_context += f"Content: {doc.get('text', '')}\n\n"
            
        return formatted_context.strip()


class OpenAIProvider(LLMProvider):
    """Integration with OpenAI API."""
    
    def __init__(self, api_key: Optional[str] = None):
        """
        Initialize the OpenAI provider.
        
        Args:
            api_key: OpenAI API key. If None, uses OPENAI_API_KEY environment variable.
        """
        try:
            import openai
        except ImportError:
            raise ImportError("OpenAI package not installed. Install with 'pip install openai'")
        
        self.api_key = api_key or os.environ.get("OPENAI_API_KEY")
        if not self.api_key:
            raise ValueError("OpenAI API key not provided and OPENAI_API_KEY not set in environment")
        
        self.client = openai.Client(api_key=self.api_key)
    
    def generate(self, prompt: str, context: List[Dict[str, Any]], options: Optional[Dict[str, Any]] = None) -> str:
        """
        Generate a response using OpenAI's API.
        
        Args:
            prompt: The user query or prompt
            context: List of context documents with text and metadata
            options: Generation options (model, temperature, max_tokens, etc.)
            
        Returns:
            Generated text response
        """
        options = options or {}
        model = options.get("model") or DEFAULT_OPENAI_MODEL  # Handle None values
        temperature = options.get("temperature") or 0.7
        max_tokens = options.get("max_tokens") or 500

        formatted_context = self.format_context(context)

        system_prompt = options.get("system_prompt") or (
            "You are a knowledgeable assistant. Answer the user's question based only on the provided context. "
            "If the answer cannot be determined from the context, say so clearly.")

        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": f"Context information:\n\n{formatted_context}\n\nQuestion: {prompt}"}
        ]

        try:
            start_time = time.time()
            response = self.client.chat.completions.create(
                model=model,
                messages=messages,
                temperature=temperature,
                max_tokens=max_tokens
            )
            
            logger.info(f"OpenAI request completed in {time.time() - start_time:.2f}s")
            
            return response.choices[0].message.content
        except Exception as e:
            logger.error(f"Error generating response with OpenAI: {e}")
            return f"Error generating response: {str(e)}"


    async def generate_stream(self, prompt: str, context: List[Dict[str, Any]], options: Optional[Dict[str, Any]] = None):
        """
        Stream-generate a response using OpenAI's API.
        
        Args:
            prompt: The user query or prompt
            context: List of context documents with text and metadata
            options: Generation options (model, temperature, max_tokens, etc.)
            
        Yields:
            Token-by-token generated text response
        """
        options = options or {}
        model = options.get("model") or DEFAULT_OPENAI_MODEL  # Handle None values
        temperature = options.get("temperature") or 0.7
        max_tokens = options.get("max_tokens") or 500

        formatted_context = self.format_context(context)

        system_prompt = options.get("system_prompt") or (
            "You are a knowledgeable assistant. Answer the user's question based only on the provided context. "
            "If the answer cannot be determined from the context, say so clearly.")

        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": f"Context information:\n\n{formatted_context}\n\nQuestion: {prompt}"}
        ]

        try:
            start_time = time.time()
            stream = await asyncio.to_thread(
                self.client.chat.completions.create,
                model=model,
                messages=messages,
                temperature=temperature,
                max_tokens=max_tokens,
                stream=True  # Enable streaming
            )
            
            logger.info(f"OpenAI stream started in {time.time() - start_time:.2f}s")
            first_token_time = None
            
            # Process the streaming response using the Completion object's stream iterator
            for chunk in stream:
                # Record time to first token
                if first_token_time is None and chunk.choices and chunk.choices[0].delta.content:
                    first_token_time = time.time() - start_time
                    logger.info(f"OpenAI first token time: {first_token_time*1000:.2f}ms")
                
                # Extract and yield the token
                if chunk.choices and chunk.choices[0].delta.content:
                    yield chunk.choices[0].delta.content
                
                # Add a small delay to simulate a consistent streaming rate if needed
                # This can help maintain the 15-20 tokens/second requirement
                if options.get("regulate_token_rate", False):
                    await asyncio.sleep(0.05)  # ~20 tokens per second
                
        except Exception as e:
            logger.error(f"Error streaming response with OpenAI: {e}")
            yield f"Error generating response: {str(e)}"

class AnthropicProvider(LLMProvider):
    """Integration with Anthropic API."""
    
    def __init__(self, api_key: Optional[str] = None):
        """
        Initialize the Anthropic provider.
        
        Args:
            api_key: Anthropic API key. If None, uses ANTHROPIC_API_KEY environment variable.
        """
        try:
            import anthropic
        except ImportError:
            raise ImportError("Anthropic package not installed. Install with 'pip install anthropic'")
        
        self.api_key = api_key or os.environ.get("ANTHROPIC_API_KEY")
        if not self.api_key:
            raise ValueError("Anthropic API key not provided and ANTHROPIC_API_KEY not set in environment")
        
        self.client = anthropic.Anthropic(api_key=self.api_key)
    
    def generate(self, prompt: str, context: List[Dict[str, Any]], options: Optional[Dict[str, Any]] = None) -> str:
        """
        Generate a response using Anthropic's API.
        
        Args:
            prompt: The user query or prompt
            context: List of context documents with text and metadata
            options: Generation options (model, temperature, max_tokens, etc.)
            
        Returns:
            Generated text response
        """
        options = options or {}
        model = options.get("model", DEFAULT_ANTHROPIC_MODEL)
        temperature = options.get("temperature", 0.7)
        max_tokens = options.get("max_tokens", 500)
        
        formatted_context = self.format_context(context)
        
        system_prompt = options.get("system_prompt", 
            "You are a knowledgeable assistant. Answer the user's question based only on the provided context. "
            "If the answer cannot be determined from the context, say so clearly.")
        
        try:
            start_time = time.time()
            response = self.client.messages.create(
                model=model,
                system=system_prompt,
                max_tokens=max_tokens,
                temperature=temperature,
                messages=[
                    {
                        "role": "user",
                        "content": f"Context information:\n\n{formatted_context}\n\nQuestion: {prompt}"
                    }
                ]
            )
            
            logger.info(f"Anthropic request completed in {time.time() - start_time:.2f}s")
            
            return response.content[0].text
        except Exception as e:
            logger.error(f"Error generating response with Anthropic: {e}")
            return f"Error generating response: {str(e)}"


    async def generate_stream(self, prompt: str, context: List[Dict[str, Any]], options: Optional[Dict[str, Any]] = None):
        """
        Stream-generate a response using Anthropic's API.
        
        Args:
            prompt: The user query or prompt
            context: List of context documents with text and metadata
            options: Generation options (model, temperature, max_tokens, etc.)
            
        Yields:
            Token-by-token generated text response
        """
        options = options or {}
        model = options.get("model", DEFAULT_ANTHROPIC_MODEL)
        temperature = options.get("temperature", 0.7)
        max_tokens = options.get("max_tokens", 500)
        
        formatted_context = self.format_context(context)
        
        system_prompt = options.get("system_prompt", 
            "You are a knowledgeable assistant. Answer the user's question based only on the provided context. "
            "If the answer cannot be determined from the context, say so clearly.")
        
        try:
            start_time = time.time()
            first_token_time = None
            
            # Create a function to be run in a separate thread
            def create_stream():
                return self.client.messages.stream(
                    model=model,
                    system=system_prompt,
                    max_tokens=max_tokens,
                    temperature=temperature,
                    messages=[
                        {
                            "role": "user",
                            "content": f"Context information:\n\n{formatted_context}\n\nQuestion: {prompt}"
                        }
                    ]
                )
            
            # Run the stream creation in a separate thread
            stream_context_manager = await asyncio.to_thread(create_stream)
            with stream_context_manager as stream:
                logger.info(f"Anthropic stream started in {time.time() - start_time:.2f}s")
                
                async for text in stream.text_stream:
                    # Record time to first token
                    if first_token_time is None and text.strip():
                        first_token_time = time.time() - start_time
                        logger.info(f"Anthropic first token time: {first_token_time*1000:.2f}ms")
                    
                    yield text
                    
                    # Add a small delay to simulate a consistent streaming rate if needed
                    if options.get("regulate_token_rate", False):
                        await asyncio.sleep(0.05)  # ~20 tokens per second
                    
        except Exception as e:
            logger.error(f"Error streaming response with Anthropic: {e}")
            yield f"Error generating response: {str(e)}"

class LocalProvider(LLMProvider):
    """Integration with locally hosted models using Hugging Face transformers."""
    
    def __init__(self, model_name_or_path: str = "meta-llama/Llama-2-7b-chat-hf"):
        """
        Initialize the local provider.
        
        Args:
            model_name_or_path: Hugging Face model name or local path
        """
        try:
            import torch
            from transformers import AutoModelForCausalLM, AutoTokenizer, pipeline
        except ImportError:
            raise ImportError("Required packages not installed. Install with 'pip install torch transformers'")
        
        self.model_name = model_name_or_path
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        
        try:
            logger.info(f"Loading local model {model_name_or_path} on {self.device}")
            self.tokenizer = AutoTokenizer.from_pretrained(model_name_or_path)
            self.model = AutoModelForCausalLM.from_pretrained(
                model_name_or_path, 
                torch_dtype=torch.float16 if self.device == "cuda" else torch.float32,
                low_cpu_mem_usage=True,
                device_map="auto"
            )
            
            self.generator = pipeline(
                "text-generation",
                model=self.model,
                tokenizer=self.tokenizer,
                device_map="auto"
            )
            logger.info(f"Local model loaded successfully")
        except Exception as e:
            logger.error(f"Error loading local model: {e}")
            raise
    
    def generate(self, prompt: str, context: List[Dict[str, Any]], options: Optional[Dict[str, Any]] = None) -> str:
        """
        Generate a response using a local model.
        
        Args:
            prompt: The user query or prompt
            context: List of context documents with text and metadata
            options: Generation options (temperature, max_tokens, etc.)
            
        Returns:
            Generated text response
        """
        options = options or {}
        temperature = options.get("temperature", 0.7)
        max_tokens = options.get("max_tokens", 500)
        
        formatted_context = self.format_context(context)
        
        # Format prompt for local model (may vary by model type)
        if "llama" in self.model_name.lower():
            # Llama-specific formatting
            full_prompt = f"<s>[INST] <<SYS>>\nYou are a knowledgeable assistant. Answer the user's question based only on the provided context. If the answer cannot be determined from the context, say so clearly.\n<</SYS>>\n\nContext information:\n\n{formatted_context}\n\nQuestion: {prompt} [/INST]"
        else:
            # Generic prompt
            full_prompt = f"Context information:\n\n{formatted_context}\n\nQuestion: {prompt}\n\nAnswer:"
        
        try:
            start_time = time.time()
            result = self.generator(
                full_prompt,
                max_new_tokens=max_tokens,
                temperature=temperature,
                do_sample=True,
                num_return_sequences=1
            )
            
            logger.info(f"Local model generation completed in {time.time() - start_time:.2f}s")
            
            # Extract generated text, removing the prompt
            generated_text = result[0]["generated_text"]
            answer = generated_text[len(full_prompt):].strip()
            
            return answer
        except Exception as e:
            logger.error(f"Error generating response with local model: {e}")
            return f"Error generating response: {str(e)}"


    async def generate_stream(self, prompt: str, context: List[Dict[str, Any]], options: Optional[Dict[str, Any]] = None):
        """
        Stream-generate a response using a local model.
        Note: This is a simplified implementation that doesn't actually stream tokens
        from local models, since most HF implementations don't support true streaming.
        Instead, it generates the full response and yields it token by token with small delays.
        
        Args:
            prompt: The user query or prompt
            context: List of context documents with text and metadata
            options: Generation options (temperature, max_tokens, etc.)
            
        Yields:
            Token-by-token generated text response
        """
        options = options or {}
        temperature = options.get("temperature", 0.7)
        max_tokens = options.get("max_tokens", 500)
        token_rate = options.get("token_rate", 20)  # Tokens per second
        
        formatted_context = self.format_context(context)
        
        # Format prompt for local model (may vary by model type)
        if "llama" in self.model_name.lower():
            # Llama-specific formatting
            full_prompt = f"<s>[INST] <<SYS>>\nYou are a knowledgeable assistant. Answer the user's question based only on the provided context. If the answer cannot be determined from the context, say so clearly.\n<</SYS>>\n\nContext information:\n\n{formatted_context}\n\nQuestion: {prompt} [/INST]"
        else:
            # Generic prompt
            full_prompt = f"Context information:\n\n{formatted_context}\n\nQuestion: {prompt}\n\nAnswer:"
        
        try:
            start_time = time.time()
            first_token_sent = False
            
            # Start a timer to measure time to first token
            generation_start = time.time()
            
            # Generate the full response first (non-streaming implementation)
            logger.info(f"Starting local model generation")
            result = await asyncio.to_thread(
                self.generator,
                full_prompt,
                max_new_tokens=max_tokens,
                temperature=temperature,
                do_sample=True,
                num_return_sequences=1
            )
            
            generation_time = time.time() - generation_start
            logger.info(f"Local model generation completed in {generation_time:.2f}s")
            
            # Extract generated text, removing the prompt
            generated_text = result[0]["generated_text"]
            answer = generated_text[len(full_prompt):].strip()
            
            # Simulate streaming by yielding chunks of text with small delays
            # Calculate token delay based on desired token rate
            token_delay = 1.0 / token_rate  # Default: 0.05s for 20 tokens/second
            
            # Split into "tokens" (we're using words as a proxy for tokens)
            tokens = answer.split(" ")
            
            # Simulate a brief initial delay for more realistic streaming
            await asyncio.sleep(0.3)  # 300ms initial delay
            
            for token in tokens:
                # Record time to first token
                if not first_token_sent:
                    first_token_time = time.time() - start_time
                    logger.info(f"Local model first token time: {first_token_time*1000:.2f}ms")
                    first_token_sent = True
                
                yield token + " "
                
                # Regulate token rate by delaying between tokens
                await asyncio.sleep(token_delay)
                
        except Exception as e:
            logger.error(f"Error generating response with local model: {e}")
            yield f"Error generating response: {str(e)}"

class LLMProviderRegistry:
    """Registry for managing and selecting LLM providers."""
    
    def __init__(self):
        """Initialize an empty provider registry."""
        self._providers = {}
        self._default_provider = None
    
    def register(self, name: str, provider: LLMProvider, default: bool = False):
        """
        Register an LLM provider.
        
        Args:
            name: Provider name
            provider: LLM provider instance
            default: Whether this provider should be the default
        """
        self._providers[name] = provider
        if default or self._default_provider is None:
            self._default_provider = name
            
        logger.info(f"Registered LLM provider: {name} (default: {default})")
    
    def get_provider(self, name: Optional[str] = None) -> LLMProvider:
        """
        Get a provider by name.
        
        Args:
            name: Provider name, or None for default
            
        Returns:
            LLM provider instance
            
        Raises:
            ValueError: If provider not found
        """
        if name is None:
            if self._default_provider is None:
                raise ValueError("No default provider registered")
            return self._providers[self._default_provider]
        
        if name not in self._providers:
            raise ValueError(f"Provider '{name}' not registered")
        
        return self._providers[name]
    
    def list_providers(self) -> List[str]:
        """
        List all registered provider names.
        
        Returns:
            List of provider names
        """
        return list(self._providers.keys())


    async def generate_stream_with_fallback(self, prompt: str, context: List[Dict[str, Any]], 
                                           providers_priority: List[str] = None, options: Optional[Dict[str, Any]] = None):
        """
        Stream a response using multiple providers with fallback support.
        
        Args:
            prompt: The user query
            context: Context documents
            providers_priority: List of provider names in priority order
            options: Generation options
            
        Yields:
            Token-by-token response with fallback information when needed
        """
        if not providers_priority:
            # Default priority (could be configurable)
            providers_priority = ["openai", "anthropic", "local"]
            
        # Filter to available providers only
        available_providers = self.list_providers()
        providers_to_try = [p for p in providers_priority if p in available_providers]
        
        if not providers_to_try:
            yield json.dumps({"error": "No available providers configured"})
            return
            
        # Try each provider in sequence
        for i, provider_name in enumerate(providers_to_try):
            try:
                provider = self.get_provider(provider_name)
                
                # If fallback, yield a notification
                if i > 0:
                    fallback_info = {
                        "event": "fallback",
                        "from": providers_to_try[i-1],
                        "to": provider_name
                    }
                    yield json.dumps(fallback_info) + "\n"
                
                # Generate with the selected provider
                async for token in provider.generate_stream(prompt, context, options):
                    yield token
                
                # If successful, don't try other providers
                break
                
            except Exception as e:
                logger.error(f"Provider {provider_name} failed: {e}")
                # If this is the last provider, yield error
                if i == len(providers_to_try) - 1:
                    yield json.dumps({"error": f"All providers failed: {str(e)}"})

# Initialize and configure provider registry
def create_provider_registry() -> LLMProviderRegistry:
    """
    Create and configure the LLM provider registry with available providers.
    
    Returns:
        Configured provider registry
    """
    registry = LLMProviderRegistry()
    
    # Try to initialize OpenAI provider if API key is available
    if OPENAI_API_KEY:
        try:
            is_default = DEFAULT_LLM_PROVIDER == 'openai'
            registry.register("openai", OpenAIProvider(OPENAI_API_KEY), default=is_default)
            logger.info(f"OpenAI provider registered successfully (default: {is_default})")
        except Exception as e:
            logger.warning(f"Failed to register OpenAI provider: {e}")
    
    # Try to initialize Anthropic provider if API key is available
    if ANTHROPIC_API_KEY:
        try:
            is_default = DEFAULT_LLM_PROVIDER == 'anthropic'
            registry.register("anthropic", AnthropicProvider(ANTHROPIC_API_KEY), default=is_default)
            logger.info(f"Anthropic provider registered successfully (default: {is_default})")
        except Exception as e:
            logger.warning(f"Failed to register Anthropic provider: {e}")
    
    # Try to initialize local provider if enabled
    if ENABLE_LOCAL_LLM:
        try:
            is_default = DEFAULT_LLM_PROVIDER == 'local'
            registry.register("local", LocalProvider(LOCAL_LLM_PATH), default=is_default)
            logger.info(f"Local provider registered successfully with model {LOCAL_LLM_PATH} (default: {is_default})")
        except Exception as e:
            logger.warning(f"Failed to register local provider: {e}")
    
    return registry


# Global provider registry
llm_registry = create_provider_registry()
