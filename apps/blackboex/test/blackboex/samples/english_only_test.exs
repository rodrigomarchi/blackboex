defmodule Blackboex.Samples.EnglishOnlyTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../../../../", __DIR__)

  @excluded_paths [
    ~r(^apps/blackboex_web/assets/vendor/),
    ~r(^apps/blackboex_web/priv/gettext/),
    ~r(^apps/blackboex/test/blackboex/samples/english_only_test\.exs$),
    ~r(^deps/),
    ~r(^_build/),
    ~r(^mix\.lock$)
  ]

  @text_extensions ~w(
    .css .ex .exs .heex .js .json .md .mjs .txt .yml .yaml
  )

  @portuguese_pattern ~r/(?:[ÁÀÂÃÉÊÍÓÔÕÚÜÇáàâãéêíóôõúüç]|(?i)\b(?:nao|não|voce|você|portugues|português|usuario|usuário|usuarios|usuários|senha|entrar|sair|salvar|cancelar|excluir|remover|criar|editar|atualizar|carregando|nenhum|nenhuma|sucesso|falha|organizacao|organização|organizacoes|organizações|projeto|projetos|pagina|página|paginas|páginas|fluxo|fluxos|configuracao|configuração|configuracoes|configurações|convite|convites|membro|membros|ambiente|chave|chaves|execucao|execução|execucoes|execuções|documentacao|documentação|pedido|resposta|resumo|codigo|código|conteudo|conteúdo|exemplo|parametro|parâmetro|obrigatorio|obrigatório|descricao|descrição)\b)/u

  @allowed_matches [
    "CPF",
    "CNPJ",
    "CEP",
    "ICMS",
    "ISS",
    "PIS",
    "COFINS",
    "São Paulo"
  ]

  test "tracked project text is written in English" do
    violations =
      tracked_files()
      |> Enum.filter(&File.regular?(Path.join(@root, &1)))
      |> Enum.reject(&excluded?/1)
      |> Enum.filter(&text_file?/1)
      |> Enum.flat_map(&file_violations/1)

    assert violations == [],
           "Portuguese text remains in tracked files:\n" <>
             (violations
              |> Enum.take(250)
              |> Enum.map(&inspect(&1, binaries: :as_strings, printable_limit: 500))
              |> Enum.join("\n"))
  end

  defp tracked_files do
    {output, 0} = System.cmd("git", ["ls-files"], cd: @root)

    output
    |> String.split("\n", trim: true)
  end

  defp excluded?(path), do: Enum.any?(@excluded_paths, &Regex.match?(&1, path))

  defp text_file?(path), do: Path.extname(path) in @text_extensions

  defp file_violations(path) do
    absolute_path = Path.join(@root, path)

    absolute_path
    |> File.stream!()
    |> Stream.with_index(1)
    |> Enum.flat_map(&line_violations(path, &1))
  end

  defp line_violations(_path, {line, _line_number}) when not is_binary(line), do: []

  defp line_violations(path, {line, line_number}) do
    if String.valid?(line), do: scan_valid_line(path, line, line_number), else: []
  end

  defp scan_valid_line(path, line, line_number) do
    @portuguese_pattern
    |> Regex.scan(line)
    |> List.flatten()
    |> Enum.reject(&allowed_match?/1)
    |> Enum.map(fn match -> "#{path}:#{line_number}: #{match}" end)
  end

  defp allowed_match?(match), do: match in @allowed_matches
end
