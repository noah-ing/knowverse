import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ 
    "query", 
    "provider", 
    "model", 
    "minSimilarity",
    "limit",
    "dimensionDisplay"
  ]
  
  connect() {
    console.log("Search form controller connected")
    this.updateDimensionDisplay()
  }
  
  search(event) {
    // Optional: prevent form submission if query is too short
    if (this.queryTarget.value.length < 2) {
      event.preventDefault()
      alert("Please enter a longer search query")
    }
  }
  
  changeProvider(event) {
    const provider = event.target.value
    // Store the selected provider in localStorage for persistence
    localStorage.setItem('search_provider', provider)
    
    // Optionally, you can update UI elements based on the selected provider
    if (provider === 'hnsw') {
      // HNSW-specific controls
    } else if (provider === 'pgvector_cosine') {
      // pgvector-specific controls
    }
  }
  
  changeModel(event) {
    const modelName = event.target.value
    // Store the selected model in localStorage for persistence
    localStorage.setItem('search_model', modelName)
    
    // Update dimension display based on the selected model
    this.updateDimensionDisplay()
  }
  
  updateDimensionDisplay() {
    if (!this.hasModelTarget || !this.hasDimensionDisplayTarget) return
    
    const modelName = this.modelTarget.value
    let dimension
    
    // Map model to dimension
    switch(modelName) {
      case 'mini':
        dimension = 384
        break
      case 'small':
        dimension = 768
        break
      case 'base':
        dimension = 1024
        break
      case 'large':
        dimension = 1536
        break
      case 'xl':
        dimension = 2048
        break
      default:
        dimension = 1024
    }
    
    // Update the display
    this.dimensionDisplayTarget.textContent = dimension
    
    // Optional: You can dynamically adjust min similarity based on dimension
    if (this.hasMinSimilarityTarget) {
      // Higher dimensions may need lower similarity thresholds
      if (dimension >= 1536) {
        this.minSimilarityTarget.value = 0.4
      } else {
        this.minSimilarityTarget.value = 0.5
      }
    }
  }
  
  changeSimilarity(event) {
    // Store the selected similarity threshold in localStorage for persistence
    localStorage.setItem('min_similarity', event.target.value)
  }
  
  changeLimit(event) {
    // Store the selected result limit in localStorage for persistence
    localStorage.setItem('search_limit', event.target.value)
  }
}
