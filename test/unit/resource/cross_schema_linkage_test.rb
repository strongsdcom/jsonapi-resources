require File.expand_path('../../../test_helper', __FILE__)

class CrossSchemaLinkageTest < ActiveSupport::TestCase
  # Disable fixtures for this test class since we create data manually
  self.use_transactional_tests = false

  # Override to prevent fixtures from loading
  def setup_fixtures
    # Do nothing - we don't use fixtures in this test
  end

  # Override to prevent fixtures teardown errors
  def teardown_fixtures
    # Do nothing - we don't use fixtures in this test
  end
  # Define models for testing
  class TestUser < ActiveRecord::Base
    self.table_name = 'test_users'
  end

  class TestLocation < ActiveRecord::Base
    self.table_name = 'test_locations'
  end

  class TestCandidate < ActiveRecord::Base
    self.table_name = 'test_candidates'
    belongs_to :recruiter, class_name: 'CrossSchemaLinkageTest::TestUser', foreign_key: 'recruiter_id', optional: true
    belongs_to :location, class_name: 'CrossSchemaLinkageTest::TestLocation', optional: true
  end

  class TestDepartment < ActiveRecord::Base
    self.table_name = 'test_departments'
    belongs_to :manager, class_name: 'CrossSchemaLinkageTest::TestUser', foreign_key: 'manager_id', optional: true
  end

  class TestCompany < ActiveRecord::Base
    self.table_name = 'test_companies'
    has_many :employees, class_name: 'CrossSchemaLinkageTest::TestUser', foreign_key: 'company_id'
  end

  class TestProject < ActiveRecord::Base
    self.table_name = 'test_projects'
    has_many :project_members, class_name: 'CrossSchemaLinkageTest::TestProjectMember', foreign_key: 'test_project_id'
    has_many :members, through: :project_members, source: :user, class_name: 'CrossSchemaLinkageTest::TestUser'
  end

  class TestProjectMember < ActiveRecord::Base
    self.table_name = 'test_project_members'
    belongs_to :project, class_name: 'CrossSchemaLinkageTest::TestProject', foreign_key: 'test_project_id'
    belongs_to :user, class_name: 'CrossSchemaLinkageTest::TestUser', foreign_key: 'test_user_id'
  end

  # Define JSONAPI Resources
  class TestUserResource < JSONAPI::Resource
    model_name 'CrossSchemaLinkageTest::TestUser'
    attributes :first_name, :last_name, :email
  end

  class TestLocationResource < JSONAPI::Resource
    model_name 'CrossSchemaLinkageTest::TestLocation'
    attributes :name
  end

  class TestCandidateResource < JSONAPI::ActiveRelationResource
    model_name 'CrossSchemaLinkageTest::TestCandidate'
    attributes :full_name, :email

    has_one :recruiter, class_name: 'TestUser', schema: 'core_api', exclude_links: :default, always_include_linkage_data: true
    has_one :location, exclude_links: :default
  end

  class TestDepartmentResource < JSONAPI::ActiveRelationResource
    model_name 'CrossSchemaLinkageTest::TestDepartment'
    attributes :name

    has_one :manager, class_name: 'TestUser', schema: 'core_api', exclude_links: :default, always_include_linkage_data: true
  end

  class TestCompanyResource < JSONAPI::ActiveRelationResource
    model_name 'CrossSchemaLinkageTest::TestCompany'
    attributes :name

    has_many :employees, class_name: 'TestUser', schema: 'hr_schema', exclude_links: :default
  end

  class TestProjectResource < JSONAPI::ActiveRelationResource
    model_name 'CrossSchemaLinkageTest::TestProject'
    attributes :name

    has_many :members, class_name: 'TestUser', schema: 'core_api', exclude_links: :default
  end

  def setup
    # Cross-schema functionality only works with PostgreSQL
    skip "Cross-schema tests require PostgreSQL" unless ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'

    DatabaseCleaner.start
    @user = TestUser.create!(first_name: 'Robert', last_name: 'Khromei', email: 'robert@example.com')
    @user2 = TestUser.create!(first_name: 'Alice', last_name: 'Smith', email: 'alice@example.com')
    @location = TestLocation.create!(name: 'Kyiv')
    @candidate = TestCandidate.create!(full_name: 'John Doe', email: 'john@example.com', recruiter_id: @user.id, location_id: @location.id)
    @department = TestDepartment.create!(name: 'Engineering', manager_id: @user.id)
    @company = TestCompany.create!(name: 'ACME Corp')
    @project = TestProject.create!(name: 'Website Redesign')
  end

  def teardown
    DatabaseCleaner.clean
  end

  def test_has_one_cross_schema_creates_linkage_data
    # Test that has_one cross-schema relationship properly sets linkage data

    # Create the resource
    resource = TestCandidateResource.new(@candidate, nil)

    # Serialize with include
    serializer = JSONAPI::ResourceSerializer.new(TestCandidateResource, include: ['recruiter', 'location'])
    json = serializer.serialize_to_hash(resource)

    # Assert structure
    assert_not_nil json['data'], "Should have data section"
    assert_not_nil json['data']['relationships'], "Should have relationships"

    # Check recruiter relationship (cross-schema)
    recruiter_rel = json['data']['relationships']['recruiter']
    assert_not_nil recruiter_rel, "Recruiter relationship should exist"
    assert_not_nil recruiter_rel['data'], "Recruiter linkage data should NOT be null"
    assert_equal 'test-users', recruiter_rel['data']['type'], "Recruiter type should be test-users"
    assert_equal @user.id.to_s, recruiter_rel['data']['id'], "Recruiter id should match"

    # Check location relationship (normal, same schema)
    location_rel = json['data']['relationships']['location']
    assert_not_nil location_rel, "Location relationship should exist"
    assert_not_nil location_rel['data'], "Location linkage data should NOT be null"
    assert_equal 'test-locations', location_rel['data']['type']
    assert_equal @location.id.to_s, location_rel['data']['id']

    # Check included section contains both
    assert_not_nil json['included'], "Should have included section"

    user_included = json['included'].find { |inc| inc['type'] == 'test-users' && inc['id'] == @user.id.to_s }
    assert_not_nil user_included, "User should be in included section"
    assert_equal 'Robert', user_included['attributes']['first-name']

    location_included = json['included'].find { |inc| inc['type'] == 'test-locations' && inc['id'] == @location.id.to_s }
    assert_not_nil location_included, "Location should be in included section"
  end

  def test_has_one_cross_schema_with_null_foreign_key
    # Test that null foreign keys are handled gracefully
    candidate_without = TestCandidate.create!(full_name: 'No Recruiter', email: 'none@example.com', recruiter_id: nil)

    resource = TestCandidateResource.new(candidate_without, nil)
    serializer = JSONAPI::ResourceSerializer.new(TestCandidateResource, include: ['recruiter'])
    json = serializer.serialize_to_hash(resource)

    recruiter_rel = json['data']['relationships']['recruiter']
    assert_not_nil recruiter_rel, "Recruiter relationship should exist"
    assert_nil recruiter_rel['data'], "Recruiter linkage data should be null when foreign key is null"

    # Should not have user in included
    users_in_included = json['included']&.select { |inc| inc['type'] == 'test-users' } || []
    assert_empty users_in_included, "Should not include any users when recruiter_id is null"
  end

  def test_cross_schema_relationship_with_array_source
    # This tests the specific case where source comes as Array (not Hash)
    # which was the bug we fixed

    source_identity = JSONAPI::ResourceIdentity.new(TestCandidateResource, @candidate.id)
    source_fragment = JSONAPI::ResourceFragment.new(source_identity)

    # Call find_included_fragments with Array source (simulating real usage)
    fragments = TestCandidateResource.find_included_fragments(
      [source_fragment],
      :recruiter,
      { context: nil }
    )

    assert_not_nil fragments, "Should return fragments"
    assert fragments.is_a?(Hash), "Fragments should be a hash"

    # Check that linkage was added to source fragment
    assert_not_nil source_fragment.related[:recruiter], "Source fragment should have recruiter linkage"
    recruiter_identities = source_fragment.related[:recruiter].to_a
    assert_equal 1, recruiter_identities.size, "Should have one recruiter identity"
    assert_equal @user.id, recruiter_identities.first.id, "Recruiter ID should match"
  end

  def test_cross_schema_relationship_with_hash_source
    # Test when source is already a Hash of fragments

    source_identity = JSONAPI::ResourceIdentity.new(TestCandidateResource, @candidate.id)
    source_fragment = JSONAPI::ResourceFragment.new(source_identity)
    source_hash = { source_identity => source_fragment }

    # Call find_included_fragments with Hash source
    fragments = TestCandidateResource.find_included_fragments(
      source_hash,
      :recruiter,
      { context: nil }
    )

    assert_not_nil fragments, "Should return fragments"

    # Check that linkage was added to source fragment
    assert_not_nil source_fragment.related[:recruiter], "Source fragment should have recruiter linkage"
    recruiter_identities = source_fragment.related[:recruiter].to_a
    assert_equal 1, recruiter_identities.size
    assert_equal @user.id, recruiter_identities.first.id
  end

  def test_multiple_candidates_with_same_recruiter
    # Test that multiple candidates with same recruiter work correctly
    candidate2 = TestCandidate.create!(full_name: 'Jane Doe', email: 'jane@example.com', recruiter_id: @user.id)

    # Create fragments for both candidates
    frag1_id = JSONAPI::ResourceIdentity.new(TestCandidateResource, @candidate.id)
    frag1 = JSONAPI::ResourceFragment.new(frag1_id)

    frag2_id = JSONAPI::ResourceIdentity.new(TestCandidateResource, candidate2.id)
    frag2 = JSONAPI::ResourceFragment.new(frag2_id)

    source_hash = { frag1_id => frag1, frag2_id => frag2 }

    # Load recruiter for both
    fragments = TestCandidateResource.find_included_fragments(
      source_hash,
      :recruiter,
      { context: nil }
    )

    # Both candidates should have linkage to same recruiter
    assert_not_nil frag1.related[:recruiter], "Candidate 1 should have recruiter linkage"
    assert_not_nil frag2.related[:recruiter], "Candidate 2 should have recruiter linkage"

    assert_equal @user.id, frag1.related[:recruiter].first.id
    assert_equal @user.id, frag2.related[:recruiter].first.id

    # Should only have ONE user fragment (deduped)
    assert_equal 1, fragments.size, "Should have exactly one user fragment"
  end

  def test_cross_schema_included_in_full_serialization
    # Full end-to-end test with serializer
    resource = TestCandidateResource.new(@candidate, nil)

    serializer = JSONAPI::ResourceSerializer.new(
      TestCandidateResource,
      include: ['recruiter']
    )
    json = serializer.serialize_to_hash(resource)

    # Verify complete JSON structure
    assert json['data']['relationships']['recruiter']['data'].present?, "Recruiter linkage should be present"
    assert_equal 'test-users', json['data']['relationships']['recruiter']['data']['type']
    assert_equal @user.id.to_s, json['data']['relationships']['recruiter']['data']['id']

    # Verify included
    user_data = json['included'].find { |inc| inc['type'] == 'test-users' }
    assert_not_nil user_data, "User should be in included"
    assert_equal 'Robert', user_data['attributes']['first-name']
    assert_equal 'Khromei', user_data['attributes']['last-name']
  end

  def test_cross_schema_relationships_hash_registration
    # Verify that cross-schema relationships are properly registered
    assert_not_nil TestCandidateResource._cross_schema_relationships
    assert TestCandidateResource._cross_schema_relationships.key?(:recruiter)

    recruiter_config = TestCandidateResource._cross_schema_relationships[:recruiter]
    assert_equal 'core_api', recruiter_config[:schema]
    assert_equal :has_one, recruiter_config[:type]
  end

  def test_non_cross_schema_relationships_still_work
    # Verify that normal relationships without schema option still work
    resource = TestCandidateResource.new(@candidate, nil)
    serializer = JSONAPI::ResourceSerializer.new(TestCandidateResource, include: ['location'])
    json = serializer.serialize_to_hash(resource)

    # Location is NOT cross-schema, should work normally
    location_rel = json['data']['relationships']['location']
    assert_not_nil location_rel['data'], "Normal relationship should have linkage"
    assert_equal 'test-locations', location_rel['data']['type']
  end

  # === has_many cross-schema tests ===

  def test_has_many_cross_schema_creates_linkage_data
    # Test that has_many cross-schema relationship properly sets linkage data

    # Add users to company
    @user.update!(company_id: @company.id)
    @user2.update!(company_id: @company.id)

    resource = TestCompanyResource.new(@company, nil)
    serializer = JSONAPI::ResourceSerializer.new(TestCompanyResource, include: ['employees'])
    json = serializer.serialize_to_hash(resource)

    # Check employees relationship (cross-schema has_many)
    employees_rel = json['data']['relationships']['employees']
    assert_not_nil employees_rel, "Employees relationship should exist"
    assert_not_nil employees_rel['data'], "Employees linkage data should NOT be null"
    assert employees_rel['data'].is_a?(Array), "has_many linkage should be an array"
    assert_equal 2, employees_rel['data'].size, "Should have 2 users"

    # Verify user IDs in linkage
    user_ids = employees_rel['data'].map { |link| link['id'] }.sort
    assert_equal [@user.id.to_s, @user2.id.to_s].sort, user_ids

    # Verify all users are in included
    assert_not_nil json['included'], "Should have included section"
    included_users = json['included'].select { |inc| inc['type'] == 'test-users' }
    assert_equal 2, included_users.size, "Should have 2 users in included"
  end

  def test_has_many_cross_schema_with_array_source
    # Test has_many with Array source
    @user.update!(company_id: @company.id)
    @user2.update!(company_id: @company.id)

    source_identity = JSONAPI::ResourceIdentity.new(TestCompanyResource, @company.id)
    source_fragment = JSONAPI::ResourceFragment.new(source_identity)

    fragments = TestCompanyResource.find_included_fragments(
      [source_fragment],
      :employees,
      { context: nil }
    )

    # Check that linkage was added
    assert_not_nil source_fragment.related[:employees], "Should have employees linkage"
    user_identities = source_fragment.related[:employees].to_a
    assert_equal 2, user_identities.size, "Should have 2 user identities"

    user_ids = user_identities.map(&:id).sort
    assert_equal [@user.id, @user2.id].sort, user_ids
  end

  def test_has_many_cross_schema_empty_collection
    # Test has_many when there are no related records
    empty_company = TestCompany.create!(name: 'Empty Corp')

    resource = TestCompanyResource.new(empty_company, nil)
    serializer = JSONAPI::ResourceSerializer.new(TestCompanyResource, include: ['employees'])
    json = serializer.serialize_to_hash(resource)

    employees_rel = json['data']['relationships']['employees']
    assert_not_nil employees_rel, "Employees relationship should exist"
    # For empty has_many, data should be empty array (or possibly null depending on config)
    assert employees_rel['data'].nil? || employees_rel['data'] == [], "Empty has_many should have empty or null data"

    # Should not have any users in included
    included_users = json['included']&.select { |inc| inc['type'] == 'test-users' } || []
    assert_empty included_users, "Should not include any users"
  end

  def test_has_many_cross_schema_deduplication
    # Test that same user in multiple companies is not duplicated
    company2 = TestCompany.create!(name: 'Other Corp')

    # Same user works for both companies
    @user.update!(company_id: @company.id)

    # Create fragments for both companies
    frag1_id = JSONAPI::ResourceIdentity.new(TestCompanyResource, @company.id)
    frag1 = JSONAPI::ResourceFragment.new(frag1_id)

    frag2_id = JSONAPI::ResourceIdentity.new(TestCompanyResource, company2.id)
    frag2 = JSONAPI::ResourceFragment.new(frag2_id)

    source_hash = { frag1_id => frag1, frag2_id => frag2 }

    fragments = TestCompanyResource.find_included_fragments(
      source_hash,
      :employees,
      { context: nil }
    )

    # User should appear only once in fragments
    user_fragments = fragments.select { |rid, _| rid.resource_klass == TestUserResource }
    assert_equal 1, user_fragments.size, "User should appear only once in fragments"
  end

  # === has_many :through cross-schema tests ===

  def test_has_many_through_cross_schema_creates_linkage_data
    # Test that has_many :through cross-schema relationship properly sets linkage data
    # This tests the specific code path in handle_cross_schema_to_many that handles :through relationships

    # Add members to project via join table
    TestProjectMember.create!(test_project_id: @project.id, test_user_id: @user.id, role: 'developer')
    TestProjectMember.create!(test_project_id: @project.id, test_user_id: @user2.id, role: 'manager')

    resource = TestProjectResource.new(@project, nil)
    serializer = JSONAPI::ResourceSerializer.new(TestProjectResource, include: ['members'])
    json = serializer.serialize_to_hash(resource)

    # Check members relationship (cross-schema has_many :through)
    members_rel = json['data']['relationships']['members']
    assert_not_nil members_rel, "Members relationship should exist"
    assert_not_nil members_rel['data'], "Members linkage data should NOT be null"
    assert members_rel['data'].is_a?(Array), "has_many :through linkage should be an array"
    assert_equal 2, members_rel['data'].size, "Should have 2 members"

    # Verify user IDs in linkage
    member_ids = members_rel['data'].map { |link| link['id'] }.sort
    assert_equal [@user.id.to_s, @user2.id.to_s].sort, member_ids

    # Verify type is correct
    members_rel['data'].each do |link|
      assert_equal 'test-users', link['type'], "Member type should be test-users"
    end

    # Verify all members are in included
    assert_not_nil json['included'], "Should have included section"
    included_users = json['included'].select { |inc| inc['type'] == 'test-users' }
    assert_equal 2, included_users.size, "Should have 2 users in included"

    # Verify user attributes
    robert = included_users.find { |u| u['id'] == @user.id.to_s }
    assert_not_nil robert, "Robert should be in included"
    assert_equal 'Robert', robert['attributes']['first-name']

    alice = included_users.find { |u| u['id'] == @user2.id.to_s }
    assert_not_nil alice, "Alice should be in included"
    assert_equal 'Alice', alice['attributes']['first-name']
  end

  def test_has_many_through_cross_schema_with_array_source
    # Test has_many :through with Array source
    TestProjectMember.create!(test_project_id: @project.id, test_user_id: @user.id, role: 'developer')
    TestProjectMember.create!(test_project_id: @project.id, test_user_id: @user2.id, role: 'manager')

    source_identity = JSONAPI::ResourceIdentity.new(TestProjectResource, @project.id)
    source_fragment = JSONAPI::ResourceFragment.new(source_identity)

    fragments = TestProjectResource.find_included_fragments(
      [source_fragment],
      :members,
      { context: nil }
    )

    # Check that linkage was added
    assert_not_nil source_fragment.related[:members], "Should have members linkage"
    member_identities = source_fragment.related[:members].to_a
    assert_equal 2, member_identities.size, "Should have 2 member identities"

    member_ids = member_identities.map(&:id).sort
    assert_equal [@user.id, @user2.id].sort, member_ids

    # Verify fragments were created
    assert_equal 2, fragments.size, "Should have 2 user fragments"
  end

  def test_has_many_through_cross_schema_empty_collection
    # Test has_many :through when there are no related records
    empty_project = TestProject.create!(name: 'Empty Project')

    resource = TestProjectResource.new(empty_project, nil)
    serializer = JSONAPI::ResourceSerializer.new(TestProjectResource, include: ['members'])
    json = serializer.serialize_to_hash(resource)

    members_rel = json['data']['relationships']['members']
    assert_not_nil members_rel, "Members relationship should exist"
    # For empty has_many, data should be empty array (or possibly null depending on config)
    assert members_rel['data'].nil? || members_rel['data'] == [], "Empty has_many :through should have empty or null data"

    # Should not have any users in included
    included_users = json['included']&.select { |inc| inc['type'] == 'test-users' } || []
    assert_empty included_users, "Should not include any users"
  end

  def test_has_many_through_cross_schema_with_multiple_projects
    # Test that has_many :through works correctly with multiple source records
    project2 = TestProject.create!(name: 'Mobile App')

    # Project 1 has user1 and user2
    TestProjectMember.create!(test_project_id: @project.id, test_user_id: @user.id, role: 'developer')
    TestProjectMember.create!(test_project_id: @project.id, test_user_id: @user2.id, role: 'manager')

    # Project 2 has only user1
    TestProjectMember.create!(test_project_id: project2.id, test_user_id: @user.id, role: 'lead')

    # Create fragments for both projects
    frag1_id = JSONAPI::ResourceIdentity.new(TestProjectResource, @project.id)
    frag1 = JSONAPI::ResourceFragment.new(frag1_id)

    frag2_id = JSONAPI::ResourceIdentity.new(TestProjectResource, project2.id)
    frag2 = JSONAPI::ResourceFragment.new(frag2_id)

    source_hash = { frag1_id => frag1, frag2_id => frag2 }

    fragments = TestProjectResource.find_included_fragments(
      source_hash,
      :members,
      { context: nil }
    )

    # Project 1 should have 2 members
    assert_not_nil frag1.related[:members], "Project 1 should have members linkage"
    project1_members = frag1.related[:members].to_a
    assert_equal 2, project1_members.size, "Project 1 should have 2 members"
    assert_equal [@user.id, @user2.id].sort, project1_members.map(&:id).sort

    # Project 2 should have 1 member
    assert_not_nil frag2.related[:members], "Project 2 should have members linkage"
    project2_members = frag2.related[:members].to_a
    assert_equal 1, project2_members.size, "Project 2 should have 1 member"
    assert_equal @user.id, project2_members.first.id

    # User1 should appear only once in fragments (deduped)
    user_fragments = fragments.select { |rid, _| rid.resource_klass == TestUserResource }
    assert_equal 2, user_fragments.size, "Should have 2 unique user fragments (user1 and user2)"
  end
end

