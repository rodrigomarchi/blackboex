defmodule Blackboex.Playgrounds.HttpTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.Playgrounds.Http

  describe "validate_url/1 (via get/1)" do
    test "blocks private IP 10.x.x.x" do
      assert {:error, "requests to private/internal networks are blocked"} =
               Http.get("http://10.0.0.1/secret")
    end

    test "blocks private IP 172.16.x.x" do
      assert {:error, "requests to private/internal networks are blocked"} =
               Http.get("http://172.16.0.1/secret")
    end

    test "blocks private IP 192.168.x.x" do
      assert {:error, "requests to private/internal networks are blocked"} =
               Http.get("http://192.168.1.1/secret")
    end

    test "blocks link-local 169.254.x.x" do
      assert {:error, "requests to private/internal networks are blocked"} =
               Http.get("http://169.254.169.254/latest/meta-data")
    end

    test "blocks loopback 127.x.x.x when not base host" do
      # Override config so base host is NOT localhost
      original = Application.get_env(:blackboex, Blackboex.Playgrounds.Api)
      Application.put_env(:blackboex, Blackboex.Playgrounds.Api, base_url: "http://example.com")

      assert {:error, "requests to private/internal networks are blocked"} =
               Http.get("http://127.0.0.1/secret")

      if original do
        Application.put_env(:blackboex, Blackboex.Playgrounds.Api, original)
      else
        Application.delete_env(:blackboex, Blackboex.Playgrounds.Api)
      end
    end

    test "allows localhost when it matches configured base host" do
      # Default config has base_url: "http://localhost:4000"
      # If dev server is running, we get a response; if not, a connection error.
      # Either way, it should NOT be an SSRF blocking error.
      result = Http.get("http://localhost:4000/nonexistent")

      case result do
        {:ok, _resp} -> :ok
        {:error, msg} -> refute msg =~ "private/internal networks"
      end
    end

    test "blocks ftp scheme" do
      assert {:error, "only http and https URLs are allowed"} =
               Http.get("ftp://example.com/file")
    end

    test "blocks file scheme" do
      assert {:error, "only http and https URLs are allowed"} =
               Http.get("file:///etc/passwd")
    end

    test "blocks missing scheme" do
      assert {:error, "only http and https URLs are allowed"} =
               Http.get("example.com/path")
    end
  end

  describe "call count limit" do
    test "enforces max 5 HTTP calls per execution" do
      # Use private IPs — blocked instantly by SSRF check, but still count
      # since check_call_count runs before validate_url
      # Actually, call count is checked first, then URL validation.
      # Private IPs fail at validate_url (after count check passes), so count is NOT incremented.
      # We need URLs that pass validation but fail fast at connection.
      # Use localhost with a port that's unlikely to be listening.
      for _ <- 1..5 do
        result = Http.get("http://localhost:19999/test")

        case result do
          {:error, msg} -> refute msg =~ "call limit exceeded"
          {:ok, _} -> :ok
        end
      end

      # 6th call should be blocked by rate limit
      assert {:error, "HTTP call limit exceeded: max 5 calls per execution"} =
               Http.get("http://localhost:19999/test")
    end
  end

  describe "post/3" do
    test "passes body and headers" do
      # Use private IP to fail fast at SSRF validation
      result =
        Http.post("http://10.0.0.1/test", ~s({"key":"val"}), [
          {"content-type", "application/json"}
        ])

      assert {:error, "requests to private/internal networks are blocked"} = result
    end
  end

  describe "put/3" do
    test "accepts body and headers" do
      result =
        Http.put("http://10.0.0.1/test", ~s({"key":"val"}), [{"content-type", "application/json"}])

      assert {:error, "requests to private/internal networks are blocked"} = result
    end
  end

  describe "patch/3" do
    test "accepts body and headers" do
      result =
        Http.patch("http://10.0.0.1/test", ~s({"key":"val"}), [
          {"content-type", "application/json"}
        ])

      assert {:error, "requests to private/internal networks are blocked"} = result
    end
  end

  describe "delete/2" do
    test "accepts url and headers" do
      result = Http.delete("http://10.0.0.1/test", [{"x-custom", "val"}])
      assert {:error, "requests to private/internal networks are blocked"} = result
    end
  end
end
