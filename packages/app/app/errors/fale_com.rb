module FaleCom
  class Error < StandardError; end

  class AuthorizationError < Error; end

  class ValidationError < Error; end
end
