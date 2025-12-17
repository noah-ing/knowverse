import { Controller } from "@hotwired/stimulus"
import * as THREE from 'three'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls'
import { TrackballControls } from 'three/examples/jsm/controls/TrackballControls'
import Stats from 'three/examples/jsm/libs/stats.module'

export default class extends Controller {
  static targets = [
    "container", 
    "loading", 
    "stats", 
    "info", 
    "controlPanel",
    "dimensionSelector",
    "algorithmSelector",
    "lodSelector"
  ]
  
  static values = {
    organizationId: Number,
    algorithm: { type: String, default: 'tsne' },
    lod: { type: Number, default: 0 },
    model: { type: String, default: 'base' },
    dimension: { type: Number, default: 1024 }
  }
  
  // Keep track of state for interactions
  documentPoints = new Map()
  raycaster = new THREE.Raycaster()
  mousePosition = new THREE.Vector2()
  selectedPoint = null
  intersectedPoint = null
  colorsByCluster = null
  
  // Initialize Three.js scene
  connect() {
    this.initThree()
    this.initControls()
    this.initStats()
    this.initEvents()
    this.loadVectorData()
  }
  
  // Initialize Three.js scene, camera, renderer
  initThree() {
    this.scene = new THREE.Scene()
    this.scene.background = new THREE.Color(0x111827)
    
    // Camera setup for 3D visualization
    this.camera = new THREE.PerspectiveCamera(
      60, // Field of view
      this.containerTarget.offsetWidth / this.containerTarget.offsetHeight, // Aspect ratio
      0.1, // Near clipping plane
      1000 // Far clipping plane
    )
    this.camera.position.z = 5
    
    // Renderer setup
    this.renderer = new THREE.WebGLRenderer({ antialias: true })
    this.renderer.setSize(this.containerTarget.offsetWidth, this.containerTarget.offsetHeight)
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2)) // Limit for performance
    this.containerTarget.appendChild(this.renderer.domElement)
    
    // Add lights
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.5)
    this.scene.add(ambientLight)
    
    const directionalLight = new THREE.DirectionalLight(0xffffff, 0.8)
    directionalLight.position.set(0, 1, 1)
    this.scene.add(directionalLight)
    
    // Add axes helper for reference
    const axesHelper = new THREE.AxesHelper(1)
    this.scene.add(axesHelper)
    
    // Setup animation loop
    this.renderer.setAnimationLoop(() => this.animate())
  }
  
  // Controls for camera movement
  initControls() {
    this.controls = new OrbitControls(this.camera, this.renderer.domElement)
    this.controls.enableDamping = true
    this.controls.dampingFactor = 0.05
    this.controls.rotateSpeed = 0.5
  }
  
  // Performance stats
  initStats() {
    if (this.hasStatsTarget) {
      this.stats = new Stats()
      this.statsTarget.appendChild(this.stats.dom)
    }
  }
  
  // Event listeners
  initEvents() {
    // Handle resize
    window.addEventListener('resize', () => this.onWindowResize())
    
    // Handle mouse movement for hover effects
    this.renderer.domElement.addEventListener('mousemove', (event) => this.onMouseMove(event))
    
    // Handle clicks for point selection
    this.renderer.domElement.addEventListener('click', (event) => this.onMouseClick(event))
    
    // Handle control panel changes
    if (this.hasDimensionSelectorTarget) {
      this.dimensionSelectorTarget.addEventListener('change', (event) => {
        this.dimensionValue = parseInt(event.target.value)
        this.loadVectorData()
      })
    }
    
    if (this.hasAlgorithmSelectorTarget) {
      this.algorithmSelectorTarget.addEventListener('change', (event) => {
        this.algorithmValue = event.target.value
        this.loadVectorData()
      })
    }
    
    if (this.hasLodSelectorTarget) {
      this.lodSelectorTarget.addEventListener('change', (event) => {
        this.lodValue = parseInt(event.target.value)
        this.loadVectorData()
      })
    }
  }
  
  // Resize handler
  onWindowResize() {
    this.camera.aspect = this.containerTarget.offsetWidth / this.containerTarget.offsetHeight
    this.camera.updateProjectionMatrix()
    this.renderer.setSize(this.containerTarget.offsetWidth, this.containerTarget.offsetHeight)
  }
  
  // Animation loop
  animate() {
    if (this.controls) {
      this.controls.update()
    }
    
    if (this.stats) {
      this.stats.update()
    }
    
    // Handle raycasting for hover effects
    this.handleRaycasting()
    
    this.renderer.render(this.scene, this.camera)
  }
  
  // Handle mouse position updates
  onMouseMove(event) {
    const rect = this.renderer.domElement.getBoundingClientRect()
    this.mousePosition.x = ((event.clientX - rect.left) / rect.width) * 2 - 1
    this.mousePosition.y = -((event.clientY - rect.top) / rect.height) * 2 + 1
  }
  
  // Handle mouse clicks
  onMouseClick(event) {
    if (this.intersectedPoint) {
      // Deselect previous point if any
      if (this.selectedPoint) {
        const prevPointData = this.documentPoints.get(this.selectedPoint.userData.id)
        if (prevPointData) {
          this.selectedPoint.material.color.set(prevPointData.color)
          this.selectedPoint.scale.set(1, 1, 1)
        }
      }
      
      // Select new point
      this.selectedPoint = this.intersectedPoint
      this.selectedPoint.material.color.set(0xffff00) // Yellow for selected
      this.selectedPoint.scale.set(1.5, 1.5, 1.5)
      
      // Show document info
      if (this.hasInfoTarget) {
        const pointData = this.documentPoints.get(this.selectedPoint.userData.id)
        if (pointData) {
          this.infoTarget.innerHTML = `
            <div class="p-4 bg-white shadow rounded-lg">
              <h3 class="text-lg font-bold">${pointData.title}</h3>
              <p class="text-sm text-gray-600">Document ID: ${pointData.document_id}</p>
              <p class="text-sm text-gray-600">Model: ${pointData.model} (${pointData.dimension} dimensions)</p>
              <a href="/organizations/${this.organizationIdValue}/documents/${pointData.document_id}" 
                 class="mt-2 inline-block text-indigo-600 hover:text-indigo-800">
                View Document
              </a>
            </div>
          `
        }
      }
    } else if (this.selectedPoint) {
      // Deselect if clicking elsewhere
      const pointData = this.documentPoints.get(this.selectedPoint.userData.id)
      if (pointData) {
        this.selectedPoint.material.color.set(pointData.color)
        this.selectedPoint.scale.set(1, 1, 1)
      }
      this.selectedPoint = null
      
      // Clear info panel
      if (this.hasInfoTarget) {
        this.infoTarget.innerHTML = '<div class="p-4 bg-white shadow rounded-lg text-gray-500">Select a document point to see details</div>'
      }
    }
  }
  
  // Raycasting for hover effects
  handleRaycasting() {
    this.raycaster.setFromCamera(this.mousePosition, this.camera)
    
    // Find intersected objects
    const intersects = this.raycaster.intersectObjects(this.scene.children)
    
    // Handle hover state
    if (intersects.length > 0) {
      const firstObject = intersects[0].object
      
      // Check if it's a document point
      if (firstObject.userData && firstObject.userData.isDocumentPoint) {
        if (this.intersectedPoint !== firstObject) {
          // Restore previous hover, if any
          if (this.intersectedPoint && this.intersectedPoint !== this.selectedPoint) {
            const prevPointData = this.documentPoints.get(this.intersectedPoint.userData.id)
            if (prevPointData) {
              this.intersectedPoint.material.color.set(prevPointData.color)
              this.intersectedPoint.scale.set(1, 1, 1)
            }
          }
          
          // Set new hover
          this.intersectedPoint = firstObject
          
          // Don't change color if it's the selected point
          if (this.intersectedPoint !== this.selectedPoint) {
            this.intersectedPoint.material.color.set(0xffffff) // White for hover
            this.intersectedPoint.scale.set(1.2, 1.2, 1.2)
          }
          
          // Update cursor
          this.renderer.domElement.style.cursor = 'pointer'
        }
      } else {
        // Not hovering over a document point
        if (this.intersectedPoint && this.intersectedPoint !== this.selectedPoint) {
          const pointData = this.documentPoints.get(this.intersectedPoint.userData.id)
          if (pointData) {
            this.intersectedPoint.material.color.set(pointData.color)
            this.intersectedPoint.scale.set(1, 1, 1)
          }
        }
        this.intersectedPoint = null
        this.renderer.domElement.style.cursor = 'auto'
      }
    } else {
      // No intersections
      if (this.intersectedPoint && this.intersectedPoint !== this.selectedPoint) {
        const pointData = this.documentPoints.get(this.intersectedPoint.userData.id)
        if (pointData) {
          this.intersectedPoint.material.color.set(pointData.color)
          this.intersectedPoint.scale.set(1, 1, 1)
        }
      }
      this.intersectedPoint = null
      this.renderer.domElement.style.cursor = 'auto'
    }
  }
  
  // Load vector data from API
  loadVectorData() {
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.remove('hidden')
    }
    
    // Clear existing points
    this.clearPoints()
    
    // Build URL with current parameters
    const url = `/organizations/${this.organizationIdValue}/vectors/projections?` +
                `algorithm=${this.algorithmValue}&` +
                `lod_level=${this.lodValue}&` +
                `dimension=${this.dimensionValue}`
    
    // Fetch vector projections
    fetch(url)
      .then(response => response.json())
      .then(data => this.renderVectorSpace(data))
      .catch(error => {
        console.error('Error loading vector data:', error)
        if (this.hasInfoTarget) {
          this.infoTarget.innerHTML = '<div class="p-4 bg-white shadow rounded-lg text-red-500">Error loading vector data</div>'
        }
      })
      .finally(() => {
        if (this.hasLoadingTarget) {
          this.loadingTarget.classList.add('hidden')
        }
      })
  }
  
  // Clear existing points from scene
  clearPoints() {
    // Remove existing points from scene
    this.scene.children = this.scene.children.filter(child => !child.userData?.isDocumentPoint)
    
    // Clear document points map
    this.documentPoints.clear()
    
    // Reset selection state
    this.selectedPoint = null
    this.intersectedPoint = null
  }
  
  // Render vector space with data from API
  renderVectorSpace(data) {
    if (!data.points || data.points.length === 0) {
      if (this.hasInfoTarget) {
        this.infoTarget.innerHTML = '<div class="p-4 bg-white shadow rounded-lg text-gray-500">No vector data available. Try generating projections first.</div>'
      }
      return
    }
    
    // Generate colors for clusters if using cluster visualization
    this.generateClusterColors(data.points)
    
    // Create point geometry
    const pointsMaterial = new THREE.PointsMaterial({
      size: 0.05,
      vertexColors: true
    })
    
    const pointsGeometry = new THREE.BufferGeometry()
    const positions = []
    const colors = []
    
    // Process each point
    data.points.forEach(point => {
      // Extract coordinates (handle 2D or 3D)
      const coords = point.coordinates
      positions.push(
        coords[0] || 0,
        coords[1] || 0,
        coords[2] || 0
      )
      
      // Determine color (either by cluster or by model)
      const color = this.getPointColor(point)
      colors.push(color.r, color.g, color.b)
      
      // Create individual point for interaction
      this.createInteractivePoint(point)
    })
    
    // Set geometry attributes
    pointsGeometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3))
    pointsGeometry.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3))
    
    // Create points system for background rendering (performance optimization)
    const pointsSystem = new THREE.Points(pointsGeometry, pointsMaterial)
    this.scene.add(pointsSystem)
    
    // Update the camera to fit all points
    this.fitCameraToPoints(positions)
    
    // Update info display
    if (this.hasInfoTarget) {
      this.infoTarget.innerHTML = `
        <div class="p-4 bg-white shadow rounded-lg">
          <p class="text-sm text-gray-600">Displaying ${data.points.length} points</p>
          <p class="text-sm text-gray-600">Algorithm: ${data.algorithm}</p>
          <p class="text-sm text-gray-600">Level of Detail: ${data.lod_level}</p>
          <p class="text-sm text-gray-500">Select a point to see document details</p>
        </div>
      `
    }
  }
  
  // Create individual interactive points
  createInteractivePoint(point) {
    const geometry = new THREE.SphereGeometry(0.015, 8, 8)
    const color = this.getPointColor(point)
    const material = new THREE.MeshBasicMaterial({ color: color })
    
    const mesh = new THREE.Mesh(geometry, material)
    mesh.position.set(
      point.coordinates[0] || 0,
      point.coordinates[1] || 0,
      point.coordinates[2] || 0
    )
    
    // Set user data for interaction
    mesh.userData = {
      isDocumentPoint: true,
      id: point.id,
      document_id: point.document_id,
      title: point.title
    }
    
    // Store in document points map
    this.documentPoints.set(point.id, {
      ...point,
      color: color.getHex()
    })
    
    // Add to scene
    this.scene.add(mesh)
  }
  
  // Determine color for a point (based on cluster or model)
  getPointColor(point) {
    // Default color strategy based on model type
    const modelColors = {
      'mini': new THREE.Color(0x4299e1),   // Blue
      'small': new THREE.Color(0x48bb78),  // Green
      'base': new THREE.Color(0xf6e05e),   // Yellow
      'large': new THREE.Color(0xed8936),  // Orange
      'xl': new THREE.Color(0xe53e3e)      // Red
    }
    
    // If we're using cluster colors and this point has a cluster
    if (this.colorsByCluster && point.cluster_id) {
      return this.colorsByCluster.get(point.cluster_id) || new THREE.Color(0xcccccc)
    }
    
    // Otherwise use model-based colors
    return modelColors[point.model] || new THREE.Color(0xcccccc)
  }
  
  // Generate consistent colors for clusters
  generateClusterColors(points) {
    // Check if we need cluster colors
    const hasClusters = points.some(p => p.cluster_id)
    
    if (!hasClusters) {
      this.colorsByCluster = null
      return
    }
    
    // Find all unique cluster IDs
    const clusterIds = [...new Set(points.map(p => p.cluster_id).filter(id => id))]
    
    // Generate colors for each cluster
    this.colorsByCluster = new Map()
    
    clusterIds.forEach((id, index) => {
      // HSL provides good color separation
      const hue = (index * 137.5) % 360
      const color = new THREE.Color().setHSL(hue / 360, 0.7, 0.5)
      this.colorsByCluster.set(id, color)
    })
  }
  
  // Adjust camera to fit all points
  fitCameraToPoints(positions) {
    if (positions.length < 3) return
    
    // Calculate bounding box
    let minX = Infinity, minY = Infinity, minZ = Infinity
    let maxX = -Infinity, maxY = -Infinity, maxZ = -Infinity
    
    for (let i = 0; i < positions.length; i += 3) {
      minX = Math.min(minX, positions[i])
      maxX = Math.max(maxX, positions[i])
      minY = Math.min(minY, positions[i + 1])
      maxY = Math.max(maxY, positions[i + 1])
      minZ = Math.min(minZ, positions[i + 2])
      maxZ = Math.max(maxZ, positions[i + 2])
    }
    
    // Calculate center and size
    const center = new THREE.Vector3(
      (minX + maxX) / 2,
      (minY + maxY) / 2,
      (minZ + maxZ) / 2
    )
    
    const size = Math.max(maxX - minX, maxY - minY, maxZ - minZ)
    
    // Position camera to see all points
    this.camera.position.copy(center)
    this.camera.position.z += size * 1.5
    
    // Set controls target to center
    this.controls.target.copy(center)
    this.controls.update()
  }
}
