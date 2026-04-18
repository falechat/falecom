class ApplicationController < ActionController::Base
  include Authentication

  # Only allow modern browsers in non-test environments (test requests don't send a real User-Agent).
  allow_browser versions: :modern unless Rails.env.test?
end
