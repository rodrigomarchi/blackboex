defmodule Blackboex.Repo.IndexCoverageTest do
  use Blackboex.DataCase, async: false

  @moduletag :unit

  test "all foreign keys have a supporting leading index" do
    result =
      Repo.query!("""
      WITH fk AS (
        SELECT conrelid, conname, conkey
        FROM pg_constraint
        WHERE contype = 'f'
      ),
      idx AS (
        SELECT indrelid, indkey
        FROM pg_index
        WHERE indisvalid
      )
      SELECT c.relname, fk.conname, a.attname
      FROM fk
      JOIN pg_class c ON c.oid = fk.conrelid
      JOIN LATERAL unnest(fk.conkey) WITH ORDINALITY AS k(attnum, ord) ON true
      JOIN pg_attribute a ON a.attrelid = fk.conrelid AND a.attnum = k.attnum
      WHERE NOT EXISTS (
        SELECT 1
        FROM idx
        WHERE idx.indrelid = fk.conrelid
          AND (idx.indkey::smallint[])[0:array_length(fk.conkey, 1)-1] = fk.conkey
      )
      ORDER BY c.relname, fk.conname
      """)

    assert result.rows == []
  end
end
