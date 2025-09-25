# frozen_string_literal: true

# Extensions to ActiveRelationResource for cross-schema support
module JSONAPI
  module ActiveRelationResourceExtensions
    def self.included(base)
      base.class_eval do
        # Override find_related_fragments to handle cross-schema relationships
        def self.find_related_fragments(source_rids, relationship_name, options = {})
          relationship = _relationship(relationship_name)

          if defined?(_cross_schema_relationships) && _cross_schema_relationships && (cross_schema_info = _cross_schema_relationships[relationship_name.to_sym])
            # Handle cross-schema relationship
            handle_cross_schema_relationship(source_rids, relationship, cross_schema_info, options)
          else
            # Call the original implementation
            super(source_rids, relationship_name, options)
          end
        end

        # Override find_included_fragments to handle cross-schema relationships
        def self.find_included_fragments(source, relationship_name, options)
          relationship = _relationship(relationship_name)

          if defined?(_cross_schema_relationships) && _cross_schema_relationships && (cross_schema_info = _cross_schema_relationships[relationship_name.to_sym])
            # Handle cross-schema relationship
            handle_cross_schema_included(source, relationship, cross_schema_info, options)
          else
            # Call the original implementation
            super(source, relationship_name, options)
          end
        end

        private

        def self.handle_cross_schema_relationship(source_rids, relationship, cross_schema_info, options)
          schema = cross_schema_info[:schema]

          # Get the source records
          source_records = source_rids.map { |rid| find_by_key(rid.id, options) }.compact

          # Build the cross-schema query
          if relationship.is_a?(JSONAPI::Relationship::ToOne)
            handle_cross_schema_to_one(source_records, relationship, schema, options)
          else
            handle_cross_schema_to_many(source_records, relationship, schema, options)
          end
        end

        def self.handle_cross_schema_included(source, relationship, cross_schema_info, options)
          schema = cross_schema_info[:schema]

          # Extract IDs from source - it could be a hash of resource fragments
          source_ids = if source.is_a?(Hash)
            source.keys.map(&:id)
          elsif source.is_a?(Array) && source.first.respond_to?(:identity)
            # Array of resource fragments
            source.map { |fragment| fragment.identity.id }
          else
            source.map(&:id)
          end

          # Get the source records
          source_records = source_ids.map { |id| find_by_key(id, options) }.compact

          # Build the cross-schema query
          if relationship.is_a?(JSONAPI::Relationship::ToOne)
            handle_cross_schema_to_one(source_records, relationship, schema, options)
          else
            handle_cross_schema_to_many(source_records, relationship, schema, options)
          end
        end

        def self.handle_cross_schema_to_one(source_records, relationship, schema, options)
          # For has_one or belongs_to with cross-schema
          related_klass = relationship.resource_klass
          foreign_key = relationship.foreign_key

          # Get the foreign key values from source records
          foreign_key_values = source_records.map { |r| r._model.send(foreign_key) }.compact.uniq

          return {} if foreign_key_values.empty?

          # Query the related table with schema prefix
          # This should be configured based on the actual schema and table
          full_table_name = "#{schema}.#{relationship.table_name || related_klass._table_name}"

          # Use ActiveRecord to query cross-schema with proper connection
          connection = ActiveRecord::Base.connection
          quoted_table = connection.quote_table_name(full_table_name)
          quoted_ids = foreign_key_values.map { |id| connection.quote(id) }.join(',')

          sql = "SELECT * FROM #{quoted_table} WHERE id IN (#{quoted_ids})"
          related_records = connection.exec_query(sql)

          # Convert to fragments
          fragments = {}
          related_records.each do |record_hash|
            # Create a model instance from the hash
            model_class = related_klass._model_class
            instance = model_class.instantiate(record_hash)
            resource = related_klass.new(instance, options[:context])
            rid = JSONAPI::ResourceIdentity.new(related_klass, instance.id)
            fragments[rid] = JSONAPI::ResourceFragment.new(rid, resource: resource)
          end

          fragments
        end

        def self.handle_cross_schema_to_many(source_records, relationship, schema, options)
          # For has_many with cross-schema
          related_klass = relationship.resource_klass

          # Determine the foreign key based on the source model
          foreign_key = relationship.foreign_key || "#{_type.to_s.singularize}_id"

          # Get source IDs
          source_ids = source_records.map { |r| r._model.send(_primary_key) }.compact.uniq

          return {} if source_ids.empty?

          # Query the related table with schema prefix
          full_table_name = "#{schema}.#{relationship.table_name || related_klass._table_name}"

          connection = ActiveRecord::Base.connection
          quoted_table = connection.quote_table_name(full_table_name)
          quoted_key = connection.quote_column_name(foreign_key)
          quoted_ids = source_ids.map { |id| connection.quote(id) }.join(',')

          sql = "SELECT * FROM #{quoted_table} WHERE #{quoted_key} IN (#{quoted_ids})"
          related_records = connection.exec_query(sql)

          # Convert to fragments
          fragments = {}
          related_records.each do |record_hash|
            # Create a model instance from the hash
            model_class = related_klass._model_class
            instance = model_class.instantiate(record_hash)
            resource = related_klass.new(instance, options[:context])
            rid = JSONAPI::ResourceIdentity.new(related_klass, instance.id)
            fragments[rid] = JSONAPI::ResourceFragment.new(rid, resource: resource)
          end

          fragments
        end
      end
    end
  end
end