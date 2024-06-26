require 'rails/generators/migration'
require 'generators/sorcery/helpers'

module Sorcery
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      include Sorcery::Generators::Helpers

      source_root File.expand_path('templates', __dir__)

      argument :submodules, optional: true, type: :array, banner: 'submodules'

      class_option :model, optional: true, type: :string, banner: 'model',
                           desc: "Specify the model class name if you will use anything other than 'User'"

      class_option :migrations, optional: true, type: :boolean, banner: 'migrations',
                                desc: '[DEPRECATED] Please use --only-submodules option instead'

      class_option :only_submodules, optional: true, type: :boolean, banner: 'only-submodules',
                                     desc: "Specify if you want to add submodules to an existing model\n\t\t\t     # (will generate migrations files, and add submodules to config file)"

      def check_deprecated_options
        return unless options[:migrations]

        warn('[DEPRECATED] `--migrations` option is deprecated, please use `--only-submodules` instead')
      end

      # Copy the initializer file to config/initializers folder.
      def copy_initializer_file
        template 'initializer.rb', sorcery_config_path unless only_submodules?
      end

      def configure_initializer_file
        # Add submodules to the initializer file.
        return unless submodules

        submodule_names = submodules.collect { |submodule| ':' + submodule }

        gsub_file sorcery_config_path, /submodules = \[.*\]/ do |str|
          current_submodule_names = (str =~ /\[(.*)\]/ ? Regexp.last_match(1) : '').delete(' ').split(',')
          "submodules = [#{(current_submodule_names | submodule_names).join(', ')}]"
        end
      end

      def configure_model
        # Generate the model and add 'authenticates_with_sorcery!' unless you passed --only-submodules
        return if only_submodules?

        generate "model #{model_class_name} --skip-migration"
      end

      def inject_sorcery_to_model
        indents = '  ' * (namespaced? ? 2 : 1)

        inject_into_class(model_path, model_class_name, "#{indents}authenticates_with_sorcery!\n")
      end

      # Copy the migrations files to db/migrate folder
      def copy_migration_files
        # Copy core migration file in all cases except when you pass --only-submodules.
        return unless defined?(ActiveRecord)

        migration_template 'migration/core.rb', 'db/migrate/sorcery_core.rb', migration_class_name: migration_class_name unless only_submodules?

        return unless submodules

        submodules.each do |submodule|
          unless %w[http_basic_auth session_timeout core].include?(submodule)
            migration_template "migration/#{submodule}.rb", "db/migrate/sorcery_#{submodule}.rb", migration_class_name: migration_class_name
          end
        end
      end

      # Define the next_migration_number method (necessary for the migration_template method to work)
      def self.next_migration_number(dirname)
        if timestamped_migrations?
          sleep 1 # make sure each time we get a different timestamp
          Time.new.utc.strftime('%Y%m%d%H%M%S')
        else
          format('%.3d', (current_migration_number(dirname) + 1))
        end
      end

      private

      def self.timestamped_migrations?
        if Rails::VERSION::MAJOR >= 7
          ActiveRecord.timestamped_migrations
        else
          ActiveRecord::Base.timestamped_migrations
        end
      end

      def only_submodules?
        options[:migrations] || options[:only_submodules]
      end

      def migration_class_name
        "ActiveRecord::Migration[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end
    end
  end
end
