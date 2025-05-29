# Pin npm packages by running ./bin/importmap

pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/components", under: "components"

# Three.js and its modules
pin "three", to: "https://ga.jspm.io/npm:three@0.157.0/build/three.module.js"
pin "three/examples/jsm/controls/OrbitControls", to: "https://ga.jspm.io/npm:three@0.157.0/examples/jsm/controls/OrbitControls.js"
pin "three/examples/jsm/controls/TrackballControls", to: "https://ga.jspm.io/npm:three@0.157.0/examples/jsm/controls/TrackballControls.js"
pin "three/examples/jsm/libs/stats.module", to: "https://ga.jspm.io/npm:three@0.157.0/examples/jsm/libs/stats.module.js"

# Other essential dependencies
pin "chartkick", to: "chartkick.js"
pin "Chart.bundle", to: "Chart.bundle.js"

# Removed problematic UI support modules that don't exist
