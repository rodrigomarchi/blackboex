defmodule BlackboexWeb.Showcase.Sections.AvatarShowcase do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Avatar

  @code_with_image ~S"""
  <.avatar>
    <.avatar_image src="https://i.pravatar.cc/40" alt="User" />
  </.avatar>
  """

  @code_with_fallback ~S"""
  <.avatar>
    <.avatar_fallback>JD</.avatar_fallback>
  </.avatar>
  """

  @code_sizes ~S"""
  <.avatar class="w-8 h-8 rounded-full">
    <.avatar_fallback>S</.avatar_fallback>
  </.avatar>
  <.avatar class="w-10 h-10 rounded-full">
    <.avatar_fallback>M</.avatar_fallback>
  </.avatar>
  <.avatar class="w-16 h-16 rounded-full">
    <.avatar_fallback>L</.avatar_fallback>
  </.avatar>
  """

  @code_image_with_fallback ~S"""
  <.avatar>
    <.avatar_image src="https://i.pravatar.cc/40?img=3" alt="Jane" />
    <.avatar_fallback>JA</.avatar_fallback>
  </.avatar>
  """

  @code_custom_styles ~S"""
  <.avatar class="w-12 h-12 rounded-none">
    <.avatar_fallback class="rounded-none bg-primary text-primary-foreground font-bold">
      SQ
    </.avatar_fallback>
  </.avatar>
  <.avatar class="w-12 h-12 rounded-full">
    <.avatar_fallback class="bg-accent-blue/20 text-accent-blue font-semibold">
      BL
    </.avatar_fallback>
  </.avatar>
  <.avatar class="w-12 h-12 rounded-full">
    <.avatar_fallback class="bg-accent-green/20 text-accent-green font-semibold">
      GR
    </.avatar_fallback>
  </.avatar>
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_with_image, @code_with_image)
      |> assign(:code_with_fallback, @code_with_fallback)
      |> assign(:code_sizes, @code_sizes)
      |> assign(:code_image_with_fallback, @code_image_with_fallback)
      |> assign(:code_custom_styles, @code_custom_styles)

    ~H"""
    <.section_header
      title="Avatar"
      description="Composable avatar component. avatar_image renders the photo; avatar_fallback renders when the image fails or is absent. Compose them inside avatar."
      module="BlackboexWeb.Components.Avatar"
    />
    <div class="space-y-10">
      <.showcase_block title="With Image" code={@code_with_image}>
        <div class="flex gap-4">
          <.avatar>
            <.avatar_image src="https://i.pravatar.cc/40" alt="User" />
          </.avatar>
        </div>
      </.showcase_block>

      <.showcase_block title="With Fallback" code={@code_with_fallback}>
        <div class="flex gap-4">
          <.avatar>
            <.avatar_fallback>JD</.avatar_fallback>
          </.avatar>
        </div>
      </.showcase_block>

      <.showcase_block title="Sizes via class" code={@code_sizes}>
        <div class="flex items-end gap-4">
          <.avatar class="w-8 h-8 rounded-full">
            <.avatar_fallback>S</.avatar_fallback>
          </.avatar>
          <.avatar class="w-10 h-10 rounded-full">
            <.avatar_fallback>M</.avatar_fallback>
          </.avatar>
          <.avatar class="w-16 h-16 rounded-full">
            <.avatar_fallback>L</.avatar_fallback>
          </.avatar>
        </div>
      </.showcase_block>

      <.showcase_block title="Image with fallback" code={@code_image_with_fallback}>
        <div class="flex gap-4">
          <.avatar>
            <.avatar_image src="https://i.pravatar.cc/40?img=3" alt="Jane" />
            <.avatar_fallback>JA</.avatar_fallback>
          </.avatar>
          <.avatar>
            <.avatar_image src="/broken-image.png" alt="Broken" />
            <.avatar_fallback>BR</.avatar_fallback>
          </.avatar>
        </div>
      </.showcase_block>

      <.showcase_block title="Custom styles" code={@code_custom_styles}>
        <div class="flex items-center gap-4">
          <.avatar class="w-12 h-12 rounded-none">
            <.avatar_fallback class="rounded-none bg-primary text-primary-foreground font-bold">
              SQ
            </.avatar_fallback>
          </.avatar>
          <.avatar class="w-12 h-12 rounded-full">
            <.avatar_fallback class="bg-blue-100 text-blue-600 font-semibold">
              BL
            </.avatar_fallback>
          </.avatar>
          <.avatar class="w-12 h-12 rounded-full">
            <.avatar_fallback class="bg-green-100 text-green-600 font-semibold">
              GR
            </.avatar_fallback>
          </.avatar>
        </div>
      </.showcase_block>
    </div>
    """
  end
end
