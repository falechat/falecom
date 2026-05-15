module Admin
  class BaseController < ApplicationController
    include RequireAdmin
    layout "application"
  end
end
