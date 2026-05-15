module Flows
  class Validators
    EMAIL = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/
    PHONE = /\A\+?\d{8,}\z/

    def self.call(value, kind)
      value = value.to_s
      case kind
      when "email" then EMAIL.match?(value)
      when "phone" then PHONE.match?(value.gsub(/\s/, ""))
      when "number" then value.match?(/\A-?\d+\z/)
      else true
      end
    end
  end
end
