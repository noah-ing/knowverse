# This initializer provides a way to bypass pending migration checks
# when ENV["RAILS_SKIP_MIGRATIONS"] is set to "true"

Rails.application.config.to_prepare do
  if ENV["RAILS_SKIP_MIGRATIONS"] == "true"
    # Monkey patch ActiveRecord::Migration to skip the check_pending! method
    ActiveRecord::Migration.singleton_class.prepend(Module.new do
      def check_pending!(connection = ActiveRecord::Base.connection)
        # Skip check if RAILS_SKIP_MIGRATIONS is set
        return if ENV["RAILS_SKIP_MIGRATIONS"] == "true"
        super
      end
    end)

    ActiveRecord::MigrationContext.prepend(Module.new do
      def check_pending!
        # Skip check if RAILS_SKIP_MIGRATIONS is set
        return if ENV["RAILS_SKIP_MIGRATIONS"] == "true"
        super
      end
    end)
  end
end
