defmodule Blackboex.Mailer do
  @moduledoc """
  Mailer module for sending transactional emails.
  """
  use Swoosh.Mailer, otp_app: :blackboex
end
