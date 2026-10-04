defmodule YouCongress.Workers.ReconsiderationCreatedNotificationWorkerTest do
  use YouCongress.DataCase

  import Swoosh.TestAssertions

  alias YouCongress.Workers.ReconsiderationCreatedNotificationWorker

  test "emails Hector with the page creator's name and URL" do
    assert :ok =
             ReconsiderationCreatedNotificationWorker.perform(%Oban.Job{
               args: %{
                 "creator_name" => "Ada Lovelace",
                 "reconsideration_url" => "https://youcongress.org/@ada/r/analytical-engine"
               }
             })

    assert_email_sent(fn email ->
      assert email.to == [{"", "hector@youcongress.org"}]
      assert email.subject == "New YouCongress Reconsider page"
      assert email.text_body =~ "Creator: Ada Lovelace"
      assert email.text_body =~ "Page: https://youcongress.org/@ada/r/analytical-engine"
      assert email.html_body =~ "Creator: Ada Lovelace"
      assert email.html_body =~ ~s(href="https://youcongress.org/@ada/r/analytical-engine")
      true
    end)
  end
end
