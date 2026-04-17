defmodule Blackboex.PlaygroundAgent.PromptsTest do
  use ExUnit.Case, async: true

  alias Blackboex.PlaygroundAgent.Prompts

  describe "system_prompt/1" do
    test ":generate includes allowlist modules and helper aliases" do
      prompt = Prompts.system_prompt(:generate)
      assert prompt =~ "Playground do Blackboex"
      assert prompt =~ "Blackboex.Playgrounds.Http"
      assert prompt =~ "Blackboex.Playgrounds.Api"
      assert prompt =~ "Enum"
      assert prompt =~ "Jason"
      assert prompt =~ "PROIBIDO"
      assert prompt =~ "defmodule"
      assert prompt =~ "Resumo:"
    end

    test ":edit includes preservation rules" do
      prompt = Prompts.system_prompt(:edit)
      assert prompt =~ "EDITA"
      assert prompt =~ "Preserve"
      assert prompt =~ "diffs"
    end
  end

  describe "user_message/3" do
    test ":generate contains only the user request" do
      msg = Prompts.user_message(:generate, "soma 1+1", nil)
      assert msg =~ "Pedido do usuário"
      assert msg =~ "soma 1+1"
      refute msg =~ "Código atual"
    end

    test ":edit includes current code and user request" do
      msg = Prompts.user_message(:edit, "adicione um IO.puts", "x = 1\nx + 1")
      assert msg =~ "Código atual"
      assert msg =~ "x = 1"
      assert msg =~ "adicione um IO.puts"
    end

    test ":edit handles nil code_before safely" do
      msg = Prompts.user_message(:edit, "faça algo", nil)
      assert msg =~ "Código atual"
      assert msg =~ "faça algo"
    end

    test "renders thread history when provided" do
      history = [
        %{role: "user", content: "como imprimir algo?"},
        %{role: "assistant", content: "use IO.puts/1"}
      ]

      msg = Prompts.user_message(:edit, "exemplo", "x = 1", history: history)
      assert msg =~ "Histórico da conversa"
      assert msg =~ "Usuário: como imprimir algo?"
      assert msg =~ "Assistente: use IO.puts/1"
      assert msg =~ "Pedido do usuário:\nexemplo"
    end

    test "truncates long history messages to keep prompt bounded" do
      long = String.duplicate("a", 1000)
      history = [%{role: "user", content: long}]
      msg = Prompts.user_message(:generate, "go", nil, history: history)
      assert msg =~ "Histórico da conversa"
      assert msg =~ "..."
      refute msg =~ String.duplicate("a", 600)
    end

    test "no history block when history is empty" do
      msg = Prompts.user_message(:generate, "go", nil, history: [])
      refute msg =~ "Histórico"
    end
  end
end
