# frozen_string_literal: true

# Extensions to ActiveRelationResource for cross-schema support
module JSONAPI
  class ActiveRelationResource
    class << self
      # Store original methods if they exist
      def setup_cross_schema_support
        return if @cross_schema_support_setup

        # Only alias if the method exists and hasn't been aliased already
        if method_defined?(:find_related_fragments) && !method_defined?(:original_find_related_fragments)
          alias_method :original_find_related_fragments, :find_related_fragments
        end

        if method_defined?(:find_included_fragments) && !method_defined?(:original_find_included_fragments)
          alias_method :original_find_included_fragments, :find_included_fragments
        end

        @cross_schema_support_setup = true
      end

      # Override find_related_fragments to handle cross-schema relationships
      def find_related_fragments(source_rids, relationship_name, options = {})
        setup_cross_schema_support

        relationship = _relationship(relationship_name)

        if defined?(_cross_schema_relationships) && _cross_schema_relationships && (cross_schema_info = _cross_schema_relationships[relationship_name.to_sym])
          # Handle cross-schema relationship
          schema = cross_schema_info[:schema]

          # Get the source records
          source_records = source_rids.map { |rid| find_by_key(rid.id, options) }.compact

          # Build the cross-schema query
          if relationship.is_a?(JSONAPI::Relationship::ToOne)
            handle_cross_schema_to_one(source_records, relationship, schema, options)
          else
            handle_cross_schema_to_many(source_records, relationship, schema, options)
          end
        else
          # Use the original method for normal relationships
          if respond_to?(:original_find_related_fragments)
            original_find_related_fragments(source_rids, relationship_name, options)
          else
            super(source_rids, relationship_name, options)
          end
        end
      end

      # Override find_included_fragments to handle cross-schema relationships
      def find_included_fragments(source, relationship_name, options)
        setup_cross_schema_support

        relationship = _relationship(relationship_name)

        if defined?(_cross_schema_relationships) && _cross_schema_relationships && (cross_schema_info = _cross_schema_relationships[relationship_name.to_sym])
          # Handle cross-schema relationship
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
        elsif respond_to?(:original_find_included_fragments)
          # Use the original method for normal relationships
          original_find_included_fragments(source, relationship_name, options)
        else
          # This resource doesn't have find_included_fragments, delegate to parent
          # We'll use the default implementation from ActiveRelationResource
          find_included_fragments_default(source, relationship_name, options)
        end
      end

      # Default implementation for resources that don't have find_included_fragments
      def find_included_fragments_default(source, relationship_name, options)
        relationship = _relationship(relationship_name)

        if relationship.polymorphic?
          find_related_polymorphic_fragments(source, relationship_name, options, true)
        else
          find_related_monomorphic_fragments(source, relationship, options, true)
        end
      end

      private

      def handle_cross_schema_to_one(source_records, relationship, schema, options)
        # For has_one or belongs_to with cross-schema
        related_klass = relationship.resource_klass
        foreign_key = relationship.foreign_key

        # Get the foreign key values from source records
        foreign_key_values = source_records.map { |r| r._model.send(foreign_key) }.compact.uniq

        return {} if foreign_key_values.empty?

        # Query the related table with schema prefix
        full_table_name = "#{schema}.users_v1"

        # Use raw SQL to query cross-schema
        sql = "SELECT * FROM #{full_table_name} WHERE id IN (?)"
        related_records = ActiveRecord::Base.connection.exec_query(
          ActiveRecord::Base.send(:sanitize_sql_array, [sql, foreign_key_values])
        )

        # Convert to fragments
        fragments = {}
        related_records.each do |record_hash|
          # Create a mock Employee model instance from the hash
          employee = Employee.instantiate(record_hash)
          resource = related_klass.new(employee, options[:context])
          rid = JSONAPI::ResourceIdentity.new(related_klass, employee.id)
          fragments[rid] = JSONAPI::ResourceFragment.new(rid, resource: resource)
        end

        fragments
      end

      def handle_cross_schema_to_many(source_records, relationship, schema, options)
        # For has_many with cross-schema
        related_klass = relationship.resource_klass

        # Determine the foreign key based on the source model
        foreign_key = "#{_type.to_s.singularize}_id"

        # Get source IDs
        source_ids = source_records.map { |r| r._model.send(_primary_key) }.compact.uniq

        return {} if source_ids.empty?

        # Query the related table with schema prefix
        full_table_name = "#{schema}.users_v1"

        # For has_many employees, we need to handle the join table or direct relationship
        # This is a simplified version - you may need to adjust based on your actual schema
        sql = "SELECT * FROM #{full_table_name}"
        related_records = ActiveRecord::Base.connection.exec_query(sql)

        # Convert to fragments
        fragments = {}
        related_records.each do |record_hash|
          # Create a mock Employee model instance from the hash
          employee = Employee.instantiate(record_hash)
          resource = related_klass.new(employee, options[:context])
          rid = JSONAPI::ResourceIdentity.new(related_klass, employee.id)
          fragments[rid] = JSONAPI::ResourceFragment.new(rid, resource: resource)
        end

        fragments
      end
    end
  end
end