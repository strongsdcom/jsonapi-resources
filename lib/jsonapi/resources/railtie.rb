module JSONAPI
  module Resources
    class Railtie < Rails::Railtie
      rake_tasks do
        load 'tasks/check_upgrade.rake'
      end

      initializer "jsonapi_resources.deprecators" do
        if Rails::VERSION::MAJOR >= 8 && Rails.application
          Rails.application.deprecators[:jsonapi_resources] = ActiveSupport::Deprecation.new("1.0", "JSONAPI::Resources")
        end
      end
    end
  end
end