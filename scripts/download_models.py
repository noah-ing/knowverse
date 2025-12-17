#!/usr/bin/env python3
"""
Download and prepare ONNX embedding models for Knowverse.

This script downloads sentence-transformer models from HuggingFace,
converts them to ONNX format, and prepares them for the Rust embedding service.

Usage:
    python scripts/download_models.py [--models MODEL1,MODEL2] [--output-dir DIR]

Requirements:
    pip install transformers onnx onnxruntime sentence-transformers optimum
"""

import argparse
import os
import shutil
import sys
from pathlib import Path

# Models to download with their HuggingFace IDs
MODELS = {
    "all-MiniLM-L6-v2": {
        "hf_id": "sentence-transformers/all-MiniLM-L6-v2",
        "dimension": 384,
        "max_tokens": 256,
        "description": "Fast, lightweight model for general-purpose embeddings"
    },
    "all-mpnet-base-v2": {
        "hf_id": "sentence-transformers/all-mpnet-base-v2",
        "dimension": 768,
        "max_tokens": 384,
        "description": "High-quality embeddings, best for semantic search"
    },
    "bge-small-en-v1.5": {
        "hf_id": "BAAI/bge-small-en-v1.5",
        "dimension": 384,
        "max_tokens": 512,
        "description": "BGE small model, excellent quality/speed ratio"
    },
    "bge-base-en-v1.5": {
        "hf_id": "BAAI/bge-base-en-v1.5",
        "dimension": 768,
        "max_tokens": 512,
        "description": "BGE base model, high quality embeddings"
    },
    "bge-large-en-v1.5": {
        "hf_id": "BAAI/bge-large-en-v1.5",
        "dimension": 1024,
        "max_tokens": 512,
        "description": "BGE large model, best quality (slower)"
    },
}


def check_dependencies():
    """Check if required packages are installed."""
    required = ["transformers", "onnx", "onnxruntime", "optimum"]
    missing = []

    for package in required:
        try:
            __import__(package)
        except ImportError:
            missing.append(package)

    if missing:
        print(f"Missing required packages: {', '.join(missing)}")
        print(f"Install with: pip install {' '.join(missing)}")
        sys.exit(1)


def download_and_convert_model(model_name: str, model_config: dict, output_dir: Path) -> bool:
    """Download a model and convert it to ONNX format."""
    from optimum.onnxruntime import ORTModelForFeatureExtraction
    from transformers import AutoTokenizer

    model_output_dir = output_dir / model_name

    print(f"\n{'='*60}")
    print(f"Processing: {model_name}")
    print(f"HuggingFace ID: {model_config['hf_id']}")
    print(f"Dimension: {model_config['dimension']}")
    print(f"{'='*60}")

    # Check if already downloaded
    if (model_output_dir / "model.onnx").exists() and (model_output_dir / "tokenizer.json").exists():
        print(f"Model already exists at {model_output_dir}, skipping...")
        return True

    try:
        # Create output directory
        model_output_dir.mkdir(parents=True, exist_ok=True)

        # Download and export to ONNX
        print(f"Downloading and converting {model_config['hf_id']} to ONNX...")
        model = ORTModelForFeatureExtraction.from_pretrained(
            model_config['hf_id'],
            export=True
        )

        # Save ONNX model
        model.save_pretrained(model_output_dir)

        # Download tokenizer
        print(f"Downloading tokenizer...")
        tokenizer = AutoTokenizer.from_pretrained(model_config['hf_id'])
        tokenizer.save_pretrained(model_output_dir)

        # Rename model file if needed (optimum may use different name)
        onnx_files = list(model_output_dir.glob("*.onnx"))
        if onnx_files and not (model_output_dir / "model.onnx").exists():
            # Find the main model file
            for onnx_file in onnx_files:
                if "model" in onnx_file.name.lower():
                    shutil.copy(onnx_file, model_output_dir / "model.onnx")
                    break
            else:
                # Just use the first one
                shutil.copy(onnx_files[0], model_output_dir / "model.onnx")

        # Create model info file
        info_content = f"""# {model_name}

HuggingFace ID: {model_config['hf_id']}
Dimension: {model_config['dimension']}
Max Tokens: {model_config['max_tokens']}
Description: {model_config['description']}

## Files
- model.onnx: ONNX model file
- tokenizer.json: Tokenizer configuration
- config.json: Model configuration
"""
        (model_output_dir / "README.md").write_text(info_content)

        print(f"Successfully saved model to {model_output_dir}")
        return True

    except Exception as e:
        print(f"Error processing {model_name}: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description="Download ONNX embedding models for Knowverse")
    parser.add_argument(
        "--models",
        type=str,
        default=None,
        help=f"Comma-separated list of models to download. Available: {', '.join(MODELS.keys())}. Default: all"
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default="./models",
        help="Output directory for models (default: ./models)"
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List available models and exit"
    )

    args = parser.parse_args()

    if args.list:
        print("\nAvailable models:")
        print("-" * 80)
        for name, config in MODELS.items():
            print(f"\n{name}:")
            print(f"  HuggingFace: {config['hf_id']}")
            print(f"  Dimension:   {config['dimension']}")
            print(f"  Max Tokens:  {config['max_tokens']}")
            print(f"  Description: {config['description']}")
        return

    check_dependencies()

    # Determine which models to download
    if args.models:
        model_names = [m.strip() for m in args.models.split(",")]
        for name in model_names:
            if name not in MODELS:
                print(f"Unknown model: {name}")
                print(f"Available models: {', '.join(MODELS.keys())}")
                sys.exit(1)
    else:
        model_names = list(MODELS.keys())

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Output directory: {output_dir.absolute()}")
    print(f"Models to download: {', '.join(model_names)}")

    # Download each model
    results = {}
    for model_name in model_names:
        success = download_and_convert_model(model_name, MODELS[model_name], output_dir)
        results[model_name] = success

    # Summary
    print("\n" + "=" * 60)
    print("DOWNLOAD SUMMARY")
    print("=" * 60)

    for model_name, success in results.items():
        status = "SUCCESS" if success else "FAILED"
        print(f"  {model_name}: {status}")

    failed = [m for m, s in results.items() if not s]
    if failed:
        print(f"\nFailed models: {', '.join(failed)}")
        sys.exit(1)
    else:
        print(f"\nAll models downloaded successfully to {output_dir.absolute()}")
        print("\nTo use with the Rust embedding service:")
        print(f"  1. Mount {output_dir.absolute()} to /app/models in the container")
        print(f"  2. Or copy models to services/embedding-rust/models/")


if __name__ == "__main__":
    main()
