# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Blackboex.Repo.insert!(%Blackboex.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Blackboex.Accounts
alias Blackboex.Accounts.User
alias Blackboex.Repo

admin_email = "admin@admin.com"
admin_password = "adminadminadmin"

case Accounts.get_user_by_email(admin_email) do
  nil ->
    {:ok, user} = Accounts.register_user(%{email: admin_email})

    user
    |> User.password_changeset(%{password: admin_password}, hash_password: true)
    |> User.confirm_changeset()
    |> Ecto.Changeset.change(is_platform_admin: true)
    |> Repo.update!()

    IO.puts("Admin user created: #{admin_email} / #{admin_password}")

  user ->
    user
    |> User.password_changeset(%{password: admin_password}, hash_password: true)
    |> Ecto.Changeset.change(is_platform_admin: true)
    |> Repo.update!()

    IO.puts("Admin user already exists, updated password and ensured is_platform_admin: true")
end
