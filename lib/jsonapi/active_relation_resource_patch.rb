 # frozen_string_literal: true

# Monkey patch for ActiveRelationResource to support cross-schema relationships
module JSONAPI
  class ActiveRelationResource
    class << self
      # Store original methods
      alias_method :original_find_included_fragments, :find_included_fragments
      alias_method :original_find_related_monomorphic_fragments, :find_related_monomorphic_fragments

      # Override find_included_fragments to handle cross-schema relationships
      def find_included_fragments(source, relationship_name, options)
        relationship = _relationship(relationship_name)

        # Check if this resource has cross-schema relationships defined
        if respond_to?(:_cross_schema_relationships) && _cross_schema_relationships && (cross_schema_info = _cross_schema_relationships[relationship_name.to_sym])
          handle_cross_schema_included(source, relationship, cross_schema_info, options)
        else
          original_find_included_fragments(source, relationship_name, options)
        end
      end

      # Override find_related_monomorphic_fragments to handle cross-schema relationships
      def find_related_monomorphic_fragments(source, relationship, options, connect_source_identity)
        # Check if this resource has cross-schema relationships defined
        if respond_to?(:_cross_schema_relationships) && _cross_schema_relationships && (cross_schema_info = _cross_schema_relationships[relationship.name.to_sym])
          handle_cross_schema_included(source, relationship, cross_schema_info, options)
        else
          original_find_related_monomorphic_fragments(source, relationship, options, connect_source_identity)
        end
      end

      private

      def handle_cross_schema_included(source, relationship, cross_schema_info, options)
        schema = cross_schema_info[:schema]

        # Extract IDs and fragments from source - convert to hash if needed
        source_fragments_hash = {}
        source_ids = if source.is_a?(Hash)
          # Already a hash - use as is
          source_fragments_hash = source
          source.keys.map(&:id)
        elsif source.is_a?(Array)
          # Array - could be ResourceIdentities or ResourceFragments
          source.each do |item|
            if item.respond_to?(:identity)
              # It's a ResourceFragment
              source_fragments_hash[item.identity] = item
            elsif item.is_a?(JSONAPI::ResourceIdentity)
              # It's just an identity - create a basic fragment
              source_fragments_hash[item] = JSONAPI::ResourceFragment.new(item)
            end
          end
          source.map { |item| item.respond_to?(:identity) ? item.identity.id : item.id }
        else
          source.map(&:id)
        end

        # Pass source fragments to the handler so it can add linkage
        enhanced_options = options.dup
        enhanced_options[:source_fragments] = source_fragments_hash if source_fragments_hash.any?

        # Get the source records
        source_records = source_ids.map { |id| find_by_key(id, enhanced_options) }.compact

        # Build the cross-schema query
        if relationship.is_a?(JSONAPI::Relationship::ToOne)
          handle_cross_schema_to_one(source_records, relationship, schema, enhanced_options)
        else
          handle_cross_schema_to_many(source_records, relationship, schema, enhanced_options)
        end
      end

      def handle_cross_schema_to_one(source_records, relationship, schema, options)
        # For has_one or belongs_to with cross-schema
        related_klass = relationship.resource_klass
        foreign_key = relationship.foreign_key

        # Get the foreign key values from source records
        foreign_key_values = source_records.map { |r| r._model.send(foreign_key) }.compact.uniq

        return {} if foreign_key_values.empty?

        # Get the actual table name from the related resource's model
        related_model_class = related_klass._model_class
        base_table_name = related_model_class.table_name.split('.').last  # Remove schema if present
        full_table_name = "#{schema}.#{base_table_name}"

        # Use raw SQL to query cross-schema
        sql = "SELECT * FROM #{full_table_name} WHERE id IN (?)"
        related_records = ActiveRecord::Base.connection.exec_query(
          ActiveRecord::Base.send(:sanitize_sql_array, [sql, foreign_key_values])
        )

        # Create a mapping of foreign_key_value => related_record
        related_by_id = {}
        related_records.each do |record_hash|
          related_by_id[record_hash['id']] = record_hash
        end

        # Convert to fragments and add linkage to source fragments
        fragments = {}
        source_records.each do |source_resource|
          foreign_key_value = source_resource._model.send(foreign_key)
          next unless foreign_key_value

          record_hash = related_by_id[foreign_key_value]
          next unless record_hash

          # Create a model instance from the hash using the related model class
          model_instance = related_model_class.instantiate(record_hash)
          resource = related_klass.new(model_instance, options[:context])
          rid = JSONAPI::ResourceIdentity.new(related_klass, model_instance.id)

          # Create fragment for related resource
          fragments[rid] = JSONAPI::ResourceFragment.new(rid, resource: resource)

          # Add linkage to source fragment
          # This ensures relationships.recruiter.data is set in the JSON response
          source_rid = JSONAPI::ResourceIdentity.new(self, source_resource.id)
          if options[:source_fragments] && options[:source_fragments][source_rid]
            options[:source_fragments][source_rid].add_related_identity(relationship.name, rid)
          end
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

        # Get the actual table name from the related resource's model
        related_model_class = related_klass._model_class
        base_table_name = related_model_class.table_name.split('.').last  # Remove schema if present
        full_table_name = "#{schema}.#{base_table_name}"

        # For has_many employees, we need to handle the join table or direct relationship
        # Query with WHERE clause to filter by foreign key
        sql = "SELECT * FROM #{full_table_name} WHERE #{foreign_key} IN (?)"
        related_records = ActiveRecord::Base.connection.exec_query(
          ActiveRecord::Base.send(:sanitize_sql_array, [sql, source_ids])
        )

        # Group related records by source_id for linkage
        related_by_source = {}
        related_records.each do |record_hash|
          source_id = record_hash[foreign_key]
          related_by_source[source_id] ||= []
          related_by_source[source_id] << record_hash
        end

        # Convert to fragments and add linkage
        fragments = {}
        source_records.each do |source_resource|
          source_id = source_resource._model.send(_primary_key)
          records_for_source = related_by_source[source_id] || []

          records_for_source.each do |record_hash|
            # Create a model instance from the hash using the related model class
            model_instance = related_model_class.instantiate(record_hash)
            resource = related_klass.new(model_instance, options[:context])
            rid = JSONAPI::ResourceIdentity.new(related_klass, model_instance.id)
            fragments[rid] = JSONAPI::ResourceFragment.new(rid, resource: resource)

            # CRITICAL FIX: Add linkage to source fragment for has_many
            source_rid = JSONAPI::ResourceIdentity.new(self, source_resource.id)
            if options[:source_fragments] && options[:source_fragments][source_rid]
              options[:source_fragments][source_rid].add_related_identity(relationship.name, rid)
            end
          end
        end

        fragments
      end
    end
  end
end