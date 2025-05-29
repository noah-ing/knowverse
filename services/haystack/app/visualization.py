"""
Visualization module for KnowVerse Haystack service.
Includes dimension reduction techniques and clustering algorithms.
"""

import logging
import time
import numpy as np
from typing import Dict, List, Optional, Any, Union, Tuple
from sklearn.manifold import TSNE
from sklearn.cluster import KMeans, AgglomerativeClustering
from sklearn.metrics import silhouette_score
from sklearn.neighbors import NearestNeighbors
import hdbscan
import umap

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("haystack_visualization")

# Optional: Try to use GPU acceleration if available
try:
    import cuml
    from cuml.manifold import TSNE as cuTSNE
    from cuml.cluster import KMeans as cuKMeans
    from cuml.cluster import HDBSCAN as cuHDBSCAN
    HAS_GPU = True
    logger.info("GPU acceleration enabled via RAPIDS cuML")
except ImportError:
    HAS_GPU = False
    logger.info("GPU acceleration not available, using CPU implementations")

class DimensionReduction:
    """
    Handles dimension reduction techniques for vector visualization.
    Supports t-SNE and UMAP algorithms with optional GPU acceleration.
    """
    
    @staticmethod
    def reduce_dimensions(
        vectors: List[List[float]], 
        algorithm: str = "tsne", 
        params: Dict[str, Any] = None,
        use_gpu: bool = HAS_GPU
    ) -> List[List[float]]:
        """
        Reduce dimensions of vectors using the specified algorithm.
        
        Args:
            vectors: List of high-dimensional vectors
            algorithm: 'tsne' or 'umap'
            params: Algorithm-specific parameters
            use_gpu: Whether to use GPU acceleration if available
            
        Returns:
            List of low-dimensional vectors (typically 2D or 3D)
        """
        start_time = time.time()
        
        # Default parameters
        default_params = {
            "tsne": {
                "perplexity": 30,
                "learning_rate": 200,
                "iterations": 1000,
                "dimensions": 3
            },
            "umap": {
                "n_neighbors": 15,
                "min_dist": 0.1,
                "dimensions": 3
            }
        }
        
        # Merge with provided parameters
        if params is None:
            params = {}
        
        algorithm = algorithm.lower()
        if algorithm not in default_params:
            raise ValueError(f"Unsupported algorithm: {algorithm}. Must be 'tsne' or 'umap'")
            
        # Merge default params with provided params
        all_params = {**default_params[algorithm], **params}
        
        # Convert vectors to numpy array
        vectors_np = np.array(vectors)
        n_samples, n_features = vectors_np.shape
        logger.info(f"Reducing dimensions for {n_samples} vectors with {n_features} features")
        
        # Get output dimensions
        n_components = all_params.get("dimensions", 3)
        
        try:
            # Apply dimension reduction
            if algorithm == "tsne":
                # GPU implementation of t-SNE
                if use_gpu and HAS_GPU:
                    logger.info("Using GPU-accelerated t-SNE")
                    tsne = cuTSNE(
                        n_components=n_components,
                        perplexity=all_params["perplexity"],
                        learning_rate=all_params["learning_rate"],
                        n_iter=all_params["iterations"]
                    )
                    reduced_vectors = tsne.fit_transform(vectors_np)
                # CPU implementation of t-SNE
                else:
                    logger.info("Using CPU t-SNE")
                    tsne = TSNE(
                        n_components=n_components,
                        perplexity=all_params["perplexity"],
                        learning_rate=all_params["learning_rate"],
                        n_iter=all_params["iterations"],
                        n_jobs=-1  # Use all cores
                    )
                    reduced_vectors = tsne.fit_transform(vectors_np)
                    
            elif algorithm == "umap":
                # UMAP implementation (similar performance on CPU and GPU)
                logger.info("Using UMAP for dimension reduction")
                reducer = umap.UMAP(
                    n_components=n_components,
                    n_neighbors=all_params["n_neighbors"],
                    min_dist=all_params["min_dist"]
                )
                reduced_vectors = reducer.fit_transform(vectors_np)
                
            # Convert to list for JSON serialization
            result = reduced_vectors.tolist()
            
            logger.info(f"Dimension reduction completed in {time.time() - start_time:.2f} seconds")
            return result
            
        except Exception as e:
            logger.error(f"Error in dimension reduction: {str(e)}")
            raise
    
    @staticmethod
    def detect_gpu_availability() -> Dict[str, Any]:
        """
        Check if GPU acceleration is available and return capabilities
        """
        capabilities = {
            "gpu_available": HAS_GPU,
            "supported_algorithms": ["tsne", "umap"]
        }
        
        if HAS_GPU:
            capabilities["gpu_accelerated"] = ["tsne", "kmeans", "hdbscan"]
        
        return capabilities

