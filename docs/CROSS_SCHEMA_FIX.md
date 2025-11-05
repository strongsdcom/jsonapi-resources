# Cross-Schema Relationship Linkage Fix

## Problem

When using `has_one` or `has_many` relationships with the `schema:` option for cross-schema relationships, the relationship linkage data was not being set correctly in the JSON:API response.

**Symptom:**
```json
{
  "data": {
    "relationships": {
      "author": {
        "data": null  // ❌ Should be { "type": "users", "id": "123" }
      }
    }
  },
  "included": [
    {
      "type": "users",  // ✅ Related resource is included
      "id": "123",
      "attributes": { ... }
    }
  ]
}
```

The related resource appears in the `included` section, but `relationships.author.data` is `null`, preventing clients from properly linking the resources.

## Root Cause

The `handle_cross_schema_to_one` and `handle_cross_schema_to_many` methods in `active_relation_resource_patch.rb` were:

1. ✅ Correctly loading related resources from cross-schema tables
2. ✅ Correctly adding them to `included` section
3. ❌ **NOT** setting the relationship linkage data in the source resource

This prevented JSON:API clients from establishing the relationship between the primary resource and the included resource.

## Solution

Modified `lib/jsonapi/active_relation_resource_patch.rb` to:

### 1. Handle Array sources (not just Hash)

The `handle_cross_schema_included` method now converts Array sources to a Hash of fragments:

```ruby
source_fragments_hash = {}
source_ids = if source.is_a?(Hash)
  source_fragments_hash = source
  source.keys.map(&:id)
elsif source.is_a?(Array)
  source.each do |item|
    if item.respond_to?(:identity)
      source_fragments_hash[item.identity] = item
    elsif item.is_a?(JSONAPI::ResourceIdentity)
      source_fragments_hash[item] = JSONAPI::ResourceFragment.new(item)
    end
  end
  # ...
end
```

### 2. Add linkage to source fragments

In both `handle_cross_schema_to_one` and `handle_cross_schema_to_many`, after creating the related resource fragment, we now add the linkage to the source fragment:

```ruby
# Create fragment for related resource
fragments[rid] = JSONAPI::ResourceFragment.new(rid, resource: resource)

# Add linkage to source fragment
source_rid = JSONAPI::ResourceIdentity.new(self, source_resource.id)
if options[:source_fragments] && options[:source_fragments][source_rid]
  options[:source_fragments][source_rid].add_related_identity(relationship.name, rid)
end
```

This ensures that the `relationships.<name>.data` field is populated correctly in the serialized output.

## Testing

### Unit Tests

Created comprehensive unit tests in `test/unit/resource/cross_schema_linkage_test.rb`:

- `test_has_one_cross_schema_creates_linkage_data` - Verifies linkage data is set for has_one
- `test_has_one_cross_schema_with_null_foreign_key` - Handles null foreign keys gracefully
- `test_cross_schema_relationship_with_array_source` - Tests Array source handling
- `test_cross_schema_relationship_with_hash_source` - Tests Hash source handling
- `test_multiple_candidates_with_same_recruiter` - Tests deduplication
- `test_cross_schema_included_in_full_serialization` - End-to-end serialization test
- `test_cross_schema_relationships_hash_registration` - Verifies configuration
- `test_non_cross_schema_relationships_still_work` - Regression test

### Test Fixtures

Created test fixtures:
- `test_users.yml` - User data from "another schema"
- `test_candidates.yml` - Primary resources with foreign keys
- `test_locations.yml` - Normal same-schema relationships
- `test_departments.yml` - For has_many testing

## Usage

Define cross-schema relationships using the `schema:` option:

### has_one example:

```ruby
class CandidateResource < JSONAPI::ActiveRelationResource
  attributes :full_name, :email

  has_one :author,
    class_name: 'User',
    schema: 'auth_schema',
    exclude_links: :default,
    always_include_linkage_data: true
end
```

### has_many example:

```ruby
class DepartmentResource < JSONAPI::ActiveRelationResource
  attributes :name

  has_many :members,
    class_name: 'User',
    schema: 'auth_schema',
    exclude_links: :default
end
```

## Files Modified

- `lib/jsonapi/active_relation_resource_patch.rb` - Core fix for linkage
- `test/unit/resource/cross_schema_linkage_test.rb` - Comprehensive unit tests
- `test/unit/resource/cross_schema_test.rb` - Original cross-schema tests
- `test/fixtures/active_record.rb` - Added test tables
- `test/fixtures/test_*.yml` - Test data fixtures

## Running Tests

```bash
cd jsonapi-resources
bundle install
bundle exec rake test TEST=test/unit/resource/cross_schema_linkage_test.rb
```

## Migration Notes

Existing applications using cross-schema relationships will automatically benefit from this fix. No changes to application code are required - the linkage data will now be correctly populated in responses.
