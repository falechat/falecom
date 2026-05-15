module Dashboard
  class ContactsController < ApplicationController
    def index
      @contacts = Contact.order(:name).limit(100)
    end

    def new
      @contact = Contact.new
    end

    def create
      @contact = Contacts::Create.call(
        name: params[:contact][:name],
        phone_number: params[:contact][:phone_number],
        email: params[:contact][:email]
      )
      redirect_to dashboard_contact_path(@contact)
    end

    def show
      @contact = Contact.find(params[:id])
    end

    def update
      @contact = Contact.find(params[:id])
      @contact.update!(params.require(:contact).permit(:name, :phone_number, :email))
      attrs = params[:contact][:additional_attributes]
      if attrs.is_a?(ActionController::Parameters) || attrs.is_a?(Hash)
        Contacts::UpdateAttributes.call(contact: @contact, additional_attributes: attrs.to_unsafe_h.transform_values { |v| v.presence })
      end
      redirect_to dashboard_contact_path(@contact)
    end
  end
end
