defmodule MosaicWeb.Router do
  use MosaicWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MosaicWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MosaicWeb do
    pipe_through :browser

    get "/", PageController, :home

    live "/workers", WorkersLive.Index, :index
    live "/workers/new", WorkersLive.Index, :new
    live "/workers/:id/edit", WorkersLive.Index, :edit

    live "/workers/:id", WorkersLive.Show, :show
    live "/workers/:id/show/edit", WorkersLive.Show, :edit
    live "/workers/:id/show/new_employment", WorkersLive.Show, :new_employment

    live "/employments", EmploymentLive.Index, :index

    live "/employments/:id", EmploymentLive.Show, :show
    live "/employments/:id/show/edit", EmploymentLive.Show, :edit
    live "/employments/:id/show/new_shift", EmploymentLive.Show, :new_shift

    live "/shifts", ShiftLive.Index, :index

    live "/shifts/:id", ShiftLive.Show, :show
    live "/shifts/:id/show/edit", ShiftLive.Show, :edit
  end

  # Other scopes may use custom stacks.
  # scope "/api", MosaicWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:mosaic, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MosaicWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
