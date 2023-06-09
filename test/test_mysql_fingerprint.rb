require 'test_helper'

class TestMysqlFingerprint < Minitest::Test
  # Many thanks to https://github.com/genkami/fluent-plugin-query-fingerprint/
  def test_no_side_effect
    q = "SELECT * FROM hoge WHERE fuga = 1"
    Prosopite.mysql_fingerprint(q)
    assert_equal(q, "SELECT * FROM hoge WHERE fuga = 1")
  end

  def test_mysqldump
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT /*!40001 SQL_NO_CACHE */ * FROM `the_table`"),
      "mysqldump"
    )
  end

  def test_percona_toolkit
    assert_equal(
      Prosopite.mysql_fingerprint("REPLACE /*foo.bar:3/3*/ INTO checksum.checksum"),
      "percona-toolkit"
    )
  end

  def test_admin_command
    assert_equal(
      Prosopite.mysql_fingerprint("administrator command: Ping"),
      "administrator command: ping"
    )
  end

  def test_use
    assert_equal(
      Prosopite.mysql_fingerprint("USE `the_table`"),
      "use ?"
    )
  end

  def test_double_quoted_strings
    assert_equal(
      Prosopite.mysql_fingerprint(%{SELECT "foo_bar"}),
      "select ?"
    )
  end

  def test_escaped_double_quotes
    assert_equal(
      Prosopite.mysql_fingerprint(%{SELECT "foo_\\"bar\\""}),
      "select ?"
    )
  end

  def test_single_quoted_strings
    assert_equal(
      Prosopite.mysql_fingerprint(%{SELECT 'foo_bar'}),
      "select ?"
    )
  end

  def test_escaped_single_quotes
    assert_equal(
      Prosopite.mysql_fingerprint(%{SELECT 'foo_\\'bar\\''}),
      "select ?"
    )
  end

  def test_true
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table WHERE a_value = TRUE"),
      "select * from a_table where a_value = ?"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table WHERE a_value = true"),
      "select * from a_table where a_value = ?"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table WHERE true_column = true"),
      "select * from a_table where true_column = ?"
    )
  end

  def test_false
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table WHERE a_value = FALSE"),
      "select * from a_table where a_value = ?"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table WHERE a_value = false"),
      "select * from a_table where a_value = ?"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table WHERE false_column = false"),
      "select * from a_table where false_column = ?"
    )
  end

  def test_numbers
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table WHERE a_value = 123"),
      "select * from a_table where a_value = ?"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table WHERE a_value = +123"),
      "select * from a_table where a_value = ?"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table WHERE a_value = -123"),
      "select * from a_table where a_value = ?"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table WHERE a_value = 0x12ab"),
      "select * from a_table where a_value = ?"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table WHERE a_value = 0b0011"),
      "select * from a_table where a_value = ?"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table WHERE a_value = 12.3"),
      "select * from a_table where a_value = ?"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table WHERE a_value = .1"),
      "select * from a_table where a_value = ?"
    )
  end

  def test_numbers_in_identifiers
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table0 WHERE a_value1 = 123"),
      "select * from a_table? where a_value? = ?"
    )
  end

  def test_leading_trailing_whitespaces
    assert_equal(
      Prosopite.mysql_fingerprint("  \t\nSELECT * FROM a_table WHERE a_value = 123   \t\n"),
      "select * from a_table where a_value = ?"
    )
  end

  def test_whitespaces
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT *\tFROM a_table  \n  \fWHERE\r\na_value = 123"),
      "select * from a_table where a_value = ?"
    )
  end

  def test_nulls
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table WHERE a_value IS NULL"),
      "select * from a_table where a_value is ?"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table WHERE a_value IS null"),
      "select * from a_table where a_value is ?"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table WHERE nullable IS null"),
      "select * from a_table where nullable is ?"
    )
  end

  def test_in_operator
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table WHERE a_value IN (1)"),
      "select * from a_table where a_value in(?+)"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table WHERE a_value IN (1, 2, 3)"),
      "select * from a_table where a_value in(?+)"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT SIN(3.14)"),
      "select sin(?)"
    )
  end

  def test_values_function
    assert_equal(
      Prosopite.mysql_fingerprint("INSERT INTO a_table (foo, bar) VALUES (1, 'aaa')"),
      "insert into a_table (foo, bar) values(?+)"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("INSERT INTO a_table (foo, bar) VALUES (1, 'aaa'), (2, 'bbb')"),
      "insert into a_table (foo, bar) values(?+)"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("INSERT INTO a_table (foo, bar) VALUE (1, 'aaa'), (2, 'bbb')"),
      "insert into a_table (foo, bar) value(?+)"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT my_function_values(1, 2)"),
      "select my_function_values(?, ?)"
    )
  end

  def test_unioning_similar_queries
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM foo WHERE bar = 1 "\
                     "UNION SELECT * FROM foo WHERE bar = 2"),
                     "select * from foo where bar = ? /*repeat union*/"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM foo WHERE bar = 1 "\
                     "UNION SELECT * FROM foo WHERE bar = 2 "\
                     "UNION SELECT * FROM foo WHERE bar = 3"),
                     "select * from foo where bar = ? /*repeat union*/"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM foo WHERE bar = 1 "\
                     "UNION ALL SELECT * FROM foo WHERE bar = 2"),
                     "select * from foo where bar = ? /*repeat union all*/"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM foo WHERE bar = 1 "\
                     "UNION SELECT * FROM foo WHERE bar = 2 "\
                     "UNION ALL SELECT * FROM foo WHERE bar = 3"),
                     "select * from foo where bar = ? /*repeat union all*/"
    )

    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM hoge INNER JOIN "\
                     "(SELECT * FROM foo WHERE bar = 1 "\
                     "UNION SELECT * FROM foo WHERE bar = 2) "\
                     "ON hoge.id = foo.hoge_id"),
                     "select * from hoge inner join "\
                     "(select * from foo where bar = ? /*repeat union*/) "\
                     "on hoge.id = foo.hoge_id"
    )

    assert_equal(
      Prosopite.mysql_fingerprint("SELECT MY_FUNC_SELECT (1) "\
                     "UNION SELECT (1)"),
    "select my_func_select (?) union select (?)"
    )
  end

  def test_limit_clauses
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table LIMIT 10"),
      "select * from a_table limit ?"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table LIMIT 5, 10"),
      "select * from a_table limit ?"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table LIMIT 5,10"),
      "select * from a_table limit ?"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM a_table LIMIT 10 OFFSET 5"),
      "select * from a_table limit ?"
    )
  end

  def test_order_by_clauses
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * from a_table ORDER BY foo"),
      "select * from a_table order by foo"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * from a_table ORDER BY foo ASC"),
      "select * from a_table order by foo"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * from a_table ORDER BY foo DESC"),
      "select * from a_table order by foo desc"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * from a_table ORDER BY foo ASC, bar ASC"),
      "select * from a_table order by foo, bar"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * from a_table ORDER BY foo ASC, bar DESC, baz ASC"),
      "select * from a_table order by foo, bar desc, baz"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * from a_table ORDER BY foo ASC, bar DESC, baz, quux ASC"),
      "select * from a_table order by foo, bar desc, baz, quux"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * from a_table ORDER BY FIELD(id, 1, 2, 3, 4)"),
      "select * from a_table order by field(id, ?+)"
    )
  end

  def test_call_procedures
    assert_equal(
      Prosopite.mysql_fingerprint("CALL func(@foo, @bar)"),
      "call func"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("  CALL func(@foo, @bar)"),
      "call func"
    )
  end

  def test_multi_line_comments
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT hoge /* comment */ FROM fuga"),
      "select hoge from fuga"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT hoge /* this is \n"\
                     "a multi-line comment */ FROM fuga"),
                     "select hoge from fuga"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT hoge /* comment */ FROM /* another comment */ fuga"),
      "select hoge from fuga"
    )
  end

  def test_multi_line_comments_followed_by_exclamation_marks
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT /*! STRAIGHT_JOIN */ hoge from fuga, foo"),
      "select /*! straight_join */ hoge from fuga, foo"
    )
  end

  def test_one_line_comments
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM hoge -- comment"),
      "select * from hoge"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM hoge -- comment\n"\
                     "WHERE fuga = 1"),
                     "select * from hoge where fuga = ?"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM hoge # comment"),
      "select * from hoge"
    )
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM hoge # comment\n"\
                     "WHERE fuga = 1"),
                     "select * from hoge where fuga = ?"
    )
  end

  def test_unicode
    assert_equal(
      Prosopite.mysql_fingerprint("SELECT * FROM hoge where value = 'ほげふが'"),
      "select * from hoge where value = ?"
    )
  end
end
