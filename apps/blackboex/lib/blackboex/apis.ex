defmodule Blackboex.Apis do
  @moduledoc """
  The Apis context. Manages API endpoints created by users.

  Each API has a virtual filesystem of ApiFiles with revision history.
  ApiVersions represent compiled snapshots referencing specific file revisions.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Agent.KickoffWorker
  alias Blackboex.Apis.Api
  alias Blackboex.Apis.ApiFile
  alias Blackboex.Apis.ApiFileRevision
  alias Blackboex.Apis.ApiVersion
  alias Blackboex.Apis.DiffEngine
  alias Blackboex.Apis.Registry
  alias Blackboex.Apis.VirtualFile
  alias Blackboex.Audit
  alias Blackboex.Billing.Enforcement
  alias Blackboex.CodeGen.Compiler
  alias Blackboex.CodeGen.GenerationResult
  alias Blackboex.Organizations
  alias Blackboex.Organizations.Organization
  alias Blackboex.Repo

  require Logger

  # ── API CRUD ─────────────────────────────────────────────────

  @spec create_api(map()) ::
          {:ok, Api.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :limit_exceeded, map()}
  def create_api(attrs) do
    org_id = attrs[:organization_id] || attrs["organization_id"]

    if org_id do
      create_api_with_lock(attrs, org_id)
    else
      %Api{}
      |> Api.changeset(attrs)
      |> Repo.insert()
    end
  end

  defp create_api_with_lock(attrs, org_id) do
    Repo.transaction(fn ->
      acquire_api_creation_lock(org_id)
      check_and_insert_api(attrs, org_id)
    end)
    |> case do
      {:ok, api} -> {:ok, api}
      {:error, {:limit_exceeded, details}} -> {:error, :limit_exceeded, details}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  rescue
    e in Ecto.InvalidChangesetError -> {:error, e.changeset}
  end

  defp acquire_api_creation_lock(org_id) do
    lock_key = :erlang.phash2({"create_api", org_id})
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])
  end

  defp check_and_insert_api(attrs, org_id) do
    case Organizations.get_organization(org_id) do
      nil ->
        insert_api!(attrs)

      org ->
        case Enforcement.check_limit(org, :create_api) do
          {:ok, _remaining} -> insert_api!(attrs)
          {:error, :limit_exceeded, details} -> Repo.rollback({:limit_exceeded, details})
        end
    end
  end

  defp insert_api!(attrs) do
    %Api{}
    |> Api.changeset(attrs)
    |> Repo.insert!()
  end

  @spec list_apis(Ecto.UUID.t()) :: [Api.t()]
  def list_apis(organization_id) do
    Api
    |> where([a], a.organization_id == ^organization_id)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  @spec get_api(Ecto.UUID.t(), Ecto.UUID.t()) :: Api.t() | nil
  def get_api(organization_id, api_id) do
    Api
    |> where([a], a.organization_id == ^organization_id and a.id == ^api_id)
    |> Repo.one()
  end

  @spec update_api(Api.t(), map()) :: {:ok, Api.t()} | {:error, Ecto.Changeset.t()}
  def update_api(%Api{} = api, attrs) do
    api
    |> Api.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_api(Api.t()) :: {:ok, Api.t()} | {:error, Ecto.Changeset.t()}
  def delete_api(%Api{} = api) do
    if api.status == "published" do
      Registry.unregister(api.id)

      module_name = Compiler.module_name_for(api)
      Compiler.unload(module_name)
    end

    Repo.delete(api)
  end

  # ── File System ──────────────────────────────────────────────

  @spec list_files(Ecto.UUID.t()) :: [ApiFile.t()]
  def list_files(api_id) do
    ApiFile
    |> where([f], f.api_id == ^api_id)
    |> order_by([f], asc: f.path)
    |> Repo.all()
  end

  @spec list_files_with_virtual(Api.t()) :: [map()]
  def list_files_with_virtual(%Api{} = api) do
    db_files = list_files(api.id) |> Enum.map(&Map.put(&1, :read_only, false))
    virtual_files = VirtualFile.build(api)
    db_files ++ virtual_files
  end

  @spec list_source_files(Ecto.UUID.t()) :: [ApiFile.t()]
  def list_source_files(api_id) do
    ApiFile
    |> where([f], f.api_id == ^api_id and f.file_type == "source")
    |> order_by([f], asc: f.path)
    |> Repo.all()
  end

  @spec list_test_files(Ecto.UUID.t()) :: [ApiFile.t()]
  def list_test_files(api_id) do
    ApiFile
    |> where([f], f.api_id == ^api_id and f.file_type == "test")
    |> order_by([f], asc: f.path)
    |> Repo.all()
  end

  @spec get_file(Ecto.UUID.t(), String.t()) :: ApiFile.t() | nil
  def get_file(api_id, path) do
    ApiFile
    |> where([f], f.api_id == ^api_id and f.path == ^path)
    |> Repo.one()
  end

  @spec get_file!(Ecto.UUID.t()) :: ApiFile.t()
  def get_file!(file_id) do
    Repo.get!(ApiFile, file_id)
  end

  @spec create_file(Api.t(), map()) :: {:ok, ApiFile.t()} | {:error, Ecto.Changeset.t()}
  def create_file(%Api{} = api, attrs) do
    Repo.transaction(fn ->
      file =
        %ApiFile{}
        |> ApiFile.changeset(Map.put(attrs, :api_id, api.id))
        |> Repo.insert!()

      create_initial_revision(
        file,
        attrs[:content],
        attrs[:source] || "generation",
        attrs[:created_by_id]
      )

      file
    end)
  end

  @spec update_file_content(ApiFile.t(), String.t(), map()) ::
          {:ok, ApiFile.t()} | {:error, Ecto.Changeset.t()}
  def update_file_content(%ApiFile{} = file, new_content, opts \\ %{}) do
    old_content = file.content

    Repo.transaction(fn ->
      updated_file =
        file
        |> Ecto.Changeset.change(content: new_content)
        |> Repo.update!()

      diff = if old_content, do: DiffEngine.compute_diff(old_content, new_content), else: nil

      create_revision(
        file,
        new_content,
        diff && DiffEngine.format_diff_summary(diff),
        opts[:source] || "manual_edit",
        opts[:message],
        opts[:created_by_id]
      )

      updated_file
    end)
  end

  @spec delete_file(ApiFile.t()) :: {:ok, ApiFile.t()} | {:error, Ecto.Changeset.t()}
  def delete_file(%ApiFile{} = file) do
    Repo.delete(file)
  end

  @spec list_file_revisions(Ecto.UUID.t()) :: [ApiFileRevision.t()]
  def list_file_revisions(file_id) do
    ApiFileRevision
    |> where([r], r.api_file_id == ^file_id)
    |> order_by([r], desc: r.revision_number)
    |> Repo.all()
  end

  defp create_initial_revision(file, content, source, created_by_id) do
    %ApiFileRevision{}
    |> ApiFileRevision.changeset(%{
      api_file_id: file.id,
      content: content || "",
      source: source,
      message: "Initial file creation",
      revision_number: 1,
      created_by_id: created_by_id
    })
    |> Repo.insert!()
  end

  defp create_revision(file, content, diff, source, message, created_by_id) do
    next_rev = next_revision_number(file.id)

    %ApiFileRevision{}
    |> ApiFileRevision.changeset(%{
      api_file_id: file.id,
      content: content,
      diff: diff,
      source: source,
      message: message,
      revision_number: next_rev,
      created_by_id: created_by_id
    })
    |> Repo.insert!()
  end

  defp next_revision_number(file_id) do
    result =
      ApiFileRevision
      |> where([r], r.api_file_id == ^file_id)
      |> select([r], max(r.revision_number))
      |> Repo.one()

    (result || 0) + 1
  end

  @doc """
  Upserts files for an API from a list of `%{path, content, file_type}` maps.
  Creates new files or updates existing ones, creating revisions for each change.
  Returns the list of upserted ApiFile records.
  """
  @spec upsert_files(Api.t(), [map()], map()) :: {:ok, [ApiFile.t()]}
  def upsert_files(%Api{} = api, file_maps, opts \\ %{}) do
    Repo.transaction(fn ->
      Enum.map(file_maps, &upsert_single_file(api, &1, opts))
    end)
  end

  defp upsert_single_file(api, file_map, opts) do
    path = file_map[:path] || file_map["path"]
    content = file_map[:content] || file_map["content"]
    file_type = file_map[:file_type] || file_map["file_type"] || infer_file_type(path)
    source = opts[:source] || "generation"

    case get_file(api.id, path) do
      nil ->
        {:ok, file} =
          create_file(api, %{
            path: path,
            content: content,
            file_type: file_type,
            source: source,
            created_by_id: opts[:created_by_id]
          })

        file

      existing ->
        {:ok, file} =
          update_file_content(existing, content, %{
            source: source,
            message: opts[:message],
            created_by_id: opts[:created_by_id]
          })

        file
    end
  end

  defp infer_file_type(path) when is_binary(path) do
    cond do
      String.starts_with?(path, "/test") -> "test"
      String.starts_with?(path, "/src") -> "source"
      true -> "source"
    end
  end

  @doc """
  Builds file_snapshots for the current state of all files in an API.
  Used when creating ApiVersions.
  """
  @spec build_file_snapshots(Ecto.UUID.t()) :: [map()]
  def build_file_snapshots(api_id) do
    files = list_files(api_id)

    Enum.map(files, fn file ->
      latest_rev =
        ApiFileRevision
        |> where([r], r.api_file_id == ^file.id)
        |> order_by([r], desc: r.revision_number)
        |> limit(1)
        |> Repo.one()

      %{
        path: file.path,
        content: file.content,
        file_id: file.id,
        revision_number: if(latest_rev, do: latest_rev.revision_number, else: 1)
      }
    end)
  end

  @doc """
  Returns the source code for compilation as a list of `%{path: String.t(), content: String.t()}`.
  """
  @spec get_source_for_compilation(Ecto.UUID.t()) :: [%{path: String.t(), content: String.t()}]
  def get_source_for_compilation(api_id) do
    api_id
    |> list_source_files()
    |> Enum.map(&%{path: &1.path, content: &1.content || ""})
  end

  @doc """
  Returns the test code for testing as a list of `%{path: String.t(), content: String.t()}`.
  """
  @spec get_tests_for_running(Ecto.UUID.t()) :: [%{path: String.t(), content: String.t()}]
  def get_tests_for_running(api_id) do
    api_id
    |> list_test_files()
    |> Enum.map(&%{path: &1.path, content: &1.content || ""})
  end

  # ── Versioning ───────────────────────────────────────────────

  @spec create_version(Api.t(), map()) :: {:ok, ApiVersion.t()} | {:error, Ecto.Changeset.t()}
  def create_version(%Api{} = api, attrs) do
    file_snapshots = attrs[:file_snapshots] || build_file_snapshots(api.id)

    Ecto.Multi.new()
    |> Ecto.Multi.run(:next_number, &next_version_number(&1, &2, api.id))
    |> Ecto.Multi.run(:diff_summary, fn _repo, _changes ->
      {:ok, compute_version_diff_summary(api.id, file_snapshots)}
    end)
    |> Ecto.Multi.insert(:version, fn %{next_number: number, diff_summary: summary} ->
      ApiVersion.changeset(
        %ApiVersion{},
        Map.merge(attrs, %{
          api_id: api.id,
          version_number: number,
          file_snapshots: file_snapshots,
          diff_summary: summary
        })
      )
    end)
    |> Repo.transaction()
    |> unwrap_version_transaction()
  end

  defp next_version_number(repo, _changes, api_id) do
    result =
      ApiVersion
      |> where([v], v.api_id == ^api_id)
      |> select([v], max(v.version_number))
      |> repo.one()

    {:ok, (result || 0) + 1}
  end

  defp compute_version_diff_summary(api_id, current_snapshots) do
    latest =
      ApiVersion
      |> where([v], v.api_id == ^api_id)
      |> order_by([v], desc: v.version_number)
      |> limit(1)
      |> Repo.one()

    case latest do
      nil -> nil
      prev -> diff_snapshots(prev.file_snapshots, current_snapshots)
    end
  end

  defp diff_snapshots(prev_snapshots, curr_snapshots) do
    prev_map = snapshots_to_map(prev_snapshots)
    curr_map = snapshots_to_map(curr_snapshots)

    all_paths = (Map.keys(curr_map) ++ Map.keys(prev_map)) |> Enum.uniq()

    changes = Enum.flat_map(all_paths, &diff_single_path(&1, prev_map, curr_map))

    if changes == [], do: "No changes", else: Enum.join(changes, "\n")
  end

  defp snapshots_to_map(snapshots) do
    Map.new(snapshots, &{&1["path"] || &1[:path], &1["content"] || &1[:content]})
  end

  defp diff_single_path(path, prev_map, curr_map) do
    prev_content = Map.get(prev_map, path)
    curr_content = Map.get(curr_map, path)

    cond do
      is_nil(prev_content) ->
        ["+ #{path} (new file)"]

      is_nil(curr_content) ->
        ["- #{path} (deleted)"]

      prev_content != curr_content ->
        diff = DiffEngine.compute_diff(prev_content, curr_content)
        ["~ #{path}: #{DiffEngine.format_diff_summary(diff)}"]

      true ->
        []
    end
  end

  defp unwrap_version_transaction({:ok, %{version: version}}), do: {:ok, version}
  defp unwrap_version_transaction({:error, :version, changeset, _}), do: {:error, changeset}
  defp unwrap_version_transaction({:error, _step, reason, _}), do: {:error, reason}

  @spec list_versions(Ecto.UUID.t()) :: [ApiVersion.t()]
  def list_versions(api_id) do
    ApiVersion
    |> where([v], v.api_id == ^api_id)
    |> order_by([v], desc: v.version_number)
    |> Repo.all()
  end

  @spec get_version(Ecto.UUID.t(), integer()) :: ApiVersion.t() | nil
  def get_version(api_id, version_number) do
    ApiVersion
    |> where([v], v.api_id == ^api_id and v.version_number == ^version_number)
    |> Repo.one()
  end

  @spec published_version(Ecto.UUID.t()) :: ApiVersion.t() | nil
  def published_version(api_id) do
    ApiVersion
    |> where([v], v.api_id == ^api_id and v.source == "publish")
    |> order_by([v], desc: v.version_number)
    |> limit(1)
    |> Repo.one()
  end

  @spec get_latest_version(Api.t()) :: ApiVersion.t() | nil
  def get_latest_version(%Api{id: api_id}) do
    ApiVersion
    |> where([v], v.api_id == ^api_id)
    |> order_by([v], desc: v.version_number)
    |> limit(1)
    |> Repo.one()
  end

  @spec rollback_to_version(Api.t(), integer(), integer() | nil) ::
          {:ok, ApiVersion.t()} | {:error, :version_not_found | Ecto.Changeset.t()}
  def rollback_to_version(%Api{} = api, target_version_number, created_by_id \\ nil) do
    case get_version(api.id, target_version_number) do
      nil ->
        {:error, :version_not_found}

      target ->
        # Restore files from snapshot
        restore_files_from_snapshots(api, target.file_snapshots, created_by_id)

        create_version(api, %{
          source: "rollback",
          prompt: "Rollback to version #{target_version_number}",
          created_by_id: created_by_id
        })
    end
  end

  defp restore_files_from_snapshots(api, snapshots, created_by_id) do
    Enum.each(snapshots, fn snapshot ->
      path = snapshot["path"] || snapshot[:path]
      content = snapshot["content"] || snapshot[:content]

      case get_file(api.id, path) do
        nil ->
          create_file(api, %{
            path: path,
            content: content,
            file_type: infer_file_type(path),
            source: "rollback",
            created_by_id: created_by_id
          })

        existing ->
          update_file_content(existing, content, %{
            source: "rollback",
            message: "Restored from version snapshot",
            created_by_id: created_by_id
          })
      end
    end)

    snapshot_paths = Enum.map(snapshots, &(&1["path"] || &1[:path]))
    current_files = list_files(api.id)

    Enum.each(current_files, fn file ->
      unless file.path in snapshot_paths, do: delete_file(file)
    end)
  end

  @doc """
  Creates an API and seeds it with default skeleton files based on its template_type.

  Creates `/src/handler.ex` with a template-appropriate skeleton and
  `/test/handler_test.ex` as an empty placeholder.

  Returns `{:ok, api}` on success.
  """
  @spec create_api_with_files(map()) ::
          {:ok, Api.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :limit_exceeded, map()}
  def create_api_with_files(attrs) do
    case create_api(attrs) do
      {:ok, api} ->
        template_type = to_string(api.template_type || "computation")
        handler_content = default_handler_content(template_type)

        create_file(api, %{
          path: "/src/handler.ex",
          content: handler_content,
          file_type: "source",
          source: "scaffold"
        })

        create_file(api, %{
          path: "/test/handler_test.ex",
          content: "# Tests will be generated by the AI agent",
          file_type: "test",
          source: "scaffold"
        })

        create_file(api, %{
          path: "/README.md",
          content:
            "# #{api.name}\n\nDocumentation will be generated after code generation completes.",
          file_type: "doc",
          source: "scaffold"
        })

        {:ok, api}

      error ->
        error
    end
  end

  defp default_handler_content("crud") do
    "def handle_list(params), do: []\n" <>
      "def handle_get(id, params), do: %{id: id}\n" <>
      "def handle_create(params), do: %{created: true}\n" <>
      "def handle_update(id, params), do: %{updated: true}\n" <>
      "def handle_delete(id), do: %{deleted: true}"
  end

  defp default_handler_content("webhook") do
    "def handle_webhook(payload) do\n  %{received: true}\nend"
  end

  defp default_handler_content(_computation) do
    "def handle(params) do\n  %{result: \"ok\"}\nend"
  end

  # --- API from generation ---

  @spec create_api_from_generation(GenerationResult.t(), Ecto.UUID.t(), integer(), String.t()) ::
          {:ok, Api.t()} | {:error, Ecto.Changeset.t()}
  def create_api_from_generation(%GenerationResult{} = result, organization_id, user_id, name) do
    create_api(%{
      name: name,
      description: result.description,
      template_type: to_string(result.template),
      method: result.method || "POST",
      organization_id: organization_id,
      user_id: user_id,
      example_request: result.example_request,
      example_response: result.example_response,
      param_schema: result.param_schema
    })
  end

  # --- Publishing ---

  @spec publish(Api.t(), Organization.t()) ::
          {:ok, Api.t()}
          | {:error, :not_compiled | :org_mismatch | Ecto.Changeset.t()}
  def publish(
        %Api{status: "compiled", organization_id: org_id} = api,
        %Organization{id: org_id} = org
      ) do
    case update_api(api, %{status: "published"}) do
      {:ok, published_api} ->
        register_published_api(published_api, org)

        version_label = generate_version_label(published_api.id)

        create_version(published_api, %{
          source: "publish",
          version_label: version_label
        })

        Audit.log_async("api.published", %{
          resource_type: "api",
          resource_id: published_api.id,
          user_id: published_api.user_id,
          organization_id: org.id
        })

        {:ok, published_api}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def publish(%Api{status: "compiled"}, %Organization{}), do: {:error, :org_mismatch}
  def publish(%Api{}, _org), do: {:error, :not_compiled}

  @spec unpublish(Api.t()) :: {:ok, Api.t()} | {:error, :not_published | Ecto.Changeset.t()}
  def unpublish(%Api{status: "published"} = api) do
    case update_api(api, %{status: "compiled"}) do
      {:ok, updated_api} ->
        Registry.unregister(api.id)

        module_name = Compiler.module_name_for(api)
        Compiler.unload(module_name)

        Audit.log_async("api.unpublished", %{
          resource_type: "api",
          resource_id: api.id,
          user_id: api.user_id,
          organization_id: api.organization_id
        })

        {:ok, updated_api}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def unpublish(%Api{}), do: {:error, :not_published}

  defp generate_version_label(api_id) do
    today = Date.to_iso8601(Date.utc_today())
    count = count_versions_today(api_id)
    "prod-#{today}.#{String.pad_leading(to_string(count + 1), 2, "0")}"
  end

  defp count_versions_today(api_id) do
    today = Date.utc_today()

    ApiVersion
    |> where([v], v.api_id == ^api_id)
    |> where([v], fragment("?::date", v.inserted_at) == ^today)
    |> where([v], not is_nil(v.version_label))
    |> Repo.aggregate(:count)
  end

  defp register_published_api(api, org) do
    Registry.register(api.id, Compiler.module_name_for(api),
      org_slug: org.slug,
      slug: api.slug,
      requires_auth: api.requires_auth,
      visibility: api.visibility
    )
  rescue
    error ->
      Logger.warning("Failed to register published API #{api.id}: #{inspect(error)}")
  end

  # ── Agent Pipeline ───────────────────────────────────────────

  @spec start_agent_generation(Api.t(), String.t(), String.t() | integer()) ::
          {:ok, String.t()} | {:error, term()}
  def start_agent_generation(%Api{} = api, description, user_id) do
    args = %{
      "api_id" => api.id,
      "organization_id" => api.organization_id,
      "user_id" => user_id,
      "run_type" => "generation",
      "trigger_message" => description
    }

    update_api(api, %{generation_status: "generating"})

    case args |> KickoffWorker.new() |> Oban.insert() do
      {:ok, _job} -> {:ok, api.id}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec start_agent_edit(Api.t(), String.t(), String.t() | integer()) ::
          {:ok, String.t()} | {:error, term()}
  def start_agent_edit(%Api{} = api, instruction, user_id) do
    files = list_files(api.id)

    current_files =
      Enum.map(files, fn f ->
        %{"path" => f.path, "content" => f.content || "", "file_type" => f.file_type}
      end)

    args = %{
      "api_id" => api.id,
      "organization_id" => api.organization_id,
      "user_id" => user_id,
      "run_type" => "edit",
      "trigger_message" => instruction,
      "current_files" => current_files
    }

    case args |> KickoffWorker.new() |> Oban.insert() do
      {:ok, _job} -> {:ok, api.id}
      {:error, reason} -> {:error, reason}
    end
  end
end
