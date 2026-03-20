defmodule Blackboex.CodeGen.ASTValidator do
  @moduledoc """
  Validates generated code by walking the AST and checking for dangerous operations.

  Ensures that user-generated code only uses allowed modules and doesn't perform
  dangerous operations like file I/O, system commands, or process manipulation.
  """

  @blocked_modules [
    File,
    System,
    Process,
    Port,
    IO,
    Code,
    Module,
    Node,
    Application,
    # HTTP clients — prevent SSRF and data exfiltration
    Req,
    Req.Request,
    HTTPoison
  ]

  @blocked_erlang_modules [
    :os,
    :erlang,
    :ets,
    :dets,
    :mnesia,
    :net,
    :gen_tcp,
    :gen_udp,
    :httpc,
    # HTTP client backends
    :finch,
    :mint,
    :hackney
  ]

  # Kernel functions that must be blocked as bare calls
  @blocked_kernel_functions [
    :spawn,
    :spawn_link,
    :spawn_monitor,
    :exit,
    :throw,
    :send,
    :apply
  ]

  # Specific function calls on allowed modules that must be blocked
  # (prevents runtime module construction bypass)
  @blocked_function_calls %{
    String => [:to_atom, :to_existing_atom],
    Kernel => [:send, :apply, :spawn, :spawn_link, :spawn_monitor, :exit, :throw],
    List => [:to_atom]
  }

  @max_atoms 500

  @spec validate(String.t()) :: {:ok, Macro.t()} | {:error, [String.t()]}
  def validate(code) when is_binary(code) do
    atom_counter = :counters.new(1, [:atomics])

    static_atoms_encoder = fn token, _meta ->
      count = :counters.get(atom_counter, 1)

      if count >= @max_atoms do
        {:error, "too many unique atoms (limit: #{@max_atoms})"}
      else
        :counters.add(atom_counter, 1, 1)

        try do
          {:ok, String.to_existing_atom(token)}
        rescue
          ArgumentError ->
            {:ok, String.to_atom(token)}
        end
      end
    end

    case Code.string_to_quoted(code,
           static_atoms_encoder: static_atoms_encoder,
           columns: true
         ) do
      {:ok, ast} ->
        violations = walk(ast, [])

        case violations do
          [] -> {:ok, ast}
          errors -> {:error, Enum.reverse(errors)}
        end

      {:error, {_meta, message, token}} ->
        {:error, ["parse error: #{message}#{token}"]}
    end
  end

  # Module reference: check if blocked
  defp walk({:__aliases__, _meta, parts} = node, acc) do
    module = Module.concat(parts)

    acc =
      if module in @blocked_modules do
        ["blocked module: #{inspect(module)}" | acc]
      else
        acc
      end

    walk_children(node, acc)
  end

  # Elixir module function call: Module.func(args)
  defp walk({{:., _meta1, [{:__aliases__, _meta2, parts}, func]}, _meta3, args}, acc) do
    module = Module.concat(parts)

    acc =
      if module in @blocked_modules do
        ["blocked module: #{inspect(module)}" | acc]
      else
        check_blocked_function_call(acc, module, func)
      end

    walk_list(args, acc)
  end

  # Erlang module call: :erlang.func(args)
  defp walk({{:., _meta1, [erlang_mod, _func]}, _meta2, args}, acc)
       when is_atom(erlang_mod) do
    acc =
      if erlang_mod in @blocked_erlang_modules do
        ["blocked Erlang module: #{inspect(erlang_mod)}" | acc]
      else
        acc
      end

    walk_list(args, acc)
  end

  # Blocked Kernel functions as bare calls: spawn(...), exit(...), etc.
  defp walk({func, _meta, args}, acc)
       when is_atom(func) and is_list(args) and func in @blocked_kernel_functions do
    ["blocked function: #{func}/#{length(args)} is not allowed" | walk_list(args, acc)]
  end

  # receive block
  defp walk({:receive, _meta, _args} = node, acc) do
    ["blocked construct: receive is not allowed" | walk_children(node, acc)]
  end

  # import of dangerous module
  defp walk({:import, _meta, args} = node, acc) do
    acc = check_import(args, acc)
    walk_children(node, acc)
  end

  # require of dangerous module
  defp walk({:require, _meta, args} = node, acc) do
    acc = check_require(args, acc)
    walk_children(node, acc)
  end

  # Generic 3-tuple AST node
  defp walk({_form, _meta, children} = _node, acc) when is_list(children) do
    walk_list(children, acc)
  end

  # 2-tuple (keyword pairs, etc.)
  defp walk({left, right}, acc) do
    acc = walk(left, acc)
    walk(right, acc)
  end

  # Lists
  defp walk(list, acc) when is_list(list) do
    walk_list(list, acc)
  end

  # Leaf nodes (atoms, numbers, strings)
  defp walk(_leaf, acc), do: acc

  defp walk_children({_form, _meta, children}, acc) when is_list(children) do
    walk_list(children, acc)
  end

  defp walk_children(_node, acc), do: acc

  defp walk_list(list, acc) when is_list(list) do
    Enum.reduce(list, acc, &walk/2)
  end

  defp walk_list(_not_list, acc), do: acc

  defp check_import([{:__aliases__, _meta, parts} | _rest], acc) do
    module = Module.concat(parts)

    if module in @blocked_modules do
      ["blocked import: import #{inspect(module)} is not allowed" | acc]
    else
      acc
    end
  end

  defp check_import(_args, acc), do: acc

  defp check_require([{:__aliases__, _meta, parts} | _rest], acc) do
    module = Module.concat(parts)

    if module in @blocked_modules do
      ["blocked require: require #{inspect(module)} is not allowed" | acc]
    else
      acc
    end
  end

  defp check_require(_args, acc), do: acc

  defp check_blocked_function_call(acc, module, func) do
    blocked_fns = Map.get(@blocked_function_calls, module, [])

    if func in blocked_fns do
      ["blocked function: #{inspect(module)}.#{func} is not allowed" | acc]
    else
      acc
    end
  end
end
