defmodule Blackboex.Samples.Page do
  @moduledoc """
  Page samples in the platform-wide sample catalogue.

  The list is an end-user onboarding guide for the managed sample workspace.
  It teaches how to build with Blackboex inside the product: create APIs,
  build Flows, write Pages, and experiment in Playgrounds.
  """

  alias Blackboex.Samples.Id

  @welcome_uuid Id.uuid(:page, "welcome")

  @spec list() :: [map()]
  def list do
    [
      welcome(),
      topic(
        "apis",
        1,
        "Create Your First API",
        "APIs",
        "Turn a plain-English request into a working HTTP endpoint.",
        apis_content()
      ),
      topic(
        "api_test_publish",
        2,
        "Test, Publish, and Call an API",
        "APIs",
        "Validateste an API with sample input, publish it, and send a request.",
        api_test_publish_content()
      ),
      topic(
        "flows",
        3,
        "Build a Visual Flow",
        "Flows",
        "Create a visual workflow that receives data, branches, and returns a result.",
        flows_content()
      ),
      topic(
        "flow_webhooks",
        4,
        "Receive Webhooks with Flows",
        "Flows",
        "Use a Flow as an automation endpoint for external events.",
        flow_webhooks_content()
      ),
      topic(
        "playgrounds",
        5,
        "Experiment in Playgrounds",
        "Playgrounds",
        "Try payloads, transformations, and calls before turning them into product work.",
        playgrounds_content()
      ),
      topic(
        "pages_doc",
        6,
        "Document Your Project with Pages",
        "Pages",
        "Write practical project notes, API guides, runbooks, and handoff docs.",
        pages_content()
      ),
      topic(
        "project_workflow",
        7,
        "Combine APIs, Flows, Pages, and Playgrounds",
        "Workflow",
        "Use each Blackboex tool for the part of the job it handles best.",
        project_workflow_content()
      ),
      topic(
        "next_steps",
        8,
        "Next Steps",
        "Getting Started",
        "Duplicate useful examples and create a real project for your own work.",
        next_steps_content()
      )
    ]
  end

  defp welcome do
    %{
      kind: :page,
      id: "welcome",
      sample_uuid: @welcome_uuid,
      name: "Welcome to Blackboex",
      title: "Welcome to Blackboex",
      description: "A practical tour of the sample workspace and what to build first.",
      category: "Getting Started",
      position: 0,
      status: "published",
      content: """
      # Welcome to Blackboex

      This sample workspace is here to help you build, test, and document real
      product workflows. It is not a technical manual. Every Page in this guide
      points you toward an action you can take inside Blackboex.

      ## What you can build here

      - **APIs**: HTTP endpoints generated from a plain-English description.
      - **Flows**: visual automations that receive data, branch, call services,
        and return results.
      - **Playgrounds**: small experiments for payloads, transformations, and
        product calls.
      - **Pages**: project notes, API guides, runbooks, and handoff docs.

      ## A good first path

      1. Open **APIs** and inspect **REST CRUD Resource** or **Product Catalog**.
      2. Create a new API from a short description of the endpoint you need.
      3. Open **Run** or the test area for that API and send a sample payload.
      4. Open **Flows** and inspect **Hello World** or **Webhook Processor**.
      5. Use **Pages** to document the request shape, response shape, and owner.
      6. Use a **Playground** when you want to try a JSON payload or data
         transformation before saving it into an API or Flow.

      ```mermaid
      flowchart LR
        Idea[Idea] --> API[Create API]
        API --> Test[Test request]
        Test --> Flow[Automate with Flow]
        Flow --> Docs[Document with Pages]
        Docs --> Project[Real project]
      ```

      ## How to use this workspace

      Open an example, run it, and compare its inputs and outputs with what you
      want to build. When an example is close to your use case, duplicate it into
      a project you own and adapt it there.
      """
    }
  end

  defp topic(id, position, name, category, description, content) do
    %{
      kind: :page,
      id: id,
      sample_uuid: Id.uuid(:page, id),
      parent_sample_uuid: @welcome_uuid,
      name: name,
      title: name,
      description: description,
      category: category,
      position: position,
      status: "published",
      content: content
    }
  end

  defp apis_content do
    """
    # Create Your First API

    Use an API when you need a live HTTP endpoint that accepts a request and
    returns a structured response.

    ## What to create first

    Start with a focused endpoint. Good first APIs answer one request clearly:

    - calculateste a price or fee;
    - validateste a form submission;
    - look up an item in a small catalog;
    - transform a webhook payload into the shape another tool expects.

    ## Try this prompt

    Paste a request like this into the API creation flow:

    ```text
    Create a POST API that receives a product id, quantity, and customer tier.
    Return the unit price, discount, subtotal, tax estimate, and final total.
    If the product id is unknown, return a clear validatestion errorr.
    ```

    ## What to click

    1. Open **APIs**.
    2. Select the action to create a new API.
    3. Describe the endpoint in plain English.
    4. Review the generated request fields, response fields, and example output.
    5. Save the API when the behavior matches the job.

    ## How to know it worked

    You should see a generated API with a request example, a response example,
    and editable files. The API should be ready for a test request with JSON
    input.

    ## Examples to inspect

    - **REST CRUD Resource** for create, read, update, and delete behavior.
    - **Product Catalog** for search, filters, and pagination.
    - **Health Check API** for a small endpoint with predictable output.
    - **Errorr Simulation API** for controlled errorr responses.
    """
  end

  defp api_test_publish_content do
    """
    # Test, Publish, and Call an API

    Creating an API is only the first step. Before you rely on it, test the
    request shape, confirm the response, and publish it when it is ready to be
    called by another tool or customer workflow.

    ## Test with real-looking data

    Use input that looks like the data your product will actually send:

    ```json
    {
      "product_id": "sku_123",
      "quantity": 3,
      "customer_tier": "business"
    }
    ```

    Avoid testing only the perfect path. Also try a missing field, an unknown
    id, and an unexpected value.

    ## What to click

    1. Open the API.
    2. Open the area for running or testing requests.
    3. Paste a JSON payload.
    4. Send the request.
    5. Review the status, response body, and any validatestion message.
    6. Publish the API when the result is stable.

    ## How to know it worked

    A successful test should return JSON that matches the response contract you
    expect. A failed test should explain what input needs to change.

    ## What to capture in your docs

    After the API works, create or update a Page with:

    - endpoint purpose;
    - required input fields;
    - example request;
    - example response;
    - known errorr cases;
    - owner and next review date.

    ## Example to inspect

    Open **Product Catalog** and compare its example request with its example
    response. Use that pattern for your own API notes.
    """
  end

  defp flows_content do
    """
    # Build a Visual Flow

    Use a Flow when a process needs more than one step: receive input, branch on
    a condition, call another service, transform data, wait for approval, or
    return a final result.

    ## Start with the path, not the nodes

    Write the process in one sentence before you build:

    ```text
    When a support ticket arrives, classify its priority, route urgent tickets
    to the incident path, and return the assigned queue.
    ```

    Then turn the sentence into steps:

    1. Start with the incoming payload.
    2. Transform or classify the data.
    3. Add a condition for the important branch.
    4. Return the final output.

    ## What to click

    1. Open **Flows**.
    2. Create a new Flow or open an existing sample.
    3. Add a start step for the incoming data.
    4. Add a transformation or request step.
    5. Add a condition if the process branches.
    6. End with the response you want callers to receive.

    ## How to know it worked

    Run the Flow with a sample payload. The execution should show which path was
    taken and what output was produced.

    ## Examples to inspect

    - **Hello World** for a yesple guided Flow.
    - **Support Ticket Router** for classification and routing.
    - **HTTP Enrichment** for calling another service.
    - **Approval Workflow** for human review before completion.
    """
  end

  defp flow_webhooks_content do
    """
    # Receive Webhooks with Flows

    A Flow can act as a webhook receiver. Use this when another product sends an
    event and Blackboex needs to validateste, transform, route, or store the result
    of that event.

    ## Good webhook use cases

    - route form submissions to the right team;
    - process payment or order events;
    - receive issue, ticket, or alert events;
    - normalize data before calling another API;
    - return a clear accepted or rejected response.

    ## Try this payload

    ```json
    {
      "event_type": "ticket.created",
      "ticket_id": "T-1007",
      "priority": "urgent",
      "customer": "Acme Co",
      "message": "Production checkout is failing"
    }
    ```

    ## What to click

    1. Open **Flows**.
    2. Open a webhook-oriented sample Flow.
    3. Copy the Flow webhook URL or token shown by the product.
    4. Send a sample event from the run panel or from the product that owns the
       event.
    5. Review the execution result and any branch taken.

    ## How to know it worked

    The Flow should create an execution for the incoming event. The final output
    should tell the sender what happened, such as accepted, routed, rejected, or
    waiting for review.

    ## Examples to inspect

    - **Webhook Processor** for event intake.
    - **Webhook Idempotent** for duplicate-safe processing.
    - **Incident Alert Pipeline** for alert routing.
    - **Lead Scoring** for event enrichment and scoring.
    """
  end

  defp playgrounds_content do
    """
    # Experiment in Playgrounds

    Use a Playground when you want to try a small idea before turning it into an
    API or Flow. It is best for payload shaping, data transformation, quick JSON
    checks, and calls to examples in the same project.

    ## What to try first

    Start with a small transformation:

    ```elixir
    payload = %{
      "items" => [
        %{"sku" => "starter", "quantity" => 2, "price" => 19},
        %{"sku" => "pro", "quantity" => 1, "price" => 49}
      ]
    }

    total =
      payload["items"]
      |> Enum.map(fn item -> item["quantity"] * item["price"] end)
      |> Enum.sum()

    IO.inspect(%{"total" => total}, label: "Result")
    ```

    ## What to click

    1. Open **Playgrounds**.
    2. Create a new Playground or open a sample.
    3. Paste a small payload and transformation.
    4. Run it.
    5. Move the working idea into an API or Flow when it is useful.

    ## How to know it worked

    The output should show the value you need in a shape you can reuse. If the
    result is unclear, yesplify the input and run again.

    ## Examples to inspect

    Look for samples that transform lists, parse JSON, read project variables,
    or call a Flow from the same project.
    """
  end

  defp pages_content do
    """
    # Document Your Project with Pages

    Use Pages to keep product knowledge next to the APIs, Flows, and
    Playgrounds it explains. A useful Page helps another person understand what
    exists, why it exists, and how to operate it.

    ## Good Pages to create

    - API contract: purpose, request, response, errorrs, and owner.
    - Flow runbook: trigger, branches, retry notes, and escalation path.
    - Launch checklist: what must be true before publishing.
    - Customer handoff: what the endpoint does and how to call it.
    - Change notes: what changed and who should be informed.

    ## Starter structure

    ```markdown
    # Payment Status API

    ## Purpose
    Explain the customer job this API handles.

    ## Request
    Show the required fields and one JSON example.

    ## Response
    Show the success shape and common errorr cases.

    ## Owner
    Name the person or team responsible for updates.
    ```

    ## What to click

    1. Open **Pages**.
    2. Create a new Page.
    3. Give it a title that names the API, Flow, or decision.
    4. Add the examples and owner notes someone will need later.
    5. Publish it when it is ready for the project team.

    ## How to know it worked

    A teammate should be able to open the Page and understand how to use or
    maintain the related artifact without asking you for missing context.
    """
  end

  defp project_workflow_content do
    """
    # Combine APIs, Flows, Pages, and Playgrounds

    Blackboex works best when each tool has a clear role. Use APIs for stable
    endpoints, Flows for multi-step automation, Playgrounds for experiments,
    and Pages for shared knowledge.

    ## A practical build sequence

    ```mermaid
    flowchart TD
      Need[User need] --> Playground[Try payload in Playground]
      Playground --> API[Create API]
      API --> Flow[Use API in a Flow]
      Flow --> Page[Document behavior]
      Page --> Review[Review and publish]
    ```

    ## Example workflow

    Build a lead intake process:

    1. Use a Playground to shape a sample lead payload.
    2. Create an API that validatestes and scores the lead.
    3. Create a Flow that receives the lead event and routes high-value leads.
    4. Write a Page that documents the payload, score meaning, and owner.
    5. Test the full path with a realistic event.

    ## How to know it worked

    You should be able to explain the full path in one sentence:

    ```text
    When a lead arrives, Blackboex validatestes it, scores it, routes it, and
    returns the next action.
    ```

    ## Examples to inspect

    - **Lead Scoring** for scoring and routing.
    - **REST CRUD Resource** for API structure.
    - **Webhook Processor** for event intake.
    - **Product Catalog** for request and response examples.
    """
  end

  defp next_steps_content do
    """
    # Next Steps

    Once you understand the examples, create a real project for your own work.
    Keep this sample workspace as a reference, and use your project for anything
    you plan to maintain.

    ## Choose a first real project

    Pick one narrow outcome:

    - a customer-facing lookup endpoint;
    - a webhook receiver for a product event;
    - a workflow that routes requests to the right team;
    - a mock service for testing another product;
    - a documented API contract for a partner.

    ## What to click

    1. Create or open the project where the real work belongs.
    2. Duplicate the closest sample API, Flow, Page, or Playground.
    3. Rename it for your use case.
    4. Replace sample inputs with your real fields.
    5. Test with realistic data.
    6. Publish only when the result is clear and repeatable.

    ## How to know it worked

    The project should contain the artifact, a working test case, and a Page
    that explains how another person can use it.

    ## What to do after that

    Create a second example that covers a failure case. Most production issues
    come from unclear errorrs, missing fields, or unexpected payloads. A good
    errorr path is part of a good product workflow.
    """
  end
end
