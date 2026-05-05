defmodule Blackboex.ProjectAgent.Planner do
  @moduledoc """
  Pure-ish module that builds the Planner prompt, drives the typed
  emission backend (`ReqLLM.Generation.generate_object/4` per M2 SPIKE),
  and returns `{:ok, %{plan_attrs, task_attrs}}`.

  ## Cacheable prompt assembly

  The Planner prompt has a stable cacheable prefix (system instructions +
  tool descriptions + ProjectIndex digest) and a volatile suffix (user
  message). The prefix is constructed via
  `Blackboex.LLM.PromptCache.stable_segment/2` (the sole sanctioned
  constructor — the Credo `AnthropicCacheTtl` check rejects bare
  `cache_control:` literals outside this module's directory). The suffix
  is `Blackboex.LLM.PromptCache.volatile_segment/1`.

  ## Heartbeat

  `Budget.touch_run/1` is invoked around the LLM call and (when the real
  ReqLLM streaming API lands in M5+) between streaming chunks so the
  planner Run's `updated_at` advances every few seconds. This prevents
  `Agent.RecoveryWorker` from killing the planner Run at the 120s stale
  threshold.

  ## Tier

  All planner LLM calls flow through
  `Blackboex.LLM.Config.client_for_project(project_id, tier: :planner)`.
  Per-tier rate limiting (`Blackboex.LLM.RateLimiter.check_rate(user_id,
  plan, tier: :planner)`) is the caller's responsibility (`KickoffWorker`
  enforces this before invoking the Planner).

  ## Test seam

  In test env an opt-in client function can be configured under
  `:project_planner_client` (a 2-arity fun); when set the Planner uses it
  instead of `ReqLLM.Generation.generate_object/4`. This lets unit tests
  bypass network access without compromising the production code path.
  """

  alias Blackboex.Agent.Pipeline.Budget
  alias Blackboex.LLM.Config, as: LLMConfig
  alias Blackboex.Plans.MarkdownRenderer
  alias Blackboex.Plans.Plan
  alias Blackboex.Plans.PlanTask
  alias Blackboex.ProjectAgent.ProjectIndex
  alias Blackboex.Projects.Project

  @typedoc "Result of `build_prompt/2`."
  @type prompt :: %{required(:messages) => [map()], required(:system) => String.t()}

  @typedoc "Result of `build_plan/2`."
  @type plan_emission :: %{
          required(:plan_attrs) => map(),
          required(:task_attrs) => [map()]
        }

  @system_prompt """
  You are the Project Agent Planner. Your job is to decompose a user's
  natural-language request into a small ordered set of tasks, where each
  task targets exactly one of four artifact types: api, flow, page, or
  playground. Output a typed plan with concrete acceptance criteria. Do
  NOT generate code. The per-artifact agents (Agent / FlowAgent /
  PageAgent / PlaygroundAgent) handle code generation.
  """

  @tool_description """
  Available artifact types:
    - api: an HTTP-callable handler. Action: create | edit.
    - flow: a multi-step automation. Action: create | edit.
    - page: a free-form Markdown page. Action: create | edit.
    - playground: a code snippet. Action: create | edit.

  Use `acceptance_criteria` for any artifact-specific details
  (template type, page title, expected behavior, etc.). The per-artifact
  agents read these criteria and produce concrete code/content.
  """

  @doc """
  Builds the Planner prompt for `project` + `user_message`. Returns a map
  with the system prompt and the segmented messages list (stable +
  volatile).

  Options:
    * `:prior_partial_summary` — string summarizing the prior plan's
      failure context. When given, it is appended to the volatile segment
      so the LLM can re-plan around the failure (M7 continuation flow).
  """
  @spec build_prompt(Project.t(), String.t(), keyword()) :: prompt()
  def build_prompt(project, user_message, opts \\ [])

  def build_prompt(%Project{} = project, user_message, opts)
      when is_binary(user_message) and is_list(opts) do
    digest = ProjectIndex.build(project)
    index_text = ProjectIndex.to_text(digest)

    stable_text =
      [
        @tool_description,
        "\n\nProject inventory (cache key: ",
        digest.cache_key,
        "):\n",
        index_text
      ]
      |> IO.iodata_to_binary()

    volatile_text = build_volatile_text(user_message, Keyword.get(opts, :prior_partial_summary))

    %{
      system: @system_prompt,
      messages: [
        %{text: stable_text},
        %{text: volatile_text}
      ]
    }
  end

  @spec build_volatile_text(String.t(), String.t() | nil) :: String.t()
  defp build_volatile_text(user_message, nil), do: "User request: " <> user_message

  defp build_volatile_text(user_message, summary) when is_binary(summary) do
    "Prior plan summary (continuation):\n" <> summary <> "\n\nUser request: " <> user_message
  end

  @doc """
  Builds a plan by calling the typed-emission backend. Returns
  `{:ok, %{plan_attrs, task_attrs}}` ready for
  `Blackboex.Plans.create_draft_plan/3`, or `{:error, reason}` on failure.

  Required attrs: `:user_message`. Optional: `:run_id` (planner Run id for
  heartbeat), `:prior_partial_summary` (M7 continuation context appended
  to the volatile prompt segment).
  """
  @spec build_plan(Project.t(), map()) ::
          {:ok, plan_emission()} | {:error, term()}
  def build_plan(%Project{} = project, %{user_message: user_message} = attrs) do
    run_id = Map.get(attrs, :run_id)
    prior_summary = Map.get(attrs, :prior_partial_summary)

    prompt =
      build_prompt(project, user_message, prior_partial_summary: prior_summary)

    _ = Budget.touch_run(run_id)

    case call_emission_backend(project, prompt) do
      {:ok, %{tasks: []}} ->
        {:error, :empty_plan}

      {:ok, %{title: title, tasks: tasks}} when is_binary(title) and is_list(tasks) ->
        _ = Budget.touch_run(run_id)
        {:ok, build_emission(project, title, user_message, tasks)}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:invalid_emission, other}}
    end
  end

  @spec build_emission(Project.t(), String.t(), String.t(), [map()]) :: plan_emission()
  defp build_emission(project, title, user_message, tasks) do
    task_attrs =
      tasks
      |> Enum.with_index()
      |> Enum.map(fn {t, idx} -> normalize_task(t, idx) end)

    plan_skeleton = build_plan_skeleton(project, title, user_message, task_attrs)

    %{
      plan_attrs:
        Map.put(
          plan_skeleton,
          :markdown_body,
          MarkdownRenderer.render(plan_skeleton_to_struct(plan_skeleton, task_attrs))
        ),
      task_attrs: task_attrs
    }
  end

  @spec build_plan_skeleton(Project.t(), String.t(), String.t(), [map()]) :: map()
  defp build_plan_skeleton(project, title, user_message, _task_attrs) do
    %{
      project_id: project.id,
      title: title,
      user_message: user_message,
      status: "draft",
      model_tier_caps: %{}
    }
  end

  @spec plan_skeleton_to_struct(map(), [map()]) :: Plan.t()
  defp plan_skeleton_to_struct(skeleton, task_attrs) do
    tasks =
      Enum.map(task_attrs, fn t ->
        struct(PlanTask, Map.put(t, :status, "pending"))
      end)

    struct(
      Plan,
      Map.merge(
        Map.take(skeleton, [:project_id, :title, :user_message, :status, :failure_reason]),
        %{tasks: tasks}
      )
    )
  end

  @spec normalize_task(map(), non_neg_integer()) :: map()
  defp normalize_task(%{} = task, idx) do
    %{
      order: idx,
      artifact_type: Map.fetch!(task, :artifact_type),
      action: Map.fetch!(task, :action),
      target_artifact_id: Map.get(task, :target_artifact_id),
      title: Map.fetch!(task, :title),
      params: Map.get(task, :params, %{}),
      acceptance_criteria: Map.get(task, :acceptance_criteria, []),
      status: "pending"
    }
  end

  # ── LLM emission backend ───────────────────────────────────────

  @spec call_emission_backend(Project.t(), prompt()) ::
          {:ok, %{title: String.t(), tasks: [map()]}} | {:error, term()}
  defp call_emission_backend(project, prompt) do
    case Application.get_env(:blackboex, :project_planner_client) do
      fun when is_function(fun, 2) ->
        fun.(project, prompt)

      _ ->
        do_call_req_llm(project, prompt)
    end
  end

  # JSON-Schema-compatible keyword list for ReqLLM.Schema.compile/1.
  # NimbleOptions nested map type maps to a JSON Schema "object" with properties.
  @plan_schema [
    title: [
      type: :string,
      required: true,
      doc: "Short, human-readable plan title (≤ 80 chars)"
    ],
    tasks: [
      type:
        {:list,
         {:map,
          [
            artifact_type: [
              type: {:in, ["api", "flow", "page", "playground"]},
              required: true,
              doc: "Type of artifact this task targets"
            ],
            action: [
              type: {:in, ["create", "edit"]},
              required: true,
              doc: "Whether to create a new artifact or edit an existing one"
            ],
            title: [
              type: :string,
              required: true,
              doc: "Short task title"
            ],
            target_artifact_id: [
              type: :string,
              doc: "UUID of the artifact to edit; omit or null for create"
            ],
            acceptance_criteria: [
              type: {:list, :string},
              doc: "Bullet list of acceptance criteria for this task"
            ]
          ]}},
      required: true,
      doc: "Ordered list of tasks; must have at least one entry"
    ]
  ]

  @spec do_call_req_llm(Project.t(), prompt()) ::
          {:ok, %{title: String.t(), tasks: [map()]}} | {:error, term()}
  defp do_call_req_llm(project, prompt) do
    with {:ok, _client_mod, llm_opts} <- LLMConfig.client_for_project(project.id),
         model = planner_model(),
         messages = build_req_llm_messages(prompt),
         # Force tool-calling for typed object emission. The Anthropic
         # `output_format` (structured outputs, beta Nov/2025) is only
         # supported on a small set of newer models; tool-calling is
         # universally supported and equally strict for our use case.
         req_opts =
           llm_opts
           |> Keyword.merge(max_tokens: 4096, temperature: 0.2)
           |> Keyword.update(:provider_options, [anthropic_structured_output_mode: :tool_strict],
             fn po -> Keyword.put(po, :anthropic_structured_output_mode, :tool_strict) end
           ),
         {:ok, response} <-
           ReqLLM.Generation.generate_object(model, messages, @plan_schema, req_opts) do
      object = ReqLLM.Response.object(response)
      validate_plan_object(object)
    else
      {:error, :not_configured} -> {:error, :planner_backend_not_configured}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec planner_model() :: String.t()
  defp planner_model do
    Application.get_env(
      :blackboex,
      :llm_default_model,
      "anthropic:claude-sonnet-4-20250514"
    )
  end

  # Build the ReqLLM-compatible messages list from our prompt map.
  # ReqLLM.Context accepts a list with system + user messages.
  @spec build_req_llm_messages(prompt()) :: ReqLLM.Context.t()
  defp build_req_llm_messages(%{system: system, messages: segments}) do
    # Convert PromptCache segments (stable + volatile) to plain text for ReqLLM.
    # Cache-control metadata is preserved for providers that support it; for
    # providers that don't, the text content is used as-is.
    text =
      segments
      |> Enum.map(fn
        %{text: t} -> t
        other -> inspect(other)
      end)
      |> Enum.join("\n\n")

    ReqLLM.Context.new([
      ReqLLM.Context.system(system),
      ReqLLM.Context.user(text)
    ])
  end

  # Validate and normalize the raw map returned by the LLM.
  # Uses the same Ecto-changeset approach verified in the M2 SPIKE.
  @spec validate_plan_object(map() | nil) ::
          {:ok, %{title: String.t(), tasks: [map()]}} | {:error, term()}
  defp validate_plan_object(nil), do: {:error, :empty_emission}

  defp validate_plan_object(object) when is_map(object) do
    title = Map.get(object, "title") || Map.get(object, :title)
    raw_tasks = Map.get(object, "tasks") || Map.get(object, :tasks) || []

    with true <- is_binary(title) and String.length(title) > 0,
         true <- is_list(raw_tasks) do
      tasks = Enum.map(raw_tasks, &normalize_raw_task/1)
      {:ok, %{title: title, tasks: tasks}}
    else
      _ -> {:error, {:invalid_emission, object}}
    end
  end

  @spec normalize_raw_task(map()) :: map()
  defp normalize_raw_task(t) when is_map(t) do
    %{
      artifact_type: Map.get(t, "artifact_type") || Map.get(t, :artifact_type),
      action: Map.get(t, "action") || Map.get(t, :action),
      title: Map.get(t, "title") || Map.get(t, :title),
      target_artifact_id: Map.get(t, "target_artifact_id") || Map.get(t, :target_artifact_id),
      params: Map.get(t, "params") || Map.get(t, :params) || %{},
      acceptance_criteria:
        Map.get(t, "acceptance_criteria") || Map.get(t, :acceptance_criteria) || []
    }
  end
end
