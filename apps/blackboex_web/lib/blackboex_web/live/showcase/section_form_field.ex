defmodule BlackboexWeb.Showcase.Sections.FormFieldShowcase do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers

  @code_text_types ~S"""
  <.input type="text" name="name" value="" label="Name" />
  <.input type="email" name="email" value="" label="Email" />
  <.input type="password" name="password" value="" label="Password" />
  <.input type="number" name="count" value="" label="Count" />
  <.input type="search" name="q" value="" label="Search" />
  <.input type="url" name="website" value="" label="Website" />
  """

  @code_textarea ~S"""
  <.input type="textarea" name="description" value="" label="Description" rows="4" />
  """

  @code_select ~S"""
  <.input
    type="select"
    name="role"
    value="user"
    label="Role"
    prompt="-- select a role --"
    options={[{"Admin", "admin"}, {"User", "user"}, {"Viewer", "viewer"}]}
  />
  """

  @code_checkbox ~S"""
  <.input type="checkbox" name="agree" value="false" label="I agree to the terms" />
  <.input type="checkbox" name="subscribe" value="true" label="Subscribe to newsletter" />
  """

  @code_with_label ~S"""
  <.input name="title" value="My API" label="API Title" />
  <.input name="slug" value="my-api" label="Slug" />
  """

  @code_with_errors ~S"""
  <.input
    name="email"
    value=""
    label="Email"
    errors={["can't be blank", "is too short"]}
  />
  """

  @code_datetime ~S"""
  <.input type="date" name="start_date" value="" label="Start date" />
  <.input type="datetime-local" name="scheduled_at" value="" label="Scheduled at" />
  <.input type="time" name="time" value="" label="Time" />
  <.input type="month" name="month" value="" label="Month" />
  """

  @code_disabled ~S"""
  <.input type="text" name="name" value="Read only plan" label="Plan" disabled />
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_text_types, @code_text_types)
      |> assign(:code_textarea, @code_textarea)
      |> assign(:code_select, @code_select)
      |> assign(:code_checkbox, @code_checkbox)
      |> assign(:code_with_label, @code_with_label)
      |> assign(:code_with_errors, @code_with_errors)
      |> assign(:code_datetime, @code_datetime)
      |> assign(:code_disabled, @code_disabled)

    ~H"""
    <.section_header
      title="FormField (input)"
      description="Full-featured form input with label, validation errors, and Phoenix form field binding. Handles all HTML input types plus select and textarea. Use field= for Phoenix form integration; name=/value= for manual binding."
      module="BlackboexWeb.Components.FormField"
    />
    <div class="space-y-10">
      <.showcase_block title="Text types" code={@code_text_types}>
        <div class="grid grid-cols-1 gap-0 max-w-sm">
          <.input type="text" name="name" value="" label="Name" placeholder="John Doe" />
          <.input type="email" name="email" value="" label="Email" placeholder="you@example.com" />
          <.input type="password" name="password" value="" label="Password" />
          <.input type="number" name="count" value="" label="Count" placeholder="0" />
          <.input type="search" name="q" value="" label="Search" placeholder="Search..." />
          <.input type="url" name="website" value="" label="Website" placeholder="https://" />
        </div>
      </.showcase_block>

      <.showcase_block title="Textarea" code={@code_textarea}>
        <div class="max-w-sm">
          <.input
            type="textarea"
            name="description"
            value=""
            label="Description"
            rows="4"
            placeholder="Describe your API..."
          />
        </div>
      </.showcase_block>

      <.showcase_block title="Select" code={@code_select}>
        <div class="max-w-sm">
          <.input
            type="select"
            name="role"
            value="user"
            label="Role"
            prompt="-- select a role --"
            options={[{"Admin", "admin"}, {"User", "user"}, {"Viewer", "viewer"}]}
          />
        </div>
      </.showcase_block>

      <.showcase_block title="Checkbox" code={@code_checkbox}>
        <div class="max-w-sm">
          <.input type="checkbox" name="agree" value="false" label="I agree to the terms" />
          <.input
            type="checkbox"
            name="subscribe"
            value="true"
            label="Subscribe to newsletter"
          />
        </div>
      </.showcase_block>

      <.showcase_block title="With label" code={@code_with_label}>
        <div class="max-w-sm">
          <.input name="title" value="My API" label="API Title" />
          <.input name="slug" value="my-api" label="Slug" />
        </div>
      </.showcase_block>

      <.showcase_block title="With errors" code={@code_with_errors}>
        <div class="max-w-sm">
          <.input
            name="email"
            value=""
            label="Email"
            errors={["can't be blank", "is too short"]}
          />
        </div>
      </.showcase_block>

      <.showcase_block title="Date/time types" code={@code_datetime}>
        <div class="grid grid-cols-1 gap-0 max-w-sm">
          <.input type="date" name="start_date" value="" label="Start date" />
          <.input type="datetime-local" name="scheduled_at" value="" label="Scheduled at" />
          <.input type="time" name="time" value="" label="Time" />
          <.input type="month" name="month" value="" label="Month" />
        </div>
      </.showcase_block>

      <.showcase_block title="Disabled state" code={@code_disabled}>
        <div class="max-w-sm">
          <.input type="text" name="plan" value="Read only plan" label="Plan" disabled />
        </div>
      </.showcase_block>
    </div>
    """
  end
end
