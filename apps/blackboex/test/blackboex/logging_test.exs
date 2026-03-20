defmodule Blackboex.LoggingTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias Blackboex.Logging

  describe "with_api_context/2" do
    test "sets api_id in Logger metadata during execution" do
      api_id = Ecto.UUID.generate()

      Logging.with_api_context(api_id, fn ->
        assert Logger.metadata()[:api_id] == api_id
      end)
    end

    test "returns the result of the function" do
      assert Logging.with_api_context("test", fn -> :result end) == :result
    end

    test "restores previous metadata after execution" do
      Logger.metadata(api_id: "old")

      Logging.with_api_context("new", fn ->
        assert Logger.metadata()[:api_id] == "new"
      end)

      assert Logger.metadata()[:api_id] == "old"
    end

    test "restores metadata even when callback raises" do
      Logger.metadata(api_id: "preserved")

      assert_raise RuntimeError, fn ->
        Logging.with_api_context("temporary", fn ->
          raise "boom"
        end)
      end

      assert Logger.metadata()[:api_id] == "preserved"
    end

    test "nested contexts restore correctly" do
      Logging.with_api_context("outer", fn ->
        assert Logger.metadata()[:api_id] == "outer"

        Logging.with_api_context("inner", fn ->
          assert Logger.metadata()[:api_id] == "inner"
        end)

        assert Logger.metadata()[:api_id] == "outer"
      end)
    end

    test "does not pollute unrelated metadata" do
      Logger.metadata(custom_key: "value")

      Logging.with_api_context("api", fn ->
        assert Logger.metadata()[:custom_key] == "value"
      end)

      assert Logger.metadata()[:custom_key] == "value"
    end
  end

  describe "with_user_context/2" do
    test "sets user_id in Logger metadata during execution" do
      user_id = 42

      Logging.with_user_context(user_id, fn ->
        assert Logger.metadata()[:user_id] == user_id
      end)
    end

    test "returns the result of the function" do
      assert Logging.with_user_context(1, fn -> :ok end) == :ok
    end

    test "restores previous metadata after execution" do
      Logger.metadata(user_id: 1)

      Logging.with_user_context(2, fn ->
        assert Logger.metadata()[:user_id] == 2
      end)

      assert Logger.metadata()[:user_id] == 1
    end

    test "restores metadata even when callback raises" do
      Logger.metadata(user_id: 99)

      assert_raise RuntimeError, fn ->
        Logging.with_user_context(100, fn ->
          raise "boom"
        end)
      end

      assert Logger.metadata()[:user_id] == 99
    end
  end
end
