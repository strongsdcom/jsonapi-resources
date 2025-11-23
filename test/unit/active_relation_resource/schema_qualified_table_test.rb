require File.expand_path('../../../test_helper', __FILE__)

class SchemaQualifiedTableTest < ActiveSupport::TestCase
  class TestResource < JSONAPI::ActiveRelationResource
    # Empty resource for testing class methods
  end

  def test_concat_table_field_with_simple_table_quoted
    result = TestResource.send(:concat_table_field, 'users', 'id', true)
    assert_equal '"users"."id"', result
  end

  def test_concat_table_field_with_simple_table_unquoted
    result = TestResource.send(:concat_table_field,'users', 'id', false)
    assert_equal 'users.id', result
  end

  def test_concat_table_field_with_schema_qualified_table_quoted
    # Schema-qualified table should be split: schema.table.field
    # Should become: "schema"."table"."field"
    result = TestResource.send(:concat_table_field,'core_api.employees_v1', 'id', true)
    assert_equal '"core_api"."employees_v1"."id"', result
  end

  def test_concat_table_field_with_schema_qualified_table_unquoted
    result = TestResource.send(:concat_table_field,'core_api.employees_v1', 'id', false)
    assert_equal 'core_api.employees_v1.id', result
  end

  def test_concat_table_field_with_blank_table_quoted
    result = TestResource.send(:concat_table_field,'', 'users.id', true)
    assert_equal '"users.id"', result
  end

  def test_concat_table_field_with_blank_table_unquoted
    result = TestResource.send(:concat_table_field,'', 'users.id', false)
    assert_equal 'users.id', result
  end

  def test_concat_table_field_with_nil_table_quoted
    result = TestResource.send(:concat_table_field,nil, 'users.id', true)
    assert_equal '"users.id"', result
  end

  def test_concat_table_field_with_field_containing_dot_quoted
    # When field already contains a dot, table is ignored
    result = TestResource.send(:concat_table_field,'users', 'accounts.name', true)
    assert_equal '"accounts.name"', result
  end

  def test_alias_table_field_with_simple_table_quoted
    result = TestResource.send(:alias_table_field,'users', 'id', true)
    assert_equal '"users_id"', result
  end

  def test_alias_table_field_with_simple_table_unquoted
    result = TestResource.send(:alias_table_field,'users', 'id', false)
    assert_equal 'users_id', result
  end

  def test_alias_table_field_with_schema_qualified_table_quoted
    # Schema-qualified table dots should be replaced with underscores in alias
    # "core_api.employees_v1" becomes "core_api_employees_v1_id"
    result = TestResource.send(:alias_table_field,'core_api.employees_v1', 'id', true)
    assert_equal '"core_api_employees_v1_id"', result
  end

  def test_alias_table_field_with_schema_qualified_table_unquoted
    result = TestResource.send(:alias_table_field,'core_api.employees_v1', 'id', false)
    assert_equal 'core_api_employees_v1_id', result
  end

  def test_alias_table_field_with_blank_table_quoted
    result = TestResource.send(:alias_table_field,'', 'users.id', true)
    assert_equal '"users.id"', result
  end

  def test_alias_table_field_with_blank_table_unquoted
    result = TestResource.send(:alias_table_field,'', 'users.id', false)
    assert_equal 'users.id', result
  end

  def test_alias_table_field_with_nil_table_quoted
    result = TestResource.send(:alias_table_field,nil, 'users.id', true)
    assert_equal '"users.id"', result
  end

  def test_alias_table_field_with_field_containing_dot_quoted
    # When field contains dot, table is ignored
    result = TestResource.send(:alias_table_field,'users', 'accounts.name', true)
    assert_equal '"accounts.name"', result
  end

  def test_sql_field_with_alias_with_simple_table
    result = TestResource.send(:sql_field_with_alias,'users', 'id', true)
    expected_sql = '"users"."id" AS "users_id"'
    # Arel.sql returns Arel::Nodes::SqlLiteral, which contains the SQL string
    assert_equal expected_sql, result.to_s
  end

  def test_sql_field_with_alias_with_schema_qualified_table
    result = TestResource.send(:sql_field_with_alias,'core_api.employees_v1', 'id', true)
    expected_sql = '"core_api"."employees_v1"."id" AS "core_api_employees_v1_id"'
    # Arel.sql returns Arel::Nodes::SqlLiteral, which contains the SQL string
    assert_equal expected_sql, result.to_s
  end

  def test_quote_method
    result = TestResource.send(:quote,'field_name')
    assert_equal '"field_name"', result
  end

  def test_quote_method_with_dots
    result = TestResource.send(:quote,'schema.table')
    assert_equal '"schema.table"', result
  end

  def test_multiple_schema_levels
    # Edge case: what if someone has multiple dots?
    # Current implementation splits on first 2 parts only
    result = TestResource.send(:concat_table_field,'schema.subschema.table', 'id', true)
    # split('.', 2) will create ['schema', 'subschema.table']
    assert_equal '"schema"."subschema.table"."id"', result
  end
end
