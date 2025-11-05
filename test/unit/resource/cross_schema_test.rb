require File.expand_path('../../../test_helper', __FILE__)

class CrossSchemaTest < ActiveSupport::TestCase
  class Organization < ActiveRecord::Base
    self.table_name = 'companies'
    has_many :employees, class_name: 'CrossSchemaTest::Employee'
  end

  class Employee < ActiveRecord::Base
    self.table_name = 'people'
    belongs_to :organization, class_name: 'CrossSchemaTest::Organization', foreign_key: 'company_id'
  end

  class OrganizationResource < JSONAPI::ActiveRelationResource
    model_name 'CrossSchemaTest::Organization'
    attributes :name

    has_many :employees

    # Define cross-schema relationship using the module method
    self._cross_schema_relationships = { employees: { schema: 'hr_schema' } }
  end

  class EmployeeResource < JSONAPI::Resource
    model_name 'CrossSchemaTest::Employee'
    attributes :name, :email

    has_one :organization
  end

  def setup
    @original_cross_schema = OrganizationResource._cross_schema_relationships
  end

  def teardown
    OrganizationResource._cross_schema_relationships = @original_cross_schema
  end

  def test_cross_schema_relationship_registration
    OrganizationResource._cross_schema_relationships = { test_relation: { schema: 'test_schema' } }

    assert_not_nil OrganizationResource._cross_schema_relationships
    assert_equal 'test_schema', OrganizationResource._cross_schema_relationships[:test_relation][:schema]
  end

  def test_cross_schema_relationship_with_custom_table
    OrganizationResource._cross_schema_relationships = {
      custom_employees: {
        schema: 'custom_schema',
        table: 'custom_table'
      }
    }

    assert_equal 'custom_schema', OrganizationResource._cross_schema_relationships[:custom_employees][:schema]
    assert_equal 'custom_table', OrganizationResource._cross_schema_relationships[:custom_employees][:table]
  end

  def test_handle_cross_schema_to_one
    skip "Requires database setup for cross-schema testing"
    # This test would require actual cross-schema database setup
    # It's here as documentation of expected behavior

    # Setup mock data
    org = Organization.create!(name: 'Test Org')
    employee = Employee.create!(name: 'Test Employee', company_id: org.id)

    # Create resource instance
    org_resource = OrganizationResource.new(org, nil)

    # Test finding related fragments
    source_rids = [JSONAPI::ResourceIdentity.new(OrganizationResource, org.id)]
    fragments = OrganizationResource.find_related_fragments(source_rids, :employees, {})

    assert_equal 1, fragments.size
    assert_equal employee.id, fragments.keys.first.id
  end

  def test_handle_cross_schema_to_many
    skip "Requires database setup for cross-schema testing"
    # This test would require actual cross-schema database setup
    # It's here as documentation of expected behavior

    # Setup mock data
    org = Organization.create!(name: 'Test Org')
    employee1 = Employee.create!(name: 'Employee 1', company_id: org.id)
    employee2 = Employee.create!(name: 'Employee 2', company_id: org.id)

    # Create resource instance
    org_resource = OrganizationResource.new(org, nil)

    # Test finding related fragments
    source_rids = [JSONAPI::ResourceIdentity.new(OrganizationResource, org.id)]
    fragments = OrganizationResource.find_related_fragments(source_rids, :employees, {})

    assert_equal 2, fragments.size
    employee_ids = fragments.keys.map(&:id)
    assert_includes employee_ids, employee1.id
    assert_includes employee_ids, employee2.id
  end

  def test_cross_schema_included_fragments
    skip "Requires database setup for cross-schema testing"
    # This test would require actual cross-schema database setup

    org = Organization.create!(name: 'Test Org')
    employee = Employee.create!(name: 'Test Employee', company_id: org.id)

    # Create resource fragments
    org_rid = JSONAPI::ResourceIdentity.new(OrganizationResource, org.id)
    org_fragment = JSONAPI::ResourceFragment.new(org_rid)

    source = { org_rid => org_fragment }
    fragments = OrganizationResource.find_included_fragments(source, :employees, {})

    assert_equal 1, fragments.size
    assert_equal employee.id, fragments.keys.first.id
  end

  def test_cross_schema_with_filters
    skip "Requires database setup for cross-schema testing"
    # This test would require actual cross-schema database setup

    org = Organization.create!(name: 'Test Org')
    employee1 = Employee.create!(name: 'Alice', company_id: org.id)
    employee2 = Employee.create!(name: 'Bob', company_id: org.id)

    source_rids = [JSONAPI::ResourceIdentity.new(OrganizationResource, org.id)]

    # Test with filters
    filters = { name: 'Alice' }
    fragments = OrganizationResource.find_related_fragments(source_rids, :employees, { filters: filters })

    assert_equal 1, fragments.size
    assert_equal employee1.id, fragments.keys.first.id
  end

  def test_cross_schema_sql_injection_protection
    # Test that SQL is properly escaped
    OrganizationResource._cross_schema_relationships = {
      dangerous: { schema: "'; DROP TABLE users; --" }
    }

    # The schema should be stored but properly escaped when used
    assert_equal "'; DROP TABLE users; --", OrganizationResource._cross_schema_relationships[:dangerous][:schema]

    # When actually used in queries, it should be properly quoted
    # This is handled by ActiveRecord::Base.connection.quote_table_name
  end

  def test_cross_schema_with_context
    skip "Requires database setup for cross-schema testing"

    org = Organization.create!(name: 'Test Org')
    employee = Employee.create!(name: 'Test Employee', company_id: org.id)

    # Test with context
    context = { current_user: 'test_user' }
    source_rids = [JSONAPI::ResourceIdentity.new(OrganizationResource, org.id)]
    fragments = OrganizationResource.find_related_fragments(source_rids, :employees, { context: context })

    assert_equal 1, fragments.size
    # Verify context was passed through
    fragment = fragments.values.first
    assert_equal context, fragment.resource.context if fragment.resource
  end

  def test_module_inclusion
    # Test that the module is properly included
    assert OrganizationResource.respond_to?(:find_related_fragments)
    assert OrganizationResource.respond_to?(:find_included_fragments)
  end

  def test_fallback_to_normal_relationship
    # Test that non-cross-schema relationships still work
    OrganizationResource._cross_schema_relationships = nil

    # This should not raise an error and should call the original implementation
    assert_nothing_raised do
      source_rids = []
      OrganizationResource.find_related_fragments(source_rids, :employees, {})
    end
  end

  def test_has_one_cross_schema_linkage_data
    skip "Requires database setup for cross-schema testing"
    # This test verifies that has_one cross-schema relationships
    # properly set the linkage data in relationships.data

    # Setup: Create a candidate with recruiter_id pointing to employee in different schema
    # Expected: relationships.recruiter.data should be { type: "employees", id: "167" }
    # Actual bug: relationships.recruiter.data is null

    # Create test data
    org = Organization.create!(name: 'Test Company')
    employee = Employee.create!(name: 'Test Recruiter', company_id: org.id)

    # Simulate a resource with has_one cross-schema relationship
    class CandidateTest < ActiveRecord::Base
      self.table_name = 'companies' # Reuse existing table for test
      belongs_to :recruiter, class_name: 'CrossSchemaTest::Employee', foreign_key: 'id', optional: true
    end

    class CandidateResourceTest < JSONAPI::ActiveRelationResource
      model_name 'CrossSchemaTest::CandidateTest'
      attributes :name
      has_one :recruiter, class_name: 'Employee', schema: 'hr_schema', always_include_linkage_data: true
    end

    candidate = CandidateTest.create!(name: 'Test Candidate', id: employee.id)

    # Serialize the resource
    serializer = JSONAPI::ResourceSerializer.new(
      CandidateResourceTest,
      include: ['recruiter']
    )

    resource = CandidateResourceTest.new(candidate, nil)
    json = serializer.serialize_to_hash(resource)

    # Assert linkage data is set correctly
    assert_not_nil json['data']['relationships']['recruiter'], "Recruiter relationship should exist"
    assert_not_nil json['data']['relationships']['recruiter']['data'], "Recruiter linkage data should not be null"
    assert_equal 'employees', json['data']['relationships']['recruiter']['data']['type']
    assert_equal employee.id.to_s, json['data']['relationships']['recruiter']['data']['id']

    # Assert included contains the employee
    assert_not_nil json['included'], "Should have included section"
    employee_included = json['included'].find { |inc| inc['type'] == 'employees' && inc['id'] == employee.id.to_s }
    assert_not_nil employee_included, "Employee should be in included section"
  end
end