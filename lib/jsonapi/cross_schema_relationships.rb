# frozen_string_literal: true

module JSONAPI
  module CrossSchemaRelationships
    extend ActiveSupport::Concern

    included do
      class_attribute :_cross_schema_relationships, default: {}
    end

    class_methods do
      # Store cross-schema relationship information
      def has_one(*args)
        options = args.extract_options!
        schema = options.delete(:schema)

        if schema
          args.each do |name|
            register_cross_schema_relationship(name, schema, :has_one, options)
          end
        end

        super(*args, options)
      end

      def has_many(*args)
        options = args.extract_options!
        schema = options.delete(:schema)

        if schema
          args.each do |name|
            register_cross_schema_relationship(name, schema, :has_many, options)
          end
        end

        super(*args, options)
      end

      private

      def register_cross_schema_relationship(name, schema, type, options)
        self._cross_schema_relationships = _cross_schema_relationships.merge(
          name => { schema: schema, type: type, options: options }
        )
      end
    end

    # Instance methods to handle cross-schema relationships
    def cross_schema_relationship?(relationship_name)
      self.class._cross_schema_relationships.key?(relationship_name.to_sym)
    end

    def cross_schema_for(relationship_name)
      self.class._cross_schema_relationships[relationship_name.to_sym]
    end
  end
end