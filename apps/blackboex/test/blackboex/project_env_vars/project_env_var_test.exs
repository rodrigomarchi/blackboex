defmodule Blackboex.ProjectEnvVars.ProjectEnvVarTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.ProjectEnvVars.ProjectEnvVar

  setup do
    {_user, org} = user_and_org_fixture()
    project = Blackboex.Projects.get_default_project(org.id)
    %{org: org, project: project}
  end

  describe "changeset/2 happy path" do
    test "valid with name, value, kind=env", %{org: org, project: project} do
      cs =
        ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
          name: "VALID_KEY",
          value: "secret",
          kind: "env",
          organization_id: org.id,
          project_id: project.id
        })

      assert cs.valid?
      # Cloak encrypts at Repo.insert time — at changeset stage the change
      # is the plaintext value that will be encrypted on persist.
      assert get_change(cs, :encrypted_value) == "secret"
    end

    test "valid with kind=llm_anthropic", %{org: org, project: project} do
      cs =
        ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
          name: "ANTHROPIC_API_KEY",
          value: "sk-ant-abc-xxxxxxxxxxxxxxxxxxxx",
          kind: "llm_anthropic",
          organization_id: org.id,
          project_id: project.id
        })

      assert cs.valid?
    end

    test "rejects Anthropic key with embedded NUL", %{org: org, project: project} do
      cs =
        ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
          name: "ANTHROPIC_API_KEY",
          value: "sk-ant-ok-xxxxxxxxxxxxxxxxxxxx\0evil",
          kind: "llm_anthropic",
          organization_id: org.id,
          project_id: project.id
        })

      refute cs.valid?
      assert %{value: _} = errors_on(cs)
    end

    test "rejects Anthropic key with embedded CR/LF", %{org: org, project: project} do
      for ctrl <- ["\r", "\n"] do
        cs =
          ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
            name: "ANTHROPIC_API_KEY",
            value: "sk-ant-ok-xxxxxxxxxxxxxxxxxxxx" <> ctrl,
            kind: "llm_anthropic",
            organization_id: org.id,
            project_id: project.id
          })

        refute cs.valid?
      end
    end

    test "kind defaults to env when not provided", %{org: org, project: project} do
      {:ok, env_var} =
        Repo.insert(
          ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
            name: "NO_KIND",
            value: "v",
            organization_id: org.id,
            project_id: project.id
          })
        )

      assert env_var.kind == "env"
    end
  end

  describe "at-rest encryption (Cloak.Vault)" do
    test "plaintext round-trips through insert+reload", %{org: org, project: project} do
      for text <- ["hello", "hello 👋 apple", "sk-ant-" <> String.duplicate("x", 40)] do
        {:ok, inserted} =
          Repo.insert(
            ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
              name: "ROUNDTRIP_#{System.unique_integer([:positive])}",
              value: text,
              organization_id: org.id,
              project_id: project.id
            })
          )

        reloaded = Repo.get!(ProjectEnvVar, inserted.id)
        assert reloaded.encrypted_value == text
      end
    end

    test "column bytes at rest are not equal to the plaintext", %{
      org: org,
      project: project
    } do
      plaintext = "sk-ant-plaintext-leak-canary"

      {:ok, %{id: id}} =
        Repo.insert(
          ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
            name: "CANARY",
            value: plaintext,
            organization_id: org.id,
            project_id: project.id
          })
        )

      # Read the raw column bypassing Cloak decoding.
      %{rows: [[raw]]} =
        Repo.query!(
          "SELECT encrypted_value FROM project_env_vars WHERE id = $1",
          [Ecto.UUID.dump!(id)]
        )

      refute raw == plaintext
      refute String.contains?(raw, plaintext)
    end
  end

  describe "required field validations" do
    test "rejects missing name", %{org: org, project: project} do
      cs =
        ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
          value: "v",
          organization_id: org.id,
          project_id: project.id
        })

      refute cs.valid?
      assert %{name: ["can't be blank"]} = errors_on(cs)
    end

    test "rejects missing value (encrypted_value required)", %{org: org, project: project} do
      cs =
        ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
          name: "NAME",
          organization_id: org.id,
          project_id: project.id
        })

      refute cs.valid?
      assert %{encrypted_value: _} = errors_on(cs)
    end

    test "rejects missing project_id", %{org: org} do
      cs =
        ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
          name: "NAME",
          value: "v",
          organization_id: org.id
        })

      refute cs.valid?
      assert %{project_id: ["can't be blank"]} = errors_on(cs)
    end

    test "rejects missing organization_id", %{project: project} do
      cs =
        ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
          name: "NAME",
          value: "v",
          project_id: project.id
        })

      refute cs.valid?
      assert %{organization_id: ["can't be blank"]} = errors_on(cs)
    end
  end

  describe "name format validation" do
    test "accepts letter/underscore-prefixed alphanumeric + underscore names",
         %{org: org, project: project} do
      for name <- ~w(VALID valid valid_name_123 X123 a b _underscore_first) do
        cs =
          ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
            name: name,
            value: "v",
            organization_id: org.id,
            project_id: project.id
          })

        assert cs.valid?, "expected '#{name}' to be valid; errors: #{inspect(errors_on(cs))}"
      end
    end

    test "rejects name starting with a digit (POSIX env-var rule)",
         %{org: org, project: project} do
      cs =
        ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
          name: "123_starts_with_number",
          value: "v",
          organization_id: org.id,
          project_id: project.id
        })

      refute cs.valid?
      assert %{name: _} = errors_on(cs)
    end

    test "rejects names with dashes / spaces / dots", %{org: org, project: project} do
      for name <- ~w(bad-name bad.name), extra <- ["", " "] do
        bad = name <> extra

        cs =
          ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
            name: bad,
            value: "v",
            organization_id: org.id,
            project_id: project.id
          })

        refute cs.valid?, "expected '#{bad}' to be invalid"
        assert %{name: _} = errors_on(cs)
      end
    end

    test "rejects name with whitespace", %{org: org, project: project} do
      cs =
        ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
          name: "name with space",
          value: "v",
          organization_id: org.id,
          project_id: project.id
        })

      refute cs.valid?
      assert %{name: _} = errors_on(cs)
    end

    test "rejects names longer than 255 chars", %{org: org, project: project} do
      cs =
        ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
          name: String.duplicate("A", 256),
          value: "v",
          organization_id: org.id,
          project_id: project.id
        })

      refute cs.valid?
      assert %{name: _} = errors_on(cs)
    end
  end

  describe "kind validation" do
    test "accepts allowed kinds", %{org: org, project: project} do
      cases = [
        {"env", "v"},
        {"llm_anthropic", "sk-ant-test-xxxxxxxxxxxxxxxxxxxx"}
      ]

      for {kind, value} <- cases do
        cs =
          ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
            name: "NAME",
            value: value,
            kind: kind,
            organization_id: org.id,
            project_id: project.id
          })

        assert cs.valid?, "expected kind=#{kind} valid"
      end
    end

    test "rejects invalid kind", %{org: org, project: project} do
      cs =
        ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
          name: "NAME",
          value: "v",
          kind: "invalid",
          organization_id: org.id,
          project_id: project.id
        })

      refute cs.valid?
      assert %{kind: _} = errors_on(cs)
    end

    test "DB check constraint rejects unsupported kind via raw insert", %{
      org: org,
      project: project
    } do
      # Bypass the changeset by inserting raw via Repo.query
      assert {:error, _} =
               Blackboex.Repo.query("""
               INSERT INTO project_env_vars
                 (id, name, encrypted_value, kind, organization_id, project_id, inserted_at, updated_at)
               VALUES
                 ('#{Ecto.UUID.generate()}', 'X', 'dg==', 'openai', '#{org.id}', '#{project.id}', NOW(), NOW())
               """)
    end
  end

  describe "value validation" do
    test "rejects empty value", %{org: org, project: project} do
      cs =
        ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
          name: "NAME",
          value: "",
          organization_id: org.id,
          project_id: project.id
        })

      refute cs.valid?
      assert %{value: _} = errors_on(cs)
    end

    test "rejects values containing newlines/CR/NUL (header-injection guard)",
         %{org: org, project: project} do
      for ctrl <- ["\n", "\r", "\0"] do
        value = "line1" <> ctrl <> "line2"

        cs =
          ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
            name: "MULTILINE",
            value: value,
            organization_id: org.id,
            project_id: project.id
          })

        refute cs.valid?, "expected value with control char to be invalid"
        assert %{value: _} = errors_on(cs)
      end
    end

    test "accepts tab characters in generic env values",
         %{org: org, project: project} do
      value = "col1\tcol2"

      {:ok, env_var} =
        Repo.insert(
          ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
            name: "WITH_TAB",
            value: value,
            organization_id: org.id,
            project_id: project.id
          })
        )

      assert env_var.encrypted_value == value
    end

    test "rejects kind=env value larger than 8KiB", %{org: org, project: project} do
      cs =
        ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
          name: "BIG",
          value: String.duplicate("x", 8_193),
          organization_id: org.id,
          project_id: project.id
        })

      refute cs.valid?
      assert %{value: _} = errors_on(cs)
    end

    test "accepts kind=env value at 8KiB boundary", %{org: org, project: project} do
      cs =
        ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
          name: "BOUNDARY",
          value: String.duplicate("x", 8_192),
          organization_id: org.id,
          project_id: project.id
        })

      assert cs.valid?
    end

    test "rejects kind=llm_anthropic value larger than 16KiB", %{org: org, project: project} do
      # Valid anthropic prefix followed by lots of A's (to pass the regex) but over 16KiB
      over_16k = "sk-ant-xxxxxxxxxxxxxxxxxxxx" <> String.duplicate("A", 16_385)

      cs =
        ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
          name: "ANTHROPIC_API_KEY",
          kind: "llm_anthropic",
          value: over_16k,
          organization_id: org.id,
          project_id: project.id
        })

      refute cs.valid?
      assert %{value: _} = errors_on(cs)
    end
  end

  describe "unique constraints" do
    test "rejects duplicate (project_id, kind, name)", %{org: org, project: project} do
      attrs = %{
        name: "DUP_KEY",
        value: "v",
        kind: "env",
        organization_id: org.id,
        project_id: project.id
      }

      {:ok, _} = Repo.insert(ProjectEnvVar.changeset(%ProjectEnvVar{}, attrs))

      assert {:error, cs} = Repo.insert(ProjectEnvVar.changeset(%ProjectEnvVar{}, attrs))
      refute cs.valid?
    end

    test "allows same name in different projects", %{org: org} do
      {_user2, org2} = user_and_org_fixture()
      project2 = Blackboex.Projects.get_default_project(org2.id)

      assert {:ok, _} =
               Repo.insert(
                 ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
                   name: "SHARED",
                   value: "a",
                   organization_id: org.id,
                   project_id: Blackboex.Projects.get_default_project(org.id).id
                 })
               )

      assert {:ok, _} =
               Repo.insert(
                 ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
                   name: "SHARED",
                   value: "b",
                   organization_id: org2.id,
                   project_id: project2.id
                 })
               )
    end

    test "allows same name with different kinds in the same project", %{
      org: org,
      project: project
    } do
      assert {:ok, _} =
               Repo.insert(
                 ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
                   name: "X",
                   value: "v1",
                   kind: "env",
                   organization_id: org.id,
                   project_id: project.id
                 })
               )

      assert {:ok, _} =
               Repo.insert(
                 ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
                   name: "X",
                   value: "sk-ant-v2-xxxxxxxxxxxxxxxxxxxxx",
                   kind: "llm_anthropic",
                   organization_id: org.id,
                   project_id: project.id
                 })
               )
    end

    test "rejects a second llm_anthropic row in the same project", %{
      org: org,
      project: project
    } do
      assert {:ok, _} =
               Repo.insert(
                 ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
                   name: "ANTHROPIC_API_KEY",
                   value: "sk-ant-a-xxxxxxxxxxxxxxxxxxxxxx",
                   kind: "llm_anthropic",
                   organization_id: org.id,
                   project_id: project.id
                 })
               )

      assert {:error, _cs} =
               Repo.insert(
                 ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
                   name: "SECOND_KEY",
                   value: "sk-ant-b-xxxxxxxxxxxxxxxxxxxxxx",
                   kind: "llm_anthropic",
                   organization_id: org.id,
                   project_id: project.id
                 })
               )
    end

    test "allows llm_anthropic rows in different projects", %{org: org, project: project} do
      {_user2, org2} = user_and_org_fixture()
      project2 = Blackboex.Projects.get_default_project(org2.id)

      assert {:ok, _} =
               Repo.insert(
                 ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
                   name: "ANTHROPIC_API_KEY",
                   value: "sk-ant-a-xxxxxxxxxxxxxxxxxxxxxx",
                   kind: "llm_anthropic",
                   organization_id: org.id,
                   project_id: project.id
                 })
               )

      assert {:ok, _} =
               Repo.insert(
                 ProjectEnvVar.changeset(%ProjectEnvVar{}, %{
                   name: "ANTHROPIC_API_KEY",
                   value: "sk-ant-b-xxxxxxxxxxxxxxxxxxxxxx",
                   kind: "llm_anthropic",
                   organization_id: org2.id,
                   project_id: project2.id
                 })
               )
    end
  end

  describe "fixtures" do
    test "project_env_var_fixture persists a kind=env row" do
      env_var = project_env_var_fixture()
      assert env_var.id
      assert env_var.kind == "env"
      assert String.starts_with?(env_var.name, "ENV_VAR_")
      assert String.starts_with?(env_var.encrypted_value, "value-")
    end

    test "llm_anthropic_key_fixture persists the Anthropic row" do
      env_var = llm_anthropic_key_fixture()
      assert env_var.kind == "llm_anthropic"
      assert env_var.name == "ANTHROPIC_API_KEY"

      assert env_var.encrypted_value == "sk-ant-test-xxxxxxxxxxxxxxxxxxxx"
    end
  end
end