class ClusterAnalysis:
    """
    Handles document clustering and analysis.
    Supports KMeans, hierarchical clustering, and DBSCAN.
    """
    
    @staticmethod
    def cluster_vectors(
        vectors: List[List[float]], 
        document_ids: List[int],
        algorithm: str = "kmeans", 
        params: Dict[str, Any] = None,
        use_gpu: bool = HAS_GPU
    ) -> Dict[str, Any]:
        """
        Cluster vectors using the specified algorithm.
        
        Args:
            vectors: List of vectors to cluster
            document_ids: List of document IDs corresponding to vectors
            algorithm: 'kmeans', 'hierarchical', or 'dbscan'
            params: Algorithm-specific parameters
            use_gpu: Whether to use GPU acceleration if available
            
        Returns:
            Dictionary with cluster assignments and metadata
        """
        start_time = time.time()
        
        # Default parameters
        default_params = {
            "kmeans": {
                "n_clusters": 0,  # 0 means auto-detect
                "max_clusters": 20,
                "random_state": 42,
                "init": "k-means++"
            },
            "hierarchical": {
                "n_clusters": 0,  # 0 means auto-detect
                "linkage": "ward",
                "max_clusters": 20,
                "distance_threshold": 1.5
            },
            "dbscan": {
                "eps": 0.5,
                "min_samples": 5,
                "metric": "cosine"
            }
        }
        
        # Merge with provided parameters
        if params is None:
            params = {}
        
        algorithm = algorithm.lower()
        if algorithm not in default_params:
            raise ValueError(f"Unsupported algorithm: {algorithm}. Must be 'kmeans', 'hierarchical', or 'dbscan'")
            
        # Merge default params with provided params
        all_params = {**default_params[algorithm], **params}
        
        # Convert vectors to numpy array
        vectors_np = np.array(vectors)
        n_samples, n_features = vectors_np.shape
        logger.info(f"Clustering {n_samples} vectors with {n_features} features")
        
        try:
            # Auto-detect optimal number of clusters if needed
            if algorithm in ["kmeans", "hierarchical"] and all_params["n_clusters"] <= 0:
                n_clusters = ClusterAnalysis._find_optimal_clusters(
                    vectors_np, 
                    max_clusters=all_params["max_clusters"]
                )
                all_params["n_clusters"] = n_clusters
                logger.info(f"Auto-detected optimal number of clusters: {n_clusters}")
            
            # Apply clustering algorithm
            if algorithm == "kmeans":
                # GPU implementation of KMeans
                if use_gpu and HAS_GPU:
                    logger.info("Using GPU-accelerated KMeans")
                    kmeans = cuKMeans(
                        n_clusters=all_params["n_clusters"],
                        init=all_params["init"],
                        random_state=all_params["random_state"]
                    )
                    labels = kmeans.fit_predict(vectors_np)
                    centroids = kmeans.cluster_centers_.tolist()
                # CPU implementation of KMeans
                else:
                    logger.info("Using CPU KMeans")
                    kmeans = KMeans(
                        n_clusters=all_params["n_clusters"],
                        init=all_params["init"],
                        random_state=all_params["random_state"],
                        n_init=10
                    )
                    labels = kmeans.fit_predict(vectors_np)
                    centroids = kmeans.cluster_centers_.tolist()
                
                # Calculate membership strengths (distance to centroid, normalized)
                membership_strengths = ClusterAnalysis._calculate_kmeans_membership(vectors_np, kmeans)
                
            elif algorithm == "hierarchical":
                n_clusters = all_params["n_clusters"]
                
                # AgglomerativeClustering (no GPU implementation available)
                logger.info("Using hierarchical clustering")
                clustering = AgglomerativeClustering(
                    n_clusters=n_clusters if n_clusters > 0 else None,
                    linkage=all_params["linkage"],
                    distance_threshold=all_params["distance_threshold"] if n_clusters == 0 else None
                )
                labels = clustering.fit_predict(vectors_np)
                
                # Calculate centroids manually
                unique_labels = set(labels)
                centroids = []
                for label in unique_labels:
                    mask = labels == label
                    centroid = vectors_np[mask].mean(axis=0)
                    centroids.append(centroid.tolist())
                
                # Calculate membership strengths (distance to centroid, normalized)
                membership_strengths = ClusterAnalysis._calculate_hierarchical_membership(
                    vectors_np, labels, centroids
                )
                
            elif algorithm == "dbscan":
                # GPU implementation of HDBSCAN
                if use_gpu and HAS_GPU:
                    logger.info("Using GPU-accelerated HDBSCAN")
                    clustering = cuHDBSCAN(
                        min_samples=all_params["min_samples"],
                        metric=all_params["metric"]
                    )
                    labels = clustering.fit_predict(vectors_np)
                # CPU implementation of HDBSCAN
                else:
                    logger.info("Using CPU HDBSCAN")
                    clustering = hdbscan.HDBSCAN(
                        min_cluster_size=all_params["min_samples"],
                        metric=all_params["metric"]
                    )
                    labels = clustering.fit_predict(vectors_np)
                
                # Calculate centroids manually
                unique_labels = set(labels)
                if -1 in unique_labels:  # Remove noise cluster
                    unique_labels.remove(-1)
                
                centroids = []
                for label in unique_labels:
                    mask = labels == label
                    centroid = vectors_np[mask].mean(axis=0)
                    centroids.append(centroid.tolist())
                
                # Add a "noise" centroid if there are noise points
                if -1 in set(labels):
                    mask = labels == -1
                    if sum(mask) > 0:
                        noise_centroid = vectors_np[mask].mean(axis=0)
                        centroids.append(noise_centroid.tolist())
                
                # Calculate membership strengths
                membership_strengths = ClusterAnalysis._calculate_dbscan_membership(
                    vectors_np, labels, centroids
                )
            
            # Create cluster results
            result = ClusterAnalysis._create_cluster_result(
                labels.tolist(),
                centroids,
                document_ids,
                membership_strengths,
                algorithm,
                all_params
            )
            
            logger.info(f"Clustering completed in {time.time() - start_time:.2f} seconds")
            return result
            
        except Exception as e:
            logger.error(f"Error in clustering: {str(e)}")
            raise
    
    @staticmethod
    def _find_optimal_clusters(vectors: np.ndarray, max_clusters: int = 20) -> int:
        """Find optimal number of clusters using silhouette score"""
        # Default to 3 clusters for very small datasets
        if len(vectors) < 10:
            return min(3, len(vectors))
        
        # For slightly larger datasets, use a simpler approach
        if len(vectors) < 100:
            return min(5, len(vectors) // 5)
        
        # For larger datasets, use the silhouette method
        max_clusters = min(max_clusters, len(vectors) // 10)  # Ensure reasonable cluster size
        range_n_clusters = range(2, max_clusters + 1)
        best_score = -1
        best_n_clusters = 2
        
        # Sample dataset for efficiency if very large
        if len(vectors) > 1000:
            indices = np.random.choice(len(vectors), 1000, replace=False)
            sample_vectors = vectors[indices]
        else:
            sample_vectors = vectors
        
        for n_clusters in range_n_clusters:
            # Initialize KMeans and fit
            kmeans = KMeans(n_clusters=n_clusters, n_init=2, random_state=42)
            cluster_labels = kmeans.fit_predict(sample_vectors)
            
            # Calculate silhouette score
            if len(set(cluster_labels)) > 1:  # Ensure we have more than one cluster
                silhouette_avg = silhouette_score(sample_vectors, cluster_labels)
                if silhouette_avg > best_score:
                    best_score = silhouette_avg
                    best_n_clusters = n_clusters
        
        return best_n_clusters
    
    @staticmethod
    def _calculate_kmeans_membership(vectors: np.ndarray, kmeans_model) -> List[List[float]]:
        """Calculate membership strength for KMeans clustering"""
        # Calculate distance to each centroid
        distances = np.zeros((len(vectors), kmeans_model.n_clusters))
        for i in range(kmeans_model.n_clusters):
            distances[:, i] = np.linalg.norm(vectors - kmeans_model.cluster_centers_[i], axis=1)
        
        # Convert distances to strengths (closer = stronger)
        max_distances = np.max(distances, axis=1, keepdims=True)
        min_distances = np.min(distances, axis=1, keepdims=True)
        range_distances = max_distances - min_distances
        
        # Handle case where all distances are the same
        range_distances[range_distances == 0] = 1.0
        
        # Normalize to [0, 1] range and invert (1 = closest)
        strengths = 1 - (distances - min_distances) / range_distances
        
        return strengths.tolist()
    
    @staticmethod
    def _calculate_hierarchical_membership(
        vectors: np.ndarray, 
        labels: np.ndarray, 
        centroids: List[List[float]]
    ) -> List[List[float]]:
        """Calculate membership strength for hierarchical clustering"""
        # Convert centroids to numpy array
        centroids_np = np.array(centroids)
        
        # Calculate distance to each centroid
        distances = np.zeros((len(vectors), len(centroids)))
        for i in range(len(centroids)):
            distances[:, i] = np.linalg.norm(vectors - centroids_np[i], axis=1)
        
        # Convert distances to strengths (closer = stronger)
        max_distances = np.max(distances, axis=1, keepdims=True)
        min_distances = np.min(distances, axis=1, keepdims=True)
        range_distances = max_distances - min_distances
        
        # Handle case where all distances are the same
        range_distances[range_distances == 0] = 1.0
        
        # Normalize to [0, 1] range and invert (1 = closest)
        strengths = 1 - (distances - min_distances) / range_distances
        
        return strengths.tolist()
    
    @staticmethod
    def _calculate_dbscan_membership(
        vectors: np.ndarray, 
        labels: np.ndarray, 
        centroids: List[List[float]]
    ) -> List[List[float]]:
        """Calculate membership strength for DBSCAN clustering"""
        # Convert centroids to numpy array
        centroids_np = np.array(centroids)
        
        # Calculate distance to each centroid
        distances = np.zeros((len(vectors), len(centroids)))
        for i in range(len(centroids)):
            distances[:, i] = np.linalg.norm(vectors - centroids_np[i], axis=1)
        
        # For vectors in noise cluster (-1), set strength based on distance
        strengths = np.zeros_like(distances)
        
        # For each point, calculate membership strength to each cluster
        for i in range(len(vectors)):
            if labels[i] == -1:  # Noise point
                # Assign weak membership to closest cluster
                min_dist_idx = np.argmin(distances[i])
                strengths[i, :] = 0.1  # Low baseline
                strengths[i, min_dist_idx] = 0.3  # Slightly stronger for closest
            else:
                # Assign strongest membership to assigned cluster
                cluster_idx = int(labels[i])
                # If cluster_idx is out of bounds, assign to closest centroid
                if cluster_idx >= len(centroids):
                    cluster_idx = np.argmin(distances[i])
                
                # Calculate distance-based membership
                max_dist = np.max(distances[i])
                min_dist = np.min(distances[i])
                range_dist = max_dist - min_dist
                
                # Normalize distances to strengths
                if range_dist > 0:
                    strengths[i, :] = 1 - (distances[i] - min_dist) / range_dist
                else:
                    strengths[i, :] = 0.5  # Equal strength if all distances are the same
                
                # Boost assigned cluster
                strengths[i, cluster_idx] = 1.0
        
        return strengths.tolist()
    
    @staticmethod
    def _create_cluster_result(
        labels: List[int],
        centroids: List[List[float]],
        document_ids: List[int],
        membership_strengths: List[List[float]],
        algorithm: str,
        params: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Create formatted cluster result"""
        # Map labels to output clusters
        unique_labels = sorted(set(labels))
        clusters = []
        
        for i, label in enumerate(unique_labels):
            # Skip noise cluster for DBSCAN if requested
            if label == -1 and algorithm == "dbscan" and not params.get("include_noise", True):
                continue
                
            # Find documents in this cluster
            cluster_indices = [j for j, l in enumerate(labels) if l == label]
            cluster_doc_ids = [document_ids[j] for j in cluster_indices]
            
            # Get membership strengths for this cluster
            cluster_memberships = [membership_strengths[j][i] for j in cluster_indices]
            
            # Create cluster entry
            cluster = {
                "id": i,
                "size": len(cluster_indices),
                "centroid": centroids[i] if i < len(centroids) else [],
                "document_indices": cluster_indices,
                "document_ids": cluster_doc_ids,
                "membership_strengths": cluster_memberships,
                "metadata": {
                    "algorithm": algorithm,
                    "is_noise": (label == -1)
                }
            }
            
            clusters.append(cluster)
        
        # Create result object
        result = {
            "clusters": clusters,
            "num_clusters": len(clusters),
            "algorithm": algorithm,
            "parameters": params
        }
        
        return result

# Example usage
if __name__ == "__main__":
    # Generate some test vectors
    test_vectors = np.random.rand(100, 50).tolist()
    test_doc_ids = list(range(100))
    
    # Test dimension reduction
    reduced = DimensionReduction.reduce_dimensions(test_vectors, algorithm="tsne")
    print(f"Reduced to {len(reduced)} vectors with {len(reduced[0])} dimensions")
    
    # Test clustering
    clusters = ClusterAnalysis.cluster_vectors(test_vectors, test_doc_ids, algorithm="kmeans")
    print(f"Found {len(clusters['clusters'])} clusters")
