require 'test_helper'
require 'pg_query'

class TestFingerprint < Minitest::Test
  def test_sqlite_placeholders
    assert_equal(
      Prosopite.fingerprint('SELECT "legs".* FROM "legs" WHERE "legs"."chair_id" = ? LIMIT ?', 'SQLite'),
      Prosopite.fingerprint('SELECT "legs".* FROM "legs" WHERE "legs"."chair_id" = ? LIMIT ?', 'SQLite')
    )
  end

  def test_sqlite_inlined_values
    assert_equal(
      Prosopite.fingerprint('SELECT "legs".* FROM "legs" WHERE "legs"."chair_id" = 1', 'SQLite'),
      Prosopite.fingerprint('SELECT "legs".* FROM "legs" WHERE "legs"."chair_id" = 2', 'SQLite')
    )
  end

  def test_double_quoted_identifiers_are_kept_outside_mysql
    refute_equal(
      Prosopite.fingerprint('SELECT "users".* FROM "users" WHERE "users"."id" = ?', 'SQLite'),
      Prosopite.fingerprint('SELECT "orgs".* FROM "orgs" WHERE "orgs"."id" = ?', 'SQLite')
    )
  end

  def test_oracle_bind_placeholders
    assert_equal(
      Prosopite.fingerprint('SELECT 1 AS one FROM "CCBS" WHERE "CCBS"."NAME" = :a1 FETCH FIRST :a2 ROWS ONLY', 'OracleEnhanced'),
      Prosopite.fingerprint('SELECT 1 AS one FROM "CCBS" WHERE "CCBS"."NAME" = :a1 FETCH FIRST :a2 ROWS ONLY', 'OracleEnhanced')
    )
  end

  def test_mysql_adapters_use_mysql_fingerprint
    q = "SELECT `legs`.* FROM `legs` WHERE `legs`.`chair_id` = 1"

    assert_equal(Prosopite.mysql_fingerprint(q), Prosopite.fingerprint(q, 'Mysql2'))
    assert_equal(Prosopite.mysql_fingerprint(q), Prosopite.fingerprint(q, 'Trilogy'))
  end

  def test_postgres_adapters_use_pg_query
    q = 'SELECT "legs".* FROM "legs" WHERE "legs"."chair_id" = $1 LIMIT $2'

    assert_equal(PgQuery.fingerprint(q), Prosopite.fingerprint(q, 'PostgreSQL'))
    assert_equal(PgQuery.fingerprint(q), Prosopite.fingerprint(q, 'PostGIS'))
  end

  def test_defaults_to_the_primary_connection_adapter
    q = 'SELECT "legs".* FROM "legs" WHERE "legs"."chair_id" = ?'

    assert_equal(Prosopite.fingerprint(q, 'SQLite'), Prosopite.fingerprint(q))
  end
end
