# Enhanced Propshaft configuration to ensure all assets are correctly loaded
# This configuration resolves asset loading issues with JavaScript controllers and CSS

Rails.application.config.to_prepare do
  # Add JavaScript paths to asset pipeline
  Rails.application.config.assets.paths << Rails.root.join('app/javascript')
  Rails.application.config.assets.paths << Rails.root.join('app/javascript/controllers')
  Rails.application.config.assets.paths << Rails.root.join('app/javascript/controllers/search')
  Rails.application.config.assets.paths << Rails.root.join('app/javascript/components')
  Rails.application.config.assets.paths << Rails.root.join('app/javascript/wasm')
  
  # Ensure public assets are discoverable
  Rails.application.config.assets.paths << Rails.root.join('public')
  
  # Precompile specific UI files to ensure they're available
  Rails.application.config.assets.precompile += %w( 
    dark_mode_controller.js
    dropdown_controller.js
    mobile_menu_controller.js
    ui_fixes.css
    ui_component_fallbacks.css
  )
  
  # Enable asset debugging in development for clearer troubleshooting
  if Rails.env.development?
    Rails.application.config.assets.debug = true
    
    # Log asset load attempts to help diagnose issues
    Rails.application.config.after_initialize do
      Rails.logger.info "Propshaft asset paths:"
      Rails.application.config.assets.paths.each do |path|
        Rails.logger.info " - #{path}"
      end
    end
  end
end
